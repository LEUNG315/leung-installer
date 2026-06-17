#Requires -Version 5.1

function Install-NodeViaWinget {
    # Install Node.js LTS through winget when npm is missing and no offline Node
    # bundle is present, then refresh PATH so npm/node are usable in this process.
    if (-not (Test-WingetAvailable)) { return $false }
    Write-Log "Node.js/npm not found — installing Node.js LTS via winget..."
    try {
        $r = Invoke-ProcessWithTimeout -FilePath 'winget' -Label 'Node.js LTS (winget)' -TimeoutSeconds 600 -ArgumentList @(
            'install', '--id', 'OpenJS.NodeJS.LTS',
            '--silent', '--disable-interactivity',
            '--accept-package-agreements', '--accept-source-agreements'
        )
        if ($r.TimedOut) { Write-Log "Node.js winget install timed out." 'WARN'; return $false }
        if ($r.ExitCode -ne 0) { Write-Log "Node.js winget returned exit $($r.ExitCode). $($r.Output)" 'WARN'; return $false }
    } catch {
        Write-Log "Node.js winget failed: $($_.Exception.Message)" 'WARN'
        return $false
    }

    # winget installs to %ProgramFiles%\nodejs but does not update THIS process's
    # PATH — rebuild it from the machine+user values and add the dir explicitly.
    try {
        $machine = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        $user    = [Environment]::GetEnvironmentVariable('PATH', 'User')
        $env:PATH = "$machine;$user"
    } catch {}
    $nodeDir = Join-Path $env:ProgramFiles 'nodejs'
    if ((Test-Path $nodeDir) -and ($env:PATH -notlike "*$nodeDir*")) {
        $env:PATH = "$env:PATH;$nodeDir"
    }

    if ((Test-Path (Join-Path $nodeDir 'npm.cmd')) -or (Test-NpmAvailable)) {
        Write-Success "Node.js LTS installed."
        return $true
    }
    Write-Log "Node.js installed but npm still not detected on PATH." 'WARN'
    return $false
}

function Install-CliViaNpm {
    param([string]$CliName)
    $pkg = $script:CLI_REGISTRY[$CliName].NpmPackage
    $display = $script:CLI_REGISTRY[$CliName].DisplayName

    if (-not (Test-NpmAvailable)) {
        # Try, in order: offline Node bundle, then winget (OpenJS.NodeJS.LTS).
        $nodeOk = $false
        if (Install-NodeFromBundle) { $nodeOk = (Test-NpmAvailable) }
        if (-not $nodeOk) { $nodeOk = (Install-NodeViaWinget) }
        if (-not $nodeOk) {
            Write-Fail "npm is not available and Node.js auto-install failed. Install Node.js LTS from https://nodejs.org/ then re-run."
            return $false
        }
    }

    # Try bundle/cache first
    if (Install-NpmFromBundle -Package $pkg) {
        return $true
    }

    # Tell npm to fail fast on a dead/slow socket instead of hanging forever, and
    # skip audit/fund chatter. (npm is a .cmd shim, so we invoke it through cmd.exe
    # — Start-Process -NoNewWindow does not resolve PATHEXT.)
    $npmNet = @('--fetch-timeout=60000', '--fetch-retries=2', '--fetch-retry-maxtimeout=60000', '--no-audit', '--no-fund')

    # Mirror FIRST: this installer targets users who typically can't reach the
    # default npm registry reliably, where `npm install -g` would otherwise stall.
    Write-Log "Installing $display via npm mirror ($pkg)..."
    try {
        $r = Invoke-ProcessWithTimeout -FilePath 'cmd.exe' -Label "$display (npm mirror)" -TimeoutSeconds 300 -ArgumentList (
            @('/c', 'npm', 'install', '-g', '--registry', $script:NPM_REGISTRY_MIRROR) + $npmNet + @($pkg)
        )
        if (-not $r.TimedOut -and $r.ExitCode -eq 0) {
            Write-Success "$display installed via npm mirror."
            return $true
        }
        if ($r.TimedOut) { Write-Log "npm mirror install timed out, trying default registry..." 'WARN' }
        else { Write-Log "npm mirror install failed (exit $($r.ExitCode)), trying default registry..." 'WARN' }
    } catch {
        Write-Log "npm mirror error: $($_.Exception.Message)" 'WARN'
    }

    Write-Log "Installing $display via npm default registry ($pkg)..."
    try {
        $r = Invoke-ProcessWithTimeout -FilePath 'cmd.exe' -Label "$display (npm)" -TimeoutSeconds 300 -ArgumentList (
            @('/c', 'npm', 'install', '-g') + $npmNet + @($pkg)
        )
        if (-not $r.TimedOut -and $r.ExitCode -eq 0) {
            Write-Success "$display installed via npm."
            return $true
        }
        if ($r.TimedOut) { Write-Log "npm default registry install timed out." 'WARN' }
        else { Write-Log "npm default registry install failed (exit $($r.ExitCode))." 'WARN' }
    } catch {
        Write-Log "npm install error: $($_.Exception.Message)" 'WARN'
    }

    Write-Fail "$display npm installation failed."
    return $false
}

function Install-CodexCli {
    Write-Step "Installing Codex CLI..."

    if (Test-WingetAvailable) {
        Write-Log "Trying winget install (silent)..."
        try {
            $r = Invoke-ProcessWithTimeout -FilePath 'winget' -Label 'Codex CLI (winget)' -TimeoutSeconds 600 -ArgumentList @(
                'install', '--id', 'OpenAI.Codex',
                '--silent', '--disable-interactivity',
                '--accept-package-agreements', '--accept-source-agreements'
            )
            if (-not $r.TimedOut -and $r.ExitCode -eq 0) {
                Write-Success "Codex CLI installed via winget."
                return $true
            }
            if ($r.TimedOut) { Write-Log "winget install timed out; falling back." 'WARN' }
            else { Write-Log "winget returned exit code $($r.ExitCode)" 'WARN' }
        } catch {
            Write-Log "winget failed: $($_.Exception.Message)" 'WARN'
        }
    }

    if (Install-CliViaNpm 'codex') { return $true }

    Write-Log "Falling back to GitHub release binary..." 'WARN'
    return Install-CodexCliFromRelease
}

function Install-CodexCliFromRelease {
    $tag = $script:CODEX_FALLBACK_TAG
    $filename = 'codex-x86_64-pc-windows-msvc.exe'
    $primaryUrl = "$($script:GITHUB_RELEASE_BASE)/openai/codex/releases/download/$tag/$filename"
    $mirrorUrl = Get-GithubProxyUrl $primaryUrl

    $tempDir = Join-Path $env:TEMP "leung-codex-install-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $destFile = Join-Path $tempDir $filename

    try {
        $downloaded = Invoke-DownloadWithFallback `
            -Filename $filename `
            -PrimaryUrl $primaryUrl `
            -MirrorUrl $mirrorUrl `
            -Destination $destFile `
            -ExpectedSha256 $script:CODEX_FALLBACK_SHA256

        if (-not $downloaded) {
            Write-Fail "Failed to download Codex CLI binary."
            return $false
        }

        $installDir = Join-Path $env:LOCALAPPDATA 'Programs\CodexCli'
        if (-not (Test-Path $installDir)) {
            New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        }
        $targetPath = Join-Path $installDir 'codex.exe'
        Copy-Item -Path $destFile -Destination $targetPath -Force

        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($userPath -notlike "*$installDir*") {
            [Environment]::SetEnvironmentVariable('PATH', "$userPath;$installDir", 'User')
            $env:PATH = "$env:PATH;$installDir"
            Write-Log "Added $installDir to user PATH."
        }

        Write-Success "Codex CLI installed to $targetPath"
        return $true
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-ClaudeCli {
    Write-Step "Installing Claude Code..."

    if (Install-CliViaNpm 'claude') { return $true }

    Write-Host ""
    Write-Host "  Claude Code installation failed." -ForegroundColor Yellow
    Write-Host "  You can install manually: npm install -g @anthropic-ai/claude-code" -ForegroundColor White
    Write-Host ""
    return $false
}

function Install-GeminiCli {
    Write-Step "Installing Gemini CLI..."

    if (Install-CliViaNpm 'gemini') { return $true }

    Write-Host ""
    Write-Host "  Gemini CLI installation failed." -ForegroundColor Yellow
    Write-Host "  You can install manually: npm install -g @google/gemini-cli" -ForegroundColor White
    Write-Host ""
    return $false
}

function Install-Cli {
    param([string]$CliName)
    switch ($CliName) {
        'codex'  { return Install-CodexCli }
        'claude' { return Install-ClaudeCli }
        'gemini' { return Install-GeminiCli }
    }
    return $false
}

function Install-CodexDesktop {
    Write-Step "Installing Codex Desktop..."

    if (Test-WingetAvailable) {
        Write-Log "Trying winget install for Codex Desktop (Microsoft Store)..."
        try {
            # Codex Desktop ships as a Microsoft Store (MSIX) app. Its winget id is
            # the Store product id 9PLM9XGG6VKS from the 'msstore' source — NOT
            # 'OpenAI.Codex.Desktop', which does not exist and silently fails.
            # --silent + --disable-interactivity keep the Store installer from
            # popping its own UI; our timeout helper backstops any hang.
            $r = Invoke-ProcessWithTimeout -FilePath 'winget' -Label 'Codex Desktop (winget)' -TimeoutSeconds 900 -ArgumentList @(
                'install', '--id', '9PLM9XGG6VKS', '--source', 'msstore',
                '--silent', '--disable-interactivity',
                '--accept-package-agreements', '--accept-source-agreements'
            )
            if (-not $r.TimedOut -and $r.ExitCode -eq 0) {
                Write-Success "Codex Desktop installed via Microsoft Store."
                return $true
            }
            if ($r.TimedOut) { Write-Log "winget Desktop install timed out." 'WARN' }
            else { Write-Log "winget Desktop returned exit code $($r.ExitCode). $($r.Output)" 'WARN' }
        } catch {
            Write-Log "winget Desktop failed: $($_.Exception.Message)" 'WARN'
        }
    }

    Write-Host ""
    Write-Host "  Codex Desktop could not be installed automatically." -ForegroundColor Yellow
    Write-Host "  Install it manually with one of:" -ForegroundColor Yellow
    Write-Host "    winget install --id 9PLM9XGG6VKS --source msstore" -ForegroundColor White
    Write-Host "    Microsoft Store - search 'Codex'" -ForegroundColor White
    Write-Host "    https://developers.openai.com/codex/windows" -ForegroundColor White
    Write-Host ""
    Write-Log "Codex Desktop: manual installation required (winget unavailable or install failed)." 'WARN'
    return $false
}
