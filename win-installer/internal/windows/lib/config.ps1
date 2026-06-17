#Requires -Version 5.1

function Write-CodexConfig {
    param(
        [string]$ApiKey,
        [string]$BaseUrl = $script:LEUNG_DEFAULT_CODEX_URL,
        [string]$Model = $script:LEUNG_DEFAULT_CODEX_MODEL
    )

    if (-not (Test-Path $script:CODEX_HOME)) {
        New-Item -ItemType Directory -Path $script:CODEX_HOME -Force | Out-Null
    }

    $configContent = @"
model_provider = "leung"
model = "$Model"
model_reasoning_effort = "high"
disable_response_storage = true

[model_providers.leung]
name = "LEUNG API"
base_url = "$BaseUrl"
wire_api = "responses"
requires_openai_auth = true
model_context_window = 1000000
model_auto_compact_token_limit = 900000
"@

    Write-Utf8NoBom -Path $script:CODEX_CONFIG_FILE -Content $configContent
    Write-Log "Written: $($script:CODEX_CONFIG_FILE)"

    $authContent = @{ OPENAI_API_KEY = $ApiKey } | ConvertTo-Json
    Write-Utf8NoBom -Path $script:CODEX_AUTH_FILE -Content $authContent
    Write-Log "Written: $($script:CODEX_AUTH_FILE)"
}

function Write-ClaudeConfig {
    param(
        [string]$ApiKey,
        [string]$BaseUrl = $script:LEUNG_DEFAULT_CLAUDE_URL,
        [string]$Model = $script:LEUNG_DEFAULT_CLAUDE_MODEL
    )

    if (-not (Test-Path $script:CLAUDE_HOME)) {
        New-Item -ItemType Directory -Path $script:CLAUDE_HOME -Force | Out-Null
    }

    $settings = [ordered]@{
        ENABLE_TOOL_SEARCH     = $true
        skipWebFetchPreflight  = $true
        env = [ordered]@{
            ANTHROPIC_BASE_URL                      = $BaseUrl
            ANTHROPIC_API_KEY                       = $ApiKey
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
            CLAUDE_CODE_DISABLE_TERMINAL_TITLE       = '1'
            CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS   = '1'
        }
    }

    $json = $settings | ConvertTo-Json -Depth 4
    Write-Utf8NoBom -Path $script:CLAUDE_CONFIG_FILE -Content $json
    Write-Log "Written: $($script:CLAUDE_CONFIG_FILE)"
}

function Write-GeminiConfig {
    param(
        [string]$ApiKey,
        [string]$BaseUrl = $script:LEUNG_DEFAULT_GEMINI_URL,
        [string]$Model = $script:LEUNG_DEFAULT_GEMINI_MODEL
    )

    if (-not (Test-Path $script:GEMINI_HOME)) {
        New-Item -ItemType Directory -Path $script:GEMINI_HOME -Force | Out-Null
    }

    # Gemini CLI expects security.auth to know which auth method to use, and
    # model.name (not a flat "model" string). This matches the Linux template.
    $settings = [ordered]@{
        security = [ordered]@{
            auth = [ordered]@{
                selectedType = 'gemini-api-key'
                enforcedType = 'gemini-api-key'
            }
        }
        model = [ordered]@{
            name = $Model
        }
    }

    $json = $settings | ConvertTo-Json -Depth 4
    Write-Utf8NoBom -Path $script:GEMINI_CONFIG_FILE -Content $json
    Write-Log "Written: $($script:GEMINI_CONFIG_FILE)"

    # .env — Gemini CLI reads GOOGLE_GEMINI_BASE_URL (not GEMINI_API_BASE_URL)
    $envContent = @"
GOOGLE_GEMINI_BASE_URL=$BaseUrl
GEMINI_API_KEY=$ApiKey
GEMINI_MODEL=$Model
"@
    Write-Utf8NoBom -Path $script:GEMINI_ENV_FILE -Content $envContent
    Write-Log "Written: $($script:GEMINI_ENV_FILE)"
}

function Write-CliConfig {
    param(
        [string]$CliName,
        [string]$ApiKey,
        [string]$BaseUrl,
        [string]$Model
    )
    switch ($CliName) {
        'codex' {
            $url = if ($BaseUrl) { $BaseUrl } else { $script:LEUNG_DEFAULT_CODEX_URL }
            $m = if ($Model) { $Model } else { $script:LEUNG_DEFAULT_CODEX_MODEL }
            Write-CodexConfig -ApiKey $ApiKey -BaseUrl $url -Model $m
        }
        'claude' {
            $url = if ($BaseUrl) { $BaseUrl } else { $script:LEUNG_DEFAULT_CLAUDE_URL }
            $m = if ($Model) { $Model } else { $script:LEUNG_DEFAULT_CLAUDE_MODEL }
            Write-ClaudeConfig -ApiKey $ApiKey -BaseUrl $url -Model $m
        }
        'gemini' {
            $url = if ($BaseUrl) { $BaseUrl } else { $script:LEUNG_DEFAULT_GEMINI_URL }
            $m = if ($Model) { $Model } else { $script:LEUNG_DEFAULT_GEMINI_MODEL }
            Write-GeminiConfig -ApiKey $ApiKey -BaseUrl $url -Model $m
        }
    }
}

function Get-CurrentCliConfig {
    param([string]$CliName)
    $result = @{ Url = ''; ApiKey = ''; Model = '' }

    switch ($CliName) {
        'codex' {
            if (Test-Path $script:CODEX_CONFIG_FILE) {
                $content = Get-Content -Path $script:CODEX_CONFIG_FILE -Raw -Encoding UTF8
                if ($content -match 'base_url\s*=\s*"([^"]+)"') { $result.Url = $Matches[1] }
                if ($content -match '(?m)^model\s*=\s*"([^"]+)"') { $result.Model = $Matches[1] }
            }
            if (Test-Path $script:CODEX_AUTH_FILE) {
                try {
                    $auth = Get-Content -Path $script:CODEX_AUTH_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($auth.OPENAI_API_KEY) { $result.ApiKey = $auth.OPENAI_API_KEY }
                } catch {}
            }
        }
        'claude' {
            if (Test-Path $script:CLAUDE_CONFIG_FILE) {
                try {
                    $cfg = Get-Content -Path $script:CLAUDE_CONFIG_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($cfg.env.ANTHROPIC_BASE_URL) { $result.Url = $cfg.env.ANTHROPIC_BASE_URL }
                    if ($cfg.env.ANTHROPIC_API_KEY) { $result.ApiKey = $cfg.env.ANTHROPIC_API_KEY }
                } catch {}
            }
        }
        'gemini' {
            if (Test-Path $script:GEMINI_CONFIG_FILE) {
                try {
                    $cfg = Get-Content -Path $script:GEMINI_CONFIG_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($cfg.model.name) { $result.Model = $cfg.model.name }
                    elseif ($cfg.model -and $cfg.model -is [string]) { $result.Model = $cfg.model }
                } catch {}
            }
            if (Test-Path $script:GEMINI_ENV_FILE) {
                $envContent = Get-Content -Path $script:GEMINI_ENV_FILE -Raw -Encoding UTF8
                if ($envContent -match 'GEMINI_API_KEY=(.+)') { $result.ApiKey = $Matches[1].Trim() }
                if ($envContent -match 'GOOGLE_GEMINI_BASE_URL=(.+)') { $result.Url = $Matches[1].Trim() }
                elseif ($envContent -match 'GEMINI_API_BASE_URL=(.+)') { $result.Url = $Matches[1].Trim() }
            }
        }
    }
    return $result
}

function Show-AllConfigSummary {
    Write-Host ""
    Write-Host "  Current Configuration:" -ForegroundColor Cyan
    foreach ($cli in @('codex', 'claude', 'gemini')) {
        $display = $script:CLI_REGISTRY[$cli].DisplayName
        $config = Get-CurrentCliConfig $cli
        if ($config.Url -or $config.ApiKey) {
            Write-Host "    [$display]" -ForegroundColor White
            if ($config.Url) { Write-Host "      URL:   $($config.Url)" -ForegroundColor Gray }
            if ($config.Model) { Write-Host "      Model: $($config.Model)" -ForegroundColor Gray }
            if ($config.ApiKey) {
                $masked = $config.ApiKey.Substring(0, [Math]::Min(8, $config.ApiKey.Length)) + '...'
                Write-Host "      Key:   $masked" -ForegroundColor Gray
            }
        }
    }
    Write-Host ""
}
