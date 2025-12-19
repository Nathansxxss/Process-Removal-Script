# Safe Cleanup GUI (conservative)
# - Readable, human-coded
# - Uses ListView (stable) with checkboxes
# - Shows only DETECTED items
# - Dry-run by default
# - Protects critical Windows + Store/runtime components

Write-Host "loading gui"

# ----------------------------
# Base directory + logging (works even if $PSScriptRoot is empty)
# ----------------------------
$BaseDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BaseDir)) { $BaseDir = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($BaseDir)) { $BaseDir = $env:TEMP }

$Global:LogPath = Join-Path $BaseDir ("cleanup-log_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))

function LogLine([string]$msg) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg
    try { $line | Tee-Object -FilePath $Global:LogPath -Append | Out-Null }
    catch { Write-Host $line }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ----------------------------
# PROTECTED: services we will never touch
# ----------------------------
$ProtectedServiceNames = @(
    "DcomLaunch","LSM","SamSs","ProfSvc","UserManager",
    "BrokerInfrastructure","CoreMessagingRegistrar","StateRepository","gpsvc","Schedule","SENS",
    "Dnscache","nsi","Wcmsvc","BFE","mpssvc",
    "WinDefend","WdNisSvc","MDCoreSvc","Sense","wscsvc","SecurityHealthService"
)

# ----------------------------
# PROTECTED: Appx runtimes / Store / Shell (never remove)
# ----------------------------
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
# OPTIONAL SERVICES: allowlist only (only these appear in GUI)
# ----------------------------
$OptionalServices = @(
    @{ Name="WSearch";   Reason="Windows Search indexing (optional). Disabling can slow searches." },
    @{ Name="Spooler";   Reason="Printing service (optional if you never print)." },
    @{ Name="DoSvc";     Reason="Delivery Optimization (optional). Affects update download behavior." },
    @{ Name="DiagTrack"; Reason="Telemetry/diagnostics (optional)." }
)

# ----------------------------
# UPDATED BLOAT DATABASE (Appx)
# We detect installed packages by prefix/pattern and show them with a friendly name + recommendation.
# ----------------------------
$BloatCatalog = @(
    # Microsoft / Windows apps
    @{ Prefix="Microsoft.MicrosoftOfficeHub";          Display="Microsoft 365 (Office hub)";         Recommend="UNINSTALL"; Why="Just a launcher; not required." },
    @{ Prefix="Microsoft.Clipchamp";                   Display="Microsoft Clipchamp";               Recommend="UNINSTALL"; Why="Video editor; safe to remove." },
    @{ Prefix="Microsoft.BingNews";                    Display="Microsoft News";                    Recommend="UNINSTALL"; Why="News app; safe to remove." },
    @{ Prefix="Microsoft.BingWeather";                 Display="Microsoft Weather";                 Recommend="UNINSTALL"; Why="Weather app; safe to remove." },
    @{ Prefix="Microsoft.Getstarted";                  Display="Microsoft Tips";                    Recommend="UNINSTALL"; Why="Tips app; safe to remove." },
    @{ Prefix="Microsoft.WindowsFeedbackHub";          Display="Feedback Hub";                      Recommend="UNINSTALL"; Why="Only for feedback; safe to remove." },
    @{ Prefix="Microsoft.MixedReality.Portal";         Display="Mixed Reality Portal";             Recommend="UNINSTALL"; Why="Only needed for VR/MR." },
    @{ Prefix="Microsoft.Microsoft3DViewer";           Display="3D Viewer";                         Recommend="UNINSTALL"; Why="Old 3D viewer; safe to remove." },
    @{ Prefix="Microsoft.Paint3D";                     Display="Paint 3D";                          Recommend="UNINSTALL"; Why="Not required if you use regular Paint." },
    @{ Prefix="Microsoft.SkypeApp";                    Display="Skype (consumer)";                  Recommend="UNINSTALL"; Why="If you don’t use it." },
    @{ Prefix="Microsoft.549981C3F5F10";               Display="Cortana";                            Recommend="UNINSTALL"; Why="Mostly retired; safe to remove." },
    @{ Prefix="Microsoft.People";                      Display="Microsoft People";                  Recommend="UNINSTALL"; Why="Contacts app; safe to remove." },
    @{ Prefix="Microsoft.Todos";                       Display="Microsoft To Do";                   Recommend="UNINSTALL"; Why="If you don’t use it." },
    @{ Prefix="Microsoft.Whiteboard";                  Display="Microsoft Whiteboard";              Recommend="UNINSTALL"; Why="If you don’t use it." },
    @{ Prefix="Microsoft.MicrosoftJournal";            Display="Microsoft Journal";                 Recommend="UNINSTALL"; Why="If you don’t use it." },
    @{ Prefix="MicrosoftCorporationII.MicrosoftFamily";Display="Microsoft Family";                  Recommend="UNINSTALL"; Why="If you don’t use family features." },
    @{ Prefix="Microsoft.MicrosoftStickyNotes";        Display="Microsoft Sticky Notes";            Recommend="OPTIONAL";  Why="Remove only if you never use it." },
    @{ Prefix="Microsoft.Office.OneNote";              Display="Microsoft OneNote";                 Recommend="OPTIONAL";  Why="Remove only if you never use it." },
    @{ Prefix="Microsoft.MicrosoftSolitaireCollection";Display="Microsoft Solitaire Collection";     Recommend="UNINSTALL"; Why="Safe to remove." },
    @{ Prefix="Microsoft.GetHelp";                     Display="Get Help";                          Recommend="UNINSTALL"; Why="Help app; safe to remove." },
    @{ Prefix="MicrosoftCorporationII.QuickAssist";    Display="Quick Assist";                      Recommend="OPTIONAL";  Why="Keep if you use remote help." },
    @{ Prefix="Microsoft.Windows.DevHome";             Display="Dev Home";                          Recommend="OPTIONAL";  Why="Only for dev dashboard." },

    # Media legacy names
    @{ Prefix="Microsoft.ZuneVideo";                   Display="Movies & TV";                       Recommend="UNINSTALL"; Why="Safe to remove." },
    @{ Prefix="Microsoft.ZuneMusic";                   Display="Groove Music / Media Player";       Recommend="UNINSTALL"; Why="Safe to remove if you don’t use it." },

    # Xbox / gaming (optional, with dependencies warning)
    @{ Prefix="Microsoft.GamingApp";                   Display="Xbox app";                          Recommend="OPTIONAL";  Why="Remove if you don’t use Game Pass/Xbox." },
    @{ Prefix="Microsoft.XboxGamingOverlay";           Display="Xbox Game Bar";                     Recommend="OPTIONAL";  Why="Remove if you don’t record/overlay." },
    @{ Prefix="Microsoft.XboxIdentityProvider";        Display="Xbox Identity Provider";            Recommend="OPTIONAL";  Why="Keep if any Xbox sign-in/games need it." },
    @{ Prefix="Microsoft.GamingServices";              Display="Gaming Services";                   Recommend="OPTIONAL";  Why="Keep if you install games from Store/Xbox." },

    # Teams personal (varies)
    @{ Prefix="MicrosoftTeams";                        Display="Microsoft Teams (personal)";        Recommend="UNINSTALL"; Why="Not required." },

    # Common third-party promos/bloat (show only if installed)
    @{ Prefix="SpotifyAB.SpotifyMusic";                Display="Spotify";                           Recommend="UNINSTALL"; Why="Promo app; safe to remove if unwanted." },
    @{ Prefix="4DF9E0F8.Netflix";                      Display="Netflix";                           Recommend="UNINSTALL"; Why="Safe to remove." },
    @{ Prefix="AmazonVideo.PrimeVideo";                Display="Prime Video";                       Recommend="UNINSTALL"; Why="Safe to remove." },
    @{ Prefix="Disney.37853FC22B2CE";                  Display="Disney+";                           Recommend="UNINSTALL"; Why="Safe to remove." },

    # OEM / HP / Dell / misc from your earlier list
    @{ Prefix="AD2F1837.HPSupportAssistant";           Display="HP Support Assistant";              Recommend="UNINSTALL"; Why="OEM helper; optional." },
    @{ Prefix="DellInc.DellSupportAssistforPCs";       Display="Dell SupportAssist";                Recommend="UNINSTALL"; Why="OEM helper; optional." },

    # Casual game promos (show only if installed)
    @{ Prefix="king.com.CandyCrushSaga";               Display="Candy Crush";                       Recommend="UNINSTALL"; Why="Promo game; safe to remove." },
    @{ Prefix="king.com.CandyCrushSodaSaga";           Display="Candy Crush Soda";                  Recommend="UNINSTALL"; Why="Promo game; safe to remove." },
    @{ Prefix="king.com.CandyCrushFriends";            Display="Candy Crush Friends";               Recommend="UNINSTALL"; Why="Promo game; safe to remove." }
)

# ----------------------------
# Tweaks (safe toggles)
# ----------------------------
function Get-WidgetsStatus {
    # 0 = off, 1 = on (for this value), but not always present.
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $name = "TaskbarDa"
    $val = (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
    if ($null -eq $val) { return "Unknown" }
    return ($(if ($val -eq 0) { "Disabled" } else { "Enabled" }))
}

function Set-WidgetsEnabled([bool]$enable) {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    $value = $(if ($enable) { 1 } else { 0 })
    Set-ItemProperty -Path $path -Name "TaskbarDa" -Type DWord -Value $value
}

function Get-OneDriveStartupStatus {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $name = "OneDrive"
    $val = (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
    return $(if ($val) { "Enabled" } else { "Disabled/Not present" })
}

function Disable-OneDriveStartup {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $path -Name "OneDrive" -ErrorAction SilentlyContinue
}

# ----------------------------
# Restore point + undo scripts
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
        "# Undo script generated by Safe Cleanup GUI",
        "# Restores service StartupType values captured before changes.",
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

function Write-TweaksUndoScript([hashtable]$before) {
    $undoPath = Join-Path $BaseDir "undo-tweaks.ps1"
    $lines = @(
        "# Undo script generated by Safe Cleanup GUI",
        "# Restores tweaks captured before changes.",
        ""
    )

    if ($before.ContainsKey("WidgetsEnabled")) {
        $v = $(if ($before["WidgetsEnabled"]) { '$true' } else { '$false' })
        $lines += "Set-ItemProperty -Path `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced`" -Name `"TaskbarDa`" -Type DWord -Value $(if ($before["WidgetsEnabled"]) { 1 } else { 0 })"
    }

    if ($before.ContainsKey("OneDriveRunValue")) {
        $val = $before["OneDriveRunValue"]
        if ($val) {
            $lines += "Set-ItemProperty -Path `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`" -Name `"OneDrive`" -Value `"$val`""
        } else {
            $lines += "Remove-ItemProperty -Path `"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`" -Name `"OneDrive`" -ErrorAction SilentlyContinue"
        }
    }

    $lines | Out-File -Encoding UTF8 -FilePath $undoPath
    LogLine "Undo script written: $undoPath"
    return $undoPath
}

# ----------------------------
# Load WinForms
# ----------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
} catch {
    Write-Host "GUI failed to load: $($_.Exception.Message)" -ForegroundColor Red
    return
}

Write-Host "gui loaded, enjoy!"
LogLine "GUI loaded. Log: $Global:LogPath"

# ----------------------------
# GUI setup
# ----------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Safe Cleanup GUI"
$form.Size = New-Object System.Drawing.Size(1050, 720)
$form.StartPosition = "CenterScreen"

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = "Top"
$topPanel.Height = 70

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
    $lblAdmin.Text = "Admin: NO (Apply will fail without admin)"
    $lblAdmin.ForeColor = [System.Drawing.Color]::DarkRed
}

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Size = New-Object System.Drawing.Size(120, 30)
$btnRefresh.Location = New-Object System.Drawing.Point(800, 18)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Apply Selected"
$btnApply.Size = New-Object System.Drawing.Size(150, 30)
$btnApply.Location = New-Object System.Drawing.Point(930, 18)

$topPanel.Controls.AddRange(@($chkDryRun, $chkRestore, $lblAdmin, $btnRefresh, $btnApply))

$status = New-Object System.Windows.Forms.TextBox
$status.Dock = "Bottom"
$status.Height = 120
$status.Multiline = $true
$status.ReadOnly = $true
$status.ScrollBars = "Vertical"

function Status([string]$msg) {
    $status.AppendText($msg + [Environment]::NewLine)
    LogLine $msg
}
Status "Log: $Global:LogPath"

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = "Fill"

# ----------------------------
# Tab: Optional Services
# ----------------------------
$tabServices = New-Object System.Windows.Forms.TabPage
$tabServices.Text = "Optional Services"

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
$svcHint.Text = "Only allowlisted optional services are shown."
$svcHint.AutoSize = $true
$svcHint.Location = New-Object System.Drawing.Point(170, 15)

$svcCount = New-Object System.Windows.Forms.Label
$svcCount.AutoSize = $true
$svcCount.Location = New-Object System.Drawing.Point(820, 15)

$svcPanel.Controls.AddRange(@($svcMode, $svcHint, $svcCount))

$svcList = New-Object System.Windows.Forms.ListView
$svcList.Dock = "Fill"
$svcList.View = "Details"
$svcList.FullRowSelect = $true
$svcList.GridLines = $true
$svcList.CheckBoxes = $true
$null = $svcList.Columns.Add("Service", 160)
$null = $svcList.Columns.Add("Display Name", 360)
$null = $svcList.Columns.Add("StartMode", 90)
$null = $svcList.Columns.Add("State", 90)
$null = $svcList.Columns.Add("Why", 520)

$tabServices.Controls.Add($svcList)
$tabServices.Controls.Add($svcPanel)

# ----------------------------
# Tab: Bloat Apps (Appx)
# ----------------------------
$tabApps = New-Object System.Windows.Forms.TabPage
$tabApps.Text = "Bloat Apps (Appx)"

$appPanel = New-Object System.Windows.Forms.Panel
$appPanel.Dock = "Top"
$appPanel.Height = 48

$chkProv = New-Object System.Windows.Forms.CheckBox
$chkProv.Text = "Also remove provisioned (preinstalled) copies"
$chkProv.AutoSize = $true
$chkProv.Location = New-Object System.Drawing.Point(12, 14)

$appHint = New-Object System.Windows.Forms.Label
$appHint.Text = "Only installed packages appear. Protected Store/runtimes are skipped."
$appHint.AutoSize = $true
$appHint.Location = New-Object System.Drawing.Point(330, 15)

$appCount = New-Object System.Windows.Forms.Label
$appCount.AutoSize = $true
$appCount.Location = New-Object System.Drawing.Point(820, 15)

$appPanel.Controls.AddRange(@($chkProv, $appHint, $appCount))

$appList = New-Object System.Windows.Forms.ListView
$appList.Dock = "Fill"
$appList.View = "Details"
$appList.FullRowSelect = $true
$appList.GridLines = $true
$appList.CheckBoxes = $true
$null = $appList.Columns.Add("App", 260)
$null = $appList.Columns.Add("Recommendation", 110)
$null = $appList.Columns.Add("Why", 420)
$null = $appList.Columns.Add("Package", 520)

$tabApps.Controls.Add($appList)
$tabApps.Controls.Add($appPanel)

# ----------------------------
# Tab: Tweaks
# ----------------------------
$tabTweaks = New-Object System.Windows.Forms.TabPage
$tabTweaks.Text = "Tweaks"

$tweakList = New-Object System.Windows.Forms.ListView
$tweakList.Dock = "Fill"
$tweakList.View = "Details"
$tweakList.FullRowSelect = $true
$tweakList.GridLines = $true
$tweakList.CheckBoxes = $true
$null = $tweakList.Columns.Add("Tweak", 260)
$null = $tweakList.Columns.Add("Action", 140)
$null = $tweakList.Columns.Add("Current", 180)
$null = $tweakList.Columns.Add("Notes", 520)

$tabTweaks.Controls.Add($tweakList)

# Add tabs
$tabs.TabPages.AddRange(@($tabServices, $tabApps, $tabTweaks))

# ----------------------------
# Populate
# ----------------------------
function Refresh-Services {
    $svcList.Items.Clear()
    $svcCim = Get-CimInstance Win32_Service
    $added = 0

    foreach ($item in $OptionalServices) {
        $name = $item.Name
        if ($ProtectedServiceNames -contains $name) { continue }

        $svc = $svcCim | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $svc) { continue }

        $li = New-Object System.Windows.Forms.ListViewItem($svc.Name)
        [void]$li.SubItems.Add($svc.DisplayName)
        [void]$li.SubItems.Add($svc.StartMode)
        [void]$li.SubItems.Add($svc.State)
        [void]$li.SubItems.Add($item.Reason)
        $li.Tag = $svc.Name

        $null = $svcList.Items.Add($li)
        $added++
    }

    $svcCount.Text = "Count: $added"
    Status "Loaded optional services: $added"
}

function Refresh-Apps {
    $appList.Items.Clear()

    # If -AllUsers is blocked on your edition/policy, fall back automatically.
    $installed = Get-AppxPackage -AllUsers
    if (-not $installed) { $installed = Get-AppxPackage }

    $added = 0

    foreach ($entry in $BloatCatalog) {
        $prefix = $entry.Prefix
        if (Is-ProtectedAppxName $prefix) { continue }

        $matches = $installed | Where-Object { $_.Name -eq $prefix -or $_.Name -like "$prefix*" }
        foreach ($m in $matches) {
            if (Is-ProtectedAppxName $m.Name) { continue }

            $li = New-Object System.Windows.Forms.ListViewItem($entry.Display)
            [void]$li.SubItems.Add($entry.Recommend)
            [void]$li.SubItems.Add($entry.Why)
            [void]$li.SubItems.Add($m.PackageFullName)

            $li.Tag = [PSCustomObject]@{
                Name            = $m.Name
                PackageFullName = $m.PackageFullName
                Prefix          = $prefix
            }

            $null = $appList.Items.Add($li)
            $added++
        }
    }

    $appCount.Text = "Count: $added"
    Status "Loaded removable Appx matches: $added"
}

function Refresh-Tweaks {
    $tweakList.Items.Clear()
    $added = 0

    $widgets = Get-WidgetsStatus
    $li1 = New-Object System.Windows.Forms.ListViewItem("Widgets / MSN Start feed")
    [void]$li1.SubItems.Add("DISABLE")
    [void]$li1.SubItems.Add($widgets)
    [void]$li1.SubItems.Add("Disables taskbar Widgets (reduces Start/feed noise).")
    $li1.Tag = "DisableWidgets"
    $null = $tweakList.Items.Add($li1)
    $added++

    $onedrive = Get-OneDriveStartupStatus
    $li2 = New-Object System.Windows.Forms.ListViewItem("OneDrive startup")
    [void]$li2.SubItems.Add("DISABLE")
    [void]$li2.SubItems.Add($onedrive)
    [void]$li2.SubItems.Add("Disables OneDrive auto-start (does not uninstall OneDrive).")
    $li2.Tag = "DisableOneDriveStartup"
    $null = $tweakList.Items.Add($li2)
    $added++

    Status "Loaded tweaks: $added"
}

function Refresh-All {
    Status "Refreshing..."
    Refresh-Services
    Refresh-Apps
    Refresh-Tweaks
}

# ----------------------------
# Apply selected
# ----------------------------
function Apply-Selected {
    $dryRun = $chkDryRun.Checked
    $wantRestore = $chkRestore.Checked

    if (-not (Test-IsAdmin)) {
        [System.Windows.Forms.MessageBox]::Show("Run PowerShell as Administrator to apply changes.", "Admin required") | Out-Null
        Status "Apply blocked: not admin."
        return
    }

    $selectedServiceNames = @()
    foreach ($it in $svcList.CheckedItems) { $selectedServiceNames += [string]$it.Tag }

    $selectedApps = @()
    foreach ($it in $appList.CheckedItems) { $selectedApps += $it.Tag }

    $selectedTweaks = @()
    foreach ($it in $tweakList.CheckedItems) { $selectedTweaks += [string]$it.Tag }

    if (($selectedServiceNames.Count + $selectedApps.Count + $selectedTweaks.Count) -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Nothing selected.", "No selection") | Out-Null
        return
    }

    if (-not $dryRun) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Apply changes?`n`nServices: $($selectedServiceNames.Count)`nApps: $($selectedApps.Count)`nTweaks: $($selectedTweaks.Count)",
            "Confirm",
            [System.Windows.Forms.MessageBoxButtons]::YesNo
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            Status "Apply cancelled."
            return
        }
    }

    # Capture tweak state for undo
    $beforeTweaks = @{}
    $beforeTweaks["WidgetsEnabled"] = ((Get-WidgetsStatus) -ne "Disabled")
    $runPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $beforeTweaks["OneDriveRunValue"] = (Get-ItemProperty -Path $runPath -Name "OneDrive" -ErrorAction SilentlyContinue).OneDrive

    if ($wantRestore -and -not $dryRun) {
        $ok = Create-RestorePoint
        if (-not $ok) {
            $c = [System.Windows.Forms.MessageBox]::Show("Restore point failed. Continue anyway?", "Restore point failed", [System.Windows.Forms.MessageBoxButtons]::YesNo)
            if ($c -ne [System.Windows.Forms.DialogResult]::Yes) {
                Status "Apply cancelled (restore point failed)."
                return
            }
        }
    }

    # Services changes
    $beforeServices = @()
    if ($selectedServiceNames.Count -gt 0) {
        $cim = Get-CimInstance Win32_Service
        $targetMode = [string]$svcMode.SelectedItem

        foreach ($svcName in $selectedServiceNames) {
            if ($ProtectedServiceNames -contains $svcName) {
                Status "SKIP protected service: $svcName"
                continue
            }

            $svc = $cim | Where-Object { $_.Name -eq $svcName } | Select-Object -First 1
            if (-not $svc) { continue }

            $beforeServices += [PSCustomObject]@{ Name=$svc.Name; StartMode=$svc.StartMode }
            Status "Service: $svcName -> $targetMode (dry-run=$dryRun)"

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
    }

    # Apps removal
    if ($selectedApps.Count -gt 0) {
        foreach ($app in $selectedApps) {
            if (Is-ProtectedAppxName $app.Name) {
                Status "SKIP protected Appx: $($app.Name)"
                continue
            }

            Status "Remove Appx: $($app.PackageFullName) (dry-run=$dryRun)"
            if (-not $dryRun) {
                try { Remove-AppxPackage -AllUsers -Package $app.PackageFullName -ErrorAction Stop }
                catch { Status "  FAILED: $($_.Exception.Message)" }
            }
        }

        if ($chkProv.Checked) {
            $prov = Get-AppxProvisionedPackage -Online
            foreach ($app in $selectedApps) {
                $prefix = $app.Prefix
                if (Is-ProtectedAppxName $prefix) { continue }

                $matches = $prov | Where-Object { $_.DisplayName -eq $prefix -or $_.DisplayName -like "$prefix*" }
                foreach ($m in $matches) {
                    Status "Remove Provisioned: $($m.PackageName) (dry-run=$dryRun)"
                    if (-not $dryRun) {
                        try { Remove-AppxProvisionedPackage -Online -PackageName $m.PackageName | Out-Null }
                        catch { Status "  FAILED: $($_.Exception.Message)" }
                    }
                }
            }
        }
    }

    # Tweaks apply
    if ($selectedTweaks.Count -gt 0) {
        foreach ($t in $selectedTweaks) {
            switch ($t) {
                "DisableWidgets" {
                    Status "Tweak: Disable Widgets (dry-run=$dryRun)"
                    if (-not $dryRun) { Set-WidgetsEnabled $false }
                }
                "DisableOneDriveStartup" {
                    Status "Tweak: Disable OneDrive startup (dry-run=$dryRun)"
                    if (-not $dryRun) { Disable-OneDriveStartup }
                }
            }
        }
    }

    # Write undo scripts (only when actually changing)
    if (-not $dryRun) {
        if ($beforeServices.Count -gt 0) { [void](Write-ServiceUndoScript $beforeServices) }
        if ($selectedTweaks.Count -gt 0) { [void](Write-TweaksUndoScript $beforeTweaks) }
    }

    Status "Done."
    if ($dryRun) {
        [System.Windows.Forms.MessageBox]::Show("Dry-run complete. No changes were made.", "Dry-run") | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Done. Restart recommended.`nLog: $Global:LogPath`nUndo: undo-services.ps1 / undo-tweaks.ps1 (if created)",
            "Completed"
        ) | Out-Null
    }

    Refresh-All
}

# Buttons
$btnRefresh.Add_Click({ Refresh-All })
$btnApply.Add_Click({ Apply-Selected })

# Layout
$form.Controls.Add($tabs)
$form.Controls.Add($status)
$form.Controls.Add($topPanel)

# Start
Refresh-All
[void]$form.ShowDialog()
