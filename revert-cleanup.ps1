
Write-Host "Loading revert script..." -ForegroundColor Cyan

# --- Resolve folder robustly ---
$BaseDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BaseDir)) { $BaseDir = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($BaseDir)) { $BaseDir = $env:TEMP }

# --- Admin check ---
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
    Write-Host "ERROR: Please run PowerShell as Administrator, then run this script again." -ForegroundColor Red
    exit 1
}

# --- Helpers ---
function Say($msg) { Write-Host $msg }
function Run-UndoFile($path) {
    if (-not (Test-Path $path)) { return $false }
    Say "Running: $path"
    try {
        # Execute in its own scope
        & $path
        Say "OK: $path"
        return $true
    } catch {
        Write-Host "FAILED: $path -> $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# --- Paths ---
$undoServices = Join-Path $BaseDir "undo-services.ps1"
$undoTweaks   = Join-Path $BaseDir "undo-tweaks.ps1"

# --- Run undo scripts if present ---
$didAnything = $false

if (Test-Path $undoServices) {
    $didAnything = (Run-UndoFile $undoServices) -or $didAnything
} else {
    Say "Note: undo-services.ps1 not found in $BaseDir"
}

if (Test-Path $undoTweaks) {
    $didAnything = (Run-UndoFile $undoTweaks) -or $didAnything
} else {
    Say "Note: undo-tweaks.ps1 not found in $BaseDir"
}

# --- Safe fallback tweaks (only if undo-tweaks.ps1 missing) ---
if (-not (Test-Path $undoTweaks)) {
    Say ""
    Say "Fallback tweaks (safe):"
    Say "1) Re-enable Widgets"
    Say "2) Re-enable OneDrive startup (if possible)"
    Say "3) Skip"
    $choice = Read-Host "Choose 1/2/3"

    if ($choice -eq "1") {
        try {
            $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            Set-ItemProperty -Path $path -Name "TaskbarDa" -Type DWord -Value 1
            Say "Widgets set to Enabled (may require explorer restart or sign-out)."
            $didAnything = $true
        } catch {
            Write-Host "Failed to enable Widgets: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    if ($choice -eq "2") {
        try {
            # This can only restore if we know the previous run value.
            # We'll just tell the user what to do.
            Say "OneDrive startup restore needs the exact Run entry value."
            Say "If you still have undo-tweaks.ps1, use that instead."
            Say "Otherwise: reinstall/repair OneDrive and it will re-add its startup entry."
        } catch {
            Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# --- Show what apps were removed (best-effort) ---
Say ""
Say "Looking for cleanup logs to list removed apps..."

$logs = Get-ChildItem -Path $BaseDir -Filter "cleanup-log_*.txt" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

if ($logs -and $logs.Count -gt 0) {
    $latest = $logs[0].FullName
    Say "Latest log: $latest"

    try {
        $lines = Get-Content $latest -ErrorAction Stop

        $removedAppx = @()
        foreach ($line in $lines) {
            if ($line -match "Remove Appx:\s+(?<pkg>.+?)\s+\(dry-run=False\)") {
                $removedAppx += $matches["pkg"].Trim()
            }
        }

        $removedAppx = $removedAppx | Sort-Object -Unique

        if ($removedAppx.Count -gt 0) {
            Say ""
            Say "Apps that were removed (from log):"
            $removedAppx | ForEach-Object { Say " - $_" }

            Say ""
            Say "To reinstall most Store apps:"
            Say " - Open Microsoft Store and search the app name"
            Say " - Or use winget (if installed): winget search <name>  then winget install <id>"
        } else {
            Say "No removed Appx entries found in the latest log."
        }
    } catch {
        Write-Host "Could not read log: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Say "No cleanup-log_*.txt found in $BaseDir"
}

Say ""
if ($didAnything) {
    Write-Host "Revert finished. Restart your PC to fully apply restored settings." -ForegroundColor Green
} else {
    Write-Host "Nothing was reverted (undo files missing or no changes detected)." -ForegroundColor Yellow
}
