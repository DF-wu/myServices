# SearXNG in ChatStack

SearXNG 與專用 VPN、Valkey 一起定義在 `ChatStack/docker-compose.yml`，沿用既有 ChatStack project；不要另外建立獨立 Stack。

這份文件是可公開的通用說明。實際主機位址、部署驗收、探測紀錄、備份位置與私有操作手冊只留在 appdata 的 `searxng/private-records/`，不要提交到 Git。

## 功能與網路

- 使用固定版本與 digest 的官方映像；繁中介面、HTML／JSON API。
- SearXNG、loopback Valkey 共用專用 WireGuard namespace；VPN 失效不回落直連。
- DNS 指向 namespace 內的 loopback resolver，經 VPN 使用 DoH；停用 IPv6。
- 搜尋服務只提供 LAN 入口與 ChatStack 內部 `http://searxng:8080/search`。
- 應用非 root、唯讀 rootfs／設定、capabilities 全移除，並限制資源與 log 大小。
- 引擎載入前等待 VPN／Valkey；綜合健康檢查涵蓋 VPN、Valkey 與 Web。
- Open WebUI 採摘要與來源連結，略過額外直連網頁 loader／embedding。

JSON API 支援 `q`、`format=json`、`language`、`engines`、`categories`、`pageno`。引擎可用性依出口及上游狀態變動，應以實際結果驗收。

## 私有設定

在既有 ChatStack 的 Portainer Environment 設定 `SEARXNG_BIND_IP` 為真正的 LAN 位址。此值不寫入 repo；未設定時 Compose 拒絕啟動，避免誤綁公網或靜默改成別的入口。主機端埠可用 `SEARXNG_HOST_PORT` 覆寫。

實際設定與 secrets 留在 Compose 指定的 appdata，權限限制為擁有者可讀：

- `config/settings.yml`：instance signing key、引擎及功能設定。
- `config/limiter.toml`：實際可信用戶端網段。
- `vpn.env`：VPN credential。
- `control-auth.toml`、`control-api.key`：loopback 維護 API 認證。
- `cache/`、`vpn/`、`backups/`、`private-records/`：執行資料及私有紀錄。

這些內容不屬於 repo。`.example` 是通用範本，必須自行產生密鑰及設定真實網段，不可直接當成正式設定。更新時保留有效 secret；不得把目前密鑰複製進範例或報告。

Limiter 的 passlist 會略過 bot filters，只填受信任且必要的網段。TOML loader 會擴充列表，`trusted_proxies=[]` 不會清除預設 loopback 信任；不得因此誤判來源信任邊界。不要把私人 JSON API 無限制公開。

## 維護

在 repo root 執行：

```sh
rtk proxy python3 ChatStack/searxng/probe-engines.py --url 'http://<LAN_HOST>:43072'
rtk proxy python3 ChatStack/searxng/check-vpn.py
rtk proxy python3 ChatStack/searxng/configure-open-webui.py
```

`check-vpn.py --exercise-kill-switch` 會短暫停用專用 VPN，檢查新公共 TCP／HTTPS／DNS、IPv6 與外部搜尋封鎖，並在 finally 恢復。離線 DNS 回 SERVFAIL 不代表 DNS 洩漏。這項演練會中斷搜尋，不要在別的部署進行時同時執行。

`configure-open-webui.py` 只處理搜尋相關持久欄位，使用現有容器的 Config API，不輸出或替換登入 key。變更前必須以 `--apply --backup <PRIVATE_BACKUP_FILE>` 保存原值。

部署仍以主 Compose 為準。`render-deployment.py` 可擷取同一 ChatStack 的三個搜尋服務，避免重建其他應用；它沒有建立另一個 Stack。不要對部分模型執行 `down` 或 `--remove-orphans`。VPN 重建時要同步重建共用 namespace 的兩個服務。

Portainer 從 Git 更新前，先確認使用的 revision 已包含整合設定及必要的私有 Environment。不要用舊 Compose 全量覆蓋目前部署。升級前備份私有設定，核對實際版本／digest，候選測試通過再切換。

## 提交前的隱私檢查

- 只提交程式與匿名化範例，不提交 appdata、真實 env、備份、私有報告。
- `.gitignore` 不會自動停止追蹤已存在於 Git 的檔案，必須另外檢查 index。
- 不使用 `git add .`；逐一檢查待提交 diff，確認沒有 credentials 或私人紀錄。
- 刪除目前檔案不會清除已公開的 Git 歷史；若確認實際密鑰曾公開，先撤銷／輪替，再另外處理歷史。
