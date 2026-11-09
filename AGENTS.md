# Deployment principles

- DF's instructions override generic best practices. Historical recipes are evidence, not permission for exceptions. Author repository and PR content in English.

- Default to official `latest` images. Do not introduce pins, digests or image overrides. Preserve required upstream variants and explicit owner exceptions; do not mass-convert recipes.

- Use one container when sufficient. No unsolicited build/init/proxy services or official runtime replacements. Reuse verified shared dependencies where supported; do not force unrelated dependencies together.

- Add only required persistence/config/device mounts; source mounts need a demonstrated requirement or request. Know source, target and purpose. Preserve paths, mount types/names, permissions and data; never hide permission errors with new volumes.

- Keep image-based deployment simple. Do not invent manually staged, mounted and switched commit/SHA-versioned host runtime/source directories, or gratuitous configuration/path override knobs.

- Inspect upstream support and the actual project, host, ports, networks and data first. Make the smallest requested change; preserve unrelated dirty work.

- For Portainer-managed stacks, Git source is authoritative. Do not edit its checkout. PR permission is not deployment permission: no unauthorized compose up, rebuild, restart, environment or storage changes.

- Use the actual environment flow. For Portainer, wire stack Environment through Compose interpolation/mapping; do not assume a `.env` exists or local shell values reach deployment.

- This repository is public. Never publish homelab addresses/domains, usable credentials, connection strings or private inventory.

- Review the full diff and links; verify proportionately. Report changes, checks, impact and recovery when applicable. Documentation needs no service startup or heavy tests.
