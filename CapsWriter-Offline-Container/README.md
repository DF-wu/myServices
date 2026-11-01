# CapsWriter-Offline-Container

供 axolotl 的 Portainer Git Stack 使用，對齊
[CapsWriter master `746c8a04dcce483c8731fa58ae62254c7625ce29`](https://github.com/DF-wu/CapsWriter-Offline-Container/commit/746c8a04dcce483c8731fa58ae62254c7625ce29)
（2026-11-01）。本版依上游整合成單一 `docker-compose.yml`；**只拉 GHCR image，不在部署主機 build**。

## 已核對環境與映像

- GPU 0：Tesla P4、7680 MiB，driver `580.196.07`，UUID
  `GPU-82dd964b-0c4c-78d4-8bd3-f7067e8cb29f`。
- Portainer stack `capswriter`（ID `299`）；保留原服務名稱、LAN 埠、API key 引用、
  NVIDIA reservation、16 threads、模型／logs volumes 與熱詞掛載。
- 本輪更新前，線上映像 revision 為 `54e6b88`，P4 旗標已為 `true`；日誌確認
  `selected llama backend: cuda` 與 `CUDA decoder devices verified: CUDA0, CPU`。
- 使用既有 `latest` 策略，兩個服務均為 `pull_policy: always`。上游
  [server publish](https://github.com/DF-wu/CapsWriter-Offline-Container/actions/runs/41290168386)、
  [Web publish](https://github.com/DF-wu/CapsWriter-Offline-Container/actions/runs/41290168385)、
  CI 與 portability 均已成功；查核時 `latest` 與本版 `sha-746c8a04dcce483c8731fa58ae62254c7625ce29`
  的 manifest digest 相同：server
  `sha256:89988695da86f9983eb8723fbcc17bb99d283d0fd02d8499334505d443df76ed`，
  Web `sha256:fc8ffc6862f0ae4ba7bc809233c349ecb9ef2cd818fee8c4ebc66e196ca58039`。

程式的 `fork_version` 仍為 `2.2.0`；辨別這次升級應查看 image revision，不能只看版本號。
需要固定版本時，可在 Portainer 把兩個 `*_IMAGE` 一起改為已驗證 SHA tag 或 digest。

## Portainer 更新

唯一 Git Compose path：`CapsWriter-Offline-Container/docker-compose.yml`。
移除舊 Additional Compose files 中的 `docker-compose.settings.yml`／
`docker-compose.nvidia-boost.yml`，保留原 stack 名稱與所有既有注入參數。

這份自部署 recipe 的 Web 預設一同啟動，不使用上游的選用 `web` profile，
也沒有 Web 的 `build:` 區塊。主檔已啟用 NVIDIA 裝置、P4 runtime 與 HTTP API。
Portainer 即使不載入 repo 的 `.env`，仍會使用這些主檔預設。

API key 使用現有 `DF_API_KEY` 或 `CAPSWRITER_HTTP_API_KEY`；實際秘密只由 Portainer 注入。
若已有 `CAPSWRITER_SERVER_IMAGE`／`CAPSWRITER_WEB_IMAGE` 覆寫，確認仍指向想用的新版映像。
P4 相關預設：

```dotenv
CAPSWRITER_MODEL_TYPE=qwen_asr
CAPSWRITER_QWEN_PRESET=default
CAPSWRITER_INFERENCE_HARDWARE=auto
CAPSWRITER_LLAMA_BACKEND=auto
CAPSWRITER_TESLA_P4_OPTIMIZATION=true
CAPSWRITER_GPU_BOOST_ENABLED=false
CAPSWRITER_SETTINGS_ENABLE=false
```

在 Portainer **更新 Git Stack，重新拉取 image 並重新建立容器**，才能同時套用
新版 Compose 與映像；只 restart 不會更新注入環境或掛載。修改 repo 本身不代表已部署。

## 網址與 Web

- 桌面 WebSocket：`ws://axolotl.newhome:6016`
- OpenAI 相容 API：`http://axolotl.newhome:6017/v1`
- Web Console：`http://axolotl.newhome:6018`

Web 是靜態頁面，瀏覽器直接呼叫 `http://axolotl.newhome:6017`。API base 必須是
瀏覽器可達網址，不能填容器名稱。`CAPSWRITER_WEB_API_KEY` 保持空白，使用者在頁面
輸入 token，避免公開 `/config.js` 帶有秘密。更換 hostname／port 時，同步更新
`CAPSWRITER_WEB_API_BASE` 與 `CAPSWRITER_HTTP_API_CORS_ORIGINS`。
遠端錄音需要 HTTPS，API 也應使用 HTTPS，並將 Web origin 加入 CORS。

## 設定管理與儲存

設定 API 已整合主檔，以 `CAPSWRITER_SETTINGS_ENABLE=true` 啟用，沿用 HTTP API key。
`/app/settings` 使用 `capswriter-server-settings` named volume；預設掛載但功能關閉。
不需要 settings overlay。既有 settings volume key 保留，使用原 project 名稱會重用同一個 volume。

日常設定優先序：非空 env → 保存 JSON → 程式預設。要讓 GUI 接管某欄，必須明確
設定空字串（例如 `CAPSWRITER_NUM_THREADS=`）；刪除變數會恢復 Compose 預設而鎖定欄位。
P4 旗標與 `CAPSWRITER_LLAMA_BACKEND` 仍是部署時設定，不由設定頁切換。

`CAPSWRITER_MODELS_SOURCE` 預設為 `capswriter-server-models`，保留既有模型 volume。
可改絕對 host bind 路徑，但必須先準備完整資料與映像 `appuser` 的寫入權限；切換來源
不會自動搬資料。Logs 維持 `capswriter-server-logs`。

熱詞唯讀掛載 `/mnt/appdata/capswriter-offline/hot-server.txt`，檔案必須先存在；
缺少時不會自動建成目錄。原 stack `capswriter` 的 volume 通常以 `capswriter_` 為前綴。
升級保留原 stack、models／logs／settings volumes；不要執行 `docker compose down -v`。

## P4 與調校

P4 優化沿用 llama.cpp b7798／CUDA 11.8／SM61 decoder、原 FP16 ONNX encoder 與
Q5_K_M GGUF，不更換權重，不調整時脈，也不需要 root 或額外 capabilities。
主檔維持 `cap_drop: ALL` 與 `no-new-privileges:true`。

明確 `cpu`／`vulkan` backend 或 CPU preset 會優先於 P4 旗標；`low_vram_gpu`
只讓 encoder 使用 GPU。選定 P4 CUDA 後，缺 bundle／CUDA 裝置、混合非 P4 裝置
或 probe 失敗會拒絕啟動，不悄悄改用 CPU decoder。新增其他型號顯卡時，需將
reservation 的 `count` 改成只指定 P4 的 `device_ids`，不可同時設定兩者。
此卡也供 Immich 使用，需保留顯存與散熱餘裕。

Qwen 保留原參數基準。`CHUNK_SIZE=80` 是截斷單次超長輸入，不是自動分段；
`PAD_TO` 的固定形狀 padding 僅用於 DirectML。空白 expert 值保留 adapter
batch=4096、ubatch=512，實際 logical batch 受 `N_CTX=2048` 約束；降低 `N_BATCH`
可能中止長音訊 prefill，調校前請讀
[上游 Qwen 指南](https://github.com/DF-wu/CapsWriter-Offline-Container/blob/746c8a04dcce483c8731fa58ae62254c7625ce29/docs/qwen-tuning.md)。

額外顯存鎖頻仍關閉。若要啟用，先確認支援的正 MHz，再取消主檔
`BEGIN NVIDIA_BOOST`／`END NVIDIA_BOOST` 之間每行開頭的 `# `，保留縮排，
並設定 `CAPSWRITER_GPU_BOOST_ENABLED=true` 與 `CAPSWRITER_GPU_BOOST_MEMORY_CLOCK_MHZ`。
該區塊提供 root、指定 capabilities 與 150 秒停止寬限，僅開啟權限不會自動鎖頻。
鎖頻影響同 GPU 的其他應用，強殺／斷電不保證還原；root 寫入資料可能需修復 UID/GID。

## 驗證與回退

部署後確認 image label 的 `org.opencontainers.image.revision` 為本版 SHA，並檢查：

```bash
docker logs --since 10m capswriter-server 2>&1 | grep -E 'Tesla P4 optimization enabled|selected llama backend: cuda|CUDA decoder devices verified'
curl http://axolotl.newhome:6017/health
curl http://axolotl.newhome:6017/ready
curl http://axolotl.newhome:6018/health
```

`/health` 是程序存活，`/ready` 才檢查模型 worker。確認 Web API root 後輸入 key，
跑診斷並上傳已知音訊；僅有 healthy 不足以證明 CUDA decoder 生效。

若要回退上一版，將 server／Web image 同時設為
`sha-54e6b887382458f48b3aaa4d48872f002e02bef6`，保留原 stack 與資料 volumes。
只關閉 P4 則設定 `CAPSWRITER_TESLA_P4_OPTIMIZATION=false`、backend `auto` 並重新部署。
上游遷移細節見
[單一 Compose 指南](https://github.com/DF-wu/CapsWriter-Offline-Container/blob/746c8a04dcce483c8731fa58ae62254c7625ce29/docs/compose.md)。
