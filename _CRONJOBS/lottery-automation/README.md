# Daily Lottery Automation

Automated daily lottery system using GitHub Actions, Playwright, and FlareSolverr to handle Cloudflare protection.

## Features

- ✅ Daily automation (8:00 AM Beijing Time)
- ✅ Cookie-based authentication (no password required)
- ✅ OAuth flow automation
- ✅ Cloudflare Turnstile bypass with FlareSolverr
- ✅ Screenshot capture on failure
- ✅ Manual trigger support

## Tech Stack

- **Playwright**: Browser automation
- **FlareSolverr**: Cloudflare protection bypass
- **GitHub Actions**: Scheduled task orchestration
- **OAuth 2.0**: Authentication

## Setup

### 1. Fork or Clone

```bash
git clone <your-repo-url>
cd lottery-automation
```

### 2. Configure GitHub Secrets

Navigate to `Settings` → `Secrets and variables` → `Actions` → `New repository secret`

Add the following secrets:

#### `LINUXDO_COOKIES`

**How to obtain**:

1. Log in to the main site in your browser
2. Open Developer Tools (F12)
3. Go to `Application` tab
4. Select `Cookies` from left sidebar
5. Use browser extension (e.g., **Cookie-Editor**) to export as JSON

**JSON format example**:

```json
[
  {
    "Host raw": "https://example.com/",
    "Name raw": "_t",
    "Path raw": "/",
    "Content raw": "your_cookie_value",
    "Expires raw": "1768376592",
    "Send for raw": "true",
    "HTTP only raw": "true",
    "SameSite raw": "lax"
  }
]
```

#### `CONNECT_COOKIES`

OAuth service cookies in the same JSON format as above.

### 3. Enable GitHub Actions

1. Navigate to `Actions` tab
2. Enable workflows if prompted
3. Find the lottery workflow
4. Click `Enable workflow`

### 4. Test Run

Click `Run workflow` → `Run workflow` for manual testing.

Check logs to verify:
- ✅ FlareSolverr service started
- ✅ Cookies injected
- ✅ OAuth authorization successful
- ✅ Cloudflare Turnstile bypassed
- ✅ Lottery completed

## Workflow Details

### Schedule

Runs daily at 00:00 UTC (08:00 Beijing Time) via cron schedule.

### Manual Trigger

Use `workflow_dispatch` to trigger manually from GitHub Actions UI.

## Troubleshooting

### Cookie Expired

If authentication fails:
1. Re-export cookies from browser
2. Update GitHub Secrets
3. Re-run workflow

### Cloudflare Issues

If Cloudflare verification fails:
- Check FlareSolverr service logs
- Verify OAuth cookies are set
- Review screenshots in workflow artifacts

### Screenshot Access

When workflow fails:
1. Go to failed workflow run
2. Scroll to bottom → `Artifacts` section
3. Download screenshot ZIP file

## Security Notes

- Never commit cookies or tokens to repository
- Use GitHub Secrets for all sensitive data
- Rotate cookies periodically
- Keep dependencies updated

## License

MIT
