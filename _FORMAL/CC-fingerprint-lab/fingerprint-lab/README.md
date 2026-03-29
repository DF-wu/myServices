# Claude Code OAuth Fingerprint Analysis Lab

重現 Claude Code / CRS / sub2api 三者在 OAuth 條件下的 fingerprint 分析。

## 目錄結構

```
fingerprint-lab/
├── README.md                           ← 本文件
├── REPORT.md                           ← 完整分析報告
│
├── scripts/                            ← 分析腳本
│   ├── 01-extract-axios-version.sh     ← 從 binary/npm 提取 axios 版本
│   ├── 02-capture-token-ua.js          ← 模擬 token exchange 並抓取真實 UA
│   ├── 03-compare-fingerprints.sh      ← 比較三者指紋差異
│   ├── 04-extract-binary-oauth.sh      ← 從 Claude Code binary 提取 OAuth 證據
│   ├── 05-clone-repos.sh              ← Clone CRS / sub2api repos
│   └── 06-extract-key-source.sh       ← 提取關鍵原始碼
│
├── tools/                              ← 輔助工具
│   ├── proxy-capture.js               ← HTTP/HTTPS 代理抓包
│   └── version-consistency-check.js   ← 版本一致性檢查器
│
└── evidence/                           ← 提取的證據
    ├── *.txt                          ← binary 逆向提取結果
    └── source/
        ├── crs/                       ← CRS 關鍵原始碼 (11 files)
        └── sub2api/                   ← sub2api 關鍵原始碼 (14 files)
```

## 快速重現

```bash
# 1. Clone repos
bash scripts/05-clone-repos.sh /tmp

# 2. 從 Claude Code binary 提取證據
bash scripts/04-extract-binary-oauth.sh /opt/claude-code/bin/claude ./evidence

# 3. 提取關鍵原始碼
bash scripts/06-extract-key-source.sh /tmp/crs /tmp/sub2api ./evidence/source

# 4. 驗證 Token UA (需 Node.js + axios)
npm install axios@1.13.6
node scripts/02-capture-token-ua.js

# 5. 比較指紋
bash scripts/03-compare-fingerprints.sh /tmp/crs /tmp/sub2api

# 6. 版本一致性檢查
node tools/version-consistency-check.js --dump-map
node tools/version-consistency-check.js --cli 2.1.22 --axios 1.13.6   # sub2api 非CC模式
node tools/version-consistency-check.js --cli 2.1.81 --axios 1.13.6   # sub2api 全CC模式
```

## 核心發現

### 各階段 UA 對比（全 Claude Code 下游場景）

| 階段 | Claude Code | CRS | sub2api |
|------|-------------|-----|---------|
| Cookie OAuth | 真瀏覽器 | Chrome/120 模擬 | ImpersonateChrome() |
| Token Exchange | `axios/1.13.6` | `claude-cli/1.0.56` **(錯)** | `axios/1.13.6` **(對)** |
| Token Refresh | `axios/1.13.6` | `claude-cli/1.0.56` **(錯)** | `axios/1.13.6` **(對)** |
| Token Endpoint | `platform.claude.com` | `console.anthropic.com` **(錯)** | `platform.claude.com` **(對)** |
| API 請求 | `claude-cli/2.1.81` | `claude-cli/1.0.119` (過時) | 透傳客戶端 UA **(對)** |

### 關鍵結論

- **CRS 有兩個致命的零誤判破綻**（token UA 格式 + token endpoint 域名）
- **sub2api 在全 Claude Code 下游場景下偽裝品質很高** — token 層完全匹配，API 層透傳
- sub2api 的 `DefaultHeaders["User-Agent"] = "claude-cli/2.1.22"` **只在非 Claude Code 下游場景下才會出現在 wire 上**，全 CC 下游不受影響

## 分析版本

- Claude Code v2.1.81 (SEA binary, Node.js v24.3.0, axios 1.13.6)
- CRS: commit `fdd8499f`
- sub2api: v0.1.105
- 日期: 2026-03-29
