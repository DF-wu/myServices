# Phase 2 Start Here

If you are the next agent, begin here.

1. Read `docs/05-decision-questions.md` and confirm DF's answers.
2. Run `./scripts/all-checks.sh`.
3. Run `./scripts/prepare-runtime-config.sh`.
4. Fill `.env` and runtime YAML placeholders.
5. Deploy locally with `docker compose up -d`.
6. Run `./scripts/smoke-test-homepage.sh`.
7. Only after local success, add a protected reverse proxy route.
8. Do not stop Heimdall during Phase 2.

The complete implementation checklist is `docs/08-implementation-checklist.md`; rollback/debug is `docs/11-validation-and-rollback.md`.

## Current recovery note

After the 2026-06-07 interruption, read `docs/17-stage2-current-status-2026-06-07.md` before continuing. Homepage is locally running on `33080`; public ingress for `hp.dfder.tw` remains unfinished.
