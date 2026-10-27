# ChatStack：NyaProxy / Exa key pool

本目錄提供設定範本；服務已加進 `ChatStack/docker-compose.yml`。由你在 **Portainer 更新既有 ChatStack stack**，沒有另外部署新 stack，也沒有替你啟動容器。

沿用 ChatStack 的 `/mnt/appdata/ChatStack`、`user: 3000:3000`、`TZ=Asia/Taipei` 與 `unless-stopped`。對外只有一個 port：`43068`。

## 1. 在 Docker 主機準備檔案

從 myServices repo 根目錄執行以下操作。這些是你部署前要做的步驟，不會由 Portainer 自動複製：

```sh
mkdir -p /mnt/appdata/ChatStack/nyaproxy/data
cp ChatStack/nyaproxy/config.example.yaml /mnt/appdata/ChatStack/nyaproxy/data/config.yaml
cp ChatStack/nyaproxy/nginx.conf /mnt/appdata/ChatStack/nyaproxy/nginx.conf
```

`data/` 必須能讓 `3000:3000` 讀寫，`nginx.conf` 必須可讀。你的 appdata NFS 以 all_squash 映射至 UID 3000，請使用現有可寫的 NFS 掛載建立；不要讓 Docker 首次啟動才代建來源目錄，也不要在 NFS 上硬做 chown。若改放本機檔案系統，則讓資料目錄的擁有者／權限符合 `3000:3000`。

2026-10-28 已在本機準備好上述目錄與兩個設定檔：擁有者皆為 `3000:3000`，目錄 `0775`、檔案 `0664`，並驗證 `data/` 可以建立／寫入／atomic rename。尚未啟動服務或填入真實 keys；換主機時仍需重新準備。

**為何 Docker 不能直接代建？** 此主機的 `/mnt/appdata` 是 `192.168.10.10:/mnt/cachePool/appdata` 的 NFSv4 掛載。實測以 UID 1000 建立測試目錄後，NFS 回報擁有者為 `3000:3000`；改擁有者為 `0:0` 會得到 `EPERM / Operation not permitted`。Docker daemon 則以 root 執行，bind mount 來源不存在時不只 mkdir，還會嘗試將**新建**目錄 chown 成 daemon 的 root identity，這一步會被 NFS 的帳號映射／權限拒絕。Compose 的 `user: 3000:3000` 只決定容器內程序身分，不會改變 daemon 建來源目錄的身分。預先建立來源後，Docker 的「只處理新目錄」邏輯就不再改該目錄擁有者，因此不用放寬 NFS 的 squash 設定。[Docker/Moby 的 bind mount 建目錄邏輯](https://github.com/moby/moby/blob/v28.5.1/volume/mounts/mounts.go#L249-L263) 可見 `MkdirAllAndChown(...rootIDs..., WithOnlyNew)`。

只需首次複製 `config.example.yaml`；後續更新不要覆蓋 `data/config.yaml`，以免蓋掉 UI 內的設定。NyaProxy 的 `/app` **整個目錄可寫**：UI 儲存設定會先寫暫存檔再 rename，不能改成單檔唯讀掛載。此處也保存 `.nya_state.json`、rate-limit/cooldown 狀態及 app log。

## 2. Portainer 必填環境變數

在既有 ChatStack stack 的 **Environment variables** 填以下三項；可以先匯入 `portainer.env.example`，再填真值。

| 變數 | 格式／用途 |
| --- | --- |
| `NYAPROXY_ADMIN_KEY` | 你自訂的管理 token，登入 Dashboard / Config UI 用 |
| `NYAPROXY_API_KEY` | 另一個你自訂的 client token，提供給 Exa SDK、smart-search 等客戶端 |
| `NYAPROXY_EXA_API_KEYS` | 所有真實 Exa keys 的 **JSON array**，例如 `["EXA_KEY_A","EXA_KEY_B"]` |

三項都沒有內建密碼；未填時 Compose 會拒絕解析。Admin 和 client token 用不同的長英數字串，避免引號、換行及 `$`，因為 Compose 會把它們組成 JSON list。Portainer 的 Exa keys 值直接填 `[...]`，不要再加外層單引號；不要把真值提交至 repo。

實際送入 NyaProxy 的變數是：

```text
NYA_SERVER__API_KEY=["管理token","client token"]
NYA_APIS__EXA__VARIABLES__KEYS=["Exa key A","Exa key B"]
```

這是上游 Nacho 支援的環境變數覆寫，雙底線表示巢狀 key。第一把入口 token 是管理員，第二把只能做一般 API 呼叫。**Env 是 token/key list 的權威來源**：在 UI 改這些欄位會被環境變數覆蓋，換 key 請改 Portainer 變數並重建 NyaProxy 容器。不要把範本直接拿到沒有這兩個 env overrides 的服務執行；空 `server.api_key` 在上游代表停用認證。

選填：

| 變數 | 預設 | 用途 |
| --- | --- | --- |
| `NYAPROXY_HOST_PORT` | `43068` | 對外 port；NyaProxy 與入口的容器內 port 都固定 `8080` |
| `NYAPROXY_IMAGE_TAG` | `0.8.2` | 上游 NyaProxy tag；日後更新／回退可覆寫 |

NyaProxy `0.8.2` manifest 已確認有 `linux/amd64` 與 `linux/arm64`。2026-10-28 查核時 `0.8.2` 與 `latest` 同指 `sha256:8586bca6968065168f2926cb2e9cf946b14eba3c9da2de71c846e03f3742526d`；本次使用固定版本 tag。

## 3. 由你更新既有 Stack

既有 repository stack 保留：repository `https://github.com/DF-wu/myServices.git`、reference `refs/heads/master`、compose path `ChatStack/docker-compose.yml`。先把本次變更同步到 Portainer 實際讀取的 Git reference；如果直接貼 Compose，使用更新後的完整 ChatStack Compose。

確認上面的兩個 host 檔案與三項 env 都備妥，再由你在 Portainer Pull / Update / Redeploy。不要只部署 `nyaproxy-gateway`：它會等 `nyaproxy` healthy 才啟動；兩者留在同一個 ChatStack 預設網路即可，不需要新增 PostgreSQL 或 Redis。

部署後：

- Dashboard／登入入口：`http://<Docker主機>:43068/dashboard/`，使用 `NYAPROXY_ADMIN_KEY`。根路徑 `/` 只是 welcome JSON。
- Config UI：`http://<Docker主機>:43068/config`，同樣用管理 token。
- Exa REST base URL（主機／區網客戶端）：`http://<Docker主機>:43068/api/exa`。
- Exa REST base URL（同一 ChatStack 內）：`http://nyaproxy-gateway:8080/api/exa`。
- Health：`http://<Docker主機>:43068/health`。這只檢查 gateway 和 NyaProxy 存活，不會消耗 Exa 額度，也不保證每把 key 有效。

## 4. 客戶端設定

對原生 Exa SDK 或只送 `x-api-key` 的客戶端：

```text
EXA_BASE_URL=http://<Docker主機>:43068/api/exa
EXA_API_KEY=<NYAPROXY_API_KEY 的同一個值>
EXA_TIMEOUT_SECONDS=120
```

**客戶端拿的是 pool 的 client token，不是真實 Exa key**；真實 keys 只放 `NYAPROXY_EXA_API_KEYS`。不要加 `/v1`、`/v2` 或再次附加 `/search` 到 base URL。

ChatStack 既有的 Catalina / Claudia 已經有 smart-search env 映射，不必再改服務定義。要讓兩者的 smart-search 改走此 pool，另外在同一份 Portainer Environment 設定：

```text
SMART_SEARCH_EXA_BASE_URL=http://nyaproxy-gateway:8080/api/exa
SMART_SEARCH_EXA_API_KEY=<NYAPROXY_API_KEY 的同一個值>
SMART_SEARCH_EXA_TIMEOUT_SECONDS=120
```

同時更新這些 client 容器才會收到新的 env。既有 smart-search 若已把設定寫入 `/data/.config/smart-search/config.json`，還要確認其設定來源；若持久化值優先，以該 client 的 `smart-search config set` 更新 `EXA_BASE_URL` / `EXA_API_KEY` / `EXA_TIMEOUT_SECONDS`。這次沒有更動任何 client 的真實設定或持久化檔案。

也支援手動帶 `Authorization: Bearer <NYAPROXY_API_KEY>`。NyaProxy 原生僅接受 Bearer，故 `nyaproxy-gateway` 用標準 Nginx 在 `/api/exa/` 將 client 的 `x-api-key` 轉成 Bearer；NyaProxy 驗證後再把選到的 **真實 key** 注入上游 `x-api-key`。入口 Exa 路由會清除 Cookie，**NyaProxy Exa provider 也以 `Cookie: ""` 覆寫上游 header**，避免編碼路徑繞過入口匹配後仍將管理登入 token 轉送至 Exa。管理介面不受這個 Exa 上游規則影響，仍由 NyaProxy 驗證。若兩個 header 都帶，明確的 Authorization 優先。

## 行為與限制

- 正常請求按可用 keys 順序 round robin；401/402 暫時排除該 key 300 秒，當次可換下一把；429/5xx 進入短冷卻並重試。403、400 等其他錯誤不因 key pool 而盲目重試。
- 最多 3 次嘗試；只有 GET/POST 啟用狀態碼重試。此設定首先服務 Exa search / contents / findSimilar / answer；若使用會建立付費非同步工作的 API，請另行確認其重試語義。
- `queue.expiry_seconds` 與 `request_timeout_seconds` 都設 90 秒：前者從**首次入列**計算年齡、重試不重設；後者同時包住整個 queue future，也用來推算上游 HTTP timeout。所有等待／嘗試共用這個預算，不保證能完整執行 3 次。客戶端與入口設 120 秒以容納 gateway 回傳，不能藉此延長 NyaProxy 的 90 秒。全池被封鎖時可能等候後回 gateway 504；重試用盡也可能回 gateway 429，並非永遠保留最後一個 Exa status。
- 入口最多接受 32 MiB 請求，關閉 proxy buffering 以保留串流。Docker DNS 每 10 秒重新解析，以處理 NyaProxy 容器重建後的 IP 變更。
- 同一 Exa team 的 keys 共用 QPS 與 team 額度，輪詢不會提高 team 上限。補足額度後可等冷卻結束；冷卻狀態會跨服務重啟保存。
- 未指定信任代理 IP，NyaProxy 不採信任意 client 的 X-Forwarded-For。若後續啟用 NyaProxy IP 限流，需一併設定可信代理；目前 rate_limit 預設關閉。

來源：[NyaProxy 0.8.2 原始碼／README](https://github.com/Nya-Foundation/NyaProxy/tree/21db6859c2d89420731af80747670c2a530634f4)、[Exa billing / team rate limits](https://exa.ai/docs/admin/billing)。
