# Phase 2 Implementation Checklist

This is the condensed execution checklist for the next agent.

## Before touching Docker

- [ ] Read `README.md` and docs `01` through `11`.
- [ ] Confirm DF answered `docs/05-decision-questions.md`.
- [ ] Confirm final exposure mode and hostname.
- [ ] Confirm temporary local port.
- [ ] Confirm runtime config path.
- [ ] Run `./scripts/scan-secrets.sh` and confirm no literal secrets in the handoff package.
- [ ] Run `./scripts/validate-homepage-template.sh`.

## Runtime config preparation

```bash
cd ~/workspace/myServices/hompage
./scripts/prepare-runtime-config.sh
```

Then edit:

```bash
$EDITOR .env
$EDITOR /mnt/appdata/homepage/config/settings.yaml
$EDITOR /mnt/appdata/homepage/config/services.yaml
$EDITOR /mnt/appdata/homepage/config/widgets.yaml
```

## Local deploy

```bash
cd ~/workspace/myServices/hompage
docker compose config
docker compose up -d
./scripts/smoke-test-homepage.sh
```

If it fails, do not move to reverse proxy. Check logs first.

## Discovery first card

- [ ] Pick one low-risk service.
- [ ] Add non-secret `homepage.*` labels only.
- [ ] Redeploy that service stack.
- [ ] Confirm the card appears.
- [ ] Confirm status works.
- [ ] Confirm `docker inspect SERVICE` shows no literal secret in `homepage.*` labels.

## Widgets

For each widget:

- [ ] Confirm DF wants the widget.
- [ ] Use least-privileged API key/token where possible.
- [ ] Put the value in `.env` as `HOMEPAGE_VAR_*`.
- [ ] Reference it as `{{HOMEPAGE_VAR_*}}` in YAML.
- [ ] Test connectivity from inside the Homepage container.
- [ ] Check Homepage logs and UI.

## Reverse proxy

- [ ] Homepage local URL works.
- [ ] Add final hostname to `HOMEPAGE_ALLOWED_HOSTS`.
- [ ] Add NPM route or Cloudflare Access route according to DF's decision.
- [ ] Apply authentication/access control.
- [ ] Test final URL.
- [ ] Verify Heimdall still works.

## Completion

- [ ] `./scripts/scan-secrets.sh` passes.
- [ ] `docker compose ps` shows Homepage healthy/running.
- [ ] `docker logs --tail 200 homepage` has no critical config errors.
- [ ] DF confirms layout and first-pass service list.
- [ ] Commit only non-secret files if DF approves.
