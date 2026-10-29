#!/usr/bin/env python3
"""Regression tests for the GitHub analytics archive."""

import contextlib
import csv
import io
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import github_history as history


def asset(asset_id, count, name=None):
    return {"asset_id": asset_id, "release_id": 10, "tag": "v1", "name": name or f"{asset_id}.zip",
            "count": count, "started": "2026-10-01T12:00:00.000000Z", "finished": "2026-10-01T12:00:01.000000Z"}


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        history.initialize(self.db, "example/repo", "*.zip")

    def tearDown(self):
        self.db.close()

    def fetch_days(self, items, started):
        with mock.patch.object(history, "github_json", return_value={"views": items}):
            return history.fetch_traffic("example/repo", started)

    def test_overlapping_traffic_buckets_replace_revisions_and_keep_missing_dates_unknown(self):
        first_start = "2026-10-02T12:00:00.000000Z"
        first = self.fetch_days([
            {"timestamp": "2026-10-01T05:00:00+05:00", "count": 4, "uniques": 3},
            {"timestamp": "2026-10-02T00:00:00Z", "count": 9, "uniques": 5},
        ], first_start)
        history.save_traffic(self.db, first, first_start, "2026-10-02T12:00:01.000000Z")
        second_start = "2026-10-04T00:05:00.000000Z"
        second = self.fetch_days([
            {"timestamp": "2026-10-02T00:00:00Z", "count": 8, "uniques": 4},
            {"timestamp": "2026-10-04T00:00:00Z", "count": 1, "uniques": 1},
        ], second_start)
        history.save_traffic(self.db, second, second_start, "2026-10-04T00:05:01.000000Z")
        rows = self.db.execute("SELECT day_utc, views, uniques, status FROM traffic_days ORDER BY day_utc").fetchall()
        self.assertEqual(rows, [("2026-10-01", 4, 3, "observed_after_day"),
                                ("2026-10-02", 8, 4, "observed_after_day"),
                                ("2026-10-04", 1, 1, "partial")])

    def test_traffic_rejects_non_midnight_future_naive_and_duplicate_dates(self):
        started = "2026-10-02T00:01:00.000000Z"
        for value in ("2026-10-01T01:00:00Z", "2026-10-03T00:00:00Z", "2026-10-01T00:00:00"):
            with self.subTest(value=value), self.assertRaises(history.CollectionError):
                self.fetch_days([{"timestamp": value, "count": 1, "uniques": 1}], started)
        item = {"timestamp": "2026-10-01T00:00:00Z", "count": 1, "uniques": 1}
        with self.assertRaises(history.CollectionError):
            self.fetch_days([item, item], started)

    def test_baseline_and_replacement_reset_removal_do_not_fabricate_downloads(self):
        first_start = "2026-10-01T12:00:00.000000Z"
        history.save_assets(self.db, [asset(1, 100), asset(2, 20), asset(3, 30), asset(4, 10)],
                            first_start, "2026-10-01T12:00:02.000000Z")
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            history.generate_reports(self.db, target)
            with (target / "download-intervals.csv").open(newline="", encoding="utf-8") as source:
                self.assertEqual(list(csv.DictReader(source)), [])
            # ID 1 increased by seven; 2 decreased; 3 was replaced by 5; 4 disappeared.
            second_start = "2026-10-03T12:30:00.000000Z"
            history.save_assets(self.db, [asset(1, 107), asset(2, 2), asset(5, 300)],
                                second_start, "2026-10-03T12:30:05.000000Z")
            history.generate_reports(self.db, target)
            with (target / "download-intervals.csv").open(newline="", encoding="utf-8") as source:
                rows = list(csv.DictReader(source))
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["from_start_utc"], first_start)
            self.assertEqual(rows[0]["to_start_utc"], second_start)
            self.assertEqual(rows[0]["matched_asset_increase"], "7")
            self.assertEqual((rows[0]["added_assets"], rows[0]["removed_assets"], rows[0]["decreased_assets"]), ("1", "2", "1"))
            self.assertEqual(rows[0]["status"], "partial")
            self.assertNotIn("2026-10-02", (target / "download-intervals.csv").read_text(encoding="utf-8"))
            # Returning IDs are new baselines, not a made-up change across a gap.
            history.save_assets(self.db, [asset(1, 110), asset(2, 5), asset(3, 99), asset(5, 301)],
                                "2026-10-04T12:30:00.000000Z", "2026-10-04T12:30:05.000000Z")
            history.generate_reports(self.db, target)
            with (target / "download-intervals.csv").open(newline="", encoding="utf-8") as source:
                latest = list(csv.DictReader(source))[0]
            self.assertEqual(latest["matched_asset_increase"], "7")
            self.assertEqual(latest["added_assets"], "1")
            self.assertEqual(latest["status"], "partial")

    def test_all_matching_counters_can_be_compared_without_rebinning(self):
        comparison = history.compare_assets({1: 10, 2: 20}, {1: 12, 2: 21})
        self.assertEqual(comparison, {"increase": 3, "comparable": 2, "added": 0, "removed": 0,
                                      "decreased": 0, "status": "matched_ids"})

    def test_partial_interval_with_no_comparable_assets_has_no_invented_zero(self):
        comparison = history.compare_assets({1: 100}, {2: 80})
        self.assertIsNone(comparison["increase"])
        self.assertEqual(comparison["status"], "partial")

    def test_report_shows_latest_version_platform_counts_and_escapes_names(self):
        unsafe = asset(1, 42, "openrc-simulator-v1-windows-<script>.zip")
        unsafe["tag"] = "v1<script>"
        history.save_assets(self.db, [unsafe, asset(2, 5, "openrc-simulator-v1-macos-universal.zip"),
                                      asset(3, 9, "openrc-simulator-v1-linux-x86_64.zip")],
                            "2026-10-01T12:00:00.000000Z", "2026-10-01T12:00:02.000000Z")
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            history.generate_reports(self.db, target)
            report = (target / "report.html").read_text(encoding="utf-8")
        self.assertIn("v1&lt;script&gt;</td><td>Windows</td>", report)
        self.assertIn("openrc-simulator-v1-windows-&lt;script&gt;.zip</td><td>42</td>", report)
        self.assertIn("<td>macOS</td>", report)
        self.assertIn("<td>Linux</td>", report)
        self.assertNotIn("v1<script>", report)
        self.assertIn('href="https://analytics.google.com/analytics/web/"', report)
        self.assertIn("download_request", report)
        self.assertIn("GitHub repository traffic does not report reader countries", report)

    def test_fetches_each_release_asset_page_filters_packages_and_drafts(self):
        releases = [{"id": 1, "tag_name": "v1", "draft": False},
                    {"id": 2, "tag_name": "draft", "draft": True}]
        items = [{"id": 5, "name": "openrc-simulator-v1-linux.zip", "state": "uploaded", "download_count": 50},
                 {"id": 6, "name": "SHA256SUMS", "state": "uploaded", "download_count": 30},
                 {"id": 7, "name": "openrc-simulator-pending.zip", "state": "starter", "download_count": 0}]
        with mock.patch.object(history, "github_json", side_effect=[releases, items]) as api:
            result = history.fetch_assets("example/repo", history.DEFAULT_ASSET_GLOB)
        self.assertEqual([(row["asset_id"], row["count"]) for row in result], [(5, 50)])
        self.assertEqual(api.call_count, 2)
        self.assertTrue(api.call_args.kwargs["paginated"])

    def test_gh_pagination_and_authentication_do_not_put_credentials_in_arguments(self):
        command_result = subprocess.CompletedProcess([], 0, '[[{"id":1}],[{"id":2}]]', "")
        with mock.patch.dict(os.environ, {"GH_TOKEN": "SYNTHETIC_TEST_VALUE", "GH_DEBUG": "api"}), \
                mock.patch.object(history.subprocess, "run", return_value=command_result) as run:
            self.assertEqual(history.github_json("repos/example/repo/releases", paginated=True), [{"id": 1}, {"id": 2}])
        command = run.call_args.args[0]
        self.assertIn("--paginate", command)
        self.assertIn("--slurp", command)
        self.assertNotIn("SYNTHETIC_TEST_VALUE", " ".join(command))
        self.assertNotIn("GH_DEBUG", run.call_args.kwargs["env"])

    def test_source_failure_is_nonzero_but_other_source_is_saved(self):
        fake_days = [{"day": "2026-10-01", "views": 3, "uniques": 2, "status": "observed_after_day"}]
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(history, "fetch_traffic", return_value=fake_days), \
                mock.patch.object(history, "fetch_assets", side_effect=history.CollectionError("unavailable")), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = history.collect(Path(directory), "example/repo", "*.zip")
            self.assertEqual(result, 1)
            with (Path(directory) / "daily-traffic.csv").open(newline="", encoding="utf-8") as source:
                self.assertEqual(list(csv.DictReader(source))[0]["page_views"], "3")
            with (Path(directory) / "download-intervals.csv").open(newline="", encoding="utf-8") as source:
                self.assertEqual(list(csv.DictReader(source)), [])
            report = (Path(directory) / "report.html").read_text(encoding="utf-8")
            self.assertIn("release assets</td><td>failed", report)
            self.assertIn("traffic</td><td>succeeded", report)

    def test_output_directory_cannot_mix_repository_or_asset_filter(self):
        for repo, pattern in (("other/repo", "*.zip"), ("example/repo", "*.tar.gz")):
            with self.subTest(repo=repo, pattern=pattern), self.assertRaises(history.CollectionError):
                history.initialize(self.db, repo, pattern)


@unittest.skipUnless(os.name == "nt", "Windows Task Scheduler launcher")
class WindowsTaskTests(unittest.TestCase):
    def setUp(self):
        self.powershell = Path(os.environ["WINDIR"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"
        self.installer = Path(__file__).resolve().with_name("install_daily_task.ps1")
        if not self.powershell.is_file():
            self.skipTest("Windows PowerShell is unavailable")

    def test_launcher_captures_output_and_preserves_failure_exit_code(self):
        temporary_root = Path(__file__).resolve().parents[2] / "tmp/analytics"
        temporary_root.mkdir(parents=True, exist_ok=True)
        temporary_root = temporary_root.resolve()
        with tempfile.TemporaryDirectory(prefix="task-test-", dir=temporary_root) as directory:
            test_root = Path(directory).resolve()
            self.assertTrue(test_root.is_relative_to(temporary_root))
            tools_dir = test_root / "repo/tools/analytics"
            tools_dir.mkdir(parents=True)
            shutil.copyfile(self.installer, tools_dir / self.installer.name)
            (tools_dir / "github_history.py").write_text(
                'import sys\nprint("synthetic stdout")\nprint("synthetic stderr", file=sys.stderr)\nsys.exit(7)\n', encoding="utf-8")
            local_data = test_root / "localappdata"
            environment = os.environ.copy()
            environment["LOCALAPPDATA"] = str(local_data)
            result = subprocess.run([str(self.powershell), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                                     "-File", str(tools_dir / self.installer.name), "-Run", "-PythonExe", sys.executable],
                                    capture_output=True, text=True, env=environment, timeout=30, check=False)
            self.assertEqual(result.returncode, 7, msg=result.stdout + result.stderr)
            log = (local_data / "OpenRCsimulator/analytics/last-run.log").read_text(encoding="utf-8")
            self.assertIn("Exit code: 7", log)
            self.assertIn("synthetic stdout", log)
            self.assertIn("synthetic stderr", log)

    def test_ownership_check_accepts_only_expected_action_and_current_user(self):
        script = r'''
$ErrorActionPreference = 'Stop'
function Get-ScheduledTask { [CmdletBinding()] param([string] $TaskPath, [string] $TaskName) }
. $env:OPENRC_TEST_INSTALLER -WhatIf
function FakeTask {
    [pscustomobject]@{
        Actions = @([pscustomobject]@{ Execute = $powershellExe; WorkingDirectory = $repoRoot; Arguments = ($argumentPrefix + $PythonExe + '"') })
        Principal = [pscustomobject]@{ UserId = $currentUser }
    }
}
function AssertRejected($Task) {
    $rejected = $false
    try { Assert-OwnedTask $Task $userSid $argumentPrefix } catch { $rejected = $true }
    if (-not $rejected) { throw 'A different task was accepted.' }
}
$owned = FakeTask
Assert-OwnedTask $owned $userSid $argumentPrefix
$wrongExe = FakeTask
$wrongExe.Actions[0].Execute = 'C:\Windows\not-owned.exe'
AssertRejected $wrongExe
$wrongArgs = FakeTask
$wrongArgs.Actions[0].Arguments = $argumentPrefix + 'C:\other.exe" -Command "other"'
AssertRejected $wrongArgs
$relativePython = FakeTask
$relativePython.Actions[0].Arguments = $argumentPrefix + 'C:python.exe"'
AssertRejected $relativePython
$wrongDirectory = FakeTask
$wrongDirectory.Actions[0].WorkingDirectory = 'C:\Windows'
AssertRejected $wrongDirectory
$wrongUser = FakeTask
$wrongUser.Principal.UserId = if ($userSid -eq 'S-1-5-18') { 'S-1-5-19' } else { 'S-1-5-18' }
AssertRejected $wrongUser
'''
        environment = os.environ.copy()
        environment["OPENRC_TEST_INSTALLER"] = str(self.installer)
        result = subprocess.run([str(self.powershell), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                                 "-Command", script], capture_output=True, text=True, env=environment, timeout=30, check=False)
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
