"""Synthetic operator-pipeline counterexamples and archive query counts.

Only local temporary files and fake network/SSH transports are used. Exit zero
means the baseline signatures were reproduced, not that the product is fixed.
"""
import argparse
from contextlib import closing, redirect_stdout
from datetime import datetime, timedelta, timezone
import io
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
from unittest.mock import patch

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
args = parser.parse_args()
sys.path[:0] = [str(args.repo), str(args.repo / 'tools/telemetry')]
from tools.telemetry.deploy import sync_private_github as sync
from tools.telemetry.deploy.test_sync_private_github import NOW, DAILY, COMMUNITY, batch
from tools.telemetry.test_ga4 import FakeGA, PROPERTY
import github_archive as archive
import ga4
import dashboard

results = {}
with tempfile.TemporaryDirectory() as temp:
    path = Path(temp) / sync.history.DATABASE_NAME
    with closing(sqlite3.connect(path)) as db, db:
        sync.history.initialize(db, sync.history.DEFAULT_REPO, sync.history.DEFAULT_ASSET_GLOB)
        old = '2026-11-21T21:00:00.000000Z'
        old_data = {**COMMUNITY, 'referrers': [{'referrer': 'github.com', 'count': 1, 'uniques': 1}],
                    'star_days': {'2026-11-18': 1}}
        sync.history.save_community(db, old_data, old, old, public_only=False)
        overlap = '2026-11-21T22:22:01.000000Z'
        sync.history.save_community(db, COMMUNITY, overlap, overlap, public_only=True)
    payload = batch(traffic=DAILY, clones=DAILY, community=COMMUNITY)
    calls = []
    def fake_ssh(cmd, **kwargs):
        if 'input' in kwargs:
            imported = sync.import_private(path, json.loads(kwargs['input']), NOW)
            calls.append(imported)
            return subprocess.CompletedProcess(cmd, 0, (' '.join(imported) + '\n').encode(), b'')
        return subprocess.CompletedProcess(cmd, 0, b'', b'')
    output = io.StringIO()
    with patch.object(sync, 'collect', return_value=payload), \
         patch.object(sync.subprocess, 'run', side_effect=fake_ssh), redirect_stdout(output):
        status = sync.push('root@example', Path('/synthetic-key-never-opened'))
    with closing(sqlite3.connect(path)) as db:
        old_referrer = db.execute('SELECT count FROM popular_referrers ORDER BY observation_id DESC LIMIT 1').fetchone()[0]
        private_ts = db.execute("SELECT MAX(finished_utc) FROM observations WHERE kind='community'").fetchone()[0]
    results['private_overlap'] = {'collected': sorted(payload['sources']), 'imported': calls[0],
        'exit_code': status, 'retained_private_referrer_count': old_referrer,
        'discarded_new_private_referrer_count': COMMUNITY['referrers'][0]['count'],
        'retained_private_timestamp': private_ts, 'stdout': output.getvalue()}
    assert status == 0 and set(calls[0]) == {'traffic', 'clones'}
    assert old_referrer == 1 and COMMUNITY['referrers'][0]['count'] == 14 and private_ts == old


class BadDateGA(FakeGA):
    def __call__(self, method, url, token=None, body=None, form=None, headers=None):
        reply = super().__call__(method, url, token, body, form, headers)
        if url.endswith(':runReport') and body and body.get('dimensions') == [{'name': 'date'}] and 'dimensionFilter' in body:
            for row in reply.get('rows', []):
                dims = row.get('dimensionValues') or []
                if dims and dims[0].get('value') == '20270110':
                    dims[0]['value'] = 'bad-date'
        return reply


now = 1800000000.0  # Existing synthetic fixture clock, not the audit date.
normal = ga4.collect(PROPERTY, 'synthetic', {}, days=7, now=now, http=FakeGA())
bad = ga4.collect(PROPERTY, 'synthetic', {}, days=7, now=now, http=BadDateGA())
def day_count(model):
    return next(row['count'] for row in model['downloads_daily'] if row['day'] == '2027-01-10')
results['malformed_ga4_date'] = {'normal_count': day_count(normal), 'malformed_count': day_count(bad),
    'downloads_error': bad['errors'].get('downloads'), 'downloads_quality': bad['report_quality'].get('downloads')}
assert day_count(normal) == 4 and day_count(bad) == 0
assert not bad['errors'].get('downloads') and not bad['report_quality'].get('downloads')

results['archive_scaling'] = []
for count in (20, 200):
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / archive.github_history.DATABASE_NAME
        with closing(sqlite3.connect(path)) as db, db:
            archive.github_history.initialize(db, archive.github_history.DEFAULT_REPO, archive.github_history.DEFAULT_ASSET_GLOB)
            for index in range(count):
                stamp = (datetime(2026, 1, 1, tzinfo=timezone.utc) + timedelta(hours=6 * index)).strftime('%Y-%m-%dT%H:%M:%S.000000Z')
                assets = [{'asset_id': asset, 'release_id': 1, 'tag': 'v1', 'name': f'openrc-simulator-windows-{asset}.zip',
                           'count': index + asset, 'started': stamp, 'finished': stamp} for asset in range(3)]
                archive.github_history.save_assets(db, assets, stamp, stamp)
        original_connect = sqlite3.connect
        queries = []
        def tracing_connect(*positional, **keywords):
            connection = original_connect(*positional, **keywords)
            connection.set_trace_callback(queries.append)
            return connection
        with patch.object(archive.sqlite3, 'connect', side_effect=tracing_connect):
            model = archive.load(temp)
        query_count = sum('FROM asset_counts WHERE observation_id =' in query for query in queries)
        results['archive_scaling'].append({'observations': count, 'assets': 3, 'asset_rows': 3 * count,
            'asset_queries': query_count, 'retained_intervals': len(model['intervals']), 'database_bytes': path.stat().st_size})
        assert query_count == count and len(model['intervals']) == count - 1

fresh_ga = ga4.collect(PROPERTY, 'synthetic', {}, days=30, now=now, http=FakeGA())
metrics = []
original_week_metric = dashboard.week_metric
def capture_metric(*positional, **keywords):
    value = original_week_metric(*positional, **keywords)
    metrics.append(value)
    return value
snapshot = {'generated_unix': now - 40 * 86400, 'website': fresh_ga}
with patch.object(dashboard, 'week_metric', side_effect=capture_metric), \
     patch.object(dashboard, 'review_items', return_value=''), \
     patch.object(dashboard, 'alerts_panel', return_value=''), \
     patch.object(dashboard, 'freshness_strip', return_value=''), \
     patch.object(dashboard, 'latest_week_players', return_value=None), \
     patch.object(dashboard, 'panel', return_value=''):
    dashboard.overview_section(snapshot, [], [])
sessions = next(metric for metric in metrics if metric.title == 'Website sessions')
results['stale_receiver_fresh_ga4'] = {
    'receiver_day': str(datetime.fromtimestamp(snapshot['generated_unix'], timezone.utc).date()),
    'ga4_latest_closed': fresh_ga['comparison_through'], 'overview_week': [sessions.days[0], sessions.days[-1]],
    'condition': sessions.condition, 'coverage': sessions.coverage,
    'ga4_available_days': [fresh_ga['days'][0], fresh_ga['days'][-1]],
    'note': 'Presentation helpers are stubbed; the actual overview date selection and week_metric execute.'}
assert str(sessions.days[0]) == '2026-11-29' and str(sessions.days[-1]) == '2026-12-05'
assert sessions.condition == 'Unavailable' and sessions.coverage == 0
print(json.dumps(results, indent=2, default=str))
