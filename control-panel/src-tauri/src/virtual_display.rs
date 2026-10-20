//! Manual display power uses the Core's existing VDD lifecycle and confirmation.
use crate::sunshine::{self, TrayActionResponse, TrayState};
use tokio::sync::Mutex;

static POWER_LOCK: Mutex<()> = Mutex::const_new(());

#[derive(Debug, PartialEq)]
enum PowerPlan {
    Unchanged,
    Create,
    Close { clear_keep_enabled: bool },
}

fn power_plan(state: &TrayState, enabled: bool, allow_interrupt: bool) -> Result<PowerPlan, String> {
    if state.vdd.awaiting_confirmation || state.vdd.cooldown {
        return Err("VDD_POWER_BUSY".into());
    }
    if state.vdd.active == enabled {
        return Ok(PowerPlan::Unchanged);
    }
    if !enabled && !allow_interrupt && (state.status == "streaming" || !state.sessions.is_empty()) {
        return Err("VDD_STREAMING_CONFIRM_REQUIRED".into());
    }
    Ok(if enabled {
        PowerPlan::Create
    } else {
        PowerPlan::Close { clear_keep_enabled: state.vdd.keep_enabled }
    })
}

#[tauri::command]
pub async fn get_virtual_display_power() -> Result<TrayState, String> {
    sunshine::get_tray_state().await
}

fn require_success(response: TrayActionResponse) -> Result<TrayActionResponse, String> {
    if response.status {
        Ok(response)
    } else {
        Err(if response.error.is_empty() { "VDD_POWER_REJECTED".into() } else { response.error })
    }
}

#[tauri::command]
pub async fn set_virtual_display_power(enabled: bool, allow_interrupt: bool) -> Result<TrayActionResponse, String> {
    let _guard = POWER_LOCK.try_lock().map_err(|_| "VDD_POWER_BUSY".to_string())?;
    let state = sunshine::get_tray_state().await?;
    let plan = power_plan(&state, enabled, allow_interrupt)?;
    let action = match plan {
        PowerPlan::Unchanged => return Ok(TrayActionResponse {
            status: true, tray_state: Some(state), ..Default::default()
        }),
        PowerPlan::Create => "vdd_create",
        PowerPlan::Close { clear_keep_enabled } => {
            // Closing explicitly also removes the Core policy that forbids closing.
            // Do not alter this policy merely by opening or refreshing the page.
            if clear_keep_enabled {
                require_success(sunshine::post_tray_action("vdd_toggle_keep_enabled", Some(false)).await?)?;
            }
            "vdd_destroy"
        }
    };
    require_success(sunshine::post_tray_action(action, None).await?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_is_idempotent_and_does_not_flip_newer_state() {
        let mut state = TrayState::default();
        state.vdd.active = true;
        assert_eq!(power_plan(&state, true, false).unwrap(), PowerPlan::Unchanged);
    }

    #[test]
    fn close_requires_confirmation_for_a_live_or_newly_started_stream() {
        let mut state = TrayState::default();
        state.vdd.active = true;
        state.status = "streaming".into();
        assert_eq!(power_plan(&state, false, false).unwrap_err(), "VDD_STREAMING_CONFIRM_REQUIRED");
        assert!(matches!(power_plan(&state, false, true), Ok(PowerPlan::Close { .. })));
    }

    #[test]
    fn explicit_close_clears_the_keep_policy_only_when_needed() {
        let mut state = TrayState::default();
        state.vdd.active = true;
        state.vdd.keep_enabled = true;
        assert_eq!(power_plan(&state, false, false).unwrap(), PowerPlan::Close { clear_keep_enabled: true });
        state.vdd.active = false;
        assert_eq!(power_plan(&state, false, false).unwrap(), PowerPlan::Unchanged);
    }

    #[test]
    fn pending_confirmation_and_cooldown_prevent_another_action() {
        let mut state = TrayState::default();
        state.vdd.awaiting_confirmation = true;
        assert!(power_plan(&state, true, false).is_err());
        state.vdd.awaiting_confirmation = false;
        state.vdd.cooldown = true;
        assert!(power_plan(&state, true, false).is_err());
    }
}
