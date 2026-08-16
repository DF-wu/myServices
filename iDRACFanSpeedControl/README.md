# iDRAC Fan Control on TrueNAS

這個目錄提供可貼入 TrueNAS SCALE 25.10 **Install via YAML** 的部署設定。控制器在 TrueNAS 上執行，使用本機 Kioxia CD6 與遠端 axolotl Tesla P4 的溫度控制 Dell iDRAC 風扇。

## 已確認的環境

| 項目 | 實際值 |
| --- | --- |
| TrueNAS | `192.168.10.10`, SCALE `25.10.6` |
| Apps pool | `cachePool` |
| App data | `/mnt/cachePool/appdata` |
| Docker Compose | `v2.38.1` |
| Kioxia CD6 | `KCD61LUL7T68`, serial `61J0A02CT7C8` |
| CD6 controller device | `/dev/nvme0` |
| iDRAC | `192.168.10.9` |
| axolotl | `192.168.10.13` |
| Tesla P4 | `GPU-82dd964b-0c4c-78d4-8bd3-f7067e8cb29f` |
| Controller image | `ghcr.io/df-wu/idrac-fan-control@sha256:0b67b5ea85e3d3c5de2c05eb73179a6c1adf1a5249642904db051ae47687a279` |

`docker-compose.yml` 是完整的單檔設定。部署者只需在 TrueNAS YAML 編輯器內替換三個 `REPLACE_TO_YOUR_*` 欄位，不需要建立外部 env 或 secret 檔案。

## 1. 準備日誌目錄

在 TrueNAS shell 建立持久化目錄：

```bash
sudo install -d -m 0750 /mnt/cachePool/appdata/idrac-fan-control/logs
```

若目錄尚未存在，先執行上述命令。Compose 使用這個目錄保存健康檢查所需的 `fan_control.log`。

## 2. 部署前唯讀檢查

確認 CD6 SMART 溫度：

```bash
sudo smartctl -A -j /dev/nvme0 | jq '.temperature.current'
```

確認 TrueNAS 能以設定的帳號登入 axolotl 並讀取 P4：

```bash
ssh REMOTE_GPU_USERNAME@192.168.10.13 \
  'nvidia-smi --query-gpu=index,name,uuid,temperature.gpu --format=csv,noheader,nounits'
```

## 3. TrueNAS Apps 部署

1. 開啟 **Apps > Discover**。
2. 選擇 **Custom App > Install via YAML**。
3. App name 使用 `idrac-fan-control`。
4. 貼上 `docker-compose.yml` 全部內容。
5. 在 YAML 編輯器內替換：

```yaml
IDRAC_PASSWORD: REPLACE_TO_YOUR_IDRAC_PASSWORD
REMOTE_GPU_USERNAME: REPLACE_TO_YOUR_AXOLOTL_SSH_USER
REMOTE_GPU_PASSWORD: REPLACE_TO_YOUR_AXOLOTL_SSH_PASSWORD
```

若密碼含有 `#`、`:`、`$`、空白或 YAML 特殊字元，請使用單引號包住完整值。不要把包含真實密碼的 YAML 提交回 Git。

6. 儲存並等待容器啟動。

## 4. 部署後唯讀診斷

先執行映像內建的 `diagnose`。它不會送出風扇控制命令：

```bash
sudo docker exec idrac-fan-control /usr/local/bin/fan-control.sh diagnose
```

只有下列項目全部顯示 `PASS`，才保留 `OPERATION_MODE=auto` 持續運作：

- `iDRAC/IPMI`
- `source:linux_disk`
- `source:remote_gpu`
- `decision preview`

任一項失敗時，立即依「驗證與回復」執行 `restore`，再從 TrueNAS Apps 停止此 App；修正問題並重新通過 `diagnose` 前，不要讓它持續執行。

目前控制策略允許單一來源失聯時使用另一個有效來源繼續控制；兩個來源都失敗時使用 `FAILSAFE_FAN_SPEED=70`。

查看狀態與日誌：

```bash
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' idrac-fan-control
sudo docker logs --tail 100 idrac-fan-control
sudo tail -f /mnt/cachePool/appdata/idrac-fan-control/logs/fan_control.log
```

每個正常控制週期應同時列出：

- `linux_disk:nvme0=<temperature>C`
- `remote_gpu:192.168.10.13/gpu0=<temperature>C`
- 最終 decision temperature、level 與 fan percentage

## 5. 驗證與回復

部署後可執行不改風扇的檢查：

```bash
sudo docker exec idrac-fan-control /usr/local/bin/fan-control.sh config
sudo docker exec idrac-fan-control /usr/local/bin/fan-control.sh diagnose
sudo docker exec idrac-fan-control /usr/local/bin/fan-control.sh status
```

遇到溫度異常、來源錯誤或風扇行為不符預期時，先恢復 Dell 自動控制：

```bash
sudo docker exec idrac-fan-control /usr/local/bin/fan-control.sh restore
```

然後在 TrueNAS Apps 停止 `idrac-fan-control`。Compose 的 `stop_grace_period: 45s` 會讓正常停止時的 SIGTERM trap 有時間再次恢復自動控制；主機斷電或程序遭強制終止時不能依賴此 trap。

## 安全邊界

- 不要把包含真實密碼的 YAML 或 incident dump 提交到 Git。
- 容器只映射 `/dev/nvme0`，不使用 `privileged`。
- 不掛載 Docker socket，也不要求 TrueNAS NVIDIA runtime。
- 控制器只對外連線 iDRAC UDP 623 與 axolotl SSH 22，不需發布連接埠。
- `diagnose` 是部署前必要門檻；不要在任何來源失敗時直接啟動 unattended auto mode。

## 更新映像

Compose 固定使用已驗證 digest，不會因 `latest` 漂移而在重新部署時意外換版。更新控制器時，先取得新 digest，在測試環境完成 Compose、placeholder rejection、`validate` 與 `diagnose` 驗證，再更新 `docker-compose.yml` 的 `image`。
