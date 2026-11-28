"""Exercise the restricted backup handoff with disposable SQLite archives."""
from contextlib import closing
from datetime import date, timedelta
import io
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from tools.telemetry.deploy import pull_github_backup
from tools.telemetry.deploy.ct import backup_archive
from tools.telemetry.deploy.host import openrc_stats_backup as backup


DAY = "2026-11-21"
HISTORY = backup.github_archive.github_history
START = f"{DAY}T01:40:00Z"
END = f"{DAY}T01:40:05Z"


def copy_command(source):
    return [sys.executable, "-c",
            "from pathlib import Path; import sys; p = Path(sys.argv[1]); "
            "sys.stdout.buffer.write(p.read_bytes()) if p.is_file() else sys.exit(1)",
            str(source)]


class BackupTests(unittest.TestCase):
    def setUp(self):
        scratch = Path("U:/") if os.name == "nt" and Path("U:/").is_dir() else None
        temporary = tempfile.TemporaryDirectory(prefix="openrc-stats-backup-test-", dir=scratch)
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.copies = self.work / "copies"
        self.copies.mkdir()
        self.archive = self.work / HISTORY.DATABASE_NAME
        with closing(sqlite3.connect(self.archive, isolation_level=None)) as db:
            HISTORY.initialize(db, HISTORY.DEFAULT_REPO, HISTORY.DEFAULT_ASSET_GLOB)
            HISTORY.save_assets(db, [{"asset_id": 27, "release_id": 3, "tag": "v0.3.0",
                                      "name": "openrc-simulator-v0.3.0-linux-x86_64.zip", "count": 120,
                                      "started": START, "finished": END}], START, END)
            HISTORY.save_traffic(db, [{"day": "2026-11-20", "views": 45, "uniques": 31,
                                       "status": "observed_after_day"}], START, END)
        clock = patch.object(backup, "utc_day", return_value=DAY)
        self.addCleanup(clock.stop)
        clock.start()

    def test_verified_archive_replaces_same_day_and_keeps_last_fourteen(self):
        end = date.fromisoformat(DAY)
        for offset in range(1, 17):
            copy = self.copies / backup.backup_name((end - timedelta(days=offset)).isoformat())
            copy.write_bytes(self.archive.read_bytes())
        (self.copies / backup.backup_name(DAY)).write_bytes(b"earlier copy")
        unrelated = self.copies / "local-notes.txt"
        unrelated.touch()

        published = backup.store_archive(copy_command(self.archive), self.copies, DAY, mode=0o600, keep=14)
        self.assertEqual(published.name, backup.backup_name(DAY))
        self.assertEqual(published.read_bytes(), self.archive.read_bytes())
        self.assertEqual(len(list(self.copies.glob("*.sqlite3"))), 14)
        self.assertTrue(unrelated.is_file())
        restore = self.work / "restore"
        restore.mkdir()
        with closing(sqlite3.connect(published)) as source, \
                closing(sqlite3.connect(restore / HISTORY.DATABASE_NAME)) as restored:
            source.backup(restored)
            self.assertEqual(restored.execute("PRAGMA integrity_check").fetchall(), [("ok",)])
        model = backup.github_archive.load(restore)
        self.assertEqual(model, backup.github_archive.load(self.work))
        self.assertEqual((model["assets"][0]["id"], model["assets"][0]["count"]), (27, 120))
        self.assertEqual(model["collected_utc"], END)

        with closing(sqlite3.connect(restore / HISTORY.DATABASE_NAME, isolation_level=None)) as db, \
                closing(sqlite3.connect(self.archive)) as source:
            row = source.execute("SELECT asset_id, release_id, tag, name, count FROM asset_counts").fetchone()
            latest = dict(zip(("asset_id", "release_id", "tag", "name", "count"), row))
            latest.update(count=126, started="2026-11-22T01:40:00Z", finished="2026-11-22T01:40:05Z")
            HISTORY.initialize(db, HISTORY.DEFAULT_REPO, HISTORY.DEFAULT_ASSET_GLOB)
            HISTORY.save_assets(db, [latest], latest["started"], latest["finished"])
        self.assertEqual(backup.github_archive.load(restore)["assets"][0]["count"], 126)

    def test_manifest_identity_schema_and_reader_errors_preserve_known_good_copy(self):
        stable = backup.store_archive(copy_command(self.archive), self.copies, DAY, mode=0o600, keep=14)
        original = stable.read_bytes()
        candidate = self.work / "invalid.sqlite3"
        mutations = (
            ("UPDATE settings SET repo='another/repo'", "repository or asset pattern"),
            ("UPDATE settings SET asset_glob='*.tar'", "repository or asset pattern"),
            ("INSERT INTO settings SELECT * FROM settings", "repository or asset pattern"),
            ("ALTER TABLE settings DROP COLUMN asset_glob", "incomplete.*settings"),
            ("ALTER TABLE popular_paths DROP COLUMN title", "incomplete.*popular_paths"),
            ("ALTER TABLE asset_counts DROP COLUMN release_id", "incomplete.*asset_counts"),
            ("UPDATE observations SET finished_utc='invalid' WHERE kind='assets'", "Invalid isoformat"),
        )
        for sql, message in mutations:
            with self.subTest(sql=sql):
                candidate.write_bytes(original)
                with closing(sqlite3.connect(candidate, isolation_level=None)) as db:
                    db.execute(sql)
                    self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
                with self.assertRaisesRegex(ValueError, message):
                    backup.store_archive(copy_command(candidate), self.copies, DAY, mode=0o600, keep=14)
                self.assertEqual(stable.read_bytes(), original)
                self.assertEqual(list(self.copies.iterdir()), [stable])

    def test_reader_can_open_version_one_without_community_tables(self):
        with closing(sqlite3.connect(self.archive, isolation_level=None)) as db:
            for table in ("clone_days", "repo_counters", "popular_referrers", "popular_paths", "releases", "star_days"):
                db.execute(f"DROP TABLE {table}")
            db.execute("PRAGMA user_version=1")
        backup.validate_archive(self.archive)
        self.assertEqual(backup.github_archive.load(self.work)["assets"][0]["count"], 120)

    def test_delayed_container_backup_recovers_export_and_pull(self):
        staging = self.work / "staging"
        staging.mkdir()
        ct_copies = self.work / "container"
        ct_copies.mkdir()
        previous = self.copies / backup.backup_name("2026-11-20")
        previous.write_bytes(self.archive.read_bytes())
        expected = ct_copies / backup.backup_name(DAY)

        with patch.object(backup, "EXPORT_DIR", staging), patch.dict(os.environ, {"SSH_ORIGINAL_COMMAND": ""}):
            with self.assertRaises(subprocess.CalledProcessError):
                backup.store_archive(copy_command(expected), staging, DAY, mode=0o640, keep=1)
            with self.assertRaises(FileNotFoundError):
                backup.serve_archive(io.BytesIO())
            self.assertEqual(list(self.copies.iterdir()), [previous])

            with patch.object(backup_archive, "utc_day", return_value=DAY), patch("sys.stdout"):
                self.assertEqual(backup_archive.main(self.work, ct_copies), 0)
            backup.store_archive(copy_command(expected), staging, DAY, mode=0o640, keep=1)
            transferred = io.BytesIO()
            backup.serve_archive(transferred)
            received = self.work / "received.sqlite3"
            received.write_bytes(transferred.getvalue())
            pulled = backup.store_archive(copy_command(received), self.copies, DAY, mode=0o600, keep=14)

        self.assertTrue(previous.exists())
        self.assertEqual(backup.github_archive.load_path(pulled), backup.github_archive.load(self.work))

    def test_installed_host_entry_point_finds_the_reader_from_another_directory(self):
        install = self.work / "install"
        telemetry = install / "telemetry"
        analytics = install / "analytics"
        telemetry.mkdir(parents=True)
        analytics.mkdir()
        script = install / "openrc_stats_backup.py"
        shutil.copyfile(backup.__file__, script)
        shutil.copyfile(backup.github_archive.__file__, telemetry / "github_archive.py")
        shutil.copyfile(HISTORY.__file__, analytics / "github_history.py")
        result = subprocess.run([sys.executable, "-B", str(script), "--help"], cwd=self.copies,
                                capture_output=True, text=True, check=True)
        self.assertIn("export,serve,pull", result.stdout)
        pull_script = install / "pull_github_backup.py"
        shutil.copyfile(pull_github_backup.__file__, pull_script)
        result = subprocess.run([sys.executable, "-B", str(pull_script), "--help"], cwd=self.copies,
                                capture_output=True, text=True, check=True)
        self.assertIn("--destination", result.stdout)

    def test_source_entry_points_work_from_another_directory(self):
        telemetry = Path(backup.github_archive.__file__).resolve().parent
        for script in (Path(backup.__file__), Path(pull_github_backup.__file__)):
            subprocess.run([sys.executable, "-I", "-B", str(script), "--help"], cwd=self.copies,
                           capture_output=True, text=True, check=True)
        code = "import sys; sys.path.insert(0, sys.argv[1]); from deploy.ct import backup_archive"
        subprocess.run([sys.executable, "-I", "-B", "-c", code, str(telemetry)], cwd=self.copies,
                       capture_output=True, text=True, check=True)

    @unittest.skipUnless(shutil.which("systemd-analyze"), "systemd calendar parser")
    def test_backup_timers_keep_utc_order_in_both_timezones(self):
        timers = Path(backup.__file__).parent
        schedules = ((timers.parent / "ct" / "openrc-stats-backup.timer", "02:40:00"),
                     (timers / "openrc-stats-backup-export.timer", "02:55:00"),
                     (timers / "openrc-stats-backup-pull.timer", "03:15:00"))
        for zone in ("UTC", "America/Bogota"):
            for filename, expected in schedules:
                with self.subTest(zone=zone, timer=filename.name):
                    line, = (line for line in filename.read_text().splitlines() if line.startswith("OnCalendar="))
                    result = subprocess.run(
                        ["systemd-analyze", "calendar", "--base-time=2026-11-22 02:00:00 UTC", line.split("=", 1)[1]],
                        env={**os.environ, "TZ": zone, "LC_ALL": "C"}, capture_output=True, text=True, check=True)
                    self.assertIn(f"2026-11-22 {expected} UTC", result.stdout)

    def test_corrupt_transfer_and_failed_process_keep_previous_copy(self):
        stable = self.copies / backup.backup_name(DAY)
        stable.write_bytes(self.archive.read_bytes())
        wrong = self.work / "not-an-archive.sqlite3"
        wrong.write_bytes(b"this is not SQLite")

        with self.assertRaises(sqlite3.Error):
            backup.store_archive(copy_command(wrong), self.copies, DAY, mode=0o600, keep=14)
        with self.assertRaises(subprocess.CalledProcessError):
            backup.store_archive([sys.executable, "-c", "raise SystemExit(1)"],
                                 self.copies, DAY, mode=0o600, keep=14)
        self.assertEqual(stable.read_bytes(), self.archive.read_bytes())
        self.assertEqual(list(self.copies.iterdir()), [stable])

    def test_date_change_during_transfer_does_not_publish(self):
        with patch.object(backup, "utc_day", return_value="2026-11-22"):
            with self.assertRaisesRegex(ValueError, "UTC date changed"):
                backup.store_archive(copy_command(self.archive), self.copies, DAY, mode=0o600, keep=14)
        self.assertEqual(list(self.copies.iterdir()), [])

    def test_serve_accepts_no_command_and_only_todays_staged_file(self):
        output = io.BytesIO()
        with patch.object(backup, "EXPORT_DIR", self.copies), patch.dict(os.environ, {"SSH_ORIGINAL_COMMAND": ""}):
            yesterday = self.copies / backup.backup_name("2026-11-20")
            yesterday.write_bytes(self.archive.read_bytes())
            with self.assertRaises(FileNotFoundError):
                backup.serve_archive(output)
            today = self.copies / backup.backup_name(DAY)
            today.write_bytes(self.archive.read_bytes())
            backup.serve_archive(output)
        self.assertEqual(output.getvalue(), self.archive.read_bytes())
        with patch.dict(os.environ, {"SSH_ORIGINAL_COMMAND": "echo unexpected"}):
            with self.assertRaisesRegex(ValueError, "archive transfer only"):
                backup.serve_archive(io.BytesIO())

    def test_pull_uses_pinned_dedicated_key_and_no_remote_command(self):
        with patch.object(backup, "store_archive") as store:
            backup.pull_archive("100.71.14.79", Path("/run/credentials/backup"))
            command, directory, day = store.call_args.args
            self.assertEqual(command[-2:], ["--", "openrc-stats-export@100.71.14.79"])
            self.assertIn("StrictHostKeyChecking=yes", command)
            self.assertIn("GlobalKnownHostsFile=/dev/null", command)
            self.assertIn("IdentityAgent=none", command)
            self.assertEqual(directory, backup.PULL_DIR)
            self.assertEqual(day, DAY)
        with self.assertRaises(ValueError):
            backup.pull_archive("primis", Path("/run/credentials/backup"))


if __name__ == "__main__":
    unittest.main()
