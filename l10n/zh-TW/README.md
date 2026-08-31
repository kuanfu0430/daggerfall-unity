# Daggerfall Unity 臺灣繁體中文在地化

本分支 `l10n/zh-TW` 在 [kuanfu0430/daggerfall-unity](https://github.com/kuanfu0430/daggerfall-unity) 管理譯文。上游為 [Interkarma/daggerfall-unity](https://github.com/Interkarma/daggerfall-unity)。

## 遊戲如何讀譯文

依官方 wiki：把 CSV 從 `Assets/StreamingAssets/Text/Master Localization CSV Files` 複製到 `Assets/StreamingAssets/Text`，只改 **Value**，不改 **Key**。選單類 `.txt` 直接改逗號右側文本。中文需自備 Unicode 字型放到 `StreamingAssets/Fonts`。

## 本輪範圍（UI 抽樣）

- `Assets/StreamingAssets/Text/MainMenu.txt`
- `Assets/StreamingAssets/Text/GameSettings.txt`
- `Assets/StreamingAssets/Text/ModSystem.txt`
- `Assets/StreamingAssets/Text/DialogShortcuts.txt`
- `Assets/StreamingAssets/Text/Internal_Strings.csv`
- `Assets/StreamingAssets/Text/Internal_Settings.csv`

術語表：`l10n/zh-TW/glossary.md`
