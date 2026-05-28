# Gluetun Proxy Farm

透過 [Gluetun](https://github.com/qdm12/gluetun) 將 Surfshark VPN 的多國連線以 **HTTP Proxy**、**SOCKS5**、**Shadowsocks** 方式共享出來。

## 架構概述

- 每個國家/地區運行獨立的 Gluetun 容器
- 每個容器透過 **WireGuard** 連線至 Surfshark 的對應地區伺服器
- 容器內建 HTTP Proxy (`:8888`)、SOCKS5 (`:1080`)、Shadowsocks (`:8388`)
- 透過 Docker port mapping 將各服務映射到宿主機的不同端口

## 快速開始

### 1. 準備環境變數

```bash
cp .env.example .env
```

編輯 `.env`，填入以下資訊：

| 變數 | 說明 | 取得方式 |
|------|------|----------|
| `WIREGUARD_PRIVATE_KEY` | WireGuard 私鑰 | Surfshark 帳號 → VPN → Manual Setup → WireGuard → Generate keypair |
| `WIREGUARD_ADDRESSES` | WireGuard 介面位址 | 通常為 `10.14.0.2/16`，請以 Surfshark 設定為準 |
| `SHADOWSOCKS_PASSWORD` | Shadowsocks 密碼 | 所有節點共用同一個密碼 |
| `SHADOWSOCKS_CIPHER` | Shadowsocks 加密方式 | 預設 `aes-256-gcm` |
| `TZ` | 時區 | 預設 `Asia/Taipei` |
| `LAN_SUBNET` | 區網子網路 | 讓區網裝置可連 proxy，例：`192.168.1.0/24` |

### 2. 啟動服務

```bash
cd gluetun-proxys
docker compose up -d
```

### 3. 檢查狀態

```bash
# 查看所有容器狀態
docker compose ps

# 查看日本節點日誌
docker logs -f gluetun-japan

# 確認 VPN 連線成功（應顯示日本 IP）
curl --proxy http://localhost:19200 https://ipinfo.io/json
```

## 端口對照表

| 地區 | HTTP Proxy | Shadowsocks | SOCKS5 |
|------|-----------|-------------|--------|
| 🇯🇵 日本 | `19200` | `19201` | `19202` |
| 🇺🇸 美國 | `19210` | `19211` | `19212` |
| 🇭🇰 香港 | `19220` | `19221` | `19222` |
| 🇰🇷 韓國 | `19230` | `19231` | `19232` |
| 🇸🇬 新加坡 | `19240` | `19241` | `19242` |
| 🇲🇴 澳門 | `19250` | `19251` | `19252` |
| 🇬🇧 倫敦 | `19260` | `19261` | `19262` |

## 使用方式

### curl

```bash
# 日本 IP
curl --proxy http://localhost:19200 https://ipinfo.io/json

# 美國 IP
curl --proxy http://localhost:19210 https://ipinfo.io/json

# SOCKS5
curl --socks5 localhost:19202 https://ipinfo.io/json
```

### Python requests

```python
import requests

proxies = {
    'http': 'http://localhost:19200',   # 日本
    'https': 'http://localhost:19200',
}
response = requests.get('https://api.ipify.org', proxies=proxies)
print(response.text)
```

### 瀏覽器手動代理

設定 HTTP Proxy 為 `192.168.1.100:19200`（請替換為你的伺服器 IP）

## 資源使用

| 指標 | 預設值 | 優化後（本設定） |
|------|--------|-----------------|
| 每容器記憶體 | ~400 MB | ~55 MB |
| 7 容器總記憶體 | ~2.8 GB | ~385 MB |
| CPU（閒置） | - | < 1% per instance |

優化方式：關閉 `BLOCK_MALICIOUS`、`BLOCK_SURVEILLANCE`、`BLOCK_ADS`、`DOT`

## 已知問題與注意事項

1. **韓國名稱**：若 `SERVER_COUNTRIES=South Korea` 無法連線，請嘗試 `Korea Republic of`
2. **澳門名稱**：`SERVER_COUNTRIES=Macau`（Surfshark 官方名稱為 Macau SAR China）
3. **區網存取**：`FIREWALL_OUTBOUND_SUBNETS` 必須設定正確，否則區網裝置無法連 proxy
4. **Volume 衝突**：每個容器使用獨立的 volume 路徑，請勿與其他 Gluetun 實例共用

## 參考資料

- [Gluetun 官方文件](https://github.com/qdm12/gluetun-wiki)
- [Gluetun Surfshark 設定](https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/surfshark.md)
- [多實例運行指南](https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/multiple-gluetun.md)
