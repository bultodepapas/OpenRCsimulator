"""Disposable archive and transport checks for the private GitHub sync."""

from contextlib import closing, redirect_stderr, redirect_stdout
from datetime import datetime, timezone
import io
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tools.telemetry.deploy import sync_private_github as sync


NOW = datetime(2026, 11, 21, 22, 30, tzinfo=timezone.utc)
START = "2026-11-21T22:22:00.000000Z"
END = "2026-11-21T22:22:02.000000Z"
DAY = "2026-11-20"
DAILY = [{"day": DAY, "views": 14, "uniques": 8, "status": "observed_after_day"}]
COMMUNITY = {
    "counters": {"stars": 4, "forks": 2, "watchers": 1, "open_issues": 3},
    "referrers": [{"referrer": "github.com", "count": 14, "uniques": 8}],
    "paths": [{"path": "/example/readme", "title": "Example", "count": 14, "uniques": 8}],
    "releases": [{"tag": "vNext", "published": "2026-11-19T15:10:00Z", "prerelease": True}],
    "star_days": {"2026-11-18": 2, DAY: 2},
}


def batch(**sources):
    return {"version": 1, "repo": sync.history.DEFAULT_REPO,
            "sources": {kind: {"started": START, "finished": END, "data": data}
                        for kind, data in sources.items()}}


class ImportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / sync.history.DATABASE_NAME
        with closing(sqlite3.connect(self.path)) as db, db:
            sync.history.initialize(db, sync.history.DEFAULT_REPO, sync.history.DEFAULT_ASSET_GLOB)

    def select(self, sql):
        with closing(sqlite3.connect(self.path)) as db:
            return db.execute(sql).fetchall()

    def test_import_all_sources_and_preserve_public_observations(self):
        newer = "2026-11-21T22:25:00.000000Z"
        earlier = "2026-11-19T10:00:00.000000Z"
        with closing(sqlite3.connect(self.path)) as db, db:
            public = {**COMMUNITY, "releases": [{"tag": "v1", "published": earlier, "prerelease": False}]}
            sync.history.save_community(db, public, newer, newer, public_only=True)
            sync.history.save_assets(db, [{"asset_id": 1, "release_id": 1, "tag": "v1",
                                           "name": "openrc-simulator-v1.zip", "count": 11,
                                           "started": newer, "finished": newer}], newer, newer)
            sync.history.save_traffic(db, [{"day": "2026-11-19", "views": 5, "uniques": 4,
                                            "status": "partial"}], earlier, earlier)
            db.execute("INSERT INTO star_days VALUES ('2026-11-15', 3)")

        payload = batch(traffic=DAILY, clones=DAILY, community=COMMUNITY)
        self.assertEqual(sync.import_private(self.path, payload, NOW), ["traffic", "clones", "community"])
        self.assertEqual(sync.import_private(self.path, payload, NOW), [])
        self.assertEqual(self.select("SELECT kind, finished_utc FROM observations ORDER BY id"),
                         [("public community", newer), ("assets", newer), ("traffic", earlier),
                          ("traffic", END), ("clones", END), ("community", END)])
        self.assertEqual(self.select("SELECT kind, success FROM attempts ORDER BY id"),
                         [("traffic", 1), ("clones", 1), ("community", 1)])
        self.assertEqual(self.select("SELECT day_utc, views FROM traffic_days ORDER BY day_utc"),
                         [("2026-11-19", 5), (DAY, 14)])
        self.assertEqual(self.select("SELECT day_utc, views FROM clone_days"), [(DAY, 14)])
        self.assertEqual(self.select("SELECT tag FROM releases"), [("v1",)])
        self.assertEqual(self.select("SELECT count FROM asset_counts"), [(11,)])
        self.assertEqual(self.select("SELECT referrer, count FROM popular_referrers"), [("github.com", 14)])
        self.assertEqual(self.select("SELECT path, title FROM popular_paths"), [("/example/readme", "Example")])
        self.assertEqual(self.select("SELECT day_utc, stars FROM star_days ORDER BY day_utc"),
                         [("2026-11-18", 2), (DAY, 2)])

    def test_newer_private_community_updates_release_catalogue(self):
        older = "2026-11-21T22:15:00.000000Z"
        with closing(sqlite3.connect(self.path)) as db, db:
            public = {**COMMUNITY, "releases": [{"tag": "v1", "published": older, "prerelease": False}]}
            sync.history.save_community(db, public, older, older, public_only=True)
        self.assertEqual(sync.import_private(self.path, batch(community=COMMUNITY), NOW), ["community"])
        self.assertEqual(self.select("SELECT tag, published_utc, prerelease FROM releases"),
                         [("vNext", "2026-11-19T15:10:00Z", 1)])

    def test_public_overlap_skips_community_and_preserves_other_private_updates(self):
        overlap = "2026-11-21T22:22:01.000000Z"
        with closing(sqlite3.connect(self.path)) as db, db:
            public = {**COMMUNITY, "releases": [{"tag": "v1", "published": overlap, "prerelease": False}]}
            sync.history.save_community(db, public, overlap, overlap, public_only=True)
        self.assertEqual(sync.import_private(self.path, batch(traffic=DAILY, community=COMMUNITY), NOW),
                         ["traffic"])
        self.assertEqual(self.select("SELECT tag FROM releases"), [("v1",)])
        self.assertEqual(self.select("SELECT kind FROM observations ORDER BY id"),
                         [("public community",), ("traffic",)])

    def test_out_of_order_success_preserves_newer_observation_and_attempt(self):
        newer = "2026-11-21T22:25:00.000000Z"
        with closing(sqlite3.connect(self.path)) as db, db:
            sync.history.save_traffic(db, [], newer, newer)
            db.execute("INSERT INTO attempts(kind, started_utc, finished_utc, success) VALUES ('clones', ?, ?, 0)",
                       (newer, newer))
        self.assertEqual(sync.import_private(self.path, batch(traffic=DAILY, clones=DAILY), NOW), ["clones"])
        self.assertEqual(self.select("SELECT kind, finished_utc FROM observations ORDER BY id"),
                         [("traffic", newer), ("clones", END)])
        self.assertEqual(self.select("SELECT kind, success FROM attempts"), [("clones", 0)])

    def test_invalid_fields_and_repository_do_not_update_archive(self):
        bad = batch(traffic=DAILY, community={**COMMUNITY, "logins": ["unwanted"]})
        with self.assertRaises(ValueError):
            sync.import_private(self.path, bad, NOW)
        bad = batch(traffic=DAILY)
        bad["repo"] = "other/repo"
        with self.assertRaises(ValueError):
            sync.import_private(self.path, bad, NOW)
        with self.assertRaises(ValueError):
            sync.import_private(self.path, batch(traffic=DAILY), NOW.replace(hour=0))
        self.assertEqual(self.select("SELECT * FROM observations"), [])

    def test_database_error_rolls_back_other_sources(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("CREATE TRIGGER reject_path BEFORE INSERT ON popular_paths "
                       "BEGIN SELECT RAISE(ABORT, 'fixture rejected path'); END")
        with self.assertRaises(sqlite3.IntegrityError):
            sync.import_private(self.path, batch(traffic=DAILY, community=COMMUNITY), NOW)
        self.assertEqual(self.select("SELECT * FROM observations"), [])
        self.assertEqual(self.select("SELECT * FROM traffic_days"), [])
        self.assertEqual(self.select("SELECT * FROM attempts"), [])


class TransportTest(unittest.TestCase):
    def test_collection_omits_failed_sources_and_unrequested_fields(self):
        community = {**COMMUNITY, "star_days": {"2020-01-01": 4}, "releases": []}
        with (patch.object(sync.history, "fetch_traffic", return_value=[]),
              patch.object(sync.history, "fetch_clones", side_effect=sync.history.CollectionError),
              patch.object(sync.history, "fetch_community", return_value={**community, "assets": ["irrelevant"]}),
              redirect_stderr(io.StringIO())):
            result = sync.collect()
        self.assertEqual(set(result["sources"]), {"traffic", "community"})
        self.assertEqual(result["sources"]["community"]["data"], community)

    def test_push_schedules_build_after_partial_import(self):
        payload = batch(clones=DAILY)
        with (patch.object(sync, "collect", return_value=payload),
              patch.object(sync.subprocess, "run", side_effect=[
                  subprocess.CompletedProcess([], 0, stdout=b"clones\n"),
                  subprocess.CompletedProcess([], 0),
              ]) as run, redirect_stdout(io.StringIO())):
            self.assertEqual(sync.push("root@stats.example", Path("operator-key")), 1)
        first, second = run.call_args_list
        self.assertEqual(json.loads(first.kwargs["input"]), payload)
        self.assertIn("StrictHostKeyChecking=yes", first.args[0])
        self.assertIn("runuser -u openrc-stats", first.args[0][-1])
        self.assertIn("/var/lib/openrc-stats/state/build.lock", first.args[0][-1])
        self.assertEqual(second.args[0][-1],
                         "pct exec 406 -- systemctl start openrc-stats-build.service")
        self.assertEqual(second.kwargs["timeout"], 630)

    def test_read_payload_size_limit(self):
        with self.assertRaises(ValueError):
            sync.read_payload(io.BytesIO(b" " * (sync.MAX_BYTES + 1)))


if __name__ == "__main__":
    unittest.main()
