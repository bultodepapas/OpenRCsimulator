#!/bin/bash
# TELEM-24c, Proxmox host side: take a receiver snapshot from CT 404 and drop it, atomically, into the
# directory that is bind-mounted read-only into the dashboard container (CT 405). Same command as
# `dashboard.py fetch` runs over SSH; only OPENRC_TELEMETRY_* settings are exported (no tokens).
set -euo pipefail
CT="${OPENRC_STATS_RECEIVER_CT:-404}"
ROOT="${OPENRC_STATS_RECEIVER_ROOT:-/opt/openrc-telemetry/current}"
INBOX="${OPENRC_STATS_INBOX:-/srv/openrc-stats/inbox}"
SNAPSHOT_PY="${OPENRC_STATS_SNAPSHOT_PY:-/usr/local/lib/openrc-stats/snapshot.py}"

inner="cd ${ROOT}/services/telemetry && set -a && . <(grep -E '^(export )?OPENRC_TELEMETRY_[A-Z0-9_]+=' /etc/openrc-telemetry/env) && set +a && exec runuser -u telemetry -- ${ROOT}/venv/bin/python - --days 30 --weeks 4 --floor 20"
tmp="$(mktemp "${INBOX}/.receiver.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
timeout 300 pct exec "$CT" -- bash -c "$inner" < "$SNAPSHOT_PY" > "$tmp"
python3 -c 'import json, sys; data = json.load(open(sys.argv[1])); assert data["snapshot_version"] in (1, 2)' "$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "${INBOX}/receiver.json"
trap - EXIT
