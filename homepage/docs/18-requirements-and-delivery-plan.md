# Requirements and Delivery Plan — Homepage Migration

This document consolidates DF's requirements, decisions, implementation state, and the remaining delivery plan for migrating the homelab dashboard from Heimdall to gethomepage/homepage.

## Owner requirements

DF requested the following:

1. Migrate from Heimdall to gethomepage/homepage.
2. Do not merely replace the visual page; build a maintainable homelab service cockpit.
3. Use a public hostname with reverse proxy:
   - hostname: `hp.dfder.tw`
4. Keep Heimdall available until the new Homepage is proven.
5. Prefer `services.yaml` as the long-term source of truth rather than scattering all metadata into Docker labels.
6. Connect all existing services to Homepage.
7. Use a popular, maintained, pre-existing theme instead of hand-rolling a custom design.
8. Keep detailed plans, reports, runbooks, and status documents for future traceability.
9. Be careful and explicit about every action performed.
10. Commit and push the documentation and deployable handoff files once the plan and current state are properly documented.

## Decisions already applied

| Area | Decision |
|---|---|
| Deployment platform | Docker Compose on axolotl. |
| Working directory | `~/workspace/myServices/homepage` |
| Runtime config | `/mnt/appdata/homepage/config` |
| Runtime image assets | `/mnt/appdata/homepage/images` |
| Local port | `33080 -> 3000` |
| Public hostname | `hp.dfder.tw` |
| Theme | Dracula for Homepage, from `dracula/homepage-app`. |
| Catalog model | `services.yaml` first. Docker labels optional only. |
| Docker integration | `docker-socket-proxy`, read-only, no direct socket exposure to the UI container. |
| Heimdall | Keep running during Stage 2. Do not replace route yet. |
| Secret policy | No secrets in labels, docs, or committed files. Use `.env` / `HOMEPAGE_VAR_*` later. |

## Current implemented state

As of the recovery review on 2026-06-07:

- Homepage is running locally and healthy.
- URL: `http://127.0.0.1:33080/`
- Runtime API `/api/services` returns 9 groups and 111 cards.
- 74 running Docker containers are connected via `server: local-docker`, `container`, and `showStats: true`.
- Dracula theme is installed with `custom.css`, background, and selected icons.
- Heimdall remains running and untouched.
- `hp.dfder.tw` public route is not yet complete.
- NPM container was not running during review; cloudflared appears to be the likely active ingress component.

## Repository deliverables

### Deployment files

```text
docker-compose.yml
config-template/docker-compose.yml
config-template/.env.example
config-template/config/*.yaml
config-template/config/custom.css
config-template/config/custom.js
```

### Runtime/audit scripts

```text
scripts/generate-private-inventory.sh
scripts/generate-services-from-inventory.py
scripts/audit-docker-homepage-readiness.py
scripts/export-heimdall-safe.py
scripts/prepare-runtime-config.sh
scripts/smoke-test-homepage.sh
scripts/validate-homepage-template.sh
scripts/scan-secrets.sh
scripts/check-homepage-labels.sh
scripts/all-checks.sh
scripts/render-phase2-summary.py
```

### Traceability documents

```text
README.md
PHASE2_START_HERE.md
docs/00-executive-summary.md
docs/01-research.md
docs/02-target-design.md
docs/03-migration-plan.md
docs/04-service-catalog-design.md
docs/05-decision-questions.md
docs/06-handoff-for-next-agent.md
docs/07-security-and-threat-model.md
docs/08-implementation-checklist.md
docs/09-label-patterns.md
docs/10-widget-recipes.md
docs/11-validation-and-rollback.md
docs/12-phase1-completion-report.md
docs/13-open-risks-and-quality-gates.md
docs/14-df-decisions.md
docs/15-visual-style-options.md
docs/16-stage2-service-catalog-report.md
docs/17-stage2-current-status-2026-06-07.md
docs/18-requirements-and-delivery-plan.md
```

## Stage plan

### Stage 1 — Research and design

Status: complete.

Completed:

- Researched Homepage official config model.
- Researched Docker deployment, Docker discovery, widgets, secrets, custom CSS, troubleshooting.
- Researched Heimdall SQLite export strategy.
- Created templates, runbooks, security model, and handoff docs.

### Stage 2 — Side-by-side Homepage deployment

Status: partially complete.

Completed:

- Deployed Homepage locally beside Heimdall.
- Deployed read-only docker-socket-proxy.
- Applied Dracula Homepage theme.
- Generated full services.yaml-first catalog.
- Connected all running Docker containers as cards with Docker stats.
- Validated local HTTP and Homepage API.

Remaining:

- Finish public ingress for `hp.dfder.tw`.
- Verify UI in browser via public route.
- Polish service grouping and reduce duplicate/noisy cards.
- Add official service widgets one-by-one after credentials are reviewed.

### Stage 3 — Heimdall retirement

Status: not started.

Start only after DF explicitly approves.

Planned:

- Keep a Heimdall backup.
- Keep a Homepage config backup.
- Switch or retire old Heimdall route only after Homepage is accepted.
- Leave rollback path available.

## Public ingress plan

Current blocker: the expected Nginx Proxy Manager container was not running during review, while `cloudflared` is running. Therefore the next agent should not blindly modify NPM SQLite.

Safe path:

1. Determine whether `*.dfder.tw` public ingress is currently controlled by Cloudflare Tunnel, NPM, or another layer.
2. If Cloudflare Tunnel is authoritative, add route:

```text
hp.dfder.tw -> http://localhost:33080
```

or an equivalent axolotl-local target.

3. If NPM is intended to be authoritative, first restore/locate the NPM container/API and only then add the route using API/UI. Avoid direct SQLite mutation unless there is a DB backup and restart plan.
4. Verify externally:

```bash
curl -I https://hp.dfder.tw
```

5. Confirm authentication/access control is present before considering the public route accepted.

## Widget rollout plan

The current catalog intentionally does not auto-enable secret-bearing widgets. Next step is to enable widgets one by one using reviewed `.env` values.

Priority widgets:

1. Portainer
2. Netdata
3. Uptime Kuma
4. Backrest
5. Jellyfin
6. Immich
7. Nextcloud
8. AdGuard Home
9. qBittorrent
10. PhotoPrism
11. Home Assistant
12. Gluetun
13. Suwayomi
14. TrueNAS — extra caution
15. Cloudflared — if API token is available

Rules:

- Never put credentials in Docker labels.
- Never commit `.env`.
- Prefer least-privileged API tokens.
- Test each widget from inside the Homepage container or through the runtime logs.
- Enable in small batches.

## Validation commands

Before commit or handoff:

```bash
cd ~/workspace/myServices/homepage
./scripts/scan-secrets.sh
./scripts/check-homepage-labels.sh
python - <<'PY'
from pathlib import Path
import yaml
for p in sorted(Path('/mnt/appdata/homepage/config').glob('*.yaml')):
    yaml.safe_load(p.read_text())
for p in sorted(Path('config-template/config').glob('*.yaml')):
    yaml.safe_load(p.read_text())
print('yaml ok')
PY
curl -fsS http://127.0.0.1:33080/ >/dev/null
```

## Files intentionally excluded from git

```text
homepage/.env
homepage/inventory/private/
```

These contain runtime/private inventory or secret placeholders and must remain local.

## Commit scope

The commit should include only `homepage/` deliverables and must not include unrelated dirty files already present elsewhere in the repository.
