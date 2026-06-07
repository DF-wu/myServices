# Handoff for the Phase 2 Agent

You are implementing Stage 2 only: bring Homepage online beside Heimdall. Do not take Heimdall offline.

## Hard constraints

- Do not stop, restart, remove, or modify Heimdall unless DF explicitly asks.
- Do not change Nginx Proxy Manager routes until local Homepage works.
- Do not put secrets in Docker labels.
- Do not commit `.env`, `inventory/private/`, or any secret-bearing generated files.
- Prefer `docker-socket-proxy` over direct Docker socket mount.
- If using direct Docker socket, ask DF first because it changes the security posture.

## Start here

1. Read all docs in this directory.
2. Read DF's answers to `docs/05-decision-questions.md`.
3. Review current generated inventory under `inventory/private/`.
4. Copy `config-template/` into runtime config and fill placeholders.

## Suggested implementation sequence

```bash
cd ~/workspace/myServices/hompage
cp config-template/.env.example .env
mkdir -p /mnt/appdata/homepage/config
rsync -av config-template/config/ /mnt/appdata/homepage/config/
# edit .env and /mnt/appdata/homepage/config/*.yaml

docker compose config
docker compose up -d
docker logs --tail 200 homepage
curl -fsS http://127.0.0.1:${HOMEPAGE_HOST_PORT:-33080}/ >/dev/null
```

If the shell does not expand `.env` for `curl`, source it first or check the compose file for the mapped port.

## First label test

Pick one low-risk service. Add only card metadata labels first:

```yaml
labels:
  - homepage.group=Observability
  - homepage.name=Speedtest
  - homepage.icon=speedtest-tracker.svg
  - homepage.href=https://example.invalid
  - homepage.description=LAN speed test
  - homepage.weight=10
```

Redeploy only that stack. Confirm card appears. Then proceed in batches.

## Debug checklist

- `docker compose config`
- `docker ps --filter name=homepage`
- `docker logs --tail 300 homepage`
- `docker logs --tail 300 homepage-dockerproxy`
- Check `config/logs/homepage.log` if mounted.
- Browser console.
- For widget connectivity, test from inside Homepage container.
- Temporarily set `LOG_LEVEL=debug` in `.env` if needed, then revert after diagnosis.

## Completion criteria for Stage 2

- Homepage loads on local port.
- Homepage loads through chosen protected route.
- Heimdall still loads.
- Core tabs/groups are present.
- At least one Docker-discovered service works.
- Key widgets requested by DF either work or have documented blockers.
- No secret appears in labels or git diff.

## Stage 3 is not part of this handoff

Do not offline Heimdall. Stage 3 requires DF approval after Stage 2 acceptance.
