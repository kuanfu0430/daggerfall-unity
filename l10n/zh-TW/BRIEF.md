# 翻譯作業簡報（所有子代理必讀）

譯入臺灣繁體。工作根目錄：`C:\Users\nearchan\Documents\agent_work\dfu-zh-tw`

## 必讀

- `l10n/zh-TW/glossary.md`
- 本檔

## 語言

- 禁止簡體。用「資訊／裡面／設定／螢幕／程式／選單／儲存／讀取／滑鼠／品質／開啟」。
- UI 宜短。書與任務可略帶古風但不拗口。
- 「Daggerfall Unity」整詞不譯。單獨 Daggerfall 譯「匕首雨」。
- 檔名、BSA、%巨集、[/標記]、`<ce>`、`<--->`、`_placeholder_`、Key 一律不譯。

## 格式

- CSV：只改 Value。Key、表頭不動。多行引號欄位保持合法 CSV。
- 書籍：可譯 Title、Author、正文；標簽名與 True/False／數字不譯。
- 任務 `*-LOC.txt`：只譯 DisplayName 與 QRC。可刪 QBN。保留 Message 編號。
- BIOG：只譯問答句，不譯 `#id` `!id` `GP` `r0` 數字列。

## 完成時回報

寫入路徑、條目／檔案數、未決術語、刻意保留英文的項目。不要 git commit。不要改你負責範圍以外的檔。
