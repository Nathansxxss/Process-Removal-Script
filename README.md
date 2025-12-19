---

# 🧹 Safe Cleanup GUI for Windows (Process Removal Script)

A **non-destructive, transparent PowerShell GUI tool** for **reviewing and safely disabling optional background services and built-in bloat apps** on Windows.

Designed for people who want **control, safety, and reversibility** — not aggressive “one-click debloat” scripts.

---

## 🖥️ GUI Preview

<img width="1059" height="561" alt="Safe Cleanup GUI" src="https://github.com/user-attachments/assets/b411b98a-dd2e-4e8a-a9d9-00f23c75fc6f" />

---

## 🔐 Safety First (Read This)

This tool is built to be **hard to misuse**:

* ✅ **Dry-run enabled by default** (no changes unless you disable it)
* ✅ **Protected Windows services & Store components are hard-blocked**
* ✅ **No downloads, no network calls, no telemetry**
* ✅ **Creates a restore point before applying changes**
* ✅ **Automatically generates undo scripts**
* ✅ **All actions are visible in the GUI and logged**

Nothing happens silently.

---

## 🎯 Purpose

Windows systems often accumulate:

* unused third-party background services
* preinstalled or promotional apps
* startup items you didn’t explicitly choose

This tool helps you:

* Review **only allow-listed, optional services**
* Identify **installed bloat apps** (nothing hidden)
* Apply changes **only after confirmation**
* Revert changes at any time using generated undo scripts

It can also be used as a **read-only analysis tool**.

---

## 🚀 Quick Start (One-Liner)

> ⚠️ To **apply changes**, PowerShell must be opened as **Administrator**.
> You can still preview everything without admin.

### Launch the GUI

```powershell
irm https://raw.githubusercontent.com/Nathansxxss/Process-Removal-Script/main/cleanup-non-windows-services.ps1 | iex
```

* Opens a GUI
* Dry-run ON by default
* No changes unless you click **Apply**

### Undo Changes

```powershell
irm https://raw.githubusercontent.com/Nathansxxss/Process-Removal-Script/main/revert-cleanup.ps1 | iex
```

(Undo scripts are also generated locally after changes.)

---

## ✅ What This Tool DOES

* ✔️ Shows **only allow-listed optional Windows services**
* ✔️ Detects **installed bloat / promotional Appx packages**
* ✔️ Skips all **core Windows, security, Store, and shell components**
* ✔️ Logs every action to a local file
* ✔️ Generates **undo scripts using captured pre-state**
* ✔️ Works on **Windows 10 & Windows 11**
* ✔️ Can be used in **dry-run / inspection mode only**

---

## ❌ What This Tool DOES NOT Do

To be absolutely clear:

* ❌ Does NOT disable Windows Defender or Firewall
* ❌ Does NOT add Defender exclusions
* ❌ Does NOT touch core Windows services
* ❌ Does NOT modify drivers, firmware, or boot settings
* ❌ Does NOT persist after execution
* ❌ Does NOT send or collect any data
* ❌ Does NOT connect to the internet

If you see behavior like this, **do not run the script** — this project does **none** of the above.

---

## 🛡 Threat Model

This script is intentionally conservative.

It:

* never uses obfuscated or encoded commands
* never downloads or executes external payloads
* never disables security components
* never auto-applies changes
* never hides what it is doing

Everything is user-initiated, visible, and reversible.

---

## ⚠️ Important Notes

* Some changes require **Administrator privileges**
* Disabling services may affect **specific third-party software**
* Intended for users who want **visibility and control**, not blind optimization

👉 Always understand what you’re disabling.

---

## ▶️ Recommended Usage

1. Read the script (it’s fully readable)
2. Launch the GUI
3. Leave **Dry-run** enabled on first run
4. Review detected items
5. Apply only what you understand

---

## 🔍 Code Review Welcome

This repository is intentionally:

* fully readable
* un-obfuscated
* conservative by design

If you spot a risk, edge case, or improvement, open an issue.

---

## 📄 Disclaimer

This project is provided **as-is**, without warranty.

You are responsible for:

* reviewing the code
* understanding the changes
* testing on your system

---

## 📜 License

MIT License — free to use, modify, and learn from.

---
