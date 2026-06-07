# DF Decisions Applied

Captured: 2026-06-06.

## Confirmed decisions

| Topic | Decision |
|---|---|
| Exposure model | Public endpoint with authentication/access control and reverse proxy. |
| Hostname | `hp.dfder.tw` |
| Temporary local port | Flexible; use a manageable stable port. Current template uses `33080:3000`. |
| Visual style | Pending final style choice; see `docs/15-visual-style-options.md`. Recommended default: **Obsidian Glass**. |
| First-pass widgets | Attempt to connect every available service that has an official Homepage widget, stable API, or usable health endpoint. Services without official widget should still get service cards and `siteMonitor`; use `customapi` only when a stable endpoint exists. |
| Long-term catalog model | Primarily `services.yaml`, not Docker labels. Labels remain optional for small non-secret discovery only. |
| Heimdall old route | Undecided; keep Heimdall route unchanged during Phase 2 and decide after Homepage is proven. |

## Consequences for Phase 2

1. Homepage should be deployed locally first, then exposed as `hp.dfder.tw` through the reverse proxy.
2. `HOMEPAGE_ALLOWED_HOSTS` must include `hp.dfder.tw` and the local test host/port exactly.
3. The reverse proxy route must have authentication/access control. Homepage itself does not provide auth.
4. Because DF prefers `services.yaml`, the Phase 2 agent should build a complete curated service catalog instead of scattering labels across many compose files.
5. Docker labels are now optional, not the main architecture. Keep `docker.yaml` for container stats/status, but the dashboard catalog is YAML-first.
6. First-pass work should classify all services into one of:
   - official widget configured,
   - card + `siteMonitor`,
   - card only,
   - hidden/deferred because it is too sensitive, stale, or not meaningful for the dashboard.
