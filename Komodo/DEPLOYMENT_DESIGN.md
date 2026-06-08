# Komodo Deployment Design

Date: 2026-06-08

## Purpose

Komodo is the preferred long-term replacement control plane, but it is being brought up in two phases:

1. Panel-only mode: MongoDB + Core UI only.
2. Agent mode: enable Periphery after the panel has been configured and the migration plan is clear.

This keeps the first run independent from existing Portainer and avoids touching host Docker until explicitly requested.

## Isolation

- Compose project: `komodo`
- UI container: `komodo-core`
- DB container: `komodo-mongo`
- Agent container: `komodo-periphery`, behind the `agent` profile
- UI port: `55003 -> 9120`
- Existing Portainer ports `9000/9443` are not touched.
- No Nginx Proxy Manager exposure is configured.
- Agent root directory, when enabled: `/etc/komodo`
- Backup path: `/mnt/appdata/Komodo/backups`

## Panel-Only Mode

Panel-only mode starts only MongoDB and Core. It does not mount `/var/run/docker.sock` and does not start Periphery, so Komodo can be opened and configured without managing the host.

```bash
cd /home/df/workspace/myServices/Komodo
docker compose --env-file compose.env --env-file compose.env.local up -d mongo core
```

Open: `http://<host-lan-ip>:55003`

Current panel URL: `http://192.168.10.13:55003`

Panel-only started services:

- `komodo-mongo`
- `komodo-core`

Not started in panel-only mode:

- `komodo-periphery`

## Agent Mode

Agent mode enables Periphery and mounts the Docker socket. This gives Komodo the ability to inspect and operate host Docker resources.

```bash
cd /home/df/workspace/myServices/Komodo
docker compose --env-file compose.env --env-file compose.env.local --profile agent up -d
```

Use this mode for normal Komodo operation on this host. Keep Portainer as fallback while stacks are migrated deliberately.

Current full-mode status:

- `komodo-mongo`: running
- `komodo-core`: running
- `komodo-periphery`: running
- Periphery connected to Core as server `axolotl`
- Periphery mounts `/var/run/docker.sock`, `/proc`, `/etc/komodo`, and `/config/keys`
- Terminal features remain disabled by config

## Safety Controls

- `periphery` is behind Compose profile `agent`.
- Terminal features are disabled by default:
  - `PERIPHERY_DISABLE_TERMINALS=true`
  - `PERIPHERY_DISABLE_CONTAINER_TERMINALS=true`
- Existing stacks under `/home/df/workspace/myServices` are not mounted into Komodo.
- Periphery, if enabled later, uses `/etc/komodo` as the isolated root directory.
- Portainer is left running as fallback.

## Files

- `docker-compose.yml`: pinned Mongo/Core/Periphery design. Periphery is profile-gated.
- `compose.env`: committed non-secret and operational settings.
- `compose.env.local`: local secrets, gitignored.
- `compose.env.local.example`: secret template.
- `.gitignore`: excludes local secrets and accidental local data.
- `container-management-research-2026-06-08.md`: candidate research and source references.

## Before First Start

```bash
cd /home/df/workspace/myServices/Komodo
cp compose.env.local.example compose.env.local
openssl rand -base64 24
openssl rand -base64 18
openssl rand -hex 32
openssl rand -hex 32
sudo mkdir -p /etc/komodo/stacks /etc/komodo/repos /mnt/appdata/Komodo/backups
docker compose --env-file compose.env --env-file compose.env.local config --quiet
```

Put the generated values into `compose.env.local`.

## Traceability

Selected image tags were verified locally with:

```bash
docker buildx imagetools inspect ghcr.io/moghtech/komodo-core:2.2.0
docker buildx imagetools inspect ghcr.io/moghtech/komodo-periphery:2.2.0
```

References:

- Official Mongo compose: https://github.com/moghtech/komodo/blob/v2.2.0/compose/mongo.compose.yaml
- Official env template: https://github.com/moghtech/komodo/blob/v2.2.0/compose/compose.env
- Core config reference: https://github.com/moghtech/komodo/blob/v2.2.0/config/core.config.toml

## 2026-06-08 Panel Start Record

Commands run:

```bash
docker compose --env-file compose.env --env-file compose.env.local config --quiet
docker compose --env-file compose.env --env-file compose.env.local up -d mongo core
docker compose --env-file compose.env --env-file compose.env.local up -d --force-recreate core
```

Reason for Core recreate: `KOMODO_HOST` was changed from placeholder to `http://192.168.10.13:55003`.

Verification:

- `docker compose ... config --services` returned `mongo` and `core`.
- `docker compose ... --profile agent config --services` returned `mongo`, `core`, and `periphery`.
- `curl -I http://127.0.0.1:55003/` returned `HTTP/1.1 200 OK`.
- `curl -I http://192.168.10.13:55003/` returned `HTTP/1.1 200 OK`.
- `docker inspect komodo-core` showed mounts only for `/config/keys` and `/backups`; no `/var/run/docker.sock`.

## 2026-06-08 Full Start Record

Command run:

```bash
docker compose --env-file compose.env --env-file compose.env.local --profile agent up -d
```

Verification:

- `docker compose ... --profile agent ps` showed `komodo-mongo`, `komodo-core`, and `komodo-periphery` running.
- `curl http://192.168.10.13:55003/` returned `200`.
- `docker inspect komodo-periphery` showed expected mounts:
  - `/var/run/docker.sock`
  - `/proc`
  - `/etc/komodo`
  - `/config/keys`
- Periphery log showed `Logged in to Komodo Core core:9120 websocket as Server axolotl`.
