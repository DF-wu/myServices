# Lilac native Discord mirror

`LILAC_NATIVE_DISCORD_WEBHOOK_URL` is an optional Core environment variable for
mirroring native conversations to Discord. Use a Discord incoming webhook URL
for an ordinary text channel. Store the actual value **only in the Portainer
stack Environment**; never put it in Git, documentation, or checkout env files.

## Per-instance destinations

Both Lilac Core instances in `ChatStack/docker-compose.yml` receive the standard
runtime variable `LILAC_NATIVE_DISCORD_WEBHOOK_URL` through separate stack inputs:

| Service | Portainer stack variable | Unset behavior |
| --- | --- | --- |
| `lilac-catalina` | `LILAC_CATALINA_NATIVE_DISCORD_WEBHOOK_URL` | Falls back to the existing `LILAC_NATIVE_DISCORD_WEBHOOK_URL`, or empty if absent |
| `lilac-claudia` | `LILAC_CLAUDIA_NATIVE_DISCORD_WEBHOOK_URL` | Empty; never falls back to the generic variable |

An explicitly empty instance variable disables that instance's mirror. Catalina's
fallback applies only when its instance variable is unset, preserving existing
configuration while allowing an empty override to disable it. Unset or empty
runtime values disable mirroring. Destinations are per instance so a saved
Catalina destination cannot silently activate Claudia on the same webhook.
Configure each desired destination explicitly; no new webhook is provisioned by
this wiring.

The mirror is best-effort and process-local, with no history backfill. It is not
a durable delivery queue or an archive.

## Owner-directed activation through Portainer

The existing Git-backed ChatStack stack uses `ChatStack/docker-compose.yml`,
tracks `refs/heads/master`, and has a five-minute Git auto-poll interval.
**Merging the wiring change can therefore trigger a container update and mirror
activation** if the stack environment already contains a webhook value. Follow
the owner's activation direction before merging; merge is not a preparation-only
step with this configuration.

Changing the stored stack environment alone does not change a running process's
environment. Applying a changed value requires a restart/recreation that supplies
the new environment through Portainer; a plain restart of an existing container
does not refresh its configured environment. Coordinate any instance update with
the owner and do not redeploy the entire shared stack for this setting.
