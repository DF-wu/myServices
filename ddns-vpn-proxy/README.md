# DDNS VPN Proxy

這是給 Portainer Repository Stack 使用的三區 Gluetun 模板。日本、羅馬尼亞、英國各自
建立一個 Stack，共用同一份 `docker-compose.yml`，但使用不同的 env、container 名稱、
ports 與 state volume。

DDNS hostname 變更時，`ddns-watcher` 只會透過 Gluetun 的受限 control API 重載 VPN，
不會掛 Docker socket，也不會重建 Gluetun 或外部 consumer。DNS 初始化、profile hash、
credentials 或 control role 不符合預期時會直接失敗。

## Portainer 設定

| 欄位 | 值 |
| --- | --- |
| Repository URL | `https://github.com/DF-wu/myServices.git` |
| Repository reference | `refs/heads/master` |
| Compose path | `ddns-vpn-proxy/docker-compose.yml` |
| Auto update / webhook | disabled |
| Relative path volumes | disabled |

三區 Stack Name 與 env 必須一一對應：

| 地區 | Stack Name | env 範例 | HTTP | Shadowsocks TCP/UDP | SOCKS5 |
| --- | --- | --- | ---: | ---: | ---: |
| 日本 | `ddns-vpn-proxy-jp` | `portainer/jp.env.example` | 19010 | 19011 / 19011 | 19110 |
| 羅馬尼亞 | `ddns-vpn-proxy-romania` | `portainer/romania.env.example` | 19015 | 19016 / 19017 | 19115 |
| 英國 | `ddns-vpn-proxy-uk` | `portainer/uk.env.example` | 19020 | 19021 / 19021 | 19120 |

所有 proxy port 固定綁在 host `127.0.0.1`。不要把 `PROXY_BIND_ADDRESS` 改成
`0.0.0.0`；跨主機使用請走受控 tunnel。

Portainer 拉取 repo 後會從 `docker/gluetun.Dockerfile` 與
`docker/gost.Dockerfile` 建置兩個本機 image。來源 revision、archive checksum、builder、
runtime base 與 Go module checksums 都已固定，不需要 GHCR package 或 registry credential。
目前已在此 Portainer host 的 `linux/amd64` Docker Engine 驗證。

## Host 準備

Repository Stack 仍需要 host 上的 Surfshark profiles 與 credentials；秘密不會放進 Git
或 Portainer environment。

預設 profile 來源：

```text
/mnt/appdata/gluetun/surfshark-ovpn
```

先建立以下每區五個檔案，每個檔案只能有一行值，mode 必須是 `0600` 或 `0400`：

```text
/home/df/.config/ddns-vpn-proxy/credentials/{jp,romania,uk}/openvpn-user
/home/df/.config/ddns-vpn-proxy/credentials/{jp,romania,uk}/openvpn-password
/home/df/.config/ddns-vpn-proxy/credentials/{jp,romania,uk}/httpproxy-user
/home/df/.config/ddns-vpn-proxy/credentials/{jp,romania,uk}/httpproxy-password
/home/df/.config/ddns-vpn-proxy/credentials/{jp,romania,uk}/shadowsocks-password
```

從已 checkout 的 `master` 執行：

```bash
cd ddns-vpn-proxy
sh scripts/install-portainer-assets.sh
install -d -m 0700 /home/df/.local/share/ddns-vpn-proxy/portainer-env
install -m 0600 portainer/jp.env.example \
  /home/df/.local/share/ddns-vpn-proxy/portainer-env/jp.env
install -m 0600 portainer/romania.env.example \
  /home/df/.local/share/ddns-vpn-proxy/portainer-env/romania.env
install -m 0600 portainer/uk.env.example \
  /home/df/.local/share/ddns-vpn-proxy/portainer-env/uk.env
```

Installer 會建立 hash 驗證過的 helper/profile、每區獨立 control key、status-only role、
deny-default role、private credential copies 與 fail-closed resolver。既有版本若遭修改，
installer 會拒絕覆寫。

## 部署前驗證

```bash
sh scripts/validate-static.sh
sh scripts/validate-portainer-env.sh jp ddns-vpn-proxy-jp \
  /home/df/.local/share/ddns-vpn-proxy/portainer-env/jp.env
sh scripts/validate-portainer-env.sh romania ddns-vpn-proxy-romania \
  /home/df/.local/share/ddns-vpn-proxy/portainer-env/romania.env
sh scripts/validate-portainer-env.sh uk ddns-vpn-proxy-uk \
  /home/df/.local/share/ddns-vpn-proxy/portainer-env/uk.env
```

`validate-static.sh` 只檢查檔案、Compose model 與測試，不會啟停任何 container。

## 切換注意

新 Stack 沿用 `gluetun-jp`、`gluetun-romania`、`gluetun-uk` 與既有 host ports，
因此舊 Gluetun 還在執行時不能直接按 Deploy。請依 [`MIGRATION.md`](MIGRATION.md)
在維護窗口一次切一區，保留舊 container 作回滾點。

Portainer 顯示部署完成後，仍要確認：

- `ddns-init` 是 exited (0)。
- `gluetun`、`vproxy`、`ddns-watcher` 都是 healthy。
- 8000 control port 與 9999 health port沒有發布到 host。
- HTTP、Shadowsocks、SOCKS5 的出口 IP 與地區正確。
- 外部 `network_mode: container:<gluetun-name>` consumer 已 force recreate 到新的
  Gluetun container ID。

本次 repo 準備不會部署 Stack，也不會停止、重啟或重建現行服務。

## 主要檔案

```text
docker-compose.yml
portainer/{jp,romania,uk}.env.example
docker/gluetun.Dockerfile
docker/gost.Dockerfile
scripts/ddns-openvpn.sh
scripts/install-portainer-assets.sh
scripts/validate-portainer-env.sh
scripts/validate-static.sh
security/*.openvex.json
tests/*.sh
```
