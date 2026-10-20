param(
    [ValidateSet('Status','Usb','Lan')][string]$Action = 'Status',
    [string]$SunshineRoot = 'C:\Program Files\Sunshine',
    [string]$DeviceId = '',
    [string]$DataRoot = (Join-Path $env:ProgramData 'Sunshine\harmony-usb'),
    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'
$script:Maps = @(@(48010,49010),@(47989,48989),@(47984,48984),@(47997,47997),@(47996,47996),@(48984,48984),@(48989,48989))
$script:ConfigPath = Join-Path $SunshineRoot 'config\sunshine.conf'
$script:StatePath = Join-Path $DataRoot 'transport-state.json'
$script:RelayPath = Join-Path $PSScriptRoot 'relay.py'
$script:Hdc = $null

function Write-ProgressEvent([string]$Stage, [int]$Percent) {
    @{ event='progress'; stage=$Stage; progress=$Percent } | ConvertTo-Json -Compress | Write-Output
}
function Read-Port([string]$Text) {
    $matches = [regex]::Matches($Text, '(?m)^\s*port\s*=\s*(\d+)\s*(?:#.*)?$')
    if ($matches.Count -eq 0) { return 47989 }
    return [int]$matches[$matches.Count-1].Groups[1].Value
}
function Read-ModeState {
    if (Test-Path -LiteralPath $script:StatePath) {
        return ([IO.File]::ReadAllText($script:StatePath) | ConvertFrom-Json)
    }
    return $null
}
function Write-ModeState($State) {
    [IO.Directory]::CreateDirectory($DataRoot) | Out-Null
    $temporary = $script:StatePath + '.tmp'
    [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $script:StatePath -Force
}
function Resolve-Hdc {
    $candidates = @()
    $command = Get-Command hdc.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    $candidates += @('C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
        (Join-Path $SunshineRoot 'tools\harmony-usb\hdc.exe'))
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}
function Invoke-Hdc([string[]]$Arguments, [switch]$AllowFailure) {
    if (!$script:Hdc) { throw 'HDC_MISSING' }
    $result = (& $script:Hdc @Arguments 2>&1 | Out-String).Trim()
    if (!$AllowFailure -and ($LASTEXITCODE -ne 0 -or $result -match '(?i)\b(fail(?:ed)?|error|not found|unauthorized)\b')) {
        throw ('HDC_FAILED: ' + $result)
    }
    return $result
}
function Get-Targets {
    if (!$script:Hdc) { return @() }
    $text = Invoke-Hdc @('list','targets') -AllowFailure
    return @($text -split '\r?\n' | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^[A-Za-z0-9_.:-]+$' -and $_ -notmatch '^(Empty|List|targets)$' })
}
function Get-Listeners {
    $rows = @{ connected=@() }
    foreach ($line in (& "$env:SystemRoot\System32\netstat.exe" -ano -p TCP)) {
        if ($line -match '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$') {
            $rows[[int]$Matches[1]] = [int]$Matches[2]
        } elseif ($line -match '^\s*TCP\s+\S+:(47997|47996)\s+\S+\s+ESTABLISHED\s+\d+\s*$') {
            $rows.connected += [int]$Matches[1]
        }
    }
    return $rows
}
function Get-TransportStatus {
    $saved = Read-ModeState
    $port = Read-Port ([IO.File]::ReadAllText($script:ConfigPath))
    $targets = @(Get-Targets)
    $selected = $DeviceId
    if (!$selected -and $saved) { $selected = [string]$saved.device_id }
    if (!$selected -and $targets.Count -eq 1) { $selected = $targets[0] }
    $enabled = $port -eq 48989
    if ($saved -and $saved.mode -eq 'lan') { $enabled = $false }
    if ($saved -and $saved.mode -eq 'usb') { $enabled = $true }
    $listeners = Get-Listeners
    $service = Get-Service SunshineService -ErrorAction SilentlyContinue
    $connected = $selected -and ($targets -contains $selected)
    $mapped = 0
    if ($enabled -and $connected) {
        $rules = Invoke-Hdc @('-t',$selected,'fport','ls') -AllowFailure
        foreach ($map in $script:Maps) {
            if ($rules -match ('tcp:' + $map[0] + '\s+tcp:' + $map[1] + '\s+\[Reverse\]')) { $mapped++ }
        }
    }
    $relayReady = $listeners.ContainsKey(47997) -and $listeners.ContainsKey(47996)
    $tunnelsReady = $listeners.connected -contains 47997 -and $listeners.connected -contains 47996
    $serverReady = $service -and $service.Status -eq 'Running' -and $listeners.ContainsKey($port) -and $listeners.ContainsKey($port+21)
    return @{
        enabled=[bool]$enabled; healthy=[bool]($serverReady -and (!$enabled -or ($port -eq 48989 -and $connected -and $mapped -eq 7 -and $relayReady -and $tunnelsReady)))
        hdc_available=[bool]$script:Hdc; devices=@($targets); device_id=[string]$selected
        device_connected=[bool]$connected; mappings=$mapped; relay_ready=[bool]$relayReady; tunnels_connected=[bool]$tunnelsReady
        server_ready=[bool]$serverReady; port=$port; log_path=(Join-Path $DataRoot 'relay_run.log')
    }
}
function Wait-ServiceState([string]$Expected) {
    for ($i=0; $i -lt 60; $i++) {
        if ((Get-Service SunshineService).Status.ToString() -eq $Expected) { return }
        Start-Sleep -Milliseconds 500
    }
    throw ('SERVICE_TIMEOUT: ' + $Expected)
}
function Stop-Host {
    Stop-Service SunshineService -Force
    Wait-ServiceState 'Stopped'
}
function Set-HostPort([int]$Port) {
    if ((Get-Service SunshineService).Status -ne 'Stopped') { throw 'SERVICE_NOT_STOPPED' }
    # Read AFTER stop: Sunshine persists its live settings during shutdown.
    $text = [IO.File]::ReadAllText($script:ConfigPath)
    $kept = [regex]::Replace($text, '(?m)^\s*port\s*=[^\r\n]*(?:\r?\n|$)', '')
    $updated = $kept.TrimEnd("`r","`n") + "`r`nport = $Port`r`n"
    [IO.File]::WriteAllText($script:ConfigPath, $updated, (New-Object Text.UTF8Encoding($false)))
}
function Start-Host([int]$Port) {
    Start-Service SunshineService
    Wait-ServiceState 'Running'
    for ($i=0; $i -lt 60; $i++) {
        $listeners = Get-Listeners
        if ($listeners.ContainsKey($Port) -and $listeners.ContainsKey($Port-5) -and $listeners.ContainsKey($Port+21)) { return }
        Start-Sleep -Milliseconds 500
    }
    throw 'SUNSHINE_PORTS_NOT_READY'
}
function Resolve-Python {
    $candidates = @()
    $command = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    if ($env:LOCALAPPDATA) {
        $pythonRoot = Join-Path $env:LOCALAPPDATA 'Programs\Python'
        if (Test-Path -LiteralPath $pythonRoot) {
            $candidates += @(Get-ChildItem -LiteralPath $pythonRoot -Filter python.exe -Recurse -File | ForEach-Object FullName)
        }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -match '\\WindowsApps\\') { continue }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'PYTHON_MISSING'
}
function Test-SunshineAutoTunnelOwner($Process, [int[]]$Ports) {
    # The host's built-in remote-USB tunnel uses base+7 (47996 in LAN mode).
    # It is released by Stop-Host before the relay starts. Never terminate it
    # as a relay, and do not mistake an unrelated same-named process for it.
    if ($Process.Name -ine 'Sunshine.exe' -or $Ports.Count -ne 1) { return $false }
    $hostPort = Read-Port ([IO.File]::ReadAllText($script:ConfigPath))
    if ($Ports[0] -ne ($hostPort + 7)) { return $false }
    $service = Get-CimInstance Win32_Service -Filter "Name='SunshineService'"
    if (!$service -or !$service.ProcessId -or $Process.ParentProcessId -ne $service.ProcessId) { return $false }
    if ($Process.ExecutablePath -and $Process.ExecutablePath -ine (Join-Path $SunshineRoot 'Sunshine.exe')) { return $false }
    return $true
}
function Get-ManagedRelayOwners {
    $listeners = Get-Listeners
    $owners = @(@(47997,47996) | Where-Object { $listeners.ContainsKey($_) } | ForEach-Object { $listeners[$_] } | Select-Object -Unique)
    foreach ($ownerId in $owners) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ownerId"
        $ownedPorts = @(@(47997,47996) | Where-Object { $listeners.ContainsKey($_) -and $listeners[$_] -eq $ownerId })
        if (Test-SunshineAutoTunnelOwner $process $ownedPorts) { continue }
        $line = [string]$process.CommandLine
        # Adopt only the production dual-tunnel relay. Never stop other Python jobs.
        if ($process.Name -notmatch '^python(?:w)?\.exe$' -or $line -notmatch '(?:^|[\s"\\])relay\.py(?:["\s]|$)' -or $line -notmatch '--control-port\s+47996(?:\s|$)') {
            throw ('RELAY_PORT_CONFLICT: ' + $ownerId)
        }
        Write-Output $ownerId
    }
}
function Stop-ManagedRelay {
    foreach ($ownerId in @(Get-ManagedRelayOwners)) { Stop-Process -Id $ownerId -Force }
    for ($i=0; $i -lt 20; $i++) {
        $listeners = Get-Listeners
        if (!$listeners.ContainsKey(47997) -and !$listeners.ContainsKey(47996)) { return }
        Start-Sleep -Milliseconds 250
    }
    throw 'RELAY_PORTS_BUSY'
}
function Start-ManagedRelay([string]$Python) {
    [IO.Directory]::CreateDirectory($DataRoot) | Out-Null
    $process = Start-Process -FilePath $Python -ArgumentList @('-X','utf8',('"'+$script:RelayPath+'"'),'--control-port','47996','--hi-res-timer','--stats-every','2','--hdc',('"'+$script:Hdc+'"'),'--transport-state',('"'+$script:StatePath+'"')) `
        -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $DataRoot 'relay_run.log') -RedirectStandardError (Join-Path $DataRoot 'relay_run.err')
    for ($i=0; $i -lt 30; $i++) {
        $process.Refresh()
        if ($process.HasExited) { throw ('RELAY_START_FAILED: ' + $process.ExitCode) }
        $listeners = Get-Listeners
        if ($listeners.ContainsKey(47997) -and $listeners.ContainsKey(47996) -and $listeners[47997] -eq $process.Id -and $listeners[47996] -eq $process.Id) { return }
        Start-Sleep -Milliseconds 250
    }
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw 'RELAY_START_TIMEOUT'
}
function Add-UsbMappings([string]$Target) {
    foreach ($map in $script:Maps) {
        Invoke-Hdc @('-t',$Target,'fport','rm',('tcp:'+$map[0]),('tcp:'+$map[1])) -AllowFailure | Out-Null
        Invoke-Hdc @('-t',$Target,'rport',('tcp:'+$map[0]),('tcp:'+$map[1])) | Out-Null
    }
    $rules = Invoke-Hdc @('-t',$Target,'fport','ls')
    foreach ($map in $script:Maps) {
        if ($rules -notmatch ('tcp:' + $map[0] + '\s+tcp:' + $map[1] + '\s+\[Reverse\]')) { throw 'HDC_MAPPING_INCOMPLETE' }
    }
}
function Remove-UsbMappings([string]$Target) {
    if (!$script:Hdc -or !$Target) { return }
    foreach ($map in $script:Maps) {
        Invoke-Hdc @('-t',$Target,'fport','rm',('tcp:'+$map[0]),('tcp:'+$map[1])) -AllowFailure | Out-Null
    }
}
function Switch-Transport([bool]$Usb) {
    Write-ProgressEvent 'checking' 8
    $oldState = Read-ModeState
    $oldPort = Read-Port ([IO.File]::ReadAllText($script:ConfigPath))
    $lanPort = 47989
    if ($oldState -and $oldState.lan_port) { $lanPort = [int]$oldState.lan_port }
    elseif ($oldPort -ne 48989) { $lanPort = $oldPort }
    $target = $DeviceId
    $previousTarget = ''
    if ($oldState) { $previousTarget = [string]$oldState.device_id }
    $python = $null
    if ($Usb) {
        if (!$script:Hdc) { throw 'HDC_MISSING' }
        $targets = @(Get-Targets)
        if ($targets.Count -eq 0) { throw 'USB_NO_DEVICE' }
        if (!$target -and $targets.Count -eq 1) { $target = $targets[0] }
        if (!$target -and $targets.Count -gt 1) { throw 'USB_SELECT_DEVICE' }
        if ($targets -notcontains $target) { throw 'USB_DEVICE_OFFLINE' }
        $bundle = Invoke-Hdc @('-t',$target,'shell','bm dump -n com.chenfang.usbtunnel') -AllowFailure
        if ($bundle -notmatch '"bundleName"\s*:\s*"com\.chenfang\.usbtunnel"') { throw 'BRIDGE_MISSING' }
        if (!(Test-Path -LiteralPath $script:RelayPath)) { throw 'RELAY_MISSING' }
        $python = Resolve-Python
    } elseif (!$target -and $oldState) { $target = [string]$oldState.device_id }
    if (!$target -and $script:Hdc) {
        $targets = @(Get-Targets)
        if ($targets.Count -eq 1) { $target = $targets[0] }
    }
    if (!$previousTarget) { $previousTarget = $target }
    Get-ManagedRelayOwners | Out-Null
    $mutationStarted = $false
    try {
        Write-ProgressEvent 'stopping' 20
        Stop-Host
        $mutationStarted = $true
        # Release 47998/47999/48000 BEFORE bringing the LAN Sunshine ports up.
        Stop-ManagedRelay
        Write-ProgressEvent 'configuring' 35
        $port = $lanPort
        if ($Usb) { $port = 48989 }
        Set-HostPort $port
        Write-ProgressEvent 'starting' 50
        Start-Host $port
        if ($Usb) {
            Write-ProgressEvent 'mapping' 70
            if ($previousTarget -and $previousTarget -ne $target) { Remove-UsbMappings $previousTarget }
            Add-UsbMappings $target
            Write-ProgressEvent 'relay' 85
            Start-ManagedRelay $python
            Invoke-Hdc @('-t',$target,'shell','aa start -a EntryAbility -b com.chenfang.usbtunnel') | Out-Null
        } else {
            Remove-UsbMappings $previousTarget
            if ($target -ne $previousTarget) { Remove-UsbMappings $target }
        }
        $mode = 'lan'
        if ($Usb) { $mode = 'usb' }
        Write-ModeState @{mode=$mode;lan_port=$lanPort;device_id=$target}
        Write-ProgressEvent 'ready' 100
    } catch {
        $cause = $_.Exception.Message
        if (!$mutationStarted) { throw }
        Write-ProgressEvent 'rollback' 20
        try {
            Stop-Host
            Stop-ManagedRelay
            Set-HostPort $oldPort
            Start-Host $oldPort
            if ($oldPort -eq 48989) {
                if (!$python) { $python = Resolve-Python }
                if ($target -ne $previousTarget) { Remove-UsbMappings $target }
                if ($previousTarget -and $script:Hdc) { Add-UsbMappings $previousTarget }
                Start-ManagedRelay $python
            } else { Remove-UsbMappings $target }
            if ($oldState) { Write-ModeState $oldState }
            else { Write-ModeState @{mode=$(if($oldPort -eq 48989){'usb'}else{'lan'});lan_port=$lanPort;device_id=$target} }
        } catch { throw ('ROLLBACK_FAILED: ' + $cause + ' / ' + $_.Exception.Message) }
        throw ('SWITCH_ROLLED_BACK: ' + $cause)
    }
}

if (!$NoRun) {
    try {
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        $script:Hdc = Resolve-Hdc
        if ($Action -eq 'Status') {
            @{event='result';success=$true;status=(Get-TransportStatus)} | ConvertTo-Json -Depth 6 -Compress
        } else {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            if (!(New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'ADMIN_REQUIRED' }
            $lock = New-Object Threading.Mutex($false, 'Global\SunshineHarmonyUsbMode')
            $held = $false
            try {
                $held = $lock.WaitOne(0)
                if (!$held) { throw 'SWITCH_BUSY' }
                Switch-Transport ($Action -eq 'Usb')
                @{event='result';success=$true} | ConvertTo-Json -Compress
            } finally {
                if ($held) { $lock.ReleaseMutex() }
                $lock.Dispose()
            }
        }
    } catch {
        @{event='result';success=$false;message=$_.Exception.Message} | ConvertTo-Json -Compress
        exit 1
    }
    exit 0
}
