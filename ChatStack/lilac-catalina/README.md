# Catalina native Discord mirror

`LILAC_NATIVE_DISCORD_WEBHOOK_URL` is an optional Core environment variable for
mirroring native conversations to Discord. Use a Discord incoming webhook URL
for an ordinary text channel. Store the actual value **only in the Portainer
stack Environment**; never put it in Git, documentation, or checkout env files.

`ChatStack/docker-compose.yml` forwards this variable only to `lilac-catalina`.
It is not forwarded to `lilac-claudia`. An unset or empty value resolves to an
empty string and disables the mirror.

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
does not refresh its configured environment. Coordinate any Catalina update with
the owner and do not redeploy the entire shared stack for this setting.
