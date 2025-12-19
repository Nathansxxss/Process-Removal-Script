---

# 🧹 Process Removal Script (Windows)

A **safe, transparent PowerShell script** designed to **analyze and disable unnecessary third-party background services** on Windows, helping reduce background usage without breaking the system.

This project is **open-source**, **non-destructive**, and focused on **control and visibility**, not aggressive system modification.

---

## 🖥️ GUI Preview

<img width="1059" height="561" alt="Process Removal Script GUI" src="https://github.com/user-attachments/assets/b411b98a-dd2e-4e8a-a9d9-00f23c75fc6f" />

---

## 🎯 Purpose

Windows systems often accumulate **unused or unnecessary background services**, usually installed by third-party software.

This script helps you:

* Identify **non-essential, non-Microsoft services**
* Optionally disable them **safely**
* Reduce background CPU, RAM, and service overhead
* Keep full control over what changes are made

---

## 🚀 One-Liners

> ⚠️ **Important**
> These scripts **must be run in PowerShell opened as Administrator**.
> Right-click PowerShell → **Run as administrator**.

### Run Script (GUI)

```powershell
irm https://raw.githubusercontent.com/Nathansxxss/Process-Removal-Script/main/cleanup-non-windows-services.ps1 | iex
```

### Undo Script

```powershell
irm https://raw.githubusercontent.com/Nathansxxss/Process-Removal-Script/main/revert-cleanup.ps1 | iex
```

---

## ✅ What This Script DOES

* ✔️ Analyzes background services and processes
* ✔️ Targets **third-party / non-core** services only
* ✔️ Allows review before any action is taken
* ✔️ Uses readable, non-obfuscated PowerShell code
* ✔️ Designed for **Windows 10 & Windows 11**
* ✔️ Can be used as an **analysis tool only**

---

## ❌ What This Script DOES NOT Do

To be absolutely clear:

* ❌ Does NOT delete system files
* ❌ Does NOT touch Windows core services
* ❌ Does NOT disable Windows Defender
* ❌ Does NOT bypass security features
* ❌ Does NOT modify drivers or firmware
* ❌ Does NOT send or collect any data
* ❌ Does NOT connect to the internet

If you ever see behavior like this, **do not run the script** — but this project does **none** of the above.

---

## 🔐 Safety & Transparency

* Fully **open-source** — inspect every line
* No encoded or obfuscated commands
* No hidden persistence mechanisms
* No telemetry or tracking
* No external network activity

Transparency is a core goal of this project.

---

## ⚠️ Important Notes

* Some actions require **Administrator privileges**
* Disabling services may affect **specific third-party applications**
* Intended for **advanced users** or users willing to learn

👉 Always understand what you’re disabling before confirming.

---

## ▶️ Recommended Usage

1. **Read the script**
2. Run it in **analysis / review mode first**
3. Check the detected services
4. Proceed only if you understand the impact

---

## 📄 Disclaimer

This project is provided **as-is**, without warranty.

You are responsible for:

* Reviewing the code
* Understanding the changes
* Testing on your system

Use at your own risk.

---

## 🤝 Contributing

Suggestions, improvements, and safety enhancements are welcome.
If you spot a risky behavior or edge case, feel free to open an issue.

---

## 📜 License

MIT License — free to use, modify, and learn from.

---
