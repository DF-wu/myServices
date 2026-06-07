# Open Risks and Quality Gates

## Open risks

| Risk | Mitigation |
|---|---|
| Homepage accidentally exposed without auth | Require DF decision and protected route before NPM/Cloudflare changes. |
| Docker socket access too broad | Use docker-socket-proxy with `POST=0` and no host port. |
| Secrets copied from Heimdall descriptions | Safe export excludes descriptions by default. |
| Widget internal URL differs from browser URL | Test every widget from inside Homepage container. |
| Too many labels at once break service discovery | Add labels in small batches and run smoke/log checks. |
| Config drift between repo and `/mnt/appdata` | Runtime config preparation uses templates; future commits should avoid `.env` and private inventory. |
| Public/private dashboard needs diverge | Use `instanceName` and instance-scoped labels later if needed. |

## Quality gates

Phase 2 may start only when:

```bash
./scripts/all-checks.sh
```

passes, and DF has answered the questions in `docs/05-decision-questions.md`.

Phase 2 may add a reverse proxy route only when:

```bash
docker compose config
docker compose up -d
./scripts/smoke-test-homepage.sh
```

passes locally.

Phase 3 may start only after DF explicitly approves taking Heimdall offline.
