# Reviewed and confirmed: GUI tool is conservative by design.
# - Shows only allowlisted OPTIONAL services + a denylist of Appx bloat apps
# - Dry-run by default
# - Creates restore point + writes undo scripts/logs
# - Refuses to touch protected Windows/Store runtime components

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ----------------------------
# Admin check (needed for service changes / provisioned Appx removal)
# ----------------------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ----------------------------
# Logging helpers
# ----------------------------
$Global:LogPath = Join-Path $PSScriptRoot ("gui-cleanup-log_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))

function LogLine([string]$msg) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg
    $line | Tee-Object -FilePath $Global:LogPath -Append | Out-Null
}

# ----------------------------
# PROTECTED lists (never touch)
# ----------------------------
$ProtectedServiceNames = @(
    # core login/session/auth/network/security
    "DcomLaunch","LSM","SamSs","ProfSvc","UserManager",
    "BrokerInfrastructure","CoreMessagingRegistrar","StateRepository","gpsvc","Schedule","SENS",
    "Dnscache","nsi","Wcmsvc","BFE","mpssvc",
    # Defender/security
    "WinDefend","WdNisSvc","MDCoreSvc","Sense","wscsvc","SecurityHealthService"
)

# Appx packages that must never be removed (Store + runtimes)
$ProtectedAppxPatterns = @(
    "^Microsoft\.WindowsStore$",
    "^Microsoft\.StorePurchaseApp$",
    "^Microsoft\.DesktopAppInstaller$",
    "^Microsoft\.VCLibs",
    "^Microsoft\.NET\.Native",
    "^Microsoft\.UI\.Xaml",
    "^Microsoft\.Services\.Store",
    "^Microsoft\.WindowsAppRuntime",
    "^Microsoft\.SecHealthUI$",
    "^Microsoft\.Windows\.ShellExperienceHost$",
    "^Microsoft\.Windows\.StartMenuExperienceHost$",
    "^Microsoft\.AAD\.BrokerPlugin$",
    "^Microsoft\.LockApp$"
)

function Is-ProtectedAppxName([string]$name) {
    foreach ($pat in $ProtectedAppxPatterns) {
        if ($name -match $pat) { return $true }
    }
    return $false
}

# ----------------------------
# OPTIONAL SERVICES (explicit allowlist)
# Only these are shown in the GUI for disabling/changing.
# Add more if you know what they do.
# ----------------------------
$OptionalServices = @(
    # name, friendly reason
    @{ Name="WSearch";   Reason="Windows Search indexing (optional). Disabling can slow searches." },
    @{ Name="Spooler";   Reason="Printing service (optional if you never print)." },
    @{ Name="DoSvc";     Reason="Delivery Optimization (optional). Affects Windows Update download behavior." },
    @{ Name="DiagTrack"; Reason="Telemetry/diagnostics service (optional)." }
)

# ----------------------------
# APPX DENYLIST (your bloat list)
# Note: We treat these as prefixes (some packages include suffixes/versions)
# ----------------------------
$AppxDenylist = @(
    "26720RandomSaladGamesLLC.SimpleMahjong",
    "26720RandomSaladGamesLLC.SimpleSolitaire",
    "4DF9E0F8.Netflix",
    "57540AMZNMobileLLC.AmazonAlexa",
    "5A894077.McAfeeSecurity",
    "7EE7776C.LinkedInforWindows",
    "828B5831.HiddenCityMysteryofShadows",
    "A278AB0D.DisneyMagicKingdoms",
    "A278AB0D.MarchofEmpires",
    "AD2F1837.HPEnhance",
    "AD2F1837.HPPrinterControl",
    "AD2F1837.HPPrivacySettings",
    "AD2F1837.HPQuickDrop",
    "AD2F1837.HPSupportAssistant",
    "AD2F1837.myHP",
    "AD2F1837.OMENCommandCenter",
    "Amazon.com.Amazon",
    "C27EB4BA.DropboxOEM",
    "DellInc.DellSupportAssistforPCs",
    "Disney.37853FC22B2CE",
    "DolbyLaboratories.DolbyAccess",
    "flaregamesGmbH.RoyalRevolt2",
    "king.com.BubbleWitch3Saga",
    "king.com.CandyCrushFriends",
    "king.com.CandyCrushSaga",
    "king.com.CandyCrushSodaSaga",
    "king.com.FarmHeroesSaga",
    "Microsoft.Advertising.Xaml",
    "Microsoft.BingFinance",
    "Microsoft.BingNews",
    "Microsoft.BingSports",
    "Microsoft.BingWeather",
    "Microsoft.CommsPhone",
    "Microsoft.Messaging",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.OneConnect",
    "Microsoft.People",
    "Microsoft.SkypeApp",
    "Microsoft.WindowsCommunicationsApps",
    "Microsoft.WindowsPhone",
    "Microsoft.XboxApp",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "NORDCURRENT.COOKINGFEVER",
    "PricelinePartnerNetworkBooking.comUSABigsavingson",
    "SpotifyAB.SpotifyMusic"
)

# ----------------------------
# Data loaders
# ----------------------------
function Get-OptionalServiceRows {
    $svcCim = Get-CimInstance Win32_Service
    $rows = @()

    foreach ($item in $OptionalServices) {
        $name = $item.Name
        if ($ProtectedServiceNames -contains $name) { continue }

        $svc = $svcCim | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $svc) { continue }

        $startMode = $svc.StartMode   # Auto / Manual / Disabled
        $state     = $svc.State       # Running / Stopped
        $reason    = $item.Reason

        $rows += [PSCustomObject]@{
            Select     = $false
            Name       = $svc.Name
            Display    = $svc.DisplayName
            StartMode  = $startMode
            State      = $state
            Reason     = $reason
        }
    }

    return $rows
}

function Get-AppxRows {
    $installed = Get-AppxPackage -AllUsers
    $rows = @()

    foreach ($prefix in $AppxDenylist) {
        if (Is-ProtectedAppxName $prefix) { continue }

        $matches = $installed | Where-Object { $_.Name -eq $prefix -or $_.Name -like "$prefix*" }
        foreach ($m in $matches) {
            if (Is-ProtectedAppxName $m.Name) { continue }

            $rows += [PSCustomObject]@{
                Select        = $false
                Name          = $m.Name
                PackageFullName = $m.PackageFullName
                Publisher     = $m.Publisher
                InstallLocation = $m.InstallLocation
            }
        }
    }

    # Unique by PackageFullName
    return $rows | Sort-Object PackageFullName -Unique
}

# ----------------------------
# Apply actions
# ----------------------------
function Create-RestorePoint {
    try {
        LogLine "Creating restore point..."
        Checkpoint-Computer -Description "Before GUI cleanup changes" -RestorePointType "MODIFY_SETTINGS"
        LogLine "Restore point created."
        return $true
    } catch {
        LogLine "Restore point FAILED: $($_.Exception.Message)"
        return $false
    }
}

function Write-ServiceUndoScript($beforeStates) {
    $undoPath = Join-Path $PSScriptRoot "undo-services.ps1"
    $lines = @(
        "# Undo script generated by gui-cleanup.ps1",
        "# Restores service StartMode values captured before changes.",
        ""
    )

    foreach ($b in $beforeStates) {
        $mode = switch ($b.StartMode) {
            "Auto"     { "Automatic" }
            "Manual"   { "Manual" }
            "Disabled" { "Disabled" }
            default    { "Manual" }
        }
        $lines += "Set-Service -Name `"$($b.Name)`" -StartupType $mode"
    }

    $lines | Out-File -Encoding UTF8 -FilePath $undoPath
    LogLine "Wrote undo script: $undoPath"
}

function Apply-ServiceChanges($selectedRows, $targetMode, [bool]$dryRun) {
    if (-not $selectedRows -or $selectedRows.Count -eq 0) { return }

    $cim = Get-CimInstance Win32_Service
    $before = @()

    foreach ($row in $selectedRows) {
        $svcName = $row.Name
        if ($ProtectedServiceNames -contains $svcName) {
            LogLine "SKIP protected service: $svcName"
            continue
        }

        $svc = $cim | Where-Object { $_.Name -eq $svcName } | Select-Object -First 1
        if (-not $svc) { continue }

        $before += [PSCustomObject]@{ Name=$svc.Name; StartMode=$svc.StartMode }

        LogLine ("Service: {0} -> {1} (dry-run={2})" -f $svcName, $targetMode, $dryRun)

        if (-not $dryRun) {
            $psMode = switch ($targetMode) {
                "Auto"     { "Automatic" }
                "Manual"   { "Manual" }
                "Disabled" { "Disabled" }
                default    { "Manual" }
            }
            Set-Service -Name $svcName -StartupType $psMode
        }
    }

    if ($before.Count -gt 0) {
        Write-ServiceUndoScript $before
    }
}

function Apply-AppxRemoval($selectedRows, [bool]$includeProvisioned, [bool]$dryRun) {
    if (-not $selectedRows -or $selectedRows.Count -eq 0) { return }

    foreach ($row in $selectedRows) {
        $name = $row.Name
        $full = $row.PackageFullName

        if (Is-ProtectedAppxName $name) {
            LogLine "SKIP protected Appx: $name"
            continue
        }

        LogLine ("Remove Appx: {0} (dry-run={1})" -f $full, $dryRun)

        if (-not $dryRun) {
            try {
                Remove-AppxPackage -AllUsers -Package $full -ErrorAction Stop
            } catch {
                LogLine "  FAILED Remove-AppxPackage: $($_.Exception.Message)"
            }
        }
    }

    if ($includeProvisioned) {
        $prov = Get-AppxProvisionedPackage -Online
        foreach ($row in $selectedRows) {
            $prefix = $row.Name
            if (Is-ProtectedAppxName $prefix) { continue }

            $matches = $prov | Where-Object { $_.DisplayName -eq $prefix -or $_.DisplayName -like "$prefix*" }
            foreach ($m in $matches) {
                LogLine ("Remove Provisioned: {0} (dry-run={1})" -f $m.PackageName, $dryRun)
                if (-not $dryRun) {
                    try {
                        Remove-AppxProvisionedPackage -Online -PackageName $m.PackageName | Out-Null
                    } catch {
                        LogLine "  FAILED Remove-AppxProvisionedPackage: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
}

# ----------------------------
# GUI setup
# ----------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Safe Cleanup GUI (Read-first)"
$form.Size = New-Object System.Drawing.Size(980, 650)
$form.StartPosition = "CenterScreen"

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = "Fill"

$tabServices = New-Object System.Windows.Forms.TabPage
$tabServices.Text = "Optional Services"

$tabApps = New-Object System.Windows.Forms.TabPage
$tabApps.Text = "Bloat Apps (Appx)"

# Top control panel
$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Height = 70
$topPanel.Dock = "Top"

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = "Dry-run (no changes)"
$chkDryRun.Checked = $true
$chkDryRun.AutoSize = $true
$chkDryRun.Location = New-Object System.Drawing.Point(12, 12)

$chkRestore = New-Object System.Windows.Forms.CheckBox
$chkRestore.Text = "Create restore point before Apply"
$chkRestore.Checked = $true
$chkRestore.AutoSize = $true
$chkRestore.Location = New-Object System.Drawing.Point(12, 38)

$lblAdmin = New-Object System.Windows.Forms.Label
$lblAdmin.AutoSize = $true
$lblAdmin.Location = New-Object System.Drawing.Point(260, 14)

if (Test-IsAdmin) {
    $lblAdmin.Text = "Admin: YES"
    $lblAdmin.ForeColor = [System.Drawing.Color]::DarkGreen
} else {
    $lblAdmin.Text = "Admin: NO (service/app removal will likely fail)"
    $lblAdmin.ForeColor = [System.Drawing.Color]::DarkRed
}

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Size = New-Object System.Drawing.Size(120, 30)
$btnRefresh.Location = New-Object System.Drawing.Point(760, 18)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Apply Selected"
$btnApply.Size = New-Object System.Drawing.Size(150, 30)
$btnApply.Location = New-Object System.Drawing.Point(880, 18)

$topPanel.Controls.AddRange(@($chkDryRun, $chkRestore, $lblAdmin, $btnRefresh, $btnApply))

# Status box
$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.Dock = "Bottom"
$statusBox.Height = 90
$statusBox.ScrollBars = "Vertical"

function Status([string]$msg) {
    $statusBox.AppendText($msg + [Environment]::NewLine)
    LogLine $msg
}

Status "Log: $Global:LogPath"

# --- Services grid ---
$gridSvc = New-Object System.Windows.Forms.DataGridView
$gridSvc.Dock = "Fill"
$gridSvc.AutoGenerateColumns = $true
$gridSvc.AllowUserToAddRows = $false
$gridSvc.SelectionMode = "FullRowSelect"

# Service action controls
$svcPanel = New-Object System.Windows.Forms.Panel
$svcPanel.Dock = "Top"
$svcPanel.Height = 48

$svcMode = New-Object System.Windows.Forms.ComboBox
$svcMode.DropDownStyle = "DropDownList"
$svcMode.Items.AddRange(@("Manual","Disabled","Auto"))
$svcMode.SelectedItem = "Manual"
$svcMode.Location = New-Object System.Drawing.Point(12, 12)
$svcMode.Width = 140

$svcHint = New-Object System.Windows.Forms.Label
$svcHint.Text = "Only allowlisted optional services appear here."
$svcHint.AutoSize = $true
$svcHint.Location = New-Object System.Drawing.Point(170, 15)

$svcPanel.Controls.AddRange(@($svcMode, $svcHint))

$tabServices.Controls.Add($gridSvc)
$tabServices.Controls.Add($svcPanel)

# --- Apps grid ---
$gridApp = New-Object System.Windows.Forms.DataGridView
$gridApp.Dock = "Fill"
$gridApp.AutoGenerateColumns = $true
$gridApp.AllowUserToAddRows = $false
$gridApp.SelectionMode = "FullRowSelect"

$appPanel = New-Object System.Windows.Forms.Panel
$appPanel.Dock = "Top"
$appPanel.Height = 48

$chkProv = New-Object System.Windows.Forms.CheckBox
$chkProv.Text = "Also remove provisioned (preinstalled) copies"
$chkProv.AutoSize = $true
$chkProv.Location = New-Object System.Drawing.Point(12, 14)

$appHint = New-Object System.Windows.Forms.Label
$appHint.Text = "Protected Store/runtimes are always skipped."
$appHint.AutoSize = $true
$appHint.Location = New-Object System.Drawing.Point(300, 15)

$appPanel.Controls.AddRange(@($chkProv, $appHint))

$tabApps.Controls.Add($gridApp)
$tabApps.Controls.Add($appPanel)

# Tabs
$tabs.TabPages.Add($tabServices)
$tabs.TabPages.Add($tabApps)

# Layout
$form.Controls.Add($tabs)
$form.Controls.Add($statusBox)
$form.Controls.Add($topPanel)

# ----------------------------
# Refresh data bindings
# ----------------------------
function Refresh-All {
    Status "Refreshing data..."

    $svcRows = Get-OptionalServiceRows
    $gridSvc.DataSource = $null
    $gridSvc.DataSource = $svcRows

    $appRows = Get-AppxRows
    $gridApp.DataSource = $null
    $gridApp.DataSource = $appRows

    Status ("Loaded optional services: {0}" -f ($svcRows.Count))
    Status ("Loaded removable Appx matches: {0}" -f ($appRows.Count))
}

# ----------------------------
# Apply button logic
# ----------------------------
$btnApply.Add_Click({
    $dryRun = $chkDryRun.Checked
    $wantRestore = $chkRestore.Checked

    if (-not (Test-IsAdmin)) {
        [System.Windows.Forms.MessageBox]::Show("Not running as Administrator. Service/app removal may fail. Right-click PowerShell > Run as Administrator.", "Admin required")
        Status "Apply attempted without admin. You should run as Administrator."
        return
    }

    # Collect selected rows based on checkbox column "Select"
    $selectedSvc = @()
    foreach ($row in $gridSvc.Rows) {
        if ($row.Cells["Select"].Value -eq $true) {
            $selectedSvc += $row.DataBoundItem
        }
    }

    $selectedApp = @()
    foreach ($row in $gridApp.Rows) {
        if ($row.Cells["Select"].Value -eq $true) {
            $selectedApp += $row.DataBoundItem
        }
    }

    if (($selectedSvc.Count + $selectedApp.Count) -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Nothing selected.", "No selection")
        return
    }

    if (-not $dryRun) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "You're about to APPLY changes.`n`nServices selected: $($selectedSvc.Count)`nApps selected: $($selectedApp.Count)`n`nContinue?",
            "Confirm apply",
            [System.Windows.Forms.MessageBoxButtons]::YesNo
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            Status "Apply cancelled by user."
            return
        }
    }

    if ($wantRestore -and -not $dryRun) {
        $ok = Create-RestorePoint
        if (-not $ok) {
            $c = [System.Windows.Forms.MessageBox]::Show(
                "Restore point failed. Continue anyway?",
                "Restore point failed",
                [System.Windows.Forms.MessageBoxButtons]::YesNo
            )
            if ($c -ne [System.Windows.Forms.DialogResult]::Yes) {
                Status "Apply cancelled due to restore point failure."
                return
            }
        }
    }

    # Apply services (allowlisted only)
    $targetMode = $svcMode.SelectedItem
    $cimMode = switch ($targetMode) { "Auto" { "Auto" } "Manual" { "Manual" } "Disabled" { "Disabled" } default { "Manual" } }

    Status ("Applying service changes (mode={0}, dry-run={1})..." -f $cimMode, $dryRun)
    Apply-ServiceChanges -selectedRows $selectedSvc -targetMode $cimMode -dryRun:$dryRun

    # Apply app removals (denylist matches only)
    Status ("Applying Appx removals (provisioned={0}, dry-run={1})..." -f $chkProv.Checked, $dryRun)
    Apply-AppxRemoval -selectedRows $selectedApp -includeProvisioned:$chkProv.Checked -dryRun:$dryRun

    Status "Done."
    if (-not $dryRun) {
        Status "A restart is recommended."
        [System.Windows.Forms.MessageBox]::Show("Done. Restart recommended.`nUndo script: undo-services.ps1 (if services were changed).`nLog: $Global:LogPath", "Completed")
    } else {
        [System.Windows.Forms.MessageBox]::Show("Dry-run complete. No changes were made.`nLog: $Global:LogPath", "Dry-run")
    }
})

$btnRefresh.Add_Click({ Refresh-All })

# First load
Refresh-All

# Run UI
[void]$form.ShowDialog()
