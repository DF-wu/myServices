# deepseek-harness

把官方 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）以 [misaka-link/deepseek-harness-docker](https://github.com/misaka-link/deepseek-harness-docker) 的容器套件跑起來。這份目錄不是上游原始碼，而是 `myServices` 內的部署定義。

## 目前狀態（2026-10-26）

| 項目 | 狀態 |
| --- | --- |
| Recipe 預設 | `latest-market`（當時指向 0.2.9-market，內建 DSH 0.2.1-rc.3）、host port `43066`、`TRUST_PROXY=1` |
| 資料目錄 | `/mnt/appdata/deepseek-harness/{dsh,snapshots,workspace,browser}` 四個都已建立 |
| 容器 | 尚未成功啟動過。2026-10-16 兩次 Portainer 部署因掛載目錄不存在、Docker 自動建立時 chown 失敗而中止（見「持久化」）；2026-10-26 那次拉到的是還沒 push 的舊 master，host port 仍是 `43065`，撞到 LibreChat |
| NPM | `dsh.dfder.tw` 已建立（proxy host id 52），**刻意保持停用**，等 `/setup` 設好口令後再啟用 |
| homepage / glance | 尚未加入 |

## 這個 image 實際上是什麼

image 以 `node:24-trixie` 為底，內建 `@deepseek-ai/dsh`，前面再包一層上游自寫的 Node gateway。gateway 是唯一對外的入口，負責認證、反代 DSH Web，同時提供：

- `/` — DSH Web 工作區
- `/admin/` — Web Admin 控制台（DSH 核心版本線上切換、快照備份 / 還原、插件管理、桌面設定）
- `/vnc/` — 容器內真實 Chromium 的 noVNC 桌面（給 `dsh-browser-desktop` 插件讓 AI 操作網頁）
- `/healthz` — 免認證的健康檢查

三個入口共用同一個 port 與同一組訪問口令。DSH 的 agent 在容器內以 root 執行指令，拿到口令就等於拿到容器內的 shell 與瀏覽器。

## 部署步驟

依序做，順序本身就是安全措施。

**1. commit 並 push 這個目錄。** Portainer 從 GitHub 的 `master` 拉檔案，不讀 axolotl 上的工作目錄；沒 push 就會部署到舊的 `43065` 版本，和 LibreChat 撞 port。

```bash
cd ~/workspace/myServices
git add deepseek-harness/
git commit -m "..."
git push
```

**2. 確認四個資料目錄都存在**（目前已建立；換主機或改 `DSH_APPDATA_DIR` 時要重做，理由見「持久化」）：

```bash
mkdir -p /mnt/appdata/deepseek-harness/{dsh,snapshots,workspace,browser}
```

**3. 在 Portainer 建 stack**：Stacks → Add stack → Repository。

| 欄位 | 值 |
| --- | --- |
| Name | `deepseek-harness` |
| Repository URL | `https://github.com/DF-wu/myServices.git` |
| Repository reference | `refs/heads/master` |
| Compose path | `deepseek-harness/docker-compose.yml` |
| Authentication | 關（公開 repo） |
| GitOps updates | 建議關閉（理由見「部署決策」） |
| Environment variables | 不需要填；預設值都在 `.env`。要覆寫哪些、怎麼填見下一節 |

**4. 部署後自己確認，不要只看成功提示。** Portainer 是非同步部署，compose 失敗也可能先跳成功 toast。

```bash
docker ps --filter name=deepseek-harness --format '{{.Status}}'   # 要看到 (healthy)
curl -fsS http://192.168.10.13:43066/healthz
```

`healthy` 只代表 gateway 活著；`/healthz` 回應裡要看到 `"dsh":{"running":true,"ready":true}` 才代表 DSH 核心就緒，此時 `setupRequired` 應為 `true`。

**5. 從區網設口令**：打開 `http://192.168.10.13:43066/setup`。

- `/setup` 沒有任何驗證，第一個送出的人就成為擁有者；設好之後再送出會被拒絕（409），只能到 Admin 改。
- 上游只要求 6–256 字元並擋掉少數常見弱口令（`admin`、`123456`、`deepseek` 等），但登入限流只有「同一 IP 失敗 5 次鎖 1 分鐘」，服務又要公開到網際網路，請用長的隨機口令。
- 設完再查一次 `/healthz`，`setupRequired` 要變成 `false`。

**6. 啟用 NPM 的 `dsh.dfder.tw`**：NPM（`http://192.168.10.10:7818`）→ Hosts → Proxy Hosts → `dsh.dfder.tw` 那一列的選單 → Enable。之後 `https://dsh.dfder.tw/` 應該導向 `/login`。

## Portainer 環境變數

不填任何變數就能部署。Stack Environment 只能覆寫 compose 以 `${VAR}` 映射、或 `.env` 寫成 `KEY=${KEY:-}` 的變數：

| 變數 | 預設 | 說明 |
| --- | --- | --- |
| `DSH_IMAGE_TAG` | `latest-market` | 回退時改成工程版本 tag，例如 `0.2.8-market` |
| `DSH_HOST_PORT` | `43066` | `43065` 是 LibreChat，不要用 |
| `DSH_APPDATA_DIR` | `/mnt/appdata/deepseek-harness` | 改了要先在新路徑建好四個子目錄 |
| `TZ` | `Asia/Taipei` | |
| `TRUST_PROXY` | `1` | 見「放到反代後面」 |
| `PUBLIC_HOST` | 空 | 見「放到反代後面」 |
| `AUTH_TOKEN` | 空 | **建議不設**，用 `/setup`。設了就是 env 優先：在 Admin 改口令後 gateway 會自動重啟，隨即被 env 蓋回去，等於改不了；要換只能改 Portainer 變數再重新部署 |
| `SESSION_SECRET` | 空 | 留空會自動產生並持久化；要設至少 16 字元，否則被忽略 |
| `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` | 空 | 出站代理。留空時容器內是空字串，entrypoint 不會另外 export 小寫版本，等同不用代理 |
| `NO_PROXY` | `localhost,127.0.0.1` | 設了代理時要保留這兩個（healthcheck 走 `127.0.0.1`），再加上區網模型端點，例如 `192.168.10.13` |
| `DSH_VERSIONS_MIN_FREE_MB` | `1536` | 線上切換核心版本前的磁碟水位門檻 |

注意：

- **compose 與 `.env` 都被註解掉的選用參數（`DSH_DESKTOP_ENABLED`、`DSH_IDLE_TIMEOUT_MINUTES` 等）在 UI 填了也沒用**，部署會成功但設定被靜默忽略。這類設定請到 Admin 改。在 `.env` 寫成 `KEY=${KEY:-預設}` 雖然能讓 UI 覆寫，但桌面設定在第一次啟動後就以持久化值為準（見「部署決策」），只有首次部署前填才有效。
- **Portainer 寫入值時不加引號**：`$` 會被當成變數展開，` #` 之後會被當成註解切掉，開頭是引號的值甚至會讓整個部署解析失敗。只用英數字與 `._-` 最安全；非用不可時整個值用單引號包起來。代理 URL 裡的帳密要 URL encode。

## 部署決策

**容器內 port 固定 3080。** 上游 compose 讓 `PROXY_PORT` 同時決定 host 與容器 port，但 image 的 `HEALTHCHECK` 寫死 `curl http://127.0.0.1:3080/healthz`，容器內改 port 就會永遠 unhealthy。所以這裡只開放改 host 端的 `DSH_HOST_PORT`（預設 `43066`，延續 myServices AI 工具的 43xxx 區段；`43065` 已被 ChatStack 的 LibreChat 占用，NPM 的 `chat.dfder.tw` 指向那裡）。

**用 market 變體，tag 用 `latest-market`，不手動維護版本。** market 版在純淨版之上預裝社群應用市場 `dshmarket` 與思考強度調節插件 `@hytime/dsh-thinking-effort`，這兩個插件在 image build 時跟隨 `@latest`。上游每次 build 推三個變體：純淨版（無後綴）、`-market`、`-mini`（拿掉 Chromium / noVNC 桌面）。每個變體都打五個 tag，以 market 為例：`latest-market`、`0.2.9-market`、`v0.2.9-market`（套件工程版本）、`0.2.1-rc.3-market`、`dsh-0.2.1-rc.3-market`（內建 DSH 版本），另外還有 `market`、`mini` 兩個舊式別名。

- 更新：Pull and redeploy 時打開「Re-pull image and redeploy」才會真的拉到新版。
- 回退：把 `DSH_IMAGE_TAG` 改成上一個工程版本 tag（例如 `0.2.8-market`；`0.2.5`、`0.2.6` 沒有發佈）。內建 DSH 版本 tag 會被後續 build 覆寫（0.2.8 與 0.2.9 都推了 `0.2.1-rc.3-market`），不能當回退點。
- GitOps auto-update 建議關閉：CE 版比對的是整個 myServices repo 的 commit，任何目錄有 commit 都會觸發重新部署並強制重拉 image，image 有新版就重建容器。上游發版很密、DSH 核心還是 rc，這等於無人值守升級。
- DSH 核心本身另外可以在 `/admin/` 線上切換，不必換 image。
- 純淨版與 market 版只有 `linux/amd64`，不能部署到 oracle-arm；`-mini` 有 `linux/arm64`，但沒有 `/vnc/` 桌面。

**環境變數與 Admin 設定的優先順序。** gateway 的設定存在 `/root/.dsh/gateway.config.json`，各項的權威來源不同（對照上游 v0.2.9 原始碼）：

- 桌面設定（`DSH_DESKTOP_*`、`DSH_IDLE_TIMEOUT_MINUTES` 等）：持久化優先。第一次啟動時 env 值就會寫進 `gateway.config.json`，之後改 env 不會生效，要到 Admin 改；或刪掉 `gateway.config.json` 重來。口令也存在裡面，會一起被清掉，`/setup` 隨即重新開放、誰先送出誰就是擁有者，所以刪之前先在 NPM 停用 `dsh.dfder.tw`（或先停容器），設好口令再啟用；Admin 的「清除口令」同理。
- `TRUST_PROXY`、`PUBLIC_HOST`：實際上由 env 決定。程式雖然會先讀持久化值，但 Admin 沒有欄位寫入這兩項，第一次啟動也不會存，所以改 `.env` 或 Portainer 變數後重新部署就生效。
- 顯式 env 優先：`PROXY_PORT`、`ADMIN_PATH`、`VNC_PATH`、`AUTH_TOKEN`。
- `/healthz` 的 `configSource` 會顯示 port、路徑與口令實際取自哪裡。
- `DSH_IDLE_TIMEOUT_MINUTES=0` 經 env 設定無效（會回到 30），要永不休眠請在 Admin 設。

**秘密不進 repo。** `.env` 隨 Repository 拉取，只保存可提交的預設值；`AUTH_TOKEN`、`SESSION_SECRET` 與三個代理 URL 都寫成 `${同名變數:-}`，實際值只會來自 Portainer 的 Stack Environment。口令預設走 `/setup`，所以通常什麼秘密都不必放進 Portainer。

**保留上游的容器加固。** `no-new-privileges` + `cap_drop: ALL`，只回補上游 compose 列的 `CHOWN`、`DAC_OVERRIDE`、`FOWNER`、`SETUID`、`SETGID`、`KILL`（root 管理檔案權限、`cp -a` 歸檔與 Xvfb / Chromium 等子程序需要）。上游的非 root（`user: 1001:1001`）選項要求先把 host 目錄 chown 成 `1001:1001`，這一步在 all_squash 的 NFS 上會被拒絕，無法照上游步驟啟用。

## 持久化

| Host 路徑 | 容器路徑 | 內容 |
| --- | --- | --- |
| `/mnt/appdata/deepseek-harness/dsh` | `/root/.dsh` | DSH 設定、profile、插件、會話、口令、session secret、`gateway.config.json` |
| `/mnt/appdata/deepseek-harness/snapshots` | `/root/.dsh-snapshots` | 設定快照、`versions/` 核心版本歸檔 |
| `/mnt/appdata/deepseek-harness/workspace` | `/workspace` | AI 工作區 |
| `/mnt/appdata/deepseek-harness/browser` | `/root/.config/chromium` | 容器 Chromium profile（登入狀態 / cookies） |

axolotl 的 `/mnt/appdata` 是 TrueNAS（192.168.10.10）匯出的 NFS，所有寫入都會變成 uid 3000（all_squash），這帶來兩個後果：

- **掛載來源必須事先建好。** 目錄不存在時，Docker 會自動建立並 chown 成 root，在這個 NFS 上一定被拒絕（`error while creating mount source path ... operation not permitted`），容器啟動 API 回 500、stack 部署失敗。2026-10-16 的兩次部署就是這樣失敗的；`dsh/`、`workspace/` 是那兩次留下的空目錄。
- **`0600` 擋不住其他 NFS 用戶。** 口令以明文存在 `gateway.config.json`（`0600`），但在 all_squash 下任何 NFS 客戶端的使用者都會被視為擁有者而讀得到；`snapshots/` 與 `browser/` 是 `777`，前者的快照含 `/root/.dsh` 的內容，後者有 Chromium 的 cookies。這和其他 appdata 服務的處境相同。

## 放到反代後面

對外網址是 `dsh.dfder.tw`，走 TrueNAS 上的 NPM（`http://192.168.10.10:7818`，proxy host id 52）。`*.dfder.tw` 有萬用 DNS 與萬用憑證，不必另外申請。DNS 在 Cloudflare 上是**橘雲代理**：公開 DNS 解析到 Cloudflare IP，區網 DNS（`192.168.10.1`）則回家裡的公網 IP `59.127.185.17`，所以從區網看起來像直連。網際網路的請求一律是「瀏覽器 → Cloudflare → NPM → gateway」。Proxy host 設定：

| 欄位 | 值 |
| --- | --- |
| Domain Names | `dsh.dfder.tw` |
| Scheme / Forward Hostname / Port | `http` / `192.168.10.13` / `43066` |
| Websockets Support | 開（DSH Web 與 noVNC 都靠 WebSocket） |
| Block Common Exploits / Cache Assets | 關 / 關（與 `chat.dfder.tw` 相同） |
| Access List | Publicly Accessible |
| SSL Certificate | `*.dfder.tw`（cert id 1） |
| Force SSL / HTTP/2 / HSTS | 開 / 開 / 關 |

Advanced。快照匯入 / 還原、插件安裝與長對話串流都是長請求，NPM 預設的 `proxy_read_timeout` 是 90 秒，超過就會回 504；gateway 建立快照的 tar 逾時預設 30 分鐘（`DSH_SNAPSHOT_TIMEOUT_MS`），還原解壓固定 10 分鐘：

```nginx
client_max_body_size 50000M;
proxy_buffering off;
proxy_read_timeout 1800s;
proxy_send_timeout 1800s;
```

這些設定只對區網直連 NPM 的流量完全有效。經 Cloudflare 時，Free / Pro 方案的上傳上限是 100 MB（回 413），origin 100 秒內沒回應就會被切斷（回 524），NPM 這邊調不了；大快照的匯入 / 還原請走區網 `http://192.168.10.13:43066`。gateway 本身的上傳上限是 300 MB，`client_max_body_size` 其實設 `300M` 就夠。

**只在 `/setup` 設好口令之後才啟用這個 host**（步驟 5、6）。`dsh.dfder.tw` 一啟用就是公開的。

- `TRUST_PROXY` 預設 `1`，登入限流採用 `X-Forwarded-For`，才不會把所有人算成 NPM 那一個 IP，一人輸錯就全體被鎖。gateway 只取 XFF 最右一個 IP，也就是 NPM 寫入的 `$remote_addr`。

  **目前這個 IP 可以被偽造。** NPM 對來自 Cloudflare 與私有網段（`10/8`、`172.16/12`、`192.168/16`）的請求會採信 `X-Real-IP` 改寫 `$remote_addr`，而公網流量全都從 Cloudflare 進來，所以網際網路上的人很可能自填 `X-Real-IP` 就能換 IP 繞過限流（Cloudflare 是否原樣轉送這個標頭是推論，未實測）；直接連 `43066` 的區網 / tailnet 用戶也能自帶 XFF。限流只是輔助，口令本身要夠強。

  要讓公網限流可靠，在 host 52 的 Advanced 加一行 `real_ip_header CF-Connecting-IP;`：這個標頭由 Cloudflare 覆寫，用戶端偽造不了（前提是 NPM 已載入 Cloudflare IP 段）。不要在 server 區塊另寫 `set_real_ip_from`，那會整份取代 NPM 預設的信任清單。若 `43066` 會直接暴露給不可信網路，請把 `TRUST_PROXY` 改回 `0`。
- `PUBLIC_HOST` 預設留空。gateway 的 WebSocket 同源校驗認真實 `Host` 頭與這份白名單（不認 `X-Forwarded-Host`），上游 `gateway/ws-origin.js` 是逐字精確比對，不支援 `*` 萬用字元。NPM 會保留原始 `Host`，所以留空即可；只有反代改寫 `Host` 時才需要填真實的對外 hostname。
- Cookie 的 `Secure` 屬性依 NPM 送來的 `X-Forwarded-Proto: https` 判斷，不需要額外設定。

## DeepSeek 帳號登入

DeepSeek 平台只接受 loopback 的 OAuth 回調（`http://localhost:<port>/oauth/callback`）。上游補丁會把回調 origin 改成 `http://localhost:<瀏覽器網址上的 port>`，遠端登入有兩種做法：

1. SSH 隧道：`ssh -L 43066:127.0.0.1:43066 df@<host>`，再用 `http://localhost:43066/` 發起登入，回調會自動落回本機。本機與遠端 port 要一致。
2. 內建登入助手插件：在 DSH 左下角帳號選單按「Sign in」，打開登入連結，登入後瀏覽器會跳到打不開的 `localhost` 回調網址，把整串網址貼回彈窗的「回調連結」即可。也可以直接開 `/account/callback` 頁面貼。從 `https://dsh.dfder.tw` 登入時用這個方法。

不登入帳號也可以直接在 DSH 設定裡填 API Key（例如走 ChatStack 的 new-api）。

## 已知限制

以下由原始碼與這台主機的 NFS 行為推論，尚未在正式部署上實測：

- **`/workspace` 內的 git 可能報 `dubious ownership`。** NFS 上檔案屬主都是 3000，容器內 git 以 root 執行，DSH 的工作區變更檢視與 agent 的 git 操作可能受影響。修法：掛一個含 `[safe] directory = *` 的 `/etc/gitconfig`，或把 `/workspace` 移到本機磁碟 / named volume。
- **核心版本歸檔在 NFS 上會失敗。** 線上切換核心時，root 以 `cp -a` 把目前版本歸檔到 `snapshots/versions/`，保留屬主這一步在 NFS 上失敗。切換本身仍然成功，只是回切時要重新下載。要修可另掛 named volume 並設 `DSH_VERSIONS_DIR`。
- **容器日誌沒有輪替。** recipe 沒有 `logging:` 設定，daemon 也沒有預設上限，可比照 ChatStack 加 `max-size`。
- **執行期 npm registry 預設是 `registry.npmmirror.com`。** 插件安裝與線上切換核心都走它；要改用 npmjs，需在 compose `environment` 加 `NPM_REGISTRY`。

## 尚未做的事

- 部署並完成上面的步驟 4 到 6。
- 加進 homepage / glance。
- 視需要在 NPM host 52 加 `real_ip_header CF-Connecting-IP;`，讓公網登入限流認得真實 IP（見「放到反代後面」）。
- 視需要處理「已知限制」：gitconfig `safe.directory`、日誌輪替、把 volumes 改成長語法並設 `bind.create_host_path: false`（缺目錄時直接報清楚的錯，而不是 chown 失敗）。
