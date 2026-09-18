# Runbooks

Operational runbooks, versioned alongside the infrastructure they describe.

- [`nexus-backup-restore.md`](nexus-backup-restore.md) — daily stop/tar/restart backup to S3 (via `ansible/roles/nexus`'s systemd timer), and the step-by-step restore procedure.
- [`on-call-triage.md`](on-call-triage.md) — first-response steps per alert type (`TargetDown`, `HostHighMemory`, the Nexus status-check alarm, both VPN tunnel-down alarms), where they route from, and when to escalate.
