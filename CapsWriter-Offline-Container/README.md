# CapsWriter-Offline-Container

對應 repo：<https://github.com/DF-wu/CapsWriter-Offline-Container>

這份是放進 `myServices` 的自部署版本，維持目前倉庫慣例：

- 每個服務一個目錄
- 以 `docker-compose.yml` 為主
- 使用同目錄 `.env` 控制主要參數
- 持久化模型資料走 `/mnt/appdata/...`

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
mkdir -p /mnt/appdata/capswriter-offline/models
cp hot-server.example.txt /mnt/appdata/capswriter-offline/hot-server.txt
docker compose up -d
```

第一次冷啟動可能會很久，因為容器會自動下載模型與 backend。

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

- `hot-server.txt` 我刻意不直接綁 repo 內檔案，而是走 `/mnt/appdata/capswriter-offline/hot-server.txt`，這樣你在主機上調整熱詞比較直觀。
- logs 先維持 Docker named volume，這是上游 Docker server 文件特別保留的做法，可少踩 non-root bind mount 權限坑。