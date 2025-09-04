# GoAccess on Docker: 全自動化部署指南 (DB-IP 版)

[![GoAccess](https://goaccess.io/images/goaccess-logo-large.png)](https://goaccess.io/)

這是一個全自動、易於維護的 GoAccess Docker Compose 部署方案。設計目標是將所有可變參數抽離到 `.env` 檔案中，並自動化處理所有外部依賴（如 GeoIP 資料庫），讓使用者能以最少的心力完成部署與維護。

此版本採用 **DB-IP** 的免費地理位置資料庫，**無需註冊或 API 金鑰**，實現真正的開箱即用。

## ✨ 設計特色

- **極簡設定**: 只需維護 `docker-compose.yml` 和 `.env` 兩個檔案。
- **全參數化**: 所有可變動的設定（連接埠、路徑、URL、進階參數）都已抽離至 `.env` 檔案，方便管理。
- **全自動 GeoIP**: **無需任何金鑰**，容器啟動時會自動下載並更新 DB-IP 的 GeoLite2-City 和 GeoLite2-ASN 資料庫。
- **日誌即時分析**: 採用 WebSocket 實現儀表板資料的即時更新。
- **持久化儲存**: 所有產生的報告和資料庫都儲存在指定的外部掛載卷，確保容器重啟或更新後資料不遺失。
- **高效能**: 可透過 `.env` 中的 `GOACCESS_OPTS` 參數進行細緻的效能調校。
- **無需手動建立檔案**: 部署過程無需在主機上手動建立任何設定檔、目錄或腳本。

## 🚀 快速開始

### 1. 準備環境

- 已安裝 Docker 和 Docker Compose。
- 一個正在運行的 Web 伺服器（如 Nginx Proxy Manager）並產生 access log。

### 2. 取得部署檔案

```bash
# 根據您的專案結構調整
git clone <your-repo-url>
cd myServices/goaccess
```

### 3. 設定環境變數

複製範本檔案並根據您的環境進行修改。

```bash
cp .env.example .env
nano .env
```

請務必修改以下**關鍵變數**：

- `GOACCESS_WS_URL`: 您用來存取 GoAccess 的**公開網域名稱**或**伺服器 IP**。這是儀表板即時更新的關鍵。
- `DATA_PATH`: GoAccess 持久化資料的主機路徑，例如 `/mnt/appdata/goaccess`。**請確保此目錄存在且 Docker 有權限讀寫。**
- `NGINX_LOG_PATH`: 您要分析的 Nginx 日誌檔所在的**目錄**，例如 `/mnt/appdata/NginxProxyManager/logs`。
- `LOG_FILE`: 要分析的日誌檔名，支援萬用字元，例如 `*_access.log`。

### 4. 啟動服務

```bash
docker-compose up -d
```

### 5. 存取儀表板

服務啟動後，您可以透過 `http://<您的伺服器IP>:<GOACCESS_PORT>` 存取 GoAccess 的 Web UI。

建議搭配 Nginx Proxy Manager 等反向代理工具，設定一個域名來存取，並啟用 HTTPS。

## ⚙️ `docker-compose.yml` 運作原理解析

此 `docker-compose.yml` 的核心是其 `entrypoint` 腳本，它取代了 `command`，在容器啟動時執行一系列自動化任務，實現了最大的靈活性和自動化。

```yaml
# GoAccess Docker Compose - v3.2 (DB-IP 全自動安全版)
version: "3.8"

services:
  goaccess:
    image: allinurl/goaccess:latest
    container_name: goaccess
    restart: unless-stopped
    ports:
      - "${GOACCESS_PORT:-7890}:7890"
    volumes:
      # 掛載整個資料目錄，統一管理報告、資料庫和 GeoIP 檔案
      - "${DATA_PATH:-/mnt/appdata/goaccess}:/goaccess/data"
      # 以唯讀模式掛載日誌來源目錄
      - "${NGINX_LOG_PATH}:/srv/logs:ro"
    env_file:
      - ./.env
    entrypoint:
      - /bin/sh
      - -c
      - |
        set -e
        echo "🚀 正在初始化 GoAccess (v3.2 - DB-IP)..."

        # --- 1. 自動下載 GeoIP 資料庫 (DB-IP) ---
        DB_DIR="/goaccess/data/geoip"
        # 檢查任一檔案不存在時，就觸發下載
        if [ ! -f "$DB_DIR/dbip-city-lite.mmdb" ] || [ ! -f "$DB_DIR/dbip-asn-lite.mmdb" ]; then
          echo "🌐 正在下載最新的 DB-IP GeoIP 資料庫 (免費版)..."
          mkdir -p "$DB_DIR"
          CURRENT_YM=$(date +%Y-%m)
          # 使用 curl 下載並解壓
          curl -L "https://download.db-ip.com/free/dbip-city-lite-${CURRENT_YM}.mmdb.gz" | gunzip > "$DB_DIR/dbip-city-lite.mmdb"
          curl -L "https://download.db-ip.com/free/dbip-asn-lite-${CURRENT_YM}.mmdb.gz" | gunzip > "$DB_DIR/dbip-asn-lite.mmdb"
          echo "✅ GeoIP 資料庫已就緒。"
        else
          echo "✅ GeoIP 資料庫已存在，略過下載。"
        fi

        # --- 2. 組合並執行最終命令 (安全模式) ---
        # 組合固定的核心參數
        FIXED_ARGS="--output=/goaccess/data/report.html --real-time-html --addr=0.0.0.0 --port=7890 --daemonize --pid-file=/goaccess/data/goaccess.pid --db-path=/goaccess/data/"
        [ -f "$DB_DIR/dbip-city-lite.mmdb" ] && FIXED_ARGS="$FIXED_ARGS --geoip-database=$DB_DIR/dbip-city-lite.mmdb"
        [ -f "$DB_DIR/dbip-asn-lite.mmdb" ] && FIXED_ARGS="$FIXED_ARGS --geoip-database=$DB_DIR/dbip-asn-lite.mmdb"

        echo "--------------------------------------------------"
        echo "🚀 正在啟動 GoAccess..."
        echo "日誌來源: /srv/logs/${LOG_FILE}"
        echo "自訂參數: ${GOACCESS_OPTS}"
        echo "--------------------------------------------------"

        # 使用 set -- 和 exec 來安全地處理參數，避免 eval 帶來的風險
        # $GOACCESS_OPTS 會被 shell 安全地分割成獨立的參數
        set -- ${GOACCESS_OPTS}
        exec goaccess "/srv/logs/${LOG_FILE}" "$@" ${FIXED_ARGS}

    command: [] # command 留空，因為所有命令已由 entrypoint 全權處理
```
### 啟動流程詳解

1.  **初始化**: 容器啟動時，執行 `entrypoint` 中的 shell 腳本。
2.  **GeoIP 資料庫檢查與下載 (DB-IP)**:
   - 腳本會檢查持久化目錄 `/goaccess/data/geoip` 中是否存在 DB-IP 的資料庫檔案 (`dbip-city-lite.mmdb`, `dbip-asn-lite.mmdb`)。
   - 如果檔案**不存在**，它會使用 `curl` 自動從 DB-IP 的官方下載點獲取當月最新的免費版資料庫，並解壓縮。
   - 如果檔案已存在，則會跳過下載，避免不必要的網路請求。若您想強制更新，可以手動刪除主機上對應的 `.mmdb` 檔案後重啟容器。
3.  **動態命令組合**:
   - **日誌來源**: `goaccess /srv/logs/${LOG_FILE}` - 指向您掛載的日誌檔（注意路徑已更新為 `/srv/logs`）。
   - **使用者自訂參數**: `${GOACCESS_OPTS}` - 將您在 `.env` 中設定的所有 GoAccess 參數原封不動地加到命令列中。
   - **核心固定參數**: `FIXED_ARGS` - 包含必要的參數，並自動加上剛剛下載好的 DB-IP 資料庫路徑。
4.  **安全執行命令**: 腳本最後會使用 `set --` 和 `exec` 來組合並執行 `goaccess` 命令。這種方法比 `eval` 更安全，可以有效防止潛在的 shell 注入風險，同時能正確處理帶有空格或特殊字元的參數。

這種設計的好處是，`docker-compose.yml` 檔案本身變得非常穩定，幾乎不需要修改。未來若要新增或調整 GoAccess 的任何功能，您**只需要專注於修改 `.env` 檔案中的 `GOACCESS_OPTS` 變數即可**，實現了設定與架構的完全分離。

## 📚 如何找到 Nginx Proxy Manager (NPM) 的日誌路徑

要讓 GoAccess 分析您的網站流量，首先需要找到 Nginx Proxy Manager (NPM) 儲存 `access.log` 的位置。這通常在您部署 NPM 的 `docker-compose.yml` 中定義。

1. **找到 NPM 的 `docker-compose.yml`**：這個檔案通常在您當初設定 NPM 的目錄下，例如 `/some/path/to/your/npm/docker-compose.yml`。

2. **尋找 `logs` 掛載卷**：在該檔案中，找到 `services` -> `app` -> `volumes` 區塊。您會看到類似這樣的設定：
```yaml
services:
     app:
       # ... 其他設定 ...
       volumes:
         - ./data:/data
         - ./letsencrypt:/etc/letsencrypt
         - ./logs:/data/logs  # <--- 這就是我們要找的！
```
3. **確定主機路徑**：
   - 在這個例子中，`./logs:/data/logs` 的意思是，主機上相對於 `docker-compose.yml` 的 `logs` 目錄，被掛載到了 NPM 容器內的 `/data/logs`。
   - 因此，NPM 產生的所有 access log，實際上都儲存在您主機的 `./logs` 目錄中。
   - 您需要取得這個目錄的**絕對路徑**。例如，如果您的 NPM compose 檔案在 `/root/stacks/npm/docker-compose.yml`，那麼日誌的絕對路徑就是 `/root/stacks/npm/logs`。

4. **填入 `.env` 檔案**：
   - 將您找到的絕對路徑填入 GoAccess 的 `.env` 檔案中：
```env
NGINX_LOG_PATH=/root/stacks/npm/logs
```
cker-compose.yml`，那麼日誌的絕對路徑就是 `/root/stacks/npm/logs`。

4. **填入 `.env` 檔案**：
   - 將您找到的絕對路徑填入 GoAccess 的 `.env` 檔案中：

     ```env
NGINX_LOG_PATH=/root/stacks/npm/logs
```

   - `LOG_FILE` 變數預設為 `*_access.log`，這會自動匹配該目錄下所有網站的 access log。您也可以指定單一檔案，如 `proxy-host-1_access.log`。

完成以上步驟後，GoAccess 容器啟動時就能正確地讀取到 NPM 的日誌並進行分析了。
