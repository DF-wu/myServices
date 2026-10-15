# deepseek-harness

把官方 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）以 [misaka-link/deepseek-harness-docker](https://github.com/misaka-link/deepseek-harness-docker) 的容器套件跑起來。這份目錄不是上游原始碼，而是 `myServices` 內的部署定義。

## 這個 image 實際上是什麼

image 以 `node:24-trixie` 為底，內建 `@deepseek-ai/dsh`，前面再包一層上游自寫的 Node gateway。gateway 是唯一對外的入口，負責認證、反代 DSH Web，同時提供：

- `/` — DSH Web 工作區
- `/admin/` — Web Admin 控制台（DSH 核心版本線上切換、快照備份 / 還原、插件管理、桌面設定）
- `/vnc/` — 容器內真實 Chromium 的 noVNC 桌面（給 `dsh-browser-desktop` 插件讓 AI 操作網頁）
- `/healthz` — 免認證的健康檢查

三個入口共用同一個 port 與同一組訪問口令。

## Portainer 設定

| 欄位 | 值 |
| --- | --- |
| Stack name | `deepseek-harness` |
| Build method | Repository |
| Repository URL | `https://github.com/DF-wu/myServices.git` |
| Repository reference | `refs/heads/master` |
| Compose path | `deepseek-harness/docker-compose.yml` |
| Environment variables | 可全部不填；要覆寫時參考 `.env.example` |

部署後入口：

```text
http://<host>:43065/          DSH Web
http://<host>:43065/admin/    Web Admin
http://<host>:43065/vnc/      Chromium 桌面
```

## 部署決策

**容器內 port 固定 3080。** 上游 compose 讓 `PROXY_PORT` 同時決定 host 與容器 port，但 image 的 `HEALTHCHECK` 寫死 `curl http://127.0.0.1:3080/healthz`，容器內改 port 就會永遠 unhealthy。所以這裡只開放改 host 端的 `DSH_HOST_PORT`（預設 `43065`，延續 myServices AI 工具的 43xxx 區段）。

**用 market 變體，tag 用 `latest-market`。** market 版在純淨版之上預裝社群應用市場 `dshmarket` 與思考強度調節插件 `@hytime/dsh-thinking-effort`，開箱就能從市場裝插件。上游每次 build 會打三種 tag：`latest-market`、內建 DSH 版本（如 `0.2.1-alpha.3-market`）、套件工程版本（如 `0.2.4-market`）；這裡跟著 `latest-market` 走。Portainer 重新部署時要勾「Re-pull image」才會拉到新版；新版出問題就把 `DSH_IMAGE_TAG` 改成上一個工程版本 tag（例如 `0.2.4-market`）回退。DSH 核心本身另外可以在 `/admin/` 線上切換，切換歸檔放在 snapshots 卷，容器重建也不會丟。想用純淨版就改成 `latest`。目前只有 `linux/amd64`，不能部署到 oracle-arm。

**環境變數只是初始預設值。** 桌面、反代（`TRUST_PROXY` / `PUBLIC_HOST`）等設定在 Admin 存檔後會寫進 `/root/.dsh/gateway.config.json`，之後以持久化設定為準；只有 `PROXY_PORT` 是顯式 env 優先。上游把這類設定的權威收斂在 Admin，所以 compose 裡的選用參數跟上游一樣保留成註解，要用再打開。另外 `DSH_IDLE_TIMEOUT_MINUTES=0` 經 env 設定無效（會回到 30），要永不休眠請在 Admin 設。

**訪問口令不進 git。** `AUTH_TOKEN` 預設留空，第一次打開會被導到 `/setup` 設定口令，口令以 `0600` 寫進 `/root/.dsh`，session secret 也是第一次啟動自動產生並持久化。重建容器不會失效。

**保留上游的容器加固。** `no-new-privileges` + `cap_drop: ALL`，只回補 entrypoint 以 root 修正卷權限與管理子程序所需的 capability。

## 持久化

| Host 路徑 | 容器路徑 | 內容 |
| --- | --- | --- |
| `/mnt/appdata/deepseek-harness/dsh` | `/root/.dsh` | DSH 設定、profile、插件、會話、口令、session secret、`gateway.config.json` |
| `/mnt/appdata/deepseek-harness/snapshots` | `/root/.dsh-snapshots` | 設定快照、`versions/` 核心版本歸檔 |
| `/mnt/appdata/deepseek-harness/workspace` | `/workspace` | AI 工作區 |
| `/mnt/appdata/deepseek-harness/browser` | `/root/.config/chromium` | 容器 Chromium profile |

容器以 root 執行，目錄不存在時 Docker 會自動以 root 建立，不需要先 `mkdir`；entrypoint 會把 `/root/.dsh` 收斂成 `0700`。

## 放到反代後面

- 在 NPM 開 WebSocket support（DSH Web 與 noVNC 都靠 WebSocket）。
- 設 `PUBLIC_HOST=<對外 hostname>`，gateway 的 WebSocket 同源校驗只認真實 `Host` 與這個白名單，不認 `X-Forwarded-Host`。
- 設 `TRUST_PROXY=1` 讓登入限流採用 `X-Forwarded-For`。直接暴露 port 時務必保持 `0`，否則 XFF 可被偽造繞過限流。

## DeepSeek 帳號登入

DeepSeek 平台只接受 loopback 的 OAuth 回調（`http://localhost:<port>/oauth/callback`），遠端登入有兩種做法：

上游補丁會把回調 origin 改成 `http://localhost:<瀏覽器網址上的 port>`，所以：

1. SSH 隧道：`ssh -L 43065:127.0.0.1:43065 df@<host>`，再用 `http://localhost:43065/` 發起登入，回調會自動落回本機。本機與遠端 port 要一致。
2. 內建登入助手插件：在 DSH 左下角帳號選單按「Sign in」，打開登入連結，登入後瀏覽器會跳到打不開的 `localhost` 回調網址，把整串網址貼回彈窗的「回調連結」即可。也可以直接開 `/account/callback` 頁面貼。

不登入帳號也可以直接在 DSH 設定裡填 API Key（例如走 ChatStack 的 new-api）。

## 尚未做的事

只建立了部署定義，沒有實際部署，也還沒加進 homepage / glance 與 NPM。
