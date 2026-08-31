#Requires -Version 5.1
<#
.SYNOPSIS
  把目前分支的繁中譯文同步進本機 DFU 測試包，然後啟動遊戲。
  雙擊倉庫根目錄的「測試翻譯.bat」即可。
#>
[CmdletBinding()]
param(
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$PlayRoot = Join-Path $RepoRoot 'play'
$CacheRoot = Join-Path $PlayRoot 'cache'
$DfuRoot = Join-Path $PlayRoot 'dfu'
$DfuExe = Join-Path $DfuRoot 'DaggerfallUnity.exe'
$Streaming = Join-Path $DfuRoot 'DaggerfallUnity_Data\StreamingAssets'

$DfuZipName = 'dfu_windows_64bit-v1.1.1.zip'
$DfuTag = 'v1.1.1-cve-2025'
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
    Write-Host "[測試翻譯] $Message"
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "找不到指令：$Name"
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
    if (-not (Test-Path $Path)) { return $false }
    return (Get-FileMagic $Path) -eq '50-4B-03-04'
}

function Invoke-Download([string]$Url, [string]$Destination) {
    Assert-Command curl.exe
    $tmp = "$Destination.partial"
    if (Test-Path $tmp) { Remove-Item -Force $tmp }
    & curl.exe -L --fail --retry 3 -A 'Mozilla/5.0' -o $tmp $Url
    if ($LASTEXITCODE -ne 0) {
        throw "下載失敗：$Url"
    }
    Move-Item -Force $tmp $Destination
}

function Get-GoogleDriveFile([string]$FileId, [string]$Destination) {
    Assert-Command curl.exe
    $tmpHtml = "$Destination.drive.html"
    $firstUrl = "https://drive.google.com/uc?export=download&id=$FileId"
    & curl.exe -L --retry 3 -A 'Mozilla/5.0' -o $tmpHtml $firstUrl
    if ($LASTEXITCODE -ne 0) {
        throw "無法連線 Google Drive：$FileId"
    }

    if ((Get-FileMagic $tmpHtml) -eq '50-4B-03-04') {
        Move-Item -Force $tmpHtml $Destination
        return
    }

    $html = Get-Content -LiteralPath $tmpHtml -Raw -Encoding UTF8
    $uuid = [regex]::Match($html, 'name="uuid" value="([^"]+)"').Groups[1].Value
    $confirm = [regex]::Match($html, 'name="confirm" value="([^"]+)"').Groups[1].Value
    if (-not $confirm) { $confirm = 't' }
    if (-not $uuid) {
        throw 'Google Drive 下載頁沒有 uuid，請改用手動下載 DaggerfallGameFiles.zip'
    }

    $confirmUrl = "https://drive.usercontent.google.com/download?id=$FileId&export=download&confirm=$confirm&uuid=$uuid"
    Invoke-Download $confirmUrl $Destination
    Remove-Item -Force $tmpHtml -ErrorAction SilentlyContinue

    if (-not (Test-ZipFile $Destination)) {
        throw 'DaggerfallGameFiles.zip 下載結果不是 zip'
    }
}

function Ensure-DfuRuntime {
    New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
    $zip = Join-Path $CacheRoot $DfuZipName

    if (-not (Test-Path $DfuExe)) {
        if (-not (Test-ZipFile $zip)) {
            Write-Step "下載官方 DFU Windows 64-bit（$DfuTag）…"
            Assert-Command gh
            & gh release download $DfuTag --repo Interkarma/daggerfall-unity --pattern $DfuZipName --dir $CacheRoot --clobber
            if ($LASTEXITCODE -ne 0) { throw 'gh 下載 DFU 失敗' }
        }
        Write-Step '解壓 DFU 測試包…'
        if (Test-Path $DfuRoot) { Remove-Item -Recurse -Force $DfuRoot }
        New-Item -ItemType Directory -Force -Path $DfuRoot | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $DfuRoot -Force
    }

    if (-not (Test-Path $DfuExe)) {
        throw "找不到 $DfuExe"
    }
}

function Ensure-GameFiles {
    $arena2 = Join-Path $Streaming 'GameFiles\arena2'
    $arch3d = Join-Path $arena2 'ARCH3D.BSA'
    if (Test-Path $arch3d) { return }

    $zip = Join-Path $CacheRoot $GameZipName
    if (-not (Test-ZipFile $zip)) {
        Write-Step '下載官方 Daggerfall 遊戲檔（DFU wiki Google Drive）…'
        Get-GoogleDriveFile $GameDriveId $zip
    }

    Write-Step '解壓 arena2 到 StreamingAssets/GameFiles…'
    $dest = Join-Path $Streaming 'GameFiles'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force

    if (-not (Test-Path $arch3d)) {
        throw "解壓後仍找不到 $arch3d"
    }
}

function Sync-Translations {
    $srcText = Join-Path $RepoRoot 'Assets\StreamingAssets\Text'
    $dstText = Join-Path $Streaming 'Text'
    New-Item -ItemType Directory -Force -Path $dstText | Out-Null

    foreach ($name in $TranslatedFiles) {
        $src = Join-Path $srcText $name
        if (-not (Test-Path $src)) {
            throw "譯文不存在：$src"
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $dstText $name) -Force
        Write-Step "已同步 $name"
    }

    $srcBooks = Join-Path $srcText 'Books'
    $dstBooks = Join-Path $dstText 'Books'
    if (Test-Path $srcBooks) {
        New-Item -ItemType Directory -Force -Path $dstBooks | Out-Null
        Copy-Item -Path (Join-Path $srcBooks 'BOK*-LOC.txt') -Destination $dstBooks -Force
        Write-Step '已同步 Books'
    }

    $srcQuests = Join-Path $srcText 'Quests'
    $dstQuests = Join-Path $dstText 'Quests'
    if (Test-Path $srcQuests) {
        New-Item -ItemType Directory -Force -Path $dstQuests | Out-Null
        Get-ChildItem -LiteralPath $srcQuests -Filter '*-LOC.txt' | Copy-Item -Destination $dstQuests -Force
        Write-Step '已同步 Quests *-LOC'
    }

    $srcBiog = Join-Path $RepoRoot 'Assets\StreamingAssets\BIOGs'
    $dstBiog = Join-Path $Streaming 'BIOGs'
    if (Test-Path $srcBiog) {
        New-Item -ItemType Directory -Force -Path $dstBiog | Out-Null
        Copy-Item -Path (Join-Path $srcBiog 'BIOG*.TXT') -Destination $dstBiog -Force
        Write-Step '已同步 BIOGs'
    }
}

function Get-TranslationCharset {
    $srcText = Join-Path $RepoRoot 'Assets\StreamingAssets\Text'
    $set = New-Object 'System.Collections.Generic.SortedSet[char]'
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($name in $TranslatedFiles) {
        $files.Add((Join-Path $srcText $name))
    }
    $books = Join-Path $srcText 'Books'
    if (Test-Path $books) {
        Get-ChildItem -LiteralPath $books -Filter 'BOK*-LOC.txt' | ForEach-Object { $files.Add($_.FullName) }
    }
    $quests = Join-Path $srcText 'Quests'
    if (Test-Path $quests) {
        Get-ChildItem -LiteralPath $quests -Filter '*-LOC.txt' | ForEach-Object { $files.Add($_.FullName) }
    }
    $biogs = Join-Path $RepoRoot 'Assets\StreamingAssets\BIOGs'
    if (Test-Path $biogs) {
        Get-ChildItem -LiteralPath $biogs -Filter 'BIOG*.TXT' | ForEach-Object { $files.Add($_.FullName) }
    }
    foreach ($path in $files) {
        if (-not (Test-Path $path)) { continue }
        $text = [System.IO.File]::ReadAllText($path)
        foreach ($ch in $text.ToCharArray()) {
            $code = [int]$ch
            if ($code -ge 0x80) { [void]$set.Add($ch) }
        }
    }
    return -join $set
}

function Sync-Fonts {
    $fontCache = Join-Path $CacheRoot $FontCacheName
    if (-not (Test-Path $fontCache) -or ((Get-Item $fontCache).Length -lt 1MB)) {
        Write-Step '下載 Noto Sans CJK TC 字型…'
        Invoke-Download $FontUrl $fontCache
    }

    $dstFonts = Join-Path $Streaming 'Fonts'
    New-Item -ItemType Directory -Force -Path $dstFonts | Out-Null
    $charset = Get-TranslationCharset

    0..4 | ForEach-Object {
        $stem = 'FONT{0:0000}-SDF' -f $_
        Copy-Item -LiteralPath $fontCache -Destination (Join-Path $dstFonts "$stem.otf") -Force
        [System.IO.File]::WriteAllText((Join-Path $dstFonts "$stem.txt"), $charset, [System.Text.UTF8Encoding]::new($false))
    }
    Write-Step "已安裝中文字型（字表 $($charset.Length) 字）"
}

function Start-Game {
    $running = Get-Process -Name 'DaggerfallUnity' -ErrorAction SilentlyContinue
    if ($running) {
        Write-Step "遊戲已在執行（PID $($running.Id -join ', ')）。已同步譯文，請關掉再開一次才看得到這次的改動。"
        return
    }

    Write-Step "啟動 $DfuExe"
    Start-Process -FilePath $DfuExe -WorkingDirectory $DfuRoot
}

Ensure-DfuRuntime
Ensure-GameFiles
Sync-Translations
Sync-Fonts

if ($NoLaunch) {
    Write-Step '準備完成（未啟動遊戲）。'
    exit 0
}

Start-Game
Write-Step '完成。之後改譯文只要再點一次「測試翻譯.bat」。'
