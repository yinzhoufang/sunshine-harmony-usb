param([switch]$Elevated)
$ErrorActionPreference = 'Stop'
trap {
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'installation-error.txt'), $_.ToString(), [Text.UTF8Encoding]::new($false))
    exit 1
}
. (Join-Path $PSScriptRoot 'Installer.Common.ps1')
function Quote-Argument([string]$Value) { return '"' + $Value.Replace('"','\"') + '"' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    if ($Elevated) { throw 'Administrator authorization was not granted.' }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File ' + (Quote-Argument $PSCommandPath) + ' -Elevated'
    try {
        $child = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
        exit $child.ExitCode
    } catch {
        Write-Error ('Installation was cancelled or could not start: ' + $_.Exception.Message)
        exit 1
    }
}

$root = 'C:\Program Files\Sunshine'
$destination = Join-Path $root 'assets\gui\sunshine-gui.exe'
if (!(Test-Path -LiteralPath $destination)) { throw 'Sunshine Control Panel was not found in C:\Program Files\Sunshine.' }
$installedVersion = (Get-Item -LiteralPath $destination).VersionInfo.ProductVersion
if ($installedVersion -notmatch '^0\.5\.9(?:\+usb\.\d+)?$') { throw "This package is based on GUI 0.5.9; installed GUI is $installedVersion. Installation was not changed." }
$manifest = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'manifest.json')) | ConvertFrom-Json
foreach ($property in $manifest.PSObject.Properties) {
    $file = Join-Path $PSScriptRoot $property.Name
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $property.Value) { throw ('Package verification failed: ' + $property.Name) }
}

$resources = Join-Path $root 'tools\harmony-usb'
$alreadyInstalled = Test-PanelInstallCurrent $manifest $destination $resources
if ($alreadyInstalled) {
    # Preserve the first original-version backup when the same package is run again.
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'installation-result.json'), (@{ success=$true; already_installed=$true; gui_sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    exit 0
}

$backup = Join-Path $root ('tools\harmony-usb-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item -LiteralPath $destination -Destination (Join-Path $backup 'sunshine-gui.exe')
if (Test-Path -LiteralPath $resources) { Copy-Item -LiteralPath $resources -Destination (Join-Path $backup 'harmony-usb') -Recurse }
$originalHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
$originalBackup = $backup
$priorInfoPath = Join-Path $resources 'installation.json'
if (Test-Path -LiteralPath $priorInfoPath) {
    $priorInfo = [IO.File]::ReadAllText($priorInfoPath) | ConvertFrom-Json
    $allowed = [IO.Path]::GetFullPath((Join-Path $root 'tools\harmony-usb-backups')) + '\'
    $priorBackup = [IO.Path]::GetFullPath([string]$priorInfo.backup)
    if ($priorBackup.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) {
        $priorGui = Join-Path $priorBackup 'sunshine-gui.exe'
        if ((Test-Path -LiteralPath $priorGui) -and (Get-FileHash -LiteralPath $priorGui -Algorithm SHA256).Hash -eq $priorInfo.original_gui_sha256) {
            $originalBackup = $priorBackup
            $originalHash = [string]$priorInfo.original_gui_sha256
        }
    }
}
$binaryChanged = $false
try {
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $manifest.'sunshine-gui.exe') {
        Install-PanelBinary (Join-Path $PSScriptRoot 'sunshine-gui.exe') $destination
        $binaryChanged = $true
    }
    New-Item -ItemType Directory -Path $resources -Force | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'harmony-usb') -File) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $resources $file.Name) -Force
    }
    [IO.File]::WriteAllText((Join-Path $resources 'installation.json'), (@{ backup=$originalBackup; original_gui_sha256=$originalHash; last_update_backup=$backup; installed_at=(Get-Date).ToString('o') } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'installation-result.json'), (@{ success=$true; backup=$backup; gui_sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
} catch {
    $failureMessage = $_.Exception.Message
    if ($binaryChanged) { Install-PanelBinary (Join-Path $backup 'sunshine-gui.exe') $destination }
    if (Test-Path -LiteralPath (Join-Path $backup 'harmony-usb')) {
        Get-ChildItem -LiteralPath (Join-Path $backup 'harmony-usb') -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $resources $_.Name) -Force
        }
    }
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'installation-result.json'), (@{success=$false;message=$failureMessage;backup=$backup} | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    throw
}
# The Sunshine streaming service and its current transport stay untouched.
Start-Process -FilePath $destination -WorkingDirectory (Split-Path $destination) -WindowStyle Hidden
