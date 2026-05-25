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
            Nextcloud : thumbnails/<systemId>/<file>.png
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

.PARAMETER DryRun
    Validate listing/reading/matching only. Does not write thumbnails or manifest anywhere.

.EXAMPLE
    cd D:\source\repos\Assemulator
    .\scripts\Update-Artwork.ps1

.EXAMPLE
    .\scripts\Update-Artwork.ps1 -Force

.EXAMPLE
    .\scripts\Update-Artwork.ps1 -DryRun
#>
param(
    [string]$DataPath         = '',
    [string]$NextcloudDavBase = 'https://tools.kushkurriculum.org/nextcloud/public.php/dav/files/jbXHPXxAxzj8ATB',
    [string]$NcProxyBase      = '/nc-api/public.php/dav/files/jbXHPXxAxzj8ATB',
    [string]$MetadataPath     = 'MetaData',
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

# Resolve DataPath relative to the scripts/ folder or cwd
if (-not $DataPath) {
    $base = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }
    $DataPath = Join-Path $base 'wwwroot\data'
}
$DataPath = (Resolve-Path $DataPath).Path
$NextcloudDavBase = $NextcloudDavBase.TrimEnd('/')
$NcProxyBase = $NcProxyBase.TrimEnd('/')
$MetadataPath = $MetadataPath.Trim('/')

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
function Invoke-DavPut([string]$Url, [byte[]]$Data, [string]$ContentType = 'application/octet-stream') {
    try {
        $req = [System.Net.WebRequest]::Create($Url)
        $req.Method = 'PUT'
        $req.ContentType = $ContentType
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

function Invoke-DavList([string]$Url) {
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = 'PROPFIND'
        $req.Headers.Add('Depth', '1')
        $req.ContentType = 'application/xml; charset=utf-8'
                $body = @"
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>
"@
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()

        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $xml = $reader.ReadToEnd()
        $reader.Close()
        $resp.Close()
        return $xml
    } catch {
        return $null
    }
}

function Get-DirectoryDisplayNames([string]$Xml) {
    if ([string]::IsNullOrWhiteSpace($Xml)) { return @() }

    try {
        [xml]$doc = $Xml
        $names = @()
        $responses = @($doc.SelectNodes("//*[local-name()='response']"))
        foreach ($r in $responses) {
            $nameNode = $r.SelectSingleNode(".//*[local-name()='displayname']")
            if ($null -eq $nameNode) { continue }
            $name = [string]$nameNode.InnerText
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $names += $name.Trim()
            }
        }
        return @($names | Select-Object -Unique)
    } catch {
        return @()
    }
}

function Get-MetadataFileText([string]$FileName) {
    $url = "$NextcloudDavBase/$MetadataPath/$FileName"
    try {
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        $text = [string]$resp.Content
        if ($text.Length -gt 0 -and [int][char]$text[0] -eq 65279) {
            $text = $text.Substring(1)
        }
        return $text
    } catch {
        return $null
    }
}

function Set-MetadataFileText([string]$FileName, [string]$Content) {
    $dirUrl = "$NextcloudDavBase/$MetadataPath"
    Invoke-DavMkCol $dirUrl

    $fileUrl = "$dirUrl/$([Uri]::EscapeUriString($FileName))"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    return (Invoke-DavPut $fileUrl $bytes 'application/json; charset=utf-8')
}

# ?? Store on Nextcloud; returns coverUrl string or $null on failure ????????????
function Save-ToNextcloud([string]$SystemId, [string]$Filename, [byte[]]$Data) {
    if ($DryRun) { return $null }
    if ($script:NcWritable -eq $false) { return $null }

    # Ensure /MetaData/thumbnails/ and /MetaData/thumbnails/<system>/ collections exist
    Invoke-DavMkCol "$NextcloudDavBase/$MetadataPath"
    Invoke-DavMkCol "$NextcloudDavBase/$MetadataPath/thumbnails"
    Invoke-DavMkCol "$NextcloudDavBase/$MetadataPath/thumbnails/$SystemId"

    $enc = [Uri]::EscapeUriString($Filename)
    $putUrl = "$NextcloudDavBase/$MetadataPath/thumbnails/$SystemId/$enc"

    if (Invoke-DavPut $putUrl $Data 'image/png') {
        if ($null -eq $script:NcWritable) {
            Write-Host '  Nextcloud is writable ? using Nextcloud storage for all art.' -ForegroundColor Green
            $script:NcWritable = $true
        }
        return "thumbnails/$SystemId/$enc"
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
    if ($DryRun) {
        $safeFilename = $Filename -replace '[(),]', '' -replace '\s{2,}', ' ' -replace '^\s+|\s+$', ''
        return "/data/thumbnails/$SystemId/$([Uri]::EscapeUriString($safeFilename))"
    }

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

# -- Process manifest object --------------------------------------------------
# $ConsoleLookup: platform label -> @{ Id = 'arcade'; Core = 'fbneo' }
function Update-UnifiedManifest($Manifest, [hashtable]$ConsoleLookup) {
    $manifest = $Manifest
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
        $filename = $match + '.png'

        if ($DryRun) {
            $predictedUrl = "thumbnails/$SystemId/$([Uri]::EscapeUriString($filename))"
            Write-Host "        [DRY-RUN] would set coverUrl = $predictedUrl" -ForegroundColor Cyan
            $changed = $true
            continue
        }

        $cdnUrl = "https://thumbnails.libretro.com/$([Uri]::EscapeUriString($systemFolder))/Named_Boxarts/$([Uri]::EscapeUriString($matchFile))"
        $pngBytes = Get-PngBytes $cdnUrl
        if (-not $pngBytes) { continue }

        # Try Nextcloud first, fall back to local
        $coverUrl = Save-ToNextcloud $systemId $filename $pngBytes
        if (-not $coverUrl) {
            $coverUrl = Save-ToLocal $systemId $filename $pngBytes
        }

        $game.coverUrl = $coverUrl
        $changed = $true
        Write-Host "        coverUrl = $coverUrl" -ForegroundColor Cyan
    }

    return [pscustomobject]@{
        Manifest = $manifest
        Changed = $changed
    }
}

# -- Entry point --------------------------------------------------------------
Write-Host ''
Write-Host '=== Assemulator Artwork Enrichment ===' -ForegroundColor Magenta
Write-Host "DataPath : $DataPath"
Write-Host "Nextcloud: $NextcloudDavBase"
Write-Host "MetaData : $MetadataPath"
Write-Host "Force    : $Force"
Write-Host "DryRun   : $DryRun"
Write-Host ''

$unifiedManifest = Join-Path $DataPath 'manifest.json'

# Verify directory listing from share root (Game) and MetaData.
$rootListingXml = Invoke-DavList "$NextcloudDavBase/"
$rootNames = Get-DirectoryDisplayNames $rootListingXml
if ($rootNames.Count -gt 0) {
    Write-Host "Root listing (first 20): $((($rootNames | Select-Object -First 20) -join ', '))" -ForegroundColor DarkCyan
} else {
    Write-Warning "Could not list Nextcloud share root via PROPFIND."
}

$metaListingXml = Invoke-DavList "$NextcloudDavBase/$MetadataPath/"
$metaNames = Get-DirectoryDisplayNames $metaListingXml
if ($metaNames.Count -gt 0) {
    Write-Host "MetaData listing (first 20): $((($metaNames | Select-Object -First 20) -join ', '))" -ForegroundColor DarkCyan
} else {
    Write-Warning "Could not list Nextcloud MetaData via PROPFIND."
}

# Read consoles.json and manifest.json from Nextcloud first, local fallback second.
$consolesText = Get-MetadataFileText 'consoles.json'
if ([string]::IsNullOrWhiteSpace($consolesText)) {
    $consolesPath = Join-Path $DataPath 'consoles.json'
    if (Test-Path $consolesPath) {
        $consolesText = Get-Content $consolesPath -Encoding UTF8 -Raw
        Write-Warning 'Using local consoles.json fallback.'
    } else {
        Write-Host "ERROR: Could not read consoles.json from Nextcloud or local path '$consolesPath'." -ForegroundColor Red
        exit 1
    }
}
$consoles = $consolesText | ConvertFrom-Json

$manifestText = Get-MetadataFileText 'manifest.json'
if ([string]::IsNullOrWhiteSpace($manifestText)) {
    if (Test-Path $unifiedManifest) {
        $manifestText = Get-Content $unifiedManifest -Encoding UTF8 -Raw
        Write-Warning 'Using local manifest.json fallback.'
    } else {
        Write-Host "ERROR: Could not read manifest.json from Nextcloud or local path '$unifiedManifest'." -ForegroundColor Red
        exit 1
    }
}
$manifest = $manifestText | ConvertFrom-Json

# Build platform -> {Id, Core} lookup from consoles.json
$ConsoleLookup = @{}
foreach ($c in $consoles) {
    if ($c.platform) { $ConsoleLookup[$c.platform] = @{ Id = $c.id; Core = $c.emulatorCore } }
}
Write-Host "Platform mappings loaded: $($ConsoleLookup.Count)"
$ConsoleLookup.GetEnumerator() | Sort-Object Key | ForEach-Object {
    Write-Host "  $($_.Key) => $($_.Value.Id) (core: $($_.Value.Core))" -ForegroundColor DarkCyan
}
Write-Host ''

$result = Update-UnifiedManifest $manifest $ConsoleLookup

if ($DryRun) {
    if ($result.Changed) {
        Write-Host '  [DRY-RUN] Validation found entries that would be updated.' -ForegroundColor White
    } else {
        Write-Host '  [DRY-RUN] No changes would be made.' -ForegroundColor White
    }
}
elseif ($result.Changed) {
    $outputJson = $result.Manifest | ConvertTo-Json -Depth 10
    $savedToNextcloud = Set-MetadataFileText 'manifest.json' $outputJson
    if ($savedToNextcloud) {
        Write-Host '  Saved MetaData/manifest.json to Nextcloud.' -ForegroundColor White
    } else {
        $outputJson | Set-Content $unifiedManifest -Encoding UTF8
        Write-Warning "Saved local fallback file: $unifiedManifest"
    }
}

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
