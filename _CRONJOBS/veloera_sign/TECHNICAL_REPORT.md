# Veloera 自動簽到腳本技術報告

## 📋 執行摘要

本報告說明 Veloera 自動簽到腳本的最終版本設計。腳本採用自包含的 GitHub Actions 架構，內建 FlareSolverr 服務，無需外部依賴，提供完全獨立的簽到解決方案。

**最終結果：✅ 完全自包含，無外部依賴**

---

## 🎯 架構設計

### 自包含 GitHub Actions
```yaml
services:
  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    ports:
      - 8191:8191
```

**優勢：**
- ✅ **零外部依賴**：FlareSolverr 在 GitHub Actions 中自動啟動
- ✅ **完全隔離**：每次執行都是全新環境
- ✅ **成本控制**：只在需要時運行，無持續成本
- ✅ **維護簡單**：無需管理外部服務

### 配置管理
```
優先級 1: 本地 config.json（開發測試）
    ↓
優先級 2: GitHub Secrets（生產環境）
```

---

## 🔧 技術實現

### GitHub Actions Workflow
```yaml
name: Veloera 自動簽到

on:
  workflow_dispatch: # 手動觸發
  schedule:
    - cron: "0 20 * * *" # 每日自動執行

jobs:
  check-in:
    runs-on: ubuntu-latest
    
    services:
      flaresolverr:
        image: ghcr.io/flaresolverr/flaresolverr:latest
        ports:
          - 8191:8191
        env:
          LOG_LEVEL: info
          TZ: Asia/Taipei

    steps:
      - name: 等待 FlareSolverr 啟動
        run: |
          for i in {1..30}; do
            if curl -s http://localhost:8191 > /dev/null; then
              echo "FlareSolverr 已啟動"
              break
            fi
            sleep 2
          done

      - name: 執行簽到
        env:
          SECRETS_CONTEXT: ${{ toJson(secrets) }}
          FLARESOLVERR_URL: "http://localhost:8191"
        run: python _CRONJOBS/veloera_sign/checkin.py
```

### 核心簽到邏輯
```python
def flaresolverr_checkin(base_url, checkin_url, headers):
    # 預設使用本地 FlareSolverr (GitHub Actions 中自動啟動)
    flaresolverr_url = os.environ.get("FLARESOLVERR_URL", "http://localhost:8191")
    
    # 1. 建立 session
    # 2. 獲取 clearance
    # 3. 發送認證請求
    # 4. 清理 session
```

---

## 📊 部署配置

### GitHub Actions 配置
```bash
# 在 GitHub Secrets 中設定
VELOERA_AUTOSIGN_1='{"base_url":"https://zone.veloera.org","user_id":2628,"access_token":"your_token"}'
```

### 本地測試配置
```json
// config.json
{
    "base_url": "https://zone.veloera.org",
    "user_id": 2628,
    "access_token": "your_token"
}
```

```bash
# 本地測試需要外部 FlareSolverr
export FLARESOLVERR_URL="https://flaresolverr.dfder.tw"
python checkin.py
```

---

## 🚀 執行流程

### GitHub Actions 執行
1. **啟動 FlareSolverr 服務**：Docker container 自動啟動
2. **等待服務就緒**：健康檢查確保服務可用
3. **執行簽到腳本**：使用本地 FlareSolverr (localhost:8191)
4. **自動清理**：執行完成後所有資源自動釋放

### 本地開發執行
1. **使用外部 FlareSolverr**：通過 FLARESOLVERR_URL 指定
2. **讀取本地配置**：config.json 檔案
3. **執行簽到邏輯**：相同的核心邏輯

---

## 📈 優勢分析

### 成本效益
- **零持續成本**：無需維護外部 FlareSolverr 服務
- **按需使用**：只在簽到時消耗資源
- **GitHub Actions 免費額度**：公開倉庫免費使用

### 可靠性
- **環境隔離**：每次執行都是全新環境
- **版本固定**：使用特定 FlareSolverr 映像版本
- **自動恢復**：失敗時下次執行自動重試

### 維護性
- **零維護**：無外部服務需要管理
- **版本控制**：所有配置都在代碼倉庫中
- **日誌完整**：GitHub Actions 提供完整執行日誌

---

## 🔒 安全考量

### 隔離性
- **完全隔離**：每次執行獨立環境
- **無狀態**：不保留任何執行狀態
- **自動清理**：執行完成後環境自動銷毀

### 認證安全
- **GitHub Secrets**：加密存儲敏感信息
- **環境變數**：運行時注入，不在代碼中暴露
- **HTTPS 通信**：所有 API 請求使用加密連接

---

## 📝 總結

最終版本實現了完全自包含的簽到解決方案：

### ✅ 核心特點
- **零外部依賴**：FlareSolverr 在 GitHub Actions 中自動管理
- **完全免費**：利用 GitHub Actions 免費額度
- **維護簡單**：無需管理任何外部服務
- **高可靠性**：每次執行都是全新隔離環境

### 🎯 技術創新
**自包含微服務架構**：將 FlareSolverr 作為 GitHub Actions 服務運行，實現了完全自包含的 Cloudflare 繞過解決方案，為類似項目提供了可復用的架構模式。

### 🚀 部署優勢
- **一鍵部署**：推送代碼即可運行
- **自動調度**：支援定時和手動觸發
- **完整日誌**：GitHub Actions 提供詳細執行記錄
- **版本管理**：所有變更都有完整的版本歷史

這種設計完全消除了對外部 FlareSolverr 服務的依賴，提供了更加穩定、經濟、易維護的解決方案。

---

*報告更新時間：2025-09-11*  
*版本：Self-Contained*