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

# Collect running services with execut
