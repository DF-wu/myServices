# LibreChat restoration and Code Interpreter recipe

This change is authorized for recipe editing only. Do not create, start, restart,
or exec into containers, edit production appdata, or redeploy the Portainer stack.

## Design

Restore LibreChat in the existing `ChatStack/docker-compose.yml`, keeping port
43065, existing host configuration and attachments, the exact external MongoDB /
Meilisearch / RAG volumes, and PostgreSQL `librechat_rag` owned by `librechat_rag`.
Keep all other ChatStack services identical.

Deploy the official Code Interpreter HTTP backend with its API, worker, file
server, egress gateway, tool-call server, Redis and S3-compatible storage. This
machine does not expose KVM, so use upstream's direct NsJail runner with the
upstream seccomp policy, container resource limits, no host socket or workspace
mounts, and an internal network. Supply the official, version-matched offline
language packages from the baked runner image through a one-shot provisioner.
Use prebuilt images only, with immutable digests; no Portainer build dependency.

Provision new independent signing keys and service credentials once into local
Docker volumes during Portainer deployment. Project only the credentials needed
by each service; the sandbox receives only a public manifest verifier. Preserve
the existing LibreChat encryption and login secrets. Read host secrets through
read-only binds inside containers, never through Portainer-side `env_file`.

Enable code execution, background tools and programmatic tools. The default HTTP
backend supplies isolated executions and restores files through LibreChat's file
flow; it does not provide the experimental stateful backend. Do not advertise
stateful sessions or attach the homelab host as an agent workspace.

## Implementation and verification

- [x] Read official LibreChat, Code Interpreter and Portainer documentation/source.
- [x] Verify existing volumes, RAG database/role/credential, NFS mapping and KVM.
- [x] Establish failing recipe checks before implementation.
- [x] Restore the application and existing backing stores in the recipe.
- [x] Add the authenticated Code Interpreter stack and automatic package setup.
- [x] Test key reuse, public/private signing contracts and configuration merging.
- [x] Validate Compose without creating containers; verify registry manifests.
- [x] Compare all pre-existing services with Git HEAD and scan for secret leakage.
- [x] Document Portainer deployment, post-deployment acceptance and limitations.

Independent read-only review found that reprovisioning role-owned directories
also needs `CAP_FOWNER`. Added that capability only to the offline credential
initializer and added a regression check. No other confirmed blocker was found.

Runtime acceptance is reserved for after the user deploys through Portainer:
login/history, Python execution, uploaded CSV processing, downloadable artifacts,
cross-user isolation and repeated executions. Static checks cannot establish those.
