# clashrs-wg

此 Stack 預計部署在 **axolotl 的 Portainer**。`docker-compose.yml` 已逐段加入繁體
中文註解；在 Portainer 的 Web editor 或 Git repository 畫面即可直接對照閱讀。

內網裝置透過 WireGuard 連入 axolotl，再由 Mihomo 使用 YAML 中指定的節點出網。
裝置仍然需要安裝 WireGuard；本模式只是把 WireGuard 入口限制在家中內網使用。

目前實作的 VPN 入口是 **WireGuard**。它不是 HTTP/SOCKS proxy，也不要求裝置設定
系統代理。若確定還要讓同一服務接受 OpenVPN `.ovpn` client，需另加 OpenVPN
server container；OpenVPN 與 WireGuard 是不同協定，不能共用同一個 server port。

## Portainer

- Stack name: `clashrs-wg`
- Compose path: `clashrs-wg/docker-compose.yml`
- Endpoint: Docker Standalone, not Swarm
- Compose engine: 2.23.1 or newer (`configs.content` is required)

Required environment variables:

| Variable | Value |
|---|---|
| `WG_HOST` | axolotl 的 LAN IP，固定填 `192.168.10.13` |
| `WG_ADMIN_PASSWORD` | Initial wg-easy administrator password |
| `CLASH_YAML_PATH` | Absolute Docker-host path to a Clash YAML file |
| `CLASH_NODE_FILTER` | Unique node name or regex selecting the subscription server |

以目前附件選擇日本東京節點時，axolotl 的 Portainer 可填成：

```text
WG_HOST=192.168.10.13
WG_ADMIN_PASSWORD=請自行設定高強度管理密碼
CLASH_YAML_PATH=/home/df/appdata/clashrs-wg/EdNovasCloud_clash.yaml
CLASH_NODE_FILTER=0.5X 🇯🇵 Japan Tokyo
TZ=Asia/Taipei
```

Optional variables: `WG_ADMIN_USERNAME`, `WG_PORT`, `WG_UI_PORT`,
`MIHOMO_API_PORT`（預設 `19090`）, `MIHOMO_SECRET`, and `TZ`.

`WG_HOST` 是 WireGuard client 要連線的 axolotl 內網位址，不是 YAML 裡的節點。
axolotl 已核對為 `192.168.10.13/23`，所以填：

```text
WG_HOST=192.168.10.13
```

不需要在家中路由器設定 `51820/UDP` port forwarding，也不需要公網 IP 或網域。
若 axolotl 的 DHCP 位址日後變更，必須同步更新 `WG_HOST`，因此建議在路由器為
axolotl 保留 `192.168.10.13`。

Compose 亦將 WireGuard port 明確綁在 `192.168.10.13`，不會監聽 axolotl 的
Tailscale 或其他主機位址。

To use one particular subscription node, set `CLASH_NODE_FILTER` to a unique part of
its full name. For a node named `Japan Tokyo 01`:

```text
CLASH_NODE_FILTER=Japan Tokyo 01
```

The filter is case-sensitive and accepts regular-expression syntax. It should match
only one node; otherwise Mihomo initially selects the first matching node.

## Import a Clash YAML

The YAML stays on the Docker host and is mounted read-only. It is not copied into this
repository or stored in the Compose file. Put the downloaded YAML on the server first:

```bash
install -d -m 700 /home/df/appdata/clashrs-wg
install -m 600 EdNovasCloud_clash.yaml \
  /home/df/appdata/clashrs-wg/EdNovasCloud_clash.yaml
```

Then set this Portainer environment variable:

```text
CLASH_YAML_PATH=/home/df/appdata/clashrs-wg/EdNovasCloud_clash.yaml
```

Both a full Clash configuration containing `proxies`, `proxy-groups`, and `rules`, and
a provider-only YAML containing `proxies`, are accepted. Mihomo imports only the
`proxies` list as a file provider; this stack keeps control of TUN, DNS, and gateway
routing. To refresh an updated YAML, replace the host file atomically and redeploy the
stack.

The administrator password is used only by wg-easy's first-start initialization.
After setup, remove `WG_ADMIN_PASSWORD` from the Portainer environment and redeploy.

## 內網資料流

```text
內網裝置 -> WireGuard -> 192.168.10.13:51820/UDP
         -> wg-easy wg0 -> Mihomo TUN -> YAML 指定節點 -> Internet
```

Both containers share wg-easy's network namespace. Mihomo uses its supported Linux
router mode (`auto-route` plus `auto-redirect`) and limits interception to `wg0` with
`include-interface`. It therefore does not need a custom nftables script or routing
sidecar.

wg-easy UI 與 Mihomo API 只監聽 axolotl loopback。從另一台內網電腦管理時使用：

```bash
ssh -L 51821:127.0.0.1:51821 -L 19090:127.0.0.1:19090 user@192.168.10.13
```

- wg-easy: `http://127.0.0.1:51821`
- Mihomo API: `http://127.0.0.1:19090`

## Host requirements

The host needs WireGuard kernel support, `/dev/net/tun`, nftables, and the netfilter
features used by Mihomo TUN. The stack grants `NET_ADMIN` to both containers and
`SYS_MODULE` to wg-easy. `/lib/modules` is mounted read-only for hosts that need the
WireGuard module loaded at runtime.

## Verification

After connecting a WireGuard client, verify that the public address is the selected
subscription exit rather than the VPS address:

```bash
curl -4 https://api.ipify.org
```

Inspect the shared network namespace and Mihomo logs:

```bash
docker exec clashrs-wg ip link show wg0
docker exec clashrs-wg-mihomo ip rule
docker logs --tail=100 clashrs-wg-mihomo
```

Also test UDP or HTTP/3 from the client. Mihomo can intercept UDP, but the selected
subscription node must support UDP relay.

## Upstream

- [wg-easy](https://github.com/wg-easy/wg-easy)
- [Mihomo](https://github.com/MetaCubeX/mihomo)
- [Mihomo TUN configuration](https://wiki.metacubex.one/en/config/inbound/tun/)

Both images are pinned by version and immutable multi-architecture manifest digest.
