#!/usr/bin/env bash
# Sync zh-TW overlays into a local DFU playtest build and launch the game.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLAY="$ROOT/play"
CACHE="$PLAY/cache"
DFU="$PLAY/dfu"
STREAMING="$DFU/DaggerfallUnity_Data/StreamingAssets"
TAG="v1.1.1-cve-2025"
FONT_NAME="NotoSansCJKtc-Regular.otf"
FONT_URL="https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf"
GAME_ZIP="DaggerfallGameFiles.zip"
GAME_DRIVE_ID="0B0i8ZocaUWLGWHc1WlF3dHNUNTQ"
NO_LAUNCH=0

if [[ "${1:-}" == "--no-launch" ]]; then
  NO_LAUNCH=1
fi

step() { printf '[playtest] %s\n' "$1"; }

die() { printf '[playtest] ERROR: %s\n' "$1" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

os_name() {
  case "$(uname -s)" in
    Darwin) echo mac ;;
    Linux) echo linux ;;
    *) die "Unsupported OS: $(uname -s). Use PlayTest.bat on Windows." ;;
  esac
}

zip_name() {
  case "$(os_name)" in
    mac) echo "dfu_mac_universal-v1.1.1.zip" ;;
    linux) echo "dfu_linux_64bit-v1.1.1.zip" ;;
  esac
}

is_zip() {
  [[ -f "$1" ]] && [[ "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" == "504b0304" ]]
}

download() {
  local url="$1" dest="$2"
  need curl
  local tmp="${dest}.partial"
  rm -f "$tmp"
  curl -L --fail --retry 3 -A "Mozilla/5.0" -o "$tmp" "$url"
  mv -f "$tmp" "$dest"
}

download_drive() {
  local dest="$CACHE/$GAME_ZIP"
  need curl
  local html="${dest}.drive.html"
  curl -L --retry 3 -A "Mozilla/5.0" -o "$html" "https://drive.google.com/uc?export=download&id=$GAME_DRIVE_ID"
  if is_zip "$html"; then
    mv -f "$html" "$dest"
    return
  fi
  local uuid confirm
  uuid="$(python3 - "$html" <<'PY'
import re,sys
text=open(sys.argv[1],encoding='utf-8',errors='replace').read()
m=re.search(r'name="uuid" value="([^"]+)"', text)
print(m.group(1) if m else '')
PY
)"
  confirm="$(python3 - "$html" <<'PY'
import re,sys
text=open(sys.argv[1],encoding='utf-8',errors='replace').read()
m=re.search(r'name="confirm" value="([^"]+)"', text)
print(m.group(1) if m else 't')
PY
)"
  [[ -n "$uuid" ]] || die "Google Drive page has no uuid. Put $GAME_ZIP in play/cache/"
  download "https://drive.usercontent.google.com/download?id=$GAME_DRIVE_ID&export=download&confirm=${confirm}&uuid=${uuid}" "$dest"
  rm -f "$html"
  is_zip "$dest" || die "Downloaded $GAME_ZIP is not a zip"
}

find_linux_bin() {
  find "$DFU" -type f \( -name 'DaggerfallUnity.x86_64' -o -name 'DaggerfallUnity' \) 2>/dev/null | head -n 1
}

find_mac_app() {
  find "$DFU" -type d -name 'DaggerfallUnity.app' 2>/dev/null | head -n 1
}

extract_zip() {
  local zip="$1" dest="$2"
  mkdir -p "$dest"
  if command -v unzip >/dev/null 2>&1; then
    unzip -qo "$zip" -d "$dest"
  else
    python3 - "$zip" "$dest" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
  fi
}

ensure_dfu() {
  mkdir -p "$CACHE"
  local zip="$CACHE/$(zip_name)"
  local ready=0
  case "$(os_name)" in
    linux) [[ -n "$(find_linux_bin)" ]] && ready=1 ;;
    mac) [[ -n "$(find_mac_app)" ]] && ready=1 ;;
  esac
  if [[ "$ready" -eq 1 ]]; then return; fi

  if ! is_zip "$zip"; then
    step "Downloading official DFU $(os_name) ($TAG)..."
    download "https://github.com/Interkarma/daggerfall-unity/releases/download/$TAG/$(zip_name)" "$zip"
  fi
  step "Extracting DFU..."
  rm -rf "$DFU"
  mkdir -p "$DFU"
  extract_zip "$zip" "$DFU"
}

ensure_game_files() {
  local arch3d="$STREAMING/GameFiles/arena2/ARCH3D.BSA"
  [[ -f "$arch3d" ]] && return
  local zip="$CACHE/$GAME_ZIP"
  if ! is_zip "$zip"; then
    step "Downloading official Daggerfall game files..."
    download_drive
  fi
  step "Extracting arena2..."
  mkdir -p "$STREAMING/GameFiles"
  extract_zip "$zip" "$STREAMING/GameFiles"
  if [[ ! -f "$arch3d" ]]; then
    local found
    found="$(find "$STREAMING/GameFiles" -name 'ARCH3D.BSA' 2>/dev/null | head -n 1)"
    if [[ -n "$found" ]]; then
      mkdir -p "$STREAMING/GameFiles/arena2"
      cp -R "$(dirname "$found")/." "$STREAMING/GameFiles/arena2/"
    fi
  fi
  [[ -f "$arch3d" ]] || die "Still missing $arch3d"
}

copy_named() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || die "Missing translation: $src"
  mkdir -p "$(dirname "$dest")"
  cp -f "$src" "$dest"
}

sync_translations() {
  local src_text="$ROOT/Assets/StreamingAssets/Text"
  local dst_text="$STREAMING/Text"
  mkdir -p "$dst_text"
  local name
  for name in \
    MainMenu.txt GameSettings.txt ModSystem.txt \
    Internal_Settings.csv Internal_Strings.csv Internal_RSC.csv \
    Internal_Items.csv Internal_MagicItems.csv Internal_Spells.csv \
    Internal_Factions.csv Internal_Flats.csv Internal_Locations.csv \
    Example_MageLight.csv
  do
    copy_named "$src_text/$name" "$dst_text/$name"
    step "Synced $name"
  done
  mkdir -p "$dst_text/Books" "$dst_text/Quests" "$STREAMING/BIOGs"
  local n
  n="$(find "$src_text/Books" -maxdepth 1 -name 'BOK*-LOC.txt' -type f | wc -l | tr -d ' ')"
  find "$src_text/Books" -maxdepth 1 -name 'BOK*-LOC.txt' -type f -exec cp -f {} "$dst_text/Books/" \;
  step "Synced Books ($n)"
  n="$(find "$src_text/Quests" -maxdepth 1 -name '*-LOC.txt' -type f | wc -l | tr -d ' ')"
  find "$src_text/Quests" -maxdepth 1 -name '*-LOC.txt' -type f -exec cp -f {} "$dst_text/Quests/" \;
  step "Synced Quests ($n)"
  n="$(find "$ROOT/Assets/StreamingAssets/BIOGs" -maxdepth 1 -name 'BIOG*.TXT' -type f | wc -l | tr -d ' ')"
  find "$ROOT/Assets/StreamingAssets/BIOGs" -maxdepth 1 -name 'BIOG*.TXT' -type f -exec cp -f {} "$STREAMING/BIOGs/" \;
  step "Synced BIOGs ($n)"
}

build_charset() {
  python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
text = root / 'Assets' / 'StreamingAssets' / 'Text'
# Seed atlas with launcher/UI glyphs only. Full CJK dump freezes DFU intro.
files = [
    text / n for n in [
        'MainMenu.txt','GameSettings.txt','ModSystem.txt',
        'Internal_Settings.csv','Internal_Strings.csv','Example_MageLight.csv',
    ]
]
chars = set(chr(i) for i in range(32, 127))
chars.update('、。，：；！？「」『』（）')
for path in files:
    if not path.is_file():
        continue
    for ch in path.read_text(encoding='utf-8', errors='replace'):
        if ord(ch) >= 0x80:
            chars.add(ch)
sys.stdout.write(''.join(sorted(chars)))
PY
}

sync_fonts() {
  local font="$CACHE/$FONT_NAME"
  if [[ ! -f "$font" ]] || [[ "$(wc -c < "$font" | tr -d ' ')" -lt 1000000 ]]; then
    step "Downloading Noto Sans CJK TC..."
    download "$FONT_URL" "$font"
  fi
  mkdir -p "$STREAMING/Fonts"
  local charset
  charset="$(build_charset)"
  local i
  for i in 0 1 2 3 4; do
    local stem
    stem="$(printf 'FONT%04d-SDF' "$i")"
    cp -f "$font" "$STREAMING/Fonts/${stem}.otf"
    printf '%s' "$charset" > "$STREAMING/Fonts/${stem}.txt"
  done
  step "Installed CJK font (charset ${#charset} glyphs)"
}

launch_game() {
  case "$(os_name)" in
    linux)
      local bin
      bin="$(find_linux_bin)"
      [[ -n "$bin" ]] || die "Linux DFU binary not found"
      chmod +x "$bin" || true
      find "$DFU" -type f -name '*.so' -exec chmod +x {} \; 2>/dev/null || true
      step "Launching $bin"
      (cd "$(dirname "$bin")" && nohup "$bin" >/dev/null 2>&1 &)
      ;;
    mac)
      local app
      app="$(find_mac_app)"
      [[ -n "$app" ]] || die "DaggerfallUnity.app not found"
      step "Launching $app"
      open "$app"
      ;;
  esac
}

ensure_dfu
ensure_game_files
sync_translations
sync_fonts

if [[ "$NO_LAUNCH" -eq 1 ]]; then
  step "Ready (did not launch the game)."
  exit 0
fi

launch_game
step "Done. Run the launcher again after editing translations."
