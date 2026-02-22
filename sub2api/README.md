# sub2api (next-gen CRS)

This folder deploys **sub2api** (the new project by the same author of `claude-relay-service`).

Goal: run sub2api in parallel with the existing CRS on axolotl, use **"Sync from CRS"** to import accounts, then gradually switch clients.

## Deploy

```bash
cd myServices/sub2api
docker compose up -d
```

- Web UI: `http://<host>:43062`
- Health check: `http://<host>:43062/health`

Default admin:
- Email: `admin@sub2api.local`
- Password: `${DF_PASSWORD}` (same as other stacks in this repo)

Data paths:
- `/mnt/appdata/sub2api/data`
- `/mnt/appdata/sub2api/postgres`
- `/mnt/appdata/sub2api/redis`

## Migrate Accounts From CRS (claude-relay-service)

1. Keep old CRS running (current ChatStack uses host port `43057`).
2. In sub2api Admin UI: **Accounts** -> **Sync from CRS**
3. CRS Base URL examples (pick one):
   - `http://axolotl.newhome:43057`
   - `http://host.docker.internal:43057` (this compose file already adds `host.docker.internal` mapping)
4. CRS Username / Password: use the CRS admin credentials.

Notes:
- sub2api requires CRS version >= v1.1.240 for server-to-server export.
- API Keys in sub2api are different from CRS: after syncing accounts, create Groups + API Keys in sub2api.

## Switch Clients

Claude (Anthropic compatible):

```bash
export ANTHROPIC_BASE_URL="http://<host>:43062"
export ANTHROPIC_AUTH_TOKEN="sk-xxx" # sub2api generated api key
```

Antigravity dedicated endpoints:

```bash
export ANTHROPIC_BASE_URL="http://<host>:43062/antigravity"
export ANTHROPIC_AUTH_TOKEN="sk-xxx"
```

## Optional Hardening

If you plan to enable 2FA (TOTP) long-term, set a fixed 64-hex encryption key:

```bash
openssl rand -hex 32
```

Then add `TOTP_ENCRYPTION_KEY` to `myServices/sub2api/docker-compose.yml`.