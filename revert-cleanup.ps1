Write-Host "=== Revert Cleanup (friendly mode) ===" -ForegroundColor Cyan

# --- Resolve base folder robustly ---
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
    Write-Host "ERROR: Run PowerShell as Administrator, then run this script again." -ForegroundColor Red
    exit 1
}

# --- Temporary execution policy bypass (THIS SESSION ONLY) ---
# If a policy is enforced by your PC (Group Policy), this may fail
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
    Write-Host "ExecutionPolicy: temporary bypass enabled for this session." -ForegroundColor Green
} catch {
    Write-Host "ExecutionPolicy: could not set Process Bypass (policy may be enforced). Using fallbacks." -ForegroundColor Yellow
}

# --- Logging (best-effort) ---
$LogPath = Join-Path $BaseDir ("revert-log_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))
function LogLine([string]$msg) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg
    try { $line | Tee-Object -FilePath $LogPath -Append | Out-Null } catch { Write-Host $line }
}

LogLine "BaseDir: $BaseDir"
LogLine "Log: $LogPath"

# --- Find undo files in common locations ---
function Find-UndoFile([string]$fileName) {
    $candidates = @(
        (Join-Path $BaseDir $fileName),
        (Join-Path (Get-Location).Path $fileName),
        (Join-Path $env:WINDIR "System32\$fileName")
    ) | Select-Object -Unique

    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# --- Run undo file with friendly bypass behavior ---
function Run-UndoFile([string]$path) {
    if (-not $path -or -not (Test-Path $path)) { return $false }

    Write-Host "Running: $path" -ForegroundColor Cyan
    LogLine "Running: $path"

    # 1) Try powershell.exe -ExecutionPolicy Bypass -File (usually works)
    try {
        $args = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$path`""
        )

        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList ($args -join " ") -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -eq 0) {
            Write-Host "OK: $path" -ForegroundColor Green
            LogLine "OK via Start-Process: $path"
            return $true
        } else {
            Write-Host "Note: ExitCode $($proc.ExitCode). Trying fallback..." -ForegroundColor Yellow
            LogLine "Start-Process ExitCode $($proc.ExitCode) for $path"
        }
    } catch {
        Write-Host "Note: couldn't run via Start-Process. Trying fallback..." -ForegroundColor Yellow
        LogLine "Start-Process failed for $path : $($_.Exception.Message)"
    }

    # 2) Fallback: execute file contents (often bypasses script-file policy)
    try {
        iex (Get-Content $path -Raw)
        Write-Host "OK (fallback): $path" -ForegroundColor Green
        LogLine "OK via iex fallback: $path"
        return $true
    } catch {
        Write-Host "FAILED: $path -> $($_.Exception.Message)" -ForegroundColor Red
        LogLine "FAILED for $path : $($_.Exception.Message)"
        return $false
    }
}

# --- Locate undo files ---
$undoServices = Find-UndoFile "undo-services.ps1"
$undoTweaks   = Find-UndoFile "undo-tweaks.ps1"

if (-not $undoServices) { Write-Host "undo-services.ps1 not found (searched BaseDir/current/System32)." -ForegroundColor Yellow }
if (-not $undoTweaks)   { Write-Host "undo-tweaks.ps1 not found (searched BaseDir/current/System32)." -ForegroundColor Yellow }

# --- Execute undo files ---
$didSomething = $false
if ($undoServices) { $didSomething = (Run-UndoFile $undoServices) -or $didSomething }
if ($undoTweaks)   { $didSomething = (Run-UndoFile $undoTweaks) -or $didSomething }

Write-Host ""
if ($didSomething) {
    Write-Host "Revert complete. Restart recommended." -ForegroundColor Green
    LogLine "Revert complete."
} else {
    Write-Host "Nothing reverted (undo files missing or could not run)." -ForegroundColor Yellow
    LogLine "Nothing reverted."
}

Write-Host "Log saved to: $LogPath" -ForegroundColor Gray
