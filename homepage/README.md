# Homepage Migration — Phase 1 Research & Design

This directory contains the Phase 1 deliverables for migrating DF's homelab dashboard from Heimdall to [gethomepage/homepage](https://github.com/gethomepage/homepage).

The user-facing goal is not merely “replace the start page”. The goal is to create a maintainable service cockpit: automatic Docker service discovery where appropriate, curated panels for operational information, fast access to important services, a clean visual design, and minimal future hand-maintenance.

## Current status

Phase 1 is **research and design only**. No production service has been deployed, no existing Heimdall container has been modified, and no reverse proxy route has been changed.

A future agent should treat these files as the canonical handoff package and begin Phase 2 only after DF answers the questions in `docs/05-decision-questions.md`.

## Files

| File | Purpose |
|---|---|
| `PHASE2_START_HERE.md` | Short entrypoint for the next implementation agent. |
| `docs/00-executive-summary.md` | High-level summary and readiness. |
| `docs/01-research.md` | Verified Homepage / Heimdall / local homelab research notes with official references. |
| `docs/02-target-design.md` | Proposed target architecture, config model, security model, service grouping, and UI design. |
| `docs/03-migration-plan.md` | Three-stage migration plan with Phase 2 and Phase 3 execution gates. |
| `docs/04-service-catalog-design.md` | Service catalog strategy and widget mapping candidates. |
| `docs/05-decision-questions.md` | Consolidated questions for DF; answer these once before implementation. |
| `docs/06-handoff-for-next-agent.md` | Exact runbook for the next agent implementing Phase 2. |
| `docs/07-security-and-threat-model.md` | Threat model and security gates. |
| `docs/08-implementation-checklist.md` | Condensed Phase 2 checklist. |
| `docs/09-label-patterns.md` | Docker label examples and anti-patterns. |
| `docs/10-widget-recipes.md` | Widget configuration recipes with placeholders. |
| `docs/11-validation-and-rollback.md` | Validation, smoke tests, and rollback runbook. |
| `docs/12-phase1-completion-report.md` | Final Phase 1 completion summary. |
| `docs/13-open-risks-and-quality-gates.md` | Remaining risks and go/no-go gates. |
| `docs/15-visual-style-options.md` | Visual style options and recommended default. |
| `docs/17-stage2-current-status-2026-06-07.md` | Current post-interruption Stage 2 state review and continuation checklist. |
| `docs/18-requirements-and-delivery-plan.md` | Consolidated owner requirements, delivery plan, implemented state, and remaining work. |
| `docs/19-rename-hompage-to-homepage.md` | Rename report for correcting the original `hompage` directory typo. |
| `docs/14-df-decisions.md` | DF decisions already applied to Phase 2 planning. |
| `config-template/` | Homepage compose and config templates; intentionally placeholder-based. |
| `scripts/` | Read-only audit/export helpers. They avoid exporting secrets by default. |
| `inventory/private/` | Generated local inventory. Private; ignored by git. |

## Path note

The working directory is now `~/workspace/myServices/homepage`. An earlier typo used `hompage`; it has been corrected in the repository, runtime docs, and Docker Compose project naming.

## Safety rules for later phases

Do not mount the Docker socket directly unless DF explicitly chooses that tradeoff. Prefer `docker-socket-proxy` with read-only API permissions. Do not put API keys, passwords, or tokens into labels; labels are visible through Docker inspect. Use `HOMEPAGE_VAR_*` / `HOMEPAGE_FILE_*` environment substitutions for secrets in Homepage config files.
