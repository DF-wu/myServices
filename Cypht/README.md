# Cypht

Standalone webmail aggregator using `cypht/cypht:latest` and a dedicated
`mariadb:latest`. This procedure starts with a **fresh installation and empty
database directory**; it is not an in-place MariaDB major-version migration.
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
`www-data` (verified UID/GID 33:33 in the tested image). Do not set PUID/PGID or
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
3. With authorized test accounts from **two providers**, explicitly save settings,
   log out, then log in from a fresh browser session. Recreate Cypht and repeat:
   settings must survive. Verify the combined inbox, read/unread and other flags,
   folder operations, sending and sent-folder mapping for each provider, attachment
   upload/download, and mobile-browser use through the final HTTPS hostname.
4. Remove bootstrap variables, redeploy and verify the same login still works.
5. Confirm the backend is accessible only from the proxy and DB port is unpublished.

These are deployment acceptance checks, not claims of exercised mailbox flows.
Real-account onboarding, OAuth provider registration and attachment-bind redesign
are separate and out of scope. Upstream names are
`GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_CLIENT_URI`; `OUTLOOK_CLIENT_ID`,
`OUTLOOK_CLIENT_SECRET`, `OUTLOOK_CLIENT_URI`; and `OFFICE365_CLIENT_ID`,
`OFFICE365_CLIENT_SECRET`, `OFFICE365_CLIENT_URI`. Add the selected variables to the
Cypht service environment and Portainer. Use the provider and Cypht documentation
to register the actual redirect URI; do not assume a callback URL from this recipe.

## Backup, restore and upgrade

No existing Cypht data needs migration for this fresh installation. Once data
exists, keep encrypted off-host backups of a **consistent logical database dump**,
the recipe revision, staged Nginx config, deployed image digests, and references to
securely retrievable DB secrets **and the matching Cypht login secret for each
retained backup**. Saved settings are encrypted with the login password; a DB dump
and a newer password alone may not unlock an older backup. Keep secret versions in
a protected secret manager, never in this repository or plaintext backup manifests.
Optionally back up attachment staging while Cypht is stopped. Do not copy live
MariaDB data files as a substitute for a consistent backup.

For local Compose (or equivalent commands against this stack's containers on the
endpoint), run the following in **sh** with Cypht initially running. Replace
`/secure/backup` with an existing protected backup directory outside this checkout.
Each run creates a private unique directory; only a successful, nonempty dump is
published as `database.sql`. A failed attempt removes its partial dump, preserves
previous backups, and attempts to resume Cypht even if stopping/dumping fails or a
catchable signal arrives. A restart failure returns failure and requires operator
intervention; no trap can recover from power loss or SIGKILL. Check the exit status
and restore-test the artifact before considering it a usable backup.

```sh
(
    set -eu
    umask 077
    backup_dir=$(mktemp -d /secure/backup/cypht.XXXXXXXX)
    finish() {
        status=$?
        trap - 0 HUP INT TERM
        if ! rm -f "$backup_dir/partial.sql"; then status=1; fi
        rmdir "$backup_dir" 2>/dev/null || : # Keep a published backup.
        if ! docker compose start cypht; then
            echo 'ERROR: resume Cypht manually before leaving maintenance' >&2
            status=1
        fi
        exit "$status"
    }
    trap finish 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    docker compose stop cypht
    docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -uroot --single-transaction --routines --events --triggers cypht' > "$backup_dir/partial.sql"
    test -s "$backup_dir/partial.sql"
    mv "$backup_dir/partial.sql" "$backup_dir/database.sql"
    printf 'Backup: %s\n' "$backup_dir/database.sql"
)
```

For a supported login-password change, use upstream's
[`scripts/update_password.php`](https://github.com/cypht-org/cypht/blob/v2.14.0/scripts/update_password.php)
with **username, old password and new password** in that order. It authenticates,
decrypts and re-encrypts saved settings. Omitting the old password is a destructive
reset, not a credential rotation; do not confirm a decryption-failure override.
Use a protected administrative session, avoid shell history/process-list exposure,
and verify the success message and saved settings (the script can report errors
without a nonzero exit). Preserve the old secret version for retained backups;
changing bootstrap variables does not perform this flow.

Restore-test off-host on a disposable isolated stack. **Before the restored app's
first boot**, enforce default-deny outbound provider access, including IMAP, SMTP
and HTTPS/OAuth (and IPv6); allow only the isolated DB and test client as needed.
An internal-only test network without any outbound attachment is one option.
Do not rely on avoiding clicks: [restored settings](https://github.com/cypht-org/cypht/blob/v2.14.0/modules/core/handler_modules.php#L764-L778)
can trigger [background requests](https://github.com/cypht-org/cypht/blob/v2.14.0/modules/imap/site.js#L1310-L1319).
Initialize an empty dedicated DB with the recorded recovery image and original DB
credentials, leave Cypht stopped, import the dump using
`MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot cypht` inside the DB container,
restore config/optional files with the dedicated ownership above, then start the
matching Cypht image **without bootstrap credentials**. Verify login with the
backup's matching secret and readable saved settings while provider egress remains
blocked. Never point the drill at production mailbox operations.

Before pulling updates, record each running container's image ID and repository
digest (`docker inspect --format '{{.Image}}' CONTAINER` and
`docker image inspect --format '{{json .RepoDigests}}' IMAGE_ID`) in the protected
backup inventory. Keep these recovery references and access to the images;
**Compose remains on `latest`**, with no digest pins or image overrides. Read
upstream migration/release notes, take and verify a backup, pull and record the new
resolved digests, and test on a restored isolated DB before redeploying. MariaDB
`latest` can cross major versions: validate the supported upgrade path separately;
fresh initialization does not prove an existing data directory can be upgraded.
Stage matching Nginx config before recreation. Entrypoint runs `setup_database.php`
on every start. After schema changes, rolling back only the app image is
insufficient: restore the matching pre-upgrade DB backup, images and recipe in an
isolated recovery procedure. Do not delete persistent directories or use volume
removal as an upgrade step.

## Verified upstream references

- Cypht v2.14.0 resolves to immutable commit
  [`06395f146096bcad8d2594b27dc56ee553a36286`](https://github.com/cypht-org/cypht/tree/06395f146096bcad8d2594b27dc56ee553a36286/docker).
  This is a source reference for the tested behavior, not an image pin. The [deprecated cypht-docker image](https://github.com/cypht-org/cypht-docker/blob/554b38d972a54f0c85cc7d856a3f552eeb68b63f/README.md)
  and old `CYPHT_*` variables are unused.
- [Bootstrap](https://github.com/cypht-org/cypht/blob/06395f146096bcad8d2594b27dc56ee553a36286/scripts/setup_system.sh),
  [account creation](https://github.com/cypht-org/cypht/blob/06395f146096bcad8d2594b27dc56ee553a36286/lib/account_manager.php),
  [TLS detection](https://github.com/cypht-org/cypht/blob/06395f146096bcad8d2594b27dc56ee553a36286/lib/request.php),
  [cookies](https://github.com/cypht-org/cypht/blob/06395f146096bcad8d2594b27dc56ee553a36286/lib/session_base.php),
  [environment names](https://github.com/cypht-org/cypht/blob/06395f146096bcad8d2594b27dc56ee553a36286/.env.example).
- [Official MariaDB image initialization and healthcheck documentation](https://github.com/MariaDB/mariadb-docker).

## Recipe validation (2026-11-21)

Compose rendering resolves `cypht/cypht:latest` and `mariadb:latest`; blank required
variables fail. A fresh disposable Linux AMD64 stack used dummy credentials,
temporary local binds and no published ports. The pulled images identified Cypht
2.14.0 and MariaDB 13.0.2, with repository digests:

- Cypht: `sha256:141ec827dc5faf01a056a6d61c49c7a43366e967b7535c254b39ff6b7b26a4e1`
- MariaDB: `sha256:54f493ea0d60b621a5bff84e5b20100f8b86b6efa6b79158e04756c5194a5e4d`

These are test evidence, not Compose pins. Fresh DB initialization/health, app
migration/boot, Nginx syntax, same-origin login, Secure/HttpOnly cookies,
cross-origin authentication rejection, saved preference retrieval in a fresh
session, and recreation of both containers without bootstrap credentials passed.
HTTP requests ran only inside the disposable network, carrying the cookies as a
TLS proxy would; this did not exercise a public TLS ingress or browser UI.
The documented backup snippet produced distinct protected artifacts; an injected
failed dump preserved previous artifact hashes, removed partial output and resumed
Cypht. Empty-dump, stop-failure and resume-failure paths also returned failure
without changing earlier dumps; resume failure was injected after a real start.
A successful dump imported into a disposable scratch schema. The temporary stack and its data were removed after testing.

Portainer, proxy/CDN/firewall behavior, NFS permissions, multi-provider mailbox and
OAuth flows, attachments and mobile-browser acceptance, password rotation,
signal/power-loss recovery and a full off-host app restore were not exercised.
They remain operator acceptance work; the older MariaDB 11.8.9 smoke test is not
evidence for an existing-database upgrade to 13.0.2.
