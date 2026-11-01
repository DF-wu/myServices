# LobeHub

直接整合在 `ChatStack/docker-compose.yml`，由既有 ChatStack 的 Portainer stack 管理，包含 `lobehub/lobehub:latest` 與 `ghcr.io/lobehub/lobehub-gateway:latest`。沿用既有 PostgreSQL、Redis、OpenList S3 與 new-api；本目錄保存設定範本、秘密產生器與資料庫前置 SQL，沒有另一份 Compose。

實際網址、內網位址、連線字串、bucket 與憑證，只填在 Portainer Environment 或本機忽略的 `compose.env.local`，不要提交至 Git 或貼進 PR。

## 設定

在 repo 根目錄產生本機設定檔：

```sh
node ChatStack/lobehub/generate-secrets.mjs ChatStack/lobehub/compose.env.local
```

helper 不連網、不啟動容器；檔案權限為 `0600`，已有檔案時拒絕覆蓋。備份原始 secrets，不要在既有部署上重新產生 vault key。

填完檔案中的空白欄位，再加入**既有 ChatStack** 的 Portainer Environment，保留原本其他服務的變數。完整欄位見 [compose.env.example](compose.env.example)：

- `LOBEHUB_APP_URL`：應用程式對外 HTTPS 網址。
- `LOBEHUB_DATABASE_URL`：專用 `lobehub` 資料庫的 PostgreSQL URI；帳號也是 `lobehub`。密碼與產生的 `LOBEHUB_POSTGRES_PASSWORD` 相同，URI 中的特殊字元須編碼。
- `LOBEHUB_REDIS_URL`：既有 Redis／Valkey 連線網址，使用 DB **9**。先確認這個 DB 沒有被其他服務使用。
- `LOBEHUB_NEWAPI_PROXY_URL`、`LOBEHUB_NEWAPI_API_KEY`：模型 API 入口與專用 client token。預設模型為 `deepseek-v4-flash`，可用 `LOBEHUB_CHAT_MODEL` 更改；先確認 token 的 group／額度可用該模型。
- `LOBEHUB_S3_ENDPOINT`、`LOBEHUB_S3_BUCKET` 及兩個 S3 keys：現有 OpenList S3 設定。endpoint 必須讓瀏覽器連得到；若既有反代已將根路徑轉入 OpenList S3，請勿重複附加該路徑或 bucket。
- `LOBEHUB_AGENT_GATEWAY_URL`、`LOBEHUB_DEVICE_GATEWAY_URL`：兩個 Gateway 的對外 HTTPS 網址，反代須支援 WebSocket。
- `LOBEHUB_AUTH_ALLOWED_EMAILS`：允許建立帳號的 email 清單。這不是既有使用者的停權清單；未啟用郵件驗證時，首次註冊先限制管理者來源。
- `LOBEHUB_SSRF_ALLOW_IP_ADDRESS_LIST`：需要存取私網 API 時，在 Portainer 填必要的 IP；不要為了連線方便全面關閉 SSRF 保護。

Gateway 只取得公開 JWKS；私有 JWKS、vault key 與模型憑證只送入應用程式。新使用者的預設對話 agent 與標題生成會使用同一個模型設定，預設啟用 Gateway Mode。

## 資料庫前置

由你將 `<postgres-container>` 換成既有 PostgreSQL 容器名稱，再執行：

```sh
docker exec -i <postgres-container> psql -U postgres -d postgres < ChatStack/lobehub/init-db.sql
docker exec -it <postgres-container> psql -U postgres -d postgres -c '\password lobehub'
```

互動輸入產生的資料庫密碼。SQL 建立專用 role、database 與 `vector` extension，不重設既有密碼；同名物件權限或 owner 不符時停止。應用程式使用 `pg_like` 全文搜尋，不要求 `pg_search`。啟動時的 schema migrations 由 LobeHub 自行執行。

## Portainer 與反代

1. 使用既有 ChatStack stack，Compose path 維持 `ChatStack/docker-compose.yml`；將 `LOBEHUB_*` 變數加入現有 Environment，不建立另一個 stack。
2. 先建立專用資料庫，確認既有 S3 bucket 可用。LobeHub 與 Gateway 使用 ChatStack 預設網路；應用程式會等待 PostgreSQL 啟動、Redis 和 Gateway 健康，以及 new-api 啟動。不需要額外 external network 或 `LOBEHUB_CHATSTACK_NETWORK`。
3. 應用程式 host port 預設 **43069**；Agent／Device Gateway 預設 **43070／43071**。反代目標使用部署主機和對應埠，開啟 HTTPS、WebSocket，關閉串流 buffering，適度放寬 read/send timeout。
4. Gateway 預設只綁 `127.0.0.1`。反代在其他主機時，先為兩個 Gateway 入口設定可信來源限制，再在 Portainer 指定 `LOBEHUB_GATEWAY_BIND_IP` 為可供反代連線的介面。維持 loopback 時，遠端反代無法串流；請勿直接將 Gateway 埠轉發至公網。

先前審查的上游 Gateway 版本，其 API-key 身分驗證會信任客戶端提供的身分查詢網址；公鑰設定無法阻止該分支。因此保留可信來源限制，直到確認實際拉取的 `latest` 已修正。參考：[上游認證實作](https://github.com/lobehub/lobehub-gateway/blob/0.5.0/agent-gateway-go/internal/gateway/auth.go)。`latest` 是浮動標籤，這裡不宣稱某次拉取已修復問題。

## 驗證與更新

部署前可只解析設定，不啟動服務：

```sh
docker compose --env-file <chatstack-env-file> --env-file ChatStack/lobehub/compose.env.local -f ChatStack/docker-compose.yml config -q
```

由你部署後確認：登入、預設 agent 串流回覆、標題生成、Gateway WebSocket `101`，以及 S3 上傳／預覽／刪除。S3 使用 path-style 和簽名讀取，`S3_SET_ACL=0`；不要求公開 bucket。

`<chatstack-env-file>` 需包含其他既有服務的變數。這份整合配置不使用 profile；更新 ChatStack 前必須填完 LobeHub 必要設定。若先前已建立獨立的 LobeHub stack，請先由你停止舊的兩個服務，再更新 ChatStack，以免容器名稱或埠衝突；保留並沿用原資料庫、S3 和 secrets。

本次只做靜態設定驗證，沒有實際部署或執行上述流程。檔案可用性取決於 OpenList 和其底層儲存；請將應用程式物件視為持久資料保存。

更新時由 Portainer 重新拉取兩個 `latest`。更新前備份資料庫、S3 檔案與 secrets；schema migration 後只換回舊映像未必能復原。停用 LobeHub 時，只停止 `lobehub` 和 `lobehub-gateway` 兩個服務，保留資料；不要對整個 ChatStack 執行 `down`，也不要清空共用 Redis 或整個 S3 bucket。
