#Requires -Version 5.1

function Show-Banner {
    $banner = @"

  ╔══════════════════════════════════════════════╗
  ║       LEUNG CLI Installer for Windows        ║
  ║                                              ║
  ║   Codex CLI / Claude Code / Gemini CLI       ║
  ║   + Codex Desktop + LEUNG API Relay          ║
  ╚══════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Read-ApiKey {
    param(
        [string]$Default = '',
        [string]$DisplayName = ''
    )
    Write-Host ""
    $label = if ($DisplayName) { "$DisplayName API Key" } else { 'API Key' }
    if ($Default) {
        $masked = $Default.Substring(0, [Math]::Min(8, $Default.Length)) + '...'
        Write-Host "  Current ${label}: $masked" -ForegroundColor Gray
    }
    Write-Host "  Enter your $label:" -ForegroundColor White
    $key = Read-Host "  $label"
    if (-not $key -and $Default) { return $Default }
    if (-not $key) {
        Write-Host "  API Key cannot be empty." -ForegroundColor Red
        return Read-ApiKey -Default $Default -DisplayName $DisplayName
    }
    return $key
}

function Show-MainMenu {
    Write-Host ""
    Write-Host "  Choose an action:" -ForegroundColor White
    Write-Host "    [1] Install CLIs + Configure" -ForegroundColor Green
    Write-Host "    [2] Configure only (write config for existing installs)" -ForegroundColor Yellow
    Write-Host "    [3] View current configuration" -ForegroundColor Cyan
    Write-Host "    [4] Exit" -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "  Selection (1-4)"
    return $choice
}

function Show-CliSelection {
    Write-Host ""
    Write-Host "  Select CLIs to install:" -ForegroundColor White
    Write-Host "    [1] All (Codex CLI + Desktop + Claude + Gemini)" -ForegroundColor Green
    Write-Host "    [2] Codex CLI + Desktop only" -ForegroundColor Yellow
    Write-Host "    [3] Claude Code only" -ForegroundColor Yellow
    Write-Host "    [4] Gemini CLI only" -ForegroundColor Yellow
    Write-Host "    [5] Custom selection" -ForegroundColor Cyan
    Write-Host ""
    $choice = Read-Host "  Selection (1-5)"
    return $choice
}

function Show-CustomCliSelection {
    Write-Host ""
    Write-Host "  Toggle each (Y/n):" -ForegroundColor White
    $selections = @{}

    Write-Host "    Install Codex CLI? (Y/n): " -NoNewline
    $ans = Read-Host
    $selections.codex = ($ans -eq '' -or $ans -match '^[Yy]')

    Write-Host "    Install Codex Desktop? (Y/n): " -NoNewline
    $ans = Read-Host
    $selections.desktop = ($ans -eq '' -or $ans -match '^[Yy]')

    Write-Host "    Install Claude Code? (Y/n): " -NoNewline
    $ans = Read-Host
    $selections.claude = ($ans -eq '' -or $ans -match '^[Yy]')

    Write-Host "    Install Gemini CLI? (Y/n): " -NoNewline
    $ans = Read-Host
    $selections.gemini = ($ans -eq '' -or $ans -match '^[Yy]')

    return $selections
}

function Show-SystemStatus {
    param([hashtable]$Status)
    Write-Host ""
    Write-Host "  System Status:" -ForegroundColor Cyan
    Write-Host "    Windows:       $($Status.Windows.Caption) (Build $($Status.Windows.Build))" -ForegroundColor White
    Write-Host "    Arch:          $($Status.Windows.Arch)" -ForegroundColor White

    $wg = if ($Status.WingetAvailable) { "Available" } else { "Not found" }
    Write-Host "    Winget:        $wg" -ForegroundColor $(if ($Status.WingetAvailable) { 'Green' } else { 'Yellow' })

    $nd = if ($Status.NodeAvailable) { "Available" } else { "Not found" }
    Write-Host "    Node.js:       $nd" -ForegroundColor $(if ($Status.NodeAvailable) { 'Green' } else { 'Yellow' })

    $nm = if ($Status.NpmAvailable) { "Available" } else { "Not found" }
    Write-Host "    npm:           $nm" -ForegroundColor $(if ($Status.NpmAvailable) { 'Green' } else { 'Yellow' })

    Write-Host ""
    Write-Host "    Codex CLI:     $(Format-CliStatus $Status.CodexCliInstalled $Status.CodexCliVersion)"
    Write-Host "    Codex Desktop: $(Format-InstalledStatus $Status.CodexDesktopInstalled)"
    Write-Host "    Claude Code:   $(Format-CliStatus $Status.ClaudeCliInstalled $Status.ClaudeCliVersion)"
    Write-Host "    Gemini CLI:    $(Format-CliStatus $Status.GeminiCliInstalled $Status.GeminiCliVersion)"
    Write-Host ""
}

function Format-CliStatus {
    param([bool]$Installed, [string]$Version)
    if ($Installed) {
        $v = if ($Version) { " ($Version)" } else { '' }
        Write-Host "Installed$v" -ForegroundColor Green -NoNewline
    } else {
        Write-Host "Not installed" -ForegroundColor Gray -NoNewline
    }
    Write-Host ""
}

function Format-InstalledStatus {
    param([bool]$Installed)
    if ($Installed) {
        Write-Host "Installed" -ForegroundColor Green -NoNewline
    } else {
        Write-Host "Not installed" -ForegroundColor Gray -NoNewline
    }
    Write-Host ""
}

function Confirm-Action {
    param([string]$Message)
    Write-Host "  $Message (Y/n): " -NoNewline -ForegroundColor White
    $answer = Read-Host
    return ($answer -eq '' -or $answer -match '^[Yy]')
}
