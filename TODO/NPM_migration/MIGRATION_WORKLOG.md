# NPM 遷移工作日誌 (jlesage → 官方 jc21)

> 日期：2026-07-01 / 2026-07-02（TrueNAS 時區）。執行者：Claude Code（唯讀驗證 + staging，未切換流量）。
> 原則：舊 NPM 全程未動；新 NPM app 未被啟動/改設定；TrueNAS SSH 僅唯讀 + sudo 唯讀檢查。
> 註：TrueNAS 密碼由使用者當面提供，未記錄於此檔。

## 1. 環境拓撲（實測）

| 角色 | 主機 | 說明 |
|---|---|---|
| Docker 主機 | `axolotl` = **192.168.10.13** | 跑 ~40 個 compose 服務；`axolotl.newhome` 即此機 |
| TrueNAS (NFS server) | `truenas` = **192.168.10.12** | app 都跑在這；`/mnt/appdata`(於.13) = NFS 掛載其 `/mnt/cachePool/appdata` |

NFS：`192.168.10.12:/mnt/cachePool/appdata` → `.13:/mnt/appdata`（.13 上以 uid1000 df 寫入，落到 TrueNAS 上 owner=`df`(uid3000)）。

### 兩個 NPM（都是 TrueNAS app）
- **舊（線上服務中）**：`ix-df-nginx-proxy-manager-df-nginx-proxy-manager-1`，image `jlesage/nginx-proxy-manager:latest`（後端 NPM 2.14.0）。
  - 對外埠 **7818→8181(admin) / 18080→8080 / 18443→4443**。
  - 資料：`/mnt/cachePool/appdata/NginxProxyManager`（owner `axolotl`）。**未開 stream 51443。**
- **新（遷移目標，全新未設定）**：TrueNAS 市場部署的官方 `jc21/nginx-proxy-manager:**2.15.1**`，容器 `ix-nginx-proxy-manager-npm-1`。
  - 對外埠 **30020→81(admin) / 30021→80 / 30022→443**。API `setup:false`（尚無管理員）。
  - 目前資料：`/mnt/.ix-apps/app_mounts/nginx-proxy-manager/{data,certs}`（ix-apps 預設，全新空機）。
  - 容器以 **root** 執行；init `10-usergroup.sh` 開機會 `chown -R $PUID:$PGID $NPMHOME`（此 app PUID/PGID=568）。

## 2. 已完成：staged 遷移資料

位置（TrueNAS 本地）：`/mnt/cachePool/appdata/NginxProxyManager_official/`
（= .13 的 `/mnt/appdata/NginxProxyManager_official/`）

```
NginxProxyManager_official/
├── data/            → 掛給新容器 /data
│   ├── database.sqlite  (600, df)
│   ├── keys.json        (600, df)
│   ├── access/          (含 htpasswd「2」)
│   ├── custom_ssl/
│   ├── logs/
│   └── nginx/           (消毒後的 proxy_host/redirection_host/dead_host/stream/… conf)
└── letsencrypt/     → 掛給新容器 /etc/letsencrypt
```

### 使用的腳本與修改
`scripts/migrate_to_official_npm.sh --execute`（只寫 `_official` 與 `_migration`，不碰來源）。本次為配合環境所做修改：
1. **DB 一致快照**：`copy_core_assets` 由 `cp -a` 改為 `sqlite3 -readonly … ".backup"`（來源只讀、避免熱拷貝撕裂）。
2. **NFS 相容**：所有 `rsync -a`→`rsync -a --no-owner --no-group`、`cp -a`→`cp -d --preserve=mode,timestamps`（NFS 不允許 chgrp 到來源 gid，且新容器開機會自行 chown，故無需保留擁有者）。
3. `OFFICIAL_IMAGE` 維持 `2.15.1`（＝實際新 app 版本；產出的 compose 檔僅為附帶物，TrueNAS app 才是實際 runtime）。

### 內容修正（唯二的資料變更）
新 NPM 在 TrueNAS，解不到 .13 的 docker 容器名，故把兩個「容器名/內部名」後端改為 LAN IP（DB + 對應 conf 同步改）：

| id | 域名 | 原 forward_host | 改為 | 埠 |
|---|---|---|---|---|
| 19 | ani.dfder.tw | `AutoBangumi` | `192.168.10.13` | 7892 |
| 42 | api-conversion.dfder.tw | `axolotl.newhome` | `192.168.10.13` | 43061 |

（兩個後端服務都在 .13、以 host 埠對外，故走 IP 直達最穩，不依賴容器 DNS / `.newhome` 解析。）

## 3. 正確性驗證結果（全數通過）

- **DB `.dump` 全量比對（來源 vs staged）**：全檔僅 **2 行**不同 = 上表 id 19、42 的 forward_host。其餘 100% 位元組相同。
- **逐表 row count**：13 張表全部一致（proxy_host 46 / redirection 2 / dead 2 / stream 3 / access_list 2 / access_list_auth 2 / access_list_client 1 / certificate 3 / user 1 / user_permission 1 / auth 1 / setting 1 / audit_log 312）。`PRAGMA integrity_check = ok`。
- **keys.json**：md5 一致（`9cae1491…`）→ JWT 簽章鑰匙保留，管理員帳密與既有 token 延續。
- **access/2**：md5 一致（`eea923e6…`）→ teslamate basic auth 保留。
- **letsencrypt**：archive 8 個 .pem、renewal 2 個 .conf、credentials 1 個；萬用憑證 `npm-1/fullchain.pem` md5 一致（`6f23e0a7…`）；live symlink 皆可解。憑證續期路徑皆為 `/etc/letsencrypt/*`（跨映像通用），`dns_cloudflare_credentials=/etc/letsencrypt/credentials/credentials-1` 已帶入。
- **conf 消毒 gate**：無 `/config`、無 `listen 8080/4443`；listen 埠只剩 80/443/51443；日誌路徑改為 `/data/logs`；IPv6 `[::]` 行全為註解（與 app `DISABLE_IPV6` 一致）。
- **權限風險已排除**：新 NPM 2.15.1 開機 `chown -R $PUID:$PGID /data`，會把 staged 的 df/600 檔自動轉成 app 使用者 → 可讀寫。
- **快照純淨**：無任何執行中容器掛載 staged 目錄，DB 仍為 01:28 原始快照。

## 4. 尚未做（保留給使用者手動切換）

新 app 目前仍用 ix-apps 空機資料，**尚未**指向 staged 資料。切換時：

1. TrueNAS UI **停**官方 NPM app（`ix-nginx-proxy-manager-npm-1`）。
2. 改其 storage（host path）：
   - `/data` → `/mnt/cachePool/appdata/NginxProxyManager_official/data`
   - `/etc/letsencrypt` → `/mnt/cachePool/appdata/NginxProxyManager_official/letsencrypt`
   - 保留 `DISABLE_IPV6=true`、`TZ=Asia/Taipei`。
3. **啟動** → 觀察 log：會跑 2.11→2.15.1 的 knex migration（確認無 error）＋ chown data。
4. 驗證（此時新 app 仍在 30020/30021/30022，未接正式流量）：
   - 容器內 `nginx -t` 過；`http://192.168.10.12:30020` 用**舊 NPM 的管理員帳密**登入。
   - UI 數量：39 proxy / 2 redirection / 1 dead / 1 stream（enabled）。
   - 抽測路由（含改過的兩台）：
     `curl -k --resolve ani.dfder.tw:30022:192.168.10.12 https://ani.dfder.tw/`
     `curl -k --resolve api-conversion.dfder.tw:30022:192.168.10.12 https://api-conversion.dfder.tw/`
   - teslamate.dfder.tw basic auth；`*.dfder.tw` 萬用憑證載入。
5. **切流量**：把目前指向舊 jlesage（18080/18443）的來源（路由器 port-forward / 上游），改指向新 app（30021/30022）。舊 app 先留著＝即時回滾。
6. **回滾**：來源指回舊 app（18080/18443）即可；staged 樹與舊資料互不干擾。

### 注意事項
- **Stream 51443**：新舊 app 目前都沒開這埠（舊的本來就沒開 → 非回歸）。若要用，需在新 app port 設定加 `51443 tcp+udp`。
- **切換前若動過舊後台**：staged 是 01:28 的快照；若切換前你在舊 NPM 改了設定，切換前請重跑一次 staging（`ALLOW_OVERWRITE_TARGET=1 bash scripts/migrate_to_official_npm.sh --execute` + 重做 id19/42 IP 改寫）以取得最新資料。
- **最終路徑對齊**：容器內永遠是 `/data`，之後要讓新 app 落到與舊相同的資料夾名，只需停 app→改 host-path→起 app，對容器透明。
