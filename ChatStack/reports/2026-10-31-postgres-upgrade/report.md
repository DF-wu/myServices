# ChatStack 資料庫升級研究

研究日期：2026-10-31（Asia/Taipei）。這是一份決策與演練規劃，尚未執行資料庫升級、套件更新、服務重啟或設定變更。公開版只含彙總資料與技術資訊，不含帳密、連線字串、內網位址、聊天內容或用戶紀錄。

## 建議先看這裡 {#decision}

**保留 PostgreSQL＋pgvector。先整理現有 17 分支與延伸套件，再把 PostgreSQL 18 作為下一階段的演練目標。** 現在沒有足夠證據，證明更換向量引擎能改善你的主要負載。

這個專案真正需要處理的是「三個已確認客戶端共用同一叢集的可靠性」，以及遺留設定、日誌、聊天資料與升級回復能力。升級資料庫主版本只是其中一項工作。

- **現況已確認**：PostgreSQL **17.11**；映像內可用的 pgvector 預設版本 **0.8.7**，各 database 已安裝版本卻分別為 **0.8.0／0.8.1／0.8.7**。
- **相依範圍已縮小**：**3 個已確認直接客戶端＋1 個遺留 PG 設定**、7 個非 template 資料庫，合計約 **10.07 GiB**。Infinite Canvas 目前是靜態前端，不能只看 DSN 就算成活躍 PG 使用者。主機上的 Immich、TeslaMate、Nextcloud、MetaMCP 有各自的 PostgreSQL，不是這次共用叢集的升級範圍。
- **向量負載很小**：在三個已辨識的向量資料表做唯讀 `COUNT(*)`，結果是 **0／149／0 筆**。這是查核當下的實際筆數，不代表歷史未使用或其他外部系統沒有副本。
- **優先補強**：確認可還原的備份、NFS 寫入持久性與延遲、固定映像 digest、各服務獨立帳號與連線預算，再決定是否切到 18。

**決策順序：保護資料 → 固定基線 → 同 major 的 extension 整理 → 18 的還原演練 → 各服務驗收 → 另案批准切換。** 不把服務軟體升版、資料庫 major、作業系統基底與向量引擎替換混在同一個變更窗口。

## 現況：我們實際查到了什麼 {#inventory}

證據來自目前解析後的 Compose、所有本機容器的已遮蔽環境設定、映像 metadata、PostgreSQL catalog 與統計視圖。SQL 使用唯讀模式、8 秒 statement timeout、1 秒 lock timeout；沒有讀取聊天文字、token、API 金鑰或業務資料列內容。

### 容量分布

<div id="size-chart"></div>

| 資料庫 | 大小（GiB） | 主要用途與本次觀察 | 向量 extension |
|---|---:|---|---|
| `veloera_db` | 5.318 | **目前由 New API 使用**，舊名稱不等於目前執行 Veloera；`logs` 約 5.293 GiB，含索引與 TOAST | 無 |
| `openwebui_db` | 3.530 | 聊天資料為主；`chat` 約 2.416 GiB、`chat_message` 約 1.050 GiB | vector 0.8.0 |
| `sub2api` | 1.180 | 操作日誌、用量紀錄與監控資料；`ops_system_logs` 約 0.776 GiB | 無；有 pg_trgm 1.6 |
| `js_llmcord_rag` | 0.014 | 舊 RAG 庫；embeddings 149 筆，當前 Compose 未見啟用的直接客戶端 | vector 0.8.1 |
| `infinite_canvas` | 0.013 | 歷史提示詞、設定、用戶與資產 metadata；共 5 個 user tables；當前 Canvas 映像不包含 PG 後端 | 無 |
| `librechat_rag` | 0.008 | 舊 RAG 庫；langchain embedding 表目前 0 筆；仍有 collection metadata | vector 0.8.7 |
| `postgres` | 0.007 | 預設維運 database | 無 |

大小是 PostgreSQL 的 `pg_database_size`／`pg_total_relation_size`，會隨寫入變動；不是備份檔大小，也沒有包含完整 WAL、額外快照或 NAS 空間成本。約 87.9% 的 database 空間在 New API 與 Open WebUI。不能由大表大小直接判定為 bloat。

### 向量資產

| 資料庫／表 | 型別與實際筆數 | 現有索引 | 判斷 |
|---|---|---|---|
| Open WebUI / `document_chunk` | `vector(1536)`；0 筆 | IVFFlat，cosine，lists=100；索引實體約 41.8 MiB | 現階段不需要用大規模 ANN benchmark 決定架構；空表仍有索引空間不等於資料遺失 |
| 舊 llmcord / `embeddings` | `vector(1536)`；149 筆 | 1 個全表 HNSW＋3 個依 type 的 partial HNSW | 小資料集可能連 exact search 都足夠；先找 owner，不刪庫、不先拆索引 |
| 舊 LibreChat / `langchain_pg_embedding` | 無 typmod 的 `vector`；0 筆 | 無 ANN 索引 | 保留 schema 與 collection；不能因當下沒有連線就認定可刪 |

`n_live_tup`、`reltuples` 是估計值，本次看見部分表的估計明顯不適合拿來當實際筆數，因此只對上述小型向量表另做有時間上限的計數。未對大型聊天表做全表掃描，也沒有在生產環境執行 `ANALYZE` 或重建索引。[PostgreSQL 統計視圖][stats]

### 執行環境

| 項目 | 已確認現況 | 對升級的意義 |
|---|---|---|
| 映像 | `pgvector/pgvector:pg17`，目前實際為 PostgreSQL 17.11／Debian 12 基底 | tag 會漂移；正式演練應固定 digest，不能把 tag 當成精確版本 |
| 資料目錄 | 舊式 `/var/lib/postgresql/data` 掛載，底層 **NFS 4.2**，client 為 `hard` mount | 18+ 官方映像有目錄布局變更；另查 NAS server 的同步寫入語義 |
| 記憶體／CPU | PostgreSQL 容器未設 memory／CPU 限制；主機約 125.9 GiB RAM、48 logical CPUs，且有大量其他容器 | 不能用整台主機 RAM 的 25% 直接當此 DB 的 buffers |
| shared memory | Docker `/dev/shm` 64 MiB | 平行查詢與向量建索引前要另行評估；不代表 shared_buffers 只能設 64 MiB |
| 連線 | max_connections=100；取樣約 12–13 條業務連線，另有研究查詢 | 一次低負載取樣不是尖峰容量；目前沒有證據支持先大幅增加上限 |
| 可觀測性 | pg_stat_statements 未安裝、shared_preload_libraries 空、track_io_timing off、慢查詢門檻未啟用 | 缺少按 query 衡量的基線，無法承諾升級後快幾倍 |
| 備份相關 | archive_mode=off；有 Backrest 容器，但未確認本叢集的 DB-aware 備份／成功還原紀錄 | 只能說未驗證 PITR／還原能力，不能推論整台主機沒有備份 |
| collation | 所查 database 皆為 en_US.utf8；記錄版本與 runtime glibc 版本都是 2.36 | 目前未見 mismatch；更換 Debian／glibc 基底後要重查 |

## 版本應該怎麼選 {#versions}

| 決策用途 | 推薦版本 | 理由與條件 |
|---|---|---|
| 短期維護基線 | **PostgreSQL 17.11＋pgvector 0.8.7** | 17.11 已是本次官網列出的 17 最新 minor，現場不需要為了「補新版本」重做同版升級；應重點處理逐 database 的 extension catalog、可重現部署與 restore |
| 下一個 major 演練目標 | **PostgreSQL 18.6＋pgvector 0.8.7** | 本次查得最新正式 major／minor；三個直接客戶端、間接服務與歷史資料都通過完整演練後，才列正式切換候選 |
| 暫不採用 | **PostgreSQL 19 RC1** | 官方仍標 RC；公告規劃 2026-11-19 GA，不等於已正式發布，亦不應以 CI 中出現 PG19／20 推論可投入生產 |
| 替代 extension 的條件式 PoC | pgvectorscale **0.9.1**／VectorChord **1.1.1** | 僅在真實向量負載不達標時評估；release、授權、PG major、架構、preload 與 restore 必須一起驗證，不是本案預設安裝項 |

版本依 [PostgreSQL 官方支援表](https://www.postgresql.org/support/versioning/)、[PG19 RC1 公告](https://www.postgresql.org/about/news/postgresql-19-rc-1-released-3409/)、[pgvector 0.8.7 固定版說明](https://raw.githubusercontent.com/pgvector/pgvector/v0.8.7/README.md) 與 [changelog](https://raw.githubusercontent.com/pgvector/pgvector/master/CHANGELOG.md)。正式操作前重新查詢，不能把本報告的版本永久當成 latest。

| PG 分支 | 本次查得最新 minor | 官方支援截止 | 本案選擇 |
|---|---|---|---|
| 18 | 18.6 | 2030-11-14 | 下一階段演練目標 |
| 17 | 17.11 | 2029-11-08 | 現在仍有充足維護週期，先把基線整理好 |
| 16 | 16.15 | 2028-11-09 | 不從 17 降級 |
| 15 | 15.19 | 2027-11-11 | 不作新目標 |
| 14 | 14.24 | 2026-11-12 | 將屆 EOL，不作本案目標；其他產品的 PG14 另案處理 |

**升到 18 能得到什麼？** 新 AIO 改善部分掃描／vacuum 路徑，B-tree skip scan 可能改善符合條件的複合索引查詢，pg_upgrade 可以保留 optimizer statistics，並多一個 major 的支援週期。但應用不會自動使用 UUIDv7 等 schema 新功能，也沒有證據顯示現有 RAG 會因此固定加速多少。[PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)

**本案特別要處理 checksums。** 現場 `data_checksums=off`；18 的新 initdb 預設開啟。若用 pg_upgrade，新舊設定需相容，不能照預設初始化就假定 check 會過。若用邏輯 restore 到新庫，可獨立決定 checksums；這也是偏好先演練 restore 的理由之一。Sub2API 已使用 pg_trgm，還要對照 PG18 的 collation／全文與 trigram 行為變更及必要 reindex 指示。[PG18 相容性說明](https://www.postgresql.org/docs/18/release-18.html) [pg_upgrade](https://www.postgresql.org/docs/18/pgupgrade.html)

### 為什麼不直接把 image 換成 pg18？

主版本有資料目錄格式差異，**17 的舊目錄不能交給 18 直接啟動**。而且 PostgreSQL Docker Official Image 在 18+ 的預設 `PGDATA` 改為 major-specific 路徑，常見為 `/var/lib/postgresql/18/docker`，建議掛載層級也改為 `/var/lib/postgresql`；沿用舊掛載可能報錯或初始化到錯的位置。這是路徑調整與資料轉換兩件事，換一個 volume target 不會完成升級。[Docker PostgreSQL 官方說明][dockerpg]

pgvector 也有兩層版本：映像裡的 extension 檔案／shared library，與每個 database 內 `pg_extension.extversion`。拉新 image 不會自動將所有 database 的 SQL extension 版本統一。本次已直接看見兩者不同；應逐庫確認官方 upgrade path，然後在還原副本上測試更新，不在這次研究時更新。0.8.x 有多項索引建置／vacuum 修補，但**僅看 catalog 的 0.8.0 不能推論執行中的 shared library 仍是 0.8.0**；目前映像提供 0.8.7，需分層驗證，不能將版本不一致直接當成已發現損毀。[pgvector 官方說明][pgvector] [修補紀錄](https://raw.githubusercontent.com/pgvector/pgvector/master/CHANGELOG.md)

## 相依圖與各服務要求 {#dependencies}

<div id="dependency-map"></div>

圖中的直接關係由設定、固定映像實作與當下 PG 連線互相印證；間接關係代表 API／啟動相依。Infinite Canvas 另列為遺留設定，沒有畫成直接連線。這不是完整網路流量追蹤，也不代表所有功能都會隨 DB 停止立即不可用。

### 三個直接客戶端與一個遺留設定

| 服務／已部署版本 | 官方 PG 要求 | Extension 要求與現場狀態 | PG18 證據／遷移重點 |
|---|---|---|---|
| **Open WebUI**：OCI 標記 main-ollama，固定 revision `f7ac7ee` | 官方列 PostgreSQL／SQLite，**未找到最低或推薦 PG major 明文**；pgvector 本身 PG13+ 是 extension 的條件 | `VECTOR_DB=pgvector` 需要 vector；目前庫內 SQL version 0.8.0。pgcrypto 僅選用加密時需要，本機未顯式啟用 | 未找到本 app revision 的 PG18 成功驗證紀錄。Alembic 預設啟動升 schema，向量初始化另有 DDL 路徑；兩者都須演練 [文件][OW-DBDocs] [固定程式][OW-Config] |
| **New API**：v1.0.0-rc.47，revision `e835b1b` | README 明列 **PG ≥9.6**；這是上游宣告，**不代表建議使用已 EOL 版本**。範例 PG15 不構成最高版本限制 | 所查初始化未找到必需 vector／uuid-ossp／pg_trgm；現場僅 plpgsql | 未取得此 revision 的 PG18 明確通過紀錄。master node 啟動 migration／GORM AutoMigrate，部分 custom migration 會取排他 table lock [README][NA-README] [初始化][NA-Main] [migrator][NA-Dialect] |
| **Sub2API**：0.2.19，revision `dece261` | README 與初始 SQL 明列 **PG15+** | pg_trgm 是可跳過的搜尋效能選項，migration 捕捉 extension 建立失敗；本機已安裝 1.6，遷移應保留 | 官方 compose 用 PG18，integration harness 固定 18.1，CI 有執行路徑；**未核對成功 run**。migration 使用 session advisory lock；transaction pooler 需特別處理 [需求][S2-README] [測試][S2-Tests] [runner][S2-Runner] |
| **Infinite Canvas**：v0.20.0，revision `3a6b64b` | **當前映像不適用 PG major 要求**，不能用舊後端文件推論 | 目前 runtime 是 Nginx 靜態前端，localforage 儲存在瀏覽器；遺留 PG DSN 不被當前 entrypoint 使用 | 本機另外核對 command／process 與 Nginx 設定：只有 Nginx、未見 proxy_pass。歷史 `infinite_canvas` DB 仍保留，不因這項發現刪除 [Dockerfile][IC-Dockerfile] [storage][IC-Storage] [entrypoint][IC-Entrypoint] |

**共用版本下限的實務解讀**：已找到的應用明文要求中，Sub2API 的 PG15+ 較高；pgvector 支援 PG13+ 不構成升回 PG13 的理由。這些下限也不證明 15、17、18 的每個流程都已測過。PG17 現在已有 runtime 使用證據；PG18 則仍須你這組映像與 schema 的整體驗收。未找到任何一個直接客戶端對 PG19 的明確通過證據。

<details markdown="1"><summary>展開：各服務的 driver、migration 與連線池細節</summary>

**Open WebUI：同一組 URL，可能不只一個 pool。** 已部署 runtime metadata 與固定 requirements 一致：SQLAlchemy 2.0.50、psycopg 3.3.4、psycopg2-binary 2.9.12、Alembic 1.18.4、Python pgvector client 0.4.2。**Python client 0.4.2 不是資料庫 extension 0.8.7。** 同步 engine、非同步 engine、vector engine 可能各有 pool；`PGVECTOR_DB_URL` 未設定時取 `DATABASE_URL`，本次兩者指到同一庫，但不代表 pool 合併。[requirements][OW-Requirements] [DB engines][OW-DB] [vector adapter][OW-PGVector]

Open WebUI 應用 migration 預設啟用；關掉 Alembic 不代表 vector 初始化完全不做 DDL。現行 adapter 遇到既有索引方法、向量維度或 Vector／HALFVEC 型別與設定不同，會拒絕自動重建／要求另處理資料，不能把切 env 當完整轉換。部署多副本時，schema migration 需協調單一程序，避免新舊 app 混跑。[官方部署][OW-Enterprise] [固定 vector 實作][OW-PGVector]

**New API：兩種 prepare 都已關閉，但 pool 上限仍需預算。** 固定 source 宣告 GORM 1.25.12、postgres driver 1.5.9、pgx/v5 5.9.2；本次未抽取 Go binary build info，所以它們是 source dependency 證據。此 revision 使用 `PreferSimpleProtocol: true` 並停用 GORM PrepareStmt。上游 fallback 的 `SQL_MAX_OPEN_CONNS=1000` 高於共用 PG 的 max_connections=100；本機環境未顯式覆寫這些 pool key。這表示**潛在上限不協調**，不是目前已開 1000 條連線或已經塞滿。[go.mod][NA-GoMod] [初始化][NA-Main] [GORM config][NA-Gorm]

New API 支援 `LOG_SQL_DSN`，可另拆日誌 DB；本機未設定，logs 目前與主 DB 共用。這是比新增向量服務更貼近容量現況的未來選項，但拆庫仍需資料搬移、備份與稽核需求，不能只改 DSN 丟下舊 logs。[固定初始化][NA-Main]

**Sub2API：不是 pgx，且 session lock 是真實限制。** 固定 source 為 Ent 0.14.5、lib/pq 1.10.9；主資料層明確使用 PostgreSQL dialect。migration 以 SQL 檔案及 checksum 為準，取得專用 sql.Conn 後使用 session-level `pg_try_advisory_lock`；`*_notx.sql` 可含不能包在一般 transaction 的 concurrent DDL。因此不任意修改已套用 migration，也不憑空假設應用有獨立 migration DSN 可切。[go.mod][S2-GoMod] [初始化][S2-DB] [runner][S2-Runner]

**Infinite Canvas：資料保全方向也要修正。** 當前 storage 是 browser localforage，不能把伺服器歷史 PG／`/app/data` 備份當成現行瀏覽器畫布的完整備份。若之後整理遺留部署，應另確認使用者端 export／儲存與歷史 DB 的去向；本次沒有讀取或匯出任何瀏覽器資料。同 revision 的文件有 Next.js 敘述與 Dockerfile 不一致，本報告優先採固定建置實作及本機 Nginx runtime 證據。[storage][IC-Storage] [Dockerfile][IC-Dockerfile]

</details>

### 其他服務：不要把 depends_on 當成 DB 相容性

| 服務 | 與本叢集的關係 | 專案處理方式 |
|---|---|---|
| Apache Tika | Compose 有 `depends_on` 指向 PG，但環境設定未見資料庫連線；Tika 是文件解析服務 | 視為編排相依，不把它列成 pgvector／PG major 限制；日後清理不必要的啟動耦合 |
| Lilac 兩個 persona | Compose 依賴 New API 與 Valkey，未發現直接 PG DSN | 驗收 API 路由、模型呼叫與串流；這次不搬它們的獨立資料 |
| AstrBot | Compose 依賴 New API，未發現直接 PG DSN | 驗收代理模型呼叫與 bot 回覆；不把它自己的儲存當成此 PG 的資料 |
| api-conversion | 明確設定 SQLite | 排除直接 DB 升級；仍驗收上下游 API 影響 |
| SillyTavern、CLI Proxy、CCR、cline-pass-switcher、Gluetun、Valkey | 本次掃描未發現直接使用此叢集的 DB 設定 | API／網路／快取可能有間接影響；不等於已證明所有 runtime 外掛都不連 PG |
| Immich、TeslaMate、Nextcloud、MetaMCP | 本機 runtime 顯示另有獨立 PostgreSQL 與連線目標 | 維持各自升級計畫；**不要借本次升級順便合庫** |
| `js_llmcord_rag`、`librechat_rag` | database 存在，當前 Compose 未見啟用的對應服務 | 納入備份與升級保全，待 owner 確認後才能歸檔 |

現行 Open WebUI 沒有對 PG 宣告 Compose `depends_on`；另外有的服務等待 `service_started`，也不等於資料庫已可接受連線。日後以 healthcheck＋應用 retry 處理啟動順序，但 healthcheck 不保證資料遷移成功。[Compose 啟動順序][compose-order]

## 除了 pgvector，有哪些選項 {#alternatives}

先區分兩層：**PostgreSQL 是帳號、聊天、用量、金流與設定的關聯式主庫；pgvector 是其中一種向量能力。** Qdrant 或 Milvus 不能直接接手 SQL 資料庫所有職責。更換向量後端只會搬向量相關資料，主庫通常仍然要保留。

| 選項 | 能替換哪一層 | 遷移／維運代價 | 本案判斷 |
|---|---|---|---|
| **維持 pgvector 0.8.7** | PostgreSQL 中的向量型別與索引 | 最少變更；保留 SQL、交易、權限與備份體系，仍需正確選索引與調 filter | **預設推薦**；已有資產、向量量小、沒有已證實的瓶頸 [官方說明](https://github.com/pgvector/pgvector) |
| **VectorChord 1.1.1** | 同 PostgreSQL 新增量化／向量索引能力，依賴 pgvector | 要換／建專屬索引、處理訓練、preload、二進位相容與 restore；沿用 vector 型別不等於 app 原生支援 | 量大且 RAM／磁碟壓力經證實才 PoC。當前官方 README 列 AGPLv3／Elastic License v2 雙授權，選定 release 另核對，不能沿用舊授權印象 [官方 repo](https://github.com/tensorchord/VectorChord) [release API](https://api.github.com/repos/tensorchord/VectorChord/releases/latest) |
| **pgvectorscale 0.9.1** | 在 pgvector 上新增 StreamingDiskANN／量化等能力 | SQL extension 名 vectorscale；索引與某些 filter／排序寫法不同，型別／維度需逐項確認 | 與 VectorChord 並列條件式 PoC，**不必因此安裝 TimescaleDB**；0.9.1 固定 manifest 列 PG14–18 [官方 repo](https://github.com/timescale/pgvectorscale) [固定 manifest](https://raw.githubusercontent.com/timescale/pgvectorscale/0.9.1/pgvectorscale/Cargo.toml) |
| **TimescaleDB／Tiger Cloud** | 時序擴充，或將 PG 維運轉成託管服務 | 新增 extension／PG 相容矩陣，或增加託管成本、延遲、匯出與備份限制 | 它與 pgvectorscale 是不同決策。除非需要時序查詢或外包運維，本案不導入 [官方版本矩陣](https://docs.tigerdata.com/self-hosted/latest/upgrades/upgrade-pg/) |
| **Qdrant** | 向量 sidecar，透過 API 操作 point／payload／filter | 新資料投影、collection、同步、snapshot／restore 與監控；主庫仍保留 | 若日後要獨立擴容，可先列 sidecar 候選；當前無必要 [官方定位](https://qdrant.tech/documentation/overview/what-is-qdrant/) [分散式部署](https://qdrant.tech/documentation/scaling/distributed_deployment/) |
| **Milvus** | 向量 sidecar，適合另行設計大規模檢索層 | 分散式模式涉及 coordinator／worker／metadata／WAL／object storage 等，部署成本看模式 | 服務已很多，本案沒有規模證據支持再引入這套架構 [官方架構](https://milvus.io/docs/architecture_overview.md) |
| **Weaviate** | 以 collection／object API 提供向量與 BM25 hybrid search | schema／API／權限投影、一致性、備份與同步需設計 | 只有其 hybrid／模型整合直接對應產品需求才評估 [官方 hybrid search](https://docs.weaviate.io/weaviate/search/hybrid) [replication](https://docs.weaviate.io/weaviate/concepts/replication-architecture) |
| **OpenSearch** | 全文／向量搜尋 sidecar | mapping、分析器、shard、pipeline、refresh 延遲、投影與刪除同步 | 已有搜尋運維體系或強全文需求時合理；不為升 PG 而新增 [官方 vector search](https://docs.opensearch.org/latest/vector-search/) |
| **MySQL／MariaDB** | 更換部分應用的關聯式 store；向量能力另看產品／版本 | SQL、JSONB、driver、migration、型別與索引都變；各 app 支援不一 | 不作本案共用 PG 的原位替換。不能只因 MySQL 有 VECTOR 就推論普通版有等價 ANN；查到的 DISTANCE 文件有產品限制。Open WebUI 的 mariadb-vector adapter 也不代表其他服務都可遷 [MySQL 官方文件](https://dev.mysql.com/doc/refman/9.7/en/vector-functions.html) |
| **SQLite＋sqlite-vec** | 嵌入式的新資料層 | 單 writer、權限／部署模式、extension API 與資料轉換均不同；sqlite-vec 仍 pre-v1 | 新單機／離線產品可考慮；不把現有多服務 server 架構當成低成本升級 [SQLite 用途](https://www.sqlite.org/whentouse.html) [sqlite-vec](https://github.com/asg017/sqlite-vec) |

VectorChord 與 pgvectorscale 的「保留 PG」路線也不是只換 image。Open WebUI 的 pgvector adapter 會自行判斷／管理 IVFFlat、HNSW 與相關 GUC；自訂索引是否被忽略、覆寫或判斷錯誤，都要在固定 app revision 下驗證。LibreChat 舊表的無 typmod `vector` 也不能假定可直接建立 DiskANN；0.9.1 對維度有效性有明確限制。[pgvectorscale release notes](https://github.com/timescale/pgvectorscale/releases)

若走 sidecar，除了重匯向量，必須設計**可靠同步、刪除與撤權、讀寫時序、復原對帳、回退**。可用經驗證的 outbox／CDC 搭配冪等 upsert，保存 document／chunk ID、embedding model/version、tenant／ACL 版本與重建 watermark。把 PG 與 sidecar 各備份一份，不代表兩邊會還原到同一業務時間點；不能只更改 Open WebUI `VECTOR_DB` 就期待舊 collection 自動搬完。

### 什麼情況才值得重開向量引擎選型？

不是「數量達到某個神奇門檻」就換。當真實語料下，已調整索引／filter／連線後仍無法滿足已定義的 p95 延遲、Recall@k、寫入速度、RAM 或備份時間預算，再對替代方案做可重現 PoC。對本次僅 149 筆已知現存向量的情況，新增一套向量服務會先增加備份、監控、資料同步與故障點。

PoC 至少固定 embedding model、維度、distance metric、查詢集、top-k、metadata filter、硬體與 warm/cold cache；以 exact search 結果作 recall ground truth，連同索引建置時間、刪除後可見性、備份還原、混合讀寫與失敗重試一起測。不同廠商宣傳的倍數不能直接套用。

## 優化選項：按證據排序 {#optimization}

### 先做可靠性與量測

| 優先度 | 建議 | 本次依據 | 演練／驗收方式 |
|---|---|---|---|
| P0 | 建立 DB-aware 備份、異機副本與還原紀錄 | 未驗證可用還原點；WAL archive 未開 | 對空白隔離叢集還原所有 DB、roles、extensions，驗證完整性與應用流程 |
| P0 | 查 NFS server `sync` export、掉電保護與 fsync latency | PGDATA 是 NFS；client hard 已確認，server export 未查 | 請儲存端查實際設定；演練故障與 restore，不能在生產上壓力測試 |
| P0 | 固定 DB、三個直接客戶端與相關服務 image digest | 有 latest、main-ollama、未標版本映像 | 保存 compose／digest／extension inventory；演練重啟不自動換軟體 |
| P1 | 使用 pg_stat_statements，補 slow query／I/O 觀測 | 現在缺少按 query 的 latency 與 I/O 基線 | 未來排程重啟啟用 preload；研究階段不動。報表遮蔽 query literals、限制可讀權限 |
| P1 | 訂定日誌留存與查詢策略 | New API logs 與 Sub2API ops logs 占主要空間 | 依服務既有保留機制處理，先定 audit／billing 保全需求；不要直接 DELETE 生產表 |
| P1 | 各服務獨立非 superuser 帳號 | 多服務共用管理員；停機影響集中 | 權限與 schema ownership 在副本測試；migration 與 runtime 權限視需求分開 |
| P1 | 觀測後再調連線池與記憶體 | 目前接近預設配置、單次連線數低 | 收集至少一個完整尖峰週期，驗證 latency／error／RSS／I/O 差異 |
| P2 | 向量索引與壓縮 PoC | 已知現存向量量很小 | 以 retrieval 品質與真實 workload 決定；不是為了升版而加索引 |

**NFS 可以承載 PostgreSQL，不應直接貼上「不支援」的標籤。** 官方要求它呈現正確的持久化行為；建議 client hard mount，並查 server 端 sync export。client mount 的 sync／async 與 server export 是不同層級；只看 client 設定不能證明 server 已保證 fsync 持久化。若比較本地 SSD，應將 PGDATA 放到新路徑、保留舊庫與異機備份，以演練數據決定；不能在執行中的資料目錄直接搬檔。[PostgreSQL 的 NFS 說明][nfs]

### 一組可供副本演練的資源起點

下列是針對這個約 10 GiB、小量向量、混合服務環境的**工程假設**，不是已測得的最佳值。先為 DB 訂出約 8–12 GiB 的實際資源預算，並為同機模型、其他容器與 OS cache 留空間；目前 snapshot 不足以承諾這個預算一定適合。

| 參數 | 現況 | 副本可比較的候選 | 注意事項 |
|---|---:|---|---|
| shared_buffers | 128 MiB | 1 GiB vs 2 GiB | 重啟項；不能按整台共享主機 RAM 直接套 25% |
| effective_cache_size | 4 GiB | 4–6 GiB | 只是 planner 對可用 cache 的估計，不是預留 RAM |
| work_mem | 4 MiB | 全域先維持；特定報表 session 比較 8–16 MiB | 每個 sort/hash operation、worker 與併發都會放大總使用量 |
| maintenance_work_mem | 64 MiB | 維護 session 256–512 MiB | 注意同時維護與 autovacuum 的總預算；不是先全域加到數 GiB |
| max_connections | 100 | 暫維持；先設定各 app 的 pool 上限 | 不因 CPU 多就增加；總 pool／overflow／workers 必須留管理連線 |
| max_wal_size | 1 GiB | 量測後比較 2–4 GiB | 影響 checkpoint 節奏與磁碟需求；不是 WAL 的硬上限 |
| Docker shm_size | 64 MiB | 若有平行查詢／索引需求，比較 256 MiB–1 GiB | 與 shared_buffers 不是同一容量；會占用實際記憶體 |
| random_page_cost、effective_io_concurrency | 4、1 | 先保留 | NFS 延遲與儲存端未知，不直接套用本地 NVMe 參數 |
| fsync／full_page_writes／synchronous_commit | on／on／on | 維持可靠寫入 | 不以關閉它們換取表面吞吐量 |

記憶體粗估需同時計入 shared_buffers、後端基礎成本、併發 operation × work_mem × worker、hash multiplier、維護作業及 OS cache；`effective_cache_size` 不應再算作實際分配。官方 25% buffers 建議以 dedicated server 為前提。[PostgreSQL 記憶體設定][memory]

### 連線池與啟動遷移

先在應用層設定保守的 pool／overflow／worker 預算；Open WebUI 的同步、非同步與 pgvector engine 可能各自連線，不能只算一個。增加 PgBouncer 以前，確認 prepared statements、LISTEN、session-level advisory locks、session SET、temporary tables 與 migrations 的實際使用方式。**Sub2API 的啟動 migration 已確認使用 session advisory lock；不能直接放到 transaction pooling 後面就宣稱安全。** 新版本 PgBouncer 可在特定設定下處理 protocol-level prepared plans，不等於 transaction pooling 完全相容所有 session 功能。[PgBouncer 功能矩陣][pool] [Sub2API runner][S2-Runner]

本次取樣的 DB 連線 `application_name` 大多空白。日後加上服務識別並記錄 pool wait、連線尖峰、active／idle in transaction，會比先加一個代理更有利於定位問題。migration 可考慮單獨直連通道；是否可行需依各服務啟動機制測試。

### 向量與大表的具體選項

- **HNSW / IVFFlat / exact search**：HNSW 不需要 IVFFlat 的訓練階段，但建索引與記憶體成本可能較高；IVFFlat 需要足夠、有代表性的資料。0 或 149 筆不值得以大型 ANN 預設值決策。新增索引也不保證 planner 一定使用。[pgvector][pgvector]
- **metadata filter 與 iterative scan**：ANN 通常在取出候選後套 filter，容易少於 top-k。pgvector 0.8 起提供 iterative scan，但仍受 scan budget 影響；可比較 partial index、必要的 B-tree filter index 與增加探索量，並測品質與延遲。[pgvector][pgvector]
- **halfvec / 量化**：只有真實向量 RAM／索引已成瓶頸時再做 recall 對照。1536 維向量目前不需要為了維度限制轉型；Open WebUI 型別與 schema 也不應只改 env 便期待舊資料自動轉換。[pgvector][pgvector]
- **embedding 一致性**：升級 PG 不需要重算 embedding；換 model、維度或 distance metric 才可能需要重建語料。即使兩個 model 都是 1536 維，也不代表向量空間可混用。先備份原文、chunk ID、metadata、model 與版本，再評估重新嵌入成本。
- **聊天／日誌大表**：區分 heap、index、TOAST、retention 與 bloat；本次只看 catalog 大小，沒有證實 bloat。不先做 VACUUM FULL、全表重寫、partitioning 或改 app 自管 schema。新 schema 是否被下次 migration 覆寫也要先測。

## 建議的升級與回復路線 {#roadmap}

這是後續執行專案的提案，**本次未建立升級副本、未跑 pg_upgrade、未產生業務資料 dump，也未排程停機**。

### 各種資料轉換方法

| 方法 | 優點 | 成本／限制 | 對本案的建議 |
|---|---|---|---|
| 邏輯 dump / restore 到新叢集 | 乾淨、容易隔離與驗證；舊叢集可保留 | 重新建立索引，時間需量測；要處理 roles、ownership、extensions 與跨 DB 一致性 | **首選演練基線**，約 10 GiB 且停機要求未定，不先引入複寫複雜度 |
| pg_upgrade 的 copy 模式 | 減少重載資料的工作；較適合已測得 restore 太久的情況 | 要同時提供兩版 binaries 與相容的 extension library，通過 check；glibc／collation 仍要處理 | 第二候選；仍須測服務與備份 |
| pg_upgrade 的 link 模式 | 可減少複製時間與額外空間 | 新舊庫共用檔案；新庫啟動後舊庫不可當成安全回復點 | 本案初次演練不優先，避免把「保留舊目錄」誤當可回復 |
| 邏輯複寫切換 | 可縮短最後停寫窗口 | schema／DDL、sequence、extension、replica identity、large object 及回切另有工作；目前 wal_level 不是 logical | 只有 restore 演練未達業務 RTO 才另案設計；不是零停機保證 |
| 原地換 image tag | 操作看似少 | 沒有做資料格式轉換，major 不相容 | 不採用 |

方法限制依 [PostgreSQL 升級文件][upgrade]、[pg_upgrade][pgupgrade]、[邏輯複寫限制][logical]。`pg_upgrade --check` 只能檢查部分 cluster 相容性，不是應用相容性證明。

### 四個階段，逐關放行

1. **建立保全基線**：固定 DB／服務 digest、保存 schema、extension、roles、ownership、locale、volume 與設定清單；查明每個舊 database 的 owner；定出可接受資料遺失與停機時間。建立可驗證還原點，包含 DB 與 Open WebUI 外部附件的相容快照；Canvas 的瀏覽器儲存則另確認 export 保全，不把歷史 PG 當成全部畫布資料。
2. **17 分支整理演練**：先做 17 同 major 的還原演練，再測逐庫 pgvector 更新與既有索引行為。正式是否更新 17 minor，以當時查得版本與公告決定。保持應用程式不升版。
3. **18 隔離副本演練**：新目錄、新 container、新連線入口；固定 OS 基底／locale；先確認可用 vector、pg_trgm、uuid-ossp，再 restore。檢查 collation、索引、constraint、sequence、large objects 與 schema migrations；重建統計後量測 warm／cold cache。副本必須斷開真實 API／webhook／排程／郵件等副作用。
4. **切換方案另案批准**：全體直接寫入者與會重試的背景工作先 quiesce；取得一致的最後資料與檔案備份；切換 alias／DSN，按序啟動並驗收。外部消費者、connection pools、排程與 API 路由都要列入。舊叢集保留為唯讀／離線保全，不讓新舊兩邊同時接寫入。

不同 database 各自 `pg_dump` 的 snapshot 並不是整個 cluster、所有服務與檔案的共同時間點。若 New API 與 Sub2API 都涉及用量與扣款，必須定義跨服務業務一致性，最後 cutover 時停止所有寫入與重試，不能只停止前端。[SQL dump][dump] [檔案層備份限制][backup-file]

### 回復界線，必須在切換前寫清楚

**新庫尚未接收正式寫入**：停止新庫，恢復舊 DSN／alias 與原版應用映像，確認舊庫仍保持原資料，再驗收。這是最簡單的回復窗口。

**新庫已接收正式寫入**：舊庫已經落後，直接指回舊庫會遺失新聊天、用量／扣款與設定。應先停寫，依事先約定的資料接受損失範圍，選擇前向修復、經驗證的資料回補，或可驗證的反向同步。跨 major 不能假設可用新版本 dump 無痛還原到舊版本；沒有設計就不要宣稱「一鍵 rollback」。[SQL dump 的版本相容性][dump]

PITR 是用對應 major 的 base backup＋連續 WAL 回復到時間點，不是用 18 的 WAL 去回復 17，也不會自動解決跨 major 的雙向同步。執行中的 PGDATA 若只被一般檔案備份逐檔掃描，不能直接視為一致、可還原的資料庫備份。[PostgreSQL 備份方法][backup] [檔案備份條件][backup-file]

## 驗收清單與待決事項 {#acceptance}

### 進入正式升級前的最低驗收

| 驗收面向 | 應留下的證據 |
|---|---|
| 資料完整性 | 7 個非 template DB 都有去向；schema／tables／extensions／ownership 清單；必要的 row counts 與抽樣結果相符；向量目前 0／149／0 的基線；sequence 不倒退；大型物件／檔案關係確認 |
| New API | 登入、既有 channel／token 的非敏感摘要、模型路由與串流、用量／配額、日誌查詢、背景任務與重試；副本不發真實扣款請求 |
| Sub2API | 登入、帳號排程、API key 驗證、trigram 搜尋、用量統計、去重與 outbox 行為、管理頁面；禁止用副本刷新真實外部憑證 |
| Open WebUI | 登入、既有對話讀寫、附件／圖片資產、串流、刪除與搜尋；用隔離測試 corpus 驗證 RAG ingest／filter／retrieval，不把空向量表誤判為 RAG 已驗收 |
| Infinite Canvas／歷史庫 | 歷史 PG schema 與資料保全；現行 browser 儲存、畫布與 prompt export 另驗證。它不是 PG 連線相容性測試的直接客戶端；真實 provider 呼叫避免由測試副本觸發 |
| 間接服務 | Lilac 與 AstrBot API 路徑、串流與錯誤重試；Tika 文件解析；其餘代理服務冒煙測試 |
| 效能與容量 | 同工作負載下 p50／p95／p99、error、pool wait、RSS、WAL、checkpoint、lock、NFS latency、restore／reindex 時間；沒有用單次 docker stats 冒充長期基線 |
| 回復 | 未接寫入回切演練成功；接寫入後的處理政策寫明；最後驗收者、停機公告與重試順序確定 |

效能門檻尚無使用者 SLO，不捏造「通過」數值。可先提議：錯誤率不增加、資料完整性零未解釋差異、p95 相較同硬體基線退步不超過 10% 作為待確認的驗收假設；若 workload 波動大，需重複量測與適當區間，不以單次結果判定。

### 我建議你接下來決定的五件事

1. **停機容忍度**：能否接受一次經演練量測後的維護窗口？若只能接受極短停機，才投入邏輯複寫方案。
2. **資料遺失容忍度**：聊天、帳務用量與畫布各自的 RPO／RTO 是多少？需要幾分鐘級 PITR，還是備份週期即可？尚未替你假設數字。
3. **儲存位置**：保留 NFS 並驗證持久性，或另測本地 SSD＋NAS 異機備份？先取得 latency 與 restore 證據。
4. **舊資料庫 owner**：llmcord 與 LibreChat 是否仍有外部客戶端？確認前完整保全，這次不清除。
5. **隔離粒度**：短期用每服務獨立 DB／role／pool 預算；若聊天與日誌負載確實互相干擾，再測分成兩個 PG instance。別因有多服務就立刻每服務一套 DB，也別因想減少容器就把其他產品的 PG 一起合併。

## 研究限制與來源 {#sources}

### 證據分級

- **實測現況**：本機 Compose、容器 metadata、catalog、設定與有時間限制的 metadata／count 查詢；採樣時間約 2026-10-31 17:12–17:15（台北）。它不是長期效能監控。
- **官方明文**：已取回的 PostgreSQL、pgvector、Docker 文件與服務官方 repo；能證明文件／程式碼所述內容，不等於證明已在這台機器通過 PG18 驗收。
- **程式碼推論**：由 driver、ORM、migration 與 compose 推得的相容性／操作風險，會明確保留驗證條件；官方範例使用 PG15／16／17，不等於最低版本或最高支援版本。
- **尚待驗證**：尖峰負載、外部客戶端、備份可還原性、NAS server export／掉電保護、各服務 PG18 全流程相容性與可接受的停機時間。

掃描範圍是這台 Docker 主機的容器設定與當下連線；未搜尋所有主機、所有 cron、外部工作站或所有 plugin 設定，不能宣稱客戶端清單絕對完整。未執行升級／restore／benchmark，所以沒有成功率、耗時或加速倍數的實測承諾。網頁版本與發布資訊以本次實際取得內容為準，不用日曆推測未發布版本。

### 官方來源索引

完整版本與替代引擎 primary sources 台帳另見同站 sources.html；它包含官方版本表、固定 tag、release API 與文件落差紀錄。PostgreSQL 與 pgvector 版本查核採官方實際內容：PG19 仍為 RC、pgvector tags 有 0.8.7 即使 Releases 頁未建立 release、VectorChord suite 的舊版本表不能與當前 extension release 混用。

| 主題 | 來源 |
|---|---|
| NFS 持久性與 cluster | [PostgreSQL：Creating a database cluster][nfs] |
| 記憶體參數 | [PostgreSQL 17：Resource consumption][memory] |
| 統計估計與 metadata | [PostgreSQL 17：Statistics collection][stats] |
| 按 query 的效能觀測 | [PostgreSQL：pg_stat_statements][pgss] |
| 備份方法 | [PostgreSQL：Backup and restore][backup] |
| 檔案備份一致性 | [PostgreSQL 17：File system level backup][backup-file] |
| SQL dump、版本與跨 DB 注意事項 | [PostgreSQL：SQL dump][dump] |
| 主版本升級 | [PostgreSQL：Upgrading a cluster][upgrade] |
| pg_upgrade 限制 | [PostgreSQL：pg_upgrade][pgupgrade] |
| 邏輯複寫限制 | [PostgreSQL：Logical replication restrictions][logical] |
| 官方映像與 PGDATA | [Docker PostgreSQL Official Image][dockerpg] |
| 向量型別／索引／升級 | [pgvector 官方 repository][pgvector] |
| 連線池限制 | [PgBouncer：Features][pool] |
| 啟動順序 | [Docker Compose：Control startup order][compose-order] |

研究命令使用 `smart-search fetch <官方 URL> --format markdown --output <evidence file>` 與 source-focused search；本地 raw 證據另存、不公開。此報告的版本、數據與提案均應在真正執行前重新查核。

[nfs]: https://www.postgresql.org/docs/current/creating-cluster.html
[memory]: https://www.postgresql.org/docs/17/runtime-config-resource.html
[stats]: https://www.postgresql.org/docs/17/monitoring-stats.html
[pgss]: https://www.postgresql.org/docs/current/pgstatstatements.html
[backup]: https://www.postgresql.org/docs/current/backup.html
[backup-file]: https://www.postgresql.org/docs/17/backup-file.html
[dump]: https://www.postgresql.org/docs/current/backup-dump.html
[upgrade]: https://www.postgresql.org/docs/current/upgrading.html
[pgupgrade]: https://www.postgresql.org/docs/current/pgupgrade.html
[logical]: https://www.postgresql.org/docs/current/logical-replication-restrictions.html
[dockerpg]: https://hub.docker.com/_/postgres
[pgvector]: https://github.com/pgvector/pgvector
[pool]: https://www.pgbouncer.org/features.html
[compose-order]: https://docs.docker.com/compose/how-tos/startup-order/


[OW-Requirements]: https://github.com/open-webui/open-webui/blob/f7ac7ee10962ddec0017f5c29b6740d9b9c5faca/backend/requirements.txt
[OW-DB]: https://github.com/open-webui/open-webui/blob/f7ac7ee10962ddec0017f5c29b6740d9b9c5faca/backend/open_webui/internal/db.py
[OW-Env]: https://github.com/open-webui/open-webui/blob/f7ac7ee10962ddec0017f5c29b6740d9b9c5faca/backend/open_webui/env.py
[OW-Config]: https://github.com/open-webui/open-webui/blob/f7ac7ee10962ddec0017f5c29b6740d9b9c5faca/backend/open_webui/config.py
[OW-Alembic]: https://github.com/open-webui/open-webui/blob/f7ac7ee10962ddec0017f5c29b6740d9b9c5faca/backend/open_webui/migrations/env.py
[OW-PGVector]: https://github.com/open-webui/open-webui/blob/f7ac7ee10962ddec0017f5c29b6740d9b9c5faca/backend/open_webui/retrieval/vector/dbs/pgvector.py
[OW-Factory]: https://github.com/open-webui/open-webui/blob/f7ac7ee10962ddec0017f5c29b6740d9b9c5faca/backend/open_webui/retrieval/vector/factory.py
[OW-CI]: https://github.com/open-webui/open-webui/blob/f7ac7ee10962ddec0017f5c29b6740d9b9c5faca/.github/workflows/backend.yaml
[OW-DBDocs]: https://docs.openwebui.com/reference/env-configuration/
[OW-Enterprise]: https://docs.openwebui.com/enterprise/deployment/
[OW-Scaling]: https://docs.openwebui.com/getting-started/advanced-topics/scaling/
[NA-README]: https://github.com/QuantumNous/new-api/blob/e835b1bfc43b565d625537830dbfb19328925134/README.md
[NA-GoMod]: https://github.com/QuantumNous/new-api/blob/e835b1bfc43b565d625537830dbfb19328925134/go.mod
[NA-Main]: https://github.com/QuantumNous/new-api/blob/e835b1bfc43b565d625537830dbfb19328925134/model/main.go
[NA-Gorm]: https://github.com/QuantumNous/new-api/blob/e835b1bfc43b565d625537830dbfb19328925134/model/gorm_logger.go
[NA-Dialect]: https://github.com/QuantumNous/new-api/blob/e835b1bfc43b565d625537830dbfb19328925134/model/migration_dialector.go
[NA-Locking]: https://github.com/QuantumNous/new-api/blob/e835b1bfc43b565d625537830dbfb19328925134/model/locking.go
[NA-Compose]: https://github.com/QuantumNous/new-api/blob/e835b1bfc43b565d625537830dbfb19328925134/docker-compose.yml
[NA-CI]: https://github.com/QuantumNous/new-api/blob/e835b1bfc43b565d625537830dbfb19328925134/.github/workflows/ci.yml
[S2-README]: https://github.com/wei-shaw/sub2api/blob/dece26153621959ccd7635814f4b2d08304e681a/README.md
[S2-GoMod]: https://github.com/wei-shaw/sub2api/blob/dece26153621959ccd7635814f4b2d08304e681a/backend/go.mod
[S2-DB]: https://github.com/wei-shaw/sub2api/blob/dece26153621959ccd7635814f4b2d08304e681a/backend/internal/repository/ent.go
[S2-Runner]: https://github.com/wei-shaw/sub2api/blob/dece26153621959ccd7635814f4b2d08304e681a/backend/internal/repository/migrations_runner.go
[S2-Pool]: https://github.com/wei-shaw/sub2api/blob/dece26153621959ccd7635814f4b2d08304e681a/backend/internal/repository/db_pool.go
[S2-Init]: https://github.com/wei-shaw/sub2api/blob/dece26153621959ccd7635814f4b2d08304e681a/backend/migrations/001_init.sql
[S2-Trgm]: https://github.com/wei-shaw/sub2api/blob/dece26153621959ccd7635814f4b2d08304e681a/backend/migrations/065_add_search_trgm_indexes.sql
[S2-Tests]: https://github.com/wei-shaw/sub2api/blob/dece26153621959ccd7635814f4b2d08304e681a/backend/internal/repository/integration_harness_test.go
[S2-Compose]: https://github.com/wei-shaw/sub2api/blob/dece26153621959ccd7635814f4b2d08304e681a/deploy/docker-compose.yml
[S2-CI]: https://github.com/wei-shaw/sub2api/blob/dece26153621959ccd7635814f4b2d08304e681a/.github/workflows/backend-ci.yml
[IC-Dockerfile]: https://github.com/basketikun/infinite-canvas/blob/3a6b64b602ad062b29fac66902ed18a7ef5fd9dc/Dockerfile
[IC-Package]: https://github.com/basketikun/infinite-canvas/blob/3a6b64b602ad062b29fac66902ed18a7ef5fd9dc/web/package.json
[IC-Entrypoint]: https://github.com/basketikun/infinite-canvas/blob/3a6b64b602ad062b29fac66902ed18a7ef5fd9dc/web/docker-entrypoint.sh
[IC-Storage]: https://github.com/basketikun/infinite-canvas/blob/3a6b64b602ad062b29fac66902ed18a7ef5fd9dc/web/src/lib/localforage-storage.ts
[IC-Compose]: https://github.com/basketikun/infinite-canvas/blob/3a6b64b602ad062b29fac66902ed18a7ef5fd9dc/docker-compose.yml
[IC-Doc]: https://github.com/basketikun/infinite-canvas/blob/3a6b64b602ad062b29fac66902ed18a7ef5fd9dc/docs/content/docs/overview/docker.mdx
[IC-README]: https://github.com/basketikun/infinite-canvas/blob/3a6b64b602ad062b29fac66902ed18a7ef5fd9dc/README.md
[TIKA-Docker]: https://github.com/apache/tika-docker/blob/main/README.md
[AC-README]: https://github.com/ChinRain/api-conversion/blob/main/README.md
[PV-README]: https://github.com/pgvector/pgvector/blob/master/README.md
[PGB-Features]: https://www.pgbouncer.org/features.html
[PSY-Prepare]: https://www.psycopg.org/psycopg3/docs/advanced/prepare.html
