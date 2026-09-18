# Runbooks

Operational runbooks, versioned alongside the infrastructure they describe. Populated starting in Phase 6 (Nexus backup/restore) and Phase 9 (on-call triage) — see the [top-level roadmap](../../README.md#build-roadmap).

Planned:

- `nexus-backup-restore.md` — EBS snapshot + S3 lifecycle backup, and the restore procedure.
- `on-call-triage.md` — first-response steps for alerts fired from either K8s tier, with links to the relevant Grafana dashboards.
