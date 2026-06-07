# Validation and Rollback Runbook

## Static validation

```bash
cd ~/workspace/myServices/homepage
./scripts/validate-homepage-template.sh
./scripts/scan-secrets.sh
```

`validate-homepage-template.sh` renders Docker Compose and parses YAML templates. `scan-secrets.sh` fails on likely literal secrets outside ignored private areas.

## Runtime smoke test

After `docker compose up -d`:

```bash
./scripts/smoke-test-homepage.sh
```

The script checks:

- `homepage` container exists.
- Homepage local HTTP endpoint responds.
- Recent logs are shown for diagnosis.
- Docker proxy container exists.

## Manual browser checks

- Open temporary local URL.
- Open final protected URL.
- Confirm `HOMEPAGE_ALLOWED_HOSTS` errors are absent.
- Confirm browser console has no major API proxy failures.
- Click several cards.
- Expand Docker stats on one service if enabled.

## Widget checks

For every failing widget:

1. Confirm widget URL does not end with `/` or include extra API path.
2. Confirm Homepage container can reach the host.
3. Confirm credentials are valid.
4. Check `docker logs homepage`.
5. Temporarily set `LOG_LEVEL=debug` and redeploy Homepage only.
6. Revert debug logging after diagnosis.

## Safe rollback during Stage 2

Homepage is side-by-side with Heimdall, so rollback is simply:

```bash
cd ~/workspace/myServices/homepage
docker compose down
```

Do not delete config. Heimdall remains online.

If NPM route was added, disable only the new Homepage proxy host. Do not touch Heimdall's proxy host.

## Safe rollback after Stage 3

Stage 3 is not part of this phase. If Heimdall was later disabled and needs rollback:

1. Re-enable Heimdall stack.
2. Restore NPM route to Heimdall target.
3. Leave Homepage on alternate port for debugging.
4. Use the backup created before Stage 3.

## Evidence to collect before asking for help

```bash
docker compose ps
docker logs --tail 300 homepage
docker logs --tail 300 homepage-dockerproxy
ls -la /mnt/appdata/homepage/config
sed -n '1,220p' /mnt/appdata/homepage/config/settings.yaml
```

Do not paste `.env` or secret-bearing service widget blocks into public chat.
