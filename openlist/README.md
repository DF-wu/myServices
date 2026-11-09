# OpenList 與 Sinclair OneDrive bridge

本 stack 由 Portainer 的 Git 更新流程部署；不要在主機另外執行 Compose 或重新建立容器。

## 錯誤透傳與大目錄相容版

2026-11-09 修正分成 bridge 與 OpenList 兩層。bridge 在 SharePoint classic 列舉回報清單門檻錯誤時，改用 OneDrive v2 children 完整分頁；實機原本失敗的大目錄已由候選程序列出 6,237 個子項。原始上游狀態、錯誤內容、Retry-After 及 request ID 會繼續傳給 OpenList；本機傳輸故障另提供不含敏感內容的固定分類。

原版 OpenList v4.2.9 會把 PUT 的多種上游失敗包成 405，且它的 WebDAV client 丟掉重試標頭。單改 bridge 無法補回此資訊，因此 recipe 增加 `openlist-compat-build`：使用固定 digest 的官方 Go 1.27.3 公開 image，自動下載固定來源／前端 SHA-256、套用 bridge runtime 中的 `deploy/openlist-errors.patch`、測試並編譯。成功後才由固定 digest 的官方 OpenList v4.2.9 image 執行該成品。沒有 Dockerfile、`build:` 或手動 build image；首次套用需要下載及編譯時間。

builder 不掛載既有 OpenList data 或學校認證。原始碼／模組快取保留在 `openlist-build-cache` volume，驗證後的版本成品保留在 `openlist-compat` volume；兩者都由 Portainer stack 管理。runtime 以唯讀方式取得成品，既有 `/opt/openlist/data` 掛載保持原位置。成品 key 包含來源、前端、patch、Go 版本、建置腳本與平台；再次啟動驗證 checksum 後重用，沒有變更便不重新編譯。下載、測試或編譯失敗時，新的 OpenList 不會靜默改回原 binary 啟動。

`OPENLIST_COMPAT_REVISION` 與 bridge 的 source pin 一起更新，讓後續 runtime 更新也能由 Portainer 辨識。這個值不改動 OpenList 使用者或 storage；實際 API 錯誤修正來自經 patch 編譯的成品。這是自訂可執行檔搭配官方 runtime image，並非宣稱官方 image 本身已有該修復。不要刪除 `openlist-compat` volume，否則須先重新完成 builder 才能啟動 runtime。

目前 TrueNAS rclone v1.70.2 的 WebDAV backend 會辨認 429／503 等可重試狀態，但不像原生 OneDrive backend 解析 Retry-After。因此 bridge 的上游 cooldown 仍保留；轉送標頭讓客戶端取得提示，不能宣稱未修改的 rclone 已會遵守它。沒有自動修改 TrueNAS binary、工作參數或排程。

隔離實際 OpenList → bridge → 合成 SharePoint 驗證：10 種 PUT 錯誤、3 種列表錯誤保留原狀態／Retry-After／request ID／有意義的診斷，成功建立與覆寫維持 201／204。rclone v1.70.2 收到真正 429 與上游錯誤 code，該次提交沒有重播。這些是部署前驗證，正式套用仍交由 Portainer；沒有自行 restart 或 redeploy。

## 免 build 的 bridge 子服務

`sinclair-od-bridge` 使用 Docker 官方 `node:24-bookworm-slim` 公開映像，不含 `build:`，也不需要自行建置映像。啟動腳本會在新容器內安裝 Debian Chromium、Xvfb、noVNC 與鎖定版本的 npm 依賴；同一容器重新啟動會沿用已安裝的系統套件。容器被重新建立時，安裝系統套件仍需要網路，首次啟動可能需數分鐘。

本 recipe 明確設定 `BRIDGE_TRANSPORT=http`，由 Node 透過 `impit@0.14.8` 直接串流上下載，使用固定 Chrome 151 的 TLS／HTTP2 profile 與相同版本的 Linux User-Agent、Client Hints；同時設定同源 fetch 的 Origin／Referer／Sec-Fetch 標頭。WebDAV 僅在 OpenList 與 bridge 之間使用，上游仍是 SharePoint 的 GET／POST REST 操作，檔案位元組不經 CDP 或 Base64。

Chromium 僅用於正常登入與定期提供 Cookie 快照，記憶體快取預設五分鐘；不參與每個檔案的資料中繼。`impit` 由 npm 安裝平台預編譯套件，不需要自行 build 映像或編譯程式。這是固定瀏覽器 profile 的模擬，並非完整重現登入瀏覽器的所有特徵，也不保證不可辨識；套件或 profile 更新時需重新驗證。`browser` 僅保留為明確選用的診斷模式，不會自動切回。

此學校端點可能忽略 Range 並回 200；配額 API 則可能因 Cookie 驗證回 403。HTTP 模式不依賴該配額 API 判斷健康，未知配額不會虛報為零；HEAD 透過檔案中繼資料提供大小。對此租戶明確回報的非空資料夾回收錯誤，bridge 會完整列舉所有分頁與深層內容，檢查路徑及 UniqueId，再由子至父逐項回收。權限錯誤不觸發此流程；子項失敗或出現並行變更即停止，已回收的項目保留在回收筒，整體不是原子交易。站台與 Documents 文件庫根禁止刪除。

2026-11-01 在 OneDrive 根目錄 `TESTDIR` 的獨立 UUID 子目錄完成三輪實機 CRUD，最終 27/27 組通過，涵蓋經 OpenList 的空檔、64 MiB 檔案、SHA-256 核對、覆寫、特殊檔名、檔案／多層資料夾複製、移動、重新命名與刪除；另有 25 項條件式寫入與兩種物件替換競態實測。回收與刪除計畫的列目錄使用物件 ID，避免刪除同路徑的替代內容。218 項本機回歸全數通過。測試程序與臨時 storage 均已清理，原 `/Sinclair_OD` 設定不變。結果報告保留在 `TESTDIR/CRUD-report-*.md`。這些結果來自另外載入的候選程序，正式 bridge 仍待 Portainer 套用新版本，沒有自行重新部署。

寫入條件不符回 412；無法保證原子性的條件式修改回 501，避免靜默覆蓋／刪除已變更的內容。原始碼內 `npm test` 可重跑本機回歸測試；`deploy/verify-crud.js` 須明確設定 `OD_BRIDGE_VERIFY_CRUD=TESTDIR` 才會建立合成測試資料，不會自動隨容器啟動。

2026-11-02 批次備份修正保留 4 個同時上傳名額，改以有界 FIFO 等候，避免 8 個用戶端傳輸直接撞到 503。中繼資料、寫入與完整下載共用 8 個上游名額；429／503 遵守 Retry-After 共用冷卻，只對安全讀取有限重試，寫入不盲目重播。recipe 明確列出佇列、等候與清理預算；不需要提高學校端併發。失敗上傳的暫存清理會等待同一冷卻，且 digest 更新也受清理期限約束；預算不足時仍可能留下暫存檔。

272 項本機測試通過；實際 rclone → 既有 OpenList → bridge → 合成上游，8 路傳輸的 32 個檔案由舊版缺 12 個改為 32/32 雜湊一致、零錯誤。另有學校 TESTDIR 的 32 KiB 小量實機驗證，測試目錄及臨時掛載已清理。OpenList 可能把底層上傳錯誤轉成 405，應併看其檔案日誌與 bridge audit；原正式 502 的確切來源尚未確認。這些測試不代表整批 TrueNAS 備份已完成；工作與排程沒有被修改，正式套用仍交由既有 Portainer 流程。

2026-11-03 大型備份 profile 將同時上傳調為 8，配合目前 8 路用戶端工作。二進位上傳請求與下載共用 8 個 data 名額，上游總名額 12，讓資料請求無法單獨占滿列目錄所需的空間。等待上傳最多 64 個，上游／data gate 各最多等候 128 個，兩段取得名額共用同一次排隊預算；這些是同時請求的上限，不是整批備份檔案總數。全部已改為 `${變數:-預設值}`，可由 Portainer Stack 的環境設定覆蓋。

`BRIDGE_REQUEST_TIMEOUT_MS` 預設 0，停用單檔固定總期限，避免仍在正常傳輸的大檔被一小時限制切斷。用戶端及上游閒置各 10 分鐘，上傳與上游排隊各 30 分鐘，列目錄等 metadata 總期限 30 分鐘，失敗清理總期限 10 分鐘。讀取用戶端內容的 idle 計時不包含上游處理及冷卻等待；下載保護持續到最後輸出完成。仍保留 60 秒標頭期限、取消及資源上限。程式本身仍接受正值總期限，以上是 recipe 的備份 profile，不是學校公布的容量或效能保證。

單檔大小（預設 250 GiB）、metadata 回應大小（8 MiB）與單次列舉項目數（100000）也可透過 `BRIDGE_MAX_UPLOAD_BYTES`、`BRIDGE_MAX_METADATA_BYTES`、`BRIDGE_MAX_LIST_ITEMS` 覆蓋；它們不限制整個備份的總容量。提高 metadata 上限會增加單目錄的記憶體需求，仍須以實際目錄分布驗證。

本機完整回歸 290 項通過，包含 512 檔／8 worker、220 MiB 串流上傳 SHA-256、持續有進度與真正停住的逾時分流、最後輸出清理、資料名額隔離及原有 CRUD／TLS 測試。實際 rclone／OpenList 合成上游與 TESTDIR 32 KiB smoke test 重跑通過；沒有冒稱已完成數小時的真實整批備份。

目前查核的 OpenList v4.2.9 WebDav client 沒有固定 30 秒上傳限制，但 TrueNAS 的 rclone v1.70.2 預設 `--timeout 5m` 仍會限制 I/O 閒置及送完 body 後等待回應。可在 Cloud Sync 額外 rclone 參數加入 `--timeout 1h --contimeout 1m`，保留原有其他參數，與上述 profile 配合；一小時是無進度／等候回應期限，不是整個備份期限。這個 TrueNAS 設定沒有被自動修改，bridge 更新也不會替它調整。來源：[rclone 預設](https://github.com/rclone/rclone/blob/v1.70.2/fs/config.go)、[HTTP 回應期限](https://github.com/rclone/rclone/blob/v1.70.2/fs/fshttp/http.go)、[OpenList client](https://github.com/OpenListTeam/OpenList/blob/v4.2.9/pkg/gowebdav/client.go)。

bridge 原始碼來自私有的 `DF-wu/od-openlist-bridge`。本 recipe 指定版本為 `c171234b270c34d864aa0ca17ecc2ecb6face630`，已預先放在主機 `/mnt/appdata/openlist-sinclair/runtime/c171234b270c34d864aa0ca17ecc2ecb6face630`，以唯讀 bind mount 載入，不把私有原始碼或 GitHub token 放入此公開 repo。修正與驗證見 [bridge PR #3](https://github.com/DF-wu/od-openlist-bridge/pull/3)。`SINCLAIR_BRIDGE_SOURCE` 可在 Portainer 指向另一個已備妥的版本目錄；同時更新 `OD_BRIDGE_REVISION` 與 `OPENLIST_COMPAT_REVISION`，啟動時會核對版本。bind 設定禁止自動建立空的原始碼目錄，路徑有誤時會明確失敗。

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
