# clash-lan

部署在 axolotl 的內網代理。內網裝置不需要安裝 WireGuard，只需將 HTTP 或
SOCKS5 proxy 設為 `192.168.10.13:7890`，流量就會由 Mihomo 經指定的 YAML
節點送出。

> 這是明確代理模式，不是透明閘道。未使用系統代理的程式、遊戲主機及部分 App
> 可能不會經過本服務。若要整台裝置無感接管，需改做路由器 PBR／透明閘道。

## axolotl 準備

把 Clash YAML 放到 axolotl：

```bash
sudo install -d -m 700 /opt/appdata/clash-lan
sudo install -m 600 EdNovasCloud_clash.yaml \
  /opt/appdata/clash-lan/EdNovasCloud_clash.yaml
```

## Portainer

- Stack name: `clash-lan`
- Compose path: `clash-lan/docker-compose.yml`
- Endpoint: axolotl 的 Docker Standalone

必填環境變數：

```text
CLASH_YAML_PATH=/opt/appdata/clash-lan/EdNovasCloud_clash.yaml
CLASH_NODE_FILTER=0.5X 🇯🇵 Japan Tokyo
PROXY_USERNAME=<自行設定的內網代理帳號>
PROXY_PASSWORD=<自行設定的高強度密碼>
```

選填：

```text
MIHOMO_SECRET=<Mihomo API 密碼>
TZ=Asia/Taipei
```

Mihomo API 位於 axolotl 的 `127.0.0.1:19090`。未沿用 `9090`，因為該 port
目前已被 axolotl 上的其他服務占用。

不需要填：

```text
WG_HOST
WG_ADMIN_PASSWORD
WG_PORT
WG_UI_PORT
```

也不需要在路由器或防火牆開放 `51820/UDP`。本服務只在 axolotl 的 LAN IP
`192.168.10.13` 上提供 `7890/tcp` 與 `7890/udp`。

## 裝置設定

HTTP proxy 與 SOCKS5 都使用：

```text
Server:   192.168.10.13
Port:     7890
Username: PROXY_USERNAME 的值
Password: PROXY_PASSWORD 的值
```

瀏覽器或作業系統若要求分開填 HTTP／HTTPS proxy，兩者都填
`192.168.10.13:7890`。需要 UDP 的應用必須使用支援 SOCKS5 UDP associate 的
client；一般 HTTP proxy 不會代理 UDP。

## 驗證

在內網裝置測試 HTTP proxy：

```bash
curl --proxy http://<username>:<password>@192.168.10.13:7890 \
  https://api.ipify.org
```

顯示的應是 YAML 選定節點的出口 IP，而不是家中原始公網 IP。

查看服務狀態：

```bash
docker logs --tail=100 clash-lan
```
