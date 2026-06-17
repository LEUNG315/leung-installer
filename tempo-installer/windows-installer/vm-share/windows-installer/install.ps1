#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [string]$CodexApiKey = '',
    [string]$ClaudeApiKey = '',
    [string]$GeminiApiKey = '',
    [string]$CodexBaseUrl = 'https://api.leung315.site/v1',
    [string]$ClaudeBaseUrl = 'https://api.leung315.site',
    [string]$GeminiBaseUrl = 'https://api.leung315.site',
    [string]$CodexModel = 'gpt-5.4',
    [string]$ClaudeModel = 'claude-sonnet-4-5',
    [string]$GeminiModel = 'gemini-2.5-pro',
    [switch]$SkipDesktop,
    [switch]$ConfigOnly,
    [switch]$SkipNodeInstall,
    [switch]$ForceNpm,
    [switch]$SkipSelfCheck,
    [switch]$InstallCodex,
    [switch]$InstallClaude,
    [switch]$InstallGemini,
    [switch]$InstallDesktop,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:CodexHome = Join-Path $env:USERPROFILE '.codex'
$Script:ClaudeHome = Join-Path $env:USERPROFILE '.claude'
$Script:GeminiHome = Join-Path $env:USERPROFILE '.gemini'
$Script:CodexConfigFile = Join-Path $Script:CodexHome 'config.toml'
$Script:CodexAuthFile = Join-Path $Script:CodexHome 'auth.json'
$Script:ClaudeConfigFile = Join-Path $Script:ClaudeHome 'settings.json'
$Script:GeminiConfigFile = Join-Path $Script:GeminiHome 'settings.json'
$Script:GeminiEnvFile = Join-Path $Script:GeminiHome '.env'
$Script:LogRoot = Join-Path $env:USERPROFILE '.leung'
$Script:LogDir = Join-Path $Script:LogRoot 'logs'
$Script:LogFile = Join-Path $Script:LogDir ("install-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$Script:Failures = New-Object System.Collections.Generic.List[string]
$Script:Warnings = New-Object System.Collections.Generic.List[string]
$Script:Status = [ordered]@{}
$Script:DesktopInstallRequested = $false

$Script:Packages = @{
    codex = @{ Display = 'Codex CLI'; Command = 'codex'; Npm = '@openai/codex'; Winget = 'OpenAI.Codex' }
    claude = @{ Display = 'Claude Code'; Command = 'claude'; Npm = '@anthropic-ai/claude-code'; Winget = '' }
    gemini = @{ Display = 'Gemini CLI'; Command = 'gemini'; Npm = '@google/gemini-cli'; Winget = '' }
}

function Show-Usage {
@"
Windows installer for Codex Desktop / Codex CLI / Claude Code / Gemini CLI

Usage:
  powershell -ExecutionPolicy Bypass -File .\windows-installer\install.ps1
  powershell -ExecutionPolicy Bypass -File .\windows-installer\install.ps1 -NonInteractive -CodexApiKey <key> -ClaudeApiKey <key> -GeminiApiKey <key>
  powershell -ExecutionPolicy Bypass -File .\windows-installer\install.ps1 -ConfigOnly -CodexApiKey <key>

Optional component selectors:
  -InstallCodex -InstallClaude -InstallGemini -InstallDesktop
  If none are provided, all components are selected by default.
"@ | Write-Host
}

function Ensure-Dir([string]$Path) { if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }
Ensure-Dir $Script:LogDir
function Write-LogLine([string]$Level, [string]$Message) { Add-Content -Path $Script:LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" -Encoding UTF8 }
function Write-Info([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Cyan; Write-LogLine 'INFO' $Message }
function Write-Ok([string]$Message) { Write-Host "[ OK ] $Message" -ForegroundColor Green; Write-LogLine 'OK' $Message }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow; Write-LogLine 'WARN' $Message; $Script:Warnings.Add($Message) | Out-Null }
function Write-Fail([string]$Message) { Write-Host "[FAIL] $Message" -ForegroundColor Red; Write-LogLine 'FAIL' $Message; $Script:Failures.Add($Message) | Out-Null }
function Set-Status([string]$Name, [string]$Value) { $Script:Status[$Name] = $Value; Write-LogLine 'STATE' "$Name => $Value" }
function Write-Utf8NoBom([string]$Path, [string]$Content) { $enc = New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path, $Content, $enc) }
function Test-CommandAvailable([string]$Name) { try { $null = Get-Command $Name -ErrorAction Stop; return $true } catch { return $false } }
function Refresh-Path { try { $env:Path = ([Environment]::GetEnvironmentVariable('Path', 'Machine')) + ';' + ([Environment]::GetEnvironmentVariable('Path', 'User')) } catch {} }
function Try-SetExecutionPolicy {
    try {
        $current = Get-ExecutionPolicy -Scope CurrentUser
        if ($current -eq 'Restricted' -or $current -eq 'Undefined') {
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
            Write-Ok 'PowerShell execution policy set to RemoteSigned for current user.'
            Set-Status 'ExecutionPolicy' 'UpdatedToRemoteSigned'
            return
        }
        Set-Status 'ExecutionPolicy' $current
    } catch { Write-Warn 'Could not adjust PowerShell execution policy automatically.'; Set-Status 'ExecutionPolicy' 'Unchanged' }
}
function Get-CommandVersion([string]$CommandName) { try { $output = & $CommandName --version 2>&1; if ($LASTEXITCODE -eq 0 -and $output) { return ($output | Select-Object -First 1).ToString().Trim() } } catch {}; return '' }
function Test-CodexDesktopInstalled {
    $paths = @((Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe'), (Join-Path $env:PROGRAMFILES 'Codex\Codex.exe'), (Join-Path ${env:PROGRAMFILES(x86)} 'Codex\Codex.exe'))
    foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return $true } }
    try { $appx = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Codex' -or $_.Publisher -match 'OpenAI' }; if ($appx) { return $true } } catch {}
    return $false
}
function Resolve-Selection {
    $explicit = $InstallCodex -or $InstallClaude -or $InstallGemini -or $InstallDesktop
    if ($explicit) {
        return [ordered]@{ codex = [bool]$InstallCodex; claude = [bool]$InstallClaude; gemini = [bool]$InstallGemini; desktop = [bool]$InstallDesktop }
    }
    return [ordered]@{ codex = $true; claude = $true; gemini = $true; desktop = (-not $SkipDesktop) }
}
function Ensure-NodeInstalled {
    if ((Test-CommandAvailable 'node') -and (Test-CommandAvailable 'npm')) { Write-Ok 'Node.js and npm already available.'; Set-Status 'Node.js' ('Present: ' + (Get-CommandVersion 'node')); Set-Status 'npm' ('Present: ' + (Get-CommandVersion 'npm')); return }
    if ($SkipNodeInstall) { throw 'Node.js/npm missing and -SkipNodeInstall was set.' }
    if (-not (Test-CommandAvailable 'winget')) { throw 'Node.js/npm missing and winget is not available. Install Node.js LTS manually from https://nodejs.org/ and re-run.' }
    Write-Info 'Installing Node.js LTS via winget...'
    & winget install --id OpenJS.NodeJS.LTS --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw 'winget failed to install Node.js LTS.' }
    Refresh-Path
    if ((-not (Test-CommandAvailable 'node')) -or (-not (Test-CommandAvailable 'npm'))) {
        $nodeDir = Join-Path $env:ProgramFiles 'nodejs'
        if ((Test-Path $nodeDir) -and ($env:Path -notlike "*$nodeDir*")) { $env:Path = "$env:Path;$nodeDir" }
    }
    if ((-not (Test-CommandAvailable 'node')) -or (-not (Test-CommandAvailable 'npm'))) { throw 'Node.js installed but node/npm still not found in current session. Open a new PowerShell window and run again.' }
    Write-Ok 'Node.js LTS installed.'; Set-Status 'Node.js' ('Installed: ' + (Get-CommandVersion 'node')); Set-Status 'npm' ('Installed: ' + (Get-CommandVersion 'npm'))
}
function Install-NpmPackage([string]$CliName) {
    $pkg = $Script:Packages[$CliName]
    if (Test-CommandAvailable $pkg.Command) { $version = Get-CommandVersion $pkg.Command; Write-Ok "$($pkg.Display) already available."; Set-Status $pkg.Display $(if ($version) { 'Present: ' + $version } else { 'Present' }); return }
    $args = @('install', '-g', '--no-audit', '--no-fund', $pkg.Npm)
    if ($ForceNpm) {
        Write-Info "Installing $($pkg.Display) via npm..."; & npm @args; if ($LASTEXITCODE -ne 0) { throw "npm install failed for $($pkg.Display)." }
        $version = Get-CommandVersion $pkg.Command; Write-Ok "$($pkg.Display) installed via npm."; Set-Status $pkg.Display $(if ($version) { 'Installed via npm: ' + $version } else { 'Installed via npm' }); return
    }
    if ($CliName -eq 'codex' -and $pkg.Winget -and (Test-CommandAvailable 'winget')) {
        Write-Info 'Trying Codex CLI via winget first...'; & winget install --id $pkg.Winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements; Refresh-Path
        if (Test-CommandAvailable $pkg.Command) { $version = Get-CommandVersion $pkg.Command; Write-Ok "$($pkg.Display) installed via winget."; Set-Status $pkg.Display $(if ($version) { 'Installed via winget: ' + $version } else { 'Installed via winget' }); return }
        Write-Warn 'winget install for Codex CLI did not finish cleanly; falling back to npm.'
    }
    Write-Info "Installing $($pkg.Display) via npm..."; & npm @args; if ($LASTEXITCODE -ne 0) { throw "npm install failed for $($pkg.Display)." }
    $version = Get-CommandVersion $pkg.Command; Write-Ok "$($pkg.Display) installed via npm."; Set-Status $pkg.Display $(if ($version) { 'Installed via npm: ' + $version } else { 'Installed via npm' })
}
function Install-CodexDesktop {
    $Script:DesktopInstallRequested = $true
    if ($SkipDesktop) { Write-Warn 'Skipping Codex Desktop installation.'; Set-Status 'Codex Desktop' 'Skipped'; return }
    if (-not (Test-CommandAvailable 'winget')) { Write-Warn 'winget unavailable; cannot auto-install Codex Desktop. Install manually from Microsoft Store.'; Set-Status 'Codex Desktop' 'ManualInstallRequired'; return }
    Write-Info 'Installing Codex Desktop from Microsoft Store via winget...'; & winget install --id 9PLM9XGG6VKS --source msstore --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) { Write-Ok 'Codex Desktop installed (or already present).'; Set-Status 'Codex Desktop' 'InstalledOrPresent' } else { Write-Warn 'Codex Desktop auto-install failed. You can manually install: winget install --id 9PLM9XGG6VKS --source msstore'; Set-Status 'Codex Desktop' 'ManualInstallRequired' }
}
function Write-CodexConfig {
    Ensure-Dir $Script:CodexHome
    $config = @"
model_provider = "leung"
model = "$CodexModel"
model_reasoning_effort = "medium"
disable_response_storage = true

[model_providers.leung]
name = "LEUNG API"
base_url = "$CodexBaseUrl"
wire_api = "responses"
requires_openai_auth = true
model_context_window = 1000000
model_auto_compact_token_limit = 900000
"@
    Write-Utf8NoBom -Path $Script:CodexConfigFile -Content $config
    $auth = @{ OPENAI_API_KEY = $CodexApiKey } | ConvertTo-Json
    Write-Utf8NoBom -Path $Script:CodexAuthFile -Content $auth
    Write-Ok "Wrote $Script:CodexConfigFile and auth.json"; Set-Status 'Codex Config' 'Written'
}
function Write-ClaudeConfig {
    Ensure-Dir $Script:ClaudeHome
    $settings = [ordered]@{ ENABLE_TOOL_SEARCH = $true; skipWebFetchPreflight = $true; env = [ordered]@{ ANTHROPIC_API_KEY = $ClaudeApiKey; ANTHROPIC_BASE_URL = $ClaudeBaseUrl; ANTHROPIC_MODEL = $ClaudeModel; CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'; CLAUDE_CODE_DISABLE_TERMINAL_TITLE = '1'; CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS = '1' } }
    $json = $settings | ConvertTo-Json -Depth 5
    Write-Utf8NoBom -Path $Script:ClaudeConfigFile -Content $json
    Write-Ok "Wrote $Script:ClaudeConfigFile"; Set-Status 'Claude Config' 'Written'
}
function Write-GeminiConfig {
    Ensure-Dir $Script:GeminiHome
    $settings = [ordered]@{ security = [ordered]@{ auth = [ordered]@{ selectedType = 'gemini-api-key'; enforcedType = 'gemini-api-key' } }; model = [ordered]@{ name = $GeminiModel } }
    $json = $settings | ConvertTo-Json -Depth 5
    Write-Utf8NoBom -Path $Script:GeminiConfigFile -Content $json
    $envContent = @"
GOOGLE_GEMINI_BASE_URL=$GeminiBaseUrl
GEMINI_API_KEY=$GeminiApiKey
GEMINI_MODEL=$GeminiModel
"@
    Write-Utf8NoBom -Path $Script:GeminiEnvFile -Content $envContent
    Write-Ok "Wrote $Script:GeminiConfigFile and .env"; Set-Status 'Gemini Config' 'Written'
}
function Read-Secret([string]$Prompt) { $secure = Read-Host -AsSecureString $Prompt; $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure); try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) } finally { if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) } } }
function Collect-InteractiveInput {
    if ($Script:Selection.codex -and -not $CodexApiKey) { $script:CodexApiKey = Read-Secret 'Enter OPENAI_API_KEY for Codex' }
    if ($Script:Selection.claude -and -not $ClaudeApiKey) { $script:ClaudeApiKey = Read-Secret 'Enter ANTHROPIC_API_KEY for Claude Code' }
    if ($Script:Selection.gemini -and -not $GeminiApiKey) { $script:GeminiApiKey = Read-Secret 'Enter GEMINI_API_KEY for Gemini CLI' }
}
function Assert-FileExists([string]$Path, [string]$Label) { if (Test-Path $Path) { Write-Ok "$Label exists."; return $true }; Write-Fail "$Label missing: $Path"; return $false }
function Assert-FileContains([string]$Path, [string]$Pattern, [string]$Label) { if (-not (Test-Path $Path)) { Write-Fail "$Label missing before content check: $Path"; return $false }; $content = Get-Content -Path $Path -Raw -Encoding UTF8; if ($content -match $Pattern) { Write-Ok "$Label content verified."; return $true }; Write-Fail "$Label content check failed: pattern not found -> $Pattern"; return $false }
function Assert-CommandResolvable([string]$CommandName) { try { $cmd = Get-Command $CommandName -ErrorAction Stop; Write-Ok "$CommandName resolves to $($cmd.Source)"; return $true } catch { Write-Fail "$CommandName is not resolvable on PATH."; return $false } }
function Run-SelfCheck {
    if ($SkipSelfCheck) { Write-Warn 'Skipping self-check.'; Set-Status 'SelfCheck' 'Skipped'; return }
    Write-Info 'Running post-install self-check...'; $ok = $true
    if (-not (Test-CommandAvailable 'node')) { Write-Fail 'node command not found after installation.'; $ok = $false } else { if (-not (Assert-CommandResolvable 'node')) { $ok = $false }; $nodeVersion = Get-CommandVersion 'node'; if ($nodeVersion) { Write-Ok "node --version => $nodeVersion" } }
    if (-not (Test-CommandAvailable 'npm')) { Write-Fail 'npm command not found after installation.'; $ok = $false } else { if (-not (Assert-CommandResolvable 'npm')) { $ok = $false }; $npmVersion = Get-CommandVersion 'npm'; if ($npmVersion) { Write-Ok "npm --version => $npmVersion" } }
    if (-not $ConfigOnly) {
        foreach ($name in @('codex','claude','gemini')) {
            if (-not $Script:Selection[$name]) { continue }
            $pkg = $Script:Packages[$name]; $cmd = $pkg.Command
            if (Test-CommandAvailable $cmd) { if (-not (Assert-CommandResolvable $cmd)) { $ok = $false }; $version = Get-CommandVersion $cmd; Write-Ok "$cmd available" + $(if ($version) { ": $version" } else { '' }) }
            else { Write-Fail "$cmd command not found after installation."; $ok = $false }
        }
    }
    if ($Script:Selection.codex -and $CodexApiKey) {
        if (-not (Assert-FileExists $Script:CodexConfigFile 'Codex config.toml')) { $ok = $false }
        if (-not (Assert-FileExists $Script:CodexAuthFile 'Codex auth.json')) { $ok = $false }
        if (-not (Assert-FileContains $Script:CodexConfigFile 'model_provider\s*=\s*"leung"' 'Codex config.toml')) { $ok = $false }
        if (-not (Assert-FileContains $Script:CodexConfigFile 'base_url\s*=\s*"[^"]+"' 'Codex base_url')) { $ok = $false }
        if (-not (Assert-FileContains $Script:CodexAuthFile 'OPENAI_API_KEY' 'Codex auth.json')) { $ok = $false }
    }
    if ($Script:Selection.claude -and $ClaudeApiKey) {
        if (-not (Assert-FileExists $Script:ClaudeConfigFile 'Claude settings.json')) { $ok = $false }
        if (-not (Assert-FileContains $Script:ClaudeConfigFile 'ANTHROPIC_API_KEY' 'Claude settings.json')) { $ok = $false }
        if (-not (Assert-FileContains $Script:ClaudeConfigFile 'ANTHROPIC_BASE_URL' 'Claude settings base url')) { $ok = $false }
    }
    if ($Script:Selection.gemini -and $GeminiApiKey) {
        if (-not (Assert-FileExists $Script:GeminiConfigFile 'Gemini settings.json')) { $ok = $false }
        if (-not (Assert-FileExists $Script:GeminiEnvFile 'Gemini .env')) { $ok = $false }
        if (-not (Assert-FileContains $Script:GeminiConfigFile 'selectedType' 'Gemini auth config')) { $ok = $false }
        if (-not (Assert-FileContains $Script:GeminiEnvFile 'GEMINI_API_KEY=' 'Gemini .env')) { $ok = $false }
        if (-not (Assert-FileContains $Script:GeminiEnvFile 'GOOGLE_GEMINI_BASE_URL=' 'Gemini base url env')) { $ok = $false }
    }
    if ($Script:Selection.desktop -and (-not $SkipDesktop)) { if (Test-CodexDesktopInstalled) { Write-Ok 'Codex Desktop detection passed.' } else { Write-Warn 'Codex Desktop could not be verified locally after installation attempt.' } }
    if ($ok) { Write-Ok 'Self-check passed.'; Set-Status 'SelfCheck' 'Passed' } else { Set-Status 'SelfCheck' 'Failed'; throw 'Post-install self-check failed.' }
}
function Show-StatusTable { Write-Host ''; Write-Host 'Installation status:' -ForegroundColor Cyan; foreach ($key in $Script:Status.Keys) { Write-Host (("  - {0}: {1}" -f $key, $Script:Status[$key])) -ForegroundColor Gray } }
function Show-Summary {
    Write-Host ''; Write-Host 'Completed. Installed/configured:' -ForegroundColor Cyan
    if ($Script:Selection.codex) { Write-Host '  - Codex CLI via global npm package @openai/codex' -ForegroundColor Gray }
    if ($Script:Selection.claude) { Write-Host '  - Claude Code via global npm package @anthropic-ai/claude-code' -ForegroundColor Gray }
    if ($Script:Selection.gemini) { Write-Host '  - Gemini CLI via global npm package @google/gemini-cli' -ForegroundColor Gray }
    if ($Script:Selection.desktop) { Write-Host '  - Codex Desktop via Microsoft Store / winget' -ForegroundColor Gray }
    Show-StatusTable; Write-Host ''
    if ($Script:Warnings.Count -gt 0) { Write-Host 'Warnings:' -ForegroundColor Yellow; foreach ($item in $Script:Warnings) { Write-Host "  - $item" -ForegroundColor Yellow }; Write-Host '' }
    Write-Host ('Install log: ' + $Script:LogFile) -ForegroundColor DarkGray
    Write-Host 'Recommended next step: open a new PowerShell window and run:' -ForegroundColor Yellow
    if ($Script:Selection.codex) { Write-Host '  codex --version' -ForegroundColor White }
    if ($Script:Selection.claude) { Write-Host '  claude --version' -ForegroundColor White }
    if ($Script:Selection.gemini) { Write-Host '  gemini --version' -ForegroundColor White }
}
if ($Help) { Show-Usage; exit 0 }
Write-Info ('Writing log to ' + $Script:LogFile)
$Script:Selection = Resolve-Selection
try {
    Set-Status 'StartTime' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Try-SetExecutionPolicy
    Set-Status 'Selection' ((@($Script:Selection.GetEnumerator() | ForEach-Object { if ($_.Value) { $_.Key } }) -join ', '))
    if (-not $NonInteractive) { Collect-InteractiveInput }
    if (-not $ConfigOnly) {
        if ($Script:Selection.codex -or $Script:Selection.claude -or $Script:Selection.gemini) { Ensure-NodeInstalled }
        if ($Script:Selection.codex) { Install-NpmPackage 'codex' }
        if ($Script:Selection.claude) { Install-NpmPackage 'claude' }
        if ($Script:Selection.gemini) { Install-NpmPackage 'gemini' }
        if ($Script:Selection.desktop) { Install-CodexDesktop }
    } else { Set-Status 'InstallMode' 'ConfigOnly' }
    if ($Script:Selection.codex) { if ($CodexApiKey) { Write-CodexConfig } else { Write-Warn 'Codex API key not provided; skipped Codex auth/config.'; Set-Status 'Codex Config' 'Skipped' } }
    if ($Script:Selection.claude) { if ($ClaudeApiKey) { Write-ClaudeConfig } else { Write-Warn 'Claude API key not provided; skipped Claude config.'; Set-Status 'Claude Config' 'Skipped' } }
    if ($Script:Selection.gemini) { if ($GeminiApiKey) { Write-GeminiConfig } else { Write-Warn 'Gemini API key not provided; skipped Gemini config.'; Set-Status 'Gemini Config' 'Skipped' } }
    Run-SelfCheck; Set-Status 'Result' 'Success'; Show-Summary; exit 0
} catch {
    $msg = $_.Exception.Message; if (-not [string]::IsNullOrWhiteSpace($msg)) { Write-Fail $msg }
    Set-Status 'Result' 'Failed'; Show-StatusTable
    if ($Script:Failures.Count -gt 0) { Write-Host ''; Write-Host 'Failures:' -ForegroundColor Red; foreach ($item in $Script:Failures) { Write-Host "  - $item" -ForegroundColor Red } }
    Write-Host ''; Write-Host ('Install log: ' + $Script:LogFile) -ForegroundColor DarkGray; exit 1
}
