#Requires -Version 5.1
# LEUNG CLI Installer - WinForms GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Load core libraries
. (Join-Path $ScriptDir 'lib\common.ps1')
. (Join-Path $ScriptDir 'lib\download.ps1')
. (Join-Path $ScriptDir 'lib\detect.ps1')
. (Join-Path $ScriptDir 'lib\installers.ps1')
. (Join-Path $ScriptDir 'lib\config.ps1')

# --- Main Form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'LEUNG CLI Installer'
$form.Size = New-Object System.Drawing.Size(540, 625)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
# Use a CJK-capable font with Segoe UI fallback for systems without YaHei.
$_fontName = if ([System.Drawing.FontFamily]::Families.Name -contains 'Microsoft YaHei UI') {
    'Microsoft YaHei UI'
} else { 'Segoe UI' }
$form.Font = New-Object System.Drawing.Font($_fontName, 9)

# Title
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'LEUNG CLI Installer'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 15)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Text = 'Install Codex / Claude / Gemini and configure LEUNG API relay'
$lblSubtitle.Location = New-Object System.Drawing.Point(22, 50)
$lblSubtitle.AutoSize = $true
$lblSubtitle.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblSubtitle)

# --- API Keys (one per CLI) ---
$grpKeys = New-Object System.Windows.Forms.GroupBox
$grpKeys.Text = 'API Keys (each CLI uses its own key)'
$grpKeys.Location = New-Object System.Drawing.Point(20, 80)
$grpKeys.Size = New-Object System.Drawing.Size(480, 115)
$form.Controls.Add($grpKeys)

$lblCodexKey = New-Object System.Windows.Forms.Label
$lblCodexKey.Text = 'Codex:'
$lblCodexKey.Location = New-Object System.Drawing.Point(10, 25)
$lblCodexKey.Size = New-Object System.Drawing.Size(55, 20)
$grpKeys.Controls.Add($lblCodexKey)

$txtCodexKey = New-Object System.Windows.Forms.TextBox
$txtCodexKey.Location = New-Object System.Drawing.Point(70, 22)
$txtCodexKey.Size = New-Object System.Drawing.Size(395, 22)
$txtCodexKey.UseSystemPasswordChar = $true
$grpKeys.Controls.Add($txtCodexKey)

$lblClaudeKey = New-Object System.Windows.Forms.Label
$lblClaudeKey.Text = 'Claude:'
$lblClaudeKey.Location = New-Object System.Drawing.Point(10, 55)
$lblClaudeKey.Size = New-Object System.Drawing.Size(55, 20)
$grpKeys.Controls.Add($lblClaudeKey)

$txtClaudeKey = New-Object System.Windows.Forms.TextBox
$txtClaudeKey.Location = New-Object System.Drawing.Point(70, 52)
$txtClaudeKey.Size = New-Object System.Drawing.Size(395, 22)
$txtClaudeKey.UseSystemPasswordChar = $true
$grpKeys.Controls.Add($txtClaudeKey)

$lblGeminiKey = New-Object System.Windows.Forms.Label
$lblGeminiKey.Text = 'Gemini:'
$lblGeminiKey.Location = New-Object System.Drawing.Point(10, 85)
$lblGeminiKey.Size = New-Object System.Drawing.Size(55, 20)
$grpKeys.Controls.Add($lblGeminiKey)

$txtGeminiKey = New-Object System.Windows.Forms.TextBox
$txtGeminiKey.Location = New-Object System.Drawing.Point(70, 82)
$txtGeminiKey.Size = New-Object System.Drawing.Size(395, 22)
$txtGeminiKey.UseSystemPasswordChar = $true
$grpKeys.Controls.Add($txtGeminiKey)

# --- Install Options ---
$grpInstall = New-Object System.Windows.Forms.GroupBox
$grpInstall.Text = 'Install Components'
$grpInstall.Location = New-Object System.Drawing.Point(20, 205)
$grpInstall.Size = New-Object System.Drawing.Size(480, 105)
$form.Controls.Add($grpInstall)

$chkCodexCli = New-Object System.Windows.Forms.CheckBox
$chkCodexCli.Text = 'Codex CLI (@openai/codex)'
$chkCodexCli.Location = New-Object System.Drawing.Point(15, 22)
$chkCodexCli.Checked = $true
$chkCodexCli.AutoSize = $true
$grpInstall.Controls.Add($chkCodexCli)

$chkCodexDesktop = New-Object System.Windows.Forms.CheckBox
$chkCodexDesktop.Text = 'Codex Desktop App'
$chkCodexDesktop.Location = New-Object System.Drawing.Point(260, 22)
$chkCodexDesktop.Checked = $true
$chkCodexDesktop.AutoSize = $true
$grpInstall.Controls.Add($chkCodexDesktop)

$chkClaude = New-Object System.Windows.Forms.CheckBox
$chkClaude.Text = 'Claude Code (@anthropic-ai/claude-code)'
$chkClaude.Location = New-Object System.Drawing.Point(15, 50)
$chkClaude.Checked = $true
$chkClaude.AutoSize = $true
$grpInstall.Controls.Add($chkClaude)

$chkGemini = New-Object System.Windows.Forms.CheckBox
$chkGemini.Text = 'Gemini CLI (@google/gemini-cli)'
$chkGemini.Location = New-Object System.Drawing.Point(15, 78)
$chkGemini.Checked = $true
$chkGemini.AutoSize = $true
$grpInstall.Controls.Add($chkGemini)

# --- Configuration URLs ---
$grpConfig = New-Object System.Windows.Forms.GroupBox
$grpConfig.Text = 'Relay URLs (LEUNG API defaults)'
$grpConfig.Location = New-Object System.Drawing.Point(20, 320)
$grpConfig.Size = New-Object System.Drawing.Size(480, 115)
$form.Controls.Add($grpConfig)

$lblCodexUrl = New-Object System.Windows.Forms.Label
$lblCodexUrl.Text = 'Codex:'
$lblCodexUrl.Location = New-Object System.Drawing.Point(10, 25)
$lblCodexUrl.Size = New-Object System.Drawing.Size(55, 20)
$grpConfig.Controls.Add($lblCodexUrl)

$txtCodexUrl = New-Object System.Windows.Forms.TextBox
$txtCodexUrl.Location = New-Object System.Drawing.Point(70, 22)
$txtCodexUrl.Size = New-Object System.Drawing.Size(395, 22)
$txtCodexUrl.Text = $script:LEUNG_DEFAULT_CODEX_URL
$grpConfig.Controls.Add($txtCodexUrl)

$lblClaudeUrl = New-Object System.Windows.Forms.Label
$lblClaudeUrl.Text = 'Claude:'
$lblClaudeUrl.Location = New-Object System.Drawing.Point(10, 55)
$lblClaudeUrl.Size = New-Object System.Drawing.Size(55, 20)
$grpConfig.Controls.Add($lblClaudeUrl)

$txtClaudeUrl = New-Object System.Windows.Forms.TextBox
$txtClaudeUrl.Location = New-Object System.Drawing.Point(70, 52)
$txtClaudeUrl.Size = New-Object System.Drawing.Size(395, 22)
$txtClaudeUrl.Text = $script:LEUNG_DEFAULT_CLAUDE_URL
$grpConfig.Controls.Add($txtClaudeUrl)

$lblGeminiUrl = New-Object System.Windows.Forms.Label
$lblGeminiUrl.Text = 'Gemini:'
$lblGeminiUrl.Location = New-Object System.Drawing.Point(10, 85)
$lblGeminiUrl.Size = New-Object System.Drawing.Size(55, 20)
$grpConfig.Controls.Add($lblGeminiUrl)

$txtGeminiUrl = New-Object System.Windows.Forms.TextBox
$txtGeminiUrl.Location = New-Object System.Drawing.Point(70, 82)
$txtGeminiUrl.Size = New-Object System.Drawing.Size(395, 22)
$txtGeminiUrl.Text = $script:LEUNG_DEFAULT_GEMINI_URL
$grpConfig.Controls.Add($txtGeminiUrl)

# --- Log Output ---
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 445)
$txtLog.Size = New-Object System.Drawing.Size(480, 90)
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$txtLog.ForeColor = [System.Drawing.Color]::LightGreen
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$form.Controls.Add($txtLog)

# --- Buttons ---
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = 'Install'
$btnInstall.Location = New-Object System.Drawing.Point(310, 545)
$btnInstall.Size = New-Object System.Drawing.Size(90, 30)
$form.Controls.Add($btnInstall)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(410, 545)
$btnClose.Size = New-Object System.Drawing.Size(90, 30)
$form.Controls.Add($btnClose)

# --- Helpers ---
# Thread-safe queue shared between the background install runspace and the UI timer.
$script:LogQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
$script:InstallState = [hashtable]::Synchronized(@{ Done = $false; Failed = $false })
$script:InstallPowerShell = $null
$script:InstallHandle = $null

function Append-Log {
    param([string]$Msg)
    $txtLog.AppendText("$Msg`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

# Drains queued log lines from the background runspace onto the UI.
$logTimer = New-Object System.Windows.Forms.Timer
$logTimer.Interval = 200
$logTimer.Add_Tick({
    $line = $null
    while ($script:LogQueue.TryDequeue([ref]$line)) {
        Append-Log $line
    }
    if ($script:InstallState.Done) {
        $logTimer.Stop()
        if ($script:InstallPowerShell) {
            try { $script:InstallPowerShell.EndInvoke($script:InstallHandle) } catch {}
            $script:InstallPowerShell.Runspace.Dispose()
            $script:InstallPowerShell.Dispose()
            $script:InstallPowerShell = $null
        }
        $btnInstall.Enabled = $true
        if ($script:InstallState.Failed) {
            [System.Windows.Forms.MessageBox]::Show(
                "Installation finished with errors. Check the log above.",
                'Finished with errors', 'OK', 'Warning'
            )
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Installation complete!`n`nAll selected CLIs are configured to use the LEUNG API relay.",
                'Success', 'OK', 'Information'
            )
        }
    }
})

# --- Events ---
$btnClose.Add_Click({ $form.Close() })

$btnInstall.Add_Click({
    $codexKey  = $txtCodexKey.Text.Trim()
    $claudeKey = $txtClaudeKey.Text.Trim()
    $geminiKey = $txtGeminiKey.Text.Trim()

    # Validate that each selected CLI has its own key.
    if (($chkCodexCli.Checked -or $chkCodexDesktop.Checked) -and -not $codexKey) {
        [System.Windows.Forms.MessageBox]::Show('Please enter the Codex API Key.', 'Error', 'OK', 'Error')
        return
    }
    if ($chkClaude.Checked -and -not $claudeKey) {
        [System.Windows.Forms.MessageBox]::Show('Please enter the Claude API Key.', 'Error', 'OK', 'Error')
        return
    }
    if ($chkGemini.Checked -and -not $geminiKey) {
        [System.Windows.Forms.MessageBox]::Show('Please enter the Gemini API Key.', 'Error', 'OK', 'Error')
        return
    }

    $btnInstall.Enabled = $false
    $txtLog.Clear()
    $script:InstallState.Done = $false
    $script:InstallState.Failed = $false

    # Snapshot UI selections into a plain hashtable to hand off to the runspace.
    $opts = @{
        ScriptDir   = $ScriptDir
        CodexCli    = $chkCodexCli.Checked
        CodexDesk   = $chkCodexDesktop.Checked
        Claude      = $chkClaude.Checked
        Gemini      = $chkGemini.Checked
        CodexKey    = $codexKey
        ClaudeKey   = $claudeKey
        GeminiKey   = $geminiKey
        CodexUrl    = $txtCodexUrl.Text.Trim()
        ClaudeUrl   = $txtClaudeUrl.Text.Trim()
        GeminiUrl   = $txtGeminiUrl.Text.Trim()
    }

    # Background work: dot-source the same libs in a fresh runspace so every
    # Install-* / Write-* function and $script: default is available, then run
    # the install sequence, pushing progress lines onto the shared queue.
    $work = {
        param($opts, $queue, $state)
        function Log([string]$m) { $queue.Enqueue($m) }
        try {
            . (Join-Path $opts.ScriptDir 'lib\common.ps1')
            . (Join-Path $opts.ScriptDir 'lib\download.ps1')
            . (Join-Path $opts.ScriptDir 'lib\detect.ps1')
            . (Join-Path $opts.ScriptDir 'lib\installers.ps1')
            . (Join-Path $opts.ScriptDir 'lib\config.ps1')

            # Route every Write-* line and progress heartbeat from the libs into
            # the shared queue so the UI log streams live install progress.
            $script:LeungLogQueue = $queue

            Log "[*] Starting installation..."
            Ensure-LeungDirectories
            Log "[OK] Directories ready."

            if ($opts.CodexCli) {
                if (Test-CliInstalled 'codex') { Log "[OK] Codex CLI already installed." }
                else {
                    Log "[*] Installing Codex CLI (this can take a minute)..."
                    if (Install-CodexCli) { Log "[OK] Codex CLI done." }
                    else { Log "[WARN] Codex CLI failed."; $state.Failed = $true }
                }
            }
            if ($opts.Claude) {
                if (Test-CliInstalled 'claude') { Log "[OK] Claude Code already installed." }
                else {
                    Log "[*] Installing Claude Code (this can take a minute)..."
                    if (Install-ClaudeCli) { Log "[OK] Claude Code done." }
                    else { Log "[WARN] Claude Code failed."; $state.Failed = $true }
                }
            }
            if ($opts.Gemini) {
                if (Test-CliInstalled 'gemini') { Log "[OK] Gemini CLI already installed." }
                else {
                    Log "[*] Installing Gemini CLI (this can take a minute)..."
                    if (Install-GeminiCli) { Log "[OK] Gemini CLI done." }
                    else { Log "[WARN] Gemini CLI failed."; $state.Failed = $true }
                }
            }
            if ($opts.CodexDesk) {
                if (Test-CodexDesktopInstalled) { Log "[OK] Codex Desktop already installed." }
                else {
                    Log "[*] Installing Codex Desktop..."
                    if (Install-CodexDesktop) {
                        # Verify the package actually landed before claiming success.
                        if (Test-CodexDesktopInstalled) { Log "[OK] Codex Desktop done." }
                        else { Log "[WARN] winget reported success but Codex Desktop was not detected."; $state.Failed = $true }
                    }
                    else {
                        Log "[WARN] Codex Desktop NOT installed. Install it manually: winget install --id 9PLM9XGG6VKS --source msstore  (or Microsoft Store - search 'Codex')."
                        $state.Failed = $true
                    }
                }
            }

            Log "[*] Writing configuration..."
            if ($opts.CodexCli -or $opts.CodexDesk) {
                Write-CodexConfig -ApiKey $opts.CodexKey -BaseUrl $opts.CodexUrl -Model $script:LEUNG_DEFAULT_CODEX_MODEL
                Log "[OK] Codex config written."
            }
            if ($opts.Claude) {
                Write-ClaudeConfig -ApiKey $opts.ClaudeKey -BaseUrl $opts.ClaudeUrl -Model $script:LEUNG_DEFAULT_CLAUDE_MODEL
                Log "[OK] Claude config written."
            }
            if ($opts.Gemini) {
                Write-GeminiConfig -ApiKey $opts.GeminiKey -BaseUrl $opts.GeminiUrl -Model $script:LEUNG_DEFAULT_GEMINI_MODEL
                Log "[OK] Gemini config written."
            }

            Log ""
            # Ensure CLIs installed via npm can run from PowerShell.
            if (Set-PsExecutionPolicyIfNeeded) {
                Log "[OK] PowerShell ExecutionPolicy set to RemoteSigned."
            }
            Log ""
            if ($state.Failed) {
                Log "[DONE] Finished, but some steps did not complete — see the [WARN] lines above."
            } else {
                Log "[DONE] All complete!"
            }
        } catch {
            Log "[ERROR] $($_.Exception.Message)"
            $state.Failed = $true
        } finally {
            $state.Done = $true
        }
    }

    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript($work).AddArgument($opts).AddArgument($script:LogQueue).AddArgument($script:InstallState)
    $script:InstallPowerShell = $ps
    $script:InstallHandle = $ps.BeginInvoke()

    $logTimer.Start()
})

# Load existing config (per CLI)
try {
    $cfgCodex  = Get-CurrentCliConfig 'codex'
    $cfgClaude = Get-CurrentCliConfig 'claude'
    $cfgGemini = Get-CurrentCliConfig 'gemini'
    if ($cfgCodex.ApiKey)  { $txtCodexKey.Text  = $cfgCodex.ApiKey }
    if ($cfgClaude.ApiKey) { $txtClaudeKey.Text = $cfgClaude.ApiKey }
    if ($cfgGemini.ApiKey) { $txtGeminiKey.Text = $cfgGemini.ApiKey }
} catch {}

# Clean up a still-running install runspace if the window is closed mid-install.
$form.Add_FormClosing({
    $logTimer.Stop()
    if ($script:InstallPowerShell) {
        try { $script:InstallPowerShell.Stop() } catch {}
        try { $script:InstallPowerShell.Runspace.Dispose() } catch {}
        try { $script:InstallPowerShell.Dispose() } catch {}
        $script:InstallPowerShell = $null
    }
})

$form.ShowDialog() | Out-Null
