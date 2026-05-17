param(
    [string]$SourcePath = "",
    [string]$SourceUrl = "http://localhost:8088/nc-api/public.php/dav/files/jbXHPXxAxzj8ATB/mame-listxml.xml",
    [string]$DestinationPath = "wwwroot/data/mame-listxml.xml"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourcePath) -and [string]::IsNullOrWhiteSpace($SourceUrl)) {
    throw "Provide either -SourcePath or -SourceUrl."
}

$destDir = Split-Path $DestinationPath -Parent
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
    Write-Host "Copied MAME listxml from $SourcePath to $DestinationPath"
    return
}

$response = Invoke-WebRequest -Uri $SourceUrl -UseBasicParsing
$raw = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 65279) {
    $raw = $raw.Substring(1)
}
$fullDestinationPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $DestinationPath))
[System.IO.File]::WriteAllText($fullDestinationPath, $raw, [System.Text.UTF8Encoding]::new($false))
Write-Host "Downloaded MAME listxml from $SourceUrl to $DestinationPath"
