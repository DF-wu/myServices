# Arcane Deployment Design

Date: 2026-06-08

## Purpose

Arcane is prepared as an evaluation deployment only. It is not the primary replacement for Portainer yet because the selected version is the fresh `v2.0.0` line and should be observed before being trusted with critical stacks.

## Isolation

- Compose project: `arcane`
- Container: `arcane`
- UI port: `55004 -> 3552`
- Data root: `/mnt/appdata/Arcane`
- Existing Portainer ports `9000/9443` are not touched.
- No Nginx Proxy Manager exposure is configured.

## Host Access

Arcane uses `/var/run/docker.sock` in this design because container management requires Docker API access. Starting it gives Arcane the ability to affect host containers, so keep it as a trial UI and do not expose it publicly.

## Files

- `docker-compose.yml`: pinned deployment design using `ghcr.io/getarcaneapp/manager:v2.0.0`.
- `compose.env`: committed non-secret settings.
- `compose.env.local.example`: secret template.
- `.gitignore`: excludes local secrets and accidental local data.

## Before Starting

```bash
cd /home/df/workspace/myServices/Arcane
cp compose.env.local.example compose.env.local
openssl rand -base64 32
openssl rand -base64 32
sudo mkdir -p /mnt/appdata/Arcane/data /mnt/appdata/Arcane/projects /mnt/appdata/Arcane/builds
docker compose config --quiet
```

Put the two generated values into `compose.env.local` as `ENCRYPTION_KEY` and `JWT_SECRET`.

## Start / Stop

```bash
docker compose up -d
docker compose down
```

Open: `http://192.168.10.13:55004`

## Traceability

Selected image tag was verified locally with:

```bash
docker buildx imagetools inspect ghcr.io/getarcaneapp/manager:v2.0.0
```

Reference:

- Official basic compose: https://github.com/getarcaneapp/arcane/blob/v2.0.0/docker/examples/compose.basic.yaml
- Official env example: https://github.com/getarcaneapp/arcane/blob/v2.0.0/.env.example
