# Runbook: Nexus Backup & Restore

Nexus is a single "pet" VM — `terraform/modules/nexus-ec2` — not an HA cluster (see [`docs/pitfalls.md`](../pitfalls.md) for when that stops being the right call). This runbook covers both the standing backup discipline and what to actually do when you need to restore.

## How backups work

[`ansible/roles/nexus`](../../ansible/roles/nexus/) installs `/usr/local/bin/backup-nexus.sh`, run daily by a systemd timer (`nexus-backup.timer`). Each run:

1. Stops the `nexus` service.
2. Archives the data directory (`/nexus-data`, excluding `cache/`, `tmp/`, `log/`, and its own `backups/`) to a timestamped `.tar.gz` under `/nexus-data/backups/`.
3. Restarts `nexus`.
4. Uploads the archive to the S3 bucket `terraform/modules/nexus-ec2` created (`terraform/live/dev/nexus`'s `backup_bucket_name` output), using the instance's own IAM role — no credentials on disk.
5. Prunes local copies beyond `nexus_backup_retention_local` (default 3); S3 objects age out via the bucket's own lifecycle rules (Standard → IA → Glacier → expire, see the module's variables).

**Why stop/tar/restart instead of a hot backup:** it's the simplest way to guarantee the embedded database and the blob store are mutually consistent in one archive, at the cost of a brief maintenance window (however long the tar takes — proportional to how much is in `/nexus-data`). Nexus 3 ships a built-in "Export databases for backup" scheduled task that dumps the DB without stopping the service, which combined with a live copy of a *File*-type blob store avoids the window entirely — worth adopting once the maintenance window is actually a problem (see [`docs/pitfalls.md`](../pitfalls.md)'s pattern of "documented tradeoff now, real fix when it matters").

## Verify backups are actually happening

```bash
# On the Nexus instance, over SSM (no SSH):
aws ssm start-session --target <instance-id>
sudo systemctl list-timers nexus-backup.timer
sudo journalctl -u nexus-backup.service --since "-7 days"

# From your own machine, against the S3 bucket:
aws s3 ls "s3://$(cd terraform/live/dev/nexus && terragrunt output -raw backup_bucket_name)/"
```

## Restore procedure

1. **Get the instance into a state where you can work on it.** If the instance itself is gone (replaced, terminated), re-apply `terraform/live/dev/nexus` and re-run `ansible-playbook playbooks/configure-nexus.yml` first — the data volume (`prevent_destroy = true`, see the module's README) survives instance replacement and reattaches automatically, so this step alone may already restore service without needing step 2 at all. Only continue if the data volume itself was lost or you need to roll back to an earlier point in time.

2. **Pick the archive to restore from:**
   ```bash
   aws s3 ls "s3://<backup_bucket_name>/" | sort | tail -20
   ```

3. **Stop Nexus and clear the current data directory** (over SSM Session Manager, as root):
   ```bash
   sudo systemctl stop nexus
   sudo mv /nexus-data /nexus-data.bak-$(date -u +%Y%m%dT%H%M%SZ)
   sudo mkdir /nexus-data
   ```

4. **Download and extract the chosen archive:**
   ```bash
   aws s3 cp "s3://<backup_bucket_name>/nexus-backup-<timestamp>.tar.gz" /tmp/restore.tar.gz
   sudo tar -xzf /tmp/restore.tar.gz -C /
   sudo chown -R nexus:nexus /nexus-data
   ```

5. **Restart and verify:**
   ```bash
   sudo systemctl start nexus
   sudo journalctl -u nexus -f   # watch startup; Nexus can take a minute or two
   ```
   Confirm from a host that can reach it (either K8s tier, per `terraform/modules/nexus-ec2`'s `allowed_cidr_blocks`): `curl -sf http://<dns_name>:8081/service/rest/v1/status` should return `200`.

6. **Clean up** the `.bak` directory from step 3 once you've confirmed the restore is good.

## Known limitations

- **Point-in-time granularity is one day** (the timer's default `OnCalendar=daily`). Tighten `nexus-backup.timer`'s schedule if that's not enough for your recovery point objective.
- **No automated restore testing.** A backup nobody has ever restored from is a hope, not a backup — periodically run through this runbook against a scratch instance.
- **Single instance, not HA.** See [`docs/pitfalls.md`](../pitfalls.md) for the trigger ("Nexus artifact volume grows to the point single-VM storage is a bottleneck") and the real fix (Nexus HA cluster with S3-backed blob storage) at that point.
