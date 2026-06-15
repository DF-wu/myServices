# cc-switch-web

`cc-switch-web` 是把 `Claude Code`、`Codex`、`Gemini CLI`、`OpenCode`、`OMO` 的 provider / MCP / prompt / skills / proxy 設定，集中放到一個 Web UI 裡管理的工具。上游 repo 是 `Laliet/cc-switch-web`，這裡放的是 `myServices` 版本的部署骨架，而不是上游原始碼鏡像。

## 我先幫你拆完的重點

這個專案的常駐 runtime 不是 Node，而是 `Rust + Axum` 的 web-server。`React + Vite` 前端只是 build 產物，會在映像建置時被編譯並打包到 server 裡。Docker 啟動後真正執行的是 `cc-switch-server`，資料預設寫在容器使用者 `ccswitch` 的家目錄下。

上游已經把幾個關鍵檔案路徑固定好了：`/home/ccswitch/.cc-switch/cc-switch.db` 是主資料庫，`/home/ccswitch/.cc-switch/web_password` 是首次啟動後自動產生的 Basic Auth 密碼，`/home/ccswitch/.cc-switch/web_env` 會存 CSRF token，`/home/ccswitch/.cc-switch/backups/` 則用來放備份。也就是說，**只要把 `/home/ccswitch/.cc-switch` 做好持久化，就能保住它自己的核心狀態**。

但這個服務真正有價值的地方，不只是它自己的 SQLite，而是它能不能碰到**主機上實際在用**的 CLI 設定。如果沒有額外 bind mount，Web UI 雖然能打開，也能新增 provider，但那些設定只會寫進容器裡的 `.claude`、`.codex`、`.gemini`、`.config/opencode` 副本，不會影響你主機真正正在跑的 CLI。這也是我在 `docker-compose.yml` 裡把「可選掛載」分開寫清楚的原因。

## 目前這份服務怎麼設計

預設值偏向「先安全、先可管理、先不要誤踩 host 設定」：host port 只綁 `127.0.0.1`，容器內綁 `0.0.0.0`，並顯式打開 `ALLOW_HTTP_BASIC_OVER_HTTP=1`，讓它能在 Docker 內部用 HTTP 提供服務，再交給外層反代處理 TLS。`ENABLE_HSTS` 預設關閉，因為 HSTS 應該由正式 HTTPS 網域決定，不該在本機或測試環境先亂快取。

目前預設對外入口是：

```text
http://127.0.0.1:43064
```

首次啟動後的帳密規則依上游實作如下：帳號固定是 `admin`，密碼不會印到 log，只會寫入資料目錄裡的 `web_password` 檔。

## 如果要讓它真的管理 live CLI config

把 `docker-compose.yml` 內的「可選掛載」取消註解，並確認 host 上這些路徑真的存在：`~/.claude`、`~/.claude.json`、`~/.codex`、`~/.gemini`、`~/.config/opencode`。這樣 Web UI 寫入的內容才會直接反映到你主機的 CLI 設定。

需要注意一個上游行為：他們在 README 裡同時提到可以用 Web UI 直接編輯 prompt 檔，例如把 prompt 寫進 `~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md`、`~/.gemini/GEMINI.md`。所以只掛一半路徑沒有意義，**要嘛完整接管，要嘛就當成隔離中的測試實例**。

## `.env` 使用方式

同目錄提供 `.env.example`。真正部署時可以：

```bash
cp .env.example .env
```

然後依照實際情況改以下幾類值：第一類是入口層，例如 `CC_SWITCH_WEB_BIND_IP`、`CC_SWITCH_WEB_PORT`。第二類是資料路徑，例如 `CC_SWITCH_WEB_DATA_DIR`。第三類是安全與跨域選項，例如 `ENABLE_HSTS`、`CORS_ALLOW_ORIGINS`、`ALLOW_LAN_CORS`。第四類則是如果你要取消註解 live config bind mount 時，給 compose interpolation 用的 host 路徑變數。

## 上游深度理解摘要

這個專案本質上是把原本偏桌面向的 `cc-switch` 分成兩個 mode。桌面模式是 `Tauri GUI`；雲端/無頭模式則是 `web-server` feature。前端採 `React 18 + Vite + Tailwind 4 + Radix UI + React Query + CodeMirror`，後端核心採 `Rust + Tauri shared library + Axum`。Docker multi-stage build 先用 Node builder 編出 `dist-web/`，再用 Rust builder 編 `server` example，最後在 `debian:bookworm-slim` 內只留下單一 server binary。

它管理的不是單一產品，而是多個 CLI 生態的配置聚合。從原始碼來看，模組至少包含 provider、prompt、MCP、skills、usage、stream check、proxy、OpenCode、OMO、WebDAV、import/export 等。資料層使用 `rusqlite`，而不是外部 PostgreSQL 或 Redis，所以作為 `myServices` 裡的獨立服務非常合理，沒有額外 sidecar 依賴。

另一個重要細節是安全模型。上游在 `server.rs` 裡明確寫了：當服務綁到非 loopback 位址時，如果沒有 `ALLOW_HTTP_BASIC_OVER_HTTP=1`，程式會拒絕啟動。這表示他們是知道裸 HTTP + Basic Auth 的風險的。也因此，這份 compose 的預設部署模型不是「直接公開服務」，而是「先鎖在 loopback，外層再做 TLS 與存取控管」。

## 建議的反代模式

如果之後你要把它掛進 NPM / Caddy / Cloudflare Tunnel，最乾淨的做法是保留 `127.0.0.1:43064:3000`，讓反代打 host loopback。若需要跨域，請明確設定 `CORS_ALLOW_ORIGINS=https://你的網域`，不要直接開 `*`。上游對 `*` 也不是鼓勵路線。

## 這次我沒有做的事

我沒有把服務跑起來，也沒有替你自動掛 live CLI config，更沒有幫你動任何既有服務。這次只做**開發與 repo 落檔**，保持跟你要求一致。
