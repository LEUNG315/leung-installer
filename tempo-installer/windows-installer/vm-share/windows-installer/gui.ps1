#Requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$InstallerPath = Join-Path $ScriptDir 'install.ps1'
$CodexHome = Join-Path $env:USERPROFILE '.codex'
$ClaudeHome = Join-Path $env:USERPROFILE '.claude'
$GeminiHome = Join-Path $env:USERPROFILE '.gemini'
$LogDir = Join-Path $env:USERPROFILE '.leung\logs'

function Test-CommandAvailable([string]$Name) { try { $null = Get-Command $Name -ErrorAction Stop; return $true } catch { return $false } }
function Get-CommandVersion([string]$Name) { try { $o = & $Name --version 2>&1; if ($LASTEXITCODE -eq 0 -and $o) { return ($o | Select-Object -First 1).ToString().Trim() } } catch {}; return '' }
function Test-CodexDesktopInstalled {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe'),
        (Join-Path $env:PROGRAMFILES 'Codex\Codex.exe'),
        (Join-Path ${env:PROGRAMFILES(x86)} 'Codex\Codex.exe')
    )
    foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return $true } }
    try {
        $appx = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Codex' -or $_.Publisher -match 'OpenAI' }
        if ($appx) { return $true }
    } catch {}
    return $false
}
function Get-StatusText([string]$name) {
    switch ($name) {
        'winget'  { if (Test-CommandAvailable 'winget')  { return 'Available' } else { return 'Missing' } }
        'node'    { if (Test-CommandAvailable 'node')    { $v = Get-CommandVersion 'node'; return $(if ($v) { "Installed ($v)" } else { 'Installed' }) } else { return 'Missing' } }
        'npm'     { if (Test-CommandAvailable 'npm')     { $v = Get-CommandVersion 'npm'; return $(if ($v) { "Installed ($v)" } else { 'Installed' }) } else { return 'Missing' } }
        'codex'   { if (Test-CommandAvailable 'codex')   { $v = Get-CommandVersion 'codex'; return $(if ($v) { "Installed ($v)" } else { 'Installed' }) } else { return 'Not found' } }
        'claude'  { if (Test-CommandAvailable 'claude')  { $v = Get-CommandVersion 'claude'; return $(if ($v) { "Installed ($v)" } else { 'Installed' }) } else { return 'Not found' } }
        'gemini'  { if (Test-CommandAvailable 'gemini')  { $v = Get-CommandVersion 'gemini'; return $(if ($v) { "Installed ($v)" } else { 'Installed' }) } else { return 'Not found' } }
        'desktop' { if (Test-CodexDesktopInstalled)      { return 'Installed' } else { return 'Not found' } }
    }
    return 'Unknown'
}
function Get-ConfigStatusText([string]$name) {
    switch ($name) {
        'codex' {
            $config = Join-Path $CodexHome 'config.toml'
            $auth = Join-Path $CodexHome 'auth.json'
            if ((Test-Path $config) -and (Test-Path $auth)) { return 'Ready (config + auth)' }
            if ((Test-Path $config) -or (Test-Path $auth)) { return 'Partial' }
            return 'Missing'
        }
        'claude' {
            $config = Join-Path $ClaudeHome 'settings.json'
            if (Test-Path $config) { return 'Ready' }
            return 'Missing'
        }
        'gemini' {
            $config = Join-Path $GeminiHome 'settings.json'
            $envFile = Join-Path $GeminiHome '.env'
            if ((Test-Path $config) -and (Test-Path $envFile)) { return 'Ready (settings + env)' }
            if ((Test-Path $config) -or (Test-Path $envFile)) { return 'Partial' }
            return 'Missing'
        }
        'logs' {
            if (Test-Path $LogDir) {
                $count = @(Get-ChildItem -Path $LogDir -Filter '*.log' -ErrorAction SilentlyContinue).Count
                if ($count -gt 0) { return "Ready ($count logs)" }
                return 'Ready (empty)'
            }
            return 'Missing'
        }
    }
    return 'Unknown'
}
function Open-DirectorySafe([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    Start-Process explorer.exe $Path
}
function New-Label($text, $x, $y, $w=120) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $label.Size = New-Object System.Drawing.Size($w, 20)
    return $label
}
function New-TextBox($x, $y, $w, $password=$false) {
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point($x, $y)
    $tb.Size = New-Object System.Drawing.Size($w, 22)
    $tb.UseSystemPasswordChar = $password
    return $tb
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'AI Tools Installer'
$form.Size = New-Object System.Drawing.Size(780, 1000)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::WhiteSmoke

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Windows AI Tools Installer'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 15)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = 'LEUNG template + official Node.js/npm install + config/auth + stronger self-check'
$lblSub.Location = New-Object System.Drawing.Point(22, 48)
$lblSub.AutoSize = $true
$lblSub.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblSub)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = 'Tip: select components first, then fill only the matching API keys. Full default model names are shown below.'
$lblHint.Location = New-Object System.Drawing.Point(22, 68)
$lblHint.Size = New-Object System.Drawing.Size(720, 18)
$lblHint.ForeColor = [System.Drawing.Color]::SteelBlue
$form.Controls.Add($lblHint)

$grpStatus = New-Object System.Windows.Forms.GroupBox
$grpStatus.Text = 'System Status'
$grpStatus.Location = New-Object System.Drawing.Point(20, 95)
$grpStatus.Size = New-Object System.Drawing.Size(720, 125)
$form.Controls.Add($grpStatus)

$statusNames = @('winget','node','npm','codex','claude','gemini','desktop')
$statusLabels = @{}
$statusPositions = @(
    @{Name='winget'; X=15; Y=25; Text='winget'},
    @{Name='node'; X=15; Y=55; Text='node'},
    @{Name='npm'; X=15; Y=85; Text='npm'},
    @{Name='codex'; X=255; Y=25; Text='Codex CLI'},
    @{Name='claude'; X=255; Y=55; Text='Claude Code'},
    @{Name='gemini'; X=255; Y=85; Text='Gemini CLI'},
    @{Name='desktop'; X=500; Y=25; Text='Codex Desktop'}
)
foreach ($pos in $statusPositions) {
    $grpStatus.Controls.Add((New-Label ($pos.Text + ':') $pos.X $pos.Y 110))
    $value = New-Object System.Windows.Forms.Label
    $value.Location = New-Object System.Drawing.Point(($pos.X + 110), $pos.Y)
    $value.Size = New-Object System.Drawing.Size(190, 20)
    $grpStatus.Controls.Add($value)
    $statusLabels[$pos.Name] = $value
}
$btnRefreshStatus = New-Object System.Windows.Forms.Button
$btnRefreshStatus.Text = 'Refresh Status'
$btnRefreshStatus.Location = New-Object System.Drawing.Point(580, 82)
$btnRefreshStatus.Size = New-Object System.Drawing.Size(120, 28)
$grpStatus.Controls.Add($btnRefreshStatus)

$grpConfigStatus = New-Object System.Windows.Forms.GroupBox
$grpConfigStatus.Text = 'Config Status'
$grpConfigStatus.Location = New-Object System.Drawing.Point(20, 230)
$grpConfigStatus.Size = New-Object System.Drawing.Size(720, 110)
$form.Controls.Add($grpConfigStatus)

$configNames = @('codex','claude','gemini','logs')
$configLabels = @{}
$configPositions = @(
    @{Name='codex'; X=15; Y=28; Text='Codex config'},
    @{Name='claude'; X=15; Y=58; Text='Claude config'},
    @{Name='gemini'; X=330; Y=28; Text='Gemini config'},
    @{Name='logs'; X=330; Y=58; Text='Log folder'}
)
foreach ($pos in $configPositions) {
    $grpConfigStatus.Controls.Add((New-Label ($pos.Text + ':') $pos.X $pos.Y 110))
    $value = New-Object System.Windows.Forms.Label
    $value.Location = New-Object System.Drawing.Point(($pos.X + 110), $pos.Y)
    $value.Size = New-Object System.Drawing.Size(210, 20)
    $grpConfigStatus.Controls.Add($value)
    $configLabels[$pos.Name] = $value
}
$btnOpenConfigs = New-Object System.Windows.Forms.Button
$btnOpenConfigs.Text = 'Open Config Root'
$btnOpenConfigs.Location = New-Object System.Drawing.Point(575, 24)
$btnOpenConfigs.Size = New-Object System.Drawing.Size(125, 28)
$grpConfigStatus.Controls.Add($btnOpenConfigs)
$btnOpenLogsInline = New-Object System.Windows.Forms.Button
$btnOpenLogsInline.Text = 'Open Log Dir'
$btnOpenLogsInline.Location = New-Object System.Drawing.Point(575, 58)
$btnOpenLogsInline.Size = New-Object System.Drawing.Size(125, 28)
$grpConfigStatus.Controls.Add($btnOpenLogsInline)

$grpComponents = New-Object System.Windows.Forms.GroupBox
$grpComponents.Text = 'Components to Install'
$grpComponents.Location = New-Object System.Drawing.Point(20, 350)
$grpComponents.Size = New-Object System.Drawing.Size(720, 80)
$form.Controls.Add($grpComponents)

$chkInstallCodex = New-Object System.Windows.Forms.CheckBox
$chkInstallCodex.Text = 'Codex CLI'
$chkInstallCodex.Location = New-Object System.Drawing.Point(15, 30)
$chkInstallCodex.Checked = $true
$chkInstallCodex.AutoSize = $true
$grpComponents.Controls.Add($chkInstallCodex)

$chkInstallClaude = New-Object System.Windows.Forms.CheckBox
$chkInstallClaude.Text = 'Claude Code'
$chkInstallClaude.Location = New-Object System.Drawing.Point(145, 30)
$chkInstallClaude.Checked = $true
$chkInstallClaude.AutoSize = $true
$grpComponents.Controls.Add($chkInstallClaude)

$chkInstallGemini = New-Object System.Windows.Forms.CheckBox
$chkInstallGemini.Text = 'Gemini CLI'
$chkInstallGemini.Location = New-Object System.Drawing.Point(305, 30)
$chkInstallGemini.Checked = $true
$chkInstallGemini.AutoSize = $true
$grpComponents.Controls.Add($chkInstallGemini)

$chkInstallDesktop = New-Object System.Windows.Forms.CheckBox
$chkInstallDesktop.Text = 'Codex Desktop'
$chkInstallDesktop.Location = New-Object System.Drawing.Point(445, 30)
$chkInstallDesktop.Checked = $true
$chkInstallDesktop.AutoSize = $true
$grpComponents.Controls.Add($chkInstallDesktop)

$btnSelectAll = New-Object System.Windows.Forms.Button
$btnSelectAll.Text = 'Select All'
$btnSelectAll.Location = New-Object System.Drawing.Point(575, 24)
$btnSelectAll.Size = New-Object System.Drawing.Size(60, 28)
$grpComponents.Controls.Add($btnSelectAll)

$btnClearAll = New-Object System.Windows.Forms.Button
$btnClearAll.Text = 'Clear All'
$btnClearAll.Location = New-Object System.Drawing.Point(640, 24)
$btnClearAll.Size = New-Object System.Drawing.Size(60, 28)
$grpComponents.Controls.Add($btnClearAll)

$grpKeys = New-Object System.Windows.Forms.GroupBox
$grpKeys.Text = 'API Keys'
$grpKeys.Location = New-Object System.Drawing.Point(20, 440)
$grpKeys.Size = New-Object System.Drawing.Size(720, 125)
$form.Controls.Add($grpKeys)
$grpKeys.Controls.Add((New-Label 'Codex' 12 25 80)); $txtCodexKey = New-TextBox 100 22 600 $true; $grpKeys.Controls.Add($txtCodexKey)
$grpKeys.Controls.Add((New-Label 'Claude' 12 55 80)); $txtClaudeKey = New-TextBox 100 52 600 $true; $grpKeys.Controls.Add($txtClaudeKey)
$grpKeys.Controls.Add((New-Label 'Gemini' 12 85 80)); $txtGeminiKey = New-TextBox 100 82 600 $true; $grpKeys.Controls.Add($txtGeminiKey)

$grpModels = New-Object System.Windows.Forms.GroupBox
$grpModels.Text = 'Models / URLs'
$grpModels.Location = New-Object System.Drawing.Point(20, 575)
$grpModels.Size = New-Object System.Drawing.Size(720, 180)
$form.Controls.Add($grpModels)
$grpModels.Controls.Add((New-Label 'Codex URL' 12 25 80)); $txtCodexUrl = New-TextBox 100 22 600; $txtCodexUrl.Text = 'https://api.leung315.site/v1'; $grpModels.Controls.Add($txtCodexUrl)
$grpModels.Controls.Add((New-Label 'Claude URL' 12 55 80)); $txtClaudeUrl = New-TextBox 100 52 600; $txtClaudeUrl.Text = 'https://api.leung315.site'; $grpModels.Controls.Add($txtClaudeUrl)
$grpModels.Controls.Add((New-Label 'Gemini URL' 12 85 80)); $txtGeminiUrl = New-TextBox 100 82 600; $txtGeminiUrl.Text = 'https://api.leung315.site'; $grpModels.Controls.Add($txtGeminiUrl)
$grpModels.Controls.Add((New-Label 'Codex Model' 12 120 80)); $txtCodexModel = New-TextBox 100 117 180; $txtCodexModel.Text = 'gpt-5.4'; $grpModels.Controls.Add($txtCodexModel)
$grpModels.Controls.Add((New-Label 'Claude Model' 295 120 90)); $txtClaudeModel = New-TextBox 390 117 140; $txtClaudeModel.Text = 'claude-sonnet-4-5'; $grpModels.Controls.Add($txtClaudeModel)
$grpModels.Controls.Add((New-Label 'Gemini Model' 535 120 95)); $txtGeminiModel = New-TextBox 630 117 70; $txtGeminiModel.Text = 'gemini-2.5-pro'; $grpModels.Controls.Add($txtGeminiModel)
$lblModelTip = New-Object System.Windows.Forms.Label
$lblModelTip.Text = 'Default models use the full LEUNG template names. Keep them unless you explicitly want to override.'
$lblModelTip.Location = New-Object System.Drawing.Point(15, 150)
$lblModelTip.Size = New-Object System.Drawing.Size(685, 18)
$lblModelTip.ForeColor = [System.Drawing.Color]::DimGray
$grpModels.Controls.Add($lblModelTip)

$grpOptions = New-Object System.Windows.Forms.GroupBox
$grpOptions.Text = 'Options'
$grpOptions.Location = New-Object System.Drawing.Point(20, 765)
$grpOptions.Size = New-Object System.Drawing.Size(720, 70)
$form.Controls.Add($grpOptions)
$chkConfigOnly = New-Object System.Windows.Forms.CheckBox; $chkConfigOnly.Text = 'Config only'; $chkConfigOnly.Location = New-Object System.Drawing.Point(15, 28); $chkConfigOnly.AutoSize = $true; $grpOptions.Controls.Add($chkConfigOnly)
$chkForceNpm = New-Object System.Windows.Forms.CheckBox; $chkForceNpm.Text = 'Force npm for Codex CLI'; $chkForceNpm.Location = New-Object System.Drawing.Point(130, 28); $chkForceNpm.AutoSize = $true; $grpOptions.Controls.Add($chkForceNpm)
$chkSkipSelfCheck = New-Object System.Windows.Forms.CheckBox; $chkSkipSelfCheck.Text = 'Skip self-check'; $chkSkipSelfCheck.Location = New-Object System.Drawing.Point(350, 28); $chkSkipSelfCheck.AutoSize = $true; $grpOptions.Controls.Add($chkSkipSelfCheck)

$lblLogTitle = New-Object System.Windows.Forms.Label
$lblLogTitle.Text = 'Installer Output'
$lblLogTitle.Location = New-Object System.Drawing.Point(20, 845)
$lblLogTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblLogTitle.AutoSize = $true
$form.Controls.Add($lblLogTitle)

$lblSummary = New-Object System.Windows.Forms.Label
$lblSummary.Text = 'Ready'
$lblSummary.Location = New-Object System.Drawing.Point(120, 845)
$lblSummary.Size = New-Object System.Drawing.Size(620, 20)
$lblSummary.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblSummary)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 870)
$txtLog.Size = New-Object System.Drawing.Size(720, 70)
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
$txtLog.ForeColor = [System.Drawing.Color]::LightGreen
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$form.Controls.Add($txtLog)

$btnOpenLogs = New-Object System.Windows.Forms.Button
$btnOpenLogs.Text = 'Open Logs'
$btnOpenLogs.Location = New-Object System.Drawing.Point(450, 948)
$btnOpenLogs.Size = New-Object System.Drawing.Size(90, 30)
$form.Controls.Add($btnOpenLogs)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Install'
$btnRun.Location = New-Object System.Drawing.Point(550, 948)
$btnRun.Size = New-Object System.Drawing.Size(90, 30)
$form.Controls.Add($btnRun)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(650, 948)
$btnClose.Size = New-Object System.Drawing.Size(90, 30)
$form.Controls.Add($btnClose)

$form.AcceptButton = $btnRun
$form.CancelButton = $btnClose

function Append-Log([string]$line) {
    $txtLog.AppendText($line + [Environment]::NewLine)
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}
function Set-StatusColor($label, [string]$text) {
    if ($text -match 'Missing|Not found') { $label.ForeColor = [System.Drawing.Color]::IndianRed; return }
    if ($text -match 'Partial|ManualInstallRequired') { $label.ForeColor = [System.Drawing.Color]::DarkOrange; return }
    $label.ForeColor = [System.Drawing.Color]::DarkGreen
}
function Update-Summary {
    $selected = @()
    if ($chkInstallCodex.Checked) { $selected += 'Codex CLI' }
    if ($chkInstallClaude.Checked) { $selected += 'Claude Code' }
    if ($chkInstallGemini.Checked) { $selected += 'Gemini CLI' }
    if ($chkInstallDesktop.Checked) { $selected += 'Codex Desktop' }
    if ($selected.Count -eq 0) { $lblSummary.Text = 'No components selected'; $lblSummary.ForeColor = [System.Drawing.Color]::IndianRed; return }
    $mode = if ($chkConfigOnly.Checked) { 'Config-only' } else { 'Install + config' }
    $lblSummary.Text = "$mode | Selected: $($selected -join ', ')"
    $lblSummary.ForeColor = [System.Drawing.Color]::DimGray
}
function Refresh-SystemStatus {
    foreach ($name in $statusNames) {
        $statusLabels[$name].Text = Get-StatusText $name
        Set-StatusColor $statusLabels[$name] $statusLabels[$name].Text
    }
    foreach ($name in $configNames) {
        $configLabels[$name].Text = Get-ConfigStatusText $name
        Set-StatusColor $configLabels[$name] $configLabels[$name].Text
    }
    Update-Summary
}
function Update-FieldState {
    $txtCodexKey.Enabled = $chkInstallCodex.Checked
    $txtClaudeKey.Enabled = $chkInstallClaude.Checked
    $txtGeminiKey.Enabled = $chkInstallGemini.Checked
    if ($chkConfigOnly.Checked) {
        $chkInstallDesktop.Checked = $false
        $chkInstallDesktop.Enabled = $false
    } else {
        $chkInstallDesktop.Enabled = $true
    }
    Update-Summary
}
function Set-ComponentSelection([bool]$state) {
    $chkInstallCodex.Checked = $state
    $chkInstallClaude.Checked = $state
    $chkInstallGemini.Checked = $state
    if (-not $chkConfigOnly.Checked) { $chkInstallDesktop.Checked = $state }
    Update-FieldState
}

$btnRefreshStatus.Add_Click({ Refresh-SystemStatus })
$btnClose.Add_Click({ $form.Close() })
$btnOpenLogs.Add_Click({ Open-DirectorySafe $LogDir })
$btnOpenLogsInline.Add_Click({ Open-DirectorySafe $LogDir })
$btnOpenConfigs.Add_Click({ Open-DirectorySafe $CodexHome })
$btnSelectAll.Add_Click({ Set-ComponentSelection $true })
$btnClearAll.Add_Click({ Set-ComponentSelection $false })
$chkInstallCodex.Add_CheckedChanged({ Update-FieldState })
$chkInstallClaude.Add_CheckedChanged({ Update-FieldState })
$chkInstallGemini.Add_CheckedChanged({ Update-FieldState })
$chkInstallDesktop.Add_CheckedChanged({ Update-Summary })
$chkConfigOnly.Add_CheckedChanged({ Update-FieldState })

$btnRun.Add_Click({
    if (-not ($chkInstallCodex.Checked -or $chkInstallClaude.Checked -or $chkInstallGemini.Checked -or $chkInstallDesktop.Checked)) {
        [System.Windows.Forms.MessageBox]::Show('Please select at least one component.', 'No selection', 'OK', 'Warning') | Out-Null
        return
    }
    if ($chkInstallCodex.Checked -and [string]::IsNullOrWhiteSpace($txtCodexKey.Text)) {
        [System.Windows.Forms.MessageBox]::Show('Codex CLI selected but Codex API key is empty.', 'Missing Codex key', 'OK', 'Warning') | Out-Null
        return
    }
    if ($chkInstallClaude.Checked -and [string]::IsNullOrWhiteSpace($txtClaudeKey.Text)) {
        [System.Windows.Forms.MessageBox]::Show('Claude Code selected but Claude API key is empty.', 'Missing Claude key', 'OK', 'Warning') | Out-Null
        return
    }
    if ($chkInstallGemini.Checked -and [string]::IsNullOrWhiteSpace($txtGeminiKey.Text)) {
        [System.Windows.Forms.MessageBox]::Show('Gemini CLI selected but Gemini API key is empty.', 'Missing Gemini key', 'OK', 'Warning') | Out-Null
        return
    }

    $btnRun.Enabled = $false
    $txtLog.Clear()
    Append-Log 'Starting installer...'
    $args = @('-ExecutionPolicy','Bypass','-File',$InstallerPath,'-NonInteractive')
    if ($chkInstallCodex.Checked) { $args += '-InstallCodex' }
    if ($chkInstallClaude.Checked) { $args += '-InstallClaude' }
    if ($chkInstallGemini.Checked) { $args += '-InstallGemini' }
    if ($chkInstallDesktop.Checked) { $args += '-InstallDesktop' }
    if ($txtCodexKey.Text.Trim()) { $args += @('-CodexApiKey',$txtCodexKey.Text.Trim()) }
    if ($txtClaudeKey.Text.Trim()) { $args += @('-ClaudeApiKey',$txtClaudeKey.Text.Trim()) }
    if ($txtGeminiKey.Text.Trim()) { $args += @('-GeminiApiKey',$txtGeminiKey.Text.Trim()) }
    $args += @(
        '-CodexBaseUrl',$txtCodexUrl.Text.Trim(),
        '-ClaudeBaseUrl',$txtClaudeUrl.Text.Trim(),
        '-GeminiBaseUrl',$txtGeminiUrl.Text.Trim(),
        '-CodexModel',$txtCodexModel.Text.Trim(),
        '-ClaudeModel',$txtClaudeModel.Text.Trim(),
        '-GeminiModel',$txtGeminiModel.Text.Trim()
    )
    if (-not $chkInstallDesktop.Checked) { $args += '-SkipDesktop' }
    if ($chkConfigOnly.Checked) { $args += '-ConfigOnly' }
    if ($chkForceNpm.Checked) { $args += '-ForceNpm' }
    if ($chkSkipSelfCheck.Checked) { $args += '-SkipSelfCheck' }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    foreach ($a in $args) { [void]$psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true
    $proc.add_OutputDataReceived({ if ($_.Data) { $form.BeginInvoke([Action[string]]{ param($s) Append-Log $s }, $_.Data) | Out-Null } })
    $proc.add_ErrorDataReceived({ if ($_.Data) { $form.BeginInvoke([Action[string]]{ param($s) Append-Log ('[stderr] ' + $s) }, $_.Data) | Out-Null } })
    $proc.add_Exited({
        $form.BeginInvoke([Action]{
            $btnRun.Enabled = $true
            Refresh-SystemStatus
            if ($proc.ExitCode -eq 0) {
                [System.Windows.Forms.MessageBox]::Show('Installation completed.', 'Success', 'OK', 'Information') | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show('Installation failed. Check the log output.', 'Failed', 'OK', 'Error') | Out-Null
            }
        }) | Out-Null
        $proc.Dispose()
    })
    [void]$proc.Start()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
})

Update-FieldState
Refresh-SystemStatus
[void]$form.ShowDialog()
