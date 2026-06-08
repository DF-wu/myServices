# Dockhand Deployment Design

Date: 2026-06-08

## Purpose

Dockhand is prepared as a fast trial replacement UI for Portainer-style Docker and Compose management. It is the easiest candidate for adopting the current `/home/df/workspace/myServices` tree, but should not become the only control plane until it has been tested against this host's existing stacks.

## Isolation

- Compose project: `dockhand`
- Container: `dockhand`
- UI port: `55002 -> 3000`
- Data root: `/mnt/appdata/Dockhand`
- Existing Portainer ports `9000/9443` are not touched.
- No Nginx Proxy Manager exposure is configured.

## Host Access

Dockhand mounts:

- `/var/run/docker.sock`
- `/mnt/appdata/Dockhand`
- `/home/df/workspace/myServices`

This is intentional for adoption testing, but it also means Dockhand can see and potentially modify existing stacks. Use it carefully and avoid running broad update/adoption actions until each stack is reviewed.

## Files

- `docker-compose.yml`: pinned deployment design using `fnsys/dockhand:v1.0.32`.
- `compose.env`: committed non-secret settings.
- `compose.env.local.example`: secret template for `ENCRYPTION_KEY`.
- `.gitignore`: excludes local secrets and accidental local data.

## Before Starting

```bash
cd /home/df/workspace/myServices/Dockhand
cp compose.env.local.example compose.env.local
openssl rand -base64 32
sudo mkdir -p /mnt/appdata/Dockhand
docker compose config --quiet
```

Put the generated value into `compose.env.local` as `ENCRYPTION_KEY`.

## Start / Stop

```bash
docker compose up -d
docker compose down
```

Open: `http://192.168.10.13:55002`

## Traceability

Selected image tag was verified locally with:

```bash
docker buildx imagetools inspect fnsys/dockhand:v1.0.32
```

Reference:

- Dockhand repository: https://github.com/Finsys/dockhand
- Dockhand release: https://github.com/Finsys/dockhand/releases/tag/v1.0.32
