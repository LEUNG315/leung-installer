#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LEUNG_HOME = Join-Path $env:USERPROFILE '.leung'
$script:CODEX_HOME = Join-Path $env:USERPROFILE '.codex'
$script:CODEX_CONFIG_FILE = Join-Path $script:CODEX_HOME 'config.toml'
$script:CODEX_AUTH_FILE = Join-Path $script:CODEX_HOME 'auth.json'
$script:CLAUDE_HOME = Join-Path $env:USERPROFILE '.claude'
$script:CLAUDE_CONFIG_FILE = Join-Path $script:CLAUDE_HOME 'settings.json'
$script:GEMINI_HOME = Join-Path $env:USERPROFILE '.gemini'
$script:GEMINI_CONFIG_FILE = Join-Path $script:GEMINI_HOME 'settings.json'
$script:GEMINI_ENV_FILE = Join-Path $script:GEMINI_HOME '.env'
$script:LEUNG_LOG_DIR = Join-Path $script:LEUNG_HOME 'logs'
$script:LEUNG_LOG_FILE = Join-Path $script:LEUNG_LOG_DIR "install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

$script:LEUNG_DEFAULT_CODEX_URL = 'https://api.leung315.site/v1'
$script:LEUNG_DEFAULT_CLAUDE_URL = 'https://api.leung315.site'
$script:LEUNG_DEFAULT_GEMINI_URL = 'https://api.leung315.site'
$script:LEUNG_DEFAULT_CODEX_MODEL = 'gpt-5.4'
$script:LEUNG_DEFAULT_CLAUDE_MODEL = 'claude-sonnet-4-5'
$script:LEUNG_DEFAULT_GEMINI_MODEL = 'gemini-2.5-pro'
$script:LEUNG_PROVIDER_NAME = 'leung'
$script:LEUNG_PROVIDER_DISPLAY = 'LEUNG API'

$script:CODEX_FALLBACK_TAG = 'rust-v0.137.0'
$script:CODEX_FALLBACK_SHA256 = '0000000000000000000000000000000000000000000000000000000000000000'
$script:GITHUB_RELEASE_BASE = 'https://github.com'
$script:GITHUB_PROXY_BASE = 'https://ghproxy.net/'
$script:NPM_REGISTRY_MIRROR = 'https://registry.npmmirror.com'

# Optional progress sink. The GUI runs installers in a background runspace and
# sets this to the shared ConcurrentQueue so every Write-* line and live
# progress heartbeat surfaces in the UI log. In CLI mode it stays $null and
# output goes to the console only.
$script:LeungLogQueue = $null

function Send-LeungProgress {
    param([string]$Line)
    if ($null -ne $script:LeungLogQueue) {
        try { $null = $script:LeungLogQueue.Enqueue($Line) } catch {}
    }
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    # Windows PowerShell 5.1 'Set-Content -Encoding UTF8' prepends a UTF-8 BOM,
    # which strict parsers reject — serde_json fails with
    # "expected value at line 1 column 1", and TOML/dotenv readers choke too.
    # Write raw UTF-8 with NO BOM and no trailing newline.
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Set-PsExecutionPolicyIfNeeded {
    # npm-installed CLIs (claude, gemini) ship a .ps1 shim alongside the .cmd one.
    # If the user's PowerShell execution policy is Restricted (the Windows default),
    # typing "claude" or "gemini" in PowerShell will fail with
    # "cannot be loaded because running scripts is disabled on this system".
    # Fix it by setting the per-user policy to RemoteSigned — only affects the
    # current user, does NOT require admin, and is safe (local scripts + npm shims
    # run; only unsigned scripts downloaded from the internet are blocked).
    try {
        $current = Get-ExecutionPolicy -Scope CurrentUser
        if ($current -eq 'Restricted' -or $current -eq 'Undefined') {
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
            $after = Get-ExecutionPolicy -Scope CurrentUser
            if ($after -ne 'Restricted' -and $after -ne 'Undefined') {
                Write-Log "PowerShell ExecutionPolicy set to $after (was $current)."
                return $true
            }
        }
    } catch {}
    return $false
}

$script:CLI_REGISTRY = @{
    codex = @{
        DisplayName = 'Codex CLI'
        BinaryName  = 'codex'
        NpmPackage  = '@openai/codex'
        WingetId    = 'OpenAI.Codex'
    }
    claude = @{
        DisplayName = 'Claude Code'
        BinaryName  = 'claude'
        NpmPackage  = '@anthropic-ai/claude-code'
        WingetId    = ''
    }
    gemini = @{
        DisplayName = 'Gemini CLI'
        BinaryName  = 'gemini'
        NpmPackage  = '@google/gemini-cli'
        WingetId    = ''
    }
}

function Ensure-LeungDirectories {
    @(
        $script:LEUNG_HOME, $script:LEUNG_LOG_DIR,
        $script:CODEX_HOME, $script:CLAUDE_HOME, $script:GEMINI_HOME
    ) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    if (Test-Path (Split-Path $script:LEUNG_LOG_FILE -Parent)) {
        Add-Content -Path $script:LEUNG_LOG_FILE -Value $line -Encoding UTF8
    }
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line -ForegroundColor Gray }
    }
    switch ($Level) {
        'ERROR' { Send-LeungProgress "[ERROR] $Message" }
        'WARN'  { Send-LeungProgress "[WARN] $Message" }
        default { Send-LeungProgress $Message }
    }
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n>> $Message" -ForegroundColor Cyan
    Write-Log $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
    Write-Log $Message
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    Write-Log $Message 'ERROR'
}

# Run an external command (winget/npm/etc.) with a hard timeout and a live
# progress heartbeat. stdout/stderr are redirected to temp files (so a chatty
# child can never deadlock on a full pipe buffer), the process is polled once a
# second, and every few seconds an elapsed-time line — plus any "NN%" the tool
# printed — is pushed to the progress sink so the UI shows liveness instead of
# freezing. If the timeout is hit the process tree is killed and TimedOut is set.
#
# Returns @{ ExitCode = <int>; TimedOut = <bool>; Output = <string> }.
function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 600,
        [int]$HeartbeatSeconds = 5,
        [string]$Label = 'process'
    )

    $stamp   = Get-Date -Format 'yyyyMMddHHmmssfff'
    $outFile = Join-Path $env:TEMP "leung-proc-$stamp-out.txt"
    $errFile = Join-Path $env:TEMP "leung-proc-$stamp-err.txt"
    New-Item -ItemType File -Path $outFile -Force | Out-Null
    New-Item -ItemType File -Path $errFile -Force | Out-Null

    # Heartbeat/status lines go to the GUI sink (when set) AND the console. In GUI
    # mode the runspace console is hidden, so only the sink shows; in CLI mode the
    # sink is null, so only the console shows. Either way: one visible line.
    function emit([string]$m) {
        Send-LeungProgress $m
        Write-Host $m -ForegroundColor DarkGray
    }

    emit "[..] $Label starting..."

    try {
        $startArgs = @{
            FilePath               = $FilePath
            PassThru               = $true
            NoNewWindow            = $true
            RedirectStandardOutput = $outFile
            RedirectStandardError  = $errFile
        }
        if ($ArgumentList.Count -gt 0) { $startArgs.ArgumentList = $ArgumentList }
        $proc = Start-Process @startArgs

        # Touch .Handle while the process is alive so .NET caches it; without this,
        # Start-Process -PassThru objects often return $null for .ExitCode after the
        # process exits — which would make a SUCCESSFUL command look like a failure.
        try { $null = $proc.Handle } catch {}

        $elapsed  = 0
        $timedOut = $false
        while (-not $proc.HasExited) {
            Start-Sleep -Seconds 1
            $elapsed++

            if ($elapsed -ge $TimeoutSeconds) {
                $timedOut = $true
                # /T kills the whole tree (cmd.exe -> npm -> node), so a hung child
                # can't keep running and holding the global install lock.
                try { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null } catch {}
                try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
                break
            }

            if (($elapsed % $HeartbeatSeconds) -eq 0) {
                $pct = ''
                try {
                    $raw = Get-Content -Path $outFile -Raw -ErrorAction SilentlyContinue
                    if ($raw) {
                        $m = [regex]::Matches($raw, '(\d{1,3})\s*%')
                        if ($m.Count -gt 0) { $pct = " $($m[$m.Count - 1].Groups[1].Value)%" }
                    }
                } catch {}
                Send-LeungProgress "[..] $Label running... ${elapsed}s elapsed$pct"
                Write-Host "[..] $Label running... ${elapsed}s elapsed$pct" -ForegroundColor DarkGray
            }
        }

        if (-not $timedOut) { $proc.WaitForExit() }

        if ($timedOut) {
            $exitCode = -1
        } elseif ($null -eq $proc.ExitCode) {
            # The process exited but we couldn't read its code (rare). It did exit
            # normally, so treat as success rather than a spurious failure.
            $exitCode = 0
        } else {
            $exitCode = $proc.ExitCode
        }
        $output   = ''
        try {
            $o = Get-Content -Path $outFile -Raw -ErrorAction SilentlyContinue
            $e = Get-Content -Path $errFile -Raw -ErrorAction SilentlyContinue
            $output = "$o`n$e".Trim()
        } catch {}

        if ($timedOut) {
            emit "[WARN] $Label timed out after ${TimeoutSeconds}s; process killed."
        }

        return @{ ExitCode = $exitCode; TimedOut = $timedOut; Output = $output }
    } finally {
        Remove-Item -Path $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}
