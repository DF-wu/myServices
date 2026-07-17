# 人工遷移與回滾手冊

> 本文件是未來維護窗口的操作手冊。本次建立部署檔時沒有執行任何下列 lifecycle 命令。

## 先決條件

1. 閱讀 `FEASIBILITY.md`，接受 WireGuard → OpenVPN transport 轉換。
2. 從 examples 建立 `.env.common` 與 `env/{jp,romania,uk}.env`，填入所有必要 secrets，
   並設為 `0600`。
3. 執行 `sh scripts/validate-static.sh`；它不會碰 container runtime。
4. 確認 host firewall 只允許可信 LAN 來源連入 190xx/191xx ports。
5. 再次盤點是否新增了 `network_mode: container:gluetun-*` consumer。每區模板只能自動
   協調 `DEPENDENT_CONTAINER_NAME` 指定的一個容器；額外 consumer 必須納入維護程序。

以下是地區參數的共同寫法：

```bash
docker compose \
  --file docker-compose.yml \
  --env-file .env.common \
  --env-file env/jp.env \
  config --quiet
```

把 `jp` 換成 `romania` 或 `uk` 即可操作另一個獨立 project。不要省略 region env，也不要
在舊 Gluetun 還佔用相同名稱/ports 時執行 `up`。

## 建議切換順序

一次只切一區並完成出口驗收，再繼續下一區：Romania（無直接 consumer）→ UK → JP。
JP 放最後，因 runtime 盤點確認 `oci-bot-client` 正在使用它。

每區的維護步驟：

1. 記錄舊 Gluetun 的出口 IP、container health、相關 consumer 狀態與 proxy client 設定。
2. 停止該區所有 `network_mode: container:<舊 Gluetun>` consumer。這一步不可省略；
   單純復用容器名稱不會讓已執行的 consumer 自動換 network namespace。
3. 只停止舊 `Gluetun` project 的該地區 service，確認名稱與 ports 已釋放。
4. 使用該地區兩份 env 執行 `docker compose up -d --wait --wait-timeout 180`。
5. 確認 `ddns-init` exited 0，Gluetun/vproxy/watcher/socket proxy healthy。
6. 重新建立或啟動先前停止的 consumers；JP 是 `oci-bot-client`，UK 是當時實際使用的
   `codex-runner` compose。確認其 network mode 已指向新的 Gluetun container ID。
7. 分別驗證 HTTP、SOCKS5、Shadowsocks 出口 IP、地區與錯誤認證拒絕。
8. 觀察至少兩個 DDNS poll interval，確認沒有非預期 restart loop，再進下一區。

## DDNS 變更後的 consumer 行為

Gluetun restart 會換 network namespace。本部署的 watcher 會：

1. 原子更新 runtime profile；
2. restart Gluetun 並等待 healthy；
3. restart vproxy 並確認它已加入新 namespace；
4. 精確 inspect `DEPENDENT_CONTAINER_NAME`；只有它原本 running 才 restart，stopped/absent
   都保持原狀；
5. consumer-only 失敗以 pending marker 重試，不會每個 poll 重複 restart VPN。

這個權限只涵蓋 env 明列的單一名稱，不是任意 Docker 管理權。

## 回滾

若任一區 tunnel/proxy/consumer 驗收失敗：

1. 停止該區 consumers。
2. 使用相同 region env 對新 project 執行 `docker compose down`；預設保留 `vpn-state`，
   便於查證。不要加 `--volumes`，除非確定不需要現場狀態。
3. 從舊 `Gluetun/docker-compose.yml` 重新啟動同地區 service。
4. 重新建立/啟動 consumers，使其附掛回舊 Gluetun 的當前 container ID。
5. 驗證舊出口與服務後再結束維護窗口。

舊 Compose 本次完全未修改，因此回滾來源仍在；但新舊 stack 不能同時持有相同名稱與 ports。
