# ChatStack 服務 PostgreSQL 需求與遷移行為研究

查核日期：2026-10-31（工作環境日期；不是以日期推定任何 release 已存在）。研究範圍為官方文件、官方 GitHub 原始碼，以及本機 compose／容器的設定與版本 metadata。**沒有升級、重啟、重建或變更任何服務；沒有執行 SQL、migration、資料匯出或讀取使用者內容。**

## 1. 可供父代理採用的結論

1. **需修正「四個實際直接 PG 使用者」的前提。** Open WebUI、new-api、sub2api 的設定與對應原始碼能互相印證直接使用共用 PostgreSQL。infinite-canvas 雖仍帶有 `STORAGE_DRIVER=postgres`、`DATABASE_DSN` 與 `depends_on`，**目前執行映像卻是 Vite 靜態產物＋Nginx**；對應 revision 不建置 Go／資料庫後端，啟動腳本只處理統計分析設定。不能把遺留 DSN 當成目前實際 PG 連線的證明，也不能因此刪除歷史 `infinite_canvas` 資料庫。[IC-Dockerfile] [IC-Entrypoint] [IC-Storage]
2. **明文 major 下限只有 new-api 的 PostgreSQL ≥ 9.6、sub2api 的 PostgreSQL 15+。** 本次查到的 Open WebUI 官方文件支持 PostgreSQL，但沒有明列應用層最低或推薦 major。pgvector 自己的 PostgreSQL 13+ 要求屬 extension 層，不得改寫成 Open WebUI 官方最低 major。[NA-README] [S2-README] [OW-DBDocs] [PV-README]
3. **PG18 證據最明確的是 sub2api：** 對應 revision 的官方 compose 用 `postgres:18-alpine`，整合測試 harness 固定 `postgres:18.1-alpine3.23`，CI 會呼叫整合測試。這能確認「官方已把 PG18 納入部署範例與測試路徑」，**本次沒有讀取該 revision 的成功 CI 執行紀錄，不能說已親自驗證通過**。其餘服務沒有找到對應部署 revision 的 PG18 通過證據；四者都沒有找到 PG19 明確通過證據。未知不等於不相容。[S2-Compose] [S2-Tests] [S2-CI]
4. **Open WebUI 的兩種資料庫用途須分開處理。** `DATABASE_URL` 儲存應用資料；`PGVECTOR_DB_URL` 儲存向量，未設定時預設取 `DATABASE_URL`。本機容器未顯式設 `PGVECTOR_DB_URL`，所以目前兩者落在 `openwebui_db`，但它們可以指向不同資料庫／伺服器，而且建立各自的連線池。只搬應用 tables、只改 `DATABASE_URL`，或只換 `VECTOR_DB` 都不足以代表知識庫向量已遷移。[OW-Config] [OW-PGVector] [OW-Factory]
5. **不宜為了更換 PG major 同時替換應用 DB 類型／vector backend。** new-api 有 MySQL／SQLite 官方後端；Open WebUI 有 SQLite 官方後端但仍須另處理 pgvector；sub2api 在此 revision 的主應用儲存路徑明確寫死 PostgreSQL。跨 DB 的型別、流水號、索引、資料轉換與驗證屬另一個遷移專案。[NA-Main] [OW-DBDocs] [S2-DB] [S2-Init]
6. **connection pooler 不是只看 prepared statement。** new-api 此 revision 主動關閉 PG 的 pgx 隱式 prepared statements 與 GORM `PrepareStmt`；Open WebUI async 路徑使用 psycopg 3，需按實際 pooler／libpq 組合判斷。sub2api migration 使用 session advisory lock，無法因 prepared statement 已處理就宣稱 transaction pooling 安全。[NA-Main] [NA-Gorm] [OW-DB] [S2-Runner] [PGB-Features] [PSY-Prepare]

## 2. 證據標記與實際版本

- **確認**：官方文件明文，或已讀取對應映像 revision 的實作，或唯讀取得的本機 metadata。確認範圍以句子所述為限。
- **推測／推論**：從已確認實作推導出的遷移代價、風險或架構判斷；不是官方支援承諾。
- **未知／未找到**：未取得明文、完整覆蓋或實際通過紀錄。不能據此宣稱不支援。
- Docker 範例的 `postgres:15`／`:18` 是範例選擇，**不是只支援該 major 的證據**。driver 可以連某版，也不等於應用 migration 與所有 SQL 已驗證。

本機唯讀證據：`evidence/service-local-image-metadata.json`、`evidence/service-local-runtime-safe.json`、`evidence/service-local-version-metadata.json`、`evidence/service-local-compose-safe.json`。只保留映像 metadata、去除憑證的 DB 位址／名稱及允許的設定；沒有保存 compose 全文、密碼或使用者資料。

| 服務 | 本機映像 reference | OCI version 標籤 | 固定 source revision |
| --- | --- | --- | --- |
| Open WebUI | `ghcr.io/open-webui/open-webui:ollama` | `main-ollama`，不宣稱為某 release 版 | `f7ac7ee10962ddec0017f5c29b6740d9b9c5faca` |
| new-api | `calciumion/new-api:latest` | `v1.0.0-rc.47` | `e835b1bfc43b565d625537830dbfb19328925134` |
| sub2api | `ghcr.io/wei-shaw/sub2api` | `0.2.19` | `dece26153621959ccd7635814f4b2d08304e681a` |
| infinite-canvas | `ghcr.io/basketikun/infinite-canvas:latest` | `v0.20.0` | `3a6b64b602ad062b29fac66902ed18a7ef5fd9dc` |
| Tika | `apache/tika:latest-full` | `4.2.0` | `91361891b61f6cc043a5ea81ced4867c17b93a9c` |

**確認**：`docker exec … postgres --version` 回傳 PostgreSQL **17.11**，image reference 為 `pgvector/pgvector:pg17`。這只是伺服器 binary 版本；本次未查 SQL `server_version`、各 DB 的 `pg_extension`、schema revision 或活躍連線，因此**尚不知道安裝中的 vector extension 版本、每個 DB 目前 extension 清單及歷史 migration 狀態**。OCI 標籤是本機 metadata，不是供應鏈簽章驗證。

## 3. 直接、間接與僅啟動順序的依賴

| 服務 | 本地設定與官方實作對照 | 本次判定 |
| --- | --- | --- |
| Open WebUI | `DATABASE_URL` → 共用 PG17 的 `openwebui_db`；`VECTOR_DB=pgvector`；runtime 沒有顯式 `PGVECTOR_DB_URL` | **確認**：應用與向量兩用途都配置在 PG；是否此刻持有活躍連線未查。 |
| new-api | `SQL_DSN` → 共用 PG17 的 `veloera_db`；映像／source 是 QuantumNous/new-api | **確認**：直接 PG 應用；`veloera_db` 是歷史資料庫命名，**不是 Veloera 映像或相容性證據**。 |
| sub2api | `DATABASE_HOST` → 共用 PG17；DB `sub2api`；Ent 初始化 PostgreSQL dialect | **確認**：直接 PG 應用。[S2-DB] |
| infinite-canvas | 設定仍指 `infinite_canvas`，但當前映像只啟動 Nginx；官方 Dockerfile 只 copy 前端 `dist`，entrypoint 不讀 DSN | **確認設定遺留；依映像實作推論目前不直接使用 PG**。歷史 DB 是否仍有需保留內容未知，不能刪庫。[IC-Dockerfile] [IC-Entrypoint] |
| Tika | compose `depends_on` PG，但無 DB env；官方 Tika image 可單獨啟動 REST extraction server，基本端點不要求 PostgreSQL | **確認**：`depends_on` 只能證明啟動順序；不是 Tika 核心 PG 需求。自訂 pipes／外掛／掛載設定未做完整盤點。[TIKA-Docker] |
| lilac-catalina、lilac-claudia | `ghcr.io/df-wu/lilac-mono` 兩 persona；依賴 new-api／Valkey，沒有本次辨識的 PG env | **確認 compose 拓撲**：new-api 停機會間接影響上游 API；不是已證明的直接 PG client。 |
| AstrBot | `depends_on new-api`，沒有本次辨識的 PG env | 同上，間接受 new-api 可用性影響。 |
| api-conversion | 本地無本次辨識的 PG env；官方文件預設 `DATABASE_TYPE=sqlite`、`data/channels.db`，可另選 MySQL | **確認官方預設 SQLite；本機 SQLite 屬任務提供的部署前提，未讀取 DB 內容或額外設定檔**。[AC-README] |
| SillyTavern | 本地無本次辨識的 PG env，也未直接依賴 PG service | **確認 compose 範圍無直接 PG 證據**；未全面稽核應用外掛／私有設定。 |

`depends_on` 不等於應用依賴，更不代表 schema／extension 要求；沒有 DB env 也不構成「任何外掛都絕不會連 DB」的證明。本報告以任務範圍內的部署與官方標準實作分類。

## 4. 各服務的 PostgreSQL major 支援證據

| 服務／元件 | 明文最低 major | 明文推薦 major | 範例或測試用 major | PG18／PG19 驗證程度 |
| --- | --- | --- | --- | --- |
| Open WebUI | **未知**：文件明列 SQLite／Postgres，但所查來源沒有 major 下限 | **未知**：推薦在多副本使用 PostgreSQL；未指定 major | 所查 CI 沒有 PG major matrix | PG18：未取得應用與 pgvector 組合通過證據；PG19：未找到。[OW-DBDocs] [OW-Enterprise] [OW-CI] |
| pgvector extension（獨立於應用） | **確認 Postgres 13+**，以查得 README 為準 | 未找到推薦 major | README 列出 PG13–18 的 Docker tags，包含 `pg18` | **確認官方提供 PG18 artifacts**；不能外推 Open WebUI 已通過；未找到 PG19 tag／測試證據。[PV-README] |
| new-api | **確認 PostgreSQL ≥ 9.6**（README 的主 DB requirements） | 未找到推薦的 PostgreSQL major；外部 DB 的推薦與 major 是兩回事 | 固定 revision compose 用 `postgres:15` | PG18、PG19：未取得該應用 revision 明確通過紀錄；主 CI 檔沒列 PG major matrix。[NA-README] [NA-Compose] [NA-CI] |
| sub2api | **確認 PostgreSQL 15+**（README、初始化 SQL 都明列） | 未找到「推薦 major=18」明文 | compose `18-alpine`；測試 harness `18.1-alpine3.23` | PG18：官方測試路徑明確，CI 會呼叫 integration；未核成功 run。PG19：未找到。[S2-README] [S2-Init] [S2-Compose] [S2-Tests] [S2-CI] |
| infinite-canvas 當前映像 | **不適用**：當前固定 revision 未包含 PG server-side 儲存後端 | 不適用 | 當前 compose 無 PostgreSQL service | PG18／19：當前前端沒有 PG 驅動可測；歷史後端相容性未知。[IC-Dockerfile] [IC-Compose] [IC-Package] |

**限制**：new-api 的 9.6 是上游明文宣告，**不是建議部署過時 major**，也不是本研究對其所有新版 SQL 的逐版實測。sub2api harness 註解特別指出：只固定在 PG18 測試，會漏掉舊 major 的 JSONPath 行為差異；它提供 `SUB2API_TEST_POSTGRES_IMAGE` 以覆寫測試映像，示例為 PG15。這再次說明「15+ 宣告」、「18 測試設定」與「所有 major 都測過」必須分開。[S2-Tests]

## 5. Open WebUI：應用 SQL 與向量儲存的雙重需求

### 5.1 驅動與 ORM：來源 pin 與 runtime metadata 相符

固定 revision 的 `backend/requirements.txt` 與本機 `importlib.metadata` 得到相同版本：[OW-Requirements]

| 套件 | 版本 | 已確認用途 |
| --- | --- | --- |
| SQLAlchemy | `2.0.50`，requirements 使用 `[asyncio]` extra | 同步與非同步 engine／ORM |
| psycopg | `3.3.4`，`[binary]` | async PostgreSQL engine；一般 `postgresql://` 會轉成 `postgresql+psycopg://` |
| psycopg2-binary | `2.9.12` | 一般同步 PostgreSQL URL 的 driver；同步 engine 用於啟動／設定／migration 等 |
| Alembic | `1.18.4` | 應用 SQL schema migrations |
| pgvector Python client | `0.4.2` | SQLAlchemy `Vector`／`HALFVEC` 型別；**不是 PG extension 版本** |

程式碼只針對 SQLite／PostgreSQL 做 async URL 轉換；其他 URL 原樣交給 SQLAlchemy。requirements 含 PyMySQL **不足以證明 MySQL 是受支援的應用 DB**，尤其同步 MySQL driver 不能因此自動變成 async driver。官方 DB 文件明列 SQLite／Postgres，本報告不把 MySQL 標成官方可直接替換。[OW-DB] [OW-DBDocs]

### 5.2 Migration 行為

- **確認**：`ENABLE_DB_MIGRATIONS` 預設 true；`config.py` 啟動時呼叫 Alembic `upgrade(..., 'head')`。Alembic env 使用同步連線、`NullPool` 與 transaction context。[OW-Env] [OW-Config] [OW-Alembic]
- **確認**：若指定 `DATABASE_SCHEMA`，該 schema 必須存在；原碼會檢查 migration history／tables 是否不一致，以避免把既有安裝誤指到空 schema。migration 使用 `SET search_path`，與 session 狀態有關。[OW-Alembic]
- **確認官方文件要求**：升級時只能有一個 migration process，且其餘執行個體不可在資料搬動期間繼續服務。會改 schema 的升級不支持新舊版本混跑的 rolling update。這是應用版本升級行為，不是單純 PG binary major 升級自動會觸發的事情。[OW-DBDocs] [OW-Enterprise]
- **確認**：pgvector client 的 extension／table／index 初始化是另一條啟動路徑：檢查 vector type／維度、`Base.metadata.create_all`、建立 vector／全文／collection 索引。**不能把關掉應用 Alembic migration 解讀成向量端完全不會做 DDL**。[OW-PGVector] [OW-Factory]
- **確認**：若既有 vector index 方法與設定不同，程式拒絕自動重建；維度或 `Vector`／`HALFVEC` 型別不同也會拒絕啟動，要求另行處理資料。[OW-PGVector]

### 5.3 Extension 與既有 collection

- **必要、確認**：`VECTOR_DB=pgvector` 需要 PG 的 **`vector` extension**，安裝位置是 `PGVECTOR_DB_URL` 指向的 DB。預設嘗試建立 extension；`PGVECTOR_CREATE_EXTENSION=false` 表示管理者預先建好，不表示免除 extension 需求。[OW-Config] [OW-PGVector] [OW-DBDocs]
- **選用、確認**：只有 `PGVECTOR_PGCRYPTO=true` 才走 `pgcrypto` 加解密分支，而且要求提供 key。本機未顯式開啟該選項，固定 revision 預設 false；本研究沒有讀取任何 key。[OW-Config] [OW-PGVector]
- **未找到必要證據**：所讀的 DB 初始化／pgvector schema 不要求 `uuid-ossp` 或 `pg_trgm`。`document_chunk.id` 是文字欄位；全文 GIN 使用 PG 核心 `to_tsvector`，不能把 GIN 索引直接視為需要 `pg_trgm`。本次沒有逐一稽核全部歷史 migration，因此不把此點寫成所有版本永遠不需要。[OW-PGVector]
- **確認版本層次**：此 revision 對 extension `<0.8` 會跳過 iterative scan；`0.8+` 才設定對應的 `SET LOCAL … iterative_scan`。`HALFVEC`／索引功能又有各自的 extension 要求，不能只比較 Python client 或 PostgreSQL major。[OW-PGVector]
- **確認設定可分離**：`PGVECTOR_DB_URL` 預設值會取 `DATABASE_URL`；兩者可以分開。本機未設獨立 vector URL，因此更換 `DATABASE_URL` 也會改變預設向量目的地。[OW-Config]
- **推論、由 factory／初始化實作支持**：切換 `VECTOR_DB` 只會選另一個 client，**沒有將舊後端全部 collection 自動複製到新後端的通用流程**。舊向量仍留在舊儲存；新後端為空不代表舊資料已遺失或已遷移。必須另外計畫重建 embeddings／搬移 collection、metadata、IDs 與引用，再驗證 retrieval。[OW-Factory] [OW-PGVector]
- **確認範圍限制**：官方環境文件中的 reindex 路徑並不覆蓋所有資料，例如未加入 knowledge base 的獨立檔案與 web search cache。不可把「重建 knowledge/memory」當成完整備份或全 collection 遷移。某後端的特定內部自動 migration（如 Milvus 的特定 schema 轉換），也不能外推成跨 backend 通用搬移。[OW-DBDocs]

### 5.4 Pooling 與 prepared statement

**確認**：同步應用 engine、async 應用 engine、pgvector client engine 可能各自持有連線池；應用兩者讀 `DATABASE_POOL_*`，vector 讀 `PGVECTOR_POOL_*`。兩套 URL 相同不會自動合併池。正值 pool size 選 queue pool，0 使用 `NullPool`，未指定交由 SQLAlchemy 預設；vector 的 pool 配置與應用分開。[OW-DB] [OW-PGVector]

**推論**：評估共用 PG 的連線預算時，不能只算一次 `pool_size × replicas`；應把每個 process 內會建立的同步／async／vector engines、overflow、new-api、sub2api、管理連線一併計入。此研究沒有讀 PG `max_connections` 或實測 peak，所以沒有宣稱現況已超額。

**確認一般 driver 條件、部署適用性待驗**：psycopg 3 會自動管理 prepared statements。官方文件要求中介 pooler 若無明確支援，應停用自動 prepare；對 PgBouncer 的支援另有 PgBouncer ≥1.22、非零 `max_prepared_statements`、client libpq 能力等條件，文件也列出較舊 libpq 的特殊 deallocation 配置。**這裡的 libpq 17 指 client library，不是要求 PG server 必須 17。** 本次未查 client libpq、PgBouncer 版本或 runtime prepare 屬性，不能宣稱已相容。[PSY-Prepare]

`internal/db.py` 所讀 engine 建立路徑沒有顯式停用 psycopg prepare；單把 `DATABASE_POOL_SIZE=0` 也只影響應用端 pool，不會自動消除 server-side prepared statement 或外部 transaction-pooler 限制。Alembic 的 session `search_path` 另須考慮；migration／初始化以保有 session 語義的連線路徑處理，是根據實作的建議，不是本次已實測結果。[OW-DB] [OW-Alembic] [PGB-Features]

## 6. new-api：不是 Veloera；可選 DB 不等於可自動搬資料

### 6.1 明文支援與依賴版本

**確認**：映像 `calciumion/new-api:latest` 的 OCI source 是 `QuantumNous/new-api`，固定 revision README 的主 DB 清單為 SQLite、MySQL ≥5.7.8、PostgreSQL ≥9.6。`veloera_db` 是本地 DSN 的 DB 名，本報告沒有引用 Veloera 的支援矩陣或 migration。[NA-README]

固定 revision `go.mod`：[NA-GoMod]

- GORM `gorm.io/gorm v1.25.12`。
- `gorm.io/driver/postgres v1.5.9`，底層 `github.com/jackc/pgx/v5 v5.9.2`。
- MySQL driver `gorm.io/driver/mysql v1.5.7`、`github.com/go-sql-driver/mysql v1.7.0`。
- SQLite `github.com/glebarez/sqlite v1.11.0`、`modernc.org/sqlite v1.40.1`。

上述是映像標籤對應的 source dependency 宣告；本次未對 Go binary 做 build-info 抽取，不把它們聲稱為逐一量測過的 runtime module。主 CI 有 build／test，但所讀 workflow 沒有明示 PG18／19 matrix 或成功 run。[NA-CI]

### 6.2 Migration、extension 與連線

- **確認**：以 `SQL_DSN` 選 backend，`postgres://`／`postgresql://` 走 PostgreSQL；未設定走 SQLite。`LOG_SQL_DSN` 可把 logs 拆到另一個 DB；本機沒有設定獨立 log DSN，因此原碼會共用 `DB`。[NA-Main]
- **確認**：master node 啟動時執行多項特定 migration，再跑 `AutoMigrate`；非 master 路徑跳過主要 migration。另有針對 legacy quota 欄位的檢查，部分舊 32-bit schema 會要求明確轉換，不能假設所有歷史 schema 都可無條件自動升級。[NA-Main]
- **確認**：自訂 PostgreSQL migrator 會查 `pg_catalog`，在移除不符合模型的舊 unique constraint 時取得 `ACCESS EXCLUSIVE` table lock。這是可能阻擋讀寫的 migration 行為；不是「GORM 只會無害新增欄位」。[NA-Dialect]
- **未找到必要 extension**：所查主初始化／migration dialector 沒有建立 `vector`、`uuid-ossp`、`pg_trgm` 的必要路徑，也沒有向量 backend 要求。不能因與 Open WebUI 共用 server 就替 `veloera_db` 加上 pgvector 需求。本次未全文稽核所有 model 特例，故保留「未找到」而非絕對否定。[NA-Main] [NA-Dialect]
- **確認**：PG 分支設定 `PreferSimpleProtocol: true` 並傳入 `newGormConfig(false)`；後者的布林值直接設定 `PrepareStmt`。所以此映像 revision **已主動停用 pgx 隱式 prepare 與 GORM 顯式 prepare**。舊版 new-api／一般 GORM 預設行為不可套用在此版本。[NA-Main] [NA-Gorm]
- **確認**：`SQL_MAX_IDLE_CONNS` 預設 100、`SQL_MAX_OPEN_CONNS` 預設 1000、`SQL_MAX_LIFETIME` 預設 60 秒；它們是程式 fallback，不代表目前實際建立了那麼多連線。若 log DB 獨立，還會有另一個 sql.DB pool。[NA-Main]
- **推論**：在共用 PG 上應合併估算上限。prepare 已關閉，只能降低一類 pooler 問題，不能證明所有 session 狀態、migration 或業務交易都已在 transaction pooling 下驗證。所讀 migration 主路徑未見 sub2api 那種 session advisory lock，但沒有做全 repo advisory-lock 稽核。[NA-Main] [PGB-Features]

### 6.3 更換 MySQL／SQLite 的代價

**確認 backend 存在、資料搬移未確認**：設定選擇 DB 只決定去哪個 DB 開連線並建 schema，不包含「自動從現有 PostgreSQL 匯入資料」的通用流程。[NA-Main]

**推論代價中至高**：需處理 users／channels／tokens／options／帳務及 logs 的完整性、主鍵／sequence、JSON、boolean、numeric precision、時間與 unique constraints；若有 `LOG_SQL_DSN`，需另追 log DB。MySQL 還有原碼的中文字元集／collation 檢查。SQLite 的交易鎖策略與 PG 不同，原碼會跳過 `FOR UPDATE`，因此併發帳務操作的回歸驗證不能省略。這些是從實作導出的工作範圍，沒有讀取本機業務資料，不能估算工時或資料量。[NA-Main] [NA-Locking]

## 7. sub2api：PG15+、PG18 測試路徑與 session lock

### 7.1 版本與 extension

- **確認**：README requirements 與 `001_init.sql` 都寫 PostgreSQL 15+。[S2-README] [S2-Init]
- **確認 source dependencies**：Ent `v0.14.5`、`github.com/lib/pq v1.10.9`。主 DB 初始化 `entsql.Open(dialect.Postgres, dsn)` 或 `pq.NewConnector`；**不是 pgx**。`go.mod` 含 modernc SQLite 不足以推定主應用 DB 支援 SQLite；`db_pool.go` 甚至把轉 pgx 寫作後續方向。[S2-GoMod] [S2-DB] [S2-Pool]
- **確認**：官方 compose 的 PostgreSQL major 是 18，但明文最低仍是 15+；harness 固定 PG18.1，CI 執行 integration。沒有把這些誇大為本研究已跑過全部測試。[S2-Compose] [S2-Tests] [S2-CI]
- **選用、確認**：migration `065_add_search_trgm_indexes.sql` 嘗試 `CREATE EXTENSION pg_trgm`，但捕捉錯誤，只在 extension 存在時建立 fuzzy-search GIN 索引，否則 notice 後跳過。因此 **pg_trgm 是最佳努力的效能功能，不是此 migration 的硬性啟動前提**；沒有它可能影響大型管理搜尋效能。[S2-Trgm]
- **未找到必要證據**：讀到的主 DB 初始化／初始 schema 沒有 pgvector／`uuid-ossp` 的必要要求。初始資料表大量使用 `BIGSERIAL`、JSONB、BIGINT[]；PG 核心型別不是 extension。沒有逐檔稽核全部後續 migration，不能保證每個版本／功能永不增添 extension。[S2-Init] [S2-DB]

### 7.2 Migration 與 pooling

**確認**：SQL migration 檔案是 schema 的權威來源；初始化不是直接呼叫 Ent 自動 schema reconciliation。啟動以約 10 分鐘 context 呼叫 `applyMigrationsFS`；只對特定暫時性連線 SQLSTATE 重試，非所有 migration 錯誤都重試。[S2-DB]

**確認 runner 行為**：[S2-Runner]

1. 以 `schema_migrations(filename, checksum, applied_at)` 追蹤；按檔名排序，跳過已套用且 checksum 合法的檔案。
2. 既有 migration checksum 不合通常拒絕啟動，原碼有少數明列的歷史相容白名單；不能任意編輯已套用 SQL 或手改 migration 紀錄。
3. 取得專用 `sql.Conn` 後使用 **`pg_try_advisory_lock`／`pg_advisory_unlock`**，把多執行個體啟動 migration 序列化。這是 **session lock**，不是 `pg_advisory_xact_lock`。
4. 一般 migration 放 transaction；`*_notx.sql` 為 concurrent index DDL 特例，拆成各個 statement 執行並另行記錄。不能假設全部 schema 更新能包在單一交易 rollback。

**關鍵推論**：即使 Go 拿到同一個 `sql.Conn`，若中間是 transaction-pooling PgBouncer，背後 PostgreSQL session 仍可能跨交易改變。PgBouncer 官方 feature map 明列 session-level advisory lock 不支持 transaction pooling，因此 **sub2api 這條啟動 migration 必須保有 session 語義**；直接 PG 或 session pool 是待規劃路徑。prepared statement 已處理也不能解決這個 lock 問題。部署沒有單獨 migration DSN 的已確認功能，不能憑空假設可用 env 把 migration 與 runtime 分流。[S2-Runner] [PGB-Features]

**確認**：pool 由 `SetMaxOpenConns`／`SetMaxIdleConns`／`SetConnMaxLifetime`／`SetConnMaxIdleTime` 設定。官方 compose 的 fallback 為 50 open、10 idle、30 分鐘 lifetime、5 分鐘 idle time；這些是**範例 env 的 default**，不是本研究已讀到主程式所有 configuration fallback 的結論，也不是現場連線數。[S2-Pool] [S2-Compose]

**Prepared statement 限制未知**：此次沒有全文掃描所有 repository 的 `Prepare`／`PrepareContext` 用法，也沒有量測 lib/pq 與 pooler 的交互。不能把「lib/pq 不是 pgx」寫成「一定沒有 prepared statement 風險」。

### 7.3 換 MySQL／SQLite 或 vector backend

**確認**：目前主連線明確用 PostgreSQL dialect；schema 與 runner 使用 JSONB、array、PG advisory locks、PG catalog、concurrent index 等 PG 行為。[S2-DB] [S2-Init] [S2-Runner]

**推論代價高**：更換 DB 不只是 env，涉及改 driver／dialect、重寫 SQL migrations 與型別、替換 lock／DDL 邏輯、資料轉換及完整業務測試。Ent 支援其他 DB 並不代表這個應用已支援；`go.mod` 的 SQLite 套件也不構成替代路徑。此服務未找到 vector backend 要求，換掉 Open WebUI 的向量儲存不會解除 sub2api 的 PostgreSQL 需求。

## 8. infinite-canvas：遺留 PG 設定與目前映像的差異

**本次最重要的版本校正**：本機 `v0.20.0` revision 的 Dockerfile，以 Bun 建置 `web` 的 Vite 產物，runtime 基底是 `nginx:1.27-alpine`，copy `dist` 與 Nginx 設定；沒有 Go server／PG driver。容器 metadata 的 command 正是 Nginx。`web/package.json` 有 localforage，但沒有 PG ORM；實際 storage adapter 呼叫 localforage 的 get／set／remove。啟動腳本僅從分析用 env 產生 `config.js`，沒有讀 `DATABASE_DSN` 或 `STORAGE_DRIVER`。[IC-Dockerfile] [IC-Package] [IC-Storage] [IC-Entrypoint]

因此此**當前映像**的問題應回答：

- PG 最低／推薦 major：**不適用**；不是找到低版本支援承諾。
- PG ORM／driver 版本與 migrations：**不適用**；當前 runtime build 沒有對應 DB 後端。不能用搜尋引擎找到的舊 `.env.example` 或歷史 Go 程式，冒充這個 revision 的需求。
- `vector`／`uuid-ossp`／`pg_trgm`：沒有目前 server-side PG extension 需求的證據。
- PG18／19：沒有此版需要連 PG 的實作可據以聲稱已驗證。
- MySQL／SQLite 替換：對當前靜態應用不構成 DB backend 切換；涉及的是 browser IndexedDB／local storage 與歷史 server 資料的產品遷移，不能靠改 DSN 恢復舊資料。[IC-Storage] [IC-README]
- pooling／prepared statement／advisory lock：當前 Nginx 靜態 runtime 不適用 PG client 的這些機制。

**官方文件亦有漂移**：同一 revision 的 Docker deployment 文件有「主容器只跑 Next.js」字樣，但這與同 revision 的 Dockerfile／package scripts／本地 Nginx command 不符。本報告以建置實作與 runtime metadata 為準，僅採納其「瀏覽器預設保存畫布等內容」這項可由 storage code 印證的敘述。[IC-Doc] [IC-Dockerfile] [IC-Storage]

**歷史風險未知**：本次沒有讀 `infinite_canvas` 裡任何資料、沒有抓 DB 活躍 session，也沒有證明沒有其他舊 instance 或外部程序使用它。舊庫仍列為待保留與另行盤點的資產，**研究發現不足以授權刪庫或移除設定**。

## 9. 後端替換成本與共享 PG 的實際限制

以下「成本」是實作範圍的定性推論，沒有以資料量估時：

| 服務 | 改 MySQL／SQLite | 改 vector backend | 能否因此解除所有 PG 需求 |
| --- | --- | --- | --- |
| Open WebUI | SQLite 是官方 backend，但跨 DB 不自動搬資料；併發／多副本限制需重新評估。MySQL 未列為官方應用 DB 替代 | 工廠支持多個 backend；需要另搬／重建 collections、embeddings、metadata 與引用，驗證查詢。MariaDB vector 還有選用 connector／server 功能要求 | **不能只改一個變數**。應用 SQL 改 SQLite 但 vector 仍 pgvector，PG 仍必要；只換向量，應用 SQL 仍 PG。[OW-DBDocs] [OW-Factory] [OW-Config] |
| new-api | 官方三種主 DB；搬既有完整資料需另做，MySQL schema／charset、SQLite 併發與帳務鎖差異使成本中至高 | 沒有此應用必要 vector backend 證據 | 可解除 **new-api 自己**的 PG 需求，其他服務仍在。[NA-README] [NA-Main] [NA-Locking] |
| sub2api | 所查版沒有受支持的主 DB 替代設定；成本高，涉及 PG-specific SQL 與 lock 機制 | 不適用 | 換向量無關；除非另外開發與驗證其他主 DB 支援。[S2-DB] [S2-Runner] |
| infinite-canvas 當前映像 | 當前不是 server SQL backend 架構；不能沿用舊後端說法 | 沒有 PG vector client 需求 | 目前不應把它計為確認的直接 PG client；歷史庫仍需保留盤點。[IC-Dockerfile] [IC-Storage] |

**跨服務 extension 範圍**：共享同一 PG server 不等於共享同一 database；`CREATE EXTENSION` 必須在真正存向量的 database 可用。Open WebUI 的 vector extension 不會因安裝在 `openwebui_db` 就自動變成 `sub2api` 或 `veloera_db` 的依賴；sub2api 的 `pg_trgm` 也是其自己 DB 的效能選項。[OW-PGVector] [S2-Trgm]

**整體 pool 預算**：應用端 queue pool／Go sql.DB pool、外部 pooler 的 server pool、PG `max_connections` 是不同層。PG major 升級不會自動修正預設上限過大或 session-pooling 不相容。此次沒有修改 pool 數值，也沒有讀 production 統計或負載資料。

## 10. 查核限制與尚待驗證的清單

1. **沒有以 production 實測兼容性。** 取得 version metadata 不等於已驗證 chat、RAG、扣款、背景任務、管理搜尋與 migration。PG18／19 的「通過」需另有相應應用 revision、extension 版本及成功測試紀錄。
2. **沒有查 DB catalog／資料。** 未知 installed `vector`／`pg_trgm` 版本、是否啟用 pgcrypto、當前 Alembic head／schema checksum、活躍 client、資料量、索引方法與實際 pool 使用量。本文的 extension 結論是程式需求，不是本地 extension 清單。
3. **沒有覆蓋每個歷史 migration／私有外掛。** 對 `uuid-ossp`／`pg_trgm` 等的否定只寫「未找到必要證據」；已找到的必需／選用路徑則明確列出。PG 原生 UUID 型別與 `uuid-ossp` 是不同事物。
4. **固定 revision 優先。** 部署依賴版號取自 OCI source revision；Open WebUI Python modules 另以 runtime metadata 相互印證。初期抓的上游 main／搜尋索引只用於 discovery，不用其後來的版本替代現場版本。文件站本身是可變來源，與固定 source 有衝突時逐項記錄。
5. **沒有把 docs 範例當完整測試。** new-api 的 PG15 example 不限制上限；sub2api 的 PG18 harness 不證明 PG15–19 都跑過；pgvector 的 PG18 artifacts 不證明 Open WebUI 的全功能在 PG18 已通過。
6. **網頁工具限制有留存。** 父代理先前的 smart-search doctor 為 `ok:true,degraded:false`；本輪抓取中部分 fetch 一度 exit 4，後續 `providers status` 顯示 Tavily 暫時 cooldown（HTTP 554／EdgeOne timeout）。相同 URL 的一次重試由 **smart-search 內建同能力 fallback 到 Firecrawl** 成功；相關 JSON 保留 `provider_attempts`／`provider_notices`。沒有改用 native web、curl、直接 HTTP 或其他未批准搜尋路徑。部分 HTTP 404 被 extractor 當作可讀頁面，這些檔案不作正面證據。
7. **沒有發布或變更服務。** 檔案修改僅限本報告與 `research/evidence/service-*`。若後續另獲授權驗證，應先在獨立副本分別測：應用正常啟動、現有 schema 啟動、各 migration、RAG collections／維度／索引、帳務交易與排程，以及直連／pooler 的 session 語義；本次沒有執行這些動作。

## 11. 證據索引與重現方式

完整 URL、檔案雜湊、抓取檔大小與抓取分類另列於 `evidence/service-source-manifest.json`。Markdown evidence 是 smart-search 的抓取文字，可能含 Markdown escaping，**不是可重新編譯的 byte-for-byte source clone**；核對程式細節應回官方固定 revision。JSON fetch evidence 保留 provider／fallback metadata。

本次命令類型（所有 shell 命令均有 `rtk` 前綴）：

```text
rtk proxy smart-search agent-guide references/command-patterns.md
rtk proxy smart-search exa-search '官方來源導向查詢' --include-domains 官方網域 --format json --output research/evidence/service-....json
rtk proxy smart-search fetch '下列精確官方 URL' --format markdown --output research/evidence/service-....md
rtk proxy smart-search fetch '下列精確官方 URL' --format json --output research/evidence/service-....json
rtk proxy smart-search providers status --format json --output research/evidence/service-provider-status.json
rtk proxy docker inspect （僅擷取 image／指定 metadata 與去憑證設定）
rtk proxy docker exec open-webui-ollama python -c 'importlib.metadata 版本查詢'
rtk proxy docker exec chatstack-postgres17-pgvector postgres --version
```

本地 compose 來源：`/home/df/workspace/myServices/ChatStack/docker-compose.yml`，只經 whitelist 擷取依賴拓撲與去憑證資料庫設定。報告未重印該檔案全文。

### 官方來源 URL

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
