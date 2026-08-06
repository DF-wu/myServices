# 人工遷移與回滾手冊

> 本文件只描述未來維護窗口。本次準備 repo 時不執行任何 lifecycle 命令。

## 不可省略的前置

1. 閱讀 `FEASIBILITY.md`，接受 Surfshark WireGuard 到 custom OpenVPN 的 transport 變更。
2. 確認 repository reference 是
   `refs/heads/master`，host installer 與 Portainer 都使用同一個
   commit，並記錄 checkout 的 commit SHA。
3. 在 Docker host 先準備 `/home/df/.config/ddns-vpn-proxy/credentials/{jp,romania,uk}`
   每區五個 owner-only credential files，再執行 `sh scripts/install-portainer-assets.sh`。
   確認 `/home/df/.local/share/ddns-vpn-proxy/assets/2026-07-18.5` 與
   `private/2026-07-18.5/{jp,romania,uk}`、`runtime/2026-07-18.5/{jp,romania,uk}`
   通過 hash、權限、owner、ancestor、credential、resolver 與 status-only auth 檢查。
4. 執行 `sh scripts/validate-static.sh`。
5. 準備三份 `0600` merged env（只含 `PRIVATE_REGION` 與非-secret inputs），依 README 的
   三個完整命令通過 `validate-portainer-env.sh REGION STACK_NAME ENV_FILE`。
6. 確認三份 env 都是正確的 `PRIVATE_REGION`、`PROXY_BIND_ADDRESS=127.0.0.1`、`VPN_TYPE=openvpn`、
   `DDNS_INIT_TIMEOUT_SECONDS=120`，且 `DDNS_OVERRIDE_IPS` 留空。
7. 從同一份 host checkout 執行 `sh scripts/validate-docker-read-proxies.sh`。預設的
   `homepage-dockerproxy`、`glance-dockerproxy` 必須讓 `/_ping` 成功，但拒絕
   `inspect/top/archive/logs/export/changes`；任一 endpoint 回 2xx 就停止遷移。目前實機
   `CONTAINERS=1` 會讓此 gate 失敗，必須先在各 dashboard 的獨立維護窗口設為
   `CONTAINERS=0` 並停用 Docker integration，或改成拒絕上述 endpoints 的精確 allowlist。
8. 在舊 `gluetun` Portainer Stack 關閉 GitOps auto-update/webhook。維護期間不要 Pull and
   redeploy，也不要按舊 Stack 的 **Stop this stack**；舊 Stack 同時管理三個地區，該按鈕
   會 down 全部三區。
9. 盤點所有 `network_mode: container:gluetun-*` consumers。已知 JP 有
   `oci-bot-client`，UK workspace 有 `codex-runner` 設定，Romania 當時未找到 consumer；
   維護窗口開始前必須重新盤點 runtime。
10. 所有 consumer 的 Compose 都必須 `cap_drop: [ALL]`、不加回 capability、設定
    `no-new-privileges:true`，且不共用 PID namespace；在 cutover 前 force recreate 並以
    `sh scripts/validate-consumer-runtime.sh CONSUMER_NAME` 驗證。JP 的 exact preflight 是
    `sh scripts/validate-consumer-runtime.sh oci-bot-client`，失敗就不得切換 JP。
11. 從 host 確認三個 profile hostname 都可解析 IPv4。DNS 初始化超過 120 秒會 fail
   closed，不會讓 Portainer Create 永久等待。

本目錄只準備 files/env/gates，不會自行修改或重啟 dashboard/consumer。目前兩類
runtime gate 都是 deployment blockers，必須先在各自維護窗口解除。**不要預先在 Portainer
建立新 Stack**：Repository Stack 沒有 draft 模式，Create 會立刻 pull/build/create/start。

## 固定對照

| 地區 | 新 Stack | 舊/新正式容器名 | rollback 暫存名 | env file |
| --- | --- | --- | --- | --- |
| JP | `ddns-vpn-proxy-jp` | `gluetun-jp` | `gluetun-jp-rollback-20260718` | `jp.env` |
| Romania | `ddns-vpn-proxy-romania` | `gluetun-romania` | `gluetun-romania-rollback-20260718` | `romania.env` |
| UK | `ddns-vpn-proxy-uk` | `gluetun-uk` | `gluetun-uk-rollback-20260718` | `uk.env` |

建議一次只切一區：Romania -> UK -> JP。每區完整驗收後才進下一區。

## 每區 cutover

以下以 Romania 示範；其他地區只能使用上表同一列的四個值替換：

```bash
stack=ddns-vpn-proxy-romania
old_name=gluetun-romania
rollback_name=gluetun-romania-rollback-20260718
env_file=/home/df/.local/share/ddns-vpn-proxy/portainer-env/romania.env
project_dir=/home/df/.local/src/myServices-ddns-deploy/ddns-vpn-proxy
```

1. 重跑 `sh scripts/validate-docker-read-proxies.sh`，確認仍通過；再記錄舊 container ID、
   image ID、health、restart count、出口 IP、proxy client 組態，
   並確認 `$rollback_name` 和 `$stack` project 目前都不存在。若曾有失敗部署，先依
   「首次 Create 失敗」清除 orphan。
2. 停止該區所有 namespace consumers，確認其狀態確實不是 running。
3. 停止 `$old_name`。Stopped container 仍佔用名稱，所以必須再執行：

```bash
docker rename "$old_name" "$rollback_name"
```

4. 確認原正式名稱已不存在、舊 container 仍以 rollback 名稱 stopped、四個該區 host
   ports 已釋放。保留 rollback container，不要 remove。
5. 只在此時開啟 Portainer **Add stack -> Repository**，輸入：

```text
Name:                 ddns-vpn-proxy-romania
Repository URL:       https://github.com/DF-wu/myServices.git
Repository reference: refs/heads/master
Compose path:         ddns-vpn-proxy/docker-compose.yml
```

   載入同一份已驗證 `romania.env`。確認 relative path volumes、auto-update、webhook 都
   disabled，再按 Deploy。JP/UK 必須使用各自精確 Stack Name 與 env，不能沿用 Romania。
6. Portainer 顯示 deployment success 後仍要等待並逐項確認：

   - Portainer 顯示的 deployed Git commit 等於 installer checkout 記錄的 SHA；
   - `ddns-init` 是 exited (0)，不是 restarting 或 failed；
   - `gluetun`、`vproxy`、`ddns-watcher` 都是 healthy；
   - Stack 只有這四個 services，沒有 socket proxy；
   - control port 8000、health port 9999 沒有 published host port；
   - HTTP/SOCKS5/Shadowsocks 只綁 `127.0.0.1` 的該區固定 ports；
   - logs 沒有 DNS timeout、auth、control API 或 restart loop 錯誤。

7. `network_mode: container:<name>` 在 create 時會解析成當時的 container ID。舊 consumer
   即使 stopped，單純 Start 仍會指向 rollback container 的舊 ID；必須用其原 Compose
   **force recreate**，再用 `validate-consumer-runtime.sh CONSUMER_NAME "$old_name"` 確認
   zero effective capabilities、NoNewPrivs 與 `HostConfig.NetworkMode` 指向新 Gluetun ID。
   JP 的 exact command 是：

```bash
sh scripts/validate-consumer-runtime.sh oci-bot-client gluetun-jp
```

   Gate 未通過時立即回滾，不得只以 consumer 能連線取代安全驗證。
8. 從 Docker host loopback 測試 HTTP、Shadowsocks 的正確認證與錯誤認證拒絕；另測
   SOCKS5 data path、確認它仍只發布在 loopback，再驗出口 IP 與地區。GOST SOCKS5
   刻意不使用會出現在 process arguments 的 credentials。不要把其他 credentials 放在
   shell command line 或 log。
9. 觀察至少兩個 DDNS poll interval。Watcher 只會原子更新
   `/state/runtime/vpn.conf`，以 X-API-Key 對 `/v1/vpn/status` PUT stopped，再 PUT running。
   Gluetun 重新讀取 runtime profile，但 container namespace 不變；GOST sidecar 與已重建的
   external consumer 不應換 container ID 或被 watcher restart。

## 首次 Create 失敗

Portainer 2.39.4 在首次 Create 途中失敗時，可能尚未保存 Stack DB record，UI 因此沒有
Stop/Delete 可用，但 Compose 已可能建立 container、network 或 `vpn-state` volume。

先不要重按 Deploy。從與發布 reference 相同的 host checkout，以同一份 env 清除 project：

```bash
docker compose \
  --project-name "$stack" \
  --file "$project_dir/docker-compose.yml" \
  --env-file "$env_file" \
  down --remove-orphans
```

不要加 `--volumes`；保留 `vpn-state` 供查證。再確認沒有任何 container/network 帶有
`com.docker.compose.project=$stack`。完成清理後直接依下節回滾舊 container；不要在原因
不明時立即 retry。

## 回滾

任一 health、proxy、出口或 consumer 驗收失敗時：

1. 停止該區所有 consumers。
2. 若新 Stack 已存在於 Portainer，按新 Stack 的 **Stop this stack**。在 CE 2.39.4
   此操作會 Compose Down、釋放 container/network，保留 Portainer env/config 與 named
   volume。不要只停新 `gluetun` container，否則正式名稱仍被佔用。
3. 若首次 Create 失敗且沒有 Stack record，改用上一節的 exact project cleanup。
4. 確認正式 `$old_name` 已不存在，再執行：

```bash
docker rename "$rollback_name" "$old_name"
docker start "$old_name"
```

5. 等舊 Gluetun healthy，驗證舊出口與 proxy。
6. 用 consumer 原 Compose force recreate，使 namespace 明確附掛回復原後的舊 container
   ID；再以 `validate-consumer-runtime.sh CONSUMER_NAME "$old_name"` 驗證 capability、
   NoNewPrivs 與 attachment。JP 使用同一個 `oci-bot-client gluetun-jp` exact command。
7. 保留新 Stack 的 inactive record 與 `vpn-state` 供診斷。修正原因並重新完成所有
   preflight 前，不要按 Start this stack。

## 全區完成後

在回滾觀察期結束前保留三個 stopped rollback containers，並保持舊 `gluetun` Stack
auto-update/redeploy disabled。確認三個新 Stack 都穩定且不再需要回滾後，才移除舊
rollback containers 與舊 Stack。新舊 project labels 不同；清理時仍須逐一核對 container
ID，絕不能只依相似名稱批次刪除。
