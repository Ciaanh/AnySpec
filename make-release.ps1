# make-release.ps1
# Packages addon files from the project root into AnySpec-v<version>.zip
# Usage: .\make-release.ps1 [-OutDir <path>]
#
# PowerShell 7+: Windows PowerShell 5.1's Compress-Archive writes "\" as the path separator
# inside the zip, which addon hosts and non-Windows extractors do not treat as folders.
#Requires -Version 7

param(
    [string]$OutDir = (Join-Path $PSScriptRoot ".build")
)

$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$tocFile     = Join-Path $projectRoot "AnySpec.toc"

# --- Read version from TOC --------------------------------------------------
$versionLine = Select-String -Path $tocFile -Pattern "^## Version:\s*(.+)" |
               Select-Object -First 1
if (-not $versionLine) {
    Write-Error "Could not find '## Version:' in $tocFile"
    exit 1
}
$version = $versionLine.Matches[0].Groups[1].Value.Trim()
$tag     = "v$version"

$zipName  = "AnySpec-$tag.zip"
$zipPath  = Join-Path $OutDir $zipName
$stageDir = Join-Path $projectRoot "AnySpec"

# --- Files and folders to include in the release ----------------------------
# Keep in sync with .pkgmeta's ignore list, which the CI release (.github/workflows) packages
# from instead: a file added here must not be ignored there, and vice versa.
$includes = @(
    "AnySpec.toc",
    "Core.lua",
    "SpecManager.lua",
    "ZoneDetector.lua",
    "AutoSwitch.lua",
    "LICENSE",
    "README.md",
    "Locales",
    "UI"
)

# --- Clean previous artifacts -----------------------------------------------
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
if (Test-Path $zipPath)  { Remove-Item $zipPath  -Force }

# --- Stage ------------------------------------------------------------------
Write-Host "Staging files from project root -> AnySpec/"
New-Item -ItemType Directory -Path $stageDir | Out-Null

foreach ($entry in $includes) {
    $src = Join-Path $projectRoot $entry
    if (-not (Test-Path $src)) {
        Write-Warning "Missing: $entry - skipped"
        continue
    }
    Copy-Item -Path $src -Destination $stageDir -Recurse
}

# assets: logo only - the other images are README screenshots, not part of a release
$assetsStageDir = Join-Path $stageDir "assets"
New-Item -ItemType Directory -Path $assetsStageDir | Out-Null
Copy-Item -Path (Join-Path $projectRoot "assets\logo.png") -Destination $assetsStageDir

# --- Zip --------------------------------------------------------------------
Write-Host "Creating $zipName ..."
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
Compress-Archive -Path $stageDir -DestinationPath $zipPath

# --- Cleanup ----------------------------------------------------------------
Remove-Item $stageDir -Recurse -Force

Write-Host "Release ready: $zipPath"
