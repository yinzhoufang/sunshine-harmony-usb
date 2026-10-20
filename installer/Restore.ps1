param([switch]$Elevated)
$ErrorActionPreference = 'Stop'
trap {
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'restore-error.txt'), $_.ToString(), [Text.UTF8Encoding]::new($false))
    exit 1
}
. (Join-Path $PSScriptRoot 'Installer.Common.ps1')
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (!([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($Elevated) { throw 'Administrator authorization was not granted.' }
    try {
        $child=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Elevated') -WindowStyle Hidden -Wait -PassThru
        exit $child.ExitCode
    } catch {
        Write-Error ('Restore was cancelled or could not start: ' + $_.Exception.Message)
        exit 1
    }
}
$root='C:\Program Files\Sunshine'
$installed=Join-Path $root 'tools\harmony-usb\installation.json'
$info=[IO.File]::ReadAllText($installed) | ConvertFrom-Json
$backupPath=[IO.Path]::GetFullPath([string]$info.backup)
$allowed=[IO.Path]::GetFullPath((Join-Path $root 'tools\harmony-usb-backups')) + '\'
if (!$backupPath.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid backup location.' }
$backup=Join-Path $backupPath 'sunshine-gui.exe'
if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $info.original_gui_sha256) { throw 'Backup verification failed.' }
$destination=Join-Path $root 'assets\gui\sunshine-gui.exe'
Install-PanelBinary $backup $destination
if (Test-Path -LiteralPath (Join-Path $backupPath 'harmony-usb')) {
    Get-ChildItem -LiteralPath (Join-Path $backupPath 'harmony-usb') -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $root ('tools\harmony-usb\' + $_.Name)) -Force
    }
}
Start-Process -FilePath $destination -WorkingDirectory (Split-Path $destination) -WindowStyle Hidden
