# Reviewed and confirmed read-only behavior

<#
.SYNOPSIS
    Scans for potentially dangerous or suspicious non-Microsoft Windows services.

.DESCRIPTION
    Performs a READ-ONLY analysis of running services and flags entries
    that may warrant further investigation.

    This script does NOT disable, stop, delete, or modify any services.

    Indicators used:
    - Non-Microsoft services
    - Executables running from user-writable or unusual paths
    - Unsigned executables
    - Random or garbage-like service names
    - Common malware persistence locations

    This is NOT a malware remover.
    It is an investigation aid only.

.AUTHOR
    Nathansxxss
#>

Write-Host "=== Suspicious Service Scan (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host "No system changes will be made." -ForegroundColor Gray
Write-Host ""

# Paths that are generally considered safe
$SafeRoots = @(
    "C:\Windows\",
    "C:\Program Files\",
    "C:\Program Files (x86)\"
)

# Locations commonly abused by malware
$SuspiciousPathPattern = "\\AppData\\|\\Temp\\|\\ProgramData\\|\\Users\\Public\\"

# Random / obfuscated service name patterns
$SuspiciousNamePattern = '^[a-zA-Z]{1,3}\d{3,}$|^[a-f0-9]{8,}$'

# Collect running services with executable paths
$services = Get-CimInstance Win32_Service | Where-Object {
    $_.State -eq "Running"
}

$results = @()

foreach ($svc in $services) {

    # Skip Microsoft services entirely (non-negotiable)
    if ($svc.Manufacturer -eq "Microsoft Corporation") {
        continue
    }

    $exePath = $null
    if ($svc.PathName) {
        $exePath = ($svc.PathName -replace '"', '').Split(' ')[0]
    }

    $flags = @()

    # 1. Executable path exists and is non-standard
    if ($exePath -and (Test-Path $exePath)) {
        if (-not ($SafeRoots | Where-Object { $exePath.StartsWith($_, 'OrdinalIgnoreCase') })) {
            $flags += "Non-standard install path"
        }

        # 2. User-writable or commonly abused locations
        if ($exePath -match $SuspiciousPathPattern) {
            $flags += "User-writable / persistence location"
        }

        # 3. Unsigned executable
        $sig = Get-AuthenticodeSignature $exePath
        if ($sig.Status -ne "Valid") {
            $flags += "Unsigned executable"
        }
    }

    # 4. Suspicious or random-looking service name
    if ($svc.Name -match $SuspiciousNamePattern) {
        $flags += "Suspicious service name"
    }

    if ($flags.Count -gt 0) {
        $results += [PSCustomObject]@{
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            Executable  = $exePath
            Indicators  = ($flags -join "; ")
        }
    }
}

if ($results.Count -eq 0) {
    Write-Host "No suspicious services detected." -ForegroundColor Green
    return
}

Write-Host "Potentially suspicious services found:" -ForegroundColor Yellow
$results | Format-Table -AutoSize

Write-Host ""
Write-Host "Review these entries manually before taking any action." -ForegroundColor Cyan
Write-Host "This script does not remove or disable anything." -ForegroundColor Gray
