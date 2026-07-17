# 可行性評估

評估日期：2026-07-17 至 2026-07-18（Asia/Taipei）

結論：**可行，但屬於受控遷移，不是原地無中斷升級。** 本目錄因此採獨立部署，
沒有修改舊 `Gluetun/docker-compose.yml`，也不能在舊 stack 還佔用相同容器名/ports 時並行啟動。

## 證據與判定

| 檢查項目 | 現況證據 | 判定 |
| --- | --- | --- |
| DDNS adapter | 官方 `DF-wu/ddns-openvpn-proxy` main 為 `ca5200d28ac992c8c71200fe49c7d24f850133b3`；production Compose 核心來自其父系 `8e2523978acb19e3f8aec7485db6de932918b76b` | 可用；採經完整測試的純 Compose 核心，不用 moving tag |
| 日本 profile | `/mnt/appdata/gluetun/surfshark-ovpn/jp-tok.prod.surfshark.com_udp.ovpn` 只有一個 `remote jp-tok.prod.surfshark.com 1194` | 符合 single-remote DDNS 契約 |
| 羅馬尼亞 profile | `ro-buc.prod.surfshark.com_udp.ovpn` 只有一個 `remote ro-buc.prod.surfshark.com 1194` | 符合 |
| 英國 profile | `uk-lon.prod.surfshark.com_udp.ovpn` 只有一個 `remote uk-lon.prod.surfshark.com 1194` | 符合；同時修正舊 compose 將 UK path 指到 RO 的潛在錯誤 |
| 認證 | 三份 profile 都含 `auth-user-pass` | `.env.common` 必須同時提供 `OPENVPN_USER/PASSWORD`；空值會 fail closed |
| 容器名相容 | 既有名稱為 `gluetun-jp`、`gluetun-romania`、`gluetun-uk` | 新設定原樣保留 |
| Port 相容 | HTTP 為 19010/19015/19020；Shadowsocks 為 JP 19011、RO 19016 TCP + 19017 UDP、UK 19021 | 全數保留；SOCKS5 另用 19110/19115/19120，不偷換舊協定 |
| 直接 consumer | runtime 確認 `oci-bot-client` 正在使用 `container:gluetun-jp`；workspace 另有 `codex-runner` 設定使用 `container:gluetun-uk` | watcher 加入「只重啟原本 running 的單一精確 consumer」協調；首次 cutover 仍需維護窗口重新附掛 |
| 資料隔離 | 舊三區共寫 `/mnt/appdata/gluetun`；DDNS runtime profile 不可共用 | 舊 profile 只讀；三個 Compose project 各有自己的 `vpn-state` volume |

## 上游兩種模式的選擇

官方 main 在 `ca5200d` 新增 compatibility watcher image，但它不是 VPN/proxy 本身，只是
對既有容器執行 render/inspect/restart 的控制器。本次不採該 image，原因如下：

- 只有 `linux/amd64`，沒有 tag/release/semver；`latest` 不適合 production pin。
- image workflow 明確關閉 provenance/SBOM，OCI revision label 也落後實際 commit。
- compat watcher 只追 IP、不追 profile/憑證 fingerprint，首次無 state 時必定 restart，
  並假設 vproxy 一定存在。
- 它不能把目前 Surfshark built-in WireGuard country selection 自動變成三份 custom profile，
  也沒有處理額外 `network_mode:container` consumers。

因此採官方同一 repo 的 production **純 Compose** 核心：不 build/拉自有 watcher image，
使用固定、multi-arch 上游 images，並只在部署副本加上已知 consumer 與 legacy Shadowsocks gate。

## 主要取捨

1. 舊 stack 實際使用 Surfshark built-in **WireGuard country selection**；現有資料沒有可供
   DDNS renderer 使用的三份完整 WireGuard single-peer profile。因此本次使用已存在且契約
   驗證通過的 **OpenVPN profiles**。出口地區保留，但 transport/效能可能不同。
2. `network_mode: container:<name>` consumer 不會因名稱相同就自動換到 Gluetun restart 後的
   新 network namespace。部署內 watcher 會精確 inspect/restart 已知 consumer；實際替換舊
   container 的首次切換仍需先停 consumer、換 Gluetun、再重新建立/啟動 consumer。
3. 原 stack 雖發布 HTTP/Shadowsocks ports，卻未明確啟用 listener。本部署明確啟用兩者並
   保留 ports；由於沿用 `0.0.0.0`，所有 proxy credentials 都是啟動 gate 的必填值。
4. 新舊部署共享容器名與 host ports，技術上不可能零停機並行。檔案可以安全預先建立與
   render；真正 cutover 必須另排維護窗口。

## 未在本次靜態階段聲稱完成的 runtime 驗收

- 真實 Surfshark 認證、cipher negotiation 與 VPN 出口地區。
- HTTP、SOCKS5、Shadowsocks data path 與 authentication。
- 真實 DDNS IP 變更時的短暫中斷時間與 consumer reattach。
- 未納入版本庫或當時未存在於 Docker runtime 的其他 external consumers。

上述項目需要啟動/重啟容器；依需求本次沒有執行，步驟留在 `MIGRATION.md`。
