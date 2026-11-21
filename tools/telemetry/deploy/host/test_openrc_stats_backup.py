"""Exercise the restricted backup handoff with disposable SQLite archives."""
from contextlib import closing
from datetime import date, timedelta
import io
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from tools.telemetry.deploy.host import openrc_stats_backup as backup


DAY = "2026-11-21"


def copy_command(source):
    return [sys.executable, "-c",
            "from pathlib import Path; import sys; sys.stdout.buffer.write(Path(sys.argv[1]).read_bytes())",
            str(source)]


class BackupTests(unittest.TestCase):
    def setUp(self):
        scratch = Path("U:/") if os.name == "nt" and Path("U:/").is_dir() else None
        temporary = tempfile.TemporaryDirectory(prefix="openrc-stats-backup-test-", dir=scratch)
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.copies = self.work / "copies"
        self.copies.mkdir()
        self.archive = self.work / "github.sqlite3"
        with closing(sqlite3.connect(self.archive)) as db:
            db.executescript("""
                PRAGMA user_version = 2;
                CREATE TABLE settings (repo TEXT NOT NULL);
                CREATE TABLE observations (id INTEGER PRIMARY KEY);
                CREATE TABLE asset_counts (value INTEGER);
                CREATE TABLE traffic_days (day_utc TEXT);
                INSERT INTO observations VALUES (27);
            """)
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
        with closing(sqlite3.connect(published)) as source, closing(sqlite3.connect(":memory:")) as restored:
            source.backup(restored)
            self.assertEqual(restored.execute("PRAGMA integrity_check").fetchall(), [("ok",)])
            self.assertEqual(restored.execute("SELECT id FROM observations").fetchall(), [(27,)])

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
