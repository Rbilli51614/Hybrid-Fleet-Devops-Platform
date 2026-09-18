# Runbooks

Operational runbooks, versioned alongside the infrastructure they describe.

- [`nexus-backup-restore.md`](nexus-backup-restore.md) — daily stop/tar/restart backup to S3 (via `ansible/roles/nexus`'s systemd timer), and the step-by-step restore procedure.

Planned: `on-call-triage.md` — first-response steps for alerts fired from either K8s tier, with links to the relevant Grafana dashboards. See Phase 9 in the [top-level roadmap](../../README.md#build-roadmap).
