# clashrs-wg

WireGuard clients connect through wg-easy and leave through a Mihomo subscription.
The stack uses the official wg-easy and Mihomo images; it contains no local image build,
custom routing script, or third-party all-in-one image.

## Portainer

- Stack name: `clashrs-wg`
- Compose path: `clashrs-wg/docker-compose.yml`
- Endpoint: Docker Standalone, not Swarm
- Compose engine: 2.23.1 or newer (`configs.content` is required)

Required environment variables:

| Variable | Value |
|---|---|
| `WG_HOST` | Public IP or hostname clients connect to |
| `WG_ADMIN_PASSWORD` | Initial wg-easy administrator password |
| `CLASH_SUBSCRIPTION_URL` | Clash/Mihomo subscription URL |
| `CLASH_NODE_FILTER` | Unique node name or regex selecting the subscription server |

Optional variables: `WG_ADMIN_USERNAME`, `WG_PORT`, `WG_UI_PORT`,
`MIHOMO_API_PORT`, `MIHOMO_SECRET`, and `TZ`.

`WG_HOST` is the public address of the VPS running this stack, not an address from
the subscription. For example, if the VPS public IP is `203.0.113.10`, set:

```text
WG_HOST=203.0.113.10
```

To use one particular subscription node, set `CLASH_NODE_FILTER` to a unique part of
its full name. For a node named `Japan Tokyo 01`:

```text
CLASH_NODE_FILTER=Japan Tokyo 01
```

The filter is case-sensitive and accepts regular-expression syntax. It should match
only one node; otherwise Mihomo initially selects the first matching node.

The administrator password is used only by wg-easy's first-start initialization.
After setup, remove `WG_ADMIN_PASSWORD` from the Portainer environment and redeploy.

## Traffic path

```text
WireGuard client -> wg-easy wg0 -> Mihomo TUN -> subscription proxy -> Internet
```

Both containers share wg-easy's network namespace. Mihomo uses its supported Linux
router mode (`auto-route` plus `auto-redirect`) and limits interception to `wg0` with
`include-interface`. It therefore does not need a custom nftables script or routing
sidecar.

The wg-easy UI and Mihomo API listen only on host loopback. Access them remotely with:

```bash
ssh -L 51821:127.0.0.1:51821 -L 9090:127.0.0.1:9090 user@server
```

- wg-easy: `http://127.0.0.1:51821`
- Mihomo API: `http://127.0.0.1:9090`

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
