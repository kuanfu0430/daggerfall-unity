# Daggerfall Unity 臺灣繁體中文在地化

譯文在 [kuanfu0430/daggerfall-unity](https://github.com/kuanfu0430/daggerfall-unity) 的 `master` 維護（歷史分支 `l10n/zh-TW` 與 `master` 同步）。上游為 [Interkarma/daggerfall-unity](https://github.com/Interkarma/daggerfall-unity)。

## 遊戲如何讀譯文

依官方 wiki：把 CSV 從 `Assets/StreamingAssets/Text/Master Localization CSV Files` 複製到 `Assets/StreamingAssets/Text`，只改 **Value**，不改 **Key**。選單類 `.txt` 直接改逗號右側文本。中文需自備 Unicode 字型放到 `StreamingAssets/Fonts`。

## 翻譯範圍（完整交付）

- 啟動器／設定／模組 UI
- `Internal_Strings.csv`、`Internal_Settings.csv`、`Internal_RSC.csv`
- 物品／法術／派系／Flat／地名 CSV
- `Text/Books/BOK*-LOC.txt`（93）
- `Text/Quests/*-LOC.txt`（265；只覆蓋 QRC）
- `BIOGs/BIOG*.TXT` 角色背景

熱鍵 `DialogShortcuts.txt` 不譯。術語表：`l10n/zh-TW/glossary.md`。驗收：`python l10n/zh-TW/qa_full.py`。

## 怎麼測（不用編譯）

譯文是執行期覆蓋 `StreamingAssets`，**不必從源碼編譯**。之後再翻只要再點一次啟動器。

倉庫根目錄：

| 系統 | 啟動檔 |
| --- | --- |
| Windows | `測試翻譯.bat` 或 `PlayTest.bat` |
| macOS | `測試翻譯.command` 或 `PlayTest.command`（首次請在終端機 `chmod +x`） |
| Linux | `PlayTest.sh` |

它會：

1. 若還沒準備好，自動下載官方 DFU 1.1.1（Windows x64 / mac universal / Linux x64）與 wiki 提供的 DOS 遊戲檔
2. 把目前分支的繁中 txt/csv／書／任務／BIOG 同步進測試包
3. 安裝 Noto Sans CJK TC 字型（SDF 圖集只預載啟動器／設定 UI 用字；書、任務、地名的漢字在遊戲中動態補進圖集，避免開場卡死）
4. 啟動遊戲

本機測試包在 `play/`（已 gitignore，勿提交）。第一次需要網路；之後改譯文再點同一支啟動檔即可。Linux／macOS 需要 `curl`，以及 `unzip` 或 Python 3 其中一個來解壓。macOS 會把譯文寫進 `DaggerfallUnity.app/Contents/Resources/Data/StreamingAssets`（遊戲實際讀取的位置）。字型圖集只預載啟動器／設定用字；沒有 Python 3 時 Unix 腳本仍會寫入 ASCII＋標點字表，其餘漢字執行期動態補進圖集。

進遊戲後會先看到啟動器（解析度／開始遊戲／模組）。這正好用來驗 `MainMenu.txt`。設定頁驗 `GameSettings.txt`。沒放 `arena2` 時啟動器仍可開，但無法開始遊戲；這份測試包已把官方遊戲檔放進 `StreamingAssets/GameFiles`。
