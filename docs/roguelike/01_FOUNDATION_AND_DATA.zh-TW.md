# 01｜基礎執行環境、來源資料與確定性核心

前置：閱讀 [00 總計畫](00_MASTER_PLAN.zh-TW.md)。下一階段：[02 區塊世界](02_BLOCK_WORLD.zh-TW.md)。基準：`b64e84f2fae9240d5241c6a22554536aa8801dc2`。

**本階段終點：**新增可啟動的 2D 專用入口、可重跑的來源匯出，以及不依賴畫面幀率的 simulation 骨架。還不是最終 MVP；禁止以完成框架宣告 goal 完成。

## Phase 01.1｜一次完成能力檢查與獨立入口

### 實作

檢查 `ProjectSettings/ProjectVersion.txt`、現有 package lock 與建置設定；使用指定 Unity，不主動升級。檢查 Windows x64 Build Support、可執行測試的環境、合法可讀的 `ARENA2` 路徑，以及 agent harness 實際公開的生圖工具與其輸出檔案能力。不得假設工具名稱，也不得拿文件中的 API 範例當成已有憑證。

新增 `RoguelikeBootstrap` 與獨立場景入口；原始 Daggerfall 遊戲入口不變。Bootstrap 僅初始化來源讀取所需元件和新的 2D runtime，不能同時啟動原本 `PlayerMotor`、`EnemyMotor`、即時攻擊及另一套效果時鐘。

首次使用允許選一次原版資源路徑並保存設定；之後一鍵啟動。缺少來源要有明確 UI，不用無限載入畫面。純自製 fixture 僅用於單元測試，不能冒充原數值啟動正式模式。

### 產物與 gate

`environment-report.json`、可啟動場景、啟動命令與最小 Windows 測試 build。Gate：原入口回歸未壞；2D 入口可反覆啟閉；缺資源的錯誤可辨識；工具能力結果是實際測試而非推測。生圖可延到 03，但能力欠缺須先記錄。

## Phase 01.2｜資料盤點與原始 ID

### 實作

沿用現有讀取器，不重寫 BSA／SPELLS 格式。輸出：

| 目錄 | 必留欄位／意義 |
|---|---|
| 物品 | group、groupIndex、templateIndex、名稱 key、裝備槽、傷害上下界、重量、價值、耐久、材質、毒、附魔參數及神器身分。 |
| 敵人 | 來源 ID／career、屬性、技能、血量規則、各段攻擊範圍、抗性、最低命中材質、施法／感染等行為參照。 |
| 法術／藥水 | classic ID、effect key、variant、target type、element、magnitude/chance/duration 設定、花費及配方關係。 |
| 效果 | 來源 class、key、classic type/param、variant、trigger、合法參數域、間接依賴、保留／映射／排除狀態。 |
| 地點 | mapId、region/location index、RMB/RDB 配置、建築及室內子紀錄、門、marker 和機關參照。 |
| 角色／成長 | 能力值、技能 ID、career／種族規則、初始值與成長公式位置。 |

`ItemHelper.GetItemTemplate(group, groupIndex)` 與直接 templateIndex 不是同一個索引；必須實測 round-trip，不把 `Weapons.Dagger` 的 enum 整數當 groupIndex 傳回去。`ItemEnums` 的 ID 与裝備槽不能重排；禁用某個技能只能新增 active mask。[S1][S6，見總計畫來源]

來源正體中文名稱只供顯示，不參與 ID、seed 或 key。保留源碼 commit、各來源檔摘要、匯出器版本與選項。匯出原配置時關閉 SmallerDungeons，並隔離目前任務與全域 RNG；同 seed 的原資料不能因開著另一份存檔而不同。

這次先做全目錄盤點、少量地圖的詳細幾何匯出。不要把全世界逐一編譯成功當成後續 phase 的前置條件。

### 產物與 gate

`source-catalog.json`、`source-profile.json`、`effect-source-inventory.json`、來源／映射錯誤清單。重跑後標準化內容摘要一致；輸入數量、成功數量、排除及失敗可對帳。每個輸出值可指回來源或明確的 `adaptation-rule-id`，不得有未標註的手填替代值。

## Phase 01.3｜建立最小狀態與指令核心

### 實作

新增以下責任即可，不引入 ECS、服務容器或事件溯源框架：

```text
GameState: 世界時鐘、地圖實例、角色、物品實例、任務、RNG 狀態
ContentCatalog: 不可變的來源定義
PlayerCommand: 動作種類、方向／格位、目標或物品 ID
Simulation.Step: 驗證 → 提交狀態變更 → 排程 → 回傳 GameEvents
GameEvent: 移動、命中、傷害、效果、拾取、轉場、死亡等顯示事件
```

物品實例與模板分離；兩把同模板劍有不同 uid、耐久和附魔狀態。裝備引用同一 inventory instance，不可複製一份裝備資料導致賣掉後效果還在。所有範圍、方向、座標以整數及明確單位表示。

Core 不依賴原 3D MonoBehaviour；adapter 才接原資料。Unity 舊專案的 assembly 邊界要先實測：不要讓新增 asmdef 反向依賴 `Assembly-CSharp` 造成循環。可把純 Core 放獨立 assembly，舊類別 adapter 留在既有 assembly，以中立 DTO 交換。

建立穩定 PRNG 與保存格式。世界生成、戰鬥、掉落至少分三個獨立 stream；演算法、seed 推導與抽樣 API 有測試向量。不要用 `DateTime.Now`、`Time.frameCount`、`string.GetHashCode()`、執行期 dictionary 順序或生圖隨機數決定遊戲結果。

指令必須區分 `Rejected`（不耗時、不扣資源）與 `Committed`（有效嘗試，即使未命中仍耗時）。瞄準、預覽和 UI 不可消耗戰鬥 RNG。動畫只播放已提交事件，不能在動畫回呼再次扣血。

### 產物與 gate

可在測試地圖移動與等待；同初始狀態／指令序列得到相同 state hash。不同顯示幀率或跳過動畫不能改結果。相同內容模板建立的两個实例互不污染。暫時不做整個存檔 UI，但狀態已能序列化 round-trip。

## Phase 01.4｜公式盤點與轉換邊界

### 實作

建立 `rule-map.csv`，欄位至少為 `ruleId/sourceSymbol/sourceRevision/input/output/unit/rounding/randomCalls/adaptation/testId`。優先整理：

- 能力值修正、最大血量／魔力／負重、裝備材質、基礎傷害、命中與身體部位。
- 毒、抗性、豁免、法術成本、效果幅度與時間；附魔的直接及間接副作用。
- 原即時動畫時間、揮擊方向、反應設定，以及真正屬於 3D 的技能。

數字原樣保留不代表全部方法原樣呼叫。`FormulaHelper.CalculateAttackDamage()` 會使用 GameManager、揮擊動畫和 UI，還可能處理毒、耐久和神器效果；若外層又做一次，就會重複觸發。[S4]

先建立明確的 `CombatContext` 與可注入的擲骰接口；純數值助手能直接重用就重用，有副作用的方法抽成 handler。不要為隔離幾個依賴全面重構原遊戲。測試確切整數結果與來源 bounds，而不只比較平均傷害。

禁用技能保留原 enum 值；在預設角色的主要／次要技能組、升級計算與訓練 UI 中使用 active mask，不能讓攀爬被隱藏卻仍卡住升級門檻。跳躍／攀爬等純垂直增益依 00 排除，其餘效果進入 05 清單。

### 產物與 gate

`rule-map.csv`、三個來源角色 preset、公式對照 fixtures。Gate：短劍與弓箭資料索引正確；鐵／銀等材料結果能查源；命中是原百分骰而非自創 d20；初始角色可用的技能與 UI 一致。

## Phase 01.5｜自動執行入口與交接

新增腳本入口，名稱可依平台調整，但必須提供同一組職責：

```text
rg doctor
rg export-catalog
rg test core
rg run
rg build windows
```

這些是要實作的 wrapper，不是既有工具。Windows 提供 PowerShell；可附 shell，但不以跨所有平台作 gate。底層使用 Unity 的 batchmode／executeMethod 和現有 Test Framework，離開時傳回可靠 exit code。[E2][E3]

各命令提供 log 路徑和出錯摘要，禁止捕捉例外後回傳成功。匯出可按 source profile 暫存，不把 ARENA2、憑證或大體積快取推到 Git。保留可重建的小型合成 fixture。

### 本階段最後檢查

在 `PROGRESS.md` 記錄 01.1–01.5 的真實結果、commit 與下一入口。最低交接內容：2D scene、catalog、rule-map、序列化 state／RNG、core tests、實際啟動指令。通過後直接進入 02；不要停在要求使用者選資料庫或引擎。

## 來源

來源代號對應 [00 的源碼清單](00_MASTER_PLAN.zh-TW.md#10-源碼與外部依據)：S1、S2、S3、S4、S5、S6、S7、S9。上面的新資料結構、phase、驗收數量與指令均為本計畫設計，非原專案既有能力。
