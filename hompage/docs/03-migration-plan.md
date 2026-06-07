# Three-Stage Migration Plan

## Stage 1 — Research and design

Status: in progress / this package.

Deliverables:

- Research Homepage official docs and repo behavior.
- Inventory current Heimdall, Docker stacks, and reverse proxy state without changing anything.
- Define target architecture, config strategy, service grouping, visual direction, and security model.
- Produce config templates and scripts for safe Phase 2 implementation.
- Ask DF one consolidated set of decisions before deployment.

Stage 1 exit criteria:

- `docs/05-decision-questions.md` answered.
- No unresolved blocker around exposure/authentication, hostname, port, or secret handling.
- Future agent understands that no production changes happen until Phase 2.

## Stage 2 — Homepage online beside Heimdall

Goal: deploy Homepage while Heimdall remains online. Debug and refine until Homepage is clearly better.

### Step 2.1 — Prepare runtime config

1. Create runtime directory, recommended:

```bash
mkdir -p /mnt/appdata/homepage/config
```

2. Copy templates:

```bash
rsync -av ~/workspace/myServices/hompage/config-template/config/ /mnt/appdata/homepage/config/
cp ~/workspace/myServices/hompage/config-template/.env.example ~/workspace/myServices/hompage/.env
```

3. Fill `.env` with allowed hosts and widget secrets. Do not commit it.

### Step 2.2 — Deploy local-only first

Use a non-conflicting port such as `33080:3000` during testing. Heimdall currently uses its own ports and must remain untouched.

```bash
cd ~/workspace/myServices/hompage
docker compose config
docker compose up -d
docker logs --tail 200 homepage
curl -fsS http://127.0.0.1:33080/ >/dev/null
```

If host validation fails, read `docker logs homepage` and add the exact host:port to `HOMEPAGE_ALLOWED_HOSTS`.

### Step 2.3 — Test Docker discovery

1. Confirm Homepage can read Docker through proxy:

```bash
docker logs --tail 200 homepage | grep -i docker || true
```

2. Add labels to one low-risk service first, preferably a simple non-secret service.
3. Redeploy that stack only.
4. Confirm the card appears and status works.
5. Repeat in small batches.

### Step 2.4 — Add curated widgets

Add widgets one by one. For every widget:

1. Put secrets in `.env` as `HOMEPAGE_VAR_*`.
2. Put config in `services.yaml` or a label only if it has no secret.
3. Test network from inside Homepage container.
4. Check `docker logs homepage` and browser console.

### Step 2.5 — Reverse proxy route

Only after local testing passes:

1. Add NPM route for the chosen hostname.
2. Add hostname to `HOMEPAGE_ALLOWED_HOSTS` exactly.
3. Protect route using DF's chosen method: LAN/VPN only, NPM access list, or Cloudflare Access.
4. Do not remove Heimdall route yet.
5. Keep Heimdall and Homepage side by side for at least one normal usage cycle.

### Step 2.6 — Acceptance test

Homepage is accepted when:

- It loads through final URL without host validation errors.
- Docker-discovered cards appear correctly.
- Core services are grouped into intended tabs.
- Important widgets show correct data or fail gracefully.
- No secret appears in Docker labels, git diff, logs, or generated documents.
- Heimdall remains reachable as fallback.

## Stage 3 — Heimdall offline and migration complete

Start only after DF explicitly approves.

1. Export final Heimdall SQLite backup:

```bash
cp -a /mnt/appdata/heimdall/www/app.sqlite "/mnt/appdata/heimdall/www/app.sqlite.before-homepage-offline.$(date +%Y%m%d%H%M%S)"
```

2. Export final Homepage config backup:

```bash
tar -C /mnt/appdata -czf "/mnt/appdata/homepage-config.$(date +%Y%m%d%H%M%S).tgz" homepage/config
```

3. Disable Heimdall stack in Portainer or compose, but do not delete appdata.
4. If reusing the old Heimdall public hostname, repoint the proxy to Homepage.
5. Monitor logs and user experience for several days.
6. Archive Heimdall config only after DF confirms no rollback is needed.

Rollback from Stage 3:

- Re-enable Heimdall stack.
- Restore old NPM route / hostname if changed.
- Keep Homepage online on alternate port for later debugging.
