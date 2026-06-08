# Container Manager Deployment Designs

Date: 2026-06-08

This document records the deployment design for Arcane, Komodo, and Dockhand. It is intended as the trace point for future changes.

## Port Plan

| Tool | Status | URL | Host port | Container port | Existing Portainer impact |
|---|---|---|---:|---:|---|
| Komodo | Prepared / currently stopped | `http://192.168.10.13:55003` | 55003 | 9120 | None |
| Dockhand | Design only | `http://192.168.10.13:55002` | 55002 | 3000 | None |
| Arcane | Design only | `http://192.168.10.13:55004` | 55004 | 3552 | None |
| Portainer | Existing fallback | `http://<host>:9000`, `https://<host>:9443` | 9000/9443 | 9000/9443 | Kept running |

## Deployment Boundaries

Komodo:

- Directory: `/home/df/workspace/myServices/Komodo`
- Default mode starts only `mongo` and `core`.
- `periphery` is behind Compose profile `agent`.
- Default mode does not mount `/var/run/docker.sock`.
- Future agent root: `/etc/komodo`
- Backups: `/mnt/appdata/Komodo/backups`

Dockhand:

- Directory: `/home/df/workspace/myServices/Dockhand`
- Design only; not started by this plan.
- Uses `/mnt/appdata/Dockhand`.
- Mounts `/home/df/workspace/myServices` for adoption testing.
- Mounts Docker socket if started, so it can affect existing stacks.

Arcane:

- Directory: `/home/df/workspace/myServices/Arcane`
- Design only; not started by this plan.
- Uses `/mnt/appdata/Arcane`.
- Mounts Docker socket if started, so it can affect existing stacks.
- Kept as evaluation because `v2.0.0` is a fresh major line.

## Commands

Komodo panel-only:

```bash
cd /home/df/workspace/myServices/Komodo
docker compose --env-file compose.env --env-file compose.env.local up -d mongo core
```

Komodo agent mode, only after review:

```bash
cd /home/df/workspace/myServices/Komodo
docker compose --env-file compose.env --env-file compose.env.local --profile agent up -d
```

Dockhand trial:

```bash
cd /home/df/workspace/myServices/Dockhand
docker compose up -d
```

Arcane trial:

```bash
cd /home/df/workspace/myServices/Arcane
docker compose up -d
```

## Files Created Or Updated

- `/home/df/workspace/myServices/Komodo/docker-compose.yml`
- `/home/df/workspace/myServices/Komodo/compose.env`
- `/home/df/workspace/myServices/Komodo/DEPLOYMENT_DESIGN.md`
- `/home/df/workspace/myServices/Komodo/container-management-research-2026-06-08.md`
- `/home/df/workspace/myServices/Dockhand/docker-compose.yml`
- `/home/df/workspace/myServices/Dockhand/compose.env`
- `/home/df/workspace/myServices/Dockhand/compose.env.local.example`
- `/home/df/workspace/myServices/Dockhand/DEPLOYMENT_DESIGN.md`
- `/home/df/workspace/myServices/Arcane/docker-compose.yml`
- `/home/df/workspace/myServices/Arcane/compose.env`
- `/home/df/workspace/myServices/Arcane/compose.env.local.example`
- `/home/df/workspace/myServices/Arcane/DEPLOYMENT_DESIGN.md`

## Verification Snapshot

Image manifests verified:

- `ghcr.io/moghtech/komodo-core:2.2.0`
- `ghcr.io/moghtech/komodo-periphery:2.2.0`
- `fnsys/dockhand:v1.0.32`
- `ghcr.io/getarcaneapp/manager:v2.0.0`

Port snapshot before starting Komodo:

- `9000/9443` occupied by existing Portainer.
- `55002/55003/55004` were not listening.

Komodo panel start result:

- Started: `komodo-mongo`, `komodo-core`
- Tested URL: `http://192.168.10.13:55003`
- `curl -I http://127.0.0.1:55003/` returned `HTTP/1.1 200 OK`.
- `curl -I http://192.168.10.13:55003/` returned `HTTP/1.1 200 OK`.
- `komodo-core` has no `/var/run/docker.sock` mount.

Komodo full start test result:

- Started: `komodo-mongo`, `komodo-core`, `komodo-periphery`
- `komodo-periphery` connected to Core as server `axolotl`.
- `komodo-periphery` has expected Docker management mounts, including `/var/run/docker.sock`.
- Existing Portainer remains running on `9000/9443`.
- Komodo runtime was stopped after this test; volumes were preserved.

## Change Policy

- Do not expose these panels through Nginx Proxy Manager until auth, terminal access, and backup behavior are reviewed.
- Keep Portainer running during migration.
- Do not enable broad auto-update for database, NPM, Vaultwarden, Nextcloud, Immich, GPU/AI, VPN, or torrent stacks.
- Record every future port, mount, image tag, or profile change in this file or the service-specific `DEPLOYMENT_DESIGN.md`.
