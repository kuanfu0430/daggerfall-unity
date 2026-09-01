#Requires -Version 5.1
# UTF-8 BOM required so Windows PowerShell 5.1 can parse Chinese strings.
<#
.SYNOPSIS
  Sync zh-TW overlays into a local DFU playtest build and launch the game.
#>
[CmdletBinding()]
param(
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$PlayRoot = Join-Path $RepoRoot 'play'
$CacheRoot = Join-Path $PlayRoot 'cache'
$DfuRoot = Join-Path $PlayRoot 'dfu'
$Streaming = Join-Path $DfuRoot 'DaggerfallUnity_Data\StreamingAssets'

$DfuZipName = 'dfu_windows_64bit-v1.1.1.zip'
$DfuTag = 'v1.1.1-cve-2025'
$DfuDownloadUrl = "https://github.com/Interkarma/daggerfall-unity/releases/download/$DfuTag/$DfuZipName"
$GameZipName = 'DaggerfallGameFiles.zip'
$GameDriveId = '0B0i8ZocaUWLGWHc1WlF3dHNUNTQ'
$FontCacheName = 'NotoSansCJKtc-Regular.otf'
$FontUrl = 'https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf'

$TranslatedFiles = @(
    'MainMenu.txt',
    'GameSettings.txt',
    'ModSystem.txt',
    'Internal_Settings.csv',
    'Internal_Strings.csv',
    'Internal_RSC.csv',
    'Internal_Items.csv',
    'Internal_MagicItems.csv',
    'Internal_Spells.csv',
    'Internal_Factions.csv',
    'Internal_Flats.csv',
    'Internal_Locations.csv',
    'Example_MageLight.csv'
)

function Write-Step([string]$Message) {
    Write-Host "[playtest] $Message"
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing command: $Name"
    }
}

function Get-FileMagic([string]$Path, [int]$Count = 4) {
    $bytes = New-Object byte[] $Count
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        [void]$stream.Read($bytes, 0, $Count)
    }
    finally {
        $stream.Dispose()
    }
    return ($bytes | ForEach-Object { $_.ToString('X2') }) -join '-'
}

function Test-ZipFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return (Get-FileMagic $Path) -eq '50-4B-03-04'
}

function Invoke-Download([string]$Url, [string]$Destination) {
    Assert-Command curl.exe
    $tmp = "$Destination.partial"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    & curl.exe -L --fail --retry 3 -A 'Mozilla/5.0' -o $tmp $Url
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed: $Url"
    }
    Move-Item -LiteralPath $tmp -Destination $Destination -Force
}

function Get-GoogleDriveFile([string]$FileId, [string]$Destination) {
    Assert-Command curl.exe
    $tmpHtml = "$Destination.drive.html"
    $firstUrl = "https://drive.google.com/uc?export=download&id=$FileId"
    & curl.exe -L --retry 3 -A 'Mozilla/5.0' -o $tmpHtml $firstUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot reach Google Drive: $FileId"
    }

    if ((Get-FileMagic $tmpHtml) -eq '50-4B-03-04') {
        Move-Item -LiteralPath $tmpHtml -Destination $Destination -Force
        return
    }

    $html = Get-Content -LiteralPath $tmpHtml -Raw -Encoding UTF8
    $uuid = [regex]::Match($html, 'name="uuid" value="([^"]+)"').Groups[1].Value
    $confirm = [regex]::Match($html, 'name="confirm" value="([^"]+)"').Groups[1].Value
    if (-not $confirm) { $confirm = 't' }
    if (-not $uuid) {
        throw 'Google Drive page has no uuid. Download DaggerfallGameFiles.zip manually into play/cache/'
    }

    $confirmUrl = "https://drive.usercontent.google.com/download?id=$FileId&export=download&confirm=$confirm&uuid=$uuid"
    Invoke-Download $confirmUrl $Destination
    Remove-Item -LiteralPath $tmpHtml -Force -ErrorAction SilentlyContinue

    if (-not (Test-ZipFile $Destination)) {
        throw 'Downloaded DaggerfallGameFiles.zip is not a zip'
    }
}

function Find-DfuExe {
    $direct = Join-Path $DfuRoot 'DaggerfallUnity.exe'
    if (Test-Path -LiteralPath $direct) { return $direct }
    $found = Get-ChildItem -LiteralPath $DfuRoot -Recurse -Filter 'DaggerfallUnity.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Ensure-DfuRuntime {
    New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
    $zip = Join-Path $CacheRoot $DfuZipName

    if (-not (Find-DfuExe)) {
        if (-not (Test-ZipFile $zip)) {
            Write-Step "Downloading official DFU Windows x64 ($DfuTag)..."
            $downloaded = $false
            if (Get-Command gh -ErrorAction SilentlyContinue) {
                & gh release download $DfuTag --repo Interkarma/daggerfall-unity --pattern $DfuZipName --dir $CacheRoot --clobber
                if ($LASTEXITCODE -eq 0 -and (Test-ZipFile $zip)) { $downloaded = $true }
            }
            if (-not $downloaded) {
                Invoke-Download $DfuDownloadUrl $zip
            }
        }
        Write-Step 'Extracting DFU...'
        if (Test-Path -LiteralPath $DfuRoot) { Remove-Item -LiteralPath $DfuRoot -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $DfuRoot | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $DfuRoot -Force

        $exe = Find-DfuExe
        if ($exe) {
            $exeDir = Split-Path -Parent $exe
            if ($exeDir -ne $DfuRoot) {
                Get-ChildItem -LiteralPath $exeDir | ForEach-Object {
                    Move-Item -LiteralPath $_.FullName -Destination (Join-Path $DfuRoot $_.Name) -Force
                }
            }
        }
    }

    if (-not (Find-DfuExe)) {
        throw "DaggerfallUnity.exe not found under $DfuRoot"
    }
}

function Ensure-GameFiles {
    $arena2 = Join-Path $Streaming 'GameFiles\arena2'
    $arch3d = Join-Path $arena2 'ARCH3D.BSA'
    if (Test-Path -LiteralPath $arch3d) { return }

    $zip = Join-Path $CacheRoot $GameZipName
    if (-not (Test-ZipFile $zip)) {
        Write-Step 'Downloading official Daggerfall game files...'
        Get-GoogleDriveFile $GameDriveId $zip
    }

    Write-Step 'Extracting arena2 into StreamingAssets/GameFiles...'
    $dest = Join-Path $Streaming 'GameFiles'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force

    if (-not (Test-Path -LiteralPath $arch3d)) {
        $found = Get-ChildItem -LiteralPath $dest -Recurse -Filter 'ARCH3D.BSA' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) {
            $srcArena = Split-Path -Parent $found.FullName
            $finalArena = Join-Path $dest 'arena2'
            New-Item -ItemType Directory -Force -Path $finalArena | Out-Null
            Copy-Item -Path (Join-Path $srcArena '*') -Destination $finalArena -Recurse -Force
        }
    }

    if (-not (Test-Path -LiteralPath $arch3d)) {
        throw "Still missing $arch3d after extract"
    }
}

function Copy-Glob([string]$SourceDir, [string]$Pattern, [string]$DestDir) {
    if (-not (Test-Path -LiteralPath $SourceDir)) { return 0 }
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    $items = @(Get-ChildItem -LiteralPath $SourceDir -Filter $Pattern -File -ErrorAction SilentlyContinue)
    foreach ($item in $items) {
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $DestDir $item.Name) -Force
    }
    return $items.Count
}

function Sync-Translations {
    $srcText = Join-Path $RepoRoot 'Assets\StreamingAssets\Text'
    $dstText = Join-Path $Streaming 'Text'
    New-Item -ItemType Directory -Force -Path $dstText | Out-Null

    foreach ($name in $TranslatedFiles) {
        $src = Join-Path $srcText $name
        if (-not (Test-Path -LiteralPath $src)) {
            throw "Missing translation: $src"
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $dstText $name) -Force
        Write-Step "Synced $name"
    }

    $bookCount = Copy-Glob (Join-Path $srcText 'Books') 'BOK*-LOC.txt' (Join-Path $dstText 'Books')
    Write-Step "Synced Books ($bookCount)"
    $questCount = Copy-Glob (Join-Path $srcText 'Quests') '*-LOC.txt' (Join-Path $dstText 'Quests')
    Write-Step "Synced Quests ($questCount)"
    $biogCount = Copy-Glob (Join-Path $RepoRoot 'Assets\StreamingAssets\BIOGs') 'BIOG*.TXT' (Join-Path $Streaming 'BIOGs')
    Write-Step "Synced BIOGs ($biogCount)"
}

function Get-TranslationCharset {
    $srcText = Join-Path $RepoRoot 'Assets\StreamingAssets\Text'
    $set = New-Object 'System.Collections.Generic.SortedSet[char]'
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($name in $TranslatedFiles) {
        $files.Add((Join-Path $srcText $name))
    }
    foreach ($pair in @(
        @((Join-Path $srcText 'Books'), 'BOK*-LOC.txt'),
        @((Join-Path $srcText 'Quests'), '*-LOC.txt'),
        @((Join-Path $RepoRoot 'Assets\StreamingAssets\BIOGs'), 'BIOG*.TXT')
    )) {
        $dir = $pair[0]
        $filter = $pair[1]
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Filter $filter -File | ForEach-Object { $files.Add($_.FullName) }
        }
    }
    foreach ($path in $files) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $text = [System.IO.File]::ReadAllText($path)
        foreach ($ch in $text.ToCharArray()) {
            if ([int]$ch -ge 0x80) { [void]$set.Add($ch) }
        }
    }
    return -join $set
}

function Sync-Fonts {
    $fontCache = Join-Path $CacheRoot $FontCacheName
    if (-not (Test-Path -LiteralPath $fontCache) -or ((Get-Item -LiteralPath $fontCache).Length -lt 1MB)) {
        Write-Step 'Downloading Noto Sans CJK TC...'
        Invoke-Download $FontUrl $fontCache
    }

    $dstFonts = Join-Path $Streaming 'Fonts'
    New-Item -ItemType Directory -Force -Path $dstFonts | Out-Null
    $charset = Get-TranslationCharset

    0..4 | ForEach-Object {
        $stem = 'FONT{0:0000}-SDF' -f $_
        Copy-Item -LiteralPath $fontCache -Destination (Join-Path $dstFonts "$stem.otf") -Force
        [System.IO.File]::WriteAllText(
            (Join-Path $dstFonts "$stem.txt"),
            $charset,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    Write-Step "Installed CJK font (charset $($charset.Length) glyphs)"
}

function Start-Game {
    $running = Get-Process -Name 'DaggerfallUnity' -ErrorAction SilentlyContinue
    if ($running) {
        Write-Step "Game already running (PID $($running.Id -join ', ')). Translations synced; restart the game to see them."
        return
    }

    $exe = Find-DfuExe
    Write-Step "Launching $exe"
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe)
}

Ensure-DfuRuntime
Ensure-GameFiles
Sync-Translations
Sync-Fonts

if ($NoLaunch) {
    Write-Step 'Ready (did not launch the game).'
    exit 0
}

Start-Game
Write-Step 'Done. Run PlayTest.bat again after editing translations.'
