# Registry Mirror 驗證紀錄

> 歷史紀錄：服務已於 2026-09-20 依使用者要求移除。下列啟動與拉取結果為
> 2026-09-19 的實測，提及的部署檔案與腳本已刪除，不代表目前仍有服務運行。

日期：2026-09-19，Linux amd64。
主機 Docker 29.8.0 / Compose 5.5.1；隔離測試 daemon Docker 29.8.1。

## 啟動

- `docker compose config --quiet`、`sh -n init-certs.sh verify.sh` 通過。
- `/mnt/appdata` 是 NFS；初次由 Docker 建立 bind 目錄時發生 `chown: operation not permitted`。
  目錄存在後啟動成功；當時的 README 加入了預先 `mkdir -p` 的步驟。
- `docker compose up -d --pull never --wait --wait-timeout 180` 成功。
- 六個 registry backend 與 gateway 均為 healthy；certificates 正常 Exited (0)。
- 移除 Registry 2.8.3 不支援的 `REGISTRY_PROXY_TTL` 環境變數後，重新建立六個
  backend 並再次通過 `up --wait`。快取沿用此版本預設的七天 TTL。
- 重複啟動後 CA SHA-256 指紋保持一致：
  `F9:4F:9D:67:BD:75:64:D4:51:2E:8D:F1:CB:00:4D:01:91:74:07:31:B9:B0:CE:9C:9F:0A:9A:5E:BD:43:91:AF`。
- `nginx -t` 通過；以本服務 CA 驗證 `https://ghcr.io/v2/`，透過
  `curl --resolve ghcr.io:443:127.0.0.2` 得到 HTTP 200、`{}`。
- 啟動映像已事先下載。當時主機還有其他大量 pull，為避免共用 daemon 的下載
  排隊，使用 crane 從公開 mirror 取得映像，再 `docker load`；這不是服務運行依賴。

## 完整拉取

執行 `./verify.sh`。測試使用空白 Docker-in-Docker image store，僅在測試容器配置
原 registry 網域的 hosts 導向與 CA，不使用 `insecure-registries`。

- `alpine:3.21`：完整下載及解壓成功。
  Digest：`sha256:ce64758a109eb420d874a118f87920e625e12d3634e03b4a5573fd9f6e5d3507`。
- `ghcr.io/tecnativa/docker-socket-proxy:v0.4.2`：全部九個 layer 下載及解壓成功。
  Digest：`sha256:1f3a6f303320723d199d2316a3e82b2e2685d86c275d5e3deeaf182573b47476`。

GHCR 冷快取首次下載約九分鐘，主要耗在兩個較大 layer。重啟 backend 後，使用
另一個全新的 Docker daemon 重跑最終版 `verify.sh`，兩張 image 皆再次成功，
digest 相同，腳本 exit 0；包含 daemon 啟動、兩次 pull 及清理共 **9.93 秒**。
第二次的 layer 由持久化本地快取提供；tag 查詢仍可能連線上游。

路徑為 Docker → 原 registry 名稱 → Nginx → 對應 Distribution cache →
`docker.m.daocloud.io` / `ghcr.m.daocloud.io`。Backend log 確認公開 mirror 上游，
並保留原始 Host 的 manifest、blob 請求；本地 cache 也有寫入資料。

## 驗證範圍

- 六個原始 registry 網域皆通過以 CA 驗證的 HTTPS `/v2/` 檢查。
- Quay、GCR、K8s、NVCR 沒有逐一完整 pull；`/v2/` 健康不代表任意 image 都可用。
- 公開 mirror 首次 layer 下載可能很慢；這次測試沒有壓測限流，也不保證大量更新
  都不會被 mirror 限流。每個 registry 只配置一個公開上游。
- 測試時主機 `/etc/hosts`、`/etc/docker/certs.d`、`daemon.json` 與原應用
  Compose 均未修改，正式 Docker 的透明導向沒有啟用；當時 `sudo -n` 需要密碼。
- 測試完成時服務監聽 `127.0.0.2:443`，資料位於
  `/mnt/appdata/registry-mirror`；這些資源已於後續清除。

## 2026-09-20 移除確認

依使用者「不需要本服務了，清除乾淨，只留下文件紀錄」的要求完成：

- `docker compose down --volumes --remove-orphans` 成功，移除八個容器與
  `registry-mirror_default` 網路；查詢專案容器、網路、volume 均無殘留。
- 刪除三個僅供此服務使用的映像：DaoCloud 路徑的 Registry 2.8.3、
  Nginx stable-alpine、alpine/openssl latest；移除前確認無其他容器使用。
  Docker 29 DinD 的原始與 mirror 標籤在清除前已不存在。
- 刪除 `/mnt/appdata/registry-mirror`，包含所有快取、CA 與 TLS 私鑰。
- 刪除 `/tmp/registry-mirror-tools`、兩個暫存 manifest JSON 與驗證 log；
  `/tmp/registry-mirror*` 無殘留。
- 刪除 `docker-compose.yml`、`nginx.conf`、`.env.example`、
  `init-certs.sh`、`verify.sh`，目錄僅剩 `README.md` 與本文件。
- `127.0.0.2:443` 連線回傳 connection refused，服務已停止監聽。
- 主機 hosts 沒有本服務導向，Docker certs.d 沒有 CA 殘留。
  daemon.json 仍保留既有的 `mirror.gcr.io`、`docker.m.daocloud.io`、
  `docker.1ms.run`；本次未修改主機 Docker 設定。
