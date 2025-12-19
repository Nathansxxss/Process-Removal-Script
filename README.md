# Process Removal Script

A **safe and conservative PowerShell script** for identifying and managing
non-Windows background services.

This script is **dry-run by default** and is designed to avoid breaking
Windows by skipping critical system, network, GPU, and security services.

## Features
- Dry-run mode (no changes unless explicitly applied)
- Automatic system restore point
- Generates an undo script
- Avoids Windows core services
- Designed for Windows 10 / 11

## Usage

## One-liner

Gui:
```powershell
irm https://raw.githubusercontent.com/Nathansxxss/Process-Removal-Script/main/cleanup-non-windows-services.ps1 | iex
