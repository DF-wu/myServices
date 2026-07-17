# Cloudflare ingress runbook — `hp.dfder.tw` + `glance.dfder.tw` (DEFERRED)

Owner decision (2026-07-01): **do not configure public ingress yet.** This document
captures everything needed to do it later in one pass. Nothing here has been applied.

## How ingress works here

`cloudflared` runs as a container started with
`tunnel --no-autoupdate run --token <CONNECTOR_TOKEN>` — a **remotely-managed
(token-based) tunnel**. That means the public-hostname → local-service mapping lives
in **Cloudflare's control plane** (Zero Trust dashboard / API), *not* in a local
`config.yml`. There is no ingress file to edit on the box.

Many `*.dfder.tw` hostnames already route through this same tunnel (e.g. `immich`,
`photo`, `crs`, `bifrost`), so adding two more follows the existing, proven pattern.

### Known identifiers
| Item | Value |
|---|---|
| Zone (domain) | `dfder.tw` |
| Cloudflare account tag | `6ad156731ffe6ed1a38f42a10f3bf510` |
| Tunnel ID | `54196078-f17c-4b50-85de-06ff5b6ee527` |
| Tunnel CNAME target | `54196078-f17c-4b50-85de-06ff5b6ee527.cfargotunnel.com` |
| Host (axolotl) LAN IP | `192.168.10.13` |
| Homepage origin | `http://192.168.10.13:33080` |
| Glance origin | `http://192.168.10.13:33081` |

> The **connector token** (in the cloudflared compose `--token`) is sensitive and is
> deliberately not reproduced here. It is *not* an API token and cannot edit ingress.

### Auth requirement
Homepage has **no built-in auth**; Glance's auth is basic. Public exposure MUST sit
behind **Cloudflare Access** (Zero Trust → Access) so only you can reach them.

---

## Method A — Cloudflare dashboard (no API token needed)

1. **Zero Trust → Networks → Tunnels →** open tunnel `54196078…` **→ Public Hostname
   → Add a public hostname:**
   - `hp` . `dfder.tw` → Service **HTTP** `192.168.10.13:33080`
   - `glance` . `dfder.tw` → Service **HTTP** `192.168.10.13:33081`

   This auto-creates the proxied DNS `CNAME` records.
2. **Zero Trust → Access → Applications → Add an application → Self-hosted** (one per
   host): application domain `hp.dfder.tw`, then `glance.dfder.tw`. Add an **Allow**
   policy scoped to your identity (email / Google / etc.).
3. **Verify** from off-box: `curl -I https://hp.dfder.tw` → expect a Cloudflare Access
   challenge (302 to `*.cloudflareaccess.com`), then 200 after login.

---

## Method B — Cloudflare API

Create an API token with: **Account › Cloudflare Tunnel › Edit**, **Zone › DNS › Edit**
(zone `dfder.tw`), and **Account › Access: Apps and Policies › Edit**. Then:

```bash
ACCOUNT=6ad156731ffe6ed1a38f42a10f3bf510
TUNNEL=54196078-f17c-4b50-85de-06ff5b6ee527
TOKEN=<your-cloudflare-API-token>   # NOT the connector token

# 1) Fetch current ingress (so you can append, not overwrite)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/cfd_tunnel/$TUNNEL/configurations" | jq .

# 2) PUT the full ingress list = existing rules + these two, keeping the 404 catch-all LAST:
#    { "hostname": "hp.dfder.tw",     "service": "http://192.168.10.13:33080" }
#    { "hostname": "glance.dfder.tw", "service": "http://192.168.10.13:33081" }
#    { "service": "http_status:404" }   <-- must remain the final entry
curl -s -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/cfd_tunnel/$TUNNEL/configurations" \
  --data @tunnel-config.json

# 3) DNS CNAME (proxied) for each host — replace ZONE_ID with dfder.tw's zone id
ZONE=<dfder.tw-zone-id>
for h in hp glance; do
  curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records" \
    --data "{\"type\":\"CNAME\",\"name\":\"$h\",\"content\":\"$TUNNEL.cfargotunnel.com\",\"proxied\":true}"
done
```

Then create the **Access application + Allow policy** for each host (Zero Trust Access
API, or just do that step in the dashboard).

**Critical:** step 2 replaces the *entire* ingress array. Always GET first, append the
two rules **before** the trailing `{"service":"http_status:404"}`, and PUT the whole list.

---

## After enabling

- Homepage: `HOMEPAGE_ALLOWED_HOSTS` already includes `hp.dfder.tw` (in `.env`). If you
  changed it, `docker compose restart homepage`.
- Glance: `server.proxied: true` is already set in `config/glance.yml`. Add
  `glance.dfder.tw` to any allowlist if you later enable Glance auth.
- Verify both: `curl -I https://hp.dfder.tw` and `curl -I https://glance.dfder.tw`.

## Rollback
Delete the two public hostnames from the tunnel (dashboard) or PUT the ingress list
without them; delete the two DNS `CNAME` records; remove the Access apps. No local
service change is needed — the containers keep serving on `:33080` / `:33081`.
