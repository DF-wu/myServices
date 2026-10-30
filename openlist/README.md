# OpenList 與 Sinclair OneDrive bridge

本 stack 由 Portainer 的 Git 更新流程部署；不要在主機另外執行 Compose 或重新建立容器。

## 免 build 的 bridge 子服務

`sinclair-od-bridge` 使用 Docker 官方 `node:24-bookworm-slim` 公開映像，不含 `build:`，也不需要自行建置映像。啟動腳本會在新容器內安裝 Debian Chromium、Xvfb、noVNC 與鎖定版本的 npm 依賴；同一容器重新啟動會沿用已安裝的系統套件。容器被重新建立時，安裝系統套件仍需要網路，首次啟動可能需數分鐘。

bridge 原始碼來自私有的 `DF-wu/od-openlist-bridge`。執行版本為 `d56ba1fc2397551c5bf1cecf1fc4fb7e147e3696`，已預先放在主機 `/mnt/appdata/openlist-sinclair/runtime/d56ba1fc2397551c5bf1cecf1fc4fb7e147e3696`，以唯讀 bind mount 載入，不把私有原始碼或 GitHub token 放入此公開 repo。`SINCLAIR_BRIDGE_SOURCE` 可在 Portainer 指向另一個已備妥的版本目錄；同時更新 `OD_BRIDGE_REVISION`，啟動時會核對版本。bind 設定禁止自動建立空的原始碼目錄，路徑有誤時會明確失敗。

更新 bridge 的流程是：在私有 repo 修復、驗證並提交，以 `bash deploy/stage-runtime.sh <新的主機版本目錄>` 備妥原始碼，再更新本 recipe 的來源路徑交由 Portainer 更新。全程不需要 `docker build`。不會在容器內保存 GitHub 認證或於每次重啟拉取未固定的程式碼。

2026-10-30 查核此主機 Portainer 的 openlist stack 記錄時，`GitConfig` 與 `AutoUpdate` 均為空。Portainer 內建 Git 輪詢不會因此次 Git push 自動啟動；若另有外部同步流程，依該流程為準。需透過使用者既有的 Portainer 流程套用本 recipe；本次沒有變更 Portainer 設定或呼叫部署。

## 持久化與權限

- `/mnt/appdata/openlist`：既有 OpenList 資料，保持原掛載。
- `/mnt/appdata/openlist-sinclair/state/chromium`：專用 Chromium profile，保留登入 session；它同樣是敏感資料。
- `state/deps` 與 `state/npm-cache`：鎖定 npm 依賴及下載快取。
- `state/private/account.json`：可選的本機登入設定，包含 `username`、`password`、`totp`；不在 Git。
- `state/private/bridge-password`：bridge 專用認證，不是學校密碼。
- `state/private/openlist-token`：既有 OpenList 管理 API token，用於一次性的掛載設定；不在 Git。

此主機 appdata 使用 UID/GID 3000，bridge 的瀏覽器和 Node 程式也以 3000 執行。系統套件安裝階段需要容器 root，之後會降權。Chromium 在容器內使用 `--no-sandbox`；沒有 privileged、Docker socket、主機 Chromium profile 或 host network。

## 登入與掛載

瀏覽器桌面僅發布在主機 loopback：`http://127.0.0.1:58110/vnc.html?autoconnect=true&resize=scale`。遠端維護可使用 SSH tunnel 轉發主機的 58110 埠。VNC 本身沒有密碼，因此不可把此埠改綁公網；同主機的其他使用者可能也能連入。

CDP 9222 只監聽容器內 loopback；WebDAV 8110 僅在 Docker 內網提供，並要求 bridge 的專用 Basic 認證。OpenList 透過 `http://sinclair-od-bridge:8110` 存取。

若已有本機登入設定，登入助手會嘗試一次正常登入及 TOTP；遇到拒絕、其他 MFA 或 SSO 挑戰會停下，保留桌面供人工完成，不會持續重試密碼。工作階段仍可能被學校撤銷，不能保證永久有效。

2026-10-30 的部署後修正處理 Microsoft 明確提供「Not now」連結的可選驗證方式設定提醒；必要的驗證設定仍由人工完成。新版 OneDrive 可能導向同一主機的 `/my`，bridge 現在可使用該分頁並以實際 API 驗證健康，仍保留外部登入與 MFA 分頁。已在既有容器中恢復 `/Sinclair_OD` 並驗證根目錄列出成功，沒有自行重新部署或重啟。

待真正的 SharePoint API 驗證成功後，子服務才會透過 OpenList 正式管理 API 啟用 `/Sinclair_OD`，根目錄對應 OneDrive 的 `Documents` 文件庫根。OpenList 不允許直接更換 storage driver，所以現有同名的原生 OneDrive 設定會先備份，停用並保留在 `/Sinclair_OD__previous_<id>`，再以原名稱建立 WebDav；其他儲存不會被更動。新掛載可在部署前預先建立為停用，待 session 健康後自動啟用。瀏覽器登入未完成時，子服務健康狀態為不健康，但不會阻止既有 OpenList 啟動。

掛載啟用 `web_proxy`、`webdav_policy=use_proxy_url`、下載簽章，並停用自動索引。實際可見範圍仍受 OpenList 使用者設定與學校帳號權限控制。

## 驗證與復原

`/__live` 只回報 bridge 程序存活；`/__health` 會查驗實際上游 API，登入失效時回 503。這些端點不回傳 Cookie、URL、帳號或檔名。

部署前會以隔離環境驗證 WebDAV、串流、權限、錯誤路徑與啟動腳本；真正的學校登入、文件庫列目錄及 OpenList 全鏈路仍要在 Portainer 部署後確認。原有 `/Sinclair_OD` 的完整設定備份只存放在本機 `state/private/openlist-storage-before.json`。

若需要回復舊版，將 recipe 指回先前已備妥的 runtime 目錄，交由 Portainer 依既有更新流程處理。不要刪除或取代 `/mnt/appdata/openlist`。
