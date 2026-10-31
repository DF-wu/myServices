# ChatStack PostgreSQL／向量引擎升級研究

研究讀取日：**2026-10-31（Asia/Taipei，依本機環境日期）**。本研究僅讀取官方網頁與公開原始碼，未連線生產資料庫、拉取／重建映像、升級服務或執行下列示範 SQL。專案中僅新增本檔；其他代理的盤點與檔案不在本研究修改範圍。

已知現況僅為 **`pgvector/pgvector:pg17` 正在運行**。這不是 PostgreSQL minor 或資料庫內 `vector` extension 的精確版本；實際 `server_version`、`extversion`、image digest、掛載與索引由父代理盤點。本檔所有「目標版」均不表示現場已安裝，也不表示准許升級。

## 1. 結論與建議順序

1. **預設保留 PostgreSQL + pgvector。** 先完成實際版本、資料量、索引、備份還原時間及查詢需求盤點。若落後，優先規劃同 PG17 major 的修補，以及 pgvector 的修補；不要為取得 pgvector 0.8 iterative scan 而誤認必須先升 PG18。官方本次列出的版本是 PostgreSQL **17.11** 與 pgvector **0.8.7**。[P1][P2][V1][V2]
2. **PG18 是可規劃的正式 major 升級，非迫切的向量加速開關。** 正式最新版為 **18.6**；新增 AIO、B-tree skip scan、`pg_upgrade` 統計資料保留等，但沒有官方證據可直接換算成 ChatStack 的 HNSW／RAG 效能增幅。PG17 的官方 EOL 是 2029-11-08，毋須因 EOL 緊迫而立刻跨 major。[P1][P3]
3. **本次不建議 PG19 生產升級。** 官方首頁與 2026-10-15 公告讀到的是 **19 RC 1**；公告中的 2026-11-19 是「計畫 GA 日期」，不是已發布證明。不能用通常每年發布一次或已存在 `/docs/19/` 推論 19 已正式。[P2][P4]
4. **若真實工作負載證明 pgvector 不達標，先評估同 PostgreSQL 的索引擴充，再考慮外部向量服務。** pgvectorscale 與 VectorChord 都保留 pgvector 型別與 PostgreSQL SQL／交易框架，整體遷移面小於換成獨立 API；但自訂索引、二進位 extension、版本矩陣與還原仍要測。兩者沒有本次 ChatStack 實測結果，不排名速度。[A1][A2][A3][A4]
5. **Qdrant／Milvus／Weaviate／OpenSearch 應首先視為 vector/search sidecar。** 保留 PostgreSQL 作為關聯式權威資料來源；另建可重建的搜尋投影。把這些服務拿來整體替代 PostgreSQL，會把「升級資料庫」擴大成應用資料層重寫；本任務沒有證據證明 ChatStack 已支援任一方案。

以上是研究建議，後續是否採行取決於父代理盤點與離線／測試環境演練結果。

## 2. 時間、證據與重現方法

- 所有 web 研究只使用 **smart-search CLI**，依父代理已確認的 `doctor: ok:true, degraded:false` 工作。未使用 native web、直接 HTTP、第三方文章或模型搜尋答案來替代原頁證據。
- 官方文件與官方 GitHub repository／release API 算 primary sources；產品自述的效能與價格倍率不等於獨立證據，本報告不將它們用作推薦依據。
- 來源代號連到完整 URL；末尾來源表逐條列出讀取日期。`master`／`main`／`latest` 是可變內容，本報告另讀取固定 tag 的 pgvector README／CI 及 pgvectorscale Cargo manifest，避免把開發分支狀態當成已發行版。
- 暫存原頁證據位於 `/tmp/pg-research-*.md`，搜尋探索位於 `/tmp/pg-research-vchord-search.json`；這些不是受版本控制的永久證據，清理後需按來源表重新擷取。核心重現命令如下（此處僅文件記錄）：

```sh
rtk proxy smart-search fetch https://www.postgresql.org/support/versioning/ --format markdown --output /tmp/pg-research-versioning.md
rtk proxy smart-search fetch https://www.postgresql.org/ --format markdown --output /tmp/pg-research-pg-home.md
rtk proxy smart-search fetch https://raw.githubusercontent.com/pgvector/pgvector/master/CHANGELOG.md --format markdown --output /tmp/pg-research-vec-changelog.md
rtk proxy smart-search fetch https://raw.githubusercontent.com/pgvector/pgvector/v0.8.7/README.md --format markdown --output /tmp/pg-research-vec-tag-readme.md
rtk proxy smart-search fetch https://hub.docker.com/_/postgres --format markdown --output /tmp/pg-research-docker.md
rtk proxy smart-search fetch https://api.github.com/repos/timescale/pgvectorscale/releases/latest --format markdown --output /tmp/pg-research-scale-api.md
rtk proxy smart-search fetch https://api.github.com/repos/tensorchord/VectorChord/releases/latest --format markdown --output /tmp/pg-research-vchord-api.md
rtk proxy smart-search exa-search 'site:docs.vectorchord.ai vectorchord upgrade extension vchord' --num-results 3 --include-domains docs.vectorchord.ai --format json --output /tmp/pg-research-vchord-search.json
```

`fetch` 的成功退出碼不代表內容必然可用：例如試讀 VectorChord `/vectorchord/admin/upgrading.html` 得到的是 404 HTML；本報告沒有拿這頁證明任何升級行為。GitHub HTML 有時會缺年份、動態資產清單或顯示載入錯誤，因此另讀官方 API 的 `published_at`、`prerelease` 與 assets。

### 本次實際發現的日期／來源落差

| 現象 | 實際讀到的內容 | 本報告如何處理 |
| --- | --- | --- |
| PG19 日曆直覺可能誤導 | 官網仍標 19 RC 1；GA 計畫日期是 2026-11-19，晚於本機日。[P2][P4] | 不稱 19 正式版，不假定計畫一定實現。 |
| PostgreSQL minor 不能以算術補齊 | 18.6 notes 明示 18.5 因 wrap 後發現 regression 而未發布。[P5] | 使用官網 18.6／17.11 等原值，不自行推算 minor。 |
| pgvector Releases 與 tags 不同 | Releases 頁說沒有 releases；tags、README 與 changelog 有 v0.8.7，2026-10-01。[V1][V2][V3][V4] | 報告「最新發布 tag／changelog 版本 0.8.7」，不是「沒有新版」。 |
| pgvector CI 出現更高 PG 數字 | v0.8.7 CI 包含 PG13–20，master CI 亦有 19／20。[V5][V6] | CI 設定不是 upstream PostgreSQL GA 證明，也不是已驗證本機相容性證書。PG13–18 有明確 README／映像基礎；19／20不作生產推薦。 |
| pgvector 歷史日期小差異 | changelog 的 0.8.3 為 2026-06-17，tags 頁顯示 Jun 18, 2026。[V1][V2] | 保留兩者差異，不用其中之一推翻最新 0.8.7；可能是 tag／commit 與作者記錄時間不同，本次未證實原因。 |
| VectorChord 文件未同步 | 主 README／安裝頁為 1.1.1；被連結的 suite matrix 還標 `20250929 (latest)`、vchord 0.5.3、vector 0.8.1。[A1][A5][A6] | 套件 tag、單 extension 映像與 suite 版本不能混用。針對選定映像另驗證，不從該表宣稱最新完整組合。 |
| VectorChord repo 搬移 | `tensorchord/VectorChord` 網頁／API 回應導向 `supervc-stack/VectorChord`；latest API 仍為 1.1.1，published_at 2026-02-28。[A1][A7] | 同時記舊請求 URL 與新官方 release URL；不將舊 namespace 等同停止維護。 |
| pgvectorscale 開發版與 release | `main` manifest 為 0.9.2-dev；latest release API 為 0.9.1，2026-09-04。[A3][A8][A9] | 以 0.9.1 作已發行候選，不建議直接追 main。 |
| MySQL 舊 URL 跳版 | 請求 `/refman/9.4/en/vector.html`，頁面實際呈現 MySQL **9.7**，選單另列 26.10／26.7。[D1] | 下述 MySQL 功能依「實際呈現的 9.7 文件」描述；不據此宣稱各 MySQL 版本都支援，更不推定新選單項已 GA。 |

本次核心 PG 支援表、首頁、17.11／18.6 notes 的版本彼此一致，且其發布日期不晚於環境日。未以機器時鐘去改寫文件內容；若父代理讀到另一時間切面的官方頁面，應保存雙方內容、重新擷取關鍵頁與 registry metadata 後才定版。

## 3. PostgreSQL 正式版本與支援期限

官方政策：major 約每年一次、每個 major 支援約五年；minor 至少每季發布，必要時可臨時發布。官方建議使用所屬 major 的最新 minor。minor 不需 dump/restore；major 不可直接重用舊資料目錄，須使用正式遷移方法。[P1]

**本次官方首頁與 versioning 表共同列出的最新正式 major 是 18。** 下表是來源值，不是由本機日期外推的預測：[P1][P2]

| PG 分支 | 本次查到最新 minor | 首次正式發布 | 官方 Final Release／EOL | 2026-10-31 決策含義 |
| --- | --- | --- | --- | --- |
| 18 | **18.6** | 2025-09-25 | 2030-11-14 | 最新正式 major；可作新目標。 |
| 17 | **17.11** | 2024-09-26 | 2029-11-08 | 現場 major 仍受支援；可先作低變動維護。 |
| 16 | **16.15** | 2023-09-14 | 2028-11-09 | 受支援，但不應從17降至16。 |
| 15 | **15.19** | 2022-10-13 | 2027-11-11 | 受支援，但較短剩餘支援期。 |
| 14 | **14.24** | 2021-09-30 | **2026-11-12** | 官網仍標支援；即將到官方 EOL，不適合作新遷移目標。 |
| 13 | 13.23 | 2020-09-24 | 2025-11-13 | 已不支援；pgvector 可以編譯不等於 PostgreSQL 仍受支援。 |
| 12 | 12.22 | 2019-10-03 | 2024-11-21 | 已不支援。 |
| 11 | 11.22 | 2018-10-18 | 2023-11-09 | 已不支援。 |
| 10 | 10.23 | 2017-10-05 | 2022-11-10 | 已不支援。 |
| 9.6 | 9.6.24 | 2016-09-29 | 2021-11-11 | 已不支援；更老分支亦全部 EOL，完整歷史見官方表。 |
| 19 | **非正式：19 RC 1** | 尚未由本次來源證實 GA | 不套用未正式分支 EOL | 不作本次生產目標；官方僅公告計畫。 |

首頁標 18.6、17.11、16.15、15.19、14.24 均為 **2026-08-13** 更新。已另讀 18.6 與17.11完整 notes；16／15／14 的最新值來自官網支援表與首頁，未逐一審閱其所有 minor 變更。[P2][P5][P6]

即使是同 major 修補也須閱讀從現場版到目標版之間的 notes。17.11／18.6 notes 特別提到安全性設定／資料清理、特定 extension 的 reindex，以及更舊 minor 的額外說明；其中新增 logical decoding output plugin allowlist `output_plugin_libraries`，非內建 plugin 可能須明確加入。不能把「minor 不需重建資料庫」理解為「沒有操作後置條件」。[P5][P6]

## 4. pgvector：版本、相容性與升級邊界

### 4.1 最新版本與 PG 矩陣

最新發布 tag／changelog：**v0.8.7，2026-10-01**，tag commit `f37c13f68b57d2c3472b2214fbcff699d6d34876`。0.8.7 修正 IVFFlat index build buffer overflow 與空集合 `avg`；0.8.3／0.8.4 包含 HNSW vacuum 相關損毀／錯誤修補，0.8.2 有 parallel HNSW build buffer overflow 修補。是否現場受影響須依其實際版本、索引與使用方式判定，不能只看容器標籤。[V1][V2]

| 組合 | 官方證據 | 解讀 |
| --- | --- | --- |
| pgvector 0.8.x + PG13–18 | README 支援 PG13+，0.8.7 README 列 PG13–18 的映像 tags，v0.8.7 CI 覆蓋這些 major。[V3][V5] | PG17與18都是合理候選；PG13雖 extension 支援，upstream 已 EOL。 |
| pgvector + PG18 | 0.8.1 changelog 明列加入 PG18 rc1 支援，後續0.8.3另修PG18特定距離效能 regression。[V2] | PG18應使用現行修補版 extension，不回用早期0.8.0套件。 |
| pgvector + PG12 | 0.8.0已移除PG12支援。[V2] | 不能將「舊版曾支援」套到0.8.x。 |
| PG19／20 | CI配置存在，但README正式映像清單到PG18；PG19本身仍RC。[V3][V5][P4] | 不把CI列項當成GA／映像可用／ChatStack已相容的保證。 |

官方映像標籤包含 `pg17`、`0.8.7-pg17`、`pg18`、`0.8.7-pg18` 以及 bookworm／trixie 變體。**`0.8.7-pg17` 固定了 extension tag 與 PG major，仍不固定 PG minor、base image 或重建結果；可重現部署仍應記錄／固定 digest。** 本次未拉映像或核對 manifest，實際可用 tag、CPU architecture、裡面的 PG minor 由父代理另證。[V3]

### 4.2 extension 更新與 PostgreSQL major 更新是兩件事

官方 pgvector 升級步驟是先用原安裝方法安裝新 extension 檔案，再於**每一個使用該 extension 的 database** 更新 SQL objects。以下只是文件示意，未執行：[V3]

```sql
-- 查詢應由父代理依唯讀盤點授權執行；此研究未執行。
SELECT extversion FROM pg_extension WHERE extname = 'vector';

-- 後續變更示例，不是本次執行項目。
ALTER EXTENSION vector UPDATE TO '0.8.7';
```

換容器可更新磁碟上的 shared library／extension scripts，卻不能據此聲稱各 database 的 extension catalog 已更新；反之，只執行 `ALTER EXTENSION` 而沒有正確 PG major 編譯的 library 也不成立。跨 PG17→18時，需新舊PG binary與extension相容檔案；`pg_upgrade` 不可能全面驗證第三方模組二進位相容性。先在演練環境將 extension 版本對齊，再將 major 遷移作為獨立變更，較容易定位問題。[V3][P7]

本次沒有找到要求「所有0.8.x升級一律重建全部ANN索引」的通則；也不能反過來假定更新套件會修復已存在損毀。若舊版處於HNSW vacuum或其他已知bug影響範圍，應檢查對應issue／release notes、對備份副本作驗證並安排必要索引重建。向量原始資料與索引是不同復原層次。[V2]

### 4.3 0.8 iterative scan 直接改善什麼

ANN查詢常先掃向量索引，才套 `WHERE` 過濾；租戶、知識庫、文件ACL、狀態過濾愈嚴，愈可能 `LIMIT k` 卻不足k筆。官方以10%匹配、HNSW預設 `ef_search=40` 說明平均只剩約4筆，這是機制示例，不是ChatStack實測。[V3]

0.8.0起可選 iterative scan，掃描到有足夠結果或達預算上限。**它不是開啟後保證 exact recall，也不保證永遠滿k筆，更不取代資料庫ACL。**[V2][V3]

| 索引／設定 | 官方行為與用途 |
| --- | --- |
| `hnsw.iterative_scan = strict_order` | 掃描結果依距離嚴格排序；仍為ANN。適合作為需穩定距離順序查詢的初始實驗。 |
| `hnsw.iterative_scan = relaxed_order` | 允許局部順序放寬，官方指出可改善recall；對外需再排候選集合。 |
| `ivfflat.iterative_scan = relaxed_order` | IVFFlat使用relaxed，不能照抄HNSW strict設定。 |
| `hnsw.max_scan_tuples` | 預設20,000、近似上限，不影響initial scan；提高會增加工作量。 |
| `hnsw.scan_mem_multiplier` | 預設為 `work_mem` 的1倍；僅加tuples卻沒提高recall時，檢查記憶體預算。 |
| `ivfflat.max_probes` | 限制iterative probes；若低於 `ivfflat.probes`，後者優先。 |

上表來源均為固定版本官方 README。[V3] 建議只針對檢索交易／session調整，避免直接全域放大每連線記憶體與掃描量。若應用用connection pool，須確認設定與查詢在同一transaction／connection，並避免設定洩漏到其他請求；這是部署設計要求，尚未核對ChatStack實作。

官方提供的relaxed重排模式如下；**PostgreSQL 17+需要外層 `ORDER BY distance + 0`**。重排只保證已取得候選的順序，沒有補回漏掉的候選。距離門檻應依官方建議放在materialized CTE外層，其他租戶／ACL條件放內層。[V3]

```sql
-- 示意結構，欄位名稱／維度／距離函數須對照真實應用。
WITH candidates AS MATERIALIZED (
  SELECT id, embedding <=> :query_vector AS distance
  FROM chunks
  WHERE tenant_id = :tenant_id
  ORDER BY embedding <=> :query_vector
  LIMIT :candidate_count
)
SELECT * FROM candidates
WHERE distance < :distance_threshold
ORDER BY distance + 0
LIMIT :k;
```

### 4.4 索引策略：先做查詢診斷，再換引擎

| 選擇 | 適用與代價 | 檢核 |
| --- | --- | --- |
| Exact scan + filter B-tree／適當GIN | 小資料量或高選擇性filter；可能先縮小集合後exact排序最划算，不需ANN誤差。 | 以同filter的exact結果作recall ground truth；不能把全庫exact與租戶ANN混比。 |
| HNSW | 無需訓練，可在空表建；官方指出相較IVFFlat通常有較好的速度／recall取捨，建置較慢、記憶體較多。 | `ef_search`、`m`、`ef_construction`；build是否超出 `maintenance_work_mem`；寫入、WAL、vacuum、索引膨脹。 |
| IVFFlat | 建得較快、通常較省記憶體，但需代表性資料訓練；資料分布成長變化需再驗證。 | 官方lists起點：≤100萬列約rows/1000，更多約sqrt(rows)；probes起點sqrt(lists)，均只是起始值。 |
| Partial index | 少量固定篩選值可建立專屬ANN，降低過濾後不足量。 | 動態租戶很多時索引數與planner／維護成本，不能一租戶一索引無限擴張。 |
| 分割／獨立表 | 需要隔離租戶的召回與效能；官方提醒共用ANN時其他租戶向量會影響recall。 | 大量小分割、prepared statement的pruning、跨租戶管理查詢成本。 |
| `halfvec`／binary quantization + rerank | 降低索引占用；需驗證精度、cast表達式與查詢是否吻合。 | 不因原始向量未改就假定候選集品質相同。 |

本表功能與起始參數來自pgvector官方README；適用建議是本研究判斷。[V3] 維度尤其容易誤判：`vector`型別可存至16,000維，不代表HNSW／IVFFlat可直接索引16,000維；兩者 `vector` ANN 上限為2,000維，`halfvec`為4,000維。HNSW另支援bit至64,000維與sparsevec至1,000個非零元素。若ChatStack embeddings維度超過2,000，應先核對實際cast／量化／降維路徑，不能只換PG major。[V3]

查詢若寫成 `ORDER BY 1 - (embedding <=> q) DESC`，官方指出不符合距離operator升冪+LIMIT的索引使用形式；改為距離operator排序與另算similarity才能正確評估。NULL向量不進ANN索引，cosine的零向量亦不進；dead tuples、過少訓練資料也會影響結果量。對這些問題換引擎前應先確認資料與SQL。[V3]

## 5. PG17 vs PG18 vs PG19

| 層面 | PG17現有基礎 | PG18增量 | 對ChatStack的判斷 |
| --- | --- | --- | --- |
| 維護／I/O | 改善VACUUM記憶體管理、streaming I/O；支援incremental base backup。[P8] | 新AIO可涵蓋sequential scan、bitmap heap scan、vacuum等。[P3] | 可能改善載入／掃描／維護；不能據此宣稱ANN random traversal等比例加速。 |
| 關聯式查詢 | 已有JSON_TABLE、SQL/JSON與B-tree查詢改善。[P8] | multicolumn B-tree skip scan。[P3] | metadata／聊天列表查詢若吻合特徵可受益；需EXPLAIN證明實際命中。 |
| Major升級恢復 | 17已可保留logical slots／subscription state，幫助未來major遷移。[P8] | `pg_upgrade`可保留optimizer statistics。[P3] | 可縮短升級後planner暖身問題，但仍需讀upgrade後統計處理指示。 |
| 應用新功能 | 既有PG SQL與extension生態。 | UUIDv7、virtual generated columns、OAuth、OLD/NEW RETURNING等。[P3] | 不修改應用schema／SQL通常不會自動享有這些功能。 |
| 安全／相容 | 需保持最新minor。[P1][P6] | initdb預設checksums；MD5 authentication被deprecated；其他行為改動。[P3] | checksums需配合舊cluster；驗證driver、連線、備份工具及schema migrations。 |
| 支援期 | 至2029-11-08。[P1] | 至2030-11-14。[P1] | 多一個major支援週期有價值，但17目前不迫近EOL。 |
| PG19 | — | — | 本次來源僅RC1。可看release候選評估方向，不承諾正式功能、性能或遷移日程。[P4] |

PG18需特別審閱的相容點：[P3]

- **checksums**：新 `initdb` 預設開啟；`pg_upgrade`要求新舊一致。若17關閉，不能直接用18預設initdb後預期檢查通過；應在演練時明確選擇相符設定或另規劃啟用流程。
- **locale／full text**：18讓full text與pg_trgm依cluster預設collation provider讀設定；非libc cluster可能改變行為，官方建議對受影響full-text／pg_trgm索引reindex。若同時bookworm→trixie或libc／ICU改版，也要獨立檢查collation；不可把所有變動歸因於PG18。
- **客戶端／維護**：CSV `COPY FROM`對 `\.` 的處理變更，舊psql的 `\copy` 可能受影響；保留對應工具測試。generated columns預設轉成virtual等schema行為也須看真實migration SQL。
- **認證**：MD5是deprecated，不是本次官方已移除；避免誤判既有MD5連線一定無法使用，同時規劃相容driver的SCRAM路徑。

## 6. Docker 18+ PGDATA／volume 陷阱

Docker Official Image文件明示以下變更；pgvector映像以官方Postgres映像為基礎，但仍需核對選定digest的Dockerfile／環境，而不是僅靠通用說明。[C1][V3]

| 映像預設 | `PGDATA` | 宣告的 `VOLUME`／建議掛載根目錄 |
| --- | --- | --- |
| PG17與更早 | `/var/lib/postgresql/data` | `/var/lib/postgresql/data` |
| PG18 | `/var/lib/postgresql/18/docker` | **`/var/lib/postgresql`** |
| 後續major的文件規則 | `/var/lib/postgresql/<major>/docker` | `/var/lib/postgresql`；不是證明該major已正式。 |

**單改 `image: pg17 → pg18` 不是資料遷移。** 18不能直接啟動17的資料格式；修改 `PGDATA` 或移動目錄也沒有轉換資料格式的效果。若volume仍掛舊路徑，可能資料沒有出現在新PGDATA、entrypoint拒絕舊資料配置、或在另一個持久化位置初始化新cluster；精確行為取決於該版entrypoint與掛載，不能承諾只會報錯。[P1][C1]

反向陷阱也存在：17未設定自訂PGDATA時，只掛 `/var/lib/postgresql` 而沒有明確覆蓋 `/var/lib/postgresql/data`，官方警告會因image宣告的子路徑匿名volume而把資料寫到非預期位置，重建container時不會按預期重用。[C1]

18+推薦掛父目錄是讓17與18等不同子目錄可位在同一filesystem，方便 `pg_upgrade --link`。**這只是布局條件，不代表image會自動執行pg_upgrade，也不表示可用link後隨時降回舊容器。** 若選dump/restore到獨立新volume，沒有必要為了--link重排舊生產volume。[C1][P7]

後續演練設計需明確記錄：host source／named volume名稱、container mount target、有效PGDATA、volume中PG_VERSION位置、UID/GID、磁碟空間、tablespaces與WAL位置；新舊volume與備份不可混淆。初始化環境變數與 `/docker-entrypoint-initdb.d`只在空資料目錄生效，不能用來代替既存database的extension更新。[C1]

VectorChord安裝頁示範直接掛 `/var/lib/postgresql/18/docker`，Docker官方則推薦父目錄 `/var/lib/postgresql`。前者可持久化18單一資料目錄，後者利於跨major同filesystem布局；這是用途差異，不應直接拼成通用upgrade命令。[A5][C1]

## 7. pg_upgrade、dump/restore、logical replication 的選擇

| 方法 | 停機／資源特性 | 優點 | 主要限制與rollback邊界 | 本案條件建議 |
| --- | --- | --- | --- | --- |
| `pg_upgrade`預設copy | 正式遷移期間停止寫入；需舊新binary、cluster與複製空間。 | 不做全部邏輯匯出重載，通常比dump/restore快；保留資料檔與相容索引。 | extension binary相容性、checksum／locale檢查；舊cluster可保留，但新庫接受寫入後仍無法無損直接退回。 | 大資料庫且可接受演練量到的停機，先比較copy／clone。 |
| `pg_upgrade --clone` | 同filesystem且必須支援reflink／clone；切換需停止寫入。 | 可避免完整複製且保留獨立舊檔案語意。 | 只限受支援OS／filesystem；不能未測就假定Docker volume支援。 | 若底層支援且演練通過，可比link更利於保留舊cluster。 |
| `pg_upgrade --link` | hard link，資料目錄須在同filesystem，磁碟與複製開銷低。 | 通常可縮短檔案搬移。 | **新cluster啟動後共用資料檔被改寫，舊cluster不可安全重啟**；rollback依賴獨立備份／snapshot。 | 停機與容量限制很嚴、且有驗證過獨立復原方案才選。 |
| dump/restore到新volume | 匯出可做一致snapshot；最終無遺失切換仍須停止寫入並處理最後變更。重載／索引重建耗時與空間較多。 | 跨布局／平台較清楚，重建資料與索引；新舊volume分明，可完整演練restore。 | roles／globals、所有DB、extension檔案、權限、large objects、序列與索引都要涵蓋；dump檔不是復原成功證明。 | 中小規模、實測還原可落在停機窗，通常最容易審查。 |
| logical replication到新cluster | 初始copy／追WAL時舊庫持續服務，最後短暫停寫並追平切換。 | 可減少最終停機；並行驗證新cluster。 | DDL、sequence狀態、large objects等不自動複寫；需replica identity、publication完整性、WAL保留與lag監控；新索引另建。 | 必須低停機且團隊能維運複寫，才承擔較大流程成本。 |

方法事實依官方upgrading、pg_upgrade與logical replication限制文件；適用建議屬本研究判斷，不是已量到的工期。[P7][P9][P10]

必要細節：

- `pg_upgrade`使用**新版本**工具，且需要**舊新兩套Postgres與對應extension library**。只拿一般PG18 runtime image不一定具備舊binary；不能未準備工具映像就照文件執行。新cluster不要預先自行建立extension SQL objects干擾schema restore，應遵照工具文件安裝support files的順序。[P7]
- `pg_upgrade --check`可在一定條件下對運行中的舊server檢查，仍會連線、需工作目錄寫入權限並操作檢查用環境；本次研究**沒有執行**，不將其誤包裝成已通過的唯讀保證。[P7]
- PG18可保留optimizer statistics，但官方upgrade後仍有missing stats／累計統計相關處理；依工具產出的rebuild／analyze提示，不省略事後檢查。[P3][P7]
- logical replication的UPDATE／DELETE需合適primary key或replica identity；對含vector等特殊型別的表，別假定 `REPLICA IDENTITY FULL`一定可用。官方指出沒有預設B-tree／Hash operator class的欄位會有apply限制；必須以真實schema與extension驗證。[P10]
- logical replication不複寫extension建立／更新與ANN索引內容；目標須先有相容型別、schema與權限，並建索引。切換時序列需追到安全值；DDL需凍結或雙邊協調；slot落後可能累積WAL吃滿磁碟。[P10]
- 任何方法中，新cluster／sidecar接受新寫入後，「切回原連線字串」通常代表丟失新資料；rollback必須明確選擇回放、反向同步或接受RPO，不能把保留舊volume誤當零資料損失rollback。

## 8. 保留PostgreSQL的向量擴充

### 8.1 pgvector：預設路徑

優點是向量與關聯資料同一database，沿用SQL、JOIN、MVCC、交易、權限及既有備份／PITR體系；沒有新增跨服務同步層。ANN仍要調參、vacuum、索引重建與recall測試；是否超過單機容量取決於資料量、dimension、QPS與延遲需求，不能僅以「向量資料庫」名詞判斷。[V3]

**本研究評估：替換成本最低、現場證據需求最少；適合作為baseline。** 先修正filter策略、索引SQL與記憶體預算，再用真實query set證明需要新引擎。

### 8.2 VectorChord

它是PostgreSQL extension，依賴pgvector型別，加入 `vchordrq`等索引與RaBitQ量化／reranking，而不是新的PostgreSQL相容關聯式伺服器。現行官方latest API是 **1.1.1，2026-02-28T04:04:07Z**，`draft=false`、`prerelease=false`，assets有PG14–18、amd64／arm64套件。官方安裝頁也示範PG18映像，但不同CPU的支援、源碼編譯與套件可得性應分開判斷。[A1][A5][A7]

- **改動面**：保留原 `vector`欄位／距離SQL有助降低資料轉換量；新索引建置、訓練／量化與設定仍要設計，現有HNSW不會自動變成VectorChord索引。應用若硬編碼 `USING hnsw`、specific opclass、GUC或對planner假設，就不是完全drop-in。[A1]
- **運維**：需要自訂／官方擴充映像、相同major的library與preload設定；安裝範例可見 `shared_preload_libraries=vchord,vector`。不應因SQL相容就忽略server restart、extension／index版本與備份restore演練。[A5]
- **授權與版本風險**：目前官方README寫**AGPLv3或Elastic License v2雙授權**，不能沿用對舊版「寬鬆開源」的印象；選定release應再讀其LICENSE與相依授權。suite support matrix仍舊，必須逐一驗證。[A1][A6]
- **退回**：若保留原始pgvector欄位且未改用專屬量化型別，可規劃重建原pgvector索引；若開始將資料永久存為專屬 `rabitq4`／`rabitq8`，回到原精度與原schema的成本會不同。1.1.1 release新增dequantize函式也不表示可無損還原原始浮點精度。[A10]

**有條件推薦**：大索引的RAM／磁碟壓力確有量測證據、可接受新增extension生命週期與授權條件時，做隔離PoC；不把「相容pgvector」當成ChatStack現成支援認證。

### 8.3 pgvectorscale（Timescale／Tiger Data）

pgvectorscale是以Rust／pgrx開發、**建立在pgvector上**的PostgreSQL extension，SQL extension名稱是 `vectorscale`；加上StreamingDiskANN、Smart Binary Quantization與label-based filtered search。它不是TimescaleDB本身，也不是要求所有表轉為hypertable。官方文件可在一般PostgreSQL安裝 `vectorscale CASCADE`，相依者為pgvector；本次沒有依據說必須裝TimescaleDB。[A2]

最新release API：**0.9.1，2026-09-04T12:19:57Z**，非prerelease；固定0.9.1 manifest列 **PG14–18** features、預設PG18，release assets也有這些major的amd64／arm64包。0.9.0 release notes明示新增PG18、移除PG13支援。不能根據較舊文章宣稱「僅PG16／17」，也不能根據0.9.2-dev宣稱新正式版存在。[A3][A4][A8]

- **兼容性**：沿用pgvector的 `vector`、`<=>`／`<->`／`<#>`，但索引access method為diskann，不等於完整支援pgvector所有型別／距離。官方README指出inner product index不相容plain storage；halfvec、sparsevec、特定維度等需逐項確認，不外推。[A2]
- **filter與排序**：label-based filter使用 `smallint[]`與專用條件，不是所有JSONB／ACL表達式自動變快；DiskANN採relaxed ordering，需materialized CTE重排才能提供穩定距離順序。[A2]
- **生命週期風險**：0.9.1包含type confusion／malformed datum安全性強化，無有效 `vector(N)` typmod的欄位不能再建DiskANN；已存無效dimension的舊索引須drop／重建，官方明示 **REINDEX不能修復此情況**。這證明extension升級不只是替換二進位。[A4]
- **授權**：repository列PostgreSQL License，與VectorChord現行授權不同；不能把同一廠牌其他產品授權套過來。[A2]

**有條件推薦**：若要留在Postgres且主要瓶頸是大規模ANN儲存／記憶體，適合與VectorChord並列PoC。以安全修補版0.9.1作候選，保留原始向量與重建回pgvector的路徑；不把廠商對Pinecone的自測倍率轉用到ChatStack。

### 8.4 TimescaleDB、Timescale與Tiger Data／Tiger Cloud

TimescaleDB是PostgreSQL extension；Tiger Data是當前官方文件品牌、Tiger Cloud是託管服務。**安裝TimescaleDB、安裝pgvectorscale、換到Tiger Cloud是三個不同決策**。TimescaleDB主要價值應對應時間序列／hypertable與相關分析需求，而不是只因有向量就需要導入。[A2][A11]

本次官方TimescaleDB↔PG矩陣列2.23–2.31支援PG18；2.20–2.22不支援PG18；2.29–2.31只列PG16／17／18，2.28是最後支援PG15的minor系列。若實際安裝TimescaleDB，升級PG前必須先找**新舊PG皆支援的TimescaleDB橋接版本**，不能只用latest映像。矩陣尚明示歷史ABI破壞minor與2.31的最低build條件，顯示extension／PG minor也有耦合。[A11]

**本研究評估**：目前沒有ChatStack時序需求或已使用TimescaleDB證據，僅為向量檢索新增TimescaleDB會增加不必要的版本面；Tiger Cloud可作「外包PG運維」選項，但需另評估extension可得性、版本更新政策、連線延遲、備份匯出與成本，不是pgvector升級的必要前提。

## 9. 獨立向量／搜尋引擎與其他關聯式引擎

以下「成本／適合」是依官方架構所作本研究工程評估，並非量測benchmark。**各方案是否有ChatStack官方adapter、其功能是否完整，本子任務未讀ChatStack原始碼，全部待父代理確認。**

| 選項 | 正確角色與官方能力 | 相對遷移／運維成本與相容風險 | 有條件決策 |
| --- | --- | --- | --- |
| **Qdrant** | 獨立vector search服務，以points／vectors／payload與filter API；支援分散式部署與replication。[S1][S2] | 新client／API、collection配置、ID與payload映射、向量重匯、另一套snapshot／restore與監控。分散式模式本身**不會自動複寫或搬移資料**；需配置shard與replication factor。[S2] | 若向量查詢需要獨立擴容、而團隊能維護同步投影，列為較直接的sidecar PoC；保持Postgres處理交易與關聯資料。 |
| **Milvus** | 大規模獨立vector database，官方當前architecture頁為v3.0.x，採access／coordinator／worker／storage分層，storage含etcd、WAL、object storage。[S3] | 分散式方案引入多個服務、storage與控制面；容量／備援／升級需整體測。不可用舊版必需Kafka／Pulsar的架構斷言套當前頁，或把可單機部署等同分散式很便宜。 | 有明確超大規模、分離計算儲存與專責運維需求才評估；一般ChatStack升級不先承擔此架構面。 |
| **Weaviate** | 以collections／objects與vector／BM25 hybrid API作檢索；cluster metadata為Raft，資料replication為leaderless且consistency可調。[S4][S5] | collection／vectorizer／schema與query API改寫；tenant與物件權限投影；額外備份與不同一致性語意。不能將物件API等同PG跨表ACID交易。 | 當hybrid search與其資料／模型整合直接符合產品需求，且接受新的資料層時評估。 |
| **OpenSearch** | 獨立搜尋平台，可同索引存文字／向量並以knn／neural等API檢索。[S6] | JSON mapping、維度、分析器、索引／shard與搜尋pipeline；從PG投影資料、處理refresh／索引重建／刪除延遲；不是PG SQL／JOIN／交易的替換。 | 已有OpenSearch運維、需要統一大量全文+向量搜尋時較合理；只為升PG不新增整套搜尋叢集。 |
| **MySQL** | 另一個關聯式store，可承接交易資料，但不是PG wire／SQL／extension相容。實際讀到9.7的VECTOR型別及function文件。[D1][D2] | schema、migration、JSONB／SQL／型別／索引／driver與交易差異；`vector`欄位不能作一般key。**DISTANCE()僅MySQL HeatWave on OCI與MySQL AI提供，Community／Commercial不含**，不能因有VECTOR就假定普通MySQL可提供等價ANN。[D2] | 只有獨立業務理由、確認ChatStack支援且完整遷移測試時才談換store；不是本次升級捷徑。 |
| **SQLite + sqlite-vec** | SQLite是embedded relational store；sqlite-vec是第三方vector extension，作者README自述仍pre-v1，可能breaking changes。[D3][D4][D5] | 需把server型資料層與權限改成embedded；SQLite單時點僅一writer，沒有PG式GRANT／REVOKE。extension API／索引與PG vector不同。 | 單機／離線／個人端新架構可評估；不是既有多人ChatStack後端的原位升級。不能把SQLite本體官方支援與第三方extension保證混為一談。 |

### Sidecar不是免費替換：必須保留的語意

對Qdrant／Milvus／Weaviate／OpenSearch的建議架構是PostgreSQL繼續持有使用者、對話、文件、租戶／ACL等權威資料（實際表由父代理確認），搜尋服務只持有能從權威資料重建的chunk／embedding投影。以下是架構推論與後續驗收要求，不是聲稱上述引擎沒有本身的可靠性能力：

1. **可靠同步**：同一PG transaction寫outbox，worker冪等upsert／delete；或經驗證CDC。避免同步dual-write第一邊成功第二邊失敗造成永久分歧。投影帶document/chunk ID、embedding model/version、dimension、content hash、tenant及ACL version。
2. **刪除與撤權**：刪文件、刪租戶、改ACL、換知識庫時必須有tombstone／retry／reconciliation；搜尋候選不可在未驗證授權前回傳正文。即使sidecar可filter，也要證明過濾欄位的更新時效。
3. **讀寫時序**：定義寫入後多久可被搜尋、重試與舊版本覆蓋規則；同名embedding model更版也可能改向量空間，不能把不同model版本丟同一索引當可比較。
4. **復原一致性**：PG備份／PITR與sidecar snapshot未必同一時間；復原後需watermark、重放或全量reindex。將「可從原文重算embedding」和「可從已保存embedding重建index」的費用／時間分開估算。
5. **回退**：保留原pgvector查詢／索引直到shadow結果、recall、filter安全與lag均達標；索引切換前後的結果順序、distance方向、cosine normalization與score threshold需逐一對照。

若父代理確認ChatStack只使用Postgres作vector store、其他關聯資料在別處，sidecar遷移範圍可能較小；若同一Postgres承載核心關聯資料，整體替換風險顯著提高。本研究不預設任一資料分工已成立。

## 10. 條件式決策與後續研究缺口

| 若盤點／驗證結果是… | 推薦路線 |
| --- | --- |
| 現場PG17／vector已最新，檢索延遲／品質均達標 | 維持現狀；建立固定digest、備份復原與版本維護節奏。可排PG18演練，無需為版本數字換引擎。 |
| PG17或vector落後，尤其命中已知修補範圍 | 分開規劃PG17 minor與vector 0.8.7維護；讀完整跨版本notes、測備份與ANN品質，不混入新引擎。 |
| 有過濾後不足k筆／recall問題 | 先檢查SQL、filter索引、NULL／零向量、iterative scan與分割策略；區分ANN漏召回和資料／ACL確實不足。 |
| PG18 AIO／skip scan／支援期符合已證實需求 | 目標PG18.6 + vector 0.8.7，固定映像digest；選restore或pg_upgrade演練，處理PGDATA與checksums。正式執行前重新確認最新官方修補。 |
| 有可接受停機窗，還原測量能落在窗內 | 優先比較新volume dump/restore的簡潔性與安全性；保留舊cluster／備份，設明確切換與寫入後rollback規則。 |
| 資料大、重載索引過久，但可停機 | 測pg_upgrade copy／clone；只有獨立復原已證明、容量／停機迫使時才採link。 |
| 幾乎不可停機且具複寫維運能力 | logical replication至新cluster；DDL／sequences／replica identity／WAL保留／lag與最終停寫協調納入方案。 |
| HNSW記憶體／磁碟成本確實不達標、但想維持SQL交易 | 同資料集平行比較pgvectorscale 0.9.1與VectorChord 1.1.1；先核對授權／相容性與離線restore，再談採用。 |
| 需要向量層獨立擴容／故障隔離，PG內擴充仍不達標 | 評估sidecar；Qdrant作直接向量服務候選，Milvus看規模與團隊，Weaviate看hybrid需求，OpenSearch看既有搜尋體系。這是需求適配，非性能排名。 |
| 只因2026年已過預期發布季，想上PG19 | 暫緩；以官方GA、extension固定release、映像、工具與應用回歸測試齊備為門檻，不能以公告計畫代替。 |

父代理需補齊的證據：

- **現場版本／拓樸**：每個database的extension與schema、是否兼作relational store、連線pool／driver、image digest／PG minor／base OS／CPU架構、PGDATA／mount／locale／checksums。
- **資料與索引**：chunk／vector數、維度／model、每tenant分布與filter選擇性、index definitions／大小、insert/update/delete率、dead tuples、vacuum狀態、working set、RAM／磁碟／IOPS。
- **真實需求**：recall@k、足k率、p50／p95／p99、QPS／併發、寫入後可搜尋lag、RPO／RTO、停機窗、目前容量與預期成長；不要先捏造「百萬筆就一定換引擎」門檻。
- **可比較測試**：固定同一embedding與資料版本，按真實tenant／ACL分布產生query set，以同filter exact結果作ground truth；warm／cold cache、相同硬體、索引建置與維護時間、磁碟／RAM／WAL、同步與刪除一致性一起量。各引擎用達相同recall／安全性條件的設定比較，而非只看最快單次查詢。
- **復原演練**：還原至空volume、extension載入、表數／資料校驗、序列／權限、應用讀寫／RAG、切換後寫入與rollback。沒有實際restore，不宣稱備份可用；本次未執行演練。

## 11. 官方來源台帳

下列均於 **2026-10-31（本機環境日期）** 透過smart-search `fetch`實際讀取。API來源是官方專案GitHub metadata，不是第三方整理。歷史／可變頁內容若再次讀取不同，應保留差異。

| 代號 | 官方URL／範圍 | 讀取日期 |
| --- | --- | --- |
| P1 | https://www.postgresql.org/support/versioning/ — current minor、支援政策／EOL | 2026-10-31 |
| P2 | https://www.postgresql.org/ — 當前首頁正式與RC狀態／minor日期 | 2026-10-31 |
| P3 | https://www.postgresql.org/docs/18/release-18.html — PG18功能／不相容變更 | 2026-10-31 |
| P4 | https://www.postgresql.org/about/news/postgresql-19-rc-1-released-3409/ — RC1與計畫GA | 2026-10-31 |
| P5 | https://www.postgresql.org/docs/18/release-18-6.html — 18.6 notes | 2026-10-31 |
| P6 | https://www.postgresql.org/docs/17/release-17-11.html — 17.11 notes | 2026-10-31 |
| P7 | https://www.postgresql.org/docs/18/pgupgrade.html — pg_upgrade方法／限制／rollback | 2026-10-31 |
| P8 | https://www.postgresql.org/docs/17/release-17.html — PG17基礎功能 | 2026-10-31 |
| P9 | https://www.postgresql.org/docs/18/upgrading.html — major三種遷移路線 | 2026-10-31 |
| P10 | https://www.postgresql.org/docs/18/logical-replication-restrictions.html — DDL／sequence／large object等限制 | 2026-10-31 |
| V1 | https://github.com/pgvector/pgvector/tags — 最新tag與commit日期 | 2026-10-31 |
| V2 | https://raw.githubusercontent.com/pgvector/pgvector/master/CHANGELOG.md — 發布史／修補 | 2026-10-31 |
| V3 | https://raw.githubusercontent.com/pgvector/pgvector/v0.8.7/README.md — 固定版本安裝／升級／索引／維度／Docker | 2026-10-31 |
| V4 | https://github.com/pgvector/pgvector/releases — 無GitHub Releases，不代表無tags | 2026-10-31 |
| V5 | https://raw.githubusercontent.com/pgvector/pgvector/v0.8.7/.github/workflows/build.yml — 固定tag CI設定 | 2026-10-31 |
| V6 | https://raw.githubusercontent.com/pgvector/pgvector/master/.github/workflows/build.yml — 開發CI對照 | 2026-10-31 |
| C1 | https://hub.docker.com/_/postgres — 官方image PGDATA、VOLUME、init行為 | 2026-10-31 |
| A1 | https://github.com/tensorchord/VectorChord — 主專案；實際導向supervc-stack；功能／相依／授權 | 2026-10-31 |
| A2 | https://github.com/timescale/pgvectorscale — README能力／型別／filter／license | 2026-10-31 |
| A3 | https://api.github.com/repos/timescale/pgvectorscale/releases/latest — 0.9.1時間與assets | 2026-10-31 |
| A4 | https://github.com/timescale/pgvectorscale/releases — 0.9.1安全修補與upgrade注意事項、0.9.0 PG18支援 | 2026-10-31 |
| A5 | https://docs.vectorchord.ai/vectorchord/getting-started/installation.html — 安裝／映像／preload／architecture | 2026-10-31 |
| A6 | https://github.com/tensorchord/VectorChord-images — suite support matrix（仍列20250929） | 2026-10-31 |
| A7 | https://api.github.com/repos/tensorchord/VectorChord/releases/latest — 實際回傳supervc-stack，1.1.1時間與assets | 2026-10-31 |
| A8 | https://raw.githubusercontent.com/timescale/pgvectorscale/0.9.1/pgvectorscale/Cargo.toml — 固定release PG14–18 feature matrix | 2026-10-31 |
| A9 | https://raw.githubusercontent.com/timescale/pgvectorscale/main/pgvectorscale/Cargo.toml — 0.9.2-dev對照 | 2026-10-31 |
| A10 | https://github.com/tensorchord/VectorChord/releases — 1.1.1量化／dequantize變更；新release URL https://github.com/supervc-stack/VectorChord/releases/tag/1.1.1 | 2026-10-31 |
| A11 | https://docs.tigerdata.com/self-hosted/latest/upgrades/upgrade-pg/ — TimescaleDB↔PG支援矩陣 | 2026-10-31 |
| S1 | https://qdrant.tech/documentation/overview/what-is-qdrant/ — 引擎定位 | 2026-10-31 |
| S2 | https://qdrant.tech/documentation/scaling/distributed_deployment/ — 分散式／shards／replication | 2026-10-31 |
| S3 | https://milvus.io/docs/architecture_overview.md — 實際v3.0.x架構 | 2026-10-31 |
| S4 | https://docs.weaviate.io/weaviate/concepts/replication-architecture — metadata／data一致性架構 | 2026-10-31 |
| S5 | https://docs.weaviate.io/weaviate/search/hybrid — vector與BM25 hybrid API | 2026-10-31 |
| S6 | https://docs.opensearch.org/latest/vector-search/ — vector／neural搜尋、mapping／pipeline | 2026-10-31 |
| D1 | https://dev.mysql.com/doc/refman/9.4/en/vector.html — 實際呈現9.7 VECTOR頁；版本redirect已記錄 | 2026-10-31 |
| D2 | https://dev.mysql.com/doc/refman/9.7/en/vector-functions.html — DISTANCE產品限制 | 2026-10-31 |
| D3 | https://www.sqlite.org/whentouse.html — embedded定位／單writer（頁面last updated 2025-05-31） | 2026-10-31 |
| D4 | https://www.sqlite.org/omitted.html — GRANT／REVOKE等差異（頁面last updated 2022-04-18） | 2026-10-31 |
| D5 | https://github.com/asg017/sqlite-vec — 作者官方repository，pre-v1聲明 | 2026-10-31 |

[P1]: https://www.postgresql.org/support/versioning/
[P2]: https://www.postgresql.org/
[P3]: https://www.postgresql.org/docs/18/release-18.html
[P4]: https://www.postgresql.org/about/news/postgresql-19-rc-1-released-3409/
[P5]: https://www.postgresql.org/docs/18/release-18-6.html
[P6]: https://www.postgresql.org/docs/17/release-17-11.html
[P7]: https://www.postgresql.org/docs/18/pgupgrade.html
[P8]: https://www.postgresql.org/docs/17/release-17.html
[P9]: https://www.postgresql.org/docs/18/upgrading.html
[P10]: https://www.postgresql.org/docs/18/logical-replication-restrictions.html
[V1]: https://github.com/pgvector/pgvector/tags
[V2]: https://raw.githubusercontent.com/pgvector/pgvector/master/CHANGELOG.md
[V3]: https://raw.githubusercontent.com/pgvector/pgvector/v0.8.7/README.md
[V4]: https://github.com/pgvector/pgvector/releases
[V5]: https://raw.githubusercontent.com/pgvector/pgvector/v0.8.7/.github/workflows/build.yml
[V6]: https://raw.githubusercontent.com/pgvector/pgvector/master/.github/workflows/build.yml
[C1]: https://hub.docker.com/_/postgres
[A1]: https://github.com/tensorchord/VectorChord
[A2]: https://github.com/timescale/pgvectorscale
[A3]: https://api.github.com/repos/timescale/pgvectorscale/releases/latest
[A4]: https://github.com/timescale/pgvectorscale/releases
[A5]: https://docs.vectorchord.ai/vectorchord/getting-started/installation.html
[A6]: https://github.com/tensorchord/VectorChord-images
[A7]: https://api.github.com/repos/tensorchord/VectorChord/releases/latest
[A8]: https://raw.githubusercontent.com/timescale/pgvectorscale/0.9.1/pgvectorscale/Cargo.toml
[A9]: https://raw.githubusercontent.com/timescale/pgvectorscale/main/pgvectorscale/Cargo.toml
[A10]: https://github.com/tensorchord/VectorChord/releases
[A11]: https://docs.tigerdata.com/self-hosted/latest/upgrades/upgrade-pg/
[S1]: https://qdrant.tech/documentation/overview/what-is-qdrant/
[S2]: https://qdrant.tech/documentation/scaling/distributed_deployment/
[S3]: https://milvus.io/docs/architecture_overview.md
[S4]: https://docs.weaviate.io/weaviate/concepts/replication-architecture
[S5]: https://docs.weaviate.io/weaviate/search/hybrid
[S6]: https://docs.opensearch.org/latest/vector-search/
[D1]: https://dev.mysql.com/doc/refman/9.4/en/vector.html
[D2]: https://dev.mysql.com/doc/refman/9.7/en/vector-functions.html
[D3]: https://www.sqlite.org/whentouse.html
[D4]: https://www.sqlite.org/omitted.html
[D5]: https://github.com/asg017/sqlite-vec
