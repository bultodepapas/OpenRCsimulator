"""Offline SQL model of rollup input loss; no application imports or live data.
Run with Python 3: python rollup_boundaries_probe.py
Source: storage.py 44-74, 188-205, 318-327; rollup.py 31-42, 168-192;
cli.py 57-69, 189-197 at 19e9e69dda17261a7761625958d038a646608e8c.
Only the relevant columns are modeled; bodies are synthetic opaque bytes.
"""
from pathlib import Path
import json
import sqlite3
import sys
import tempfile

DAY = '2026-11-22'
RELEASE = 'v0.3.5'
H = 3600


def open_raw(path):
    # Same create-on-open behavior, reduced schema.
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path, isolation_level=None)
    conn.execute('PRAGMA journal_mode=WAL')
    conn.execute('CREATE TABLE IF NOT EXISTS batches(receipt_unix INTEGER, receipt_day TEXT, body BLOB)')
    return conn


def records(conn):
    return conn.execute('SELECT receipt_day, body FROM batches WHERE receipt_day=? ORDER BY rowid', (DAY,)).fetchall()


def replace_day(conn, rows):
    # Model the actual unconditional atomic day replacement and completion marker.
    conn.execute('BEGIN IMMEDIATE')
    conn.execute('DELETE FROM daily_status WHERE day=?', (DAY,))
    conn.execute('DELETE FROM daily_rollup WHERE day=?', (DAY,))
    conn.execute('INSERT INTO daily_status VALUES(?,?,?)', (DAY, RELEASE, 'ready' if len(rows) >= 20 else 'no_data' if not rows else 'suppressed'))
    conn.execute('INSERT INTO daily_rollup VALUES(?,?)', (DAY, 1))
    conn.execute('COMMIT')


def snapshot(conn):
    return {'status': conn.execute('SELECT status FROM daily_status').fetchone()[0],
            'release_count': conn.execute('SELECT release_count FROM daily_rollup').fetchone()[0]}


def main():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        raw = open_raw(root / 'original' / 'raw.sqlite')
        raw.executemany('INSERT INTO batches VALUES(?,?,?)', [(0, DAY, b'early')]*20 + [(H, DAY, b'late')]*20)
        agg = sqlite3.connect(':memory:', isolation_level=None)
        agg.execute('CREATE TABLE daily_status(day TEXT, release_id TEXT, status TEXT)')
        agg.execute('CREATE TABLE daily_rollup(day TEXT, release_count INTEGER)')
        replace_day(agg, records(raw))
        before = snapshot(agg)
        wrong_path = root / 'wrong' / 'raw.sqlite'
        assert not wrong_path.exists()
        wrong = open_raw(wrong_path)
        wrong_rows = records(wrong)
        replace_day(agg, wrong_rows)
        missing = {'original_rows': len(records(raw)), 'new_file_created': wrong_path.exists(),
                   'selected_rows': len(wrong_rows), 'before': before, 'after': snapshot(agg)}
        assert missing['original_rows'] == 40 and missing['selected_rows'] == 0
        assert missing['before']['status'] == 'ready' and missing['after'] == {'status': 'no_data', 'release_count': 1}
        wrong.close()
        # Eligibility is evaluated once at 47h-1s. A suspended worker resumes
        # after the earliest permitted automatic purge, with maximum margin.
        checked_now = 47*H - 1
        purge_now = 48*H - (1800 + 60)
        assert 25*H <= checked_now < 47*H and purge_now > 47*H
        before_count = len(records(raw))
        deleted = raw.execute('DELETE FROM batches WHERE receipt_unix <= ?', (purge_now - (48*H - 1860),)).rowcount
        after_count = len(records(raw))
        late = {'eligible_at_checked_seconds': checked_now, 'read_at_seconds': purge_now,
                'deadline_seconds': 47*H, 'delay_seconds': purge_now-checked_now,
                'rows_before': before_count, 'deleted': deleted, 'rows_after': after_count}
        assert (before_count, deleted, after_count) == (40,20,20)
        raw.close()
        agg.close()
    print(json.dumps({'scope':'source-equivalent reduced SQL model; not integrated receiver or contract-validated batches', 'python':sys.version.split()[0], 'sqlite':sqlite3.sqlite_version, 'missing_raw':missing, 'late_read_after_purge':late}, indent=2))

if __name__ == '__main__':
    main()
