# Open Terminal for ChatStack

Open Terminal is Open WebUI's native terminal integration: command execution,
file browsing, uploads, downloads, editing, and model tools in the chat workspace.
This configuration was checked against Open WebUI **0.12.5** and Open Terminal
**0.16.0**. It is an **Open Terminal connection**, not an OpenAPI tool server.

## Deployment through Portainer

1. Generate a secret with `openssl rand -hex 32`. Add `OPEN_TERMINAL_API_KEY` to
   the **existing ChatStack** stack's Environment. Preserve every existing entry;
   the example here contains no usable key. Use hex so the interpolated connection
   JSON remains valid. The same value authenticates both ends.
2. Review and merge the source change, then update the existing Git-backed stack
   from `ChatStack/docker-compose.yml` through Portainer. No extra `env_file`,
   private checkout file, new stack, published port, or reverse proxy is needed.
   An unset or empty key deliberately prevents deployment. Back up the current
   stack settings and Open WebUI database before updating.
3. Verify that `open-terminal` is healthy. The full image includes Python, Node.js,
   git, data science tools, and document tools; allow several GB for its download
   and extraction. The pinned image manifest supports amd64 and arm64.
4. In **Admin Settings → Integrations → Open Terminal**, check for
   **ChatStack Terminal**. The system URL is `http://open-terminal:8000`, auth is
   **Bearer**, and the key is the one stored in Portainer. Keep access private
   (no user or group grants) for this shared workspace.

`TERMINAL_SERVER_CONNECTIONS` supplies the initial default. Open WebUI 0.12.5
stores `terminal_server.connections` in its database; an existing saved list,
including an empty list, overrides the environment. If the connection is absent,
add it in the admin panel using the values above, leaving other connections
intact. Do not reset all persistent configuration or modify database tables to
force this one setting. When rotating the key, also update a saved connection.

Use the admin integration, rather than user-level direct connections: requests
and terminal WebSockets are proxied by Open WebUI, and the browser cannot resolve
the Docker service name. Ensure the existing WebUI reverse proxy supports
WebSockets and the model uses native function calling when exercising tools.

## Workspace and access

- The terminal persists `/home/user` at `/mnt/appdata/ChatStack/open-terminal`.
  The upstream image starts as its `user` account and initializes ownership of
  that directory. Keep this directory separate from other application data.
- This is one workspace shared by administrators, with multi-user mode disabled.
  Empty `config.access_grants` is admin-only in Open WebUI 0.12.5. Do not grant
  untrusted users access to the same instance. Separate terminal instances are
  needed for separate trust boundaries; the enterprise Terminals orchestrator
  is not part of this deployment.
- Only Open WebUI and Open Terminal join the additional `terminal` bridge.
  Open WebUI keeps its existing default network. Open Terminal has no published
  port, host networking, host Docker socket, or other application mounts.
- Outbound network access is available for downloads and package installation.
  The bridge is not a firewall against the host or LAN. The container has the
  upstream image's passwordless sudo; do not put host credentials in its home.
- Limits are 2 CPUs, 4 GiB RAM, and 512 processes, with rotated logs. Persistent
  files do not have a disk quota; monitor free storage. Installed system packages
  outside `/home/user` are lost on recreation.

## Acceptance and rollback

After the Git update, verify all of the following:

1. An administrator sees the connection and opens an interactive terminal.
2. In that terminal, `printf 'terminal-ok\n'` succeeds; create a disposable file,
   browse it, upload/download it, and remove it.
3. A model configured for native function calling successfully executes a simple
   command through the selected terminal, rather than only writing shell text.
4. A non-admin without grants cannot list or use the connection. Do not widen
   grants just to make this check pass.
5. The workspace file survives a later planned container recreation. Confirm
   normal Open WebUI chat and the existing services continue working.

The container's `/health` check establishes API liveness only. It does not prove
authentication, browser WebSockets, persistence, or model tool use.

For rollback, disable/remove only this connection in the admin panel, revert the
integration commit, and update the same Git stack through Portainer. Check for a
leftover terminal container after removing the service; stop/remove only that
container if Portainer retained it. Keep the workspace directory for recovery.
Do not run `down`, remove all orphans, delete the database, or delete workspace
data as part of rollback.

## Official references

- [Open Terminal documentation](https://docs.openwebui.com/features/open-terminal/)
- [Open Terminal README and integration instructions](https://github.com/open-webui/open-terminal/blob/v0.16.0/README.md)
- [Open WebUI 0.12.5 terminal defaults](https://github.com/open-webui/open-webui/blob/v0.12.5/backend/open_webui/config.py)
- [Open WebUI 0.12.5 connection access control](https://github.com/open-webui/open-webui/blob/v0.12.5/backend/open_webui/utils/access_control/__init__.py)
- [Open WebUI 0.12.5 persisted configuration](https://github.com/open-webui/open-webui/blob/v0.12.5/backend/open_webui/models/config.py)