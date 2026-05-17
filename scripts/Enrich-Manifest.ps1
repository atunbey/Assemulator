param(
    [string]$ManifestPath = "wwwroot/data/manifest.json",
    [string]$ArcadeManifestPath = "wwwroot/data/arcade/manifest.json",
    [string]$RomBaseUrl = "http://localhost:8088/nc-api/public.php/dav/files/jbXHPXxAxzj8ATB",
    [string]$MameListXmlPath = "wwwroot/data/mame-listxml.xml",
    [string]$MameListXmlUrl = "http://localhost:8088/nc-api/public.php/dav/files/jbXHPXxAxzj8ATB/mame-listxml.xml",
    [switch]$UpdateArcadeManifest
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$coreToPlatform = @{
    "nes" = "Nintendo NES"
    "snes" = "Super Nintendo"
    "n64" = "Nintendo 64"
    "gba" = "Game Boy Advance"
    "genesis" = "Sega Genesis"
    "segamd" = "Sega Genesis"
    "psx" = "PlayStation"
    "a2600" = "Atari 2600"
    "fbneo" = "Arcade"
    "mame2003" = "Arcade"
    "mame2003_plus" = "Arcade"
}

function Clone-Object($obj) {
    return ($obj | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function Read-XmlDocument([string]$Path, [string]$Url) {
    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing
            $raw = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
            if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 65279) {
                $raw = $raw.Substring(1)
            }
            return [xml]$raw
        } catch {
            Write-Warning "Could not read MAME listxml from URL '$Url': $($_.Exception.Message)"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path $Path)) {
        $raw = [System.IO.File]::ReadAllText((Resolve-Path $Path).Path, [System.Text.Encoding]::UTF8)
        if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 65279) {
            $raw = $raw.Substring(1)
        }
        return [xml]$raw
    }

    return $null
}

function Get-MameLookup([xml]$XmlDoc) {
    $lookup = @{}
    if ($null -eq $XmlDoc -or $null -eq $XmlDoc.mame) {
        return $lookup
    }

    foreach ($machine in @($XmlDoc.mame.machine)) {
        if ($null -eq $machine -or [string]::IsNullOrWhiteSpace($machine.name)) { continue }

        $roms = @()
        foreach ($rom in @($machine.rom)) {
            if ($null -eq $rom -or [string]::IsNullOrWhiteSpace($rom.name)) { continue }
            $roms += [pscustomobject]@{
                name = [string]$rom.name
                size = [string]$rom.size
                crc = [string]$rom.crc
                sha1 = [string]$rom.sha1
            }
        }

        $lookup[[string]$machine.name.ToLowerInvariant()] = [pscustomobject]@{
            name = [string]$machine.name
            description = [string]$machine.description
            cloneof = [string]$machine.cloneof
            roms = $roms
        }
    }

    return $lookup
}

function Resolve-MameMachine([hashtable]$Lookup, [string]$ArchiveFile, [string]$RomsetName) {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($RomsetName, [System.IO.Path]::GetFileNameWithoutExtension($ArchiveFile))) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $candidates.Add($candidate.ToLowerInvariant()) | Out-Null
        $candidates.Add(($candidate.ToLowerInvariant() -replace '[^a-z0-9]+', '')) | Out-Null
    }

    foreach ($candidate in $candidates) {
        if ($Lookup.ContainsKey($candidate)) {
            return $Lookup[$candidate]
        }
    }

    return $null
}

function Get-TargetPlatform([string]$platform, [string]$core) {
    if ([string]::IsNullOrWhiteSpace($core)) {
        return $platform
    }

    $k = $core.Trim().ToLowerInvariant()
    if ($coreToPlatform.ContainsKey($k)) {
        return $coreToPlatform[$k]
    }

    return $platform
}

function Get-FileDescription([string]$filename, [string]$core, [string]$region) {
    $name = $filename.ToLowerInvariant()

    if ($name -match "japan|\(j\)|_j\b") { return "Japan release file" }
    if ($name -match "usa|\(u\)|_u\b") { return "USA release file" }
    if ($name -match "world|\(w\)|europe|\(e\)") { return "World/Europe release file" }

    if (-not [string]::IsNullOrWhiteSpace($region)) {
        switch ($region.ToLowerInvariant()) {
            "japan" { return "Japan release file" }
            "usa" { return "USA release file" }
            "world" { return "World release file" }
            "europe" { return "Europe release file" }
        }
    }

    if ($name -match "^82s|^2s\d+|\.prom$") { return "PROM/lookup data" }
    if ($name -match "prg|\.prg$") { return "Program ROM" }
    if ($name -match "cpu|code|main|program|p[0-9]+|u[0-9]+") { return "Program ROM" }
    if ($name -match "chr|gfx|tile|sprite") { return "Graphics ROM" }
    if ($name -match "snd|sound|adpcm|pcm|voice") { return "Audio ROM" }
    if ($name -match "prom|pal|82s|2s\d+") { return "PROM/lookup data" }

    if ($core -eq "fbneo" -or $core -eq "mame2003" -or $core -eq "mame2003_plus") {
        return "Arcade ROM chip file"
    }

    return "Game ROM file"
}

function Get-ZipEntries([string]$archiveFile) {
    $url = "$RomBaseUrl/$([Uri]::EscapeDataString($archiveFile))"
    $tmp = Join-Path $env:TEMP (([Guid]::NewGuid().ToString()) + ".zip")

    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing | Out-Null
        $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
        $entries = @($zip.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } | Select-Object -ExpandProperty FullName)
        $zip.Dispose()
        return $entries
    } catch {
        Write-Warning "Could not inspect $archiveFile at $url : $($_.Exception.Message)"
        return @()
    } finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
    }
}

function Normalize-Manifest($manifest) {
    $result = New-Object System.Collections.ArrayList
    $mameLookup = Get-MameLookup -XmlDoc (Read-XmlDocument -Path $MameListXmlPath -Url $MameListXmlUrl)

    foreach ($game in $manifest) {
        $groups = @{}

        foreach ($variant in @($game.variants)) {
            $core = ""
            if ($null -ne $variant.coreOverride) { $core = [string]$variant.coreOverride }
            $targetPlatform = Get-TargetPlatform -platform ([string]$game.platform -as [string]) -core $core

            if (-not $groups.ContainsKey($targetPlatform)) {
                $groups[$targetPlatform] = New-Object System.Collections.ArrayList
            }

            $enrichedFiles = @($variant.files)
            $mameMachine = $null
            if ($mameLookup.Count -gt 0) {
                $mameMachine = Resolve-MameMachine -Lookup $mameLookup -ArchiveFile ([string]$variant.archiveFile) -RomsetName ([string]$variant.romsetName)
            }

            # Enrich empty files[] by inspecting archive contents.
            if ($null -eq $variant.files -or @($variant.files).Count -eq 0) {
                $entries = @()
                if ($null -ne $mameMachine -and @($mameMachine.roms).Count -gt 0) {
                    $entries = @($mameMachine.roms | ForEach-Object { $_.name })
                }
                if (@($entries).Count -eq 0) {
                    $entries = Get-ZipEntries -archiveFile ([string]$variant.archiveFile)
                }
                $files = @()
                foreach ($entryName in $entries) {
                    $files += [pscustomobject]@{
                        filename = $entryName
                        description = if ($null -ne $mameMachine -and @($mameMachine.roms).Count -gt 0) {
                            Get-FileDescription -filename $entryName -core $core.ToLowerInvariant() -region ([string]$variant.region)
                        } else {
                            Get-FileDescription -filename $entryName -core $core.ToLowerInvariant() -region ([string]$variant.region)
                        }
                        core = $core
                    }
                }
                $enrichedFiles = $files
            }

            $normalizedVariant = [pscustomobject]@{
                label = [string]$variant.label
                region = [string]$variant.region
                archiveFile = [string]$variant.archiveFile
                romsetName = [string]$variant.romsetName
                romsetMode = if ([string]::IsNullOrWhiteSpace([string]$variant.romsetMode)) { "auto" } else { [string]$variant.romsetMode }
                coreOverride = [string]$variant.coreOverride
                biosUrl = [string]$variant.biosUrl
                requiredRomsets = @(
                    @($variant.requiredRomsets) |
                    ForEach-Object { [string]$_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Select-Object -Unique
                )
                files = @($enrichedFiles)
            }

            [void]$groups[$targetPlatform].Add($normalizedVariant)
        }

        foreach ($platform in $groups.Keys) {
            $normalizedGame = [pscustomobject]@{
                officialName = [string]$game.officialName
                description = [string]$game.description
                coverUrl = [string]$game.coverUrl
                variants = @($groups[$platform])
                platform = [string]$platform
            }
            [void]$result.Add($normalizedGame)
        }
    }

    # Keep deterministic ordering by platform then official name.
    return @($result | Sort-Object platform, officialName)
}

function Save-Json([string]$path, $obj) {
    $json = $obj | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$normalized = Normalize-Manifest -manifest $manifest
Save-Json -path $ManifestPath -obj $normalized
Write-Host "Updated $ManifestPath"

if ($UpdateArcadeManifest -and (Test-Path $ArcadeManifestPath)) {
    $arcade = Get-Content $ArcadeManifestPath -Raw | ConvertFrom-Json
    $arcadeNormalized = Normalize-Manifest -manifest $arcade | Where-Object { $_.platform -eq "Arcade" }
    Save-Json -path $ArcadeManifestPath -obj $arcadeNormalized
    Write-Host "Updated $ArcadeManifestPath"
}
