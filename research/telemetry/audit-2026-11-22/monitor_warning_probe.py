#!/usr/bin/env python3
"""Offline synthetic dashboard-health propagation probe; no network or real data."""
from datetime import datetime, timezone
from pathlib import Path
import os
import json
import sys

root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(root / 'tools/telemetry'))
sys.path.insert(0, str(root / 'tools/telemetry/deploy/host'))
import dashboard
import check_dashboard_health

now = datetime(2026, 11, 21, 12, tzinfo=timezone.utc)
timestamp = int(now.timestamp())
stamp = dashboard.utc_stamp(timestamp)
kinds = ('release assets', 'traffic', 'clones', 'community', 'referrals', 'star history')
snapshot = {
    'generated_unix': timestamp,
    'status': {'suspend_all': False, 'retention_ok': True, 'oldest_raw_age_h': 47,
               'suspended_releases': [], 'last_accepted_age_s': 0},
    'ingest': [
        {'day': '2026-11-20', 'counts': {'accepted': 10}},
        {'day': '2026-11-21', 'counts': {'accepted': 1, 'rejected:unapproved_release': 4, 'rate_limited': 3}},
    ],
    'coverage': [], 'rollup_days': {}, 'releases_with_cells': [],
    'github': {'source_utc': dict.fromkeys(kinds, stamp), 'collected_utc': stamp},
    'website': {'collected_utc': stamp},
}
rows = dashboard.ingest_rows(snapshot)
_, _, days = dashboard.coverage_model(snapshot, rows)
alerts = dashboard.alerts(snapshot, rows, days)
report = dashboard.health(snapshot, timestamp, 7200, None, [])
monitor_result = check_dashboard_health.check(report, now, 7200)
print(json.dumps({'day_states': days, 'alerts': alerts, 'health_status': report['status'],
                  'receiver_issues': report['receiver_issues'], 'monitor_failure': monitor_result}, indent=2))
assert days['2026-11-20'] == 'overdue'
assert {'Rollup overdue for 2026-11-20', 'Raw retention near 48 h', 'Unapproved release batches',
        'Rate limiting'} <= {title for _, title, _ in alerts}
assert report['status'] == 'ok' and report['receiver_issues'] == [] and monitor_result is None
