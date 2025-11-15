# 薄荷公益站抽奖自动化

使用 GitHub Actions + Playwright + **FlareSolverr** 实现每日自动抽奖，**自动绕过 Cloudflare Turnstile 验证**。

## 功能特点

- ✅ 每天自动抽奖（北京时间 8:00 AM）
- ✅ 基于 linux.do Cookie，无需密码
- ✅ 自动处理 OAuth 授权流程
- ✅ **使用 FlareSolverr 自动绕过 Cloudflare Turnstile 验证**
- ✅ 失败时自动截图并创建 Issue
- ✅ 支持手动触发

## 技术栈

- **Playwright**: 浏览器自动化
- **FlareSolverr**: 绕过 Cloudflare 保护
- **GitHub Actions**: 定时任务调度
- **linux.do OAuth**: 身份验证

## 快速开始

### 1. Fork 或克隆此仓库

```bash
git clone <your-repo-url>
cd lottery-automation
```

### 2. 配置 GitHub Secrets

前往仓库的 `Settings` → `Secrets and variables` → `Actions` → `New repository secret`

添加以下 Secret：

#### `LINUXDO_COOKIES`

**获取方法**：

1. 在浏览器中登录 https://linux.do
2. 打开开发者工具（F12）
3. 进入 `Application` / `应用` 标签
4. 左侧选择 `Cookies` → `https://linux.do`
5. 使用浏览器插件（如 **Cookie-Editor**）导出为 JSON 格式

**Cookie JSON 格式示例**：

```json
[
  {
    "Host raw": "https://linux.do/",
    "Name raw": "_t",
    "Path raw": "/",
    "Content raw": "你的cookie值",
    "Expires raw": "1768376592",
    "Send for raw": "true",
    "HTTP only raw": "true",
    "SameSite raw": "lax",
    "This domain only raw": "true"
  },
  {
    "Host raw": "https://connect.linux.do/",
    "Name raw": "auth.session-token",
    "Path raw": "/",
    "Content raw": "你的cookie值",
    "Expires raw": "0",
    "Send for raw": "true",
    "HTTP only raw": "true",
    "SameSite raw": "lax",
    "This domain only raw": "true"
  }
]
```

**重要的 Cookie**：
- `_t` - 长期认证令牌
- `_forum_session` - 会话 cookie
- `auth.session-token` - OAuth 认证令牌（connect.linux.do 域名）

### 3. 启用 GitHub Actions

1. 进入仓库的 `Actions` 标签
2. 如果提示启用工作流，点击 `I understand my workflows, go ahead and enable them`
3. 找到 `薄荷公益站自动抽奖` 工作流
4. 点击 `Enable workflow`

### 4. 测试运行

点击 `Run workflow` → `Run workflow` 进行手动测试。

查看运行日志，确认：
- ✅ FlareSolverr 服务已启动
- ✅ Cookie 注入成功
- ✅ OAuth 授权成功
- ✅ Cloudflare Turnstile 验证已绕过
- ✅ 抽奖成功

## 工作流说明

### 定时任务

- 每天 UTC 0:00 自动运行（北京时间 8:00 AM）
- 使用 cron 表达式：`0 0 * * *`

### FlareSolverr 服务

GitHub Actions 会自动启动 FlareSolverr Docker 容器来绕过 Cloudflare 验证：

```yaml
services:
  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    ports:
      - 8191:8191
```

当检测到 Cloudflare Turnstile 验证时，脚本会：
1. 调用 FlareSolverr API 解决验证
2. 获取绕过验证后的 cookies
3. 注入 cookies 到浏览器
4. 继续抽奖流程

### 手动触发

进入 `Actions` → 选择工作流 → `Run workflow`

## 故障排查

### Cookie 已过期

**症状**：工作流失败，截图显示未登录状态

**解决**：
1. 重新登录 linux.do
2. 导出新的 cookie JSON
3. 更新 GitHub Secrets 中的 `LINUXDO_COOKIES`

### 今天已经抽过奖

**症状**：日志显示 "今天已经抽过奖了"

**解决**：这是正常的，脚本会自动退出

### FlareSolverr 无法绕过验证

**症状**：日志显示 "FlareSolverr 解决失败"

**解决**：
1. 查看 FlareSolverr 服务日志
2. 检查 Cloudflare 是否更新了验证机制
3. 尝试手动运行测试

### 页面结构变化

**症状**：找不到元素，选择器失败

**解决**：
1. 查看错误截图
2. 更新 `lottery-auto.js` 中的选择器
3. 可能需要修改 `.bg-red-500` 为新的授权按钮选择器

## 本地测试

### 安装依赖

```bash
npm install
npx playwright install chromium
```

### 使用 Docker 运行 FlareSolverr

```bash
docker run -d \
  --name=flaresolverr \
  -p 8191:8191 \
  ghcr.io/flaresolverr/flaresolverr:latest
```

### 运行脚本

```bash
export LINUXDO_COOKIES='[你的cookie JSON]'
export FLARESOLVERR_URL='http://localhost:8191/v1'
node lottery-auto.js
```

## 安全提示

⚠️ **重要**：
- 使用 **私有仓库** 以保护 cookie 和日志
- 定期更新 cookie（建议每 1-2 个月）
- 不要分享工作流日志（可能包含敏感信息）
- 启用 GitHub 账号的两步验证

## Cookie 有效期

根据配置：
- `_t` cookie：约 2 个月有效期
- `_forum_session`：会话 cookie（需定期更新）
- `auth.session-token`：会话 cookie（需定期更新）

建议：每 1-2 个月更新一次 cookie。

## 文件说明

```
.
├── .github/
│   └── workflows/
│       └── lottery.yml          # GitHub Actions 工作流配置（含 FlareSolverr）
├── lottery-auto.js              # Playwright 自动化脚本（集成 FlareSolverr）
├── package.json                 # Node.js 依赖（含 axios）
├── README.md                    # 本文件
└── screenshots/                 # 截图目录（自动生成）
```

## 高级配置

### 修改运行时间

编辑 `.github/workflows/lottery.yml`：

```yaml
on:
  schedule:
    - cron: '0 1 * * *'  # UTC 1:00 = 北京时间 9:00
```

使用 [crontab.guru](https://crontab.guru/) 生成 cron 表达式。

### FlareSolverr 配置

FlareSolverr 服务在 GitHub Actions 中自动启动，无需额外配置。

如需调整超时或其他参数，修改 `lottery-auto.js` 中的 `solveTurnstile` 函数：

```javascript
const response = await axios.post(FLARESOLVERR_URL, {
  cmd: 'request.get',
  url: url,
  maxTimeout: 60000  // 调整超时时间（毫秒）
});
```

## 工作原理

1. **定时触发** → GitHub Actions 在设定时间启动
2. **启动 FlareSolverr** → Docker 容器在后台运行
3. **注入 Cookies** → 加载 linux.do 登录状态
4. **访问抽奖页面** → 点击"开始转动"
5. **OAuth 授权** → 自动点击"允许"按钮
6. **Cloudflare 验证** → FlareSolverr 自动绕过 Turnstile
7. **执行抽奖** → 等待转盘结果
8. **提取兑换码** → 记录到工作流 Summary

## License

MIT

## 免责声明

本项目仅供学习交流使用，使用者需遵守相关网站的服务条款。作者不对使用本项目导致的任何问题负责。
