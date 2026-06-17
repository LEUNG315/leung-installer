#Requires -Version 5.1

# Resolve bundles directory
$script:BUNDLES_DIR = ''
$script:BUNDLES_DOWNLOADS_DIR = ''
$script:BUNDLES_NPM_CACHE_DIR = ''
$script:LOCAL_CACHE_DIR = Join-Path $script:LEUNG_HOME 'cache'

$_bundlesPath = Join-Path (Split-Path -Parent $PSScriptRoot) '..\..\bundles'
if (Test-Path $_bundlesPath) {
    $script:BUNDLES_DIR = (Resolve-Path $_bundlesPath).Path
    $script:BUNDLES_DOWNLOADS_DIR = Join-Path $script:BUNDLES_DIR 'downloads'
    $script:BUNDLES_NPM_CACHE_DIR = Join-Path $script:BUNDLES_DIR 'npm-cache'
}

function Test-BundleFile {
    param([string]$Filename)
    return ($script:BUNDLES_DOWNLOADS_DIR -and (Test-Path (Join-Path $script:BUNDLES_DOWNLOADS_DIR $Filename)))
}

function Copy-BundleFile {
    param([string]$Filename, [string]$Destination)
    if (Test-BundleFile $Filename) {
        $src = Join-Path $script:BUNDLES_DOWNLOADS_DIR $Filename
        Copy-Item -Path $src -Destination $Destination -Force
        Write-Log "Loaded from bundle: $Filename"
        return $true
    }
    return $false
}

function Test-CacheFile {
    param([string]$Filename)
    return (Test-Path (Join-Path $script:LOCAL_CACHE_DIR $Filename))
}

function Copy-CacheFile {
    param([string]$Filename, [string]$Destination)
    if (Test-CacheFile $Filename) {
        $src = Join-Path $script:LOCAL_CACHE_DIR $Filename
        Copy-Item -Path $src -Destination $Destination -Force
        Write-Log "Loaded from cache: $Filename"
        return $true
    }
    return $false
}

function Save-ToCache {
    param([string]$Source, [string]$Filename)
    if (-not (Test-Path $script:LOCAL_CACHE_DIR)) {
        New-Item -ItemType Directory -Path $script:LOCAL_CACHE_DIR -Force | Out-Null
    }
    Copy-Item -Path $Source -Destination (Join-Path $script:LOCAL_CACHE_DIR $Filename) -Force
}

function Get-Sha256 {
    param([string]$Path)
    $hash = Get-FileHash -Path $Path -Algorithm SHA256
    return $hash.Hash.ToLower()
}

function Test-Sha256 {
    param([string]$Path, [string]$Expected)
    if (-not $Expected -or $Expected -eq '0000000000000000000000000000000000000000000000000000000000000000') {
        return $true
    }
    Write-Log "Verifying SHA256..."
    $actual = Get-Sha256 -Path $Path
    if ($actual -ne $Expected.ToLower()) {
        Write-Log "SHA256 mismatch: expected=$Expected actual=$actual" 'ERROR'
        return $false
    }
    Write-Log "SHA256 OK: $actual"
    return $true
}

function Invoke-DownloadFile {
    param(
        [string]$Url,
        [string]$Destination,
        [int]$TimeoutSec = 300,
        [string]$Label = ''
    )
    if (-not $Label) { $Label = Split-Path $Destination -Leaf }
    Write-Log "Downloading: $Url"

    # Stream the body in chunks so we can (a) push a live percentage heartbeat to
    # the progress sink / console and (b) enforce a hard overall timeout — a plain
    # Invoke-WebRequest -OutFile gives neither and can stall on a half-open socket.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $resp = $null; $rs = $null; $fs = $null; $ok = $false
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.UserAgent = 'leung-installer'
        $req.Timeout = 30000           # connect timeout (ms)
        $req.ReadWriteTimeout = 60000  # per-read stall timeout (ms)
        $resp = $req.GetResponse()
        $total = [long]$resp.ContentLength
        $rs = $resp.GetResponseStream()
        $fs = [System.IO.File]::Create($Destination)

        $buf      = New-Object byte[] 65536
        $sofar    = [long]0
        $start    = Get-Date
        $lastBeat = $start
        $read     = 0

        while (($read = $rs.Read($buf, 0, $buf.Length)) -gt 0) {
            $fs.Write($buf, 0, $read)
            $sofar += $read

            $now = Get-Date
            if (($now - $start).TotalSeconds -ge $TimeoutSec) {
                throw "Download exceeded ${TimeoutSec}s timeout."
            }
            if (($now - $lastBeat).TotalSeconds -ge 2) {
                $lastBeat = $now
                $mb = [int]($sofar / 1MB)
                if ($total -gt 0) {
                    $pct = [int](($sofar / $total) * 100)
                    $line = "[..] Downloading $Label... $pct% ($mb/$([int]($total / 1MB)) MB)"
                } else {
                    $line = "[..] Downloading $Label... $mb MB"
                }
                Send-LeungProgress $line
                Write-Host $line -ForegroundColor DarkGray
            }
        }

        $fs.Close(); $fs = $null
        # Reject a short read — a dropped connection ends the stream early and would
        # otherwise leave a truncated file that still has a valid PE header but won't
        # run ("This app can't run on your PC" / ERROR_BAD_EXE_FORMAT).
        if ($total -gt 0 -and $sofar -ne $total) {
            throw "Incomplete download: got $sofar of $total bytes."
        }
        Write-Success "Downloaded $Label."
        $ok = $true
        return $true
    } catch {
        Write-Log "Download failed: $($_.Exception.Message)" 'WARN'
        return $false
    } finally {
        if ($fs)   { try { $fs.Close() }   catch {} }
        if ($rs)   { try { $rs.Close() }   catch {} }
        if ($resp) { try { $resp.Close() } catch {} }
        # On failure, drop the (possibly partial) file so it never passes as good.
        if (-not $ok -and (Test-Path $Destination)) {
            Remove-Item $Destination -Force -ErrorAction SilentlyContinue
        }
    }
}

# Priority: bundle → cache → online (primary) → online (mirror)
function Invoke-DownloadWithFallback {
    param(
        [string]$Filename,
        [string]$PrimaryUrl,
        [string]$MirrorUrl = '',
        [string]$Destination,
        [string]$ExpectedSha256 = ''
    )

    # 1) Bundle
    if (Copy-BundleFile -Filename $Filename -Destination $Destination) {
        if (Test-Sha256 -Path $Destination -Expected $ExpectedSha256) { return $true }
        Write-Log "Bundle SHA256 mismatch, falling through." 'WARN'
        Remove-Item -Path $Destination -Force -ErrorAction SilentlyContinue
    }

    # 2) Cache
    if (Copy-CacheFile -Filename $Filename -Destination $Destination) {
        if (Test-Sha256 -Path $Destination -Expected $ExpectedSha256) { return $true }
        Write-Log "Cache SHA256 mismatch, falling through." 'WARN'
        Remove-Item -Path $Destination -Force -ErrorAction SilentlyContinue
    }

    # 3) Online primary
    if (Invoke-DownloadFile -Url $PrimaryUrl -Destination $Destination -Label $Filename) {
        if (Test-Sha256 -Path $Destination -Expected $ExpectedSha256) {
            Save-ToCache -Source $Destination -Filename $Filename
            return $true
        }
        Remove-Item -Path $Destination -Force -ErrorAction SilentlyContinue
    }

    # 4) Online mirror
    if ($MirrorUrl -and $MirrorUrl -ne $PrimaryUrl) {
        Write-Log "Primary failed, trying mirror: $MirrorUrl" 'WARN'
        if (Invoke-DownloadFile -Url $MirrorUrl -Destination $Destination -Label $Filename) {
            if (Test-Sha256 -Path $Destination -Expected $ExpectedSha256) {
                Save-ToCache -Source $Destination -Filename $Filename
                return $true
            }
            Remove-Item -Path $Destination -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Fail "Failed to obtain: $Filename"
    return $false
}

# Legacy wrapper
function Invoke-DownloadWithMirror {
    param(
        [string]$PrimaryUrl,
        [string]$MirrorUrl,
        [string]$Destination,
        [string]$ExpectedSha256
    )
    $filename = Split-Path $Destination -Leaf
    return (Invoke-DownloadWithFallback -Filename $filename -PrimaryUrl $PrimaryUrl -MirrorUrl $MirrorUrl -Destination $Destination -ExpectedSha256 $ExpectedSha256)
}

function Get-GithubProxyUrl {
    param([string]$OriginalUrl)
    if (-not $script:GITHUB_PROXY_BASE) { return '' }
    $base = $script:GITHUB_PROXY_BASE.TrimEnd('/')
    return "$base/$OriginalUrl"
}

# npm bundle-first install (with full offline support)
function Install-NpmFromBundle {
    param([string]$Package)
    $safeName = $Package -replace '[@/]', '-' -replace '^-', ''

    # Full offline directory (with all deps)
    $offlineDir = ''
    if ($script:BUNDLES_DIR) {
        $offlineDir = Join-Path $script:BUNDLES_DIR "npm-offline\$safeName"
    }
    if ($offlineDir -and (Test-Path $offlineDir)) {
        $tgzFiles = Get-ChildItem $offlineDir -Filter '*.tgz'
        if ($tgzFiles.Count -gt 0) {
            Write-Log "Installing $Package from offline bundle (full deps)..."
            $mainTgz = $tgzFiles | Where-Object { $_.Name -like "$safeName*" -or $_.Name -like "*$($Package -replace '[@/]','-')*" } | Select-Object -First 1
            if ($mainTgz) {
                try {
                    $r = Invoke-ProcessWithTimeout -FilePath 'cmd.exe' -Label "$Package (offline bundle)" -TimeoutSeconds 300 -ArgumentList @(
                        '/c', 'npm', 'install', '-g', '--offline', '--cache', $offlineDir, $mainTgz.FullName
                    )
                    if (-not $r.TimedOut -and $r.ExitCode -eq 0) {
                        Write-Success "$Package installed from offline bundle."
                        return $true
                    }
                } catch {}
                try {
                    $r = Invoke-ProcessWithTimeout -FilePath 'cmd.exe' -Label "$Package (bundle tgz)" -TimeoutSeconds 300 -ArgumentList @(
                        '/c', 'npm', 'install', '-g', $mainTgz.FullName
                    )
                    if (-not $r.TimedOut -and $r.ExitCode -eq 0) {
                        Write-Success "$Package installed from bundle tgz."
                        return $true
                    }
                } catch {}
            }
            Write-Log "Offline bundle install failed, falling through." 'WARN'
        }
    }

    # Legacy single tgz
    $bundleTgz = ''
    $cacheTgz = Join-Path $script:LOCAL_CACHE_DIR "$safeName.tgz"
    if ($script:BUNDLES_NPM_CACHE_DIR) {
        $bundleTgz = Join-Path $script:BUNDLES_NPM_CACHE_DIR "$safeName.tgz"
    }
    if ($bundleTgz -and (Test-Path $bundleTgz)) {
        Write-Log "Installing $Package from bundle tgz..."
        try {
            $r = Invoke-ProcessWithTimeout -FilePath 'cmd.exe' -Label "$Package (bundle)" -TimeoutSeconds 300 -ArgumentList @(
                '/c', 'npm', 'install', '-g', $bundleTgz
            )
            if (-not $r.TimedOut -and $r.ExitCode -eq 0) {
                Write-Success "$Package installed from bundle."
                return $true
            }
        } catch {}
    }
    if (Test-Path $cacheTgz) {
        Write-Log "Installing $Package from cache..."
        try {
            $r = Invoke-ProcessWithTimeout -FilePath 'cmd.exe' -Label "$Package (cache)" -TimeoutSeconds 300 -ArgumentList @(
                '/c', 'npm', 'install', '-g', $cacheTgz
            )
            if (-not $r.TimedOut -and $r.ExitCode -eq 0) {
                Write-Success "$Package installed from cache."
                return $true
            }
        } catch {}
    }
    return $false
}

# Install Node.js from bundle (offline)
function Install-NodeFromBundle {
    $nodeDir = ''
    if ($script:BUNDLES_DIR) {
        $nodeDir = Join-Path $script:BUNDLES_DIR 'node'
    }
    if (-not $nodeDir -or -not (Test-Path $nodeDir)) { return $false }
    $versionFile = Join-Path $nodeDir 'version.txt'
    if (-not (Test-Path $versionFile)) { return $false }

    $nodeVer = (Get-Content $versionFile -Raw).Trim()
    $nodeZip = Join-Path $nodeDir "node-v${nodeVer}-win-x64.zip"
    if (-not (Test-Path $nodeZip)) { return $false }

    Write-Log "Installing Node.js v${nodeVer} from bundle..."
    $installDir = Join-Path $env:LOCALAPPDATA 'Programs\leung-node'
    if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }

    $tempExtract = Join-Path $env:TEMP "leung-node-extract-$(Get-Random)"
    Expand-Archive -Path $nodeZip -DestinationPath $tempExtract -Force
    $extracted = Get-ChildItem $tempExtract -Directory | Select-Object -First 1
    if ($extracted) {
        Move-Item $extracted.FullName $installDir -Force
    }
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    # Add to PATH
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath -notlike "*leung-node*") {
        [Environment]::SetEnvironmentVariable('PATH', "$installDir;$userPath", 'User')
    }
    $env:PATH = "$installDir;$env:PATH"

    Write-Log "Node.js v${nodeVer} installed from bundle to $installDir"
    return $true
}
