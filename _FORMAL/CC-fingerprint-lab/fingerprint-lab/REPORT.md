# Claude Code / CRS / sub2api — OAuth Fingerprint 完整分析報告

> **日期**: 2026-03-29
> **分析對象**:
> - Claude Code v2.1.81 (SEA binary, Node.js v24.3.0, axios 1.13.6)
> - claude-relay-service (CRS) — latest commit `fdd8499f`
> - sub2api v0.1.105 — latest commit `fdd8499f`
>
> **方法論**: 二進制逆向工程 + 原始碼審計 + 實際抓包驗證

---

## 目錄

1. [三者角色與架構](#1-三者角色與架構)
2. [OAuth 完整流程與各階段 UA](#2-oauth-完整流程與各階段-ua)
3. [Token 操作 User-Agent 實測驗證](#3-token-操作-user-agent-實測驗證)
4. [API 請求層 HTTP 指紋](#4-api-請求層-http-指紋)
5. [metadata.user_id 身份指紋](#5-metadatauserid-身份指紋)
6. [TLS 指紋](#6-tls-指紋)
7. [版本一致性交叉驗證表](#7-版本一致性交叉驗證表)
8. [偵測策略與風險評估](#8-偵測策略與風險評估)
9. [各系統弱點總覽](#9-各系統弱點總覽)
10. [附錄：關鍵原始碼證據](#10-附錄關鍵原始碼證據)

---

## 1. 三者角色與架構

| 系統 | 角色 | 語言 | 運行環境 |
|------|------|------|----------|
| **Claude Code** | Anthropic 官方 CLI | TypeScript → SEA binary | Node.js v24.3.0 (bundled) |
| **CRS** | 多帳號中繼代理 | Node.js | Node.js (原生) |
| **sub2api** | 訂閱轉 API 閘道 | Go | Go runtime + uTLS |

### 請求流程

```
使用者 (Claude Code / curl / OpenAI SDK)
  → [CRS/sub2api proxy]
    → api.anthropic.com (API 請求，帶 OAuth access_token)
    → platform.claude.com (token refresh，背景自動)
```

---

## 2. OAuth 完整流程與各階段 UA

### 2.1 Claude Code 的真實 OAuth 流程

| 階段 | 動作 | UA | 說明 |
|------|------|-----|------|
| 1. 授權 | 打開瀏覽器到 `claude.ai/oauth/authorize` | 瀏覽器原生 UA (Chrome/Safari/etc) | 用戶手動操作 |
| 2. 回調 | 瀏覽器 redirect 到 localhost callback | 瀏覽器原生 UA | 自動 |
| 3. Token Exchange | `POST platform.claude.com/v1/oauth/token` | **`axios/1.13.6`** (自動預設) | Claude Code 程式碼中未設 UA |
| 4. Token Refresh | `POST platform.claude.com/v1/oauth/token` | **`axios/1.13.6`** (自動預設) | 同上 |
| 5. API 請求 | `POST api.anthropic.com/v1/messages` | **`claude-cli/2.1.81 (external, cli)`** | 顯式設定 |
| 6. Client Data | `GET api.anthropic.com/api/oauth/claude_cli/client_data` | **`claude-code/2.1.81`** | 不同格式 |
| 7. MCP 連接 | SSE/WebSocket | **`claude-code/2.1.81`** | 又不同格式 |

### 2.2 sub2api 的 OAuth 流程（Cookie-based 自動授權）

| 階段 | 動作 | UA | 與 Claude Code 一致？ |
|------|------|-----|---------------------|
| 1. 取組織列表 | `GET claude.ai/api/organizations` (帶 sessionKey cookie) | **`ImpersonateChrome()`** — Chrome UA | 合理 — 真實流程中此步也是瀏覽器 |
| 2. 取授權碼 | `POST claude.ai/v1/oauth/{org}/authorize` (帶 sessionKey cookie) | **`ImpersonateChrome()`** — Chrome UA | 合理 — 同上 |
| 3. Token Exchange | `POST platform.claude.com/v1/oauth/token` | **`axios/1.13.6`** (硬編碼) | **正確匹配** |
| 4. Token Refresh | `POST platform.claude.com/v1/oauth/token` | **`axios/1.13.6`** (硬編碼) | **正確匹配** |
| 5a. API 請求 (下游是 Claude Code) | `POST api.anthropic.com/v1/messages` | **透傳客戶端原始 UA** (如 `claude-cli/2.1.81`) | **正確** — 只填補缺失，不覆蓋 |
| 5b. API 請求 (下游非 Claude Code) | `POST api.anthropic.com/v1/messages` | **強制 `claude-cli/2.1.22 (external, cli)`** | 版本偏舊，但不影響 CC 場景 |

### 2.3 CRS 的 OAuth 流程

| 階段 | 動作 | UA | 與 Claude Code 一致？ |
|------|------|-----|---------------------|
| 1. 取組織列表 | `GET claude.ai/api/organizations` | `Mozilla/5.0...Chrome/120.0.0.0` | 合理 |
| 2. 取授權碼 | `POST claude.ai/v1/oauth/{org}/authorize` | `Mozilla/5.0...Chrome/120.0.0.0` | 合理 |
| 3. Token Exchange | `POST console.anthropic.com/v1/oauth/token` | **`claude-cli/1.0.56 (external, cli)`** | **錯誤** — UA 格式和 endpoint 都不對 |
| 4. Token Refresh | `POST console.anthropic.com/v1/oauth/token` | **`claude-cli/1.0.56 (external, cli)`** | **錯誤** — 同上 |
| 5. API 請求 | `POST api.anthropic.com/v1/messages` | `claude-cli/1.0.119 (external, cli)` (預設) 或透傳 | 版本極度過時 |

### 2.4 端點差異

| 端點 | Claude Code | CRS | sub2api |
|------|-------------|-----|---------|
| Authorize URL | `claude.ai/oauth/authorize` | 同左 | 同左 |
| **Token URL** | **`platform.claude.com/v1/oauth/token`** | **`console.anthropic.com/v1/oauth/token`** | **`platform.claude.com/v1/oauth/token`** |
| Redirect URI | `platform.claude.com/oauth/code/callback` | 同左 | 同左 |
| Client ID | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` | 同左 | 同左 |

### 2.5 Scopes 差異

| 系統 | 瀏覽器 OAuth Scopes |
|------|-------------------|
| **Claude Code v2.1.81** | `org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload` |
| **CRS** | `org:create_api_key user:profile user:inference user:sessions:claude_code` |
| **sub2api** | `org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers` |

---

## 3. Token 操作 User-Agent 實測驗證

### 3.1 逆向分析

從 `/opt/claude-code/bin/claude` 提取的 token 函數，只設了 `Content-Type`，**沒有設 User-Agent**：

```javascript
// Token Exchange (ZjA) 和 Token Refresh ($pH) 完全相同的 header 配置
await DA.post(rL().TOKEN_URL, body, {
  headers: {"Content-Type": "application/json"},
  timeout: 15000
});
```

axios Node.js adapter 自動填入 `"axios/" + W8H`，其中 `W8H = "1.13.6"`。

### 3.2 抓包驗證

```http
POST /v1/oauth/token HTTP/1.1
Accept: application/json, text/plain, */*
Content-Type: application/json
User-Agent: axios/1.13.6
Content-Length: 207
Accept-Encoding: gzip, compress, deflate, br
Host: platform.claude.com
Connection: keep-alive
```

### 3.3 歷史版本 bundled axios（從 npm tarball 實測提取）

| Claude Code 版本 | bundled axios | Token UA |
|-----------------|-------------|----------|
| 1.0.3 ~ 2.1.72 | 1.8.4 | `axios/1.8.4` |
| 2.1.78 | 1.13.4 | `axios/1.13.4` |
| 2.1.80 ~ 2.1.87+ | 1.13.6 | `axios/1.13.6` |

### 3.4 三者 Token UA 對比

| | Claude Code | CRS | sub2api |
|---|-------------|-----|---------|
| Token UA | `axios/1.13.6` | `claude-cli/1.0.56` | `axios/1.13.6` |
| Token Endpoint | `platform.claude.com` | `console.anthropic.com` | `platform.claude.com` |

**sub2api 完全匹配。CRS 有兩個致命錯誤。**

---

## 4. API 請求層 HTTP 指紋

### 4.1 Claude Code 的 UA 格式

| 用途 | 格式 | 範例 |
|------|------|------|
| API 請求 | `claude-cli/<VER> (external, <entrypoint>)` | `claude-cli/2.1.81 (external, cli)` |
| MCP/Metrics | `claude-code/<VER>` | `claude-code/2.1.81` |
| Token 操作 | `axios/<bundled_ver>` (自動) | `axios/1.13.6` |

### 4.2 sub2api 的兩種 API Header 模式

**模式 A: 下游是 Claude Code** (`applyClaudeOAuthHeaderDefaults`, L5835)
- 只填補缺失的 header，不覆蓋
- 真實 CC 自帶 UA → **`DefaultHeaders` 中的 `2.1.22` 不會出現在 wire 上**
- X-Stainless-* 同理，客戶端自帶的優先

**模式 B: 下游非 Claude Code** (`applyClaudeCodeMimicHeaders`, L6139)
- 無條件覆蓋所有 header 為 `DefaultHeaders` 的值
- UA 會被強制設為 `claude-cli/2.1.22 (external, cli)`
- 所有 X-Stainless-* 也會被強制設為硬編碼值

### 4.3 X-Stainless-* Headers (DefaultHeaders 硬編碼值)

| Header | 硬編碼值 | 真實 CC 行為 | 風險場景 |
|--------|---------|-------------|---------|
| `x-stainless-package-version` | `0.70.0` | 隨 SDK 版本 | 僅非 CC 下游 |
| `x-stainless-os` | `Linux` | 真實 OS | 僅非 CC 下游 |
| `x-stainless-arch` | `arm64` | 真實架構 | 僅非 CC 下游 |
| `x-stainless-runtime-version` | `v24.13.0` | 真實版本 | 僅非 CC 下游 |
| `x-stainless-retry-count` | `0` (固定) | 動態遞增 | 僅非 CC 下游 |
| `x-stainless-timeout` | `600` (固定) | 動態變化 | 僅非 CC 下游 |

### 4.4 CRS 獨有問題

- **`accept-encoding: identity`** — 強制無壓縮（真實 CC 用 `gzip, compress, deflate, br`）
- CLI 版本極度過時 (`1.0.119` / `1.0.56` / `1.0.57`)
- X-Stainless-* 全部硬編碼，無論下游是否為 CC 都使用

---

## 5. metadata.user_id 身份指紋

| 欄位 | Claude Code | CRS | sub2api |
|------|-------------|-----|---------|
| `device_id` | 真實機器 SHA-256 | **保留原值** | 替換為 per-account 隨機 hex (7 天 TTL) |
| `account_uuid` | 登入帳號 UUID | 替換為上游帳號 UUID | 替換為上游帳號 UUID |
| `session_id` | 真實 session UUID | `SHA256(accountId+original)` → UUID | `SHA256(accountID+original)` → UUID |

---

## 6. TLS 指紋

| | Claude Code | CRS | sub2api |
|---|-------------|-----|---------|
| TLS 實現 | Node.js v24.3.0 原生 | Node.js 原生 (**天然匹配**) | Go + uTLS 模擬 Node.js 24.x |
| Cookie OAuth TLS | 真瀏覽器 | Node.js | `ImpersonateChrome()` |
| API 請求 TLS | Node.js 原生 | Node.js 原生 | uTLS 模擬 Node.js |
| 風險 | 基準 | **低** | **中** — HTTP/2 frame 差異 |

---

## 7. 版本一致性交叉驗證表

| Claude Code 版本 | CLI UA | Token UA | axios |
|-----------------|--------|----------|-------|
| 1.0.3 ~ 2.1.72 | `claude-cli/<ver>` | `axios/1.8.4` | 1.8.4 |
| 2.1.78 | `claude-cli/2.1.78` | `axios/1.13.4` | 1.13.4 |
| 2.1.80 ~ 2.1.87+ | `claude-cli/<ver>` | `axios/1.13.6` | 1.13.6 |

### 全 Claude Code 下游場景

| 階段 | sub2api UA | 來源 | 一致？ |
|------|-----------|------|--------|
| Cookie OAuth (Step 1-2) | Chrome UA | `ImpersonateChrome()` | N/A — 瀏覽器操作 |
| Token Exchange (Step 3) | `axios/1.13.6` | 硬編碼 | **正確** |
| Token Refresh (Step 4) | `axios/1.13.6` | 硬編碼 | **正確** |
| API 請求 (Step 5) | 透傳 (如 `claude-cli/2.1.81`) | 客戶端原始值 | **正確** |

**全 CC 下游場景完全沒有版本不一致問題。**

### 非 Claude Code 下游場景

| 階段 | sub2api UA | 一致？ |
|------|-----------|--------|
| Token Refresh | `axios/1.13.6` → 對應 CC 2.1.80+ | OK |
| API 請求 | `claude-cli/2.1.22` → 對應 CC 2.1.22 → 應搭配 `axios/1.8.4` | **不匹配** |

---

## 8. 偵測策略與風險評估

### 8.1 Token 層面

| # | 規則 | 目標 | 難度 | 誤判率 |
|---|------|------|------|--------|
| T1 | Token UA = `claude-cli/*` 而非 `axios/*` | **CRS** | 簡單 | 0% |
| T2 | Token Endpoint = `console.anthropic.com` | **CRS** | 簡單 | 0% |
| T3 | Token axios 版本與 CLI 版本交叉不匹配 | 非CC模式 sub2api | 中等 | 低 |
| T4 | 同一 IP 大量 refresh_token 操作 | 兩者 | 中等 | 0% |

### 8.2 API 請求層面

| # | 規則 | 目標 | 難度 | 誤判率 |
|---|------|------|------|--------|
| A1 | `accept-encoding: identity` | **CRS** | 簡單 | 低 |
| A2 | CLI 版本 1.0.x | **CRS** | 簡單 | 低 |
| A3 | `x-stainless-retry-count` 永遠為 0 | 非CC模式 | 中等 | 有 |

### 8.3 行為層面

| # | 規則 | 目標 | 難度 | 誤判率 |
|---|------|------|------|--------|
| B1 | 同一帳號多 device_id | CRS | 困難 | 有 |
| B2 | 24hr 不間斷 | 兩者 | 中等 | 低 |
| B3 | Tool name 隨機後綴 | **CRS** (非CC) | 簡單 | 0% |

---

## 9. 各系統弱點總覽

### CRS

| 嚴重度 | 弱點 | 現值 | 正確值 |
|--------|------|------|--------|
| **致命** | Token UA 格式錯誤 | `claude-cli/1.0.56` | `axios/1.13.6` |
| **致命** | Token Endpoint 錯誤 | `console.anthropic.com` | `platform.claude.com` |
| **高** | accept-encoding 強制 identity | `identity` | `gzip, compress, deflate, br` |
| **高** | CLI 版本極度過時 | 1.0.x | 2.1.81+ |

### sub2api

| 嚴重度 | 弱點 | 出現條件 | 說明 |
|--------|------|---------|------|
| **中** | Mimic CLI UA 偏舊 (2.1.22) | **僅非 CC 下游** | 與 token `axios/1.13.6` 交叉不匹配 |
| **中** | x-stainless-* 固定值 | **僅非 CC 下游** | retry-count=0, timeout=600 固定 |
| **低** | uTLS vs 原生 Node.js | 所有場景 | HTTP/2 frame 微妙差異 |
| **低** | 缺少 `user:file_upload` scope | OAuth 初始授權 | 不直接暴露 |

### 評分

| 維度 | CRS | sub2api (全CC) | sub2api (非CC) |
|------|-----|---------------|---------------|
| Token | 1/10 | **10/10** | **10/10** |
| API Header | 3/10 | **9/10** | 6/10 |
| TLS | **8/10** | 6/10 | 6/10 |
| **總分** | **4/10** | **8/10** | **7/10** |

---

## 10. 附錄：關鍵原始碼證據

### A. Claude Code Token 函數（binary 逆向）

```javascript
// ZjA (exchange) 和 $pH (refresh) — 只有 Content-Type，UA 由 axios 自動填入
await DA.post(rL().TOKEN_URL, body, {
  headers: {"Content-Type": "application/json"}, timeout: 15000
});
// axios adapter: y.set("User-Agent", "axios/" + W8H, false); // W8H = "1.13.6"
```

### B. Claude Code 常數（binary 逆向）

```javascript
TOKEN_URL: "https://platform.claude.com/v1/oauth/token"
CLIENT_ID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
```

### C. CRS Token Exchange

```javascript
// /tmp/crs/src/utils/oauthHelper.js:187
'User-Agent': 'claude-cli/1.0.56 (external, cli)'  // ← 錯
// URL: "https://console.anthropic.com/v1/oauth/token"  // ← 錯
```

### D. sub2api Token Exchange

```go
// /tmp/sub2api/backend/internal/repository/claude_oauth_service.go:215
SetHeader("User-Agent", "axios/1.13.6")  // ← 正確
// URL: "https://platform.claude.com/v1/oauth/token"  // ← 正確
```

### E. sub2api 兩種模式

```go
// 模式 A (L5835): 填補缺失 — CC 下游時 DefaultHeaders 不覆蓋客戶端值
if getHeaderRaw(req.Header, key) == "" { setHeaderRaw(..., value) }

// 模式 B (L6139): 強制覆蓋 — 非 CC 下游時用 DefaultHeaders 值
setHeaderRaw(req.Header, resolveWireCasing(key), value)
```

### F. 驗證命令

```bash
# bundled axios 版本
strings /opt/claude-code/bin/claude | grep -oP 'W8H="[^"]*"'

# Token Endpoint
strings /opt/claude-code/bin/claude | grep -oP 'TOKEN_URL:"[^"]*"'

# 各版本 axios
for v in 1.0.3 2.1.78 2.1.81 2.1.87; do
  tarball=$(npm view @anthropic-ai/claude-code@$v dist.tarball)
  varname=$(curl -sL "$tarball" | tar xzO '*/cli.*js' | \
    grep -oP '"User-Agent","axios/"\+\K\w+' | head -1)
  val=$(curl -sL "$tarball" | tar xzO '*/cli.*js' | \
    grep -oP "${varname}=\"\K[0-9]+\.[0-9]+\.[0-9]+" | head -1)
  echo "claude-code@$v → axios/${val}"
done
```

---

*報告結束*
