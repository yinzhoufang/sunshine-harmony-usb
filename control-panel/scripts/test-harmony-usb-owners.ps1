$ErrorActionPreference='Stop'
$fixtureRoot=Join-Path $PSScriptRoot ('../build/harmony-owner-tests/'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'config')) | Out-Null
. (Join-Path $PSScriptRoot '../src-tauri/resources/harmony-usb/transport_mode.ps1') -NoRun -SunshineRoot $fixtureRoot
[IO.File]::WriteAllText($script:ConfigPath,'port = 47989')
$script:OwnerPort=47996
$script:Owner=[pscustomobject]@{ProcessId=123;Name='Sunshine.exe';ParentProcessId=987;ExecutablePath=(Join-Path $fixtureRoot 'Sunshine.exe');CommandLine=''}
function Get-Listeners { $table=@{}; $table[$script:OwnerPort]=123; return $table }
function Get-CimInstance { param($ClassName,$Filter)
    if($ClassName -eq 'Win32_Service') { return [pscustomobject]@{ProcessId=987} }
    return $script:Owner
}
function Assert($value,[string]$message) { if(!$value){throw $message} }
function Assert-Conflict {
    try { Get-ManagedRelayOwners | Out-Null; throw 'Expected conflict' }
    catch { Assert ($_.Exception.Message -like 'RELAY_PORT_CONFLICT:*') 'Wrong conflict result' }
}
Assert (@(Get-ManagedRelayOwners).Count -eq 0) 'LAN Sunshine tunnel was classified as relay/conflict'
$script:Owner.ParentProcessId=555
Assert-Conflict
$script:Owner.ParentProcessId=987
$script:Owner.ExecutablePath=Join-Path $fixtureRoot 'unrelated\Sunshine.exe'
Assert-Conflict
$script:Owner.ExecutablePath=Join-Path $fixtureRoot 'Sunshine.exe'
$script:OwnerPort=47997
Assert-Conflict
$script:Owner.Name='python.exe'
$script:Owner.CommandLine='python.exe "C:\relay.py" --control-port 47996 --hi-res-timer'
Assert ((@(Get-ManagedRelayOwners) -join ',') -eq '123') 'Production Python relay was not adopted'
$script:Owner.CommandLine='python.exe "C:\other.py"'
Assert-Conflict
Write-Output 'PASS: LAN Sunshine auto tunnel allowed; parent/path/derived-port verified; managed relay adopted; unrelated process rejected.'
