# DDNS VPN Proxy（Gluetun 多地區遷移）

這是舊 `myServices/Gluetun` 的**獨立、可預先驗證**替代部署。它用 DDNS-aware helper
把 hostname-based OpenVPN profile 原子轉成 Gluetun 可接受的 IP-based runtime profile，
並在 A record/profile 改變時協調 Gluetun、vproxy 與已知 network namespace consumer。

目前狀態：部署檔已建立；舊服務未被修改、啟動、停止或重啟。完整判定見
[`FEASIBILITY.md`](FEASIBILITY.md)，未來人工切換見 [`MIGRATION.md`](MIGRATION.md)。

## 地區與相容契約

| 地區 | 保留的 Gluetun 名稱 | HTTP | Shadowsocks TCP/UDP | 新 SOCKS5/TCP | 已知 namespace consumer |
| --- | --- | ---: | ---: | ---: | --- |
| 日本 | `gluetun-jp` | 19010 | 19011 / 19011 | 19110 | `oci-bot-client` |
| 羅馬尼亞 | `gluetun-romania` | 19015 | 19016 / 19017 | 19115 | 無 |
| 英國 | `gluetun-uk` | 19020 | 19021 / 19021 | 19120 | `codex-runner`（若存在且 running） |

SOCKS5 使用新 port，因為既有 19011/19016/19017/19021 是 Shadowsocks 契約；兩種協定
不可只靠沿用 port 假裝相容。Homepage 與外部 `container:<name>` 引用可繼續使用原名稱。

## 為何一份 Compose 執行三次

上游 DDNS stack 的可靠性/安全檢查是以單一 VPN endpoint 為單位。這裡保留同一份
`docker-compose.yml`，再以三個 region env 建立三個 Compose project。結果是：

- helper/script 只有一份，不會出現三份手抄 Compose 漂移；
- 每區有自己的 default network、internal Docker API network 與 `vpn-state` volume；
- 每個 socket proxy 只允許自己的 Gluetun、vproxy 及至多一個已知 consumer；
- 三區仍可各自維護、回滾，不會共用 `current.ovpn`。

## 檔案

```text
ddns-vpn-proxy/
├── docker-compose.yml
├── .env.common.example
├── env/
│   ├── jp.env.example
│   ├── romania.env.example
│   └── uk.env.example
├── docker/socket-proxy-haproxy.cfg.tmpl
├── scripts/ddns-openvpn.sh
├── scripts/validate-static.sh
├── FEASIBILITY.md
└── MIGRATION.md
```

## 不啟動容器的驗證

以下命令只執行 shell syntax、Compose render/model 與 host profile contract 檢查：

```bash
sh scripts/validate-static.sh
```

它不會 pull/build image，也不會 create/start/stop/restart/remove container。

## 準備實際 env（本次未執行）

```bash
cp .env.common.example .env.common
cp env/jp.env.example env/jp.env
cp env/romania.env.example env/romania.env
cp env/uk.env.example env/uk.env
chmod 600 .env.common env/*.env
```

至少填入 `.env.common` 的：

- `OPENVPN_USER` / `OPENVPN_PASSWORD`
- `HTTPPROXY_USER` / `HTTPPROXY_PASSWORD`
- `SOCKS5_USER` / `SOCKS5_PASSWORD`
- `SHADOWSOCKS_PASSWORD`

範例保留舊服務的 `0.0.0.0` LAN bind；缺少任何必要認證時 `ddns-init` 會拒絕啟動
Gluetun。若只需本機使用，可改成 `PROXY_BIND_ADDRESS=127.0.0.1`，並另外用 host firewall
限制實際可連入的來源。

## 安全與來源

- Gluetun 固定 `qmcgaw/gluetun:v3.41.1`；其他 images 也全部固定版本，不用 `latest`。
- watcher 不直接掛 Docker socket；internal HAProxy policy 只允許精確 inspect/restart path。
- VPN profile 全程 read-only；runtime state 是可重新產生的 per-project named volume。
- 非 Gluetun services 全部 `cap_drop: ALL`、`read_only`（適用處）與
  `no-new-privileges:true`。
- helper 來自 `DF-wu/ddns-openvpn-proxy` production Compose 核心 commit
  `8e2523978acb19e3f8aec7485db6de932918b76b`；評估時官方 main 是
  `ca5200d28ac992c8c71200fe49c7d24f850133b3`，後兩個 commits 只新增/發布另一個
  compatibility image，未改此核心。部署副本差異只有已知 consumer namespace 協調與
  legacy Shadowsocks 安全 gate。

目前契約只涵蓋單一 hostname、IPv4 A record、單一 OpenVPN `remote`（或未來的單一
WireGuard peer）。多 remote、IPv6 endpoint、SOCKS5 UDP 不在支援範圍。
