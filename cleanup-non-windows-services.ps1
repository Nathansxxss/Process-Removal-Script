<#
.SYNOPSIS
    Safely lists and optionally disables non-Windows automatic services.

.DESCRIPTION
    This script is designed to help reduce unnecessary background services
    WITHOUT breaking Windows.

    - Dry-run by default (no changes unless -Apply is used)
    - Creates a System Restore Point before applying changes
    - Skips critical Windows, network, GPU, input, and security services
    - Generates an undo script automatically

    This is NOT a debloat or "nuke services" script.
    It is intentionally conservative.

.PARAMETER Apply
    Actually apply changes. Without this flag, the script only shows what
    would be changed.

.AUTHOR
    Nathansxxss
#>

param (
    [switch]$Apply
)

Write-Host "=== Safe Non-Windows Service Cleanup ===" -ForegroundColor Cyan
Write-Host "Dry-run mode is ON by default." -ForegroundColor Gray
Write-Host ""

# Keywords that should NEVER be touched
$CriticalKeywords = @(
    "windows",
    "microsoft",
    "winlogon",
    "explorer",
    "network",
    "ethernet",
    "wifi",
    "bluetooth",
    "dhcp",
    "nvidia",
    "amd",
    "intel",
    "audio",
    "sound",
    "input",
    "hid",
    "usb",
    "display",
    "gpu",
    "security",
    "defender",
    "firewall",
    "event",
    "time",
    "rpc",
    "crypt",
    "update",
    "store"
)

# Get automatic services that are currently running
$services = Get-Service | Where-Object {
    $_.StartType -eq "Automatic" -and
    $_.Status -eq "Running"
}

# Filter out anything that looks critical
$targets = $services | Where-Object {
    $serviceName = $_.Name.ToLower()

    foreach ($keyword in $CriticalKeywords) {
        if ($serviceName -like "*$keyword*") {
            return $false
        }
    }

    return $true
}

if (-not $targets -or $targets.Count -eq 0) {
    Write-Host "No safe-to-disable services were found." -ForegroundColor Green
    return
}

Write-Host "The following services were identified:" -ForegroundColor Yellow
$targets | Select-Object Name, DisplayName | Format-Table -AutoSize

# Dry-run exit
if (-not $Apply) {
    Write-Host ""
    Write-Host "DRY RUN ONLY — no changes have been made." -ForegroundColor Cyan
    Write-Host "If everything looks OK, run:" -ForegroundColor Gray
    Write-Host "  .\cleanup-non-windows-services.ps1 -Apply" -ForegroundColor Green
    return
}

# Create a restore point
Write-Host ""
Write-Host "Creating system restore point..." -ForegroundColor Cyan
Checkpoint-Computer `
    -Description "Before non-Windows service cleanup" `
    -RestorePointType "MODIFY_SETTINGS"

# Build undo script
$undoLines = @()
foreach ($svc in $targets) {
    $undoLines += "Set-Service -Name `"$($svc.Name)`" -StartupType Automatic"
}

$undoPath = Join-Path $PSScriptRoot "undo-services.ps1"
$undoLines | Out-File -FilePath $undoPath -Encoding UTF8

Write-Host "Undo script created: undo-services.ps1" -ForegroundColor Green

# Apply changes
Write-Host ""
Write-Host "Applying changes..." -ForegroundColor Red

foreach ($svc in $targets) {
    Write-Host " - Setting $($svc.Name) to Manual"
    Set-Service -Name $svc.Name -StartupType Manual
}

Write-Host ""
Write-Host "Done. A reboot is recommended." -ForegroundColor Cyan
