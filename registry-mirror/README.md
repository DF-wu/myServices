# Registry Mirror 評估紀錄（已移除）

2026-09-20 依使用者要求停用並清除服務。此目錄只保留文件，不再提供可部署的
Compose、設定或腳本。歷史實測結果見 [VERIFICATION.md](VERIFICATION.md)。

## 原方案

採用 [brighill/registry-mirror](https://github.com/brighill/registry-mirror) 的
Distribution Registry + Nginx 架構，使用
[DaoCloud 公開 mirrors](https://github.com/DaoCloud/public-image-mirror) 作為上游。
六個 backend 分別處理 Docker Hub、GHCR、Quay、GCR、K8s 與 NVCR。

設計路徑：Docker → 原始 registry 網域 → 本地 TLS gateway → 獨立 registry cache
→ 對應公開 mirror。保留原應用 Compose 與 image 名稱，但主機必須另裝 CA、設定
hosts 才會透明導向；當時僅在隔離測試容器完成此設定，正式主機沒有啟用。

## 實測與限制

- Docker Hub、GHCR 均完成完整 pull；六個 registry 的 TLS 與 `/v2/` 路由通過。
- GHCR 冷快取約九分鐘；改用另一個空白 Docker daemon 重拉兩張 image，含測試
  daemon 啟動及清理共 9.93 秒。
- 每個 registry 只使用一個公開上游，沒有多站輪替或原站 fallback。
- 公開 mirror 可能限流、缺 image 或延遲更新 tag；沒有大量更新的壓測保證。
- 僅支援公開 image pull；不支援私人 image 自動繞過，也不支援 push。
- `/mnt/appdata` 為 NFS，Docker 自動 mkdir/chown 曾失敗，需先建立 bind 目錄。

## 清除範圍

- 專案容器、Compose 網路及專用 volume。
- `/mnt/appdata/registry-mirror` 的快取、CA 與 TLS 私鑰。
- Compose、Nginx 設定、環境變數範例、憑證初始化及驗證腳本。
- 本次部署專用且無其他容器使用的映像，以及下載工具、映像封存及暫存檔。

主機沒有本服務的 hosts 或 Docker CA 設定；原有 Docker Hub 公開 mirror 設定
不屬於本服務，保留原狀。實際清除確認見驗證紀錄的移除章節。
