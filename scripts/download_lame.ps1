<#
.SYNOPSIS
    Downloads and installs LAME 3.100 source for the KikoFlu Flutter Android build.

.DESCRIPTION
    Android's MediaCodec does NOT ship a software MP3 *encoder* on most devices
    (only decoders). To get reliable MP3 encoding on Android, we bundle LAME
    3.100 as a static native library and call it through JNI.

    This script automates the manual setup:
      1. Downloads lame-3.100.tar.gz from SourceForge
      2. Extracts it using built-in tar.exe (Windows 10 1803+) or 7-Zip
      3. Moves the extracted folder to android/app/src/main/cpp/lame/
      4. Verifies that include/lame.h is in place

    Works on:
      - Windows 10 (1803+) / Windows 11 with built-in tar.exe
      - Windows 7 / 8 / 10 (pre-1803) if 7-Zip is installed and in PATH
      - PowerShell 5.1 (Desktop) and PowerShell 7+ (Core)

.PARAMETER Force
    Re-download and re-install even if LAME is already present.

.PARAMETER LameVersion
    LAME version to install. Defaults to 3.100 (latest stable).

.PARAMETER ProjectRoot
    Path to the KikoFlu project root. Defaults to the parent of this script's
    directory (so the script works from any CWD).

.EXAMPLE
    .\scripts\download_lame.ps1

.EXAMPLE
    .\scripts\download_lame.ps1 -Force

.NOTES
    Author  : KikoFlu Edge
    License : GPL-3.0
    Tested  : Windows 10 21H2 / PowerShell 5.1, PowerShell 7.4
#>

[CmdletBinding()]
param(
    [switch]$Force = $false,
    [string]$LameVersion = "3.100",
    [string]$ProjectRoot = ""
)

# ──────────────────────────────────────────────
#  Setup
# ──────────────────────────────────────────────
$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Default project root: parent directory of this script
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = (Resolve-Path $ProjectRoot).Path

$TargetDir = Join-Path $ProjectRoot "android\app\src\main\cpp\lame"
$DownloadUrl = "https://sourceforge.net/projects/lame/files/lame/$LameVersion/lame-$LameVersion.tar.gz/download"
$TempDir = Join-Path $env:TEMP "kikoflu_lame_$(Get-Random)"
$Tarball = Join-Path $TempDir "lame-$LameVersion.tar.gz"
$ExtractDir = Join-Path $TempDir "extracted"
$ExpectedHeader = Join-Path $TargetDir "include\lame.h"

# ──────────────────────────────────────────────
#  Console helpers
# ──────────────────────────────────────────────
function Write-Banner {
    param([string]$Title)
    $line = "═" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Magenta
    Write-Host "  $Title" -ForegroundColor Magenta
    Write-Host $line -ForegroundColor Magenta
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "▶ $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

function Cleanup-Temp {
    if (Test-Path $TempDir) {
        Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
    }
}

# Register cleanup on script exit
trap {
    Cleanup-Temp
    Write-Host ""
    Write-Err "Script aborted: $_"
    exit 1
}

# ──────────────────────────────────────────────
#  Banner
# ──────────────────────────────────────────────
Write-Banner "KikoFlu Edge — LAME $LameVersion Setup for Android MP3 Encoding"
Write-Host "  Project root : $ProjectRoot"
Write-Host "  Target dir   : $TargetDir"
Write-Host "  Source URL   : $DownloadUrl"
Write-Host ""

# ──────────────────────────────────────────────
#  1. Check if already installed
# ──────────────────────────────────────────────
if ((Test-Path $ExpectedHeader) -and -not $Force) {
    Write-Ok "LAME is already installed."
    Write-Ok "Header found: $ExpectedHeader"
    $srcCount = (Get-ChildItem -Path (Join-Path $TargetDir "libmp3lame") -Filter "*.c" -ErrorAction SilentlyContinue).Count
    Write-Ok "Found $srcCount .c source files in libmp3lame/"
    Write-Host ""
    Write-Host "  Run with -Force to re-install." -ForegroundColor DarkGray
    exit 0
}

if ($Force -and (Test-Path $ExpectedHeader)) {
    Write-Warn "-Force specified; removing existing installation"
    Remove-Item -Recurse -Force $TargetDir
}

# ──────────────────────────────────────────────
#  2. Locate a tar/gzip extractor
# ──────────────────────────────────────────────
Write-Step "Locating tar/gzip extractor"

$Extractor = $null
$ExtractorType = $null

# Prefer Windows 10 1803+ built-in tar.exe (handles .tar.gz natively)
$winTar = Get-Command "tar.exe" -ErrorAction SilentlyContinue
if (-not $winTar) {
    $winTar = Get-Command "tar" -ErrorAction SilentlyContinue
}
if ($winTar) {
    $Extractor = $winTar.Source
    $ExtractorType = "tar"
    $tarVersion = (& $Extractor --version 2>&1 | Select-Object -First 1)
    Write-Ok "Using built-in tar: $Extractor"
    Write-Host "    $tarVersion" -ForegroundColor DarkGray
}

# Fall back to 7-Zip if available
if (-not $Extractor) {
    $sevenZip = Get-Command "7z" -ErrorAction SilentlyContinue
    $sevenZipExe = Get-Command "7z.exe" -ErrorAction SilentlyContinue
    if ($sevenZipExe) { $sevenZip = $sevenZipExe }
    if ($sevenZip) {
        $Extractor = $sevenZip.Source
        $ExtractorType = "7z"
        Write-Ok "Using 7-Zip: $Extractor"
    }
}

if (-not $Extractor) {
    Write-Err "No tar/gzip extractor found."
    Write-Host ""
    Write-Host "  Please install one of the following:" -ForegroundColor Yellow
    Write-Host "   1. Upgrade to Windows 10 1803+ or Windows 11 (has built-in tar.exe)" -ForegroundColor Yellow
    Write-Host "   2. Install 7-Zip (https://7-zip.org) and ensure '7z' is in PATH" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Or manually:" -ForegroundColor Yellow
    Write-Host "   1. Download: $DownloadUrl" -ForegroundColor Yellow
    Write-Host "   2. Extract to: $TargetDir" -ForegroundColor Yellow
    exit 1
}

# ──────────────────────────────────────────────
#  3. Download
# ──────────────────────────────────────────────
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

Write-Step "Downloading LAME $LameVersion"
Write-Host "    From: $DownloadUrl"
Write-Host "    To:   $Tarball"
Write-Host ""

$downloadSuccess = $false
$lastError = $null

# Attempt 1: WebClient (simple, no progress)
try {
    $wc = [System.Net.WebClient]::new()
    $wc.Headers.Add("User-Agent", "KikoFlu-Flutter/1.0 (PowerShell $($PSVersionTable.PSVersion))")
    $wc.DownloadFile($DownloadUrl, $Tarball)
    $downloadSuccess = $true
} catch {
    $lastError = $_
    Write-Warn "WebClient failed: $($_.Exception.Message)"
}

# Attempt 2: Invoke-WebRequest with redirect support
if (-not $downloadSuccess) {
    try {
        Write-Warn "Retrying with Invoke-WebRequest..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $Tarball -UseBasicParsing
        $downloadSuccess = $true
    } catch {
        $lastError = $_
        Write-Warn "Invoke-WebRequest failed: $($_.Exception.Message)"
    }
}

# Attempt 3: BITS (Background Intelligent Transfer Service)
if (-not $downloadSuccess) {
    try {
        Write-Warn "Retrying with BITS (Background Intelligent Transfer)..."
        Start-BitsTransfer -Source $DownloadUrl -Destination $Tarball -Description "LAME $LameVersion download"
        $downloadSuccess = $true
    } catch {
        $lastError = $_
    }
}

if (-not $downloadSuccess) {
    Write-Err "All download methods failed."
    Write-Host "  Last error: $lastError" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Manual download:" -ForegroundColor Yellow
    Write-Host "   1. Open in browser: $DownloadUrl" -ForegroundColor Yellow
    Write-Host "   2. Save as: $Tarball" -ForegroundColor Yellow
    Write-Host "   3. Re-run this script" -ForegroundColor Yellow
    Cleanup-Temp
    exit 1
}

$fileSize = (Get-Item $Tarball).Length
$fileSizeKb = [math]::Round($fileSize / 1KB, 1)
Write-Ok "Downloaded: $Tarball ($fileSizeKb KB)"

# Sanity check: a valid tar.gz should be at least 100KB
if ($fileSize -lt 100KB) {
    Write-Warn "Downloaded file is suspiciously small ($fileSizeKb KB)."
    Write-Warn "This is usually a SourceForge HTML redirect page, not the tarball."
    $firstBytes = Get-Content $Tarball -Encoding Byte -TotalCount 4 -ErrorAction SilentlyContinue
    if ($firstBytes -and ($firstBytes[0] -eq 0x1F -and $firstBytes[1] -eq 0x8B)) {
        Write-Ok "  File starts with gzip magic (0x1F 0x8B) — looks valid."
    } else {
        Write-Err "  File does not start with gzip magic. Probably an error page."
        Cleanup-Temp
        exit 1
    }
}

# ──────────────────────────────────────────────
#  4. Extract
# ──────────────────────────────────────────────
Write-Step "Extracting tarball"
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null

try {
    Push-Location $ExtractDir

    if ($ExtractorType -eq "tar") {
        # tar.exe handles .tar.gz in one step
        & $Extractor -xzf $Tarball
        if ($LASTEXITCODE -ne 0) {
            throw "tar exited with code $LASTEXITCODE"
        }
    }
    elseif ($ExtractorType -eq "7z") {
        # 7z requires two steps: .tar.gz -> .tar -> contents
        & $Extractor x $Tarball -y | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "7z step 1 (gzip) exited with code $LASTEXITCODE"
        }
        $innerTar = Join-Path $ExtractDir "lame-$LameVersion.tar"
        if (Test-Path $innerTar) {
            & $Extractor x $innerTar -y | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "7z step 2 (tar) exited with code $LASTEXITCODE"
            }
        } else {
            throw "Expected $innerTar not found after gzip extraction"
        }
    }

    Pop-Location
    Write-Ok "Extraction complete"
} catch {
    Pop-Location -ErrorAction SilentlyContinue
    Write-Err "Extraction failed: $_"
    Cleanup-Temp
    exit 1
}

# ──────────────────────────────────────────────
#  5. Locate extracted folder and move to target
# ──────────────────────────────────────────────
$extractedLameDir = Join-Path $ExtractDir "lame-$LameVersion"

if (-not (Test-Path $extractedLameDir)) {
    # Some archives may have a different top-level folder name
    $foundDirs = Get-ChildItem -Path $ExtractDir -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match "^lame" }
    if ($foundDirs.Count -eq 1) {
        $extractedLameDir = $foundDirs[0].FullName
        Write-Warn "Folder name differs: using $($foundDirs[0].Name)"
    } else {
        Write-Err "Expected folder 'lame-$LameVersion' not found in:"
        Write-Host "    $ExtractDir" -ForegroundColor Red
        Get-ChildItem $ExtractDir | ForEach-Object {
            Write-Host "      $($_.Name)" -ForegroundColor DarkGray
        }
        Cleanup-Temp
        exit 1
    }
}

Write-Step "Installing to $TargetDir"

# Ensure parent dir exists
$parentDir = Split-Path $TargetDir -Parent
if (-not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

# Remove existing target if present
if (Test-Path $TargetDir) {
    Write-Warn "Removing existing: $TargetDir"
    Remove-Item -Recurse -Force $TargetDir
}

Move-Item -Path $extractedLameDir -Destination $TargetDir
Write-Ok "Installed to: $TargetDir"

# ──────────────────────────────────────────────
#  6. Verify
# ──────────────────────────────────────────────
Write-Step "Verifying installation"

if (-not (Test-Path $ExpectedHeader)) {
    Write-Err "Header NOT found: $ExpectedHeader"
    Write-Host "  Installation seems incomplete." -ForegroundColor Yellow
    Cleanup-Temp
    exit 1
}
Write-Ok "Header found: $ExpectedHeader"

$srcCount = (Get-ChildItem -Path (Join-Path $TargetDir "libmp3lame") -Filter "*.c" -ErrorAction SilentlyContinue).Count
if ($srcCount -gt 0) {
    Write-Ok "Found $srcCount .c source files in libmp3lame/"
} else {
    Write-Warn "No .c source files found in libmp3lame/"
}

$includeCount = (Get-ChildItem -Path (Join-Path $TargetDir "include") -Filter "*.h" -ErrorAction SilentlyContinue).Count
if ($includeCount -gt 0) {
    Write-Ok "Found $includeCount header file(s) in include/"
}

# ──────────────────────────────────────────────
#  7. Cleanup temp
# ──────────────────────────────────────────────
Cleanup-Temp

# ──────────────────────────────────────────────
#  Done
# ──────────────────────────────────────────────
Write-Host ""
Write-Banner "✓ LAME $LameVersion installed successfully!"
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "    1. cd `"$ProjectRoot`"" -ForegroundColor White
Write-Host "    2. flutter clean" -ForegroundColor White
Write-Host "    3. flutter run" -ForegroundColor White
Write-Host ""
Write-Host "  In the app:" -ForegroundColor Cyan
Write-Host "    Settings → Downloads & Storage → Convert WAV after download" -ForegroundColor White
Write-Host "    Select MP3 — conversion will now work on your device." -ForegroundColor White
Write-Host ""

exit 0
