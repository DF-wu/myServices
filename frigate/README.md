# Frigate — Tesla P4

這份配置針對目前的 axolotl Linux VM：48 個 CPU 執行緒、約 125 GiB RAM、單張 Tesla P4（GPU 0，7680 MiB）、NVIDIA 580.178.04 驅動與已安裝的 NVIDIA Container Runtime。硬體、儲存與服務狀態於 2026-10-21 以唯讀方式核對；未部署 Frigate。

## 配置內容

- 固定 `0.18.2-tensorrt` 映像；amd64 推論使用 `type: onnx` 的 CUDA 後端。映像名稱保留 `tensorrt`，但舊 `type: tensorrt` detector 已不適用。
- 指定 GPU 0，開放 NVIDIA 的 compute、video、utility 功能；影片硬解使用 `preset-nvidia`。
- `55000` 對應有驗證的 HTTPS `8971`；網址為 `https://<host>:55000`。原本 `55000:5000` 的無驗證入口已移除，反向代理也需改用 HTTPS 上游。內建憑證預設為自簽，首次登入密碼由 Frigate 啟動日誌提供。
- `/config` 改為完整、可寫的本機目錄 `/var/lib/frigate/config`，持久保存 SQLite、模型、臉部資料與設定。主機的 `/mnt/appdata` 是 NFS，舊 `frigate` 目錄為空，故不沿用它儲存 SQLite。
- 錄影繼續使用 `/mnt/mydata/frigate_data`（NFS）。該目錄目前不存在；日後部署前要先建立並確認掛載與寫入權限。兩個 bind mount 都停用自動建立目錄，避免拼錯路徑後產生空配置。
- 2 GiB shared memory、1 GB tmpfs 快取；detect 預設 5 FPS，實際容量與攝影機解析度仍需量測。
- 使用獨立 `FRIGATE_RTSP_PASSWORD`，取代共用 `DF_PASSWORD`。真實攝影機資料與密碼只放本機；此公開儲存庫僅保留範本。

## 部署前準備（本次未執行）

1. 在部署主機建立本機設定目錄與錄影目錄，確認 NFS 已掛載、空間與寫入權限足夠。若覆寫 `FRIGATE_CONFIG_DIR`，仍必須選可可靠執行 SQLite 的本機檔案系統。
2. 將 `.env.example` 複製為未追蹤的 `.env`，設定專用攝影機密碼；Portainer 可改在 stack environment 輸入相同變數。
3. 將 `config.example.yml` 複製為 `/var/lib/frigate/config/config.yml`，依官方 [ONNX／YOLOv9 匯出步驟](https://github.com/blakeblackshear/frigate/blob/v0.18.2/docs/data/object_detectors_models.yaml) 匯出 **YOLOv9-s、320×320、FP32**，放到 `/var/lib/frigate/config/model_cache/yolov9-s-320.onnx`。匯出尺寸、資料型別與設定必須一致；不要加入 `--half`。模型尚未準備就啟動會導致 detector 無法載入。
4. 範本的 `cameras: {}` 是有效的無攝影機初始配置，沒有虛構串流。新增真實攝影機時，於本機 `cameras` 下設定 FFmpeg inputs，明列 `detect`／`record` roles，並按串流設定解析度。含密碼的 URL 可用 `{FRIGATE_RTSP_PASSWORD}` 引用容器環境變數；保留 YAML 引號並確保 URL 特殊字元正確編碼。
5. 如需錄影，另依場景設定 `record.enabled` 與保留天數；範本尚未啟用錄影。若需 MQTT／Home Assistant 整合，再於本機補上 MQTT，範本預設關閉。
6. 經另外授權部署後，先驗證一支攝影機硬解、ONNX CUDA 模型載入與實際推論，再逐項啟用人臉、車牌與語意搜尋。先勿把多個進階模型同時開啟。

`config.example.yml` 已預選 GPU 人臉辨識 large、CPU 車牌辨識與支援中文的 Jina V2 large，但三者均關閉。Jina V2 使用 FP16 且需求較高，P4 上的速度未實測；`USE_FP16=False` 不能把預製 ONNX 模型轉為 FP32。使用英文搜尋可改選負擔較低的 Jina V1。

P4 所屬 Pascal 的最後 CUDA Toolkit 支援為 12.x、最後驅動分支為 R580；目前驅動已在此分支，這次無須變動主機驅動。不要因為此配置提交而自動升級驅動或套用容器更新。

## 檢查

以下 Compose 檢查只解析配置，不建立容器、下載映像或啟動服務。從本目錄執行；必須先提供 `.env` 或 stack 環境變數：

```bash
docker compose config --quiet
```

實際部署後可用以下唯讀指令驗收（本次未啟動容器，故尚未執行這組驗收）：

```bash
nvidia-smi
nvidia-smi dmon -s u
docker exec frigate python3 -c 'import onnxruntime as ort; print(ort.__version__); print(ort.get_available_providers())'
docker logs --tail 300 frigate
```

`CUDAExecutionProvider` 出現在清單中仍不代表模型已成功在 GPU 執行；須同時確認 detector 實際推論、延遲、VRAM、FFmpeg 解碼與錯誤日誌。此提交只準備配置；推送不代表部署或 P4 模型相容性已實測通過。

## 來源

- [Frigate 0.18.2](https://github.com/blakeblackshear/frigate/releases/tag/v0.18.2)
- [NVIDIA 映像依賴](https://github.com/blakeblackshear/frigate/blob/v0.18.2/docker/tensorrt/requirements-amd64.txt)
- [Frigate NVIDIA 硬解](https://docs.frigate.video/configuration/hardware_acceleration_video/#nvidia-gpus)
- [Frigate 安裝及埠配置](https://docs.frigate.video/frigate/installation/)
- [NVIDIA 架構／CUDA／驅動矩陣](https://docs.nvidia.com/datacenter/tesla/drivers/cuda-toolkit-driver-and-architecture-matrix.html)
