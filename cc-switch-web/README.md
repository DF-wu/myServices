# cc-switch-web

`cc-switch-web` 是把 `Claude Code`、`Codex`、`Gemini CLI`、`OpenCode`、`OMO` 的設定集中到同一個 Web UI 管理的工具。這份目錄不是上游原始碼，而是 `myServices` 內的部署定義。

## 我重新驗證後的理解

這個專案不是單純前端網站，也不是 Node 常駐服務。它的實際 runtime 是 `Rust + Axum` 的 web server，前端 `React + Vite` 只是 build 後打包進去的資源。Docker image 啟動時跑的是 `cc-switch-server`，所有狀態都圍繞容器使用者 `ccswitch` 的 home 與 `.cc-switch` 目錄展開。

上游最重要的持久化檔案是這些：`/home/ccswitch/.cc-switch/cc-switch.db`、`/home/ccswitch/.cc-switch/web_password`、`/home/ccswitch/.cc-switch/web_env`、`/home/ccswitch/.cc-switch/backups/`。也就是說，**只要把 `/home/ccswitch/.cc-switch` 固定掛出去，服務本身的狀態就能活下來**。

但這個工具的價值不是只保住自己的 SQLite，而是接管主機上的 CLI 設定。因此我把 `~/.claude`、`~/.codex`、`~/.gemini`、`~/.config/opencode` 直接掛到容器內對應的預設位置，讓 Web UI 改的就是 DF 這台主機上的真文件，不是容器副本。

## 這份 compose 的部署模型

預設 host port 是 `43064`，對應容器內 `3000`。容器內一定要用 `HOST=0.0.0.0`，因為 Docker port publish 需要它；同時上游在公開 bind 時會要求你顯式設定 `ALLOW_HTTP_BASIC_OVER_HTTP=1`，所以這個值我也保留為預設開啟。

`ENABLE_HSTS=false` 是刻意保守的預設。這個服務本身會提供 Basic Auth，如果你要真的對外公開，正確做法是把它放在 TLS 反代後面，而不是直接把 HTTP 裸露出去。

目前預設入口：

```text
http://127.0.0.1:43064
```

## 已啟用的掛載

`docker-compose.yml` 會直接掛這些路徑：

- `/mnt/appdata/cc-switch-web/data` → `/home/ccswitch/.cc-switch`
- `/home/df/.claude` → `/home/ccswitch/.claude`
- `/home/df/.codex` → `/home/ccswitch/.codex`
- `/home/df/.gemini` → `/home/ccswitch/.gemini`
- `/home/df/.config/opencode` → `/home/ccswitch/.config/opencode`

這個設計的意思很簡單：Web UI 看到的是主機真實設定，容器只是載體。

## `.env.example`

同目錄提供 `.env.example`，可先：

```bash
cp .env.example .env
```

需要改的通常只有三類：入口 port、cc-switch-web 自己的 data dir、以及如果 DF 主機路徑不是預設值時，改 `CLAUDE_DIR` / `CODEX_DIR` / `GEMINI_DIR` / `OPENCODE_DIR`。

## 上游結構摘要

- 前端：`React 18 + Vite + Tailwind 4 + Radix UI + React Query + CodeMirror`
- 後端：`Rust + Axum + Tauri shared library`
- 儲存：`rusqlite`，沒有外部 PostgreSQL / Redis 依賴
- 啟動安全：非 loopback bind 時，若未設 `ALLOW_HTTP_BASIC_OVER_HTTP=1`，server 會拒絕啟動

## 我這次刻意沒做的事

我沒有把服務跑起來，也沒有把你其他 stack 動到。這次只修正部署理解與 repo 內的服務定義。
