# Catalina Rename Worklog

## 2026-06-11 Execution state

- Base branch for `DF-wu/lilac-mono` confirmed as `main`.
- `/home/df/workspace/lilac-mono` was fast-forwarded to `origin/main` at `8b9756a` before edits.
- Updated `lilac-mono` image build metadata from `catalinna`/`Catalinna` to `catalina`/`Catalina`.
- Added transitional `/home/Catalinna -> /home/Catalina` symlink for Catalina image builds only.
- Updated `myServices/ChatStack/docker-compose.yml` Catalina service to lowercase service/container names, explicit `ghcr.io/df-wu/lilac-mono:catalina`, and `/home/Catalina` mount targets.
- `TreasureBox` verified: all current skill directories are under `SKILLS/`; no `qwen3-hf2api` or `vits-hf2api` skill directories found.
- `qwen3-hf2api` and `vits-hf2api` remain deployment services under `myServices/hf2api`, not TreasureBox skills.

## Pending validation

- Run `lilac-mono` tests/format/lint using the host Bun binary.
- Build and inspect a local `ghcr.io/df-wu/lilac-mono:catalina-local` image before any deployment.
- Do not deploy/recreate containers until image inspection passes.

## 2026-06-11 Validation results

- `bun test __tests__/docker-build-script.test.ts` passed: 2 tests.
- `bun run fmt:check` passed.
- `bun run lint` passed.
- Docker dry-run showed Catalina build args with `CONTAINER_USER=Catalina` and `CONTAINER_UID=3000`.
- Local image build succeeded for `ghcr.io/df-wu/lilac-mono:catalina-local`.
- Image inspect result: `user=Catalina`, `workdir=/app`, command `bun apps/core/src/runtime/main.ts`.
- Runtime check result: UID/GID `3000(Catalina)`, `HOME=/home/Catalina`, `/home/Catalinna -> /home/Catalina` symlink present, `/data` owned by Catalina.
- `docker compose config --services` in `myServices/ChatStack` passed and listed `lilac-catalina` and `lilac-claudia`.

## Ready state

- Repository changes are ready for targeted staging/commit.
- Deployment/recreate is still pending until the `catalina` image is published or the local validated image is intentionally tagged for deployment.
