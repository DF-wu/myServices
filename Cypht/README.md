# Cypht

Webmail aggregator using `cypht/cypht:latest` and the owner-selected `mariadb:10`.
This simplified recipe is for a fresh installation, not an existing-database
migration. Mail stays on the configured providers; Cypht is not a mail server.

## Before deployment

Account bootstrapping remains owner-managed.

Deploy from Git through Portainer using `Cypht/docker-compose.yml`; supply stack
variables in Portainer's Environment editor. A local `.env` or shell environment
is not automatically passed to Portainer. Use [`.env.example`](.env.example) as the
variable checklist and keep actual values private.

- MariaDB stores data in the project-scoped local `cypht-db` volume at
  `/var/lib/mysql`. Its port is not published. The DB credentials are literal
  Compose settings; `DB_PASSWORD` and `DB_ROOT_PASSWORD` are not wired overrides.
- Cypht publishes HTTP port 80 on host `HTTP_PORT`, default **58090**, using the
  normal host bind. There is no `BIND_IP` option in this recipe.
- The current Compose file includes an attachment staging bind to
  `/var/lib/hm3/attachments`. `ATTACHMENT_DIR` selects its host source; unset or
  empty uses the existing Compose path fallback and does not remove the bind.
  Ensure that dedicated directory permits the image's ownership changes and writes.
- `AUTH_USERNAME` unset or empty uses the existing Compose username fallback.
  `AUTH_PASSWORD` unset or empty falls back to `DF_PASSWORD`. Clearing these
  variables does not disable bootstrap; changing them does not reset an existing
  account password.

The stock image's Nginx configuration is used. `DB_DATA_DIR` and
`NGINX_CONFIG_PATH` are obsolete options, and the tracked `nginx.conf` is not mounted.

## Remote HTTPS

Use the existing Nginx Proxy Manager on TrueNAS to terminate TLS:

1. Create a proxy host for `<chosen-hostname>` with a certificate valid for that
   hostname, and enable **Force SSL**.
2. Set the upstream scheme to **HTTP**, forward hostname/IP to
   `<axolotl-LAN-address>`, and forward port to the published `HTTP_PORT`
   (**58090** unless changed).
3. From outside the LAN, use the intended private access path or existing approved
   proxied ingress to open that hostname. Confirm HTTP redirects to HTTPS, the
   browser trusts the certificate, and signing in and navigating Cypht work normally.

HTTPS ends at the proxy; the stock Cypht backend remains HTTP. No custom Nginx
file, cookie directives, HSTS configuration or bind-address change is required as
part of this remote HTTPS setup. Keep origin checking enabled. This is guidance
for a future deployment, not a live proxy or network change.

## Status and data safety

The simplified recipe has not been verified end to end. Inspection found no Cypht
container, listener on the default HTTP port or matching proxy host. Earlier tests
used a different recipe with custom Nginx and a different MariaDB version; they do
not establish remote HTTPS or login success for this recipe.

Keep the DB volume when recreating the stack. Once accounts exist, retain encrypted
off-host logical DB backups and the matching Cypht login secret versions needed to
read saved settings. Test recovery on an isolated disposable database, never against
production mailboxes. Attachment staging is temporary working data, not a mailbox
backup.
