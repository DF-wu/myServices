# Cypht

Standalone webmail aggregator: Cypht 2.14.0 and a dedicated MariaDB 11.8.9 LTS.
Both images are pinned to registry index digests with Linux AMD64 support.
Database authentication, sessions and user settings live in MariaDB; no users-file
mount is needed. Mail remains on the configured IMAP servers: this is **not a mail
server or mailbox backup**. No MX changes or inbound mail ports are needed.

## Prepare the Docker host

Run on the target Docker host, from a checkout of this recipe at the revision you
will deploy. These commands create dedicated directories only; never recursively
change ownership or permissions of shared `/mnt/appdata` or its parent directories.

```sh
sudo install -d -m 0700 /home/df/_serverDataAndScript/cypht/mysql
sudo install -d -m 0750 /mnt/appdata/Cypht/attachments
sudo install -m 0644 Cypht/nginx.conf /home/df/_serverDataAndScript/cypht/nginx.conf
```

Keep the database on **local disk**, not the NFS appdata mount. Override
`DB_DATA_DIR` if necessary. The MariaDB entrypoint initializes and owns its dedicated
data directory. Cypht starts as root and chowns its attachment directory to
`www-data` (verified UID/GID 33:33 in the pinned image). Do not set PUID/PGID or
force a non-root container user. On NFS with root squashing, have the storage
administrator pre-create only the dedicated attachment directory as UID/GID 33:33
with mode 0700; startup must still be able to perform the entrypoint's chown.
If that is not possible, set `ATTACHMENT_DIR` to a dedicated local directory instead.
Attachment staging is temporary upload/download working data, not the mail archive;
the bind preserves in-progress files across recreation but is not core account state.

## Variables and first account

Use `.env.example` as the variable checklist. For local Compose, copy it to `.env`
and protect that file (`chmod 600 .env`); never commit it. For Portainer, supply
stack environment variables explicitly. Infisical can store the secrets but this
recipe has no automatic Infisical integration.

- `DB_PASSWORD` and `DB_ROOT_PASSWORD`: separate, unique random values (generate
  at least 32 random alphanumeric characters each). Blank/unset values fail Compose
  interpolation. There are no default passwords. Operators must not use sample or
  placeholder credentials. Changing these variables does not rotate an existing DB.
- `BIND_IP`: the private Docker-host interface address reachable by the trusted
  reverse proxy. Required; no wildcard default. Check that `HTTP_PORT` (58090 by
  default) is free on that host before deployment. Loopback is suitable only when
  the proxy is on this host; it cannot serve a proxy on another machine.
- `NGINX_CONFIG_PATH`: absolute host path to the staged, tracked `nginx.conf` above.
  It must exist as a regular file before deployment.
- First boot only: set **both** `AUTH_USERNAME` and `AUTH_PASSWORD`. Use only ASCII
  letters and digits for both, with a random password of at least 32 characters.
  Upstream `setup_system.sh` passes them unquoted, so spaces, glob characters and
  other punctuation are unsupported by this bootstrap procedure.

Startup migrates the DB and creates that account when `USER_CONFIG_TYPE=DB` and
`AUTH_USERNAME` is nonempty. Verify login, then remove/empty **both** bootstrap
variables and recreate Cypht through Portainer. Empty values are intentionally
valid during routine operation. Existing accounts are skipped: changing bootstrap
variables does **not** reset a password. If both are empty on an empty database,
startup works but no account is created; supply the initial pair and recreate.

## Portainer Git deployment

Create a **Docker Standalone** Git stack on the target endpoint using repository
`https://github.com/DF-wu/myServices`, the reviewed branch/revision, and Compose path
`Cypht/docker-compose.yml`. Import the variables above in Portainer's environment
editor, complete preparation, then deploy. Do not deploy an unmodified example.

This recipe deliberately uses absolute host binds. It does not rely on Portainer
Business Edition relative-path support or the location of Portainer's Git checkout.
Stage `nginx.conf` on the **Docker endpoint host**, not inside Portainer's container.
On later Git updates, install the matching tracked config at the same path **before**
redeploying/recreating Cypht. A Git pull alone does not update that host file;
recreation also ensures a replaced bind-mounted file is reopened. Missing config
fails rather than silently creating a directory.

## HTTPS proxy boundary

Serve at the hostname root, through the existing HTTPS ingress path (CDN → TLS
reverse proxy → private host port). The reverse proxy forwards HTTP to
`BIND_IP:HTTP_PORT`, preserves the original `Host`, overwrites or strips client-supplied
`X-Forwarded-Host`, and redirects public HTTP to HTTPS. Use end-to-end verified TLS
between the CDN and reverse proxy. Bypass CDN caching for **all** paths, including
login, AJAX and attachments.

The tracked Nginx config follows the image's PHP-FPM layout and sets FastCGI
`HTTPS=on` unconditionally. Cypht 2.14.0 only checks `HTTPS` / `REQUEST_SCHEME`,
not `X-Forwarded-Proto`; without this adjustment session cookies can lack `Secure`.
This is an **HTTPS-only upstream convention**, not header-based TLS detection.
Arbitrary forwarded headers cannot change it. Direct plain HTTP browser access is
unsupported, and the backend must not be reachable by untrusted clients.

Before exposing ingress, restrict the published Docker port to the proxy's source
address using Docker-aware firewall/DOCKER-USER rules or equivalent network ACLs.
Binding a private IP alone is not an allowlist; account for Docker bypassing ordinary
host INPUT firewall rules. Do not forward the backend port from the WAN. The DB has
no published port and is on a stack-private internal network; Cypht has a separate
network for outbound IMAP/SMTP/HTTPS. Keep `DISABLE_ORIGIN_CHECK=false`. Resolve
Host/origin/proxy mistakes instead of disabling the check. This recipe makes no
proxy, firewall, DNS or mailbox changes itself. Upstream checks origin during
new-session authentication; do not treat it as a general proxy origin firewall.

## Acceptance

1. DB becomes healthy; Cypht starts without migration/configuration errors.
2. Through the final HTTPS hostname, login succeeds and `hm_session` / `hm_id`
   cookies carry `Secure` and `HttpOnly`. A login POST from an unrelated Origin is
   rejected. Check that CDN responses are not cached.
3. Add a test IMAP/SMTP account, explicitly save settings, log out, then log in
   from a fresh browser session. Recreate Cypht and repeat: settings must survive.
   Verify send/receive with the operator's test mailbox only.
4. Remove bootstrap variables, redeploy and verify the same login still works.
5. Confirm the backend is accessible only from the proxy and DB port is unpublished.

OAuth provider registration is separate and out of scope. Upstream names are
`GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_CLIENT_URI`; `OUTLOOK_CLIENT_ID`,
`OUTLOOK_CLIENT_SECRET`, `OUTLOOK_CLIENT_URI`; and `OFFICE365_CLIENT_ID`,
`OFFICE365_CLIENT_SECRET`, `OFFICE365_CLIENT_URI`. Add the selected variables to the
Cypht service environment and Portainer. Use the provider and Cypht documentation
to register the actual redirect URI; do not assume a callback URL from this recipe.

## Backup, restore and upgrade

Keep encrypted off-host backups of a **consistent logical database dump**, the
recipe revision, staged Nginx config, and references to retrievable DB secrets.
Cypht stores sensitive user/server settings in the DB; protect dumps accordingly.
Optionally back up attachment staging while Cypht is stopped. Do not copy live
MariaDB data files as a substitute for a consistent backup.

For local Compose (or equivalent commands against this stack's containers on the
endpoint), stop Cypht to freeze writes, dump InnoDB tables, then restart it. Store
the dump outside this public checkout with restrictive permissions (replace
`/secure/backup` below with an existing protected backup directory). The variable
below is expanded **inside** the dedicated DB container, not printed in a command:

```sh
umask 077
docker compose stop cypht
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -uroot --single-transaction --routines --events --triggers cypht' > /secure/backup/cypht.sql
# Confirm the dump command succeeded and the file is nonempty before proceeding.
docker compose start cypht
```

Restore-test off-host on an isolated stack: initialize an empty dedicated DB with
the pinned MariaDB image and original DB credentials, leave Cypht stopped, import
the dump using `MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot cypht` inside the
DB container, restore config/optional files with the dedicated ownership above,
then start the matching Cypht image **without bootstrap credentials**. Verify login
and saved settings. Never point the test at production mailbox operations.

Before upgrades, read upstream migration/release notes, take and verify a backup,
and test the new image/digest on a restored isolated DB. Update explicit tags and
digests together, stage matching Nginx config, then redeploy. Entrypoint runs
`setup_database.php` on every start. After schema changes, rolling back only the
app image is insufficient: restore the matching pre-upgrade DB backup and recipe.
Do not delete persistent directories or use volume removal as an upgrade step.

## Verified upstream references

- Cypht v2.14.0 resolves to immutable commit
  [`06395f146096bcad8d2594b27dc56ee553a36286`](https://github.com/cypht-org/cypht/tree/06395f146096bcad8d2594b27dc56ee553a36286/docker).
  The official image was built 2026-11-06; its registry index digest is pinned in
  Compose. The [deprecated cypht-docker image](https://github.com/cypht-org/cypht-docker/blob/554b38d972a54f0c85cc7d856a3f552eeb68b63f/README.md)
  and old `CYPHT_*` variables are unused.
- [Bootstrap](https://github.com/cypht-org/cypht/blob/06395f146096bcad8d2594b27dc56ee553a36286/scripts/setup_system.sh),
  [account creation](https://github.com/cypht-org/cypht/blob/06395f146096bcad8d2594b27dc56ee553a36286/lib/account_manager.php),
  [TLS detection](https://github.com/cypht-org/cypht/blob/06395f146096bcad8d2594b27dc56ee553a36286/lib/request.php),
  [cookies](https://github.com/cypht-org/cypht/blob/06395f146096bcad8d2594b27dc56ee553a36286/lib/session_base.php),
  [environment names](https://github.com/cypht-org/cypht/blob/06395f146096bcad8d2594b27dc56ee553a36286/.env.example).
- MariaDB 11.8 is [community-maintained through June 2028](https://github.com/mariadb-corporation/mariadb-docs/blob/8c8b9f3ab211561eb0c2b0dc8a59b5fc2d38e47e/release-notes/community-server/11.8/11.8.9.md).
  The pinned 11.8.9 AMD64 image identifies official build revision
  [`bdfe641466a5312bb97d06a1a4e1fb411c49e6b6`](https://github.com/MariaDB/mariadb-docker/tree/bdfe641466a5312bb97d06a1a4e1fb411c49e6b6/11.8).

## Recipe validation (2026-11-06)

Compose interpolation and missing/blank required-variable checks passed. With
pinned images, dummy credentials, temporary local storage and no published ports:
startup/health, Nginx syntax, login, Secure/HttpOnly cookies, cross-origin login
rejection, saved preference persistence after logout/fresh login, and DB/app
recreation without bootstrap credentials passed. The temporary stack was removed.
Portainer, the real proxy/CDN/firewall path, NFS permissions, mailbox/OAuth flows,
and off-host backup restoration require operator acceptance; they were not exercised.
