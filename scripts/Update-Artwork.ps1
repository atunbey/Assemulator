<#
.SYNOPSIS
    Fetches cover art from thumbnails.libretro.com, stores it on Nextcloud (or locally
    as a fallback), and updates the coverUrl field in the unified data/manifest.json.

.DESCRIPTION
    Run from the repository root (or any location) before a docker compose build.
    Reads data/manifest.json (the single unified game catalog). Each entry must have
    a 'platform' field (e.g. "Arcade", "Nintendo NES") matching the platform label in
    data/consoles.json. The system id and default emulator core are derived automatically
    from consoles.json -- no per-system manifest files are needed.

    Storage priority:
      1. Nextcloud  - tries an anonymous WebDAV PUT to the public share's thumbnails/
                      folder. Works if the share has "can edit" permissions.
      2. Local      - if Nextcloud is not writable, saves to wwwroot/data/thumbnails/
                      which is served as a static file by nginx inside the container.

    The coverUrl written to the manifest will be:
      Nextcloud : /nc-api/public.php/dav/files/<token>/thumbnails/<systemId>/<file>.png
      Local     : /data/thumbnails/<systemId>/<file>.png

    Games whose coverUrl already points to a stored path are skipped unless -Force
    is supplied. Games still pointing to the cover-art CDN are always refreshed.

.PARAMETER DataPath
    Path to the wwwroot/data folder. Defaults to the sibling of the scripts/ folder.

.PARAMETER NextcloudDavBase
    Full WebDAV URL for the Nextcloud public share root.

.PARAMETER NcProxyBase
    Nginx reverse-proxy base path the Blazor app uses to reach Nextcloud.

.PARAMETER Force
    Re-download and overwrite even for games that already have a stored coverUrl.

.EXAMPLE
    cd D:\source\repos\Assemulator
    .\scripts\Update-Artwork.ps1

.EXAMPLE
    .\scripts\Update-Artwork.ps1 -Force
#>
param(
    [string]$DataPath         = '',
    [string]$NextcloudDavBase = 'https://tools.kushkurriculum.org/nextcloud/public.php/dav/files/jbXHPXxAxzj8ATB/MetaData',
    [string]$NcProxyBase      = '/nc-api/public.php/dav/files/jbXHPXxAxzj8ATB/MetaData',
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

# Resolve DataPath relative to the scripts/ folder or cwd
if (-not $DataPath) {
    $base = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }
    $DataPath = Join-Path $base 'wwwroot\data'
}
$DataPath = (Resolve-Path $DataPath).Path

# ?? Lookup tables ??????????????????????????????????????????????????????????????

# EmulatorJS core -> cover-art system folder
$CoreToLibretro = @{
    fbneo          = 'MAME'
    mame2003       = 'MAME'
    mame2003_plus  = 'MAME'
    nes            = 'Nintendo - Nintendo Entertainment System'
    snes           = 'Nintendo - Super Nintendo Entertainment System'
    n64            = 'Nintendo - Nintendo 64'
    gba            = 'Nintendo - Game Boy Advance'
    genesis        = 'Sega - Mega Drive - Genesis'
    psx            = 'Sony - PlayStation'
    atari2600      = 'Atari - 2600'
}

# -- State --------------------------------------------------------------------
$script:IndexCache  = @{}
$script:NcWritable  = $null

# ?? Helper: fetch the Named_Boxarts directory listing ?????????????????????????
function Get-ThumbnailIndex([string]$SystemFolder) {
    if ($script:IndexCache.ContainsKey($SystemFolder)) {
        return $script:IndexCache[$SystemFolder]
    }
    $url = "https://thumbnails.libretro.com/$([Uri]::EscapeUriString($SystemFolder))/Named_Boxarts/"
    Write-Host "  [index] $SystemFolder" -ForegroundColor Cyan
    try {
        $r = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 30
        $names = ($r.Content | Select-String -Pattern 'href="([^"]+\.png)"' -AllMatches).Matches |
                 ForEach-Object { [Uri]::UnescapeDataString($_.Groups[1].Value) }
        $script:IndexCache[$SystemFolder] = @($names)
        return @($names)
    } catch {
        Write-Warning "  Could not fetch index for '$SystemFolder': $_"
        $script:IndexCache[$SystemFolder] = @()
        return @()
    }
}

# ?? Helper: fuzzy match game name against a list of PNG filenames ?????????????
$Normalize = {
    param([string]$s)
    # Replace all non-alphanumeric characters with spaces, collapse, lowercase
    ($s -replace '[^a-zA-Z0-9]', ' ' -replace '\s+', ' ').Trim().ToLower()
}

function Find-BestThumbnail([string]$OfficialName, [string[]]$Candidates) {
    if (-not $Candidates -or $Candidates.Count -eq 0) { return $null }

    $normName = & $Normalize $OfficialName

    # Strip .png extension from candidates for matching
    $stripped = $Candidates | ForEach-Object { $_ -replace '\.png$', '' }

    # Pass 1  exact starts-with.
    # Prefer "Name (region)" variants over sequels ("Name 2", "Name '88", etc.)
    # by requiring the character after the official name to be " (" (parenthetical only).
    $hits = $stripped | Where-Object { $_ -like "$OfficialName*" }
    if ($hits) {
        $paren = $hits | Where-Object { $_ -like "$OfficialName (*" }
        if ($paren) { return ($paren | Sort-Object Length | Select-Object -First 1) }
        return ($hits | Sort-Object Length | Select-Object -First 1)
    }

    # Pass 2 ? normalised starts-with
    $hits = $stripped | Where-Object { (& $Normalize $_) -like "$normName*" }
    if ($hits) { return ($hits | Sort-Object Length | Select-Object -First 1) }

    # Pass 3 ? normalised substring
    $hits = $stripped | Where-Object { (& $Normalize $_) -like "*$normName*" }
    if ($hits) { return ($hits | Sort-Object Length | Select-Object -First 1) }

    # Pass 4 ? all significant words (length > 2) present in candidate
    $words = ($normName -split '\s+') | Where-Object { $_.Length -gt 2 }
    if ($words.Count -gt 0) {
        $hits = $stripped | Where-Object {
            $entry = & $Normalize $_
            ($words | Where-Object { $entry -notlike "*$_*" }).Count -eq 0
        }
        if ($hits) { return ($hits | Sort-Object Length | Select-Object -First 1) }
    }

    return $null
}

# ?? Helper: download binary from URL ?????????????????????????????????????????
function Get-PngBytes([string]$Url) {
    try {
        return (New-Object System.Net.WebClient).DownloadData($Url)
    } catch {
        Write-Warning "  Download failed ($Url): $_"
        return $null
    }
}

# ?? Helper: WebDAV MKCOL (create collection; ignore if already exists) ????????
function Invoke-DavMkCol([string]$Url) {
    try {
        $req = [System.Net.WebRequest]::Create($Url)
        $req.Method = 'MKCOL'
        $req.ContentLength = 0
        $resp = $req.GetResponse()
        $resp.Close()
    } catch {
        # 405 = method not allowed (collection exists or share is read-only)
        # 409 = parent doesn't exist yet ? expected on first MKCOL of nested path
        # Suppress; the subsequent PUT will reveal actual writability
    }
}

# ?? Helper: WebDAV PUT ????????????????????????????????????????????????????????
function Invoke-DavPut([string]$Url, [byte[]]$Data) {
    try {
        $req = [System.Net.WebRequest]::Create($Url)
        $req.Method = 'PUT'
        $req.ContentType = 'image/png'
        $req.ContentLength = $Data.Length
        $s = $req.GetRequestStream()
        $s.Write($Data, 0, $Data.Length)
        $s.Close()
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    } catch {
        return $false
    }
}

# ?? Store on Nextcloud; returns coverUrl string or $null on failure ????????????
function Save-ToNextcloud([string]$SystemId, [string]$Filename, [byte[]]$Data) {
    if ($script:NcWritable -eq $false) { return $null }

    # Ensure /thumbnails/ and /thumbnails/<system>/ collections exist
    Invoke-DavMkCol "$NextcloudDavBase/thumbnails"
    Invoke-DavMkCol "$NextcloudDavBase/thumbnails/$SystemId"

    $enc = [Uri]::EscapeUriString($Filename)
    $putUrl = "$NextcloudDavBase/thumbnails/$SystemId/$enc"

    if (Invoke-DavPut $putUrl $Data) {
        if ($null -eq $script:NcWritable) {
            Write-Host '  Nextcloud is writable ? using Nextcloud storage for all art.' -ForegroundColor Green
            $script:NcWritable = $true
        }
        return "$NcProxyBase/thumbnails/$SystemId/$enc"
    } else {
        if ($null -eq $script:NcWritable) {
            Write-Warning '  Nextcloud PUT failed (share may be read-only). Falling back to local wwwroot storage.'
            $script:NcWritable = $false
        }
        return $null
    }
}

# ?? Store locally under wwwroot/data/thumbnails/ ?????????????????????????????
function Save-ToLocal([string]$SystemId, [string]$Filename, [byte[]]$Data) {
    $dir = Join-Path $DataPath "thumbnails\$SystemId"
    if (-not (Test-Path $dir)) {
        New-Item $dir -ItemType Directory -Force | Out-Null
    }
    # Sanitize filename: remove () and , which trip up MSBuild static-asset processing
    $safeFilename = $Filename -replace '[(),]', '' -replace '\s{2,}', ' ' -replace '^\s+|\s+$', ''
    $localFile = Join-Path $dir $safeFilename
    [IO.File]::WriteAllBytes($localFile, $Data)
    # URL path served by nginx from the container's wwwroot/data/
    return "/data/thumbnails/$SystemId/$([Uri]::EscapeUriString($safeFilename))"
}

# -- Process the unified data/manifest.json ----------------------------------
# $ConsoleLookup: platform label -> @{ Id = 'arcade'; Core = 'fbneo' }
function Update-UnifiedManifest([string]$ManifestPath, [hashtable]$ConsoleLookup) {
    $manifest = Get-Content $ManifestPath -Encoding UTF8 -Raw | ConvertFrom-Json
    $changed  = $false

    foreach ($game in $manifest) {

        # Skip if already stored (not a CDN link), unless -Force
        $isCdn    = $game.coverUrl -like '*thumbnails.libretro.com*'
        $isStored = ($game.coverUrl -ne '') -and (-not $isCdn)
        if ($isStored -and -not $Force) {
            Write-Host "  SKIP  $($game.officialName)" -ForegroundColor DarkGray
            continue
        }

        # Derive system id and default core from the platform field
        $platformKey = $game.platform
        if (-not $platformKey -or -not $ConsoleLookup.ContainsKey($platformKey)) {
            Write-Host "  SKIP  $($game.officialName) - unknown platform '$platformKey'" -ForegroundColor Yellow
            continue
        }
        $systemId    = $ConsoleLookup[$platformKey].Id
        $defaultCore = $ConsoleLookup[$platformKey].Core

        # Effective core: primary variant override > system default
        $core = $defaultCore
        $variants = @($game.variants)
        if ($variants.Count -gt 0 -and $variants[0].coreOverride -ne '') {
            $core = $variants[0].coreOverride
        }

        # Map core to the matching cover-art system folder
        $systemFolder = $CoreToLibretro[$core]
        if (-not $systemFolder) {
            Write-Host "  SKIP  $($game.officialName) - no thumbnail mapping for core '$core'" -ForegroundColor Yellow
            continue
        }

        # Fuzzy-match against thumbnail index
        $index = Get-ThumbnailIndex $systemFolder
        $match = Find-BestThumbnail $game.officialName $index

        if (-not $match) {
            Write-Host "  MISS  $($game.officialName)  [$systemFolder]" -ForegroundColor Yellow
            continue
        }

        Write-Host "  HIT   $($game.officialName)" -ForegroundColor Green
        Write-Host "        $match" -ForegroundColor DarkGreen

        # Download PNG from the cover-art CDN
        $matchFile = $match + '.png'
        $cdnUrl = "https://thumbnails.libretro.com/$([Uri]::EscapeUriString($systemFolder))/Named_Boxarts/$([Uri]::EscapeUriString($matchFile))"
        $pngBytes = Get-PngBytes $cdnUrl
        if (-not $pngBytes) { continue }

        $filename = $match + '.png'

        # Try Nextcloud first, fall back to local
        $coverUrl = Save-ToNextcloud $systemId $filename $pngBytes
        if (-not $coverUrl) {
            $coverUrl = Save-ToLocal $systemId $filename $pngBytes
        }

        $game.coverUrl = $coverUrl
        $changed = $true
        Write-Host "        coverUrl = $coverUrl" -ForegroundColor Cyan
    }

    if ($changed) {
        $manifest | ConvertTo-Json -Depth 10 | Set-Content $ManifestPath -Encoding UTF8
        Write-Host "  Saved $ManifestPath" -ForegroundColor White
    }
}

# -- Entry point --------------------------------------------------------------
Write-Host ''
Write-Host '=== Assemulator Artwork Enrichment ===' -ForegroundColor Magenta
Write-Host "DataPath : $DataPath"
Write-Host "Nextcloud: $NextcloudDavBase"
Write-Host "Force    : $Force"
Write-Host ''

$unifiedManifest = Join-Path $DataPath 'manifest.json'
if (-not (Test-Path $unifiedManifest)) {
    Write-Host "ERROR: $unifiedManifest not found." -ForegroundColor Red
    exit 1
}

# Build platform -> {Id, Core} lookup from consoles.json
$consolesPath = Join-Path $DataPath 'consoles.json'
$consoles     = Get-Content $consolesPath -Encoding UTF8 -Raw | ConvertFrom-Json
$ConsoleLookup = @{}
foreach ($c in $consoles) {
    if ($c.platform) { $ConsoleLookup[$c.platform] = @{ Id = $c.id; Core = $c.emulatorCore } }
}
Write-Host "Platform mappings loaded: $($ConsoleLookup.Count)"
$ConsoleLookup.GetEnumerator() | Sort-Object Key | ForEach-Object {
    Write-Host "  $($_.Key) => $($_.Value.Id) (core: $($_.Value.Core))" -ForegroundColor DarkCyan
}
Write-Host ''

Update-UnifiedManifest $unifiedManifest $ConsoleLookup

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
if ($script:NcWritable -eq $false) {
    Write-Host ''
    Write-Host 'NOTE: Nextcloud was not writable. Art was saved to wwwroot/data/thumbnails/.' -ForegroundColor Yellow
    Write-Host '      Rebuild the container to pick up the new files:' -ForegroundColor Yellow
    Write-Host '      docker compose up -d --build' -ForegroundColor White
} elseif ($script:NcWritable -eq $true) {
    Write-Host ''
    Write-Host 'NOTE: Art is stored on Nextcloud. No container rebuild needed.' -ForegroundColor Green
    Write-Host '      Hard-refresh the browser to see artwork.' -ForegroundColor White
}
