# ChatStack：Open WebUI → LibreChat 漸進遷移計劃

調查日期：2026-10-08（Asia/Taipei）

範圍：部署設計與驗收計劃；本 PR 僅新增文件，沒有部署或切換服務。

## 1. 結論

**可以將 LibreChat 定義在現有 `ChatStack/docker-compose.yml`，沿用 Portainer 的 Git stack 部署。** 不需要改用另一套管理平台，也不需要先拆掉 Open WebUI。但不能只新增一個 LibreChat 容器就認定圖片、搜尋、文件全部可用：必須處理 MongoDB、檔案持久化、模型能力、搜尋供應商，以及文件／embedding 路徑。[S1][S2][S3]

建議先增加獨立的 LibreChat 服務組，使用新連接埠及資料目錄，與 Open WebUI 並行。第一階段完成圖片辨識、可引用來源的網路搜尋、文字型 PDF／DOCX 讀取；第二階段驗收長文件 RAG、歷史資料移轉與掃描 PDF OCR，再逐步切換日常使用入口。**掃描 PDF OCR 納入驗收，未通過前不宣告整體文件能力完成。**

本計劃的架構可行；尚未執行付費模型／搜尋／embedding 呼叫或實際 LibreChat 部署，因此下方「待驗證」項目是後續部署的驗收門檻，不是已通過的結果。

## 2. 查到的部署慣例與實際狀態

| 項目 | 2026-10-08 的證據 | 對部署的影響 |
|---|---|---|
| Repository | 實際位置是 `/home/df/workspace/myServices`，大小寫有別；公開 remote 為 `DF-wu/myServices`，預設分支 `master` | 新設定只放非機密內容；憑證不進文件或 Git |
| 生產分支 | 根目錄 README 說明 `master` 同時是開發／生產分支 | 文件 PR 可先合併；實作 PR 必須另外安排部署窗口 |
| 實際控制平面 | `docker compose ls` 顯示 `chatstack` 執行 16 個容器，Compose 為 `/data/compose/288/ChatStack/docker-compose.yml`；Portainer `/data` 是 host `/mnt/appdata/portainer-ce/data` | 在原 Portainer stack 更新；不要從本機隨手建立另一個同名 project |
| 設定一致性 | Portainer 磁碟上的 Compose 與本機 `ChatStack/docker-compose.yml` 比對相同；調查基準 commit `475e7d7` | 仍須查 Portainer 的 Git ref、自動更新／webhook／polling 設定；本機修改不等於已部署 |
| Komodo | 本機調查時 Komodo 已在執行；未提交的 `Komodo/PORTAINER_TO_KOMODO_MIGRATION.md` 記錄匯入但尚未交接部署控制權 | 不把 LibreChat 遷移與管理平台交接綁在一起；該未提交文件僅作輔助證據 |
| Network | Open WebUI、new-api、Tika、PG17 都在 `chatstack_default` | LibreChat 可透過 Docker service DNS 連 `http://new-api:3000/v1`，不必繞公開入口 |
| Open WebUI | `:ollama` image；host `43000 → 8080`，`43002 → 11434`；有 NVIDIA reservation | 停用 WebUI 同時會停用內建 Ollama；不能只把 `43000` 改指 LibreChat |
| 歷史資料 | `openwebui_db` 的 `user` 有 8 筆、`chat` 有 1,035 筆（快照，會持續變動） | 需要使用者與歷史對話的獨立移轉計劃 |
| 檔案／資料庫 | `/mnt/appdata/ChatStack/open-webui`、`ollama`、`postgres` 等使用 bind mounts；共享 PostgreSQL 為 `pgvector/pgvector:pg17` | 不能把 WebUI 的目錄或資料表直接交給 LibreChat |
| 儲存底層 | `findmnt -T /mnt/appdata` 顯示 NAS `nfs4`；`/home` 為本機 Btrfs | MongoDB 與新索引／向量資料庫採本機磁碟；NAS 留給附件與備份 |
| 身分／權限 | 很多現有容器使用 `3000:3000` | 按新 image 的 UID/GID 與寫入路徑逐項確認，不能機械套用 |
| 搜尋現況 | SearXNG 只剩註解；Open WebUI DB 保存 `web.search.engine=searxng`、目標 `http://searxng/search`；從 WebUI 容器解析 `searxng` 失敗 | 不能聲稱已有可直接沿用的正常 SearXNG |
| 部署端搜尋憑證 | Lilac 兩個執行容器均有非空的 `EXA_API_KEY`、`TAVILY_API_KEY`、`FIRECRAWL_API_KEY`、`TAVILY_API_BASE_URL`；本機 `.env` 的對應值為空 | 要在部署端確認供應商／轉發網址與額度；此調查只查看鍵名及是否非空 |
| 文件現況 | Tika 容器仍執行；DB 保留舊 `rag.CONTENT_EXTRACTION_ENGINE=mineru`，新小寫鍵為空 | 保存的設定可能有版本殘留；未確認實際有效的解析引擎，不以 Tika 或 MinerU 已可用為前提 |
| Embedding | WebUI DB 保存 `rag.embedding_engine=openai`、`rag.embedding_model=qwen3-embedding-8b`，base URL 指向 `llm-api.dfder.tw` | 可評估沿用 embedding 供應商；API、模型路由與維度要重新測試 |
| Ollama | DB 中啟用 Ollama；調查時 `ollama list` 無模型 | 目前未見本機模型，但仍要盤點 `43002` 的外部使用者，不能據此直接移除 |
| 備份 | 執行中的 Backrest 只見 `/mnt/mydata → /userdata` 等 mounts | 不能假設新本機資料庫或既有 ChatStack 資料已被備份；須檢查實際備份 jobs 並補上來源 |
| 容量／port | 調查時 RAM 約 78 GiB available，NAS 約 4.5 TiB available；host `43006` 未 listen | `43006` 可作候選 pilot port，部署前重查；本機磁碟容量需另查，NAS 容量不能代替本機容量 |

可重做的唯讀檢查：`rtk docker compose ls`、`rtk docker ps`、`rtk proxy docker inspect <container>`（只輸出指定欄位）、`rtk proxy findmnt -T /mnt/appdata`、`rtk proxy ss -ltnH 'sport = :43006'`。不要把完整 `inspect`／`compose config` 的 secrets 貼到 PR。

## 3. 建議部署形態

仍使用 project **`chatstack`**；新增服務使用獨立且明確的名字，避免上游範例 `api`、`mongodb`、`vectordb` 的泛用 container names。不要照搬整份 upstream Compose 的 `latest`、`--noauth` 或範例 DB 密碼。[S1]

| 新服務 | 用途 | 儲存／連接 |
|---|---|---|
| `librechat` | UI/API，圖片與文件上傳、Agents | 候選 `43006:3080`；設定唯讀掛載到 `/app/librechat.yaml`；與 `new-api` 共用 default network |
| `librechat-mongodb` | 使用者、對話、設定與檔案 metadata，必需 | 本機 `/home/df/appdata/ChatStack/librechat/mongodb`，掛到 `/data/db`；啟用 DB auth，專用帳號，無 host port |
| `librechat-meilisearch` | 搜尋自己的聊天歷史，**不是**網路搜尋 | 本機 `…/meilisearch`；專用 master key，無 host port；若 pilot 暫不需要，可明確 `SEARCH=false` 並略去 |
| `librechat-rag-api` | 文件解析、分塊、embedding、檢索 | 內部 URL `http://librechat-rag-api:8000`；需要可連 embedding 供應商的網路；無 host port |
| `librechat-vectordb` | RAG API 專用 pgvector | 第一輪使用所選 RAG release 配套的 PG/pgvector；本機 `…/vectordb`，專用帳密，無 host port |

附件 images／uploads 可沿用 NAS：`/mnt/appdata/ChatStack/librechat/{images,uploads}`，分別掛到 `/app/client/public/images`、`/app/uploads`。依所選 release 保存 `/app/data`（例如 temporary credentials/runtime state）及其他必要目錄；logs 設輪替，勿無限制累積。掛載清單以鎖定版本的 upstream Compose 為準。[S1]

MongoDB 官方允許符合 POSIX.1 的 NFS，但指出遠端儲存可能造成效能退化，並強烈建議 Linux WiredTiger 使用 XFS。本計劃選擇新增 MongoDB 不沿用 `/mnt/appdata`。`/home` 目前是 Btrfs，表中的本機路徑只是候選；部署前評估將 Mongo 資料放在本機 XFS／ext4，或另驗證 Btrfs 的相容性與效能，不能把「本機」當成已符合官方推薦。新 Meilisearch／vector DB 也採本機磁碟是本計劃的隔離設計，不代表已證實所有 NAS 使用方式都不支援。[S11]

Mongo／Meili／vector DB 放在新增的內部 backend network；LibreChat 與 RAG API 同時連 backend network 及必要的可出站 network。MongoDB 即使未開 host port，也要有 auth，避免同 stack 其他服務任意讀取。單實例第一輪不需要額外 Redis；既有 Valkey DB 編號不改動。

**共享 PG17 是可行的後續優化，不是第一輪前提。** 若實測 RAG image 與 PG17 相容，可另建 `librechat_rag` database 與專用 role，啟用所需 `vector` extension；不可共用 `openwebui_db`、WebUI vector tables 或 PostgreSQL superuser。切換資料庫也是資料遷移，須另做 dump/restore 或重建索引。新增 DB 不靠修改既有 `POSTGRES_DB` env 自動建立，因既有 data directory 不會重跑首次初始化。[S6]

### 版本與部署檔案

截至調查，GitHub 最新列出的 release 是 `v0.8.8`（2026-10-01），標記為 **prerelease**；`releases/latest` 回 404，不能稱它為已驗證的穩定版。候選為 `v0.8.8`，實作時須確認主程式與 RAG image 都有可取得的相容 artifact，鎖 tag/digest 後測試。[S12]

該 tag 的 upstream Compose 仍引用 `librechat-dev:latest`、`librechat-rag-api-dev-lite:latest`，**版本化 YAML 不代表容器版本已鎖定**。實作 PR 必須列出實際 registry、tag、digest、支援架構及 release 對應關係；必要時評估 `lite` 的解析／embedding 依賴差異。管理用 `admin-panel` 不屬於本次需求，不直接引入或額外開 port。[S1]

後續實作預計新增／修改：

- `ChatStack/docker-compose.yml`：新服務、network、mount、healthcheck／readiness 與 host port index。
- `ChatStack/librechat/librechat.yaml`：可版本控管的端點、Agents、搜尋、文件上傳設定。
- `ChatStack/librechat/compose.env.example`：只放新鍵名與非機密範例；真實值在 Portainer env 或被忽略的部署端檔案。
- `ChatStack/librechat/DEPLOYMENT_RUNBOOK.md`：實際 image digests、設定交付、備份、驗收與回復紀錄。

`librechat.yaml` 掛載可用 repo 內的相對檔案，但必須驗證 Portainer 執行時解析出的 **host source path** 存在且是檔案；若 git checkout 路徑／bind 支援不可靠，改交付到固定 `/home/df/appdata/ChatStack/librechat/config/librechat.yaml`，文件記錄版本 hash。不可直接綁定 `/data/compose/288` 作為永久設定來源，stack ID／checkout 路徑可能改變。

Compose `${VAR}` 展開與應用程式 env 是兩層：LibreChat YAML 中的 `${…}` 必須真的在 **librechat 容器** 的 environment／所讀取 env file 裡存在；embedding keys 也要交付給 **rag-api 容器**。不要把 ChatStack 整份 `.env` 當作 LibreChat 專用 `/app/.env`，避免把其他服務的 tokens 一併暴露。[S2]

## 4. 必要功能如何落地

### 4.1 圖片辨識

以 `endpoints.custom` 設定既有 new-api gateway，base URL 為 `http://new-api:3000/v1`、API key 為專用的 `${LIBRECHAT_NEW_API_KEY}`。先選明確測過的模型 allowlist，不能以 `/v1/models` 有列出模型就視為支援圖片／工具。本計劃使用管理者固定的 base URL；若改開放 `user_provided` base URL，候選版會做 URL 驗證，需在 `endpoints.allowedAddresses` 精確允許可信的 `new-api:3000`。兩種模式都將 gateway 初始化與實際呼叫列為驗收。[S2][S3][S15]

圖片辨識要求完整路徑保留 multimodal `image_url`／base64 payload；測 PNG、JPEG、中文截圖、小字、兩張圖比較。new-api 的 channel／上游模型必須支援 vision。辨識與圖片生成是不同需求，本計劃不引入圖片生成服務。

建立固定的日常 Agent／preset，指定驗證過的 vision + tool-calling 模型、context／檔案能力與網路搜尋工具。**custom chat endpoint 設好不等於 Agents 已設好**：須確認 custom provider 可在 Agents 選用，且其 tools／streaming tool calls 確實運作；不以 provider-hosted Assistants API 作為 new-api 必須支援的前提。[S3][S7]

### 4.2 網路搜尋

首選 **Tavily search + Tavily extract**，因部署端已有 Tavily key，而且 `v0.8.8` 的官方範例有這組內建設定。[S2] 先確認現有 `TAVILY_API_BASE_URL` 是官方服務還是相容轉發站；不能直接把任意 base URL 填進完整 endpoint URL 欄位。

下列只是設定方向，待確認實際 endpoint 與 schema 後才形成可部署檔案：

```yaml
webSearch:
  searchProvider: tavily
  scraperProvider: tavily
  tavilyApiKey: '${LIBRECHAT_TAVILY_API_KEY}'
  tavilySearchUrl: '${LIBRECHAT_TAVILY_SEARCH_URL}'
  tavilyExtractUrl: '${LIBRECHAT_TAVILY_EXTRACT_URL}'
  rerankerType: none
```

若使用 Tavily 官方服務可省略 URL overrides；官方預設為 `https://api.tavily.com/search`、`https://api.tavily.com/extract`。`rerankerType: none` 要明確指定，第一輪不增加 Jina/Cohere 費用；日後再量測是否需要 rerank。搜尋結果必須能進一步擷取網頁內容並在回答中呈現可點來源，不能只驗證有搜尋 snippets。[S2][S4]

若現有轉發不支援 extract，改 **Tavily search + Firecrawl scraper**，核對 `firecrawlApiUrl`／`FIRECRAWL_API_URL`（不等同現有 Lilac 的 `FIRECRAWL_API_BASE_URL` 鍵名）。Firecrawl override 填服務 root，不附 `/v1` 或 `/scrape`；Agent library 會加 `/<version>/scrape`，候選版依賴的 `@librechat/agents` v4.0.1 預設為 v2。若既有相容站只有 v1，明確設定 `firecrawlVersion`／`FIRECRAWL_VERSION=v1` 並驗證，不能沿用舊文件的預設假設。[S13] 現有 Exa key 不視為 LibreChat 原生支援的證據；要用 Exa 時另評估 MCP integration，不作第一輪依賴。[S2][S4]

SearXNG 是可行備選，但需重新部署，啟用 JSON search format，選可用 engines，處理上游封鎖／限流，以及 scraper。它不需要 host port，尤其不能重用已被 AstrBot 占用的 `43004`。新版對私有搜尋／擷取 endpoint 有 SSRF 限制；需要時在 `webSearch.allowedAddresses` 精確列 `host:port`，不是 URL、CIDR 或全網放行。出站 proxy 如需沿用 gluetun，僅配置 LibreChat/RAG 的必要流量；不要機械沿用過期的 `network_mode: service:gluetun-jp-2` 註解。[S2][S4]

### 4.3 PDF／DOCX：直接讀取、RAG、OCR 分別驗收

| 文件／用途 | 路徑 | 特別處理 |
|---|---|---|
| 短 DOCX、文字型 PDF | Upload as Text／Agent context／所選版本內建 document parser | 將文字加入 context；測中文、表格與頁碼，受模型 context/token 限制；不需要把每份短文件都做 embedding |
| 長 PDF／DOCX、跨文件問答 | RAG API + pgvector + embedding；Agent File Search | 解析、chunk、索引與檢索皆須可用；RAG 只取相關片段，不代表完整讀過全檔 |
| 掃描 PDF、頁面圖片、版面複雜文件 | 明確的 OCR 路徑，例如 Mistral OCR 或經驗證的相容服務 | vision 讀單張圖不等於自動 OCR 整份 PDF；需要 OCR credentials、實際解析與引用驗收 |

Upload as Text 不需要 RAG／vector DB 就能讀支援的文字文件；近期內建 `document_parser` 可處理文字型 PDF／DOCX，但它不是掃描圖片 OCR。實際行為必須以所選 image 版本驗證，不能把 current docs 的新能力套到舊 image。[S5][S8]

RAG API 本身有文件 loaders；現有 `http://tika:9998` **不能只填一個 env 便當成 LibreChat 的 RAG parser**。若要沿用 Tika／MinerU／Docling，需要另做對接、預處理或相容 OCR adapter，不列為部署已具備的功能。特別是 current OCR docs 列出的 `custom_ocr`，在候選 v0.8.8 的 handler 未實作，不能據文件直接承諾可接任意 parser。[S6][S8][S14]

若選 Mistral OCR，依鎖定版本 schema 設 `ocr` block 或 `OCR_API_KEY`／`OCR_BASEURL`，使用專用 credential；私有相容 endpoint 亦需核對 `ocr.allowedAddresses`。若不想傳文件給外部 OCR，需先實作／驗證自架路徑，不能把掃描 PDF 驗收省略。文件外傳對象是待選的服務，PR 不含使用者文件。[S2][S8]

RAG 第一輪評估現有 `qwen3-embedding-8b`，在 RAG API 設 `EMBEDDINGS_PROVIDER=openai`、`EMBEDDINGS_MODEL=qwen3-embedding-8b`、`RAG_OPENAI_BASEURL`、`RAG_OPENAI_API_KEY`。先用無敏感短句驗證 `/v1/embeddings`、輸出維度、批次行為、配額與錯誤回報；RAG API 必須可連該 gateway，且 image 支援此維度。本計劃啟用 RAG API 的 JWT 驗證；LibreChat 與 RAG API 需共用同一個 `JWT_SECRET`，只交付給這兩個容器；不能各自產生不同值，也不能誤用 `JWT_REFRESH_SECRET`。RAG client/server 版本與授權行為須配套測試。後續變更 embedding 模型需重建索引，不直接混用不同模型向量。[S6]

設定 `fileConfig` 的 endpoint-specific MIME allowlist、單檔／總量／檔數限制，至少涵蓋 PDF、DOCX（`application/vnd.openxmlformats-officedocument.wordprocessingml.document`）及圖片。先用合理上限（候選單檔 20 MiB、每次 5 檔），並核對 proxy 與 parser 各自限制；允許副檔名並不保證能解析。舊 `.doc` 不屬本次必需格式，另做相容性測試。[S9]

## 5. 帳號、入口、歷史資料

1. 建立 LibreChat 自己的使用者／管理員；試用期採既有慣例的封閉註冊，`ALLOW_REGISTRATION=false`，bootstrap 用所選 release 支援的管理方法。Email login／SMTP 密碼重設是否可用需驗證；若後續接 OIDC，兩套應用的 client 與 callback 各自設定。
2. 產生並保存獨立 `CREDS_KEY`、`CREDS_IV`、`JWT_SECRET`、`JWT_REFRESH_SECRET`、Mongo 帳密與 Meili key；重建容器時不可重置。大小／格式遵循該 release 的官方說明。API token 使用 new-api 專用 consumer key，避免共用 admin key。[S1][S2]
3. 試用使用新 hostname（候選 `librechat.dfder.tw`）與 `43006`。現有文件顯示此 homelab 同時有 NPM 與遠端管理的 Cloudflare Tunnel 慣例；本次未讀取控制平面的實際 Chat hostname 規則，**實作前查明它的路由鏈**，再決定 NPM upstream 或 Tunnel service。若走 LAN host port，限制可達來源；只綁 localhost 會讓 bridge-mode proxy 無法直接用 LAN IP 連入。
4. 使用 HTTPS 正式入口時對齊 `DOMAIN_CLIENT`／`DOMAIN_SERVER`，驗證 forwarded headers、cookie／登入、串流 SSE、WebSocket（若使用）、timeout、body size 和大檔上傳。Cloudflare Tunnel 的 hostname 規則在遠端控制平面，不能只改本機 Compose。[S1][S2]
5. 先每位使用者匯出 Open WebUI 對話 JSON，保存帶日期的原件與附件備份。LibreChat 官方 importer 列出的來源沒有 Open WebUI，不能承諾 JSON 可直接全量匯入。[S10]
6. 另做轉換工具或先保留舊站查歷史；用少量對話驗證 role、時間戳、parent/branch、模型標籤、附件與 tools 記錄。不同使用者分開匯入，避免歸屬錯置；記錄已匯入 ID／hash，防止重跑重複。
7. WebUI 的密碼、sessions、知識庫索引、prompts、model presets、tools/functions 與共享設定不視為對話匯入的一部分。需要者逐項重建，知識庫重新上傳／embedding；1,035 筆只是調查快照，不是可保證完整移轉的筆數。

## 6. 分階段執行與通過條件

### Phase 0：準備與版本鎖定

- 查原 Portainer stack 的 Git ref／auto-update，維持唯一部署控制者；確保實作合併不會觸發未準備好的部署。
- 選並記錄 image digests、app/RAG 配套，檢查新 UID/GID、NFS 附件權限、本機容量與 `43006`。
- 決定 embedding／搜尋／OCR provider，確認費用與 URL；新 secrets 只交付給需要的容器。
- 備份原 Compose、部署端 env、Open WebUI 檔案、Ollama 目錄與 `openwebui_db`；測試能還原。
- 在部署端執行 `rtk proxy docker compose config --quiet`，查新服務的 mounts/environment 解析結果，不輸出 secret；為 DB/RAG 設 readiness checks，`depends_on` 不能取代實際 ready 驗證。

### Phase 1：並行 pilot

- 從原 Portainer stack 部署新服務，先保持原 `43000` 入口與 Open WebUI 使用者流程。
- 驗證 Mongo auth、檔案寫入、容器重建後對話／附件仍在、正常登入及關閉公開註冊。
- 驗證文字聊天、圖片辨識、網路搜尋來源引用、短 PDF／DOCX 全文問答；用固定 Agent 測試一輪，避免測到另一個 provider 才成功。
- 只切新試用入口；新 hostname 通過登入、串流與附件驗收後再給其他使用者試用。

### Phase 2：文件與使用者遷移

- 跑完整 RAG／OCR／多使用者驗收，長文件需要索引成功、引用正確、重啟後可檢索。
- 抽樣匯入歷史 JSON；確認權限、附件與分支後再決定全量轉換／保留舊站。
- 重建必要 prompts／tools／知識庫；建立本機 DB + NAS 附件的備份與復原流程。
- 觀察至少一週的日常使用（圖片、搜尋、文件、額度、延遲、錯誤），將結果寫回 runbook。

### Phase 3：逐步切換預設入口

- 更新日常 bookmark／homepage，LibreChat 成為新對話預設；舊站保留歷史查閱。
- 若要搬原 hostname，先檢查兩套 cookie/domain 與 callback，再變更單一 ingress 規則；不要同時改 port、provider、資料格式。
- 未處理完歷史／附件／Ollama consumer 之前，Open WebUI 持續並行；清理舊服務另開操作，不能把停站當成文件 PR 的副作用。

## 7. 驗收矩陣

全部使用無敏感的固定 fixture，保留結果與所測模型／image digest。

| 驗收 | 必須看到的結果 |
|---|---|
| Vision | 中文截圖、小字、兩張圖片比較能答出圖上特有內容；text-only 模型不假裝看圖 |
| 網路搜尋 | 問一個需近期資料的問題，實際有 tool call、成功取頁、可點來源，日期與引文對得上 |
| 搜尋失敗 | key 無效／額度耗盡／extract 不可達時，有可理解的失敗結果，不冒充已搜尋 |
| PDF 文字 | 以首頁／中段／末頁不同唯一字串做問答，確認取到相應內容；引用及中文正常 |
| DOCX | 段落、中文表格與檔案特有數值可讀；不以內嵌圖片也已辨識為假設 |
| RAG | 長文件相關段落可檢索、來源正確、多檔檢索正常、重建容器後索引仍可用 |
| 掃描 PDF | 純圖片頁面的獨有文字與數值可讀；OCR 無法使用時明確失敗而非捏造 |
| 使用者隔離 | A 無法讀 B 的對話／私人上傳／私人索引；shared Agent／Files 的分享權限另測 |
| 反向代理 | HTTPS 登入、refresh、長回覆串流、接近上限的檔案上傳均可用 |
| 歷史匯入 | 一般／多輪／分支／附件對話抽樣比對；歸屬正確、重跑不重複 |
| 備份復原 | 在隔離位置從備份還原 DB、密鑰、設定及附件，能登入並重新開啟文件對話 |

## 8. 備份與回復

新備份需包含 MongoDB 的一致性 dump、RAG PostgreSQL dump、附件、必要 `/app/data` runtime state、設定與加密／JWT keys。Meilisearch 通常可重建，但須記錄重建方法或保存相容 snapshot。不要把執行中的 DB directory 直接複製當作唯一備份。[S1][S11]

本機 DB 路徑要加入實際備份來源或先以受控 dump 存到 NAS 再備份；檢查 Backrest job、保留期與異地副本。單機 dump 要安排一致性窗口／必要暫停寫入，復原時對齊 DB、附件及 metadata 的時間點。

pilot 回復：把日常入口指回 Open WebUI，僅停用 LibreChat 新服務；保留其資料和新對話。**不對整個 ChatStack 執行 `down`，不使用 `down -v`。** 已寫入新對話不會自動同步回 Open WebUI，因此切換前後保存 LibreChat export，說明期間的新資料在哪裡。

升級回復：變更前備份 DB／設定並記錄 digests。schema 升級後不可只換回舊 app image 就假設相容；用該版本的還原備份與附件副本恢復，先在隔離服務驗證，再切入口。

## 9. 來源與查核邊界

官方網站會隨 current 更新，以下 tag 固定原始碼用來核對候選版本；實作時以最終 image 所屬 release 再核對 schema。

- [S1] [v0.8.8 官方 Compose](https://github.com/LibreChat-AI/LibreChat/blob/v0.8.8/docker-compose.yml)：服務、mount、Mongo／Meili／pgvector/RAG，以及 dev image 引用。
- [S2] [v0.8.8 librechat.example.yaml](https://github.com/LibreChat-AI/LibreChat/blob/v0.8.8/librechat.example.yaml)、[v0.8.8 .env.example](https://github.com/LibreChat-AI/LibreChat/blob/v0.8.8/.env.example)：custom endpoints、Tavily／Firecrawl／SearXNG、OCR、fileConfig、credentials／domains。
- [S3] [Custom endpoints](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/custom_endpoint)：OpenAI-compatible endpoint 設定。
- [S4] [Web Search configuration](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/web_search)：搜尋、scraper、reranker；較新選項亦對照 S2。
- [S5] [Upload as Text](https://www.librechat.ai/docs/features/upload_as_text)：直接把支援文件內容加入 context。
- [S6] [RAG API repository](https://github.com/LibreChat-AI/rag-api)、[RAG environment variables](https://www.librechat.ai/docs/configuration/rag_api)：loaders、embedding 與 database 設定；獨立 repository 的版本另行鎖定。
- [S7] [Agents configuration](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/agents)：Agents 能力與工具配置。
- [S8] [OCR configuration](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/ocr)：document parser／OCR 的用途與邊界。
- [S9] [File configuration](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/file_config)：MIME、檔數與大小限制。
- [S10] [Conversation import](https://www.librechat.ai/docs/features/import_convos)：官方支援來源未列 Open WebUI；是否有新支持須部署時重查。
- [S11] [MongoDB production notes](https://www.mongodb.com/docs/manual/administration/production-notes/)：NFS 與 filesystem 建議。
- [S12] [v0.8.8 release](https://github.com/LibreChat-AI/LibreChat/releases/tag/v0.8.8)、[GitHub releases API](https://api.github.com/repos/LibreChat-AI/LibreChat/releases)：release 日期與 prerelease 標記。
- [S13] [Agents v4.0.1 Firecrawl implementation](https://github.com/LibreChat-AI/agents/blob/v4.0.1/src/tools/search/firecrawl.ts)：root URL、API version 與 scrape URL 組合；實作時依 lockfile 的實際 resolved library version 再查。
- [S14] [v0.8.8 file strategies](https://github.com/LibreChat-AI/LibreChat/blob/v0.8.8/api/server/services/Files/strategies.js)：document parser／Mistral OCR handlers，對照 current docs 的差異。
- [S15] [v0.8.8 custom endpoint initialization](https://github.com/LibreChat-AI/LibreChat/blob/v0.8.8/packages/api/src/endpoints/custom/initialize.ts)：custom gateway URL 驗證。

本機證據：root `README.md`／`.gitignore`、`ChatStack/docker-compose.yml`、`CONTAINER_MANAGER_DEPLOYMENT_DESIGNS.md`、`Komodo/DEPLOYMENT_DESIGN.md`、`homepage/docs/21-cloudflare-ingress-runbook.md`、2026-10-08 的 Docker／mount／DB 唯讀快照。舊設計文件描述的狀態若與現況不同，以本次 runtime snapshot 為準；現有 NPM／Cloudflare 實際 routing、Portainer polling、備份 job 與模型 API 能力尚未驗證。
