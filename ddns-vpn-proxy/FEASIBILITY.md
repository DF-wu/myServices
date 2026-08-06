# 可行性評估

評估日期：2026-07-18（Asia/Taipei）

結論：**架構與 repo 準備可行，但目前 host 尚未達到可部署狀態。** 實際切換只能是
受控的逐區 cutover，不是並行或零停機升級；新舊部署共享正式 Gluetun 名稱與 host ports，
舊 container 必須先停下並 rename 保存，才能讓 Portainer 建立新 container。Dashboard
proxy 與 namespace consumer runtime gates 通過後，才可依 [`MIGRATION.md`](MIGRATION.md)
部署。

## 已確認契約

| 項目 | 證據/設計 | 判定 |
| --- | --- | --- |
| Profile | 三份 Surfshark OpenVPN profile 各只有一個 hostname `remote`，並含 `auth-user-pass` | 符合 single-remote DDNS renderer |
| Transport | 舊服務使用 WireGuard country selection；新服務使用 reviewed custom OpenVPN | 可用，但 transport/效能有變更 |
| Container 名稱 | `gluetun-jp`、`gluetun-romania`、`gluetun-uk` 保留 | 可在 cutover 後維持既有 namespace 引用 |
| Proxy ports | HTTP 19010/19015/19020；SS JP 19011、RO 19016+19017、UK 19021；SOCKS5 19110/19115/19120 | 只在 `127.0.0.1` 發布，避免未經 host firewall 的 LAN exposure |
| Services | `ddns-init`、`gluetun`、`vproxy`（GOST）、`ddns-watcher` | 無 Docker socket、無 socket-proxy sidecar |
| DDNS reload | watcher 原子寫 `/state/runtime/vpn.conf`，以 X-API-Key PUT `/v1/vpn/status` stopped/running | namespace 保持不變，不需重建 GOST 或 consumer |
| Control API | Gluetun port 8000 僅在 Compose network；每區 private 64-hex key、deny-default role 與 auth config 不進 Git/env | status-only role；不得有 `/v1/vpn/settings` authority |
| Init failure | `DDNS_INIT_TIMEOUT_SECONDS=120` | DNS 永久失敗會 bounded fail，不會讓 Portainer Create 無限等待 |
| Asset source | `assets/2026-07-18.5`、`private/2026-07-18.5` 與每區單一 `runtime/.../resolv.conf` | 前兩者唯讀；resolver 為唯一 writable bind，必須是 `0600`、UID/GID 1000、單一 hardlink 與 loopback 內容 |
| OpenVPN crypto | CLI 單一 allowlist `AES-256-GCM`；TLS 1.3 control channel | 真實 JP Surfshark 初始連線與 reload 均實測 negotiated AES-256-GCM，OpenVPN UID/GID 1000、zero caps |
| SOCKS5 | repo-built GOST、非 root、zero caps、read-only、bounded handshake/dial、resource limits | 完整 greeting+CONNECT health probe 必須回 `05 00 05 00`；只發布 host loopback |
| Go vulnerability exception | `x/crypto`、`x/net`、`x/text`、`circl` 均固定到 reviewed versions；唯一 module-level `GO-2026-5932` 受精確 binary VEX 限定 | Gluetun/GOST 各自先通過 architecture-specific binary/source audit；任何額外 advisory 或 openpgp import 都 fail closed |
| Portainer CE | 2.39.4 Repository Stack Create 立即部署，UI Stack Name 覆蓋 Compose project name，部署流程不等於 `--wait` | 必須精確填 Name/ref/path，並在成功提示後自行驗 health |
| Dashboard proxies | `validate-docker-read-proxies.sh` 要求 ping 可用、2375 不發布，且 inspect/top/archive/logs/export/changes 全部拒絕 | 目前 homepage/glance `CONTAINERS=1` 會失敗；屬 deployment blocker |
| Namespace consumers | `validate-consumer-runtime.sh` 要求 drop ALL、無 CapAdd、NoNewPrivs、無 PID sharing，attach 後核對 Gluetun container ID | JP `oci-bot-client` 必須先 harden/recreate；屬 deployment blocker |

## Portainer 與檔案系統邊界

Git clone 位置在 Portainer `/data/compose/<id>`，不是穩定的 Docker host bind source；因此
Compose 不引用 repo-relative host mounts。Installer 必須從與 Portainer reference
`refs/heads/master` 相同 commit 的乾淨 host checkout 執行，並驗證
checkout commit 與 asset/private/runtime version 後才建立 Stack。

絕對 path 本身不等於 immutable。若任何 ancestor 是 world-writable、無 sticky bit 的
NFS 或可被其他 UID rename 的目錄，攻擊者可在 preflight 後替換 path 元件，讓 Docker
bind 到未審核 helper/profile。Installer 與維護人員必須先驗證 ancestor ownership/mode，
並把版本目錄放在受信任的 local filesystem；看到 path-swap 風險時應停止部署。

## Portainer environment 邊界

每個 Stack 只有一份 merged environment。三份 `portainer/*.env.example` 只包含非
secret 的 Compose interpolation inputs；每區 control key/default role、OpenVPN/HTTP
proxy/Shadowsocks credentials 由 host installer 產生/複製並以 region-bound read-only
private bind 注入。`validate-portainer-env.sh` 會：

- 要求 `REGION STACK_NAME ENV_FILE` 三個參數，且 Stack Name、project、container/profile
  名稱完全符合 region；
- 以 Compose model 精確驗證 top-level network/volume、四 services 的完整 key/env/mount
  集合、固定 loopback ports、Gluetun wrapper hash、GOST resource/timeout/health contract、
  `PRIVATE_REGION`、blank `DDNS_OVERRIDE_IPS` 與 5/120 秒 deadlines；
- 驗證該區 private 8-file bundle、credential mode/content、control key/roles，並拒絕
  將任何 proxy/VPN/control secret、unknown/duplicate env key 放進 env；
- 模擬 Portainer 的 `--project-name` 覆寫；
- 確認 no Docker socket、no published control/health port，以及 status-only helper path。

Portainer 的成功通知只代表 Compose operation 回報完成，不保證所有 healthcheck 已完成。
必須人工確認 `ddns-init` exit 0 和其餘三個 service healthy。首次 Create 失敗可能沒有
Stack record，且留下 partial resources；`MIGRATION.md` 提供 exact project cleanup。

## 尚未解除的 runtime deployment blockers

本次 read-only runtime review 已確認 `homepage-dockerproxy` 與 `glance-dockerproxy` 仍可對
container metadata endpoints 回傳 2xx；只要 `sh scripts/validate-docker-read-proxies.sh`
未通過，就不得建立任何新 Stack。修正方式只能是在各 dashboard 維護窗口設
`CONTAINERS=0` 並停用 Docker integration，或建立精確 allowlist，明確拒絕
inspect/top/archive/logs/export/changes，再重跑 gate。

共享 Gluetun namespace 的 consumer 能觀察同一 namespace 內的網路流量，因此 API key
本身不能取代 capability isolation。JP `oci-bot-client` 必須先在其 Compose drop ALL、
不加回 capability、啟用 NoNewPrivs、禁止 PID sharing，force recreate 後通過
`validate-consumer-runtime.sh oci-bot-client`；attach 新 Gluetun 後再帶 `gluetun-jp`
驗證目前 container ID。本目錄刻意不修改或重啟這些現行服務，所以這兩項是部署前
必須解除的 blocker，不是可接受的 residual risk。

## Consumer 與回滾

首次切換前，`network_mode: container:<old-name>` consumer 必須停止。新 Gluetun 建立後，
consumer 必須 force recreate 才能解析到新 container ID；只 Start stopped consumer 會
仍附掛舊 rollback container。之後的 DDNS reload 只改同一 namespace 內的 VPN loop，不
重新啟動 consumer。

舊三區同屬一個 `gluetun` Portainer project，不能用 Stack-level Stop 做單區切換。每區
用 stopped+renamed old container 保留可逆點；失敗時對新 Stack 執行 Down（保留 volume）、
rename old container 回正式名稱並 start，再 force recreate consumers。全部三區通過觀察期
後才清理 rollback containers 與舊 Stack。

## 未在靜態階段聲稱完成

- 三區真實 Surfshark credentials、出口地區與完整 proxy data path（JP crypto negotiation
  已在 temporary candidate 動態驗證）；
- 真實 DNS A record 變更下的短暫中斷時間；
- Portainer UI 端載入 merged non-secret env 與部署結果的操作驗證；
- 未盤點到的其他 external `network_mode:container` consumers；
- trusted host filesystem ancestor 的現場權限修正。

上述項目必須在維護窗口逐項驗收；在完成前不能宣稱服務已安全切換。
