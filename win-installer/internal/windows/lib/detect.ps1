#Requires -Version 5.1

function Test-WingetAvailable {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-NpmAvailable {
    try {
        $null = Get-Command npm -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-NodeAvailable {
    try {
        $null = Get-Command node -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-CliInstalled {
    param([string]$CliName)
    $binary = $script:CLI_REGISTRY[$CliName].BinaryName
    try {
        $null = Get-Command $binary -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-CliVersion {
    param([string]$CliName)
    $binary = $script:CLI_REGISTRY[$CliName].BinaryName
    try {
        $output = & $binary --version 2>&1
        if ($LASTEXITCODE -eq 0) { return "$output".Trim() }
    } catch {}
    return $null
}

function Test-CodexDesktopInstalled {
    # 1) Standalone exe locations (cheap first check, covers any non-Store build).
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe'),
        (Join-Path $env:PROGRAMFILES 'Codex\Codex.exe'),
        (Join-Path ${env:PROGRAMFILES(x86)} 'Codex\Codex.exe')
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }

    # 2) The Store build is an MSIX package — look it up by name/publisher.
    try {
        $appx = Get-AppxPackage -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Codex' -or $_.Publisher -match 'OpenAI' }
        if ($appx) { return $true }
    } catch {}

    # 3) Fall back to asking winget about the Store product id.
    if (Test-WingetAvailable) {
        try {
            # --accept-source-agreements + --disable-interactivity prevent winget's
            # first-run source-agreement Y/N prompt from blocking forever in a
            # background runspace that has no console/stdin attached. The timeout
            # helper is a second backstop in case winget hangs for any other reason.
            $r = Invoke-ProcessWithTimeout -FilePath 'winget' -Label 'Detecting Codex Desktop' -TimeoutSeconds 90 -ArgumentList @(
                'list', '--id', '9PLM9XGG6VKS', '--source', 'msstore',
                '--accept-source-agreements', '--disable-interactivity'
            )
            if (-not $r.TimedOut -and $r.Output -match '9PLM9XGG6VKS|Codex') { return $true }
        } catch {}
    }
    return $false
}

function Test-ConfigExists {
    param([string]$CliName)
    switch ($CliName) {
        'codex'  { return (Test-Path $script:CODEX_CONFIG_FILE) }
        'claude' { return (Test-Path $script:CLAUDE_CONFIG_FILE) }
        'gemini' { return (Test-Path $script:GEMINI_CONFIG_FILE) }
    }
    return $false
}

function Get-WindowsVersion {
    $os = Get-CimInstance Win32_OperatingSystem
    return @{
        Caption = $os.Caption
        Version = $os.Version
        Build   = $os.BuildNumber
        Arch    = $env:PROCESSOR_ARCHITECTURE
    }
}

function Get-SystemStatus {
    $status = @{
        WingetAvailable       = Test-WingetAvailable
        NpmAvailable          = Test-NpmAvailable
        NodeAvailable         = Test-NodeAvailable
        CodexCliInstalled     = Test-CliInstalled 'codex'
        CodexCliVersion       = Get-CliVersion 'codex'
        ClaudeCliInstalled    = Test-CliInstalled 'claude'
        ClaudeCliVersion      = Get-CliVersion 'claude'
        GeminiCliInstalled    = Test-CliInstalled 'gemini'
        GeminiCliVersion      = Get-CliVersion 'gemini'
        CodexDesktopInstalled = Test-CodexDesktopInstalled
        CodexConfigExists     = Test-ConfigExists 'codex'
        ClaudeConfigExists    = Test-ConfigExists 'claude'
        GeminiConfigExists    = Test-ConfigExists 'gemini'
        Windows               = Get-WindowsVersion
    }
    return $status
}
