param([string]$SunshineRoot='C:\Program Files\Sunshine', [string]$DeviceId='')
& (Join-Path $PSScriptRoot 'transport_mode.ps1') -Action Usb -SunshineRoot $SunshineRoot -DeviceId $DeviceId
exit $LASTEXITCODE
