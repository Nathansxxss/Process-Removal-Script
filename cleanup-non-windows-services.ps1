<#
.SYNOPSIS
    Scans for potentially suspicious non-Microsoft Windows services.

.DESCRIPTION
    This script performs a READ-ONLY scan of installed services and
    highlights entries that may warrant further investigation.

    It does NOT disable, stop, or modify any services.

    Heuristics used:
    - Non-Microsoft services
    - Executables outside standard system/program paths
    - Unsigned binaries
    - Random-looking service names
    - Known malware persistence locations

    This is NOT a malware remover.
    It is an investigation aid.

.AUTHOR
    Nathansxxss
#>

Write-Host "=== Suspicious Service Scan (Read-Only) ===" -ForegroundColor Cyan
Write-Host "No changes will be made." -ForegroundColor Gray
Write-Host ""

# Known safe root paths
$SafePaths = @(
    "C:\Windows\",
    "C:\Program Files\",
    "C:\Program Files (x86)\"
)

# Regex for random / garbage-like names
$RandomNamePattern = '^[a-zA-Z]{1,3}\d{3,}$|^[a-f0-9]{8,}$'

# Get services with executable paths
$services = Get-CimInstance Win32_Service | Where-Object {
    $_.State -eq "Running"
}

$suspicious = @()

foreach ($svc in $services) {
    # Skip Microsoft services outright
    if ($svc.Manufacturer -eq "Microsoft Corporation") {
        continue
    }

    $exePath = $svc.PathName -replace '"', ''
    $exePath = $exePath.Split(' ')[0]

    $flags = @()

    # 1. Unusual install location
    if ($exePath -and -not ($SafePaths | Where-Object { $exePath.StartsWith($_, 'OrdinalIgnoreCase') })) {
        $flags += "Non-standard path"
    }

    # 2. Unsigned binary
    if (Test-Path $exePath) {
        $sig = Get-AuthenticodeSignature $exePath
        if ($sig.Status -ne "Valid") {
            $flags += "Unsigned executable"
        }
    }

    # 3. Random-looking service name
    if ($svc.Name -match $RandomNamePattern) {
        $flags += "Suspicious service name"
    }

    # 4. Known bad persistence locations
    if ($exePath -match "\\AppData\\|\\Temp\\|\\ProgramData\\") {
        $flags += "User-writable location"
    }

    if ($flags.C

