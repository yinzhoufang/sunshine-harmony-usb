$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot ('../build/harmony-usb-tests/' + [guid]::NewGuid())
$sunshine = Join-Path $root 'sunshine'
$data = Join-Path $root 'state'
New-Item -ItemType Directory -Path (Join-Path $sunshine 'config') -Force | Out-Null
. (Join-Path $PSScriptRoot '../src-tauri/resources/harmony-usb/transport_mode.ps1') -NoRun -SunshineRoot $sunshine -DataRoot $data
$script:Hdc = 'fake-hdc.exe'
$script:Events = [Collections.Generic.List[string]]::new()
$script:MockService = 'Running'
$script:Targets = @('test-tablet')
$script:FailMaps = $false
$script:ForeignOwner = $false

function Assert($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
function Get-Service { param($Name) return [pscustomobject]@{Status=$script:MockService} }
function Stop-Host { $script:Events.Add('stop-host'); $script:MockService='Stopped' }
function Start-Host([int]$Port) { $script:Events.Add("start-host:$Port"); $script:MockService='Running' }
function Get-ManagedRelayOwners { if ($script:ForeignOwner) { throw 'RELAY_PORT_CONFLICT: 99' } }
function Stop-ManagedRelay { $script:Events.Add('stop-relay') }
function Start-ManagedRelay([string]$Python) { $script:Events.Add('start-relay') }
function Get-Targets { return $script:Targets }
function Resolve-Python { return 'python.exe' }
function Invoke-Hdc { param($Arguments,[switch]$AllowFailure) return '{"bundleName":"com.chenfang.usbtunnel"}' }
function Add-UsbMappings([string]$Target) {
    $script:Events.Add('add-maps')
    if ($script:FailMaps) { $script:FailMaps=$false; throw 'HDC_MAPPING_INCOMPLETE' }
}
function Remove-UsbMappings([string]$Target) { $script:Events.Add('remove-maps') }

$original = "# keep user settings`r`nnvenc_preset = 2`r`nsunshine_name = 平板测试`r`nport = 47989`r`n"
[IO.File]::WriteAllText($script:ConfigPath, $original, [Text.UTF8Encoding]::new($false))
Assert ((Read-Port '# port = 48989') -eq 47989) 'Comment was interpreted as a port'
Assert ((Read-Port "port=47989`nport=48989 # chosen") -eq 48989) 'Last active port was not used'
Switch-Transport $true | Out-Null
$text = [IO.File]::ReadAllText($script:ConfigPath)
Assert ((Read-Port $text) -eq 48989) 'USB port was not applied'
Assert ($text.Contains('nvenc_preset = 2') -and $text.Contains('平板测试')) 'Unrelated/Unicode settings were damaged'
Assert ((Read-ModeState).mode -eq 'usb') 'USB success was not persisted'

$script:Events.Clear()
Switch-Transport $false | Out-Null
Assert ($script:Events.IndexOf('stop-relay') -lt $script:Events.IndexOf('start-host:47989')) 'Relay must release UDP ports BEFORE starting LAN Sunshine'
Assert ((Read-Port ([IO.File]::ReadAllText($script:ConfigPath))) -eq 47989) 'LAN port was not restored'

$script:Events.Clear()
$script:Targets=@()
$before=[IO.File]::ReadAllText($script:ConfigPath)
try { Switch-Transport $true | Out-Null; throw 'Expected USB_NO_DEVICE' } catch { Assert ($_.Exception.Message -eq 'USB_NO_DEVICE') 'Wrong missing-tablet error' }
Assert ($script:Events.Count -eq 0) 'Missing tablet must not stop Sunshine'
Assert ([IO.File]::ReadAllText($script:ConfigPath) -eq $before) 'Missing tablet mutated config'

$script:Targets=@('test-tablet')
$script:FailMaps=$true
try { Switch-Transport $true | Out-Null; throw 'Expected rollback' } catch { Assert ($_.Exception.Message.StartsWith('SWITCH_ROLLED_BACK:')) 'USB failure did not roll back' }
Assert ((Read-Port ([IO.File]::ReadAllText($script:ConfigPath))) -eq 47989) 'Rollback did not restore port'
Assert ($script:MockService -eq 'Running' -and (Read-ModeState).mode -eq 'lan') 'Rollback left the service or state incorrect'

$script:Events.Clear()
$script:ForeignOwner=$true
try { Switch-Transport $true | Out-Null; throw 'Expected port conflict' } catch { Assert ($_.Exception.Message.StartsWith('RELAY_PORT_CONFLICT:')) 'Wrong foreign owner error' }
Assert ($script:Events.Count -eq 0) 'Foreign relay conflict must be detected BEFORE stopping Sunshine'

$script:ForeignOwner=$false
$script:MockService='Running'
try { Set-HostPort 48989; throw 'Expected stopped-service guard' } catch { Assert ($_.Exception.Message -eq 'SERVICE_NOT_STOPPED') 'Live config write was allowed' }
Write-Output 'PASS: config preservation, LAN ordering, missing device, rollback, foreign process ownership, stopped-service guard.'
