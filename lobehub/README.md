# LobeHub + Agent Gateway

獨立的 **lobehub Portainer stack**，沿用 axolotl 的 ChatStack PostgreSQL 17、Valkey 與 OpenList S3。這次只修改部署 recipe；服務、資料庫前置設定、反代及驗收由你套用。

固定映像為 LobeHub **2.2.21** 和官方 Go Gateway **0.5.0**，同時鎖定 multi-architecture manifest digest；已確認都有 `linux/amd64`、`linux/arm64`。Gateway 的同一個程序包含 Agent Gateway 與 Device Gateway，不需要 Cloudflare Workers，也不需要另外架 Redis 或資料庫。

**Gateway 0.5.0 目前只適合可信、彼此互信的使用者。** 靜態審查確認其 API-key 身分驗證會信任客戶端提供的 `serverUrl`，沒有固定到你的 LobeHub；設定公鑰和 service token 也不會關閉這條路徑。Agent 與 Device Gateway 均受影響。因此 recipe 預設只把兩個 Gateway 埠綁在 `127.0.0.1`，不會直接開到 LAN／外部介面。最新正式版仍是 0.5.0；不能把它當成已修正的公開多租戶 Gateway。

在第 5 節完成 **兩個 Gateway NPM hosts 的可信來源 IP 白名單**後，才由你設定 `LOBEHUB_GATEWAY_BIND_IP=192.168.10.13`。若要服務不可信或任意來源的使用者，需先換成已修正的 Gateway：API-key 驗證必須固定到可信應用程式，連 redirect 也不能離開該來源。單純開放 host、增加 email 白名單或只測健康檢查，都不能解決這個問題。

## 這台主機的配置

- 應用程式：`43069 → 3210`，預定網址 `https://lobehub.dfder.tw`。
- Agent Gateway：`43070 → 8787`，預定網址 `https://lobe-agent.dfder.tw`。
- Device Gateway：`43071 → 8788`，預定網址 `https://lobe-device.dfder.tw`。
- Docker 網路：新 stack 的預設網路；只有應用程式另外加入既有 `chatstack_default`，連線 `chatstack-postgres17-pgvector` 和 `chatstack-unified-redis`。
- 資料庫／帳號：獨立的 `lobehub`／`lobehub`。共用 PG 有 `vector 0.8.7`，沒有 `pg_search`，所以明確使用 `FTS_SEARCH_PROVIDER=pg_like`。
- Valkey：**DB 9**、prefix `lobehub`。DB 8 已被既有 LibreChat 使用，不能照先前研究筆記拿來用。
- 模型入口：既有 new-api `http://192.168.10.13:43001`。使用穩定的主機 IP，對應 recipe 的 SSRF IP 白名單；沒有全面放行私網。
- S3：既有 `https://s3.api.dfder.tw`，bucket `s3-tmp`，對應 OpenList 的 `/Sinclair_OD/tmp`。

LobeHub 的帳號、會話和設定存在 PG，檔案存在 S3。這份 recipe 不需要新的 host bind mount 或 `/mnt/appdata/lobehub` 目錄。應用程式保留上游 UID 1001，避免 `/app` 權限不符；無持久檔案的 Gateway 使用 repo 慣例 `3000:3000`。兩個服務都有 healthcheck 和 log rotation。

以下現況於 **2026-10-31** 唯讀查核。Portainer 不同 stack 的更新順序不由 `depends_on` 管理，部署時 ChatStack 必須已經啟動，且主機埠 `43069–43071` 仍需確認沒有新占用。

## 1. 準備 Portainer Environment

在 myServices repo 根目錄執行本機 helper，只會建立一份新的秘密檔案：

```sh
node lobehub/generate-secrets.mjs lobehub/compose.env.local
```

需要本機 Node.js；沒有依賴套件，也不會連網或啟動容器。輸出檔使用 `0600`，並拒絕覆蓋既有檔案；`*.env.local` 已被 repo 忽略。這不是應用程式登入密碼產生器；使用者的密碼由註冊流程設定。

產生的六個值是專用 PG 密碼、vault key、auth secret、私有 JWKS、公有 JWKS、Gateway service token。兩份 JWKS 是同一組 RSA 2048／RS256 金鑰，有相同的 `kid`。Gateway **只取得公鑰**，私鑰只送入 LobeHub。

接著在產生的檔案填入四個空值，然後在 Portainer 的 stack **Environment variables → Load variables from .env file** 匯入：

- `LOBEHUB_AUTH_ALLOWED_EMAILS`：允許註冊的完整 email 清單，逗號分隔。先放你自己和預定的使用者。這個上游限制作用於**建立帳號**，不能用來撤銷已存在的使用者。
- `LOBEHUB_NEWAPI_API_KEY`：在 new-api 自行建立的 **LobeHub 專用 client token**，不是管理員 access token。選擇可使用預設模型的 group，設定合適額度；所有使用者會共用這把伺服器端 token。
- `LOBEHUB_S3_ACCESS_KEY_ID`、`LOBEHUB_S3_SECRET_ACCESS_KEY`：OpenList 管理介面 S3 設定中的現有兩個值。

其餘可選設定列在 [compose.env.example](compose.env.example)。Compose 本身已有非秘密的預設值；它不依賴 host 上的 `env_file`，也不需要把真實 `.env` 放進 Git。未填的必要值會在解析 Compose 時直接報錯。

Portainer 欄位中的 `LOBEHUB_JWKS_KEY`／`LOBEHUB_JWKS_PUBLIC_KEY` 是完整的一行 JSON，不要手動包額外的單引號。保留並另行備份產生的原始值。已有部署時不要重新產生：改掉 `KEY_VAULTS_SECRET` 會使舊有加密憑證無法解密；auth/JWKS 變更也會影響登入或 Gateway 認證。

這份基本配置使用 email／密碼登入，不要求 SMTP。**未驗證 email 的白名單不是身份證明**；先用 NPM Access List 限制只有你的來源 IP 能存取應用程式，完成預定帳號的註冊後，再調整來源。若要開放自行註冊給更多人，另行準備郵件驗證或 SSO；不要直接清空白名單。Gateway 仍須遵守上面的可信來源限制。

部署前可先做純解析檢查，命令不會建立容器，也不會列出秘密：

```sh
docker compose --env-file lobehub/compose.env.local \
  -f lobehub/docker-compose.yml config -q
```

## 2. 先建立專用 PG 資料庫

以下由你在 Docker 主機執行。`init-db.sql` 只針對 `lobehub` 建立 role／database／vector extension；不會升級或重啟共用 PG，也不會重設既有 role 密碼。遇到同名資料庫且 owner 不符會停止。

```sh
docker exec -i chatstack-postgres17-pgvector \
  psql -U postgres -d postgres < lobehub/init-db.sql

docker exec -it chatstack-postgres17-pgvector \
  psql -U postgres -d postgres -c '\password lobehub'
```

第二個命令會互動詢問密碼，填入產生檔內的 `LOBEHUB_POSTGRES_PASSWORD`。不要把真值放進 shell 命令。若是既有部署，維持原密碼，不要盲目重設。

recipe 的 `DATABASE_URL` 使用固定帳號／資料庫 `lobehub`。helper 產生的是 URL-safe 十六進位密碼；自行替換時需符合 PostgreSQL URI 編碼，避免 `@`、`:`、`/` 等字元破壞連線字串。LobeHub 每次啟動會自動執行自身 migrations，所以應用程式角色是此資料庫的 owner，但不是 PostgreSQL superuser。

## 3. OpenList S3

預設直接沿用已存在的 `s3-tmp` bucket。**不需要新增 RustFS／MinIO，也不需要修改 OpenList bucket 設定。** LobeHub 會在 bucket 內建立自身的物件路徑；這不是獨立 bucket 的權限隔離。如果你後續在 OpenList 自行配置專用 bucket，再改 `LOBEHUB_S3_BUCKET`。

`s3.api.dfder.tw` 是現有 NPM host 54：外部根路徑由反代轉入 OpenList 的 `/s3` 路由。`S3_ENDPOINT` 填 `https://s3.api.dfder.tw`，**不要再附加 `/s3` 或 `/s3-tmp`**。瀏覽器和 LobeHub 伺服器都用這個相同端點，避免自行改成帶 `/s3` 的內部網址後產生簽名路徑差異。容器需要能解析並連上這個網址。

已用預定的 `https://lobehub.dfder.tw` Origin 確認現有入口的 OPTIONS 預檢回 `204`，含允許上傳的 CORS headers。**尚未執行有簽名的 PUT／GET／HEAD／DELETE，也尚未實測 LobeHub 檔案流程。** recipe 使用 path-style、`S3_SET_ACL=0` 與簽名預覽，不要求 bucket 公開讀取。

這個 bucket 的底層是 `/Sinclair_OD/tmp`，目前透過 OneDrive WebDAV bridge 提供。bridge 的登入失效、學校端限流或上傳錯誤，都可能使 LobeHub 檔案功能失敗；S3 開啟不代表它具備本地物件儲存的可用性。不要把 bucket 或其路徑當成可定期清空的暫存資料夾。

## 4. 由你建立 Portainer stack

在 **Add stack → Repository** 設定：

- Name：`lobehub`
- Repository URL：`https://github.com/DF-wu/myServices.git`
- Repository reference：包含這份 recipe 的分支；合併至正式分支後使用 `refs/heads/master`。
- Compose path：`lobehub/docker-compose.yml`
- Environment：匯入並填完上一節的變數。

先確認前置資料庫、ChatStack 網路和 S3 設定，再由你按 Deploy。這份 recipe 不含 `build:`、資料庫自動初始化容器或其他既有服務的定義；獨立 stack 只建立兩個容器。

## 5. NPM HTTPS／WebSocket 入口

目前正式 NPM 位於 TrueNAS `http://192.168.10.10:7818`。先建立 IP Access List：只加入實際可信客戶端的固定 IP／必要 CIDR，其他來源一律拒絕。**Agent 與 Device 兩個 hosts 都必須選這個 Access List，不能設 Publicly Accessible。** 這是 Gateway 0.5.0 的必要存取限制；允許的客戶端也必須彼此互信，不能用來隔離互不信任的使用者。

由你新增以下三個 proxy hosts，使用既有 `*.dfder.tw` 憑證（目前 cert id 1）：

- `lobehub.dfder.tw` → `http://192.168.10.13:43069`
- `lobe-agent.dfder.tw` → `http://192.168.10.13:43070`
- `lobe-device.dfder.tw` → `http://192.168.10.13:43071`

開啟 Force SSL、Websockets Support；關閉 Cache Assets。Advanced 可沿用串流設定：

```nginx
client_max_body_size 100M;
proxy_buffering off;
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
```

Gateway hosts 若經 Cloudflare 代理，另外設定 `real_ip_header CF-Connecting-IP;`，並確認 NPM 的 trusted-proxy 清單正確，使來源白名單比對真正的客戶端 IP。不要把整個 Cloudflare IP 範圍當成可信客戶端來放行。先從未列入白名單的外部來源確認兩個 Gateway hosts 都被拒絕，再從可信來源確認 WebSocket 可連。

NPM 在另一台主機，無法連 axolotl 的 loopback 發布埠。上述來源限制完成後，在此 stack 的 Portainer Environment **明確新增 `LOBEHUB_GATEWAY_BIND_IP=192.168.10.13`**，再由你部署。這會把 Gateway 直接埠開到可信 LAN；不要轉發這兩個埠到 WAN，也不要將它們暴露到不可信 LAN。若維持預設 `127.0.0.1`，內部 LobeHub → Gateway 仍能連線，但遠端 NPM／瀏覽器不能完成對話串流；這是刻意保守的預設。

Gateway 的 `/ws` 需要完整保留 WebSocket upgrade，不能只讓首頁／health 通。`APP_URL` 和 Gateway 對外 URL 必須對應實際 HTTPS 網域。若沿用萬用 DNS，先確認新名字實際解析到這個 NPM 入口；不要改動既有 `chat.dfder.tw`、`chat2.dfder.tw` 或 S3 host。

LobeHub 內部對 Gateway 使用 `http://lobehub-gateway:8787`；瀏覽器使用 `https://lobe-agent.dfder.tw` 並升級為 WSS。Gateway 回呼則使用 `http://lobehub:3210`。Device Gateway 為 CLI／桌面連線提供 `https://lobe-device.dfder.tw`；基本對話不要求安裝任何裝置 agent。

## 6. 基本對話 agent 與驗收

預設模型是既有 new-api channel 中可見的 **`deepseek-v4-flash`**。這次只查核模型配置，沒有發出付費推論請求，也未驗證你之後建立的 token group。`LOBEHUB_CHAT_MODEL` 可改成你有權使用的模型，例如同樣出現在既有配置的 `gpt-4.1-mini`。

同一個變數會設定新使用者的預設 agent、預設模型清單及 system agent（對話標題等）。`DEFAULT_AGENT_CONFIG` 同時設 `chatConfig.disableGatewayMode=false`，讓新使用者的基本對話使用已配置的 Gateway；使用者可在設定 → 進階查看 Gateway Mode。既有帳號或既有 agent 的個別設定可能優先於新預設。

部署後由你確認：

1. Portainer 兩個服務 healthy。應用程式日誌有 migration pass；沒有缺少 `pg_search` 或 vector 權限錯誤。
2. **未列入白名單的來源**無法存取 Agent／Device Gateway。從可信來源連 `https://lobe-agent.dfder.tw/health` 和 `https://lobe-device.dfder.tw/health` 回 `OK`；未帶 service token 的 `/api/operations/*` 應被拒絕。這個 HTTP 拒絕測試不能證明上面的 WebSocket API-key 問題已修復。
3. 用白名單 email 註冊／登入，預設 agent 無須每人填 API key 即可回覆；標題也能產生。
4. 瀏覽器 Network 中，Agent Gateway 的 `/ws` 成功升級 `101` 並持續收到事件。再測切換頁面後回來查看同一會話。
5. 上傳一份小型文字檔與一張圖片，確認 S3 PUT、預覽 GET、metadata HEAD、應用程式刪除檔案均成功。用有視覺能力的模型驗證看圖，不能用純文字模型判斷圖片整合是否成功。
6. 新資料只出現在 `lobehub` 資料庫、Valkey DB 9 和對應 S3 物件路徑；其他 stack 保持原本狀態。

這份 recipe 先滿足基本對話與 Gateway；沒有配置外部程式執行沙盒、QStash 排程或額外搜尋服務。知識庫 embedding 另需配合 LobeHub schema 的 **1024 維**模型設定，不能直接沿用其他應用的 4096 維 embedding。

## 升級與回復

停用這個 stack 的自動 Git 更新，升級由你手動處理。映像固定 tag 和 digest，改 tag 時也需換對應 digest。每次升級前備份 `lobehub` 的邏輯 dump、S3 物件及秘密原件；PG schema migration 後，只換回舊映像不保證能還原。

如要撤回部署，只停止這個獨立 stack 並停用新增的三個 NPM hosts。保留 `lobehub` DB、S3 檔案及秘密供復原，不對 ChatStack 執行 `down`，也不清空共享 Valkey 或整個 `s3-tmp` bucket。Gateway 的執行中狀態在記憶體中，重新啟動會中斷進行中的 runs。

上游依據：[LobeHub v2.2.21 Compose](https://github.com/lobehub/lobehub/blob/v2.2.21/docker-compose/deploy/docker-compose.yml)、[環境變數](https://github.com/lobehub/lobehub/blob/v2.2.21/docs/self-hosting/environment-variables/basic.mdx)、[S3 設定](https://github.com/lobehub/lobehub/blob/v2.2.21/packages/env/src/file.ts)、[Gateway 0.5.0](https://github.com/lobehub/lobehub-gateway/tree/0.5.0)。

Gateway 身分驗證問題的原始碼依據：[Agent API-key 驗證](https://github.com/lobehub/lobehub-gateway/blob/0.5.0/agent-gateway-go/internal/gateway/auth.go#L38)、[Device API-key 驗證](https://github.com/lobehub/lobehub-gateway/blob/0.5.0/device-gateway-go/internal/gateway/auth.go#L36)。以上是原始碼審查結論，沒有對線上服務執行攻擊驗證。
