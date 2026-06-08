# Container Management Replacement Research

Date: 2026-06-08
Host observed: `axolotl`, EndeavourOS rolling, Linux `x86_64`, Docker `29.5.2`, Docker Compose `5.1.4`.

## Recommendation

Use **Komodo** as the primary Portainer replacement.

Use **Dockhand** as the runner-up if the main priority is the fastest, lowest-friction adoption of the existing `/home/df/workspace/myServices` compose tree.

Keep **Arcane** on the watchlist or test it in parallel, but do not make it the main production control plane yet because it has just shipped a breaking `v2.0.0` release and is moving very fast.

Keep **Dockge** only as a lightweight compose editor or fallback, not as the main replacement.

## Why This Is Specific To This Host

Local evidence:

- About **75 running containers** were observed with `docker ps`.
- About **68 compose files** were found under `/home/df/workspace/myServices`.
- The host is not a small homelab panel case. It runs AI/LLM services, media services, databases, VPN/proxy services, NPM, monitoring, and several GPU-enabled containers.
- Existing docs describe a Compose-heavy system with Nginx Proxy Manager as the gateway, `/mnt/appdata`, `/mnt/mydata`, and `/mnt/fastpool` storage separation, and manual update preference.
- Current Portainer is still running as fallback.
- Komodo is deployed on LAN port `55003` with Core, MongoDB, and Periphery running.
- `Komodo/compose.env.local` was generated locally and remains gitignored.
- Dockhand and Arcane are prepared as design / trial deployments, but are not started.
- Current Komodo image tags were corrected from unavailable `v2.1.2` style tags to available `2.2.0` image tags.

This environment needs a manager that handles **many Compose stacks**, **Git/source-controlled configuration**, **image update detection**, **manual or controlled redeploys**, **image prune/build lifecycle**, and **future multi-host expansion**. A simple dashboard or app-store style UI is not enough.

## Scoring

Weights:

- Active development and quality: 25
- Image lifecycle: 30
- Multi-platform / multi-host support: 20
- GUI quality: 15
- Fit for this existing system: 10

| Candidate | Score | Verdict |
|---|---:|---|
| Komodo | 89 | Best long-term fit |
| Dockhand | 82 | Best immediate Portainer-like replacement |
| Arcane | 78 | Very promising, but too fresh for primary production |
| Dockge | 64 | Good compose UI, not a full replacement |
| Portainer CE | 60 | Active, but user already wants to leave it |
| Rancher / Kubernetes | 55 | Strong, but wrong operating model unless migrating to Kubernetes |
| CasaOS / Runtipi / Coolify / CapRover | 45-60 | Useful in their niche, not a generic replacement for this host |
| Yacht | 25 | Not recommended due to weak current activity |

## Komodo

Best fit for this system.

Strengths:

- Mature relative to Dockhand and Arcane. Repository created in 2022, latest stable release observed as `v2.2.0` on 2026-05-07, with recent commits in May 2026.
- GPL-3.0, full open-source license.
- Designed as a control plane for servers, builds, deployments, compose stacks, Docker Swarm, automation, audit trails, RBAC, and credentials.
- Strong image lifecycle:
  - Digest-based update polling and auto-update for Stacks and Deployments.
  - Global Auto Update procedure can be scheduled and coordinated with backups.
  - Build resource can build Docker images, push to registries, manage semver/latest/commit tags, push to multiple registries, and use Buildx for multi-platform builds.
  - Server image prune support exists, including `docker image prune -a -f`; server config indicates auto-prune behavior.
- Good multi-host model with Core and Periphery agents. Docs state there is no limit to connected servers.
- Good fit for future expansion to another Linux host, NAS-like host, ARM host, or Swarm.
- Your existing Komodo compose already follows the right direction: separate Core/Periphery, Mongo backend, mounted backups, no Watchtower, manual update bias.

Weaknesses:

- Higher setup complexity than Dockhand or Dockge.
- Adds MongoDB.
- Local deployment now has gitignored `compose.env.local` secrets and has completed first-run setup.
- Current local design uses `/etc/komodo` isolation, which is clean but means existing stacks under `/home/df/workspace/myServices` should be migrated/imported deliberately rather than blindly adopted.
- GUI is strong enough for operations, but not as visually slick as Arcane/Dockhand.

Best use here:

- Make Komodo the source-of-truth manager.
- Keep stacks Git-backed where possible.
- Use `poll_for_updates` broadly.
- Use `auto_update` only for low-risk stateless stacks.
- Keep DB, GPU/AI, NPM, Immich, Nextcloud, Vaultwarden, and torrent/VPN stacks on manual update.
- Keep Portainer for 30 days as fallback while migrating stack-by-stack.

## Dockhand

Best immediate replacement if the priority is "replace Portainer UI quickly with minimal migration."

Strengths:

- Very active. Repository created in late 2025, pushed 2026-06-07, latest release observed as `v1.0.32` on 2026-06-06.
- Strong adoption signals for a young project: about 4.7k GitHub stars and 179 forks observed.
- Modern UI, real-time container management, Compose stack orchestration, Git deploys, webhooks, auto-sync, logs, terminal, file browser, local and remote Docker hosts.
- Directly matches your prepared deployment: your Dockhand compose mounts `/home/df/workspace/myServices`, which is exactly where the existing compose files live.
- Image lifecycle is practical:
  - Container auto-update scheduling exists.
  - Update checks and scheduled tasks exist.
  - Image prune scheduling is present in the scheduler.
  - Recent release notes specifically fixed auto-update behavior around runtime env/label preservation and Git stack path/env handling.
- Docker image manifest supports `linux/amd64` and `linux/arm64`, which covers this host and common ARM hosts.

Weaknesses:

- Business Source License 1.1, not OSI open source until the change date. It is free for personal/internal use, but this is weaker than Komodo GPL or Arcane BSD.
- Optional RBAC is Enterprise, according to the README. For single-user use this is fine, but it matters if the system grows.
- Younger than Komodo and Portainer. The open issue count is high for its age.
- Its image lifecycle is good for pull/update/prune, but not as strong as Komodo for image build/version/registry workflows.

Best use here:

- If you want to feel immediate relief from Portainer, run Dockhand first as a trial on port `55002`.
- Use it to adopt current compose files in `/home/df/workspace/myServices`.
- Keep it out of NPM/public exposure until auth and terminal settings are reviewed.
- If it proves stable after several weeks, it can remain as a secondary UI even if Komodo becomes the main control plane.

## Arcane

Most promising future challenger.

Strengths:

- Very active. Repository created in 2025, latest release observed as `v2.0.0` on 2026-06-07, with commits the same day.
- BSD-3-Clause license.
- Strong GUI direction.
- Strong image lifecycle:
  - Image polling.
  - Auto-update.
  - Scheduled prune for containers/images/volumes/networks/build cache.
  - Trivy-backed vulnerability scans.
  - Auto-heal.
  - Build support, including local Docker and hosted Depot-style builds.
- Remote environment model with direct agents and edge agents.
- Docker image manifest supports `linux/amd64`, `linux/arm64`, and `linux/arm/v7`.

Weaknesses:

- Too fresh for this host as the primary manager. The `v2.0.0` release includes breaking migration guidance.
- Fast-moving projects are useful, but this host has too many critical services to accept early-major-release churn.
- Feature breadth is high, which is attractive but raises operational risk until the project settles.

Best use here:

- Test in parallel, especially for vulnerability scan and GUI quality.
- Re-evaluate after a few minor releases past `v2.0.0`.
- Do not use it as the only manager for NPM, databases, Immich/Nextcloud, or GPU stacks yet.

## Dockge

Good secondary tool, not enough as the replacement.

Strengths:

- MIT license.
- Large community. About 23k GitHub stars observed.
- Simple and pleasant Compose-first UI.
- Supports multiple agents since `1.4.0`.
- Can update Docker images for compose stacks.
- You already have it prepared/running historically.

Weaknesses:

- It intentionally focuses on compose files.
- The README itself says it is not a full Portainer replacement if you need broader Docker features like single-container management, networks, and related resources.
- Image lifecycle is lighter: update images is useful, but not comparable to Komodo or Arcane for build, registry, vulnerability, automation, and lifecycle policy.
- Existing stacks must live under Dockge's stacks directory model unless you remap paths carefully.

Best use here:

- Keep for quick compose edits and a simple UI.
- Do not promote it to primary for this host.

## Other Systems

Not recommended as primary replacement for this host:

- **Rancher / Kubernetes dashboards**: strong if you migrate to Kubernetes, but that is a platform migration, not a Portainer replacement.
- **CasaOS / ZimaOS / Runtipi**: good app-store/home-server panels, not enough for 68 custom compose files and image lifecycle control.
- **Coolify / CapRover**: good PaaS/developer app deployment tools, not ideal for mixed home infrastructure, VPN, media, AI, database, and gateway stacks.
- **Cockpit + Podman**: useful system administration, but not a Docker Compose control plane for this environment.
- **Watchtower / Diun**: useful companions for update detection/automation, but not GUI management systems. Your existing comments already reject Watchtower-style broad auto-update, which is correct for this host.
- **Yacht**: not recommended due to weaker current activity compared with Dockhand, Komodo, Arcane, Dockge, and Portainer.

## Final Decision

Choose **Komodo**.

Reason: this host's real problem is not only "Portainer UI feels bad." The real problem is controlled operation of many source-controlled Compose stacks with image update visibility, safe manual updates, future multi-host support, and auditability. Komodo is the strongest match for that operating model.

Use **Dockhand** if you want the most immediate "Portainer but nicer" experience, especially because your prepared Dockhand compose already mounts the existing `myServices` tree. It is the fastest practical trial, but I would not make it the final source of truth before observing stability for a few weeks.

Use **Arcane** as an evaluation target, not the first production cutover.

## Suggested Migration Plan

1. Keep Portainer running for 30 days as fallback.
2. Keep Komodo running on LAN only while migration is validated.
3. Disable public exposure and review terminal settings before putting it behind NPM.
4. Import or recreate low-risk stacks first:
   - `HelloWorldPage`
   - `speedtest`
   - `easyImage`
   - `homepage`
5. Then migrate medium-risk stacks:
   - monitoring
   - API proxy utilities
   - media helper services
6. Migrate high-risk stacks last:
   - Nginx Proxy Manager
   - Vaultwarden
   - Nextcloud AIO
   - Immich
   - ChatStack
   - GPU-heavy services
   - VPN/torrent stacks
7. For image lifecycle:
   - Enable update polling broadly.
   - Enable auto-update only for stateless low-risk services.
   - Keep manual updates for databases, NPM, Vaultwarden, Nextcloud, Immich, GPU/AI stacks, and anything with external state.
   - Use image prune deliberately. On this host, aggressive pruning saves space but can remove rollback images and cause large image re-pulls.
8. After 30 stable days, stop using Portainer for changes. Keep only Komodo plus optional Dockhand/Dockge as secondary viewers.

## Local Changes Made During Research

Changed:

- `Komodo/docker-compose.yml`
  - `ghcr.io/moghtech/komodo-core:v2.1.2` -> `ghcr.io/moghtech/komodo-core:2.2.0`
  - `ghcr.io/moghtech/komodo-periphery:v2.1.2` -> `ghcr.io/moghtech/komodo-periphery:2.2.0`
- `Komodo/compose.env`
  - `COMPOSE_KOMODO_IMAGE_TAG="v2.1.2"` -> `COMPOSE_KOMODO_IMAGE_TAG="2.2.0"`

Verification:

- `docker buildx imagetools inspect ghcr.io/moghtech/komodo-core:2.2.0` succeeds.
- `docker buildx imagetools inspect ghcr.io/moghtech/komodo-periphery:2.2.0` succeeds.
- `docker compose --env-file compose.env --env-file compose.env.local config --quiet` succeeds.
- `docker compose --env-file compose.env --env-file compose.env.local --profile agent up -d` starts Core, MongoDB, and Periphery.

## Sources

[1] Komodo GitHub repository metadata: https://github.com/moghtech/komodo

[2] Komodo `v2.2.0` release: https://github.com/moghtech/komodo/releases/tag/v2.2.0

[3] Komodo docs, intro: https://github.com/moghtech/komodo/blob/main/docsite/docs/intro.md

[4] Komodo docs, Docker Compose stacks: https://github.com/moghtech/komodo/blob/main/docsite/docs/deploy/compose.md

[5] Komodo docs, automatic updates: https://github.com/moghtech/komodo/blob/main/docsite/docs/deploy/auto-update.md

[6] Komodo docs, builds and image tagging: https://github.com/moghtech/komodo/blob/main/docsite/docs/build.md

[7] Komodo image prune API/type evidence: https://github.com/moghtech/komodo/blob/main/client/core/ts/src/types.ts

[8] Dockhand GitHub repository metadata: https://github.com/Finsys/dockhand

[9] Dockhand `v1.0.32` release: https://github.com/Finsys/dockhand/releases/tag/v1.0.32

[10] Dockhand README and license summary: https://github.com/Finsys/dockhand/blob/main/README.md

[11] Dockhand license: https://github.com/Finsys/dockhand/blob/main/LICENSE.txt

[12] Dockhand scheduler evidence: https://github.com/Finsys/dockhand/blob/main/src/lib/server/scheduler/index.ts

[13] Arcane GitHub repository metadata: https://github.com/getarcaneapp/arcane

[14] Arcane `v2.0.0` release: https://github.com/getarcaneapp/arcane/releases/tag/v2.0.0

[15] Arcane README and license badge: https://github.com/getarcaneapp/arcane/blob/main/README.md

[16] Arcane license: https://github.com/getarcaneapp/arcane/blob/main/LICENSE

[17] Arcane architecture context: https://github.com/getarcaneapp/arcane/blob/main/CONTEXT.md

[18] Arcane scheduled job metadata: https://github.com/getarcaneapp/arcane/blob/main/types/meta/job_metadata.go

[19] Dockge GitHub repository metadata: https://github.com/louislam/dockge

[20] Dockge README: https://github.com/louislam/dockge/blob/master/README.md

[21] Dockge `1.5.0` release: https://github.com/louislam/dockge/releases/tag/1.5.0

[22] Dockge license: https://github.com/louislam/dockge/blob/master/LICENSE

[23] Portainer GitHub repository metadata: https://github.com/portainer/portainer

[24] Portainer `2.39.3 LTS` release: https://github.com/portainer/portainer/releases/tag/2.39.3

[25] Portainer README and license summary: https://github.com/portainer/portainer/blob/develop/README.md

[26] Portainer license: https://github.com/portainer/portainer/blob/develop/LICENSE
