# LibreChat：ChatStack 並行服務

這裡提供服務定義與設定範例。五個新服務都在 `librechat` Compose profile 下；一般 ChatStack 更新不會啟動它們。候選入口為 `http://192.168.10.13:43006`。本階段沒有建立使用者、部署服務、設定公開入口或遷移對話。

| Service | 用途 | Host port |
|---|---|---|
| `librechat` | UI/API；既有 new-api 的 custom endpoint 與 Agents | 預設 `43006 → 3080` |
| `librechat-mongodb` | 對話、使用者與 metadata；專用 app 帳號 | 無 |
| `librechat-meilisearch` | 搜尋聊天歷史；不是網路搜尋 | 無 |
| `librechat-rag-api` | 遠端 embedding、文件索引與檢索 | 無 |
| `librechat-vectordb` | 專用 PostgreSQL 15 + pgvector | 無 |

MongoDB、Meilisearch、pgvector 僅連內部 backend network；LibreChat 與 RAG API 另連 ChatStack default network，以使用 new-api／外部 API。Open WebUI、共享 PostgreSQL、Valkey 與 Ollama 的設定保留原樣。

## 準備設定與儲存

在 Docker host 的 `ChatStack` 目錄操作；Portainer 的 Git checkout 和 `~/workspace/myServices` 是兩份檔案，不會自動同步。這裡固定從 host 的 config directory 掛入 YAML／Mongo 初始化檔，避免把 Portainer container 內的 `/data/compose/...` 當成 host path。

預設路徑：

- 本機 `/home/df/appdata/ChatStack/librechat/{config,mongodb,meilisearch,vectordb,data,logs,skill}`。
- NAS `/mnt/appdata/ChatStack/librechat/{images,uploads}`。
- 可透過 `LIBRECHAT_LOCAL_ROOT`、`LIBRECHAT_FILES_ROOT`、`LIBRECHAT_CONFIG_DIR` 分別覆寫；改 local root 時也要確認 config dir。所有 bind source 必須事先存在。

`/mnt/appdata` 是 NFS；新資料庫採本機路徑。主機的 `/home` 和 Docker data root 目前是 Btrfs；MongoDB 官方強烈建議 XFS，因此部署前確認所選底層、容量、權限及備份，必要時把 local root 放到本機 XFS／ext4。不要遞迴更改既有 ChatStack／NAS 根目錄的 ownership。

使用預設路徑時，準備指令如下；若覆寫路徑，對應修改這些指令：

```bash
rtk proxy sudo install -d /home/df/appdata/ChatStack/librechat/config
rtk proxy sudo install -d /home/df/appdata/ChatStack/librechat/mongodb /home/df/appdata/ChatStack/librechat/vectordb
rtk proxy sudo install -d -o 3000 -g 3000 /home/df/appdata/ChatStack/librechat/meilisearch /home/df/appdata/ChatStack/librechat/data /home/df/appdata/ChatStack/librechat/logs /home/df/appdata/ChatStack/librechat/skill
rtk proxy sudo install -d -o 3000 -g 3000 /mnt/appdata/ChatStack/librechat/images /mnt/appdata/ChatStack/librechat/uploads
rtk proxy sudo install -m 0644 librechat/librechat.yaml /home/df/appdata/ChatStack/librechat/config/librechat.yaml
rtk proxy sudo install -m 0644 librechat/mongo-init.js /home/df/appdata/ChatStack/librechat/config/mongo-init.js
rtk proxy cp librechat/compose.env.example librechat/compose.env.local
rtk proxy chmod 600 librechat/compose.env.local
```

`compose.env.local` 受 repository 的 `*.env.local` 規則忽略。這只是供本機驗證的私密設定；Portainer 部署時，將同一組新鍵值填入該 stack 的 environment，不要把檔案或完整 `compose config` 輸出上傳到公開 Git。

## 填寫環境變數

在 `compose.env.local`／部署端填寫：

- `LIBRECHAT_CREDS_KEY`：64 個 hex 字元；`LIBRECHAT_CREDS_IV`：32 個 hex 字元。分別可用 `rtk proxy openssl rand -hex 32`、`rtk proxy openssl rand -hex 16` 產生。
- JWT、JWT refresh、Mongo root／app、Meili 與 PostgreSQL 密鑰：各自產生不同的隨機值。Mongo app password 限 hex，避免 Mongo URI 特殊字元未編碼。LibreChat 與 RAG API 使用同一個 `LIBRECHAT_JWT_SECRET`；不要以 refresh secret 取代。
- `LIBRECHAT_PUBLIC_URL`：pilot 可用 `http://192.168.10.13:43006`；改為正式 HTTPS hostname 時更新此值及 ingress。預設 host bind 僅 LAN `192.168.10.13`，改主機或入口時須更新 `LIBRECHAT_HOST_BIND`；不要無意間開放所有介面。
- `LIBRECHAT_NEW_API_KEY`：new-api 的專用 consumer token；gateway 使用 `http://new-api:3000/v1`。
- `LIBRECHAT_TAVILY_API_KEY`：供網路搜尋及網頁 extract 使用。兩個 URL 欄位是完整 endpoint，預設 `/search`、`/extract` 的官方網址；若沿用既有相容轉發，兩者都要測試，不能直接複製一個 base URL。
- `LIBRECHAT_EMBEDDING_API_KEY`／`LIBRECHAT_EMBEDDING_BASEURL`：只提供給 RAG API；base URL 包含 `/v1`。模型候選 `qwen3-embedding-8b`，先測真實向量維度與相容性，避免把其他服務的 chat key 當作必然可用的 embedding key。RAG 已設定 `RAG_CHECK_EMBEDDING_CTX_LENGTH=false`，向 gateway 傳原始文字，避免 LangChain 把 Qwen 輸入轉成 OpenAI tokenizer 的 token ID；文件切塊及服務端長度限制仍須驗收。

啟用前在 staged `librechat.yaml` 的 `endpoints.custom` → `ChatStack` → `models.default`，將 `REPLACE_WITH_VERIFIED_VISION_MODEL` 換成 gateway 真正提供且支援 vision／tool calling 的模型 ID。此版本不會在模型清單中展開環境變數；保留 placeholder 會被啟動檢查拒絕。`models.fetch=false` 保留這份已驗證清單，避免 gateway 的模型探索結果覆蓋它。模型列出或文字聊天成功，不代表圖片與工具已通過驗收。網路搜尋亦需建立／選用有 `web_search` 工具的 Agent；僅加入 service 不會自動建立使用者或 Agent。

圖片、PDF、DOCX 已列入上傳 MIME 設定。文字型 PDF／DOCX 可用內建 parser／Upload as Text，長文件用 RAG／File Search。**掃描 PDF OCR 尚未預設啟用**；先取得可用的 Mistral OCR／相容服務，再填 OCR key/base URL 並啟用 YAML 中註解的 `ocr` 設定。不能將 Tika URL 填入便假定可用。

## 驗證與啟用

以下命令只解析設定；將目前 ChatStack 的 `.env`／`.secret.env` 一併帶入，保留現有服務需要的變數。若驗證環境由部署系統注入，使用其相同 env 即可。

```bash
rtk proxy docker compose --env-file .env --env-file .secret.env --env-file librechat/compose.env.local config --quiet
rtk proxy docker compose --env-file .env --env-file .secret.env --env-file librechat/compose.env.local --profile librechat config --quiet
rtk proxy docker compose --env-file .env --env-file .secret.env --env-file librechat/compose.env.local --profile librechat config --services
```

預設 profile-off 應不包含這五個新服務；profile-on 應包含它們。`config --quiet` 只驗證 Compose 格式，不能證明 secrets 有效；新服務的啟動檢查會拒絕必要值空白的設定。保留生成的密鑰，重建容器不可重置它們。

實際部署由原 **Portainer `chatstack` Git stack** 執行：確認 Git ref、取回更新、交付上述 config 檔和環境變數，並確認該版本如何啟用 Compose profiles。若它支援 `COMPOSE_PROFILES=librechat`，先檢查部署預覽真的包含新服務；不要假設只填 env 就一定啟用。管理介面若不支援 profiles，先處理這個部署入口限制，勿另外從 host 新建同名 stack／project。

試用入口確認登入、附件與串流後再設定公開 ingress。公開註冊預設關閉，初始使用者／管理員要依 v0.8.8 支援的方法建立；SMTP／密碼重設亦另行配置。

## 映像與驗收紀錄

2026-10-08 已確認五個映像的 manifest 提供 `linux/amd64` 和 `linux/arm64`，Compose 鎖定 manifest digest：

| 映像 | 版本／digest |
|---|---|
| `ghcr.io/librechat-ai/librechat` | `v0.8.8`；`5b706bcee1ca154a1e2987303aaeca0eb27f97919cccee4bb604226c2f8abf61` |
| `ghcr.io/librechat-ai/librechat-rag-api-dev-lite` | `a62ce2221b43a9bb57fa6cb733e7047c80132960272c33d5704028f3071a1251` |
| `mongo` | `8.0.20`；`098862b1339f031900ca66cf8fef799e616d6324fa41b9a263f2ec899552c1ef` |
| `getmeili/meilisearch` | `v1.35.1`；`8b57fc3c7f46535ddef3828df1538465ac19d892eb57c9a10da6df0880bd5856` |
| `pgvector/pgvector` | `0.8.0-pg15-trixie`；`8809cfffff0082cf260c9ac752f1dd1afc77f6f0a55c4e6411321e78efc3d9a5` |

已完成設定階段驗證：profile 開關都可解析、原有 service definitions 完全一致、鎖定主程式映像內的配置 schema 與 MIME allowlists 通過、缺少密鑰／未設定模型時啟動檢查會拒絕執行，RAG healthcheck 正確區分 UP／DOWN（包含 HTTP 200 的失敗 body）。這些是在隔離且無外部網路的暫時容器內檢查，並非功能 API 或生產部署驗收。

主程式 image metadata 的 `BUILD_BRANCH=v0.8.8`、`BUILD_COMMIT=e8f3be08623663d4ad7f7241e693c94469b63bb0`；RAG image 沒有 revision label，保留 digest 作為版本依據，不把 current RAG source 當成已部署版本。upstream 新 registry 在此主機解析為 `0.0.0.0`，所以使用其官方 GHCR 發佈來源。

部署後依 [完整遷移計劃](../LIBRECHAT_MIGRATION_PLAN.md) 驗收：圖片、帶來源的搜尋、PDF／DOCX、RAG 檢索、掃描 PDF OCR、使用者隔離、重啟持久化、備份復原。功能 API 驗收完成前仍保留 Open WebUI 作日常入口。

Mongo init script 只在首次建立空資料目錄時執行；後續改 env password 不會自動修改 DB 帳號。任何換密鑰／DB migration 須另行操作，不能刪資料目錄重置。備份包含 Mongo／PG 一致性 dump、附件、app runtime data、設定與密鑰；回復只停新服務或切回舊入口，不對整個 ChatStack 執行 `down` 或 `down -v`。
