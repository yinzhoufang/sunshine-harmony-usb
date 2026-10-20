//! HarmonyOS USB streaming mode. Only the bundled Device Hub may invoke it.
//! Media stays in the proven relay; the GUI owns switching and health reporting.
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::path::PathBuf;
use std::time::Duration;
use tauri::Emitter;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

static SWITCH_LOCK: Lazy<tokio::sync::Mutex<()>> = Lazy::new(|| tokio::sync::Mutex::new(()));
const HELPER_ARG: &str = "--harmony-usb-mode";
const LIMIT: usize = 64 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Request {
    enabled: bool,
    device_id: String,
}

fn validate_device_id(value: &str) -> Result<(), String> {
    if value.len() <= 128 && !value.starts_with('-')
        && value.bytes().all(|c| c.is_ascii_alphanumeric() || b"_.:-".contains(&c))
    {
        Ok(())
    } else {
        Err("USB_INVALID_DEVICE".into())
    }
}

fn resource_dir() -> Result<PathBuf, String> {
    let installed = crate::sunshine::install_dir().join("tools/harmony-usb");
    if installed.join("transport_mode.ps1").is_file() {
        return Ok(installed);
    }
    let adjacent = std::env::current_exe().map_err(|e| e.to_string())?
        .parent().ok_or("USB_RESOURCES_MISSING")?.join("harmony-usb");
    if adjacent.join("transport_mode.ps1").is_file() {
        return Ok(adjacent);
    }
    #[cfg(debug_assertions)]
    {
        return Ok(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources/harmony-usb"));
    }
    #[cfg(not(debug_assertions))]
    Err("USB_RESOURCES_MISSING".into())
}

#[cfg(target_os = "windows")]
async fn run_script(
    action: &str,
    device_id: &str,
    mut progress: impl FnMut(&Value),
) -> Result<Value, String> {
    use std::process::Stdio;
    use tokio::io::AsyncReadExt;
    validate_device_id(device_id)?;
    let resources = resource_dir()?;
    let script = resources.join(match action {
        "Usb" => "usb_mode.ps1",
        "Lan" => "lan_mode.ps1",
        "Status" => "transport_mode.ps1",
        _ => return Err("USB_INVALID_ACTION".into()),
    });
    let powershell = crate::elevation::system_binary("WindowsPowerShell/v1.0/powershell.exe");
    let mut command = tokio::process::Command::new(powershell);
    command.args(["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"])
        .arg(script).arg("-SunshineRoot").arg(crate::sunshine::install_dir());
    if action == "Status" { command.args(["-Action", "Status"]); }
    if !device_id.is_empty() { command.arg("-DeviceId").arg(device_id); }
    command.creation_flags(0x08000000).stdin(Stdio::null())
        .stdout(Stdio::piped()).stderr(Stdio::piped()).kill_on_drop(true);
    let mut child = command.spawn().map_err(|e| format!("USB_SCRIPT_START: {e}"))?;
    let stderr = child.stderr.take().ok_or("USB_SCRIPT_STDERR")?;
    let stderr_task = tokio::spawn(async move {
        let mut bytes = Vec::new();
        let _ = stderr.take(LIMIT as u64).read_to_end(&mut bytes).await;
        String::from_utf8_lossy(&bytes).to_string()
    });
    let stdout = child.stdout.take().ok_or("USB_SCRIPT_STDOUT")?;
    let mut reader = BufReader::new(stdout);
    let mut result = None;
    let operation = async {
        loop {
            let mut line = Vec::new();
            let length = (&mut reader).take((LIMIT + 1) as u64).read_until(b'\n', &mut line)
                .await.map_err(|e| format!("USB_SCRIPT_READ: {e}"))?;
            if length == 0 { break; }
            if length > LIMIT { return Err("USB_SCRIPT_RESPONSE_TOO_LARGE".into()); }
            let Ok(message) = serde_json::from_slice::<Value>(&line) else { continue; };
            match message["event"].as_str() {
                Some("progress") => progress(&message),
                Some("result") => result = Some(message),
                _ => {}
            }
        }
        let status = child.wait().await.map_err(|e| e.to_string())?;
        let result = result.ok_or("USB_SCRIPT_NO_RESULT")?;
        if result["success"] == true && status.success() { Ok(result) }
        else { Err(result["message"].as_str().unwrap_or("USB_SWITCH_FAILED").to_string()) }
    };
    let timeout = if action == "Status" { 20 } else { 180 };
    let outcome = tokio::time::timeout(Duration::from_secs(timeout), operation).await;
    if !matches!(&outcome, Ok(Ok(_))) {
        let _ = child.kill().await;
    }
    if outcome.is_err() {
        stderr_task.abort();
        return Err("USB_SWITCH_TIMEOUT".into());
    }
    let details = stderr_task.await.unwrap_or_default();
    outcome.map_err(|_| "USB_SWITCH_TIMEOUT".to_string())?.map_err(|message| {
        if details.trim().is_empty() { message }
        else { format!("{message}: {}", details.trim().chars().take(4000).collect::<String>()) }
    })
}

#[cfg(not(target_os = "windows"))]
async fn run_script(_: &str, _: &str, _: impl FnMut(&Value)) -> Result<Value, String> {
    Err("USB_WINDOWS_ONLY".into())
}

#[tauri::command]
pub async fn harmony_usb_get_status() -> Result<Value, String> {
    let result = run_script("Status", "", |_| {}).await?;
    Ok(result["status"].clone())
}

#[tauri::command]
pub async fn harmony_usb_set_mode(
    app: tauri::AppHandle,
    enabled: bool,
    device_id: Option<String>,
) -> Result<Value, String> {
    let _lock = SWITCH_LOCK.try_lock().map_err(|_| "SWITCH_BUSY".to_string())?;
    let request = Request { enabled, device_id: device_id.unwrap_or_default() };
    validate_device_id(&request.device_id)?;
    let _ = app.emit("harmony-usb-progress", json!({"stage":"authorizing","progress":2}));
    #[cfg(target_os = "windows")]
    let switched = if crate::elevation::is_elevated() {
        run_script(if request.enabled { "Usb" } else { "Lan" }, &request.device_id, |value| {
            let _ = app.emit("harmony-usb-progress", value);
        }).await.map(|_| ())
    } else {
        run_elevated(&app, &request).await
    };
    #[cfg(not(target_os = "windows"))]
    let switched: Result<(), String> = Err("USB_WINDOWS_ONLY".into());

    // A switch or its rollback can change the Web UI port. Refresh the GUI
    // proxy even on failure, so the user can still use the control panel.
    if let Ok(url) = crate::sunshine::get_local_sunshine_url().await {
        let _ = crate::sunshine::set_runtime_sunshine_url(&url);
        let _ = crate::proxy_server::refresh_sunshine_target().await;
    }
    switched?;
    harmony_usb_get_status().await
}

#[cfg(target_os = "windows")]
async fn run_elevated(app: &tauri::AppHandle, request: &Request) -> Result<(), String> {
    use tokio::io::AsyncReadExt;
    let token = uuid::Uuid::new_v4();
    let mut server = crate::elevation::create_hardened_pipe(
        &crate::elevation::pipe_name("harmony-usb", token), "USB_UAC_FAILED")?;
    let process = crate::elevation::spawn_helper(vec![HELPER_ARG.into(), token.to_string(),
        serde_json::to_string(request).map_err(|e| e.to_string())?], "USB_UAC_CANCELLED").await?;
    crate::elevation::connect_verified(&mut server, &process, Duration::from_secs(45), "USB_UAC_FAILED").await?;
    let mut reader = BufReader::new(server);
    let operation = async {
        loop {
            let mut line = Vec::new();
            let length = (&mut reader).take((LIMIT + 1) as u64).read_until(b'\n', &mut line)
                .await.map_err(|e| format!("USB_IPC_FAILED: {e}"))?;
            if length == 0 { return Err("USB_HELPER_EXITED".to_string()); }
            if length > LIMIT { return Err("USB_IPC_RESPONSE_TOO_LARGE".into()); }
            let message: Value = serde_json::from_slice(&line).map_err(|e| e.to_string())?;
            if message["event"] == "progress" {
                let _ = app.emit("harmony-usb-progress", &message);
            } else if message["event"] == "result" {
                if message["success"] != true {
                    return Err(message["message"].as_str().unwrap_or("USB_SWITCH_FAILED").to_string());
                }
                let exit = crate::elevation::wait_for_exit(&process, Duration::from_secs(5)).await?;
                return if exit == Some(0) { Ok(()) } else { Err("USB_HELPER_EXIT_FAILED".into()) };
            }
        }
    };
    tokio::time::timeout(Duration::from_secs(200), operation).await
        .map_err(|_| "USB_SWITCH_TIMEOUT".to_string())?
}

#[cfg(target_os = "windows")]
async fn run_helper(token: uuid::Uuid, request: Request) -> i32 {
    let mut client = match crate::elevation::connect_helper_pipe(
        &crate::elevation::pipe_name("harmony-usb", token), "USB_IPC_FAILED").await {
        Ok(client) => client,
        Err(_) => return 3,
    };
    if !crate::elevation::is_elevated() { return 2; }
    // Do not bind this helper to the installer lifetime job: the media relay
    // deliberately survives both the switch helper and the control panel.
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Value>();
    let writer = tokio::spawn(async move {
        while let Some(message) = rx.recv().await {
            let encoded = serde_json::to_vec(&message).map_err(|e| e.to_string())?;
            client.write_all(&encoded).await.map_err(|e| e.to_string())?;
            client.write_all(b"\n").await.map_err(|e| e.to_string())?;
        }
        Ok::<(), String>(())
    });
    let result = run_script(if request.enabled { "Usb" } else { "Lan" }, &request.device_id, |value| {
        let _ = tx.send(value.clone());
    }).await;
    let succeeded = result.is_ok();
    let message = match result {
        Ok(_) => json!({"event":"result","success":true}),
        Err(error) => json!({"event":"result","success":false,"message":error}),
    };
    let _ = tx.send(message);
    drop(tx);
    let _ = writer.await;
    if succeeded { 0 } else { 1 }
}

#[cfg(target_os = "windows")]
pub(crate) fn try_handle_elevated_command() -> Option<i32> {
    let mut args = std::env::args().skip(1);
    if args.next()?.as_str() != HELPER_ARG { return None; }
    let token = match args.next().and_then(|s| uuid::Uuid::parse_str(&s).ok()) {
        Some(token) => token, None => return Some(2),
    };
    let request = match args.next().and_then(|s| serde_json::from_str::<Request>(&s).ok()) {
        Some(value) if args.next().is_none() && validate_device_id(&value.device_id).is_ok() => value,
        _ => return Some(2),
    };
    let runtime = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
        Ok(runtime) => runtime, Err(_) => return Some(3),
    };
    Some(runtime.block_on(run_helper(token, request)))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_device_ids_that_could_be_interpreted_as_commands() {
        for id in ["device; Stop-Service SunshineService", "--help", "x\ny", "x\"y", "x y"] {
            assert!(validate_device_id(id).is_err());
        }
        assert!(validate_device_id("3KQYD24B16200457").is_ok());
        assert!(validate_device_id("127.0.0.1:8710").is_ok());
    }
}
