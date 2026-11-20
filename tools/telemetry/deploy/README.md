# Always-on dashboard host (TELEM-24c)

Runs the [operator dashboard](../README.md) unattended in its own unprivileged container on a Proxmox node. The page is served privately with Tailscale Serve to the owner's tailnet.

Owner-specific identities, the container ID and the live state are in the HomeLab repository (`docs/plans/2026-11-20-openrc-stats-primis.md` and the guest README).

```text
Proxmox host  openrc-stats-snapshot.timer (:05 hourly)
              pct exec <receiver CT> snapshot.py ──► /srv/openrc-stats/inbox/receiver.json (atomic)
                                                         │ bind mount, read-only
Dashboard CT  openrc-stats-build.timer (:12 hourly)     ▼ /var/lib/openrc-stats/inbox
              dashboard.py build ──► /var/lib/openrc-stats/www/{index.html,health.json} (atomic)
              openrc-stats-github.timer (6 h, needs GH_TOKEN), openrc-stats-backup.timer (daily)
              tailscale serve --bg --https=443 /var/lib/openrc-stats/www   (tagged node, owner-only grant)
```

## Files

| File | Where it goes |
| --- | --- |
| `host/openrc-stats-snapshot.sh` | Host `/usr/local/sbin/`, mode 0755; plus `../snapshot.py` at `/usr/local/lib/openrc-stats/snapshot.py` |
| `host/openrc-stats-snapshot.{service,timer}` | Host `/etc/systemd/system/` |
| `ct/openrc-stats-{build,github,backup}.{service,timer}` | Container `/etc/systemd/system/` |
| `ct/nftables.conf` | Container `/etc/nftables.conf` (egress limits; the tailnet policy is the boundary) |
| `ct/backup_archive.py` | Used in place from the release directory |

## Container contents

- **Packages:** Debian 13, `python3`, `python3-cryptography`, `tzdata`, `gh`, `nftables` and `tailscale` (official repository). No virtualenv is needed.
- **User:** `openrc-stats`.
- **Writable directories:** `/var/lib/openrc-stats/{www,state,github,gh,backups}`, owned by that user. `inbox` is the read-only bind mount.
- **Code:** `/opt/openrc-stats/releases/<commit>` from `git archive <pushed commit> tools/telemetry tools/analytics`, with the symlink `/opt/openrc-stats/current`.
- **`/etc/openrc-stats/env`** (0640 root:openrc-stats): `OPENRC_GA4_CREDENTIALS=/etc/openrc-stats/ga4.json` and `OPENRC_GA4_PROPERTY=<id>`. The GA4 file is 0640 root:openrc-stats.
- **`/etc/openrc-stats/github.env`** (optional): `GH_TOKEN=<fine-grained read-only token>`. It needs Metadata and Administration read on the repository; Administration covers traffic. Without it, the GitHub archive is shown as last collected and the 6-hour refresh is skipped.
- **Tailscale:** `tailscale up --hostname=openrc-stats --advertise-tags=tag:openrc-stats --accept-dns=false`.
  - DNS stays on the site gateway, because the firewall blocks `100.64.0.0/10`.
  - The tailnet policy needs `tagOwners` for the tag and a grant from the owner to `tag:openrc-stats:443` only.

## Operation

```bash
systemctl start openrc-stats-build      # rebuild now (in the container)
cat /var/lib/openrc-stats/www/health.json   # status ok | degraded | stale | error
journalctl -u openrc-stats-build -n 50
```

`health.json` reports:
- `stale`: the receiver snapshot is older than 2 h.
- `degraded`: the GA4 or GitHub collection failed (the page shows which).
- `error`: there is no readable snapshot. The last good page stays served.

Monitors match the keyword `"status": "ok"`.
