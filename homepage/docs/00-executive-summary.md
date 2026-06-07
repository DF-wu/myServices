# Executive Summary

This package is a Phase 1 handoff for replacing Heimdall with gethomepage/homepage on axolotl.

## Recommended path

Deploy Homepage side-by-side with Heimdall, using Docker Compose and a read-only `docker-socket-proxy`. Start with a curated YAML baseline, then gradually add Docker labels for non-secret service card metadata. Keep all widget secrets in `.env` via `HOMEPAGE_VAR_*` placeholders.

## Do not do these in Phase 2

- Do not stop Heimdall.
- Do not change existing Heimdall proxy routes.
- Do not put API keys or passwords in Docker labels.
- Do not expose Homepage publicly without authentication/access control.
- Do not mutate TrueNAS/ESXi as part of this migration.

## Required DF decisions

Before implementation, DF should answer `docs/05-decision-questions.md`, especially exposure/authentication model, hostname, visual style, widget scope, and whether labels or YAML should be the dominant long-term model.

## Main deliverables

- `config-template/`: deployable Docker Compose and Homepage config templates.
- `scripts/`: export, audit, validate, prepare, smoke-test, and secret-scan helpers.
- `docs/`: research, target design, migration plan, security model, label patterns, widget recipes, validation and rollback.
- `inventory/private/`: generated local inventory, intentionally ignored by git.

## Current readiness

The package is ready for Phase 2 after DF answers the decision questions. The next agent should first run:

```bash
cd ~/workspace/myServices/homepage
./scripts/all-checks.sh
```
