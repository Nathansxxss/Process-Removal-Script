# Reviewed and confirmed: conservative GUI tool.
# - Works even when $PSScriptRoot is empty (IEX / copy-paste)
# - Fixes blank DataGridView by binding DataTables
# - Dry-run by default
# - Protects critical Windows + Store runtime components
# - Prints "loading gui" then "gui loaded, enjoy!"

Write-Host "loading gui"

# ----------------------------
# Robust base directory (fixes $PSScriptRoot empty)
# ----------------------------
$BaseDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BaseDir)) {
    $BaseDir = (Get-Location).Path
}
if ([string]::IsNullOrWhiteSpace($BaseDir)) {
    $BaseDir = $env:TEMP
}

# ----------------------------
# Logging (never hard-crash if log path fails)
# ----------------------------
$Global:LogPath = Join-Path $BaseDir ("cleanup-log_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))

function LogLine([string]$msg) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg
    try {
        $line | Tee-Object -FilePath $Global:LogPath -Append | Out-Null
    } catch {
        Write-Host $line
    }
}

# ----------------------------
# Admin check
# ----------------------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

# Appx packages that must never be removed (Store + runtimes + shell)
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
# OPTIONAL SERVICES (explicit allowlist only)
# Only these appear in the GUI for service changes.
# ----------------------------
$OptionalServices = @(
    @{ Name="WSearch";   Reason="Windows Search indexing (optional). Disabling can slow searches." },
    @{ Name="Spooler";   Reason="Printing service (optional if you never print)." },
    @{ Name="DoSvc";     Reason="Delivery Optimization (optional). Affects update download behavior." },
    @{ Name="DiagTrack"; Reason="Telemetry/diagnostics (optional)." }
)

# ----------------------------
# APPX DENYLIST (your bloat list)
# Matches as prefixes (Name or Name*)
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
# Apply actions (still conservative)
# ----------------------------
function Create-RestorePoint {
    try {
        LogLine "Creating restore point..."
        Checkpoint-Computer -Description "Before cleanup GUI changes" -RestorePointType "MODIFY_SETTINGS"
        LogLine "Restore point created."
        return $true
    } catch {
        LogLine "Restore point FAILED: $($_.Exception.Message)"
        return $false
    }
}

function Write-ServiceUndoScript($beforeStates) {
    $undoPath = Join-Path $BaseDir "undo-services.ps1"
    $lines = @(
        "# Undo script generated by cleanup GUI",
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
    LogLine "Undo script written: $undoPath"
    return $undoPath
}

function Apply-ServiceChanges {
    param(
        [string[]]$ServiceNames,
        [string]$TargetMode,
        [bool]$DryRun
    )

    if (-not $ServiceNames -or $ServiceNames.Count -eq 0) { return $null }

    $cim = Get-CimInstance Win32_Service
    $before = @()

    foreach ($svcName in $ServiceNames) {
        if ($ProtectedServiceNames -contains $svcName) {
            LogLine "SKIP protected service: $svcName"
            continue
        }

        $svc = $cim | Where-Object { $_.Name -eq $svcName } | Select-Object -First 1
        if (-not $svc) { continue }

        $before += [PSCustomObject]@{ Name=$svc.Name; StartMode=$svc.StartMode }

        LogLine ("Service: {0} -> {1} (dry-run={2})" -f $svcName, $TargetMode, $DryRun)

        if (-not $DryRun) {
            $psMode = switch ($TargetMode) {
                "Auto"     { "Automatic" }
                "Manual"   { "Manual" }
                "Disabled" { "Disabled" }
                default    { "Manual" }
            }
            Set-Service -Name $svcName -StartupType $psMode
        }
    }

    if ($before.Count -gt 0) {
        return Write-ServiceUndoScript $before
    }
    return $null
}

function Apply-AppxRemoval {
    param(
        [string[]]$SelectedAppNames,
        [string[]]$SelectedPackageFullNames,
        [bool]$IncludeProvisioned,
        [bool]$DryRun
    )

    if (-not $SelectedPackageFullNames -or $SelectedPackageFullNames.Count -eq 0) { return }

    foreach ($full in $SelectedPackageFullNames) {
        LogLine ("Remove Appx: {0} (dry-run={1})" -f $full, $DryRun)

        if (-not $DryRun) {
            try {
                Remove-AppxPackage -AllUsers -Package $full -ErrorAction Stop
            } catch {
                LogLine "  FAILED Remove-AppxPackage: $($_.Exception.Message)"
            }
        }
    }

    if ($IncludeProvisioned -and $SelectedAppNames -and $SelectedAppNames.Count -gt 0) {
        $prov = Get-AppxProvisionedPackage -Online
        foreach ($prefix in ($SelectedAppNames | Sort-Object -Unique)) {
            if (Is-ProtectedAppxName $prefix) { continue }

            $matches = $prov | Where-Object { $_.DisplayName -eq $prefix -or $_.DisplayName -like "$prefix*" }
            foreach ($m in $matches) {
                LogLine ("Remove Provisioned: {0} (dry-run={1})" -f $m.PackageName, $DryRun)
                if (-not $DryRun) {
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
# Load GUI assemblies + System.Data (for DataTables)
# ----------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Add-Type -AssemblyName System.Data -ErrorAction Stop
} catch {
    Write-Host "GUI failed to load. Error: $($_.Exception.Message)" -ForegroundColor Red
    LogLine "GUI failed to load: $($_.Exception.Message)"
    return
}

# ----------------------------
# DataTable builders (fixes blank grids)
# ----------------------------
function Get-OptionalServicesTable {
    $dt = New-Object System.Data.DataTable
    [void]$dt.Columns.Add("Select",  [bool])
    [void]$dt.Columns.Add("Name",    [string])
    [void]$dt.Columns.Add("Display", [string])
    [void]$dt.Columns.Add("StartMode",[string])
    [void]$dt.Columns.Add("State",   [string])
    [void]$dt.Columns.Add("Reason",  [string])

    $svcCim = Get-CimInstance Win32_Service

    foreach ($item in $OptionalServices) {
        $name = $item.Name
        if ($ProtectedServiceNames -contains $name) { continue }

        $svc = $svcCim | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $svc) { continue }

        $row = $dt.NewRow()
        $row["Select"]   = $false
        $row["Name"]     = $svc.Name
        $row["Display"]  = $svc.DisplayName
        $row["StartMode"]= $svc.StartMode
        $row["State"]    = $svc.State
        $row["Reason"]   = $item.Reason
        [void]$dt.Rows.Add($row)
    }

    return $dt
}

function Get-AppxTable {
    $dt = New-Object System.Data.DataTable
    [void]$dt.Columns.Add("Select",         [bool])
    [void]$dt.Columns.Add("Name",           [string])
    [void]$dt.Columns.Add("PackageFullName",[string])
    [void]$dt.Columns.Add("Publisher",      [string])

    $installed = Get-AppxPackage -AllUsers

    foreach ($prefix in $AppxDenylist) {
        if (Is-ProtectedAppxName $prefix) { continue }

        $matches = $installed | Where-Object { $_.Name -eq $prefix -or $_.Name -like "$prefix*" }
        foreach ($m in $matches) {
            if (Is-ProtectedAppxName $m.Name) { continue }

            $row = $dt.NewRow()
            $row["Select"]          = $false
            $row["Name"]            = $m.Name
            $row["PackageFullName"] = $m.PackageFullName
            $row["Publisher"]       = $m.Publisher
            [void]$dt.Rows.Add($row)
        }
    }

    return $dt
}

# ----------------------------
# Build GUI
# ----------------------------
$guiLoaded = $false

try {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Safe Cleanup GUI"
    $form.Size = New-Object System.Drawing.Size(980, 650)
    $form.StartPosition = "CenterScreen"

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = "Fill"

    $tabServices = New-Object System.Windows.Forms.TabPage
    $tabServices.Text = "Optional Services"

    $tabApps = New-Object System.Windows.Forms.TabPage
    $tabApps.Text = "Bloat Apps (Appx)"

    # Top panel
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
        $lblAdmin.Text = "Admin: NO (run as Administrator for Apply)"
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

    # Services grid
    $gridSvc = New-Object System.Windows.Forms.DataGridView
    $gridSvc.Dock = "Fill"
    $gridSvc.AllowUserToAddRows = $false
    $gridSvc.SelectionMode = "FullRowSelect"
    $gridSvc.AutoSizeColumnsMode = "Fill"

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
    $svcHint.Text = "Only explicit optional services appear here."
    $svcHint.AutoSize = $true
    $svcHint.Location = New-Object System.Drawing.Point(170, 15)

    $svcPanel.Controls.AddRange(@($svcMode, $svcHint))

    $tabServices.Controls.Add($gridSvc)
    $tabServices.Controls.Add($svcPanel)

    # Apps grid
    $gridApp = New-Object System.Windows.Forms.DataGridView
    $gridApp.Dock = "Fill"
    $gridApp.AllowUserToAddRows = $false
    $gridApp.SelectionMode = "FullRowSelect"
    $gridApp.AutoSizeColumnsMode = "Fill"

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
    $appHint.Location = New-Object System.Drawing.Point(330, 15)

    $appPanel.Controls.AddRange(@($chkProv, $appHint))

    $tabApps.Controls.Add($gridApp)
    $tabApps.Controls.Add($appPanel)

    # Tabs
    $tabs.TabPages.Add($tabServices)
    $tabs.TabPages.Add($tabApps)

    $form.Controls.Add($tabs)
    $form.Controls.Add($statusBox)
    $form.Controls.Add($topPanel)

    function Refresh-All {
        Status "Refreshing data..."

        $svcTable = Get-OptionalServicesTable
        $gridSvc.DataSource = $null
        $gridSvc.DataSource = $svcTable

        $appTable = Get-AppxTable
        $gridApp.DataSource = $null
        $gridApp.DataSource = $appTable

        # Make the Select columns appear as checkboxes
        if ($gridSvc.Columns["Select"]) { $gridSvc.Columns["Select"].ReadOnly = $false }
        if ($gridApp.Columns["Select"]) { $gridApp.Columns["Select"].ReadOnly = $false }

        Status ("Loaded optional services: {0}" -f $svcTable.Rows.Count)
        Status ("Loaded removable Appx matches: {0}" -f $appTable.Rows.Count)
    }

    $btnRefresh.Add_Click({ Refresh-All })

    $btnApply.Add_Click({
        $dryRun = $chkDryRun.Checked
        $wantRestore = $chkRestore.Checked

        if (-not (Test-IsAdmin)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Run PowerShell as Administrator to apply changes.",
                "Admin required"
            ) | Out-Null
            Status "Apply blocked: not running as Administrator."
            return
        }

        # Collect selected services/apps directly from grid cell values (works with DataTables)
        $selectedServiceNames = @()
        foreach ($row in $gridSvc.Rows) {
            if ($row.IsNewRow) { continue }
            if ([bool]$row.Cells["Select"].Value -eq $true) {
                $selectedServiceNames += [string]$row.Cells["Name"].Value
            }
        }

        $selectedAppNames = @()
        $selectedPackageFullNames = @()
        foreach ($row in $gridApp.Rows) {
            if ($row.IsNewRow) { continue }
            if ([bool]$row.Cells["Select"].Value -eq $true) {
                $selectedAppNames += [string]$row.Cells["Name"].Value
                $selectedPackageFullNames += [string]$row.Cells["PackageFullName"].Value
            }
        }

        if (($selectedServiceNames.Count + $selectedPackageFullNames.Count) -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Nothing selected.", "No selection") | Out-Null
            return
        }

        if (-not $dryRun) {
            $confirm = [System.Windows.Forms.MessageBox]::Show(
                "Apply changes?`n`nServices: $($selectedServiceNames.Count)`nApps: $($selectedPackageFullNames.Count)",
                "Confirm",
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

        $targetMode = [string]$svcMode.SelectedItem
        Status ("Applying service changes (mode={0}, dry-run={1})..." -f $targetMode, $dryRun)
        $undoPath = Apply-ServiceChanges -ServiceNames $selectedServiceNames -TargetMode $targetMode -DryRun:$dryRun

        Status ("Applying Appx removals (provisioned={0}, dry-run={1})..." -f $chkProv.Checked, $dryRun)
        Apply-AppxRemoval -SelectedAppNames $selectedAppNames -SelectedPackageFullNames $selectedPackageFullNames -IncludeProvisioned:$chkProv.Checked -DryRun:$dryRun

        Status "Done."
        if (-not $dryRun) {
            $msg = "Done. Restart recommended.`nLog: $Global:LogPath"
            if ($undoPath) { $msg += "`nUndo: $undoPath" }
            [System.Windows.Forms.MessageBox]::Show($msg, "Completed") | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("Dry-run complete. No changes were made.", "Dry-run") | Out-Null
        }
    })

    Refresh-All

    $guiLoaded = ($form -ne $null -and $tabs -ne $null -and $gridSvc -ne $null -and $gridApp -ne $null)
} catch {
    Write-Host "GUI build failed: $($_.Exception.Message)" -ForegroundColor Red
    LogLine "GUI build failed: $($_.Exception.Message)"
    return
}

if ($guiLoaded) {
    Write-Host "gui loaded, enjoy!"
    LogLine "GUI loaded successfully."
} else {
    Write-Host "GUI failed to load." -ForegroundColor Red
    LogLine "GUI failed to load (unknown reason)."
    return
}

# Show UI
[void]$form.ShowDialog()
