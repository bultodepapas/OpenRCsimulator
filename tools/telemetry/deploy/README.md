# Always-on dashboard host (TELEM-24c)

Runs the [operator dashboard](../README.md) unattended in its own unprivileged container on a Proxmox node. The page is served privately with Tailscale Serve to the owner's tailnet.

Owner-specific identities, the container ID and the live state are in the HomeLab repository (`docs/plans/2026-11-20-openrc-stats-primis.md` and the guest README).

```text
Proxmox host  openrc-stats-snapshot.timer (:05 hourly)
              pct exec <receiver CT> snapshot.py ──► /srv/openrc-stats/inbox/receiver.json (atomic)
                                                         │ bind mount, read-only
Dashboard CT  openrc-stats-build.timer (:12 hourly)     ▼ /var/lib/openrc-stats/inbox
              dashboard.py build ──► /var/lib/openrc-stats/www/{index.html,health.json} (atomic)
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
| `ct/nftables.conf` | Container `/etc/nftables.conf` (egress limits; the tailnet policy is the boundary) |
| `ct/backup_archive.py` | Used in place from the release directory |
| `pull_github_backup.py` | Operator-owned second host with established Proxmox SSH access |

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

`health.json` includes the last build time, receiver snapshot age and critical receiver alerts, plus timestamps and status per GitHub and GA4 source. A missing, failed or stale source degrades the report. Invalid inputs and failed renders keep the previous HTML. A failed health write rolls back the page and is also detectable by the external clock check. For production builds use the two systemd units, which share one lock across collection and publication.

Set `OPENRC_STATS_HEALTH_URL` in `/etc/openrc-stats-health.env` on a host that can reach the private URL. With no tailnet DNS on that host, also set `OPENRC_STATS_HEALTH_OPTIONS="--resolve-address <dashboard-tailnet-IP>"` (requires curl and retains TLS hostname verification). Enable `openrc-stats-health.timer`. The unit fails when HTTPS is unavailable, the served build is older than two hours, or a source is unhealthy. A monitor that only matches a keyword cannot detect a stopped generator. Use a second physical host to detect loss of Proxmox itself and route the failed unit to the operator's monitoring channel.

Run the daily SQLite backup before pulling it to a second host. A missing or invalid archive fails the task and leaves existing backups in place. For example, run the pull script on the operator workstation with an existing trusted key and an operator-only destination outside the repository:

```text
python pull_github_backup.py --host root@<proxmox-host> --key <ssh-key> --destination <private-backup-dir>
```

The transfer only reads the dated GitHub archive. It checks the downloaded SQLite database before retaining it. Keep raw receiver data out of this backup.

For an unattended pull, install `host/openrc_stats_backup.py` in `/usr/local/lib/openrc-stats/` on both hosts. The exporter timer stages today’s validated CT 406 backup at 02:55 UTC. Create its staging directory with `install -d -m 2750 -o root -g openrc-stats-export /var/lib/openrc-stats-backup-export` so new files inherit the reader group. The exporter runs as root:root for Proxmox IPC. The separate SSH account has a locked password, no administrative groups and a root-owned authorized-keys file. Restrict its one key to the exact pull-host address with `from=…`, `restrict` and the forced command `/usr/bin/python3 /usr/local/lib/openrc-stats/openrc_stats_backup.py serve`. This command accepts no client arguments and reads only the staged archive.

Install the pull units on the second host. Set `OPENRC_STATS_BACKUP_HOST` in `/etc/openrc-stats-backup.env`. Place a newly generated private key and the source server’s verified Ed25519 host key in `/etc/openrc-stats-backup/{id_ed25519,known_hosts}` with root-only permissions. Verify the host key over an established administrative connection. The dynamic service user receives the credentials through systemd, pulls at 03:15 UTC and keeps 14 validated copies. Enable either timer only after manually exercising the export and pull, comparing the archives and restoring a disposable database.
