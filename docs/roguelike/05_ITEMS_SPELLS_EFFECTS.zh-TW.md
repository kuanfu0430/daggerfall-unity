# 05｜裝備、消耗品、魔法與完整物品特效

前置：[01 資料](01_FOUNDATION_AND_DATA.zh-TW.md)、[04 戰鬥事件](04_TURN_COMBAT.zh-TW.md)。下一階段：[06 冒險與存檔](06_ADVENTURE_AND_SAVE.zh-TW.md)。

**本階段終點：**物品不是圖示與數字表而已；裝備、使用、命中、時間與環境觸發的效果都會真正改變世界。除 00 已授權排除的純垂直項，原物品特效必須有對應 function。這部分不是只搬資料就會自動完成，亦不得用 no-op 兌現要求。

## Phase 05.1｜完整依賴閉包與覆蓋分母

### 實作

從 01 的來源目錄建立 `effect-coverage.json` 和可讀報表。涵蓋普通 item-use 路徑、全量 MagicItemTemplates、全部來源神器定義，以及原版可生成的附魔種類／合法參數，不只掃當前掉落表。

對 `CastWhenUsed/Held/Strikes` 等間接效果，遞迴追查其 classic spell ID、effect keys、variants、目標模式及其觸發的其他功能，直到依賴閉合。原 source 的未使用資料、外部 mod、自訂分支與 upstream TODO 分開列出，不能假定它們都有可直接沿用的完成函式。

每列至少保存：

```text
sourceEffectId / classicType / paramDomain / variant
referencedByItems / referencedBySpells / sourceSymbol
policy: preserved | mapped-2d | excluded-vertical | pending
handlerId / trigger / target / lifetime / stacking
resourceCost / dependencies / testCases / actualResult
```

只能以 00 已寫明的跳躍、攀爬、Slowfall 等純垂直設計項作排除。未完成的非垂直項只能是 pending，不得擴大排除名單以縮小分母。對參數化效果可一個 handler 支援整個 domain，但需測邊界與代表 variants；不能只測參數 0 就聲稱所有參數有效。

若某神器沒有現成完整行為，建立對應 `05.6.Axx` 工作項，來源已明確部分依源實作，缺少部分以同名功能的明確 2D 契約補足並標示改編。不能留下通用「神器發光了」訊息後回傳成功。

### Gate

所有入口效果均可追到 handler 任務或明確垂直排除；沒有 dangling spell/effect key。此 phase 是盤點通過，不是特效全部完成。最終 gate 要等 05.7／07 的實際結果。

## Phase 05.2｜背包、裝備、材料與耐久

### 實作

保留來源裝備槽、左右手、雙手武器與盾牌衝突、護甲部位、衣物／飾品欄位，不隨意壓成「武器＋衣服」兩個欄位。UI 可分頁，但對應來源 slots 不改 ID。[S6]

`ItemInstance` 保存 uid、templateRef、material、condition、stack、poison、enchantments、identified 狀態及需要的來源字段。只有屬性完全相容的可堆疊物才能合併，不能把不同耐久／附魔／鑑定狀態的物件合成一份。

裝備／卸下是原子動作：驗證相容性與所有欄位變更 → 解除舊來源效果 → 更新引用 → 附加新來源效果 → 重算派生屬性 → 扣一次時間。中途失敗全部保持原狀。不要把玩家屬性永久加 10 後忘記卸裝減回來。

耐久與充能依來源字段及 callback 的意義區分：DFU 的某些施法附魔消耗的是 durability，不是所有物品都有一個通用 charges 欄位。`CastWhenStrikes` 的來源 callback 在有效傷害時施法並回報 10 點耐久消耗，應保留該規則及觸發條件，而不是按滑鼠點擊次數扣。[S8]

破損、修復、販賣、丟棄、死亡與換場景要正確解除／恢復效果。Source item uid 与 effect instanceId 綁定，賣掉裝備不能留下加成；兩個同種戒指按来源疊加規則共存，不因同 key 被錯誤合併。

### Gate

雙手／盾衝突、滿背包、分堆、裝備後販賣、破損、毒消耗、重複穿脫及同類飾品都有測試。重量、傷害与耐久来自來源；介面與實際計算一致。

## Phase 05.3｜共用效果執行器

### 實作

用 typed handler 或 delegate registry 即可，不建可執行任意腳本的魔法語言。最小生命週期：

```text
Validate(context) → Apply(instance)
OnEvent(instance, domainEvent)
OnMagicRound(instance, worldTime)
Expire/Remove(instance, reason)
SerializeState(instance)
```

最少需要 OnUse、OnEquip、OnUnequip、OnSuccessfulDamage、OnDamageReceived、OnKill、OnMagicRound、OnWorldTimeAdvance、OnEnvironmentChanged、OnRest，以及 SourceRemoved／Broken 等事件。各 effect 對哪些事件反應由來源與 coverage 決定，不是全部廣播後每個 handler 都隨機判斷。

所有數值型效果共用：回復／傷害 Health、Fatigue、SpellPoints；屬性與技能增減；抗性／豁免／免疫；護甲／命中修正；持續傷害与狀態期限。magnitude、chance、duration 的等級計算、整數處理和原始單位依來源，不把原分鐘當畫面幀數。

DFU magic round 每遊戲分鐘觸發；本版依 00/04 每 600 global ticks 處理一次。[S3] DoT、再生、裝備週期效果只跟世界時間走，不依某角色行動次數。休息／長時間跳轉按事件時間補算，不直接把角色回滿血後忽略中毒。

source→target→secondary 的連鎖帶 causal event ID，防止同一事件重複結算。反射／吸收先照來源順序，對可能的反射循環加最多八層安全上限並明示為防無限循環的改編；不能為了防循環把所有反射刪掉。死亡、觸發傷害和耐久結算的順序固定並可測。

### Gate

效果出現、續期／疊加、移除与讀檔一致；DoT 和再生時點正確；附魔傷害不再觸發同一個 source event 無限遞迴。裝備、法術、藥水使用同一條效果管線，不各寫三份平行邏輯。

## Phase 05.4｜藥水、法術、工具與目標模式

### 實作

把 04 的投射／範圍功能接到完整效果 bundle。保留 CasterOnly、ByTouch、SingleTargetAtRange、AreaAroundCaster、AreaAtRange；element 同來源火、冰、毒、電、魔法，不能只換粒子顏色。

藥水飲用／物件啟用依原 item-use 與 effect mappings，validate 後才扣庫存或耐久。缺目標或使用取消不吞物品；有效使用但未成功則依來源消耗。複合 bundle 保留各子效果顺序、成功率及成本，不只取第一個 effect。

辨識、開鎖／開門、隱形、光照、偵測、驅散、傳送／Recall、召喚、吸收與反射等，接入可觀察的 2D 世界功能。正常遊玩開局可只有少量法術，完整物品特效依賴的法術不得因沒有放在商店就不實作。

source 沒有 active use 的一般戰利品可合法只有出售／描述用途；這不叫 no-op 特效。但有明確啟用效果的道具不得以同理由僅開描述視窗。

### Gate

從背包點藥水真正回血、从附魔物發出對應法術、缺魔和缺耐久有正確訊息。所有五種目標模式都能在效果驗證場操作，且成本、抵抗、觸發與投射事件可對帳。

## Phase 05.5｜固定 2D 語意映射

以下為 agent 可直接實作的產品決策；並非宣稱原 DFU 已這樣運作。每個來源效果的具體數值仍從來源讀取。

| 效果族 | 2D function／可觀察行為 |
|---|---|
| 跳躍、攀爬、Slowfall 的純垂直功能 | 來源保留，生成與配點／購買入口排除；混合 bundle 只去除該子項，更新描述／估值。 |
| Levitate | `GrantGroundHazardBypass`：可通過同平面的深水危害而不耗氣、不觸發地面陷阱；不可穿牆、關門或任意跨層。 |
| WaterWalking | `GrantWaterSurfacePassage`：水面移动不耗氣、免水地形额外移動成本；不免非水陷阱。 |
| WaterBreathing | `GrantDrowningImmunity`：深水不發生耗氣傷害，但仍有水地形成本，與水行不是同一效果。 |
| 增強技能／talent | 非垂直技能修改實際公式；垂直子參數按排除處理，不重排源 enum。 |
| Invisibility／Chameleon | 修改敵人感知／命中條件與揭露事件；不能僅讓 sprite 半透明。 |
| Light／Darkness／偵測 | 改 FOV、已知物件 overlay 或指定類型感知；記憶地形不等於看見敵人，不提供未授權穿牆視野。 |
| Recall／Teleport | 保存並使用 `(runId, locationInstanceId, surfaceId, cell)` 錨點，跨圖保持身份；目的格有角色時按固定鄰域順序找合法格，無合法格明確失敗。 |
| Paralysis／FreeAction／Silence／Charm／Calm | 真正限制動作或改變 AI／敵我關係，並按來源的解除／免疫規則處理。 |
| Regeneration／Leech／Poison／Disease | 經 global clock 改變生命／耐力／魔力、狀態与死亡；治療／免疫能阻止相應結果。 |
| Feather／ExtraWeight／WeightAllowance | 改實際重量或容量並影響負重移動／拾取，不能只是描述。 |
| Repair／Deteriorate | 改目標物品實例 condition；破損會失效、修復會恢復，適用條件与時間沿用來源。 |
| GoodRep／BadRep／BadReactions | 修改實際派系聲望／目標類別反應；最小 NPC 服務與 AI 會讀取，06 商店服務可驗證。 |
| 日夜／室內外等條件附魔 | 讀世界時鐘與 map tags 切換，有狀態變化事件；不讀畫面亮度。 |
| Soul、Summon、Transform、特殊神器 | 各有 source ID 對應 handler，建立來源要求的最小靈魂／友軍／形態狀態；不是全數映射成攻擊力增加。 |

深水通行能力到期：角色留在目前格，恢復原本水危害與成本，提供醒目訊息；不能刪除角色、突然換層或偷偷傳送。因能力而停留危險地形需依同一時間规则承擔後果。氣量／危害強度是 2D 適配參數，集中記錄與測試，不藏於 renderer。

即使主路線不要求地形能力，正式包內的效果驗證場也要有能展示其差異的水域与地面陷阱；不能把它們放進沒有對應地形的世界後聲稱保留功能。

### Gate

每一族至少有正向、反向／失敗、過期／移除測試；複合道具排除垂直項之後，不誤刪其餘特效、不保持誤導性名稱與能力描述。

## Phase 05.6｜附魔、負面條件與神器逐項收斂

### 實作

依來源 Enchanting 與 Special 各類別逐項完成，不以文件中列出的族當完整清單。典型必要處理：CastWhenUsed／Held／Strikes、AbsorbsSpells、增強技能／護甲、耐久與負重、回血／吸取、特定敌人加減傷、聲望及反應、SoulBound 等。source 以不同參數表達的限制都要實際讀取，不能只實作正面奖励。

`CastWhenHeld` 進入裝備狀態後按來源重新施加／維持，卸裝只解除該物品提供的 instance。`CastWhenStrikes` 必須在有效的來源觸發點執行；普通 miss、取消和空揮不能當成已造成傷害。上游 custom spell 分支若未完成，MVP 不宣稱支援任意 mod 的自訂 bundle；原版 classic spell 分支仍須完整。[S8]

為所有来源神器建立專屬或可重用的參數化 handler entry，至少逐件測試一次其特殊效果；參數域有多種行為的再細分。Wabbajack、Hircine Ring、Oghma Infinium、Azura's Star、Ring of Namira 等不能只保留物品圖示；按其實際來源特殊行為映射到變形、能力變動、靈魂或傷害事件等相應服務，源碼尚未確認的细節不可靠名稱猜。

對需要較大世界系統的項目，採最小實質服務：派系態度資料真的影響服務／AI；召喚實體真的佔格、行動、死亡与消失；形態轉換真的改 source-defined 能力、可用裝備與狀態；不要求同時完成全世界劇情。小型測試場可提供各類目標与環境，供所有神器驗證。

### Gate

coverage 中非垂直 pending 歸零；每件來源神器均有通過測試或明確列出的 upstream 缺口補實作，不准標成「有 mapping 即完成」。物品依賴閉包可全量解析。這是較重的工作段，允許拆成多個小 commit，但不能為趕進度跳過。

## Phase 05.7｜玩家可用性與完整驗證

### 實作

背包／裝備 UI 支援篩選、選擇数量、裝備、卸下、使用、丟棄、說明、材質／狀態顯示與快捷槽。未鑑定物品顯示未知效果，驗證場可用明示的 debug identify；一般介面不洩漏未鑑定屬性。

建立正式 build 可選的 `EffectsLab` 驗證入口：任意來源 item/effect 可產生、指定 target／environment、推進時間与查看結果。它不是正常冒險的替代，但讓沒有自然放進短篇任務的特效也有真實可操作驗證。

coverage 測試要包含 inventory use → resolver → 世界狀態的端到端鏈，而非只呼叫 handler 並檢查沒有 exception。每種效果驗證 source 成本、成功、無效目標、疊加／解除、讀檔、源物品銷毀。為傳送、反射、召喚、持續毒与關閉遊戲後重讀設定回歸案例。

### 最终 gate 與交接

`implemented source-effect closure / expected nonvertical source-effect closure = 100%`，分母由 05.1 固定與回溯，排除表另顯示。100% 是待達成門檻，不是本計畫聲稱已實測。

若來源與規劃間發現未知非垂直類型，就增加對應工作項、實作與測試後再通過；不能把它從 exporter 漏掉或改成垂直排除。純 schema registration、幾個通用例子、僅測主線掉落，均不符合本 gate。

交付 effect runtime、完整 mapping／coverage、物品 UI、可操作驗證場與測試報告，直接進 06。所有來源都可查 [00 源碼清單](00_MASTER_PLAN.zh-TW.md#10-源碼與外部依據) 的 S1/S3/S4/S6/S7/S8；新 2D 語意皆在本文件明示。
