# clashrs-wg

單一容器的 WireGuard 至 Clash/Mihomo 出口閘道。映像整合 wg-easy、Mihomo、
MetaCubeXD、TUN policy routing 與規則復原 daemon；repository 只保留一份 Compose。

## Portainer

- Stack name: `clashrs-wg`
- Compose path: `clashrs-wg/docker-compose.yml`
- Environment: `WG_HOST`, `WG_EASY_INIT_PASSWORD`, `CLASH_SUBSCRIPTION_URL`
- Optional: `MIHOMO_SECRET`, `TZ`
- Endpoint: Docker Standalone；不可使用 Swarm
- Compose engine: 2.23.1+（需要 `configs.content`）

映像使用 host network。WireGuard 監聽 `51820/udp`；wg-easy 與 MetaCubeXD
分別只綁定 host loopback 的 `51821`、`51888`，從遠端管理時使用 SSH tunnel：

```bash
ssh -L 51821:127.0.0.1:51821 -L 51888:127.0.0.1:51888 user@server
```

然後開啟：

- wg-easy: `http://127.0.0.1:51821`
- MetaCubeXD: `http://127.0.0.1:51888/ui/`

主機需提供 WireGuard kernel support 與 `/dev/net/tun`。容器具有 `NET_ADMIN`、
`SYS_MODULE` 並使用 host network，因此必須視為具主機網路管理權限的受信任元件。

## 驗證

WireGuard client 連線後確認出口不是 VPS IP：

```bash
curl -4 https://api.ipify.org
```

檢查容器與內部服務：

```bash
docker inspect --format '{{.State.Health.Status}}' clashrs-wg
docker exec clashrs-wg supervisorctl status
docker exec clashrs-wg ip rule show
docker exec clashrs-wg ip route show table 666
```

## 來源與版本

- Integration: [sers88/wg-gateway](https://github.com/sers88/wg-gateway)
- Image: `ksantd/wg-gateway:26.08.08.07.41`
- OCI digest: `sha256:514338227f2d8ac6a9ffd2776d44e63c3025cac835445c6c6c4149c3b7d41774`
- Source revision embedded in image: `8bff3ba86f8cc2b31a499c933d887e7f79de41f4`

此整合專案建立於 2026-04，主要由單一維護者開發。映像已鎖定 immutable digest；
升級前應重新檢查 Dockerfile、routing scripts、CI 結果與 image revision。
