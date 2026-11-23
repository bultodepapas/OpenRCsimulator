# Always-on dashboard host (TELEM-24c)

Runs the [operator dashboard](../README.md) unattended in its own unprivileged container on a Proxmox node. The page is served privately with Tailscale Serve to the owner's tailnet.

Owner-specific identities, the container ID and the live state are in the HomeLab repository (`docs/plans/2026-11-20-openrc-stats-primis.md` and the guest README).

```text
Proxmox host  openrc-stats-snapshot.timer (:05 hourly)
              pct exec <receiver CT> snapshot.py ──► /srv/openrc-stats/inbox/receiver.json (atomic)
                                                         │ bind mount, read-only
Dashboard CT  openrc-stats-build.timer (:12 hourly)     ▼ /var/lib/openrc-stats/inbox
              dashboard.py build ──► /var/lib/openrc-stats/www/{index.html,health.json} (atomic)
              openrc-stats-release-watch.timer (5 min; builds when public releases or packages change)
              openrc-stats-github.timer (6 h, public fallback), openrc-stats-backup.timer (daily)
              tailscale serve --bg --https=443 /var/lib/openrc-stats/www   (tagged node, owner-only grant)
```

## Files

| File | Where it goes |
| --- | --- |
| `host/openrc-stats-snapshot.sh` | Host `/usr/local/sbin/`, mode 0755; plus `../snapshot.py` at `/usr/local/lib/openrc-stats/snapshot.py` |
| `host/openrc-stats-snapshot.{service,timer}` | Host `/etc/systemd/system/` |
| `host/check_dashboard_health.py` | Monitoring host `/usr/local/lib/openrc-stats/` |
| `host/openrc-stats-health.{service,timer}` | Monitoring host `/etc/systemd/system/` |
| `ct/openrc-stats-{build,github,backup}.{service,timer}` | Container `/etc/systemd/system/` |
| `ct/openrc-stats-release-watch.{service,timer}` | Container `/etc/systemd/system/` |
| `ct/nftables.conf` | Container `/etc/nftables.conf` (egress limits; the tailnet policy is the boundary) |
| `ct/backup_archive.py` | Used in place from the release directory |
| `pull_github_backup.py` | Operator-owned second host with established Proxmox SSH access. Run from the checkout or place it beside the installed validator and reader bundle below. |

## Container contents

- **Packages:** Debian 13, `python3`, `python3-cryptography`, `tzdata`, `gh`, `nftables` and `tailscale` (official repository). No virtualenv is needed.
- **User:** `openrc-stats`.
- **Writable directories:** `/var/lib/openrc-stats/{www,state,github,gh,backups}`, owned by that user. `inbox` is the read-only bind mount.
- **Code:** `/opt/openrc-stats/releases/<commit>` from `git archive <pushed commit> tools/telemetry tools/analytics`, with the symlink `/opt/openrc-stats/current`.
- **`/etc/openrc-stats/env`** (0640 root:openrc-stats): `OPENRC_GA4_CREDENTIALS=/etc/openrc-stats/ga4.json` and `OPENRC_GA4_PROPERTY=<id>`. The GA4 file is 0640 root:openrc-stats.
- **`/etc/openrc-stats/github.env`** (optional): `GH_TOKEN=<fine-grained read-only token>`, limited to the OpenRC repository. Use Contents read and Administration read for protected traffic and star history. Without it, the six-hour job still refreshes public downloads and repository counters. Private traffic, referrers and star history keep their last values and show their own age.
- **Tailscale:** `tailscale up --hostname=openrc-stats --advertise-tags=tag:openrc-stats --accept-dns=false`.
  - DNS stays on the site gateway, because the firewall blocks `100.64.0.0/10`.
  - Limit HTTPS grants for the dashboard tag to the operator and the designated monitor. Check the effective policy for wider matching grants.

## Operation

```bash
systemctl start openrc-stats-build      # rebuild now (in the container)
cat /var/lib/openrc-stats/www/health.json   # status ok | degraded | stale | error
journalctl -u openrc-stats-build -n 50
```

`health.json` includes the last build time, receiver snapshot age and receiver alerts with severity and recovery details, plus timestamps and status per GitHub and GA4 source. Receiver warnings and critical alerts degrade the report, including an overdue rollup, approaching raw retention, intentional release suspension, unexpected admission or rate-limit responses, and ingestion silence after the first batch. First-batch waiting is informational. A missing, failed or stale source also degrades the report. Invalid inputs and failed renders keep the previous HTML. A failed health write rolls back the page and is also detectable by the external clock check. The build, GitHub and release-watch units share one lock across collection and publication.

Enable `openrc-stats-release-watch.timer` after installing its units and the matching dashboard code. Every five minutes it checks the public GitHub catalogue and package identities against the published snapshot. A new release or a package upload triggers an archive refresh and a build. Changes to download counts alone go through the regular six-hour refresh. If GitHub has only returned part of a new release, the watcher keeps the previous page and checks again at the next tick. Use `journalctl -u openrc-stats-release-watch` for check and retry results.

Set `OPENRC_STATS_HEALTH_URL` in `/etc/openrc-stats-health.env` on a host that can reach the private URL. With no tailnet DNS on that host, also set `OPENRC_STATS_HEALTH_OPTIONS="--resolve-address <dashboard-tailnet-IP>"` (requires curl and retains TLS hostname verification). Enable `openrc-stats-health.timer`. The unit fails when HTTPS is unavailable, the served build is older than two hours, a source is unhealthy, or the receiver has a warning or critical alert. Use a second physical host to detect loss of Proxmox itself and route the failed unit to the operator's monitoring channel. Rehearse delivery with an overdue-rollup alert and confirm that the operator receives the remaining recovery time before the 47-hour cutoff.

Run the daily SQLite backup before pulling it to a second host. A missing or invalid archive fails the task and leaves existing backups in place. For example, run the pull script on the operator workstation with an existing trusted key and an operator-only destination outside the repository:

```text
python pull_github_backup.py --host root@<proxmox-host> --key <ssh-key> --destination <private-backup-dir>
```

The transfer only reads the dated GitHub archive. It checks the downloaded SQLite database before retaining it. Keep raw receiver data out of this backup.

### Private GitHub refresh from the operator workstation

If the container has no repository-scoped GitHub credential, an operator workstation can collect private traffic and star history with its existing authenticated `gh` session. Keep `sync_private_github.py` beside a copy of `tools/analytics/github_history.py` on that workstation. Install the same version of the sync script at `/usr/local/lib/openrc-stats/sync_private_github.py` in the dashboard container.

```text
python sync_private_github.py push --host root@<proxmox-host> --key <existing-ssh-key>
```

Use the established Proxmox SSH identity and verified host key. The sync sends aggregated observations and release metadata across SSH, merges them under the build lock, and starts a dashboard build. It retains the original collection times and preserves newer release and public observations.

Run the sync at sign-in and at least every six hours while the workstation is signed in. A failed or partial collection returns a nonzero task result and retains the affected sources' last observations. Their freshness budget is twelve hours. A disabled task, an unavailable workstation or an expired GitHub login can leave the sources stale. Disable the workstation task when the container can collect the private sources directly.

### Independent archive backup

For an unattended pull, install `host/openrc_stats_backup.py` in `/usr/local/lib/openrc-stats/` on both hosts. From the same revision, install `tools/telemetry/github_archive.py` under its `telemetry/` subdirectory and `tools/analytics/github_history.py` under `analytics/`. The container, host and manual pull validate the archive identity and open the closed copy with the dashboard reader before replacing a known-good copy.

The container backup starts at 02:40 UTC. The exporter timer stages today's validated CT 406 backup at 02:55 UTC. Create its staging directory with `install -d -m 2750 -o root -g openrc-stats-export /var/lib/openrc-stats-backup-export` so new files inherit the reader group. The exporter runs as root:root for Proxmox IPC. The separate SSH account has a locked password, no administrative groups and a root-owned authorized-keys file. Restrict its one key to the exact pull-host address with `from=…`, `restrict` and the forced command `/usr/bin/python3 /usr/local/lib/openrc-stats/openrc_stats_backup.py serve`. This command accepts no client arguments and reads only the staged archive.

Install the pull units on the second host. Set `OPENRC_STATS_BACKUP_HOST` in `/etc/openrc-stats-backup.env`. Place a newly generated private key and the source server’s verified Ed25519 host key in `/etc/openrc-stats-backup/{id_ed25519,known_hosts}` with root-only permissions. Verify the host key over an established administrative connection. The dynamic service user receives the credentials through systemd, pulls at 03:15 UTC and keeps 14 validated copies. Enable either timer only after manually exercising the export and pull, comparing the archives and restoring a disposable database.
