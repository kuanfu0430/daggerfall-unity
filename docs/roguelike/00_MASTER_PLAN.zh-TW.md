# 00｜可玩 MVP 總計畫與 Agent 執行契約

日期：2026-09-08。源碼基準：`b64e84f2fae9240d5241c6a22554536aa8801dc2`。目標倉庫：`kuanfu0430/daggerfall-unity`。

**本次文件是開發計畫，不是已完成的遊戲、素材、測試結果或發行包。**文中類別、指令及新目錄除非明示為既有源碼，都是要求後續 agent 建立的產物。使用者要求的是可玩的 MVP；不是另做 MCP 伺服器。

## 1. 下一個 goal 的終點

交付一個有正式像素美術、繁體中文介面、可直接啟動的 Windows x64 單機 2D 回合制遊戲。玩家能完成：

> 新遊戲／選擇預設角色 → 村莊接任務及補給 → 進入由 block 組裝的地牢 → 探索、近戰、射箭、施法、拾取及換裝 → 取得任務物 → 返回交付 → 勝利結算；途中可存讀檔，也可能死亡並重新開始。

完成標準不是「某個 API 能回傳資料」「在 Unity Editor 裡有畫面」或「agent 自動測試能跑」。必須有人能在非 Editor 的發行包裡操作上述流程，且離線遊玩不依賴 LLM、生圖服務或任何 agent harness。

MVP 是縮小冒險範圍，不是以空白特效、假數值或未完成 UI 充當完整功能。原作全世界、全部主線及完整公會活動不是這個 goal 的前置條件，但原始內容的識別與轉換來源不可丟失。

## 2. 文件順序與完成關係

| 順序 | 文件 | 階段完成後玩家／開發者能做什麼 |
|---|---|---|
| 01 | [基礎執行環境與資料](01_FOUNDATION_AND_DATA.zh-TW.md) | 啟動獨立 2D 入口，匯出可追溯的資料，重播確定性指令。 |
| 02 | [區塊世界與生成](02_BLOCK_WORLD.zh-TW.md) | 在原資料轉換的村莊、室內與地牢之間行走，產生可重現的新布局。 |
| 03 | [生圖美術與探索介面](03_ART_AND_EXPLORATION.zh-TW.md) | 用正式素材、視野與迷霧探索，所有畫面有可辨識的圖像。 |
| 04 | [回合戰鬥與敵人](04_TURN_COMBAT.zh-TW.md) | 碰撞近戰、方向射箭、基礎施法；敌人也遵守同一回合與空間規則。 |
| 05 | [裝備、道具、魔法與特效](05_ITEMS_SPELLS_EFFECTS.zh-TW.md) | 使用實際裝備及可驗證的特效，包括附魔、負面效果和特殊神器。 |
| 06 | [冒險閉環、成長與存檔](06_ADVENTURE_AND_SAVE.zh-TW.md) | 從接任務玩到勝利／死亡，交易、休息、成長、存讀檔完整。 |
| 07 | [整合驗收與發行](07_QA_AND_RELEASE.zh-TW.md) | 取得可直接操作的發行包、安裝說明與可核查的測試證據。 |

每份文件再切成 phase。先線性完成同一資料契約；不要七個 agent 各自定義世界、回合和道具模型。Phase 通過後直接往下做，不例行停下要求使用者批准。

[前一份區塊調研](BLOCK_MAP_IMPLEMENTATION_REPORT.zh-TW.md)保留為來源研究。**本組 00–07 文件是本次 MVP 的執行依據**：較早報告要求的全地圖覆蓋、完整 3D 特殊移動及以原圖烘焙為主的美術，不再是本次 MVP 的 gate。仍保留 block-first、模板與實例分離、來源 ID、接縫與任務綁定原則。

## 3. 已決定的產品邊界

### 3.1 MVP 必有內容

- 一個使用原地點資料的補給聚落；至少商店、旅店／休息點、任務 NPC 三種服務，至少一個可進出的原 RMB 室內。
- 一個可重玩的地牢探險區，至少六種實際由來源 RDB 轉換的模板（包含需要的邊界模板），正式種子布局使用約 8–12 個 block 實例；另有一個原配置地圖回歸樣本。數量是驗收目標，不是已盤點的結果。
- 至少八種來源敵人，涵蓋普通近戰、遠程、施法、狀態攻擊及材質限制的測試；三種預設角色對應近戰、弓箭、施法。敵人仍用原資料 ID、屬性和傷害範圍。
- 至少兩種武器材質可實際取得，弓與箭、護甲、飾品、消耗品、附魔物和任務物；物品目錄不限於示範道具。
- 五種法術目標模式的 runtime；正常開局提供至少一個傷害、一個治療和一個工具法術，進階測試可從特效驗證場使用其餘功能。
- 一個主要取回任務、一個短支線、可顯示的勝負狀態；目標單輪約 20–40 分鐘，這是設計目標而非實測承諾。
- 正式生圖素材、音效、說明、鍵盤與滑鼠 UI、可恢復的本機存檔及實際 Windows build。

### 3.2 此 goal 不做的事情

不做第一人稱模式、自由跳躍、攀牆、空中高度控制、3D 物理投射物、全開放世界荒野、全部主線、公會長篇流程、多人、雲端帳號、即時 AI 對話、任意外部 mod 相容、舊 DFU 存檔匯入或新通用引擎。

保留上下樓／場景切換；它們是 2D 地圖間的明確連接，不是跳躍或攀爬系統。不得把疊在一起的房間誤接成平面十字路口。

## 4. 數據与規則的來源優先序

**原 DFU 資料與公式 → 明訂的 2D 轉換規則 → 可追蹤的新玩法設定。**不要把使用者所稱的「遊戲資料庫」誤解為要新建 SQL：既有資料包含 C# 定義、資源模板及原版資源檔。

已確認 `ItemHelper` 讀取普通與魔法物品模板；敵人資料由 `EnemyBasics` 與 `MONSTER.BSA` 等來源組合；標準法術由 `SPELLS.STD` 進入 `EntityEffectBroker`。[S1][S2][S3]

戰鬥操作參考 NetHack 的朝向移動／相鄰攻擊和方向投射；**不移植 NetHack 的數值，也不套用通用 D&D d20 公式**。DFU 的 `CalculateSuccessfulHit()` 最後將機率限制在 3–97，交給 `Dice100.SuccessRoll()`。[S4][E1]

數值不是把一個方法直接呼叫就完成：原 `CalculateAttackDamage()` 混有 `GameManager`、揮擊動畫、UI、副作用、毒與附魔觸發。要分離「讀入屬性／純運算／狀態事件」，保留來源整數取整與抽樣邊界；不要造出一組看起來相近的 RPG 數字。[S4]

## 5. 垂直玩法與「特效保留」的明確界線

使用者已授權迴避 3D 才需要的玩法。本計畫採取以下固定政策，agent 不得逐次請使用者判斷：

| 內容 | 本次處置 |
|---|---|
| 跳躍、攀爬、Slowfall 與其純粹增益 | `excluded-by-design: vertical-only`。原 ID 留在來源目錄，不出現在技能配點、商店、掉落、法術購買及獎勵候選。 |
| Levitate／WaterWalking／WaterBreathing 等可能有 2D 意義的能力 | 按 05 的地形通行／危害功能轉成 2D 能力，不引入自由高度或動畫物理。 |
| 以跳躍／攀爬才能到達的強制路線 | 不選入 MVP 模板池；不能自動挖牆冒充忠實轉換。特例可另做明示的 2D 改編版本。 |
| 攻擊、回復、抗性、持續狀態、負面附魔與神器特效 | 必須有真實 handler、可觀察結果與測試，不得只保留名稱或空函式。 |
| 原資料中的非垂直未知效果 | 進入 05 的待完成清單；不能自行加入垂直排除表，也不能用一般加攻擊力代替。 |

混合效果道具只移除已授權的純垂直子效果，保留其餘效果並更新顯示描述及估值；若剩下零效果，該純垂直魔法配置不得流入玩家可取得池。固定神器的非垂直效果不得因此刪除。所有這類修改都在 mapping 中保存來源與理由。

「全部特效」的分母由**全量來源魔法物品、神器、附魔類型／參數，以及它們間接呼叫的法術效果閉包**產生，不是只數 MVP 開局的五件裝備。按類型／參數域實作可大量重用，不需要每件裝備獨立寫程式。外部 mod 與來源本就保留未使用的未知欄位另列，不宣稱已完成未支援行為。

若某個非垂直效果需要聲望、日夜、耐久或召喚等小型服務，就建立真正影響玩法的最小服務；不能拿「不是主線必需」當成 no-op 的理由。原作尚未完成的分支亦需明列，不能把 upstream TODO 算成本移植已完成。

## 6. 架構與共用契約

保留此 fork 的 Unity 宿主，不先整包升級。新增獨立場景入口與隔離的 2D runtime；原 3D 遊戲仍能啟動。現有套件已包含 Tilemap、UGUI 與 Test Framework，可優先重用。[S5]

```text
DFU readers / data / formulas
        ↓ 匯出與 adapter
SourceCatalog + RuleProfile + EffectMapping
        ↓
BlockTemplate → LocationManifest → WorldState
                                      ↓
PlayerCommand → Simulation.Step → GameEvents
                                      ↓
                              Tilemap / UI / Audio

生圖工具 → 原始 atlas → 腳本切圖與驗證 → 固定 ArtCatalog
                                                ↓
                                         Tilemap / UI
```

Simulation 不讀 `Time.deltaTime`、物理碰撞、畫面顏色或生圖結果。圖片決定外觀，不決定牆能否通過或傷害多少。地圖、美術、戰鬥共享穩定內容 ID，而非用中文名称當 key。

新檔案建議集中於 `Assets/Scripts/Roguelike/`、`Assets/Game/Roguelike/`、`Assets/Editor/Roguelike/`、`Tools/Roguelike/`。這是建議新增目錄，不表示目前已有。需要 DotRecast 時可使用獨立工具；不要為轉換器強迫舊 Unity 直接載入不相容的最新版套件。

## 7. 共用操作、時鐘與空間政策

八方向移動，數字鍵盤與方向鍵必備；`yuhjklbn` 作可選 NetHack 式鍵位。朝敵人走即近戰，朝中立 NPC 互動不自動攻擊。`.` 等待、`g` 拾取、`i` 背包、`f` 射擊、`z` 施法、`e` 互動、`Esc` 取消／選單；按鍵可在 UI 查閱。

用整數 tick 排程。基礎動作 100 ticks，100 ticks = 10 遊戲秒；每 600 ticks 推進一個原資料的 game-minute magic round。這是本 MVP 的時間映射，不是宣稱原即時戰鬥本來有同樣節奏。DFU 的 magic round 原本由遊戲分鐘驅動。[S3]

玩家停在輸入畫面或看背包不推進世界。查看、切換瞄準、取消與明確無效指令不扣時間；實際攻擊、裝備、使用物品、開門和失敗的有效嘗試依 04/05 扣時間。不容許看 UI 期間敵人繼續行動。

地圖顯示層與來源高度可保留，但正常移动仅在當前 walkable surface；跨層必經明確連接。移動、FOV 與投射都必須定義斜角遮挡，不可各自允許穿牆。詳細規則以 02、04 為準。

## 8. Agent 不需反覆請示的執行方式

每個 phase 依序：讀當前文件與前一 phase 的交接 → 先跑現有測試 → 做最小完整改動 → 跑新增及回歸測試 → 更新 `docs/roguelike/PROGRESS.md` → commit → 下一 phase。`PROGRESS.md` 是後續開發產物，本次不預填假完成狀態。

交接只記錄：phase ID、實作 commit、實際指令與結果、可操作入口、檔案／測試報告位置、已知失敗及下一步。不要重新生成整套 spec、引入更多管理框架或每 phase 開一輪長篇方案比較。

遇到真正缺少的環境能力（Unity 啟用／原版資源／生圖工具授權／建置模組），記錄缺失與可繼續工作；可先做不依賴它的 phase，但相應 gate 保持 BLOCKED。不能捏造生圖調用、把 fixture 當原版資料、以 Editor 截圖替代已驗證發行包。具備必要環境後，正常流程應可連續跑到 07。

只把不可逆刪除用戶檔案、額外付費授權／超出已批准工具額度、違反權限等問題交回使用者；一般參數、檔名、圖塊配色、模板選擇與測試修復照本計畫處理。

## 9. 最终 gate

同一發行 commit 必須同時有：正式 atlas 及來源記錄、正確數值來源、非垂直物品特效閉包的完整映射與通過測試、完整冒險、正常死亡、存讀檔重現、至少一套實際受測 Windows x64 包。`SKIPPED` 和 `BLOCKED` 不是 PASS。全目錄匯出不能冒充全部內容可玩。

資源數量與效能需在開發時實測。此處的數字均是目標或明確設計值；目前沒有執行 Unity、真實資料匯出、素材生成或遊玩驗收。

## 10. 源碼與外部依據

以下固定源碼均指向本次基準 commit，後續 agent 應先比較自己的工作基準，不自動更新規則。

- [S1｜ItemHelper：普通／魔法／神器模板與 ItemUseHandler](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Game/Items/ItemHelper.cs)
- [S2｜EnemyBasics：靜態敵人定義與 MONSTER.BSA 邊界](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Utility/EnemyBasics.cs)
- [S3｜EntityEffectBroker：法術、效果註冊與魔法回合](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Game/MagicAndEffects/EntityEffectBroker.cs)
- [S4｜FormulaHelper：命中、傷害、材質、部位、副作用](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Game/Formulas/FormulaHelper.cs#L527-L850)
- [S5｜Packages/manifest.json](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Packages/manifest.json)
- [S6｜ItemEnums：ID、材質、裝備槽與部位](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Game/Items/ItemEnums.cs)
- [S7｜EntityEffectManager：即時元件與回合事件依賴](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Game/MagicAndEffects/EntityEffectManager.cs)
- [S8｜CastWhenStrikes：觸發條件、效果 bundle、耐久扣除](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Game/MagicAndEffects/Effects/Enchanting/CastWhenStrikes.cs)
- [S9｜MapsFile：原配置與 SmallerDungeons](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/API/MapsFile.cs)
- [S10｜CityNavigation：RMB 導航底稿](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Game/Utility/CityNavigation.cs)
- [S11｜RMBLayout：地點建築資料綁定](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Utility/RMBLayout.cs)
- [S12｜DaggerfallDungeon：RDB 組裝、入口、水位與重疊門](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Internal/DaggerfallDungeon.cs)
- [S13｜Place：任務地點與標記](https://github.com/kuanfu0430/daggerfall-unity/blob/b64e84f2fae9240d5241c6a22554536aa8801dc2/Assets/Scripts/Game/Questing/Place.cs)
- [E1｜NetHack 3.6.7 Guidebook，作明確版本的操作參照，不稱最新版](https://www.nethack.org/v367/Guidebook.html)
- [E2｜Unity 2019.4 命令列](https://docs.unity3d.com/2019.4/Documentation/Manual/CommandLineArguments.html)
- [E3｜Unity Test Framework 1.1 命令列測試](https://docs.unity3d.com/Packages/com.unity.test-framework@1.1/manual/reference-command-line.html)
