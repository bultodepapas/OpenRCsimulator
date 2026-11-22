#!/usr/bin/env python3
"""Show a physically valid but structurally unusable SQLite archive passes backup validation."""
from contextlib import closing
from pathlib import Path
import os
import sqlite3
import sys
import tempfile

root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(root / 'tools/telemetry'))
sys.path.insert(0, str(root / 'tools/telemetry/deploy/host'))
import github_archive
import openrc_stats_backup
with tempfile.TemporaryDirectory(prefix='backup-validation-probe-', dir=os.environ["OPENRC_AUDIT_TMP"]) as tmp:
    path = Path(tmp) / 'github-history.sqlite3'
    with closing(sqlite3.connect(path)) as db:
        db.executescript('''PRAGMA user_version = 2;
          CREATE TABLE settings (repo TEXT NOT NULL);
          CREATE TABLE observations (id INTEGER PRIMARY KEY);
          CREATE TABLE asset_counts (value INTEGER);
          CREATE TABLE traffic_days (day_utc TEXT);
          INSERT INTO observations VALUES (27);''')
    openrc_stats_backup.validate_archive(path)
    print('backup validation: PASSED')
    try:
        github_archive.load(path.parent)
    except sqlite3.Error as error:
        print(f'actual dashboard archive load: FAILED: {type(error).__name__}: {error}')
    else:
        raise AssertionError('unexpectedly loaded malformed backup')
