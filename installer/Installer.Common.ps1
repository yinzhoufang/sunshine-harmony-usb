# File replacement helpers. This file does not perform installation on import.
function Test-PanelInstallCurrent($Manifest, [string]$Destination, [string]$Resources) {
    foreach ($property in $Manifest.PSObject.Properties) {
        $targetFile = $Destination
        if ($property.Name -ne 'sunshine-gui.exe') { $targetFile = Join-Path $Resources ([IO.Path]::GetFileName($property.Name)) }
        if (!(Test-Path -LiteralPath $targetFile) -or (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash -ne $property.Value) { return $false }
    }
    return $true
}

function Stop-InstalledPanel([string]$Destination) {
    $panelName = [IO.Path]::GetFileNameWithoutExtension($Destination)
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $panels = @(Get-Process -Name $panelName -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Destination })
        foreach ($panel in $panels) {
            try {
                Stop-Process -Id $panel.Id -Force -ErrorAction Stop
            } catch {
                if (!$panel.HasExited) { throw }
            }
            if (!$panel.WaitForExit(5000)) { throw 'PANEL_EXIT_TIMEOUT: close Sunshine Control Panel and retry.' }
        }
        $remaining = @(Get-Process -Name $panelName -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Destination })
        if ($remaining.Count -eq 0) { return }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'PANEL_RESTARTING: close Sunshine Control Panel and retry.'
}

function Wait-PanelFileReleased([string]$Destination, [int]$TimeoutSeconds = 15) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            $stream = [IO.File]::Open($Destination, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            $stream.Dispose()
            return
        } catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) { throw 'PANEL_FILE_BUSY: close Sunshine Control Panel, wait a few seconds, then retry.' }
            Start-Sleep -Milliseconds 200
        }
    } while ($true)
}

function Install-PanelBinary([string]$Source, [string]$Destination) {
    # Stage next to the target, then atomically replace it. A lock failure cannot
    # truncate the installed EXE, and the original backup remains independent.
    $stage = Join-Path (Split-Path -Parent $Destination) ('sunshine-gui-' + [guid]::NewGuid().ToString('N') + '.new')
    try {
        [IO.File]::Copy($Source, $stage, $false)
        $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
        if ((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -ne $sourceHash) { throw 'STAGED_GUI_HASH_MISMATCH' }
        Stop-InstalledPanel $Destination
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        do {
            Wait-PanelFileReleased $Destination
            try {
                [IO.File]::Replace($stage, $Destination, [NullString]::Value)
                return
            } catch [IO.IOException] {
                if ([DateTime]::UtcNow -ge $deadline) { throw 'PANEL_REPLACE_BUSY: close Sunshine Control Panel and retry.' }
                Start-Sleep -Milliseconds 200
            }
        } while ($true)
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Force }
    }
}
