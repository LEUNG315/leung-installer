#Requires -Version 5.1
param(
    [switch]$NonInteractive,
    [string]$ApiKey = '',
    [string]$CodexKey = '',
    [string]$ClaudeKey = '',
    [string]$GeminiKey = '',
    [string]$Url = '',
    [string]$Model = '',
    [string[]]$Cli = @(),
    [switch]$SkipDesktop,
    [switch]$ConfigOnly,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Load libraries
. (Join-Path $ScriptDir 'lib\common.ps1')
. (Join-Path $ScriptDir 'lib\download.ps1')
. (Join-Path $ScriptDir 'lib\detect.ps1')
. (Join-Path $ScriptDir 'lib\installers.ps1')
. (Join-Path $ScriptDir 'lib\config.ps1')
. (Join-Path $ScriptDir 'lib\ui.ps1')

function Show-Usage {
    @"
LEUNG CLI Installer for Windows
================================

Usage:
  .\install.ps1                                         Interactive mode
  .\install.ps1 -NonInteractive -CodexKey sk-a -ClaudeKey sk-b -GeminiKey sk-c
  .\install.ps1 -NonInteractive -ApiKey sk-xxx -Cli codex,claude
  .\install.ps1 -ConfigOnly -CodexKey sk-a -Cli codex

Options:
  -NonInteractive   Run without prompts
  -ApiKey <key>     Fallback API Key used for any CLI without its own key
  -CodexKey <key>   API Key for Codex (overrides -ApiKey for Codex)
  -ClaudeKey <key>  API Key for Claude (overrides -ApiKey for Claude)
  -GeminiKey <key>  API Key for Gemini (overrides -ApiKey for Gemini)
  -Url <url>        Override base URL for all CLIs
  -Model <model>    Override model name
  -Cli <list>       Which CLIs to install: codex, claude, gemini (comma-separated)
                    Default: all three
  -SkipDesktop      Skip Codex Desktop installation
  -ConfigOnly       Only write config files, skip CLI installation
  -Help             Show this help

Examples:
  .\install.ps1 -NonInteractive -CodexKey sk-a -ClaudeKey sk-b -GeminiKey sk-c
  .\install.ps1 -NonInteractive -ApiKey sk-xxx -Cli codex -SkipDesktop
  .\install.ps1 -NonInteractive -ClaudeKey sk-b -GeminiKey sk-c -Cli claude,gemini
  .\install.ps1 -ConfigOnly -CodexKey sk-a -Cli codex -Url https://custom/v1
"@ | Write-Host
}

function Resolve-CliKey {
    param([string]$CliName)
    switch ($CliName) {
        'codex'  { if ($CodexKey)  { return $CodexKey } }
        'claude' { if ($ClaudeKey) { return $ClaudeKey } }
        'gemini' { if ($GeminiKey) { return $GeminiKey } }
    }
    return $ApiKey
}

function Run-NonInteractive {
    $targetClis = if ($Cli.Count -gt 0) { $Cli } else { @('codex', 'claude', 'gemini') }

    # Validate that every target CLI has a key (its own, or the -ApiKey fallback).
    foreach ($c in $targetClis) {
        if (-not (Resolve-CliKey $c)) {
            Write-Fail "Missing API Key for $c. Provide -$($c.Substring(0,1).ToUpper() + $c.Substring(1))Key or -ApiKey."
            exit 1
        }
    }

    Ensure-LeungDirectories

    if (-not $ConfigOnly) {
        foreach ($c in $targetClis) {
            if (-not (Test-CliInstalled $c)) {
                $ok = Install-Cli $c
                if (-not $ok) { Write-Log "$c installation failed." 'WARN' }
            } else {
                Write-Success "$($script:CLI_REGISTRY[$c].DisplayName) already installed."
            }
        }
        if ((-not $SkipDesktop) -and ($targetClis -contains 'codex')) {
            if (-not (Test-CodexDesktopInstalled)) {
                Install-CodexDesktop | Out-Null
            }
        }
    }

    foreach ($c in $targetClis) {
        Write-CliConfig -CliName $c -ApiKey (Resolve-CliKey $c) -BaseUrl $Url -Model $Model
    }

    Set-PsExecutionPolicyIfNeeded
    Write-Success "Installation complete."
    Show-AllConfigSummary
}

function Run-Interactive {
    Show-Banner
    Ensure-LeungDirectories

    $status = Get-SystemStatus
    Show-SystemStatus -Status $status

    while ($true) {
        $choice = Show-MainMenu
        switch ($choice) {
            '1' { Run-InteractiveInstall -Status $status }
            '2' { Run-InteractiveConfig }
            '3' { Show-AllConfigSummary }
            '4' { Write-Host "`n  Bye!`n" -ForegroundColor Cyan; return }
            default { Write-Host "  Invalid selection." -ForegroundColor Red }
        }
    }
}

function Run-InteractiveInstall {
    param([hashtable]$Status)

    $selChoice = Show-CliSelection
    $selections = @{ codex = $false; desktop = $false; claude = $false; gemini = $false }

    switch ($selChoice) {
        '1' { $selections.codex = $true; $selections.desktop = $true; $selections.claude = $true; $selections.gemini = $true }
        '2' { $selections.codex = $true; $selections.desktop = $true }
        '3' { $selections.claude = $true }
        '4' { $selections.gemini = $true }
        '5' { $selections = Show-CustomCliSelection }
        default { $selections.codex = $true; $selections.desktop = $true; $selections.claude = $true; $selections.gemini = $true }
    }

    $cliList = @()
    if ($selections.codex) { $cliList += 'codex' }
    if ($selections.claude) { $cliList += 'claude' }
    if ($selections.gemini) { $cliList += 'gemini' }

    # Each CLI uses its own API Key (relay groups differ per CLI).
    $keys = @{}
    foreach ($c in $cliList) {
        $existing = Get-CurrentCliConfig $c
        $keys[$c] = Read-ApiKey -Default $existing.ApiKey -DisplayName $script:CLI_REGISTRY[$c].DisplayName
    }

    Write-Host ""
    if (-not (Confirm-Action "Proceed with installation?")) {
        Write-Host "  Cancelled." -ForegroundColor Gray
        return
    }

    foreach ($c in $cliList) {
        $installed = Test-CliInstalled $c
        if (-not $installed) {
            Install-Cli $c | Out-Null
        } else {
            Write-Success "$($script:CLI_REGISTRY[$c].DisplayName) already installed."
        }
    }

    if ($selections.desktop) {
        if (-not $Status.CodexDesktopInstalled) {
            Install-CodexDesktop | Out-Null
        } else {
            Write-Success "Codex Desktop already installed."
        }
    }

    Write-Step "Writing configuration for selected CLIs..."
    foreach ($c in $cliList) {
        Write-CliConfig -CliName $c -ApiKey $keys[$c] -BaseUrl '' -Model ''
        Write-Success "$($script:CLI_REGISTRY[$c].DisplayName) configured."
    }

    Set-PsExecutionPolicyIfNeeded
    Write-Host ""
    Write-Success "All done!"
    Show-AllConfigSummary
}

function Run-InteractiveConfig {
    Write-Host ""
    Write-Host "  Configure which CLIs? (enter numbers, e.g. 123):" -ForegroundColor White
    Write-Host "    [1] Codex   [2] Claude   [3] Gemini   [A] All" -ForegroundColor Cyan
    $sel = Read-Host "  Selection"
    if (-not $sel -or $sel -match '[Aa]') { $sel = '123' }

    $cliList = @()
    if ($sel -match '1') { $cliList += 'codex' }
    if ($sel -match '2') { $cliList += 'claude' }
    if ($sel -match '3') { $cliList += 'gemini' }

    # Each CLI uses its own API Key (relay groups differ per CLI).
    foreach ($c in $cliList) {
        $existing = Get-CurrentCliConfig $c
        $key = Read-ApiKey -Default $existing.ApiKey -DisplayName $script:CLI_REGISTRY[$c].DisplayName
        Write-CliConfig -CliName $c -ApiKey $key -BaseUrl '' -Model ''
    }

    Write-Success "Configuration updated."
    Show-AllConfigSummary
}

# Main
if ($Help) {
    Show-Usage
    exit 0
}

if ($NonInteractive) {
    Run-NonInteractive
} else {
    Run-Interactive
}
