# CapsWriter-Offline-Container

Portainer Git stack recipe，對應
[CapsWriter](https://github.com/DF-wu/CapsWriter-Offline-Container)。
本次依 `master` 的 `a674e40` 對齊參數，使用已發布的 server／Web 映像，
不在部署主機 build。

## 服務與網址

主檔 `docker-compose.yml` 已包含 NVIDIA server 與 Web Console，
HTTP API 已啟用，三個 port 都透過 `.env` 控制並發布至 LAN：

| 用途 | 預設網址 | 容器 port |
|---|---|---|
| 桌面用戶端 WebSocket | `ws://axolotl.newhome:6016` | 6016 |
| OpenAI 相容 HTTP API | `http://axolotl.newhome:6017/v1` | 6017 |
| Web Console | `http://axolotl.newhome:6018` | 8080 |

Web 使用 `ghcr.io/df-wu/capswriter-offline-web:latest`，server 使用
`ghcr.io/df-wu/capswriter-offline-server:latest`。兩個映像都可在 `.env`
改成已驗證的 `sha-<完整 commit>` 或 digest。

預設模型仍是 `qwen_asr`、硬體策略 `auto`、CPU threads `16`。
一般 NVIDIA 推論保持可用；**額外顯存鎖頻目前關閉**，因為沒有選定支援的
頻率，`true` 配上 `0` MHz 會被新版拒絕。

## Portainer 設定

- Git Compose path：`CapsWriter-Offline-Container/docker-compose.yml`。
- 將 `DF_API_KEY` 或 `CAPSWRITER_HTTP_API_KEY` 設為現有的 API key。
  Compose 明確映射參數，可由 Portainer stack environment 覆寫；不依賴
  `env_file` 把變數間接傳入容器。未提供 key 時，Compose 會直接報錯。
- 主檔已包含 Web 與 HTTP port，無須另外加入 Web Compose 檔。
- 只有要使用 Web 的服務端設定頁時，才在 Additional Compose files 最後
  加入 `CapsWriter-Offline-Container/docker-compose.settings.yml`。
- 這份 recipe 由 Portainer 拉取再部署；本機修改檔案不會改變既有容器。

開啟 `http://axolotl.newhome:6018`，API root 預設為
`http://axolotl.newhome:6017`；在頁面的 key 欄輸入 server token。
`CAPSWRITER_WEB_API_KEY` 保持空白，不會把 server key 發布到 `/config.js`。

Web 容器只提供頁面，**瀏覽器直接呼叫 API**。不要把 API root 設成
`http://capswriter-server:6017`，也不要讓遠端瀏覽器使用它自己的 localhost。
若改用其他主機名稱／IP，更新：

```dotenv
CAPSWRITER_WEB_HOST=axolotl.newhome
CAPSWRITER_WEB_PORT=6018
CAPSWRITER_HTTP_API_PORT=6017
CAPSWRITER_WEB_API_BASE=http://${CAPSWRITER_WEB_HOST}:${CAPSWRITER_HTTP_API_PORT}
CAPSWRITER_HTTP_API_CORS_ORIGINS=http://${CAPSWRITER_WEB_HOST}:${CAPSWRITER_WEB_PORT},http://localhost:${CAPSWRITER_WEB_PORT},http://127.0.0.1:${CAPSWRITER_WEB_PORT}
```

以 HTTPS 網域存取時，API root 也須使用瀏覽器可達的 HTTPS URL，並把完整的
Web origin 加入 CORS。遠端瀏覽器錄音需要 HTTPS；LAN HTTP 頁面可上傳檔案，
但不滿足麥克風的 secure-context 要求。Server／Web／HTTP 三個
`*_PUBLISH_HOST` 可分別調整監聽介面。

## 最新參數與設定頁

`.env` 已列出 API 上傳／音訊秒數／佇列限制、WebSocket 接入限制、下載與
worker timeout、Qwen／Fun-ASR 參數、Web runtime 設定與預加速控制。
Portainer 的環境值優先於 `.env`；變更 server 參數後需要重建服務。

選用 `docker-compose.settings.yml` 後，設定保存於
`capswriter-server-settings:/app/settings`，需使用同一個 API key 驗證。
`.env`／Portainer 中非空的日常參數會顯示為鎖定；要讓 GUI 管理某欄位，
將對應變數清空或移除，並將這個 override 放在其他 override 之後。

## 模型與熱詞持久化

模型使用 `capswriter-server-models:/app/models`，logs 使用
`capswriter-server-logs:/app/logs`，避免舊 NFS 模型 UID 與 `appuser` 不符。
Portainer stack 名稱若為 `capswriter`，模型 volume 實際名稱通常是
`capswriter_capswriter-server-models`。新的空 volume 會重新下載模型，
不會自動匯入舊 NFS 資料。

熱詞仍從 `/mnt/appdata/capswriter-offline/hot-server.txt` 唯讀掛載。
該檔案必須先存在；recipe 不會把缺少的熱詞檔自動建成目錄。
如需首次建立，可由操作人員執行：

```bash
mkdir -p /mnt/appdata/capswriter-offline
cp hot-server.example.txt /mnt/appdata/capswriter-offline/hot-server.txt
```

等 Portainer 部署後確認實際掛載、`/ready` 與辨識正常，才能考慮移除舊
`/mnt/appdata/capswriter-offline/models`；保留其父目錄與 `hot-server.txt`。
`docker compose down -v` 會移除模型、logs 與選用的 settings volume。

## NVIDIA 與預加速

這份自部署主檔保留 NVIDIA device reservation，`CAPSWRITER_GPU_DEVICE_COUNT`
只接受 `all` 或正整數。`CAPSWRITER_INFERENCE_HARDWARE=cpu` 可強制 CPU 推論，
Qwen 也可設定 `CAPSWRITER_QWEN_PRESET=cpu_only`；`cpu_only` 不是硬體策略值。
這些設定不會取消 Docker 的 NVIDIA 裝置需求；在沒有 NVIDIA runtime 的
主機上使用時，需先移除 `deploy.resources.reservations.devices`。
切換模型可設定 `CAPSWRITER_MODEL_TYPE=fun_asr_nano`。

額外鎖頻需先確認顯卡支援的 MHz，再同時設定
`CAPSWRITER_GPU_BOOST_ENABLED=true` 與正的
`CAPSWRITER_GPU_BOOST_MEMORY_CLOCK_MHZ`，並加入
`docker-compose.nvidia-boost.yml`。該檔提供 root、`SYS_ADMIN`、
`DAC_OVERRIDE`、`CHOWN`、`FOWNER` 與 150 秒停止寬限，不會自動選頻率。

HTTP、錄音與檔案辨識都有預加速整合，閒置與正常退出會嘗試還原；命令失敗
仍繼續辨識。強制 CPU／完整 CPU 回退不鎖頻，`low_vram_gpu` 保留 GPU 編碼器
資格。鎖頻會影響同一實體 GPU 上的其他程式，多個實例沒有所有權協調。
Hopper deferred clocks 不適用；強殺／斷電無法保證還原。
Root 模式產生的資料可能需要修復為映像 `appuser` 的 UID/GID，才能退回非 root。

官方說明：[NVIDIA SMI](https://docs.nvidia.com/deploy/nvidia-smi/index.html)。

## 部署後驗證

以下由部署操作人員執行；修改 recipe 本身不代表已完成部署：

```bash
curl http://axolotl.newhome:6017/health
curl http://axolotl.newhome:6017/ready
curl http://axolotl.newhome:6018/health
```

確認 Web 顯示正確的 API root，輸入 key 後跑診斷並上傳已知音訊。
`/health` 表示 HTTP 程序存活，`/ready` 才檢查模型 worker 等辨識條件。
