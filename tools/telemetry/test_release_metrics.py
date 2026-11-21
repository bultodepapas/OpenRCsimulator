"""Release milestones from a disposable GitHub history archive."""
from contextlib import closing
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sqlite3
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import github_archive as archive  # noqa: E402


class ReleaseMilestonesTest(unittest.TestCase):
    def test_selects_only_nearby_observed_package_counts(self):
        published = datetime(2026, 10, 20, tzinfo=timezone.utc)
        first, second, preview = "v0.3.0", "v0.3.1", "v0.3.2-rc.1"

        def stamp(hours, minutes=0):
            return (published + timedelta(hours=hours, minutes=minutes)).isoformat().replace("+00:00", "Z")

        def packages(tag, hours, *counts):
            release_id = (first, second, preview).index(tag)
            return [
                {"tag": tag, "release_id": release_id, "asset_id": release_id * 10 + idx,
                 "name": f"openrc-simulator-{tag}-{idx}.zip", "count": count,
                 "started": stamp(hours, -1), "finished": stamp(hours)}
                for idx, count in enumerate(counts)
            ]

        gh = archive.github_history
        with TemporaryDirectory() as directory:
            with closing(sqlite3.connect(Path(directory) / gh.DATABASE_NAME)) as db, db:
                gh.initialize(db, gh.DEFAULT_REPO, gh.DEFAULT_ASSET_GLOB)
                db.executemany("INSERT INTO releases VALUES (?, ?, ?)", [
                    (first, stamp(0), 0), (second, stamp(36), 0),
                    (preview, stamp(0), 1), ("v0.3.3", stamp(8), 0),
                ])
                for hours, rows in [
                    (14, packages(first, 14, 1)),
                    (20, packages(first, 20, 2, 3) + packages(preview, 20, 400)),
                    (28, packages(first, 28, 6, 8)),  # equally close to 24 h as the earlier capture
                    (60, packages(second, 60, 0)),  # no package for the first release at the 72 h window
                    (85, packages(first, 85, 11)),  # past the 72 h upper bound
                    (144, packages(first, 144, 13)),
                    (168, packages(first, 168, 20, 30)),
                ]:
                    gh.save_assets(db, rows, stamp(hours, -2), stamp(hours, 8))

            # Saved dashboard snapshots should preserve the public accessor's shape.
            model = json.loads(json.dumps(archive.load(directory)))

        day_one, day_three, week_one = archive.release_milestones(model, first)
        self.assertEqual(day_one, {"downloads": 5, "packages": 2, "observed_utc": stamp(20), "age_s": 20 * 3600})
        self.assertIsNone(day_three)
        self.assertEqual(week_one, {"downloads": 50, "packages": 2, "observed_utc": stamp(168), "age_s": 168 * 3600})
        self.assertEqual(archive.release_milestones(model, second)[0]["downloads"], 0)
        for tag in (preview, "v0.3.3", "unarchived"):
            with self.subTest(tag=tag):
                self.assertEqual(archive.release_milestones(model, tag), (None, None, None))

    def test_old_saved_model_has_unknown_milestones(self):
        self.assertEqual(archive.release_milestones({"assets": []}, "v0.3.0"), (None, None, None))


if __name__ == "__main__":
    unittest.main()
