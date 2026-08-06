# OCI Bot Client

Docker 部署的 [Radiance OCI Bot](https://github.com/semicons/java_oci_manage) 客戶端，用於透過 Telegram Bot 管理 Oracle Cloud Infrastructure 資源。

## 架構

```
oci-bot-client (Docker Container)
├── r_client (GraalVM native-image, Java, baked into image)
│   ├── Tomcat embedded (port 9527)
│   ├── Telegram Bot API
│   ├── OCI SDK (Singapore region)
│   └── 支援: Azure / SolusVM / SSH / Cloudflare
└── 掛載點
    ├── ./config/client_config:/app/client_config:ro
    └── ./keys/:/app/keys:ro
```

## 需求

- Docker + Docker Compose
- OCI API 金鑰（`.pem` 格式）
- 有效的 Telegram bot 憑證

## 快速開始

### 1. 設定

```bash
cp config/client_config.example config/client_config
```

編輯 `config/client_config`，填入你的 OCI API 資訊和 bot 憑證。

### 2. 金鑰

將 OCI API 私鑰放入 `keys/` 目錄。例如：
```
keys/my-key.pem
keys/my-key.pub.pem
```

### 3. 啟動

```bash
docker compose up -d --build
```

Dockerfile 會在 build 時下載固定版本的 `r_client` binary，並驗證官方 release asset 的 SHA-256；容器內直接執行，無需每次啟動重複安裝。

### 4. 更新

```bash
docker compose up -d --build --no-cache
```

## 設定

| 欄位 | 說明 |
|------|------|
| `oci=begin` ... `oci=end` | OCI API 設定（user, fingerprint, tenancy, region, key_file） |
| `username` | Telegram bot 使用者名稱（從 [@radiance_helper_bot](https://t.me/radiance_helper_bot) 取得） |
| `password` | Telegram bot 密碼 |
| `model` | 啟動模式：Docker 環境建議 `local`（無公網 IP 模式） |

## 安全

- `config/client_config` 包含機敏資訊，已加入 `.gitignore`，不會被 commit
- 範本：`config/client_config.example`（可安全 commit）
- `keys/` 目錄同樣已被 `.gitignore` 排除
- config 和 keys 在容器內以唯讀（`:ro`）掛載

## 監控

```bash
docker compose logs -f              # 容器日誌
docker compose exec oci-bot-client cat /app/log_r_client.log  # 應用日誌
docker compose restart              # 重啟
```

## 上游

- [semicons/java_oci_manage](https://github.com/semicons/java_oci_manage) — 本專案使用的客戶端程式來源
- 客戶端版本：`v10.2.1`（在 Dockerfile 中固定版本與 checksum）
