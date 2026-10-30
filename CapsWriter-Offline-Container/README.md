# CapsWriter-Offline-Container

對應 repo：<https://github.com/DF-wu/CapsWriter-Offline-Container>

這份是放進 `myServices` 的自部署版本，維持目前倉庫慣例：

- 每個服務一個目錄
- 以 `docker-compose.yml` 為主
- 使用同目錄 `.env` 控制主要參數
- 模型與 logs 使用本機 Docker named volume；熱詞檔保留在 `/mnt/appdata/...`

---

## 預設行為

- 映像：`ghcr.io/df-wu/capswriter-offline-server:latest`
- 預設模型：`qwen_asr`
- 預設 WebSocket port：`6016`
- 預設硬體策略：`auto`（有 GPU 就優先 GPU，否則回退 CPU）
- OpenAI 相容 HTTP API：**預設關閉**

---

## 首次部署

```bash
cd myServices/CapsWriter-Offline-Container
mkdir -p /mnt/appdata/capswriter-offline
cp hot-server.example.txt /mnt/appdata/capswriter-offline/hot-server.txt
docker compose up -d
```

第一次冷啟動可能會很久，因為容器會自動下載模型與 backend。

## 從舊模型掛載切換

模型掛載已改為 `capswriter-server-models:/app/models`。以目前 Portainer stack
名稱 `capswriter` 部署時，實際 volume 名稱是
`capswriter_capswriter-server-models`。Docker 初次建立 volume 時會沿用映像內
`/app/models` 的擁有者，避免 NFS 檔案 UID 與容器 `appuser` 不一致導致
bootstrap lock 被拒絕。

由 Portainer 自行拉取 recipe 更新並部署。新 volume 不會自動匯入舊 NFS
目錄的模型；未預先複製時，服務會自動下載。

確認 Portainer 更新後，容器的 `/app/models` 已掛載上述 volume，且服務
healthcheck 與 `/ready` 正常，再移除舊目錄
`/mnt/appdata/capswriter-offline/models`。`hot-server.txt` 仍從 appdata 掛載，
請保留 `/mnt/appdata/capswriter-offline` 與其中的熱詞檔。

---

## 常用檢查

```bash
cd myServices/CapsWriter-Offline-Container
docker compose ps
docker compose logs -f capswriter-server
```

預設 WebSocket endpoint：

```text
ws://127.0.0.1:6016
```

---

## CPU-only 啟動

把 `.env` 改成：

```env
CAPSWRITER_INFERENCE_HARDWARE=cpu
CAPSWRITER_GPU_DEVICE_COUNT=0
```

之後重建：

```bash
docker compose up -d --force-recreate
```

---

## 切到 Fun-ASR-Nano

把 `.env` 改成：

```env
CAPSWRITER_MODEL_TYPE=fun_asr_nano
```

然後重建：

```bash
docker compose up -d --force-recreate
```

---

## 啟用 OpenAI 相容 HTTP API

1. 先在 `.env` 設定：

```env
CAPSWRITER_HTTP_API_ENABLE=true
CAPSWRITER_HTTP_API_KEY=sk-change-me
```

2. 再把 `docker-compose.yml` 裡的 `6017` port mapping 取消註解。

3. 重建服務：

```bash
docker compose up -d --force-recreate
```

啟用後 base URL 會是：

```text
http://127.0.0.1:6017/v1
```

如果你要對外暴露，**一定要設 `CAPSWRITER_HTTP_API_KEY`**。

---

## 備註

### v2.1 NVIDIA 預加速

一般 GPU 推論使用現有的 `CAPSWRITER_INFERENCE_HARDWARE=auto` 與
`CAPSWRITER_QWEN_PRESET`。額外的顯存鎖頻預加速需先使用發布後的 v2.1
映像，再在這個目錄的 `.env` 設定：

```env
CAPSWRITER_GPU_BOOST_ENABLED=true
CAPSWRITER_GPU_BOOST_DEVICE=0
CAPSWRITER_GPU_BOOST_MEMORY_CLOCK_MHZ=6000
CAPSWRITER_GPU_BOOST_IDLE_SECONDS=1
CAPSWRITER_GPU_BOOST_TIMEOUT=5
```

`6000` 僅是設定格式示例，必須換成該顯卡實際支援的 MHz，不能直接照抄。
裝置索引以容器可見的 NVIDIA 裝置為準；預設值 `0` MHz 表示未設定，不能
啟用預加速。可先在主機唯讀查詢 `nvidia-smi -i 0 -q -d SUPPORTED_CLOCKS`。

若選用預加速，Portainer 的 Additional Compose files 需加入同目錄的
`docker-compose.nvidia-boost.yml`。它明確改用 root 並提供 NVIDIA 鎖頻所需
的 `SYS_ADMIN` 與模型檔案存取能力；預設 recipe 不加這些權限。
此檔只提供權限，不會替你啟用 `.env` 開關。

HTTP、桌面錄音與檔案辨識都會觸發，閒置及正常退出會嘗試還原。權限不足、
GPU 不支援或命令失敗時記錄警告並繼續辨識，不因此讓服務重啟。
強制 CPU、`cpu_only` 及完整 CPU 回退時不鎖頻；仍使用 CUDA 的
`low_vram_gpu` 保留預加速資格。
Hopper 等需要 deferred memory clocks 的裝置不適用此即時鎖頻功能。
強制 kill／主機斷電不能保證還原，需檢查主機時脈。

這些修改必須先提交並推送到 Portainer 追蹤的 Git 分支；本機編輯不會改變
Portainer 拉到的 recipe。映像發布與 recipe 推送是兩個步驟，發布後應使用
不可變的 `sha-<完整 commit>` 映像 tag，確認 `/health` 的 `fork_version` 是
`2.1.0`，再檢查 `/ready` 與模型掛載。

官方說明：<https://docs.nvidia.com/deploy/nvidia-smi/index.html>

- `hot-server.txt` 我刻意不直接綁 repo 內檔案，而是走 `/mnt/appdata/capswriter-offline/hot-server.txt`，這樣你在主機上調整熱詞比較直觀。
- 模型與 logs 使用 Docker named volume；請確認 Docker 資料目錄位於本機磁碟。`docker compose down -v` 會刪除這些 volume 與模型快取。
