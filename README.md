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
<img width="1059" height="561" alt="image" src="https://github.com/user-attachments/assets/b411b98a-dd2e-4e8a-a9d9-00f23c75fc6f" />

## One-liner
### Run Powershell as Administrator 
Gui:
```powershell
irm https://raw.githubusercontent.com/Nathansxxss/Process-Removal-Script/main/cleanup-non-windows-services.ps1 | iex
