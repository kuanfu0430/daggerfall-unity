# Daggerfall → 2D Roguelike：區塊式地圖實作準備報告

- 日期：2026-09-08。
- 審查倉庫：`kuanfu0430/daggerfall-unity`。
- 源碼基準：`035d447911c1de53d5bf10381d99942bf2ff8571`，本次提交前的 `master`。
- 文件性質：源碼調研、架構決策與開工順序；不是已完成的轉換器，也不是全遊戲移植規格。
- 範圍：地圖資料、block 重用、3D → 2D、多層空間、組裝／生成、地圖物件與任務位置的介接。戰鬥、回合制、數值平衡不在本次實作範圍。
- 驗證限制：本次已閱讀相關源碼，未載入 DOS `ARENA2` 資源、未執行 Unity 或實際地圖轉換。因此模板數量、覆蓋率、效能、全地圖可通行性仍待實測，不能把本文件當成測試通過證明。

## 1. 決策摘要

**採用 block-first 架構。使用者提出的「先做共用區塊，再組裝地圖」方向正確，而且比逐地點完整轉換更適合交給 agent 實作。**

但源碼確認了一個會改變開工順序的事實：**模組化不等於每次遊玩重新隨機生成。一般地牢的 block 名稱、座標、起始區塊旗標也已存於 `MAPS.BSA`；DFU 通常讀取這份配置，再建立場景。**小村莊不是唯一採區塊方式的室外地點，城鎮室外的載入流程也使用 RMB 配置。[S1][S2][S3]

因此，最省工的第一步不是重新發明原版生成演算法，而是：

> **原版資料讀取器 → 唯一 block／室內模板庫 → 2D 模板編譯 → 依原配置組裝 → 綁定地點資料與互動物件。**

新隨機生成器是同一套組裝器的第二種「配置供應者」，不是另一套引擎。需要固定的地圖、一般地牢、城鎮都可共用模板、渲染、連接驗證與資料綁定。

### 1.1 對原提案的判斷

| 原提案 | 判斷與調整 |
|---|---|
| 預先製作不同 block，執行時組合 | 採納。優先自動轉換原有 block，避免重新手做一套內容。 |
| 一般地牢用自己的 block 生成器 | 可行，但要明示它會改變原始配置。第一階段先做忠實組裝，第二階段再做種子生成。 |
| 只複製固定地圖的程式 | 改為保留配置資料與必要特例；固定地圖並不都各有一段專屬地圖程式，一般地牢也有固定配置。 |
| 村莊也可以用相同方式 | 採納，且可延伸到城鎮。必須額外保留建築用途、派系、名稱種子、門與室內連結。 |
| 這樣就不用處理 3D → 2D | 不成立。工作從「每個地點轉一次」縮為「每種幾何模板／變體轉一次」，但 block 內仍可能有多層空間。 |

前三列的源碼依據見 [S1][S2][S3]；建築資料與室內關係見 [S4][S5][S6]。最後一列是依資料結構與幾何投影所作的工程判斷。

### 1.2 兩種模式，保留目標不同

**`source-layout`：忠實配置模式，第一階段預設。**保留原地點、block 順序、座標、入口、任務錨點及互動關係；空間經格網離散化，但不主動重排房間或刪除高度層。

**`generated-layout`：種子生成模式，第二階段選配。**使用相同模板庫產生新配置。可保留內容類型、任務功能與機關模板，但不能宣稱原始地圖逐格不變。配置一經用於任務或存檔便固定，不能每次進門重抽。

若日後採用「一般地城重新生成、主線及指定地點忠實保留」，使用這兩個模式即可，不需要重做第一階段。村莊重排不是地牢生成器順手就能完成的功能，另有建築配置與服務綁定問題。

## 2. 源碼確認的實際結構

### 2.1 地牢：配置已在資料檔，執行期負責組裝

`MapsFile.ReadMapDItem()` 從資料中讀取 `BlockCount`，接著逐一讀取 `X`、`Z`、`BlockNumberStartIndexBitfield`，解出 block 編號、`IsStartingBlock` 與 block 類別，再組成 `.RDB` 名稱。這不是執行期重新隨機挑選所有房間。[S1]

`DaggerfallDungeon.LayoutDungeon()` 遍歷 `LocationData.Dungeon.Blocks`，呼叫 `GameObjectHelper.CreateRDBBlockGameObject()`，依下式配置區塊：[S2]

```text
blockOrigin = (block.X × RDBSide, 0, block.Z × RDBSide)
RDBSide = 2048 × MeshReader.GlobalScale
```

其中的平面 block 座標只表示組裝位置，不能解讀成 block 內沒有高度；物件與任務標記仍有三維座標。`GetPlayerBlockIndex()` 所說的平面判定，是用於辨認所屬 block，不是宣告整個地牢為單層。[S2][S7][S8]

**直接收益：**同一個 RDB 幾何模板可以編譯一次，被多個地點引用；每個地點只另外保存配置與实例狀態。

### 2.2 真正的執行期重組案例：SmallerDungeons

`MapsFile.GetLocation()` 先讀取地點，再視 `UseSmallerDungeon()` 的結果呼叫 `GenerateSmallerDungeon()`。後者對符合條件的非主線地牢，使用 `MapId` 設定 `DFRandom.Seed`，從參考地牢挑選中央 block 與四個邊界 block，覆寫配置。`GetRandomBlock()` 以名稱是否以 `B` 開頭區分邊界 block。[S9]

這個實作可重用其「配置替換入口、固定 seed、中央／邊界分工」概念，但**不是已完成的通用任意尺寸生成器**。不能直接推論所有 B block 都與所有其他 block、所有高度出口相容。

另外，`UseSmallerDungeon()` 會檢查該地點的任務 `SiteLinks`，沿用任務開始時的縮小地牢設定，理由就是 marker 配置不能在任務進行中變動。[S9]

結論：生成器可以做；先把配置生命週期、任務錨定與存檔固定下來，比先做更複雜的隨機演算法重要。

### 2.3 固定地圖不是獨立引擎

`DaggerfallDungeon.IsMainStoryDungeon()` 提供主線地牢 MapId 清單，但這只是特定程式用途的判別函式，不應被當成全遊戲所有固定場景的完整清單。[S2]

`Place.SetupFixedLocation()` 還會從任務的指定 locationId 解析固定地點，並處理 Mantellan Crux 等特例；任務也可以綁定建築。[S10]

因此保護名單應由「主線 helper＋任務固定地點參照＋已知座標／機關特例」構成。沒有出現在主線清單，不代表可以任意重排。主線地牢依然可走相同 block 編譯與組裝流程；必要的特殊處理應是少量資料覆寫或 adapter，不是每個固定地牢各寫一個 renderer。

### 2.4 城鎮與村莊：RMB 配置＋地點建築資料

`ReadMapPItem()` 讀取室外的寬高、`BlockIndex`、`BlockNumber`、`BlockCharacter`，再產生 `BlockNames`；`GetRmbBlockName()` 直接按座標查表。[S1]

真正執行期的 `StreamingWorld` 會建立 `BuildingDirectory`，取得已填入地點建築資料的 blocks，逐格建立 RMB，並設定 `CityNavigation`。這個流程明確涵蓋城市、hamlet、village 等地點，而非只有小村莊。[S3]

`DaggerfallLocation.LayoutLocation()` 也可當離線匯出的參考，但它的註解明確說明：這是 editor 的獨立配置路徑，不是 streaming world 的實際載入流程。若只照抄這個方法，容易漏掉執行期的建築資料綁定。[S11]

RMB 邊長為 `4096 × MeshReader.GlobalScale`，與 RDB 不同，不能把兩者套用同一個 block 尺寸常數。[S4][S7]

### 2.5 比前次調研更值得優先重用：CityNavigation

`CityNavigation.SetRMBData()` 已經把每個 RMB 的 `AutoMapData` 轉為 64×64 導航格網，並从 16×16 地表 tile 資料取得權重。每個導航格代表 64 個 Daggerfall 原始座標單位，配置時另有 Y 軸反轉。[S12]

這是城鎮第一版地圖底稿的現成來源，無需先對整座城市做幾何分析。

但類別註解明確限定它主要供遊走 NPC 使用：它把 automap 非零位置排除，並不是玩家能攀爬、上屋頂、游泳、通過全部細窄入口的完整規則。**可用作基礎街道遮罩與對照資料，不可直接升格為全部角色的最終碰撞真相。**需要高度、精確門口或特殊通路的部分再讀原始幾何，不能用 automap 建築輪廓去推測室內。[S12]

### 2.6 室內：RMB 子紀錄，不是按房屋外觀猜室內

`DaggerfallInterior.AssignBlockData()` 透過門的 `blockIndex` 找到 block，再用 `recordIndex` 取得 `RmbBlock.SubRecords[recordIndex].Interior`。`DoLayout()` 另外加入 models、flats、people、action doors 與 spawn points。[S5]

所以可重用的室內模板單位至少是「RMB 資料身分＋子紀錄索引＋幾何覆寫版本」，不能只用房子模型 ID，也不能只按商店類型隨便挑一個室內。

`AddModels()` 對 props、一般模型及梯子還有不同的座標／碰撞處理，並有特定錯誤模型排除邏輯。這也是優先沿用原載入語意，而不是從原始數字重新猜座標轉換的理由。[S5]

## 3. 模板與实例必須分開

這是模組化成功的核心，不需要引入複雜框架，但資料邊界不能混在一起。

### 3.1 可共用：BlockTemplate

保存可重用的靜態幾何與局部資訊：

- 多層格網／表面、地面高度、淨空、靜態阻擋與局部相鄰關係。
- 邊界候選出口的方向、局部位置、寬度、高度區間與所屬表面。
- 門、機關、容器、固定物件、出生規則、任務標記的局部定義與來源識別。
- 原始模型／貼圖參照，以及沒有被 walking 分析保留下來的必要空間資料。

模板是不可變資產；門是否已打開、怪物是否已死亡等狀態不能放在共用模板上。

### 3.2 每個地點另存：LocationManifest 與 BlockInstance

保存地點 ID、所引用模板、原始 block 順序及座標、起始旗標、地點覆寫、配置模式、配置版本與 seed。每個 BlockInstance 擁有獨立的互動狀態。

`BuildingDirectory.MakeBuildingKey()` 使用 `(layoutX << 16) + (layoutY << 8) + recordIndex`，並對結果 0 有特殊處理；它只保證單一地點內唯一。因此建築的跨地點識別必須帶上 `MapId`，不能把 buildingKey 當全域 ID。[S6]

`RMBLayout.GetLocationBuildingData()` 會把 `MAPS.BSA` 的 NameSeed、FactionId、Quality 等合併到 block，並處理 replacement data。它特別複製建築資料陣列後才修改，正好證明「共享 block 與地點实例資料分離」是既有架構的一部分。[S4]

### 3.3 任務與來源識別不可丟掉

`Place.EnumerateDungeonQuestMarkers()` 為標記保存局部位置、dungeonX、dungeonZ，以及由 `blockData.Position + obj.Position` 得到的 markerID；`CreateQuestMarker()` 再加入 questUID 與 placeSymbol。建築任務則還使用 mapId／buildingKey。[S8][S10]

新系統建議新增穩定的复合識別：

```text
templateObjectKey = (templateId, sourceRecordOrObjectOffset)
instanceObjectKey = (mapId, layoutRevision, blockInstanceId, templateObjectKey)
```

同時保留原來的 markerID、blockIndex、recordIndex、來源座標等，作為舊系統 adapter 的對照欄位。**新增唯一 ID 不等於自動取得舊存檔相容性。**第一版建立自己的版本化地圖狀態即可，不把原 DFU 存檔遷移列為前置需求。

相同模板出現兩次時，要分別綁定兩份实例與 action targets；不能因為模板相同就讓兩扇門共用開關狀態。

## 4. 3D → 2D 的最小實作架構

### 4.1 不重寫來源格式解析器

沿用 `ContentReader`、`MapsFile`、`BlocksFile` 及 DFU 模型載入流程。`ContentReader` 本來就提供 block 與 location 讀取；`MapsFile.ReadLocation()` 還會先檢查地點替換資料。[S13][S14]

第一版保留 Unity 為匯出宿主與 2D 檢視宿主，不同時進行全遊戲換引擎。幾何分析可以在獨立命令列程式完成，執行期不必反覆載入 3D 場景才能畫已編譯的地圖。

```text
DOS ARENA2 + 指定 DFU 版本 + 明確的來源設定
                      |
          SourceAdapter / CatalogExporter
                      |
       +--------------+----------------+
       |                               |
LocationManifest                 唯一模板幾何與物件資料
       |                               |
       |                      BlockCompiler
       |                  CityNavigation / Recast
       |                               |
       +--------------+----------------+
                      |
                 MapAssembler
                      |
          InstanceBinder + SeamValidator
                      |
             2D Viewer / Runtime Adapter

第二階段：SeededLayoutGenerator → 產生相同格式的 LocationManifest
```

上圖名稱是建議新增的模組責任，不是聲稱倉庫已存在這些類別。

### 4.2 各類地圖選最短路徑

| 類別 | 首選輸入 | 編譯策略 |
|---|---|---|
| 一般 RDB 地牢 | 原 block 幾何、物件、原 location 配置 | 唯一模板多層編譯，再按配置組裝。 |
| 主線／特殊 RDB | 相同來源＋特例資料 | 同一管線，強化機關與固定錨點驗證；必要時採固定範圍覆寫。 |
| RMB 城鎮／村莊室外 | AutoMapData、GroundTiles、建築／門資料 | 先用現成平面資料；高度與不符之處再以幾何補足。 |
| RMB 建築室內 | 指定子紀錄 Interior | 以子紀錄為模板多層編譯，入口按原關係綁定。 |
| 城鎮外的荒野／地形 | terrain 資料與原地理座標 | 另做地形 chunk 投影；不能宣稱 RMB/RDB 已涵蓋全世界。 |

最後一列的範圍區分可由 `StreamingWorld` 將 terrain、nature 與 location 分別載入看出。[S15]

### 4.3 Recast／DotRecast 是可用元件，不是遊戲內容轉換器

Recast 的 `rcCompactHeightfield` 保存開放空間的 spans，可進一步生成 heightfield layers。這適合將重疊走道轉成多層平面資料；不需要先生成簡化 NavMesh，再把 NavMesh 切回方格。[E1][E2]

DotRecast 提供 C# 實作及 `RcLayers.BuildHeightfieldLayers()`。但本 fork 使用 Unity 2019.4.41f2，而本次檢視的 DotRecast 專案包含 .NET Standard 2.1 與較新的 .NET targets，不能預設最新版套件可直接放進舊 Unity。[S16][E3][E4]

建議：Unity 匯出中立資料；獨立 C# 程式編譯。先做小型相容性實驗，記錄實際可用的套件版本與編譯設定，不為了這個工具先升級整個遊戲。若選原生 Recast 或可相容版本，保持相同中間格式即可。

### 4.4 2D 畫面不代表刪除高度

地圖資料採 `(x, z, surfaceId)` 加 floor／clearance／連接關係。Recast 的 layer 編號只是局部演算法結果，不是全地圖樓層編號，也不能用「A block 的 layer 1 連 B block 的 layer 1」拼接。

跨 block 連接必須比對實際世界高度、出口範圍及通行條件；畫面再把相關表面整理成可切換顯示層。斜坡、橋上／橋下、樓梯以資料連接，不用人手逐張地圖決定層號。

walking 分析也不是攀爬、浮空、水下移動或墜落的完整資料。編譯器必須保留原始碰撞／高度區間與動作語意；特殊移動可以暫時交由原 3D 查詢 adapter 協助，但不能先丟掉資訊，再聲稱完整保留機制。

### 4.5 不把地城變成粗糙的 32×32 格就算完成

若直接套用 CityNavigation 的 64 DF units／格到 2048 DF units 的 RDB，平面上只剩 32×32 格。這是尺寸推導，不是經驗證的適當地牢解析度。[S7][S12]

幾何取樣解析度與玩家操作格子尺度要分開。P1 可以比較能整除 block 邊長的候選解析度，例如 64／32／16 DF units，再選擇通過窄門、斜坡、階梯與接縫測試的最粗設定；垂直解析度另外校準。這些數字是實驗候選，不是最終遊戲尺度。

共同格網原點、軸向、比例必須統一。初期可以整批重編譯來簡化流程；不急著做複雜的自適應格網或跨解析度尋路框架。

### 4.6 block 快取的接縫陷阱

不能把每個 block 當作四周永久封閉的孤島來處理。可行走區域 erosion、地形越界或缺少鄰居，都可能讓逐 block 編譯的邊界不同於整張地圖編譯結果。Recast 的 `borderSize` 也是明確的建構參數，不是可隨意忽略的 padding。[E5]

建議先快取模板的幾何／原始 spans 與內部分析，組裝時對窄幅接縫重新取樣驗證；需要鄰居上下文的結果，以「兩側模板、變換、設定」快取。若單側模板無法正確表達特殊接縫，可提升為局部 superblock 編譯，不因此重做全部地點。

對照測試使用同一組相鄰 blocks 的一次性聯合編譯，檢查模板化後有沒有新增或丟失連接。這只用於參考樣本與例外，不回到每個地點全量重複轉換的架構。

## 5. 必須沿用的語意與修正

### 5.1 門、機關與水面不是靜態貼圖

`RDBLayout` 已把 action doors、action links、editor flats 與固定／隨機寶藏分開處理。`DaggerfallDungeon` 另外讀取水位與 castle block 資訊、加入水，並在組裝後處理重疊門。[S7][S2]

實作時：

- 門保存初始狀態、鎖定條件及连接；不能因匯出時關著就變成永久牆。
- 機關保存原 action 類型、參數、target／next 關係與移動資訊；不能只把可見物件匯成 sprite。
- 移動平台／移動牆及傳送點保留狀態與有向連接；未支援的 handler 要被明確列出，不能靜默刪除。
- 水位及特殊移動能力另存，不讓 walking 格網把相關內容當成不可用垃圾清掉。

這些是按類型寫一次的規則；一般不應按地圖逐次請 LLM 作主觀解讀。

### 5.2 原版與 DFU 修正要作為明確來源 profile

已確認的例子包括：

- `ReadMapDItem()` 對 Orsinium 的特定 border block 座標修正。[S1]
- `RemoveOverlappingDoors()` 對組裝後重疊門的處理。[S2]
- `DaggerfallInterior.IsBadInteriorModel()` 對會堵住階梯的模型排除。[S5]
- `GetLocationBuildingData()` 對建築 replacement 與特定公會資料的處理。[S4]

第一版預設目標是「此 fork 的 DFU 行為＋提供的原版資源＋內建修正」，不是重新製造所有 DOS 原始錯誤。外部 mods 預設不混入第一輪，但保留來源 profile 與覆寫擴充點；不承諾任意 3D mod 自動相容。

所有模板快取鍵應包含實際幾何來源摘要、必要覆寫、編譯器版本與取樣設定。純氣候／季節貼圖變化盡量作為材質參數，不因換色重跑相同幾何。地點專屬幾何變化則必須形成獨立變體，不能只用檔名作快取鍵。

### 5.3 匯出必須隔離執行期狀態

`MapsFile.GetLocation()` 可能被 SmallerDungeons 與任務狀態影響；`DaggerfallDungeon.LayoutDungeon()` 的呼叫也帶入玩家等級與 `DateTime.Now.Ticks` 作為怪物相關輸入。[S9][S2]

因此，批次匯出應在隔離的匯出環境設定明確的來源模式，禁用動態世界變動、記錄 RNG／設定，不使用當下玩家存檔。單靠 `importEnemies=false` 不能推論所有隨機寶物、機關副作用或世界事件都已停用；應明確分離幾何捕捉與物件生成定義。

API 名稱像 reader，不代表本 fork 中的類別已經是無 Unity、無 QuestMachine 相依的純函式。第一版不要急著把整套讀取器直接搬成獨立 .NET 程式；先在原環境匯出，再把純幾何分析移出去。[S9][S13]

## 6. 新地牢生成器：可做，但放在正確位置

### 6.1 最小演算法，不先引入 WFC 或通用關卡框架

生成器只負責輸出 manifest，不負責畫圖、重新製作怪物或執行機關。第一版可以使用固定 seed 的受限隨機選擇與回溯：

1. 從已驗證的 block 集合選入口；初期優先同一原始地牢／已觀測相鄰群，降低不相容組合。
2. 按尚未封閉的出口選候選 block，比對方向、範圍、世界高度、淨空與可通行模式。
3. 依目標規模擴展並檢查拼接碰撞；使用相容的邊界 block 或明確封口資料完成配置。
4. 驗證入口、必需機關、任務 marker 類型與必要區域；不合格時用同一 seed 下的固定嘗試序列回溯。
5. 凍結 manifest 與版本後，才做任務／怪物／物品綁定。

這些是建議實作，不是原 DFU 已具備的通用生成流程。`GenerateSmallerDungeon()` 僅作為已有配置替換模式的參考。[S9]

重試應有預算；失敗輸出 seed、原因、候選集合。測試／除錯時保留失敗結果；正式遊戲可在分配任務前明確選用原配置 fallback，但要保存實際採用模式，不能讓 fallback 掩蓋生成器失敗率。

### 6.2 不預設每個 block 都能旋轉、鏡射

目前確認的原始 RDB location 組裝路徑是按 X/Z 平移，不是任意旋轉模板。[S2]

新生成器第一版維持原方向。旋轉或鏡射需同步變換出口、物件、機關運動、傳送朝向與 marker，並通過測試；不能只轉換圖像。只有在確實需要增加組合多樣性時才加入。

### 6.3 固定場景與任務不是後補

固定地點先保留原 manifest。一般地牢生成時也必須先建立完整配置，再讓任務選 marker。若沿用 DFU 的任務系統，`MapsFile` 地點查詢、`Place` marker 列舉、場景組裝與保存資料必須看到同一份「有效配置」。只有 renderer 使用新配置，而 `Place` 仍讀舊的 `Dungeon.Blocks`，會把任務放到不存在的位置。[S8][S9][S10]

已在進行的任務、已保存地圖的探索與門狀態，不能被「進入時重新生成」覆寫。存檔要保存 manifest 本身或足以精確重建它的版本化資料；只有 seed 而沒有演算法／模板版本不足以保證重現。

### 6.4 村莊生成另列下一步

忠實組裝現有村莊，直接重用 RMB 清單與建築資料。若重新排列或替換村莊 RMB，會改變 buildingKey、建築順序及可用服務；原 `GetLocationBuildingData()` 是把來源資料按建築類型與遍歷順序配對，不能把原資料不加處理地塞進不同結構的村莊。[S4][S6]

新村莊生成器應先形成「建築服務與實體位置的配置結果」，再綁定 NameSeed／FactionId／Quality、門與室內、任務資格。第一個生成原型先做地牢，不把這個額外問題混進同一個最小版本。

### 6.5 重新手做 2D block 的使用邊界

可以針對難轉換的 block 寫人工或規則化的 2D 替代模板，但它應保留入口／出口、重要 marker、機關關係與內容對照。

只保留幾個通道出口，將內部重畫成不同房間，屬於重新設計關卡，不是忠實投影。它可以是 generated-layout 的合法內容，也可以是經明示接受的特例；不可把這條捷徑默默套到所有原版地圖，卻仍宣稱原地圖完整保留。

## 7. 建議的資料契約

以下是最小責任劃分，不要求先建資料庫、雲端服務或大型 ECS。原型採版本化 JSON manifest，加可替換的格網二進位／壓縮資料即可。

| 資料 | 最少需要保存 |
|---|---|
| `SourceProfile` | 源碼 commit、資源摘要、內建／外部覆寫、SmallerDungeons 狀態、座標與取樣規則、compilerVersion。 |
| `BlockTemplate` | templateId、RMB/RDB/interior 類別、来源檔案／子紀錄、尺寸、surfaces、局部連接、候選 ports、objects、markers、action graph。 |
| `LocationManifest` | mapId、region/location index、原始 key 與顯示文字分離、mode、layoutRevision、seed、instances、地點覆寫、入口與建築資料。 |
| `BlockInstance` | instanceId、templateId、原始順序與座標、變換、starting flag、來源 instance 對照。 |
| `InstanceState` | 門／機關／容器／實體狀態、探索狀態、已綁定任務位置；不回寫模板。 |

port 是幾何候選連接，不等於世界中必定存在的通路。assembler 需要將它們與鄰居上下文及動態條件組合後才確定邊。

原始非在地化 RegionName 在 DFU 中仍被用作 key；顯示時才使用翻譯。此 fork 的正體中文內容不應被直接用作資產或地圖識別鍵。[S14]

## 8. 圖形呈現的開工順序

先完成簡單圖塊檢視器：牆、地板、門、表面切換、物件／marker 圖示與跨 block 邊界。每個格子可查看來源 block、物件與世界高度，讓錯誤可追查。

接著重用原 flats／貼圖，對 3D props 批次烘焙 sprites；需要更忠實視覺时，按顯示層烘焙背景。靜態背景與可互動物件必須分離，不能把門、寶箱或整個活動機關永久畫進背景。

原生 Automap 的裁切／相機能力可作預覽與烘焙參考，但不能只匯出已探索部分，也不能把一張截圖當通行資料。[S17]

Tiled 可作可選的檢視／交換格式，不是前置依賴；第一個 viewer 能直接讀中間格式即可。不要為了漂亮的最初展示，先做完整美術管線或讓 LLM 逐張重畫。

## 9. 開工階段與可交付成果

### P0：建立可重現的盤點與來源基準

**工作：**建立獨立匯出入口與 source profile；遍歷 region/location，輸出原始配置與已使用 block、室內子紀錄、門／marker／action 的清單，辨認固定地點參照與特殊修正。另列未被一般 location 引用但存在於來源中的模板，避免把「未引用」誤當「不存在」。

**產物：**`catalog.json`、location manifests、`coverage.json`、失敗清單與來源摘要。這些檔名是規劃，不是本次已產出的資料。

**驗收：**能重跑；成功、失敗、未支援必須分開計數；原配置模式不受當前玩家任務／RNG 影響；保留已知來源特例。所有規模與工時評估都以這一步的實測盤點為起點。

### P1：唯一模板編譯的垂直原型

**工作：**選取有代表性的 RDB、RMB 室外及一個多層室內；建立中立幾何匯出與 compiler，先重用 CityNavigation。RDB／室內測試 multi-span／layer 流程，輸出來源物件與 marker 對照。

**產物：**可視化 2D 模板、穩定格網資料、解析度比較、未支援 action 報表。

**驗收：**上下重疊通道不誤接、窄門不被吞掉、樓梯／斜坡有連接、門能區分開關、不同來源物件不被合併丟失。

### P2：原配置組裝與实例綁定

**工作：**依原 manifest 組裝同模板的多份实例，接入建築資料、室內轉場與 marker 對照；處理接縫、重疊門及特殊修正。

**產物：**可連續操作的 2D 地圖 viewer；至少包括一個一般地牢、一個有特殊機關的固定地點、一個村莊和一個多層室內。可優先用 Privateer's Hold 做具名回歸樣本，但不能只靠它代表所有地牢。[S2]

**驗收：**同模板实例狀態互不污染；門能對應正確室內並返回；任務 marker 可解析到正确实例與表面；聯合編譯與模板拼接的邊界連接一致。

### P3：批次覆蓋與內容相容性收斂

**工作：**遍歷全部已盤點來源，按共同錯誤類型修正 compiler／adapter；必要時使用小範圍的 override 或 superblock，不逐地點硬改。

**產物：**模板與地點覆蓋表、特例登錄、實測耗時／快取大小、可重現的失敗測試樣本。

**驗收：**每個來源物件都有去向；所有失敗可定位；地圖關聯、固定 marker 與已實作互動通過測試。未完成的特殊移動或 action 不得被標成全內容完成。

### P4：種子式地牢配置生成

**工作：**使用相同模板庫、manifest 與 assembler，加入最小的受限生成／回溯；統一有效配置的讀取入口，完成任務分配前的凍結與保存。

**產物：**可重現的 generated-layout、測試 seed 集合、生成失敗統計、與原配置模式共用的保存格式。

**驗收：**相同輸入得到相同配置；生成不碰受保護固定地點；新任務從新配置選 marker；讀檔不因套件更新或重新進場改圖。有限 seed 測試是回歸證據，不宣稱已證明所有 seed 永遠正確。

村莊重新生成與完整荒野投影，另在前述資料契約上增量實作，不作 P1 的阻塞條件，也不將它們從全遊戲目標中默默刪除。

## 10. 自動化驗收：讓 agent 修規則，不讓它憑感覺改地圖

| 測試面向 | 必要檢查 |
|---|---|
| 來源對帳 | location/block/室內/互動物件/marker 的輸入、輸出及排除理由可對應；不靜默漏項。 |
| 幾何與座標 | 軸向、RMB/RDB 比例、子紀錄旋轉、邊界原點正確；重疊層不相互穿越。 |
| 通行 | 在明確角色尺寸、能力與機關狀態下，比對重要錨點及出口的可達關係；也檢查新增的錯誤捷徑。 |
| 接縫 | 與一次性聯合幾何分析比對；跨層出口按高度連接，不按局部 layer 編號。 |
| 互動 | 開門／关門、開關、平台、傳送等有向或有條件邊按規則變動；至少覆蓋已支援的 handler。 |
| 任務與室內 | mapId/buildingKey/block instance/marker 對照正確；生成配置與任務列舉看到同一資料。 |
| 重用隔離 | 複製同一模板後，開 A 的門不改 B；同一地點重載保留狀態，其他地點不受影響。 |
| 重現與快取 | 相同來源、版本、設定與 seed 的標準化輸出一致；來源或幾何覆寫改變能正確失效。 |

通行測試不能把「全部點都可從入口步行到達」當唯一成功條件。原本就需要鑰匙、機關、傳送或特殊能力的區域，要在相應條件下驗證；原本隔離或錯誤的區域要依來源 profile 記錄，不能自動挖通牆壁讓測試變綠。

驗證 oracle 優先使用已確定來源行為、原碰撞查詢及對照樣本；沒有獨立真值時只能標記「內部一致性通過」，不能聲稱與原遊戲完全等價。

建議 CI 分兩層：無原版資源時跑合成幾何、schema、拼接與实例隔離測試；有合法本機資源的環境再跑真實地圖整合測試。報告與程式可進 Git，原版資源及大量生成快取不要混進本次文件提交。DFU 本來就要求另外提供 DOS Daggerfall 資產。[S18]

## 11. Agent 任務拆分與最小專案配置

先依 P0 → P1 → P2 線性實作，資料格式穩定後才平行處理模板類型。避免不同 agent 同時建立彼此不相容的世界座標、ID 或生成規則。

建議責任只有四組：來源匯出、模板編譯、配置／实例綁定、驗證／viewer。每個任務附一個可重現的輸入與預期測試結果；不要求 agent 先撰寫更多層抽象規格。

可採用下列增量目錄，名稱可依實作調整；本次只新增本報告：

```text
docs/roguelike/                         決策與驗證說明
Assets/Editor/RoguelikeExport/           原 Unity 環境的匯出入口
Assets/Scripts/Roguelike/                2D viewer 與最小 runtime adapter
Tools/BlockCompiler/                    視相容性需要建立的獨立編譯程式
Tests/Roguelike/                         合成／整合測試與小型測試資料
```

不先導入資料庫、微服務、向量檢索、LLM 執行期生成、全新通用地圖引擎，也不先重構全部 DFU 類別。除必要的來源 adapter 接點外，保留原 3D 路徑可作比較；使用獨立測試場景，避免影響現有翻譯 fork 的正常遊玩。

## 12. 工作量如何縮小，以及仍未解決什麼

設地點數為 N，實際使用的唯一幾何模板／變體數為 K。逐地點重建會重複處理相同模板；本方案把昂貴幾何工作集中到 K，另外保留 N 份較輕量的配置／綁定資料，以及必要的接縫和特例工作。

**這是結構性的減工，不是已量測的節省百分比。**K 必須包含室內子紀錄、幾何 replacement 與依上下文形成的變體，不能只數不同 `.RDB` 檔名就估算全部工期。各種機關、特殊移動與固定場景的驗證也不會因快取自動消失。

未解決、必須在原型回答的問題包括：合適格子尺度、複雜斜坡／重疊空間的顯示層策略、逐 block 接縫與原碰撞行為差異、需特殊 handler 的 action 類型、實際唯一模板數與失敗分布，以及轉換耗時／產物大小。

**開工結論：可以採用，且值得優先做。第一個實作目標應是「區塊目錄匯出器＋最小 2D 組裝原型」，不是「完整隨機世界生成器」。**先證明原模板可重用、原配置可重現、任務／門／高度資訊不丟，再加入新配置生成。這同時保留忠實移植與新 roguelike 地圖設計兩條路，不需重複造輪子。

## 13. 源碼與元件依據

以下倉庫源碼連結均固定到本次審查 commit；外部元件連結為本次調研參考，實作時應記錄選用版本。

| 編號 | 已閱讀的來源與用途 |
|---|---|
| [S1] | `API/MapsFile.cs`：ReadMapPItem、ReadMapDItem、配置解碼及 Orsinium 修正。 |
| [S2] | `Internal/DaggerfallDungeon.cs`：主線判別、LayoutDungeon、位置、隨機輸入、水位及門去重。 |
| [S3] | `Terrain/StreamingWorld.cs`：執行期地點、BuildingDirectory、RMB 組裝及 CityNavigation。 |
| [S4] | `Utility/RMBLayout.cs`：尺寸、建築 key、GetBuildingData／GetLocationBuildingData 及覆寫。 |
| [S5] | `Internal/DaggerfallInterior.cs`：室內子紀錄、模型配置、梯子與錯誤模型修正。 |
| [S6] | `Game/BuildingDirectory.cs`：地點建築資料與 buildingKey 的唯一性範圍。 |
| [S7] | `Utility/RDBLayout.cs`：RDB 尺寸、action doors、flats、標記及寶物。 |
| [S8] | `Game/Questing/Place.cs`：CreateQuestMarker、室內與地牢 marker 列舉。 |
| [S9] | `API/MapsFile.cs`：GetLocation、UseSmallerDungeon、GenerateSmallerDungeon／GetRandomBlock。 |
| [S10] | `Game/Questing/Place.cs`：隨機選的是任務地點，固定地點另有解析與特例。 |
| [S11] | `Internal/DaggerfallLocation.cs`：editor 專用的獨立室外組裝路徑。 |
| [S12] | `Game/Utility/CityNavigation.cs`：64×64 RMB 導航遮罩與用途限制。 |
| [S13] | `Utility/ContentReader.cs`：既有 block／location 讀取介面與相依。 |
| [S14] | `API/MapsFile.cs`：替換資料、來源 key 與地點讀取路徑。 |
| [S15] | `Terrain/StreamingWorld.cs`：terrain、nature 與 location 的分離。 |
| [S16] | `ProjectSettings/ProjectVersion.txt`：本 fork 的 Unity 版本。 |
| [S17] | `Game/Automap.cs`：地圖幾何、探索、裁切與顯示用途。 |
| [S18] | `README.md`：DOS 遊戲資產需求與此 fork 的用途。 |
| [E1] | Recast：compact heightfield 資料結構。 |
| [E2] | Recast：heightfield layers 與建構函式。 |
| [E3] | DotRecast：C# 分層實作。 |
| [E4] | DotRecast：目前檢視到的 framework targets。 |
| [E5] | Recast：格網尺寸、垂直解析度與 borderSize 的定義。 |

[S1]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/API/MapsFile.cs#L1100-L1356
[S2]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Internal/DaggerfallDungeon.cs
[S3]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Terrain/StreamingWorld.cs#L720-L860
[S4]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Utility/RMBLayout.cs
[S5]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Internal/DaggerfallInterior.cs#L1-L570
[S6]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Game/BuildingDirectory.cs
[S7]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Utility/RDBLayout.cs#L1-L430
[S8]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Game/Questing/Place.cs#L1420-L1580
[S9]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/API/MapsFile.cs
[S10]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Game/Questing/Place.cs#L780-L1050
[S11]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Internal/DaggerfallLocation.cs#L390-L500
[S12]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Game/Utility/CityNavigation.cs#L1-L260
[S13]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Utility/ContentReader.cs#L1-L320
[S14]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/API/MapsFile.cs#L955-L1085
[S15]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Terrain/StreamingWorld.cs#L1080-L1300
[S16]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/ProjectSettings/ProjectVersion.txt
[S17]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/Assets/Scripts/Game/Automap.cs
[S18]: https://github.com/kuanfu0430/daggerfall-unity/blob/035d447911c1de53d5bf10381d99942bf2ff8571/README.md
[E1]: https://recastnav.com/structrcCompactHeightfield.html
[E2]: https://recastnav.com/RecastLayers_8cpp
[E3]: https://github.com/ikpil/DotRecast/blob/main/src/DotRecast.Recast/RcLayers.cs
[E4]: https://github.com/ikpil/DotRecast/blob/main/src/DotRecast.Recast/DotRecast.Recast.csproj
[E5]: https://recastnav.com/structrcConfig.html
