# WG Easy + ClashRS Gateway

將標準 WireGuard 用戶端流量交給 Clash 相容代理核心，再由 Clash 訂閱中的
VMess、VLESS、Shadowsocks、Trojan、Hysteria2 或 TUIC 節點送出。

本服務刻意不使用目前倉庫內容與原專案定位不一致的 Mihomo 映像。代理核心採用
[ClashRS](https://github.com/Watfaq/clash-rs)，並從指定 GitHub Release 下載靜態
binary，在 build 時驗證 SHA-256。ClashRS 原生支援 Clash YAML、proxy provider、
TProxy 與 `--compatibility` 相容模式。

WG Easy 與 Alpine base image 也固定到 OCI manifest digest；升級時應同時核對 tag
與新 digest，不要只改版本字串。

## Portainer 相容性

此 Stack 可由 **Portainer 的 Git Repository 模式部署到 Docker Standalone**。Compose
路徑填 `wg-easy-clashrs/docker-compose.yml`。它不依賴 Portainer Business Edition 的
relative-path volume 功能：規則腳本與設定範本已包含在本機建置的 ClashRS image
中，持久資料只使用 `APPDATA_DIR` 指定的宿主機絕對路徑。

Portainer 部署時必須加入：

| 環境變數 | 值 |
|---|---|
| `APPDATA_DIR` | Docker host 絕對路徑，例如 `/opt/appdata/wg-easy-clashrs` |
| `CLASH_SUBSCRIPTION_URL` | 供應商提供的 Clash subscription URL |

其餘變數可從 `.env.example` 覆寫。首次啟動會把範本寫入
`${APPDATA_DIR}/clash-rs/config.yaml`；之後即使移除環境變數，也會保留並使用既有
設定。Portainer 端點必須支援 Docker build，且此 Compose 是 Docker Standalone
用途，不可用 `docker stack deploy` 部署成 Swarm Stack，因為 Swarm 不支援
`network_mode: service:...`。

不要從 Portainer 的 **Containers** 頁面對 `wg-clash-core` 或 `wg-clash-rules`
單獨按 **Recreate**。Portainer 目前對共享 service network namespace 的單容器重建
仍有[已知問題](https://github.com/portainer/portainer/issues/13012)。更新時請回到
**Stacks** 頁面，對整個 Stack 執行 **Update the stack / Redeploy**。

## 架構

```text
WireGuard client
  -> wg-easy (wg0)
  -> nftables TProxy (only packets entering from wg0)
  -> ClashRS :7893
  -> Clash subscription node
  -> Internet
```

`gateway-rules` 與 `clash-rs` 共用 `wg-easy` 的 network namespace。規則只攔截
從 `wg0` 進入的 TCP/UDP，因此不會把 WireGuard UDP 握手或 ClashRS 自己的節點
連線再次送入代理。其他由 `wg0` 進入的 IP 協議會 fail closed，ClashRS 故障時
也不會改由主機公網直接送出。

## 限制

- ClashRS 目前不支援 ShadowsocksR (`type: ssr`)。購買前應確認供應商至少提供
  VMess、VLESS、SS、Trojan、Hysteria2 或 TUIC。
- 這是 TCP/UDP 代理閘道，不是完整的 L3 出口；ICMP (`ping`)、GRE、ESP 等協議
  會被丟棄。
- IPv6 預設停用，避免客戶端繞過 IPv4 代理出口。
- `wg-easy`、`clash-rs`、`gateway-rules` 必須一起重建；不要單獨重啟
  或 recreate `wg-easy`，否則共享的 network namespace 會被替換。

## 部署

### 1. 建立本機設定

```bash
cd wg-easy-clashrs
cp .env.example .env
mkdir -p /opt/appdata/wg-easy-clashrs
chmod 700 /opt/appdata/wg-easy-clashrs
chmod 600 .env
```

編輯 `.env`，設定絕對路徑 `APPDATA_DIR` 與 `CLASH_SUBSCRIPTION_URL`。訂閱網址
通常包含帳號 token，不可提交到 Git 或貼入公開訊息。首次啟動後可直接修改
`${APPDATA_DIR}/clash-rs/config.yaml` 做進階設定，容器不會覆寫既有檔案。

### 2. 驗證並啟動

```bash
docker compose build --pull clash-rs
docker compose config --quiet
docker compose up -d
docker compose ps
docker compose logs --tail=100 clash-rs gateway-rules
```

WG Easy 管理介面預設只監聽宿主機 `127.0.0.1:51821`。從遠端管理時使用 SSH
port forwarding，不要直接把管理介面暴露到公網：

```bash
ssh -L 51821:127.0.0.1:51821 user@server
```

然後開啟 `http://127.0.0.1:51821` 完成 WG Easy 初始設定。

### 3. WG Easy 建議值

| 設定 | 建議值 |
|---|---|
| Host | VPS 公網 IP 或 DNS 名稱 |
| Port | `51820` |
| Interface address | `10.8.0.1/24` |
| Client Allowed IPs | `0.0.0.0/0` |
| Client DNS | `10.8.0.1` |
| Client MTU | 先用 `1280`，穩定後可測試 `1340` |

不要向客戶端發放 IPv6 address 或 `::/0`，除非後續另外完成 IPv6 TProxy 與
防洩漏規則。

## 驗證出口與防洩漏

客戶端連上 WireGuard 後：

```bash
curl -4 https://api.ipify.org
curl -4 https://ipinfo.io/json
nslookup example.com 10.8.0.1
```

再暫停 ClashRS 驗證 fail-closed；此時前兩個命令必須失敗，而不是顯示 VPS IP：

```bash
docker compose stop clash-rs
# 在 WireGuard client 重新執行 curl，確認無法連線
docker compose start clash-rs
```

查看實際命中計數：

```bash
docker exec wg-clash-rules nft list table inet wg_clash_gateway
```

## 更新

先到 [ClashRS Releases](https://github.com/Watfaq/clash-rs/releases) 確認新版本，下載
對應的 `x86_64-unknown-linux-musl` 與 `aarch64-unknown-linux-musl`，自行計算：

```bash
sha256sum clash-rs-*-unknown-linux-musl
```

將版本與兩個 SHA-256 更新到 `.env`，再執行：

```bash
docker compose build --no-cache clash-rs
docker compose up -d --force-recreate
```

不要將 ClashRS 或 WG Easy 改成未固定的 `latest`。

## 上游

- [ClashRS](https://github.com/Watfaq/clash-rs)
- [ClashRS configuration reference](https://watfaq.github.io/clash-rs/)
- [WG Easy](https://github.com/wg-easy/wg-easy)
