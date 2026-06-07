# Security and Threat Model

Homepage will become a map of the homelab. Even if it does not store secrets directly, the page can reveal service names, topology, hostnames, ports, health status, and links to sensitive admin panels. Treat it as an internal operations surface, not a public brochure.

## Assets to protect

| Asset | Risk if exposed | Required control |
|---|---|---|
| Homepage UI | Reveals service topology and clickable admin surfaces. | VPN/LAN only, NPM access list, or Cloudflare Access. |
| Docker socket/API | Can expose container metadata and may become host compromise if write access exists. | Use docker-socket-proxy with read-only operations; `POST=0`. |
| Widget credentials | Can access service APIs. | Store in `.env` / secret files via `HOMEPAGE_VAR_*` or `HOMEPAGE_FILE_*`; never labels. |
| Heimdall DB | Existing descriptions may contain credentials or notes. | Export sanitized fields only by default. |
| NPM DB inventory | Reveals routes and internal upstreams. | Keep generated exports in `inventory/private/`. |
| Git repo | May be pushed/shared later. | `.gitignore`, secret scan, no `.env`, no private inventory. |

## Docker socket proxy posture

Recommended proxy settings are intentionally narrow:

```yaml
environment:
  CONTAINERS: 1
  SERVICES: 1
  TASKS: 1
  POST: 0
```

`CONTAINERS=1` allows Homepage to list containers for discovery/status. `SERVICES=1` and `TASKS=1` are needed if Swarm support is later enabled. `POST=0` blocks write operations through the proxy.

Do not publish the proxy port on the host. Keep it on an internal Docker network only. The current template attaches `dockerproxy` only to `homepage-internal`, while `homepage` also has `homepage-egress` for widget/API calls.

## Labels are public metadata

Docker labels are visible to anyone or anything that can inspect Docker containers. Therefore labels may include:

- group/name/icon/href/description/weight
- non-secret `siteMonitor`
- non-secret widget options only

Labels must not include:

- API keys
- passwords
- bearer tokens
- session cookies
- personal notes copied from Heimdall descriptions

## Reverse proxy requirements

Homepage has no built-in authentication. If exposed outside LAN/Tailscale, it must be protected by one of:

1. NPM access list / Basic Auth.
2. Cloudflare Access.
3. Another authenticated reverse proxy layer.

`HOMEPAGE_ALLOWED_HOSTS` is not authentication. It only checks the Host header for Homepage's API proxy safety. It must include the exact hostnames and ports used by browsers, and should not be set to `*` except for temporary emergency diagnosis.

## Secret scanning gate

Before any commit or deployment handoff, run:

```bash
cd ~/workspace/myServices/hompage
./scripts/scan-secrets.sh
```

The scan intentionally allows placeholder names like `{{HOMEPAGE_VAR_NPM_PASSWORD}}`, but fails on likely literal values.

## TrueNAS / ESXi caution

TrueNAS and ESXi are high-importance infrastructure. Homepage may link to them or show read-only widget data, but later agents should not run mutating commands on those hosts as part of this migration. For TrueNAS widget, use the least-privileged API key available and verify with DF before storing it.
