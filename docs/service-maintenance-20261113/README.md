# Application maintenance, 2026-11-13

This is a sanitized review record. The complete per-service ledger, deployment identities, endpoint catalog, source preimages, credentials-free operational observations and backup evidence remain in the private maintenance workspace. No private endpoints, environment files, account credentials or host mapping are published here.

## Results and accounting

The maintenance accepted **15 container image updates across 14 distinct products**. These are deployment results, not a claim that every component is healthy or that every application version changed. Two accepted updates are image rebuilds of the same application version, and the same agent product was updated on two engines.

| Application | Accepted result |
|---|---|
| Homepage | 2.7.0 → 2.8.0 |
| Glance | Previous deployed digest → 0.8.8 image |
| Jackett | v0.24.3042-ls32 → v0.24.3053-ls34 |
| Jellyfin | ls58 → ls59 image; application remains 12.4.0 |
| Cloudflared | 2026.10.7 → 2026.11.0 |
| Netdata, managed App | 2.12.2 → 2.12.3 |
| AdGuard Home, managed App | 0.107.79 → 0.107.80 |
| Nginx Proxy Manager, managed App | 2.16.0 → 2.17.0, with incident recovery described below |
| n8n | 2.47.3 → 2.47.5 |
| Immich | 3.4.0 → 3.4.1 |
| LobeHub | 2.3.2 → 2.3.3 |
| CLIProxyAPI | 8.0.66 → 8.0.67 |
| OpenTerminal | Updated image; application remains 0.17.7 |
| Portainer Agent | Compatible 2.45.3 image on two existing Compose deployments |

Separate outcomes: one unchanged-image AIO controller repair; one Tailscale chart refresh, 1.4.25 → 1.4.26, retaining application 1.104.4 and its image; and one rejected bridge Node patch rolled back to its original image. A later Tailscale retry correctly failed with “No upgrade available.”

The private ledger reconciles **108 unique observed Docker containers**: 81 on the primary engine, 21 on five other reachable Portainer engines, and six managed App containers on another engine, with no overlap. These form **56 deployment units**, defined as an engine/project pair or an ungrouped container. They are not 56 end-user applications. Four registered engines are unreachable, so their live service counts remain unknown. HA Core and six addons are accounted separately, without assuming they belong to the observed Docker set.

The 57 Homepage links overlap this inventory: 49 refer to existing observed containers. The remaining links include managed Apps, HA, appliance applications, an excluded host management console and one endpoint whose deployed owner was not established. The 86 repository Compose definitions include archived, example, absent and overlapping definitions; file presence was never treated as permission to activate a service.

Container dispositions reconcile to **15 updated, 55 current, 33 held, three existing errors, one repaired and one chart refresh = 108**. HA's existing addon error, appliance holds, unavailable engines and the endpoint with baseline 502 are additional catalog observations, not additional updated containers.

## Validation and limitations

All 57 catalog URLs retain their baseline HTTP statuses: 51 return 200, four return 401, one returns 403 and one retains its pre-existing 502. Authentication, source restrictions, proxy/VPN routing and stopped/absent services were preserved. Application checks include n8n readiness/settings and preserved entity counts; authenticated Jellyfin library listing; Immich version/ping; LobeHub migration success and entity preservation; authenticated OpenTerminal command execution and unauthenticated 401; and authenticated/unauthenticated CLIProxyAPI responses.

CLIProxyAPI returns an empty model catalog on both the previous and updated images. The previous image was tested with the unchanged configuration and read-only auth mount in an isolated namespace, using a cached client sidecar and stdin for its credential. No credential extension conversion, account mutation or live provider inference was performed. LobeHub's restored preimage and upgraded database both have one user, zero sessions and four messages; its schema grew from 229 to 233 tables and startup reports migration success. Browser login and paid model calls were not exercised.

The bridge's original Node image is restored and an authenticated document-library read returns 207 while an unauthenticated request returns 401. Sustained declared `/__health` checks on that original image still produced **five 200s, one 503 and five approximately 10-second timeouts across eleven samples**. Docker's healthy label is not evidence of steady upstream readiness. The rejected patch is excluded from the update count. The handler waits on remote storage through the application's admission/backoff mechanism; the evidence cannot attribute the intermittent behavior solely to the Node patch. A separate investigation should measure queue delay and upstream response/backoff under load. Maintenance did not redesign accounts, the browser or routing to conceal the limit.

Uptime Kuma remains **2.5.0**, with supported security target 2.5.11 held. Bounded online backup preparation exceeded deadlines. Earlier transfers failed digest validation; the final transfer matched its remote digest but archive extraction failed with a truncated gzip stream. No complete archive restore, restored SQLite integrity result or independent live/preimage count equality was established. A later attempt should use a short, scoped quiescence window if an online snapshot cannot finish, then prove the restore before deploying. No Uptime container recreation or source update occurred.

Other concrete holds include a second NPM instance without a verified compatible data/config restore, a remote sub2api update with two database migrations, AIO children requiring its coordinated updater and full-instance recovery, explicitly pinned routing/Komodo releases, prerelease/custom-fork changes, and an agent without independent recovery access. Existing remote proxy/VPN unhealthy checks and a restarting application are recorded as existing errors; maintenance added no direct proxy fallback. The private ledger provides each item's exact target, owner, reason, validation and rollback reference.

## NPM incident and rollback limits

The first managed-App upgrade failed because a mounted older global nginx configuration hid the new upstream `$forward_host` definition. An initial image rollback exposed a database migration incompatibility. Forward recovery installed the exact 2.17 stock configuration with only the original three proxy timeout values retained at 150 seconds. The companion `npm-global-nginx.conf` is that generic configuration, without live host definitions or certificates.

The target image passed `nginx -t` with the real persistent mounts and correctly initialized ephemeral runtime directories before the supported managed-App upgrade. Fresh acceptance checks confirm a healthy container, backend/admin/API responses, valid nginx configuration, SQLite integrity and restored ingress. A protected API's permission denial is an expected unauthenticated denial, distinct from a filesystem permission failure.

Both saved recovery SQLite candidates contain the 2.17 migration in the populated `migrations` table. An earlier query of the empty `knex_migrations` table was a false negative and was corrected. **Neither saved candidate proves a compatible 2.16 downgrade.** An image-only downgrade is unsafe; restoring an older compatible application database would need independent validation. A retained snapshot and sample file recovery checks are not a claim that a full old-application restore was rehearsed.

## Deployment guard and the media recreation incident

Portainer's explicit Git redeploy uses `ForceCreate=true`; disabling image repulls does not prevent recreation from effective source. The initial media batch therefore recreated six containers while changing only two images. Danmu API, AutoBangumi, Jellyseerr and JProxy were recreated with unchanged images. Their running state, recovered endpoint responses and actual old/current container IDs are recorded privately. This was an unintended interruption, not four additional upgrades.

The corrected guard uses current runtime state and the effective active source, requires explicit approval of the complete recreation footprint, rejects absent-service activation/control-plane interruption/source drift, repeats checks after bounded image pulls, and compares all outside IDs after deployment. Checks reject the original unsafe media footprint and accept isolated source profiles. Subsequent deployments preserved 79 outside IDs for n8n, 78 for Immich, 79 for the bridge batch/rollback and 78 for ChatStack. The two remote agent updates preserved every other container ID on their engines.

## Persisted ChatStack owner and future updates

ChatStack remains under its original Portainer Git stack, workflow and shared source relationship. Its Git ref is `refs/heads/maintenance/service-updates-20261113`, with `ChatStack/maintenance-20261113.override.yml` persisted in `AdditionalFiles`. Exactly three targets participate: LobeHub, CLIProxyAPI and OpenTerminal. Target image pins live in that override; the main Compose file contains no unrelated pending feature changes.

The existing 59 environment entries and auto-update object were preserved exactly, including the undisclosed webhook. Its interval remains **5m**, `ForceUpdate=false` and `ForcePullImage=false`. Owner, endpoint, workflow, source credentials/TLS relationship and resource control were retained. An actual disposable Git-stack fixture proved the supported existing-owner override update and was removed afterward.

**While this override remains, held services stay running but are excluded from future deployments through this owner**, including automatic deployments. The absent legacy bot remains absent. This is a deliberate, persisted maintenance restriction, not a replacement manager.

The final reconciliation checks all declared settings, including environment, image, mounts, ports, command/entrypoint, network, dependencies/profiles and resource/security settings. The three targets match their intended runtime. Held runtime/source drift includes the two Lilac local-password hashes and existing webhook settings, plus the WebUI display name; these pre-existing/pending values were preserved in running containers and private preimages rather than merged as unrelated source work.

To restore normal whole-stack deployment semantics, first reconcile that held drift and other pending work, review the complete footprint including absent definitions, establish the relevant data recovery path and schedule control-plane continuity. Then remove `AdditionalFiles` through the **same supported existing-owner API** as part of the separately reviewed change. Do not automatically remove the override and redeploy the drifted control plane. No duplicate stack, container adoption, hand-edited Portainer checkout or direct Compose deployment of ChatStack was used.

## Review and evidence

The original dirty checkout is preserved. Source changes are isolated on the maintenance branch and use the existing deployment owners. The private ledger records full old/current image identities, supported targets, owners/source commits, health, validation and rollback references for every observed container, plus HA, the Homepage crosswalk and repository-only definitions.

Independent Codex review covers the whole task-added branch diff, confidentiality, actual deployment evidence, backup/restore limits, counts, non-target continuity, the persisted override and these known limitations. The final private verdict is retained with the operational ledger; no private ledger or secret-bearing runtime artifact belongs in this public repository.
