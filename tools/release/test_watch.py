"""Offline release watcher tests. No test contacts GitHub or sleeps in real time."""
import copy
import io
import json
import subprocess
import unittest
from types import SimpleNamespace
from unittest import mock

if __package__:
    from . import watch
else:
    import watch


COMMIT = "a" * 40
TAG_OBJECT = "b" * 40
REPO = "owner/project"
TAG = "v1.2.3"
RUN_ID = 123


def options(**changes):
    values = dict(run_id=RUN_ID, repository=REPO, expected_commit=COMMIT, expected_tag=TAG,
                  once=False, poll_seconds=10, max_poll_seconds=30, timeout_seconds=1000)
    values.update(changes)
    return SimpleNamespace(**values)


def run(status="in_progress", conclusion=None):
    return dict(id=RUN_ID, repository={"full_name": REPO}, head_sha=COMMIT, head_branch=TAG,
                event="push", path=".github/workflows/ci.yml", run_attempt=1,
                status=status, conclusion=conclusion)


def job(number, name, status="in_progress", conclusion=None, steps=None):
    return dict(id=number, run_id=RUN_ID, name=name, status=status, conclusion=conclusion,
                steps=[] if steps is None else steps)


def gates():
    return [job(number, name, "completed", "success") for number, name in enumerate(sorted(watch.GATES), 1)]


class Clock:
    def __init__(self):
        self.now = 0
        self.sleeps = []

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


class GitHub:
    def __init__(self, snapshots):
        self.snapshots = snapshots
        self.index = 0
        self.in_snapshot = False
        self.requests = []
        self.fail_at = set()
        self.ref = {"ref": f"refs/tags/{TAG}", "object": {"type": "tag", "sha": TAG_OBJECT}}
        self.tag = {"sha": TAG_OBJECT, "tag": TAG, "object": {"type": "commit", "sha": COMMIT}}

    def __call__(self, endpoint, timeout):
        self.requests.append((endpoint, timeout))
        if len(self.requests) in self.fail_at:
            raise watch.TransportError("simulated outage")
        if "/git/ref/tags/" in endpoint:
            return copy.deepcopy(self.ref)
        if "/git/tags/" in endpoint:
            return copy.deepcopy(self.tag)
        snapshot = self.snapshots[min(self.index, len(self.snapshots) - 1)]
        if "/jobs?" in endpoint:
            page = int(endpoint.rsplit("page=", 1)[1])
            jobs = snapshot[1]
            return {"total_count": len(jobs), "jobs": copy.deepcopy(jobs[(page - 1) * 100:page * 100])}
        data = copy.deepcopy(snapshot[0])
        if self.in_snapshot:
            self.index += 1
        self.in_snapshot = not self.in_snapshot
        return data


class WatchTests(unittest.TestCase):
    def observe(self, github, **kwargs):
        clock, output, errors = Clock(), io.StringIO(), io.StringIO()
        result = watch.watch(options(**kwargs), api=github, clock=clock, sleep=clock.sleep,
                             out=output, err=errors)
        return result, clock.sleeps, output.getvalue(), errors.getvalue()

    def test_once_pending_and_terminal_success(self):
        pending = GitHub([(run(), [])])
        result, sleeps, output, _ = self.observe(pending, once=True)
        self.assertEqual(result, 7)
        self.assertEqual(sleeps, [])
        self.assertIn("PENDING", output)
        self.assertIn("does not prove ref type", output)
        complete = GitHub([(run("completed", "success"), gates())])
        result, sleeps, output, _ = self.observe(complete, once=True)
        self.assertEqual((result, sleeps), (0, []))
        self.assertIn("overall workflow conclusion: success", output)
        self.assertIn("bytes are not verified", output)
        self.assertEqual(sum("/git/ref/tags/" in url for url, _ in complete.requests), 2)

    def test_non_gate_alert_does_not_stop_and_overall_failure_is_explicit(self):
        failed = job(40, "NK-4 native kernel qualification (Windows)", "completed", "failure",
                     [{"number": 5, "name": "Build", "conclusion": "failure"}])
        github = GitHub([(run(), [failed]), (run(), [failed]),
                         (run("completed", "failure"), [failed, *gates()])])
        result, sleeps, output, errors = self.observe(github)
        self.assertEqual((result, sleeps), (0, [10, 15]))
        self.assertIn("overall workflow conclusion: failure", output)
        self.assertEqual(errors.count("step 5: Build"), 1)
        self.assertEqual(errors.count("job conclusion: failure"), 1)
        self.assertIn("gh run view 123 --repo owner/project --job 40 --log", errors)

    def test_gate_step_alerts_then_fails_fast_on_job_conclusion(self):
        failed_step = [{"number": 4, "name": "Reject failures", "conclusion": "failure"}]
        active = job(41, "CI required", steps=failed_step)
        failed = job(41, "CI required", "completed", "failure", failed_step)
        result, sleeps, _, errors = self.observe(GitHub([(run(), [active]), (run(), [failed])]))
        self.assertEqual((result, sleeps), (1, [10]))
        self.assertIn("step 4: Reject failures", errors)
        self.assertEqual(errors.count("step 4: Reject failures"), 1)
        self.assertIn("/actions/runs/123/job/41", errors)

    def test_cancel_skip_missing_and_failure_are_distinct(self):
        skipped = gates()
        skipped[0]["conclusion"] = "skipped"
        for snapshot, expected in [((run("completed", "cancelled"), []), 3),
                                   ((run("completed", "skipped"), []), 4),
                                   ((run("completed", "success"), skipped), 4),
                                   ((run("completed", "failure"), []), 1),
                                   ((run("completed", "success"), []), 8)]:
            with self.subTest(snapshot=snapshot):
                result, _, _, _ = self.observe(GitHub([snapshot]), once=True)
                self.assertEqual(result, expected)

    def test_job_timeout_and_cancelled_gate_fail_fast(self):
        for conclusion, code in [("timed_out", 1), ("cancelled", 3), ("skipped", 4)]:
            with self.subTest(conclusion=conclusion):
                gate = job(50, "Release builds (Windows, Linux, macOS)", "completed", conclusion)
                result, sleeps, _, _ = self.observe(GitHub([(run(), [gate])]))
                self.assertEqual((result, sleeps), (code, []))

    def test_run_identity_rejected(self):
        for field, value in [("id", 124), ("head_sha", "c" * 40), ("head_branch", "main"),
                             ("event", "workflow_dispatch"), ("path", ".github/workflows/other.yml"),
                             ("repository", {"full_name": "other/repo"})]:
            with self.subTest(field=field):
                bad = run()
                bad[field] = value
                result, sleeps, _, errors = self.observe(GitHub([(bad, [])]), once=True)
                self.assertEqual((result, sleeps), (2, []))
                self.assertIn("ERROR", errors)

    def test_ref_and_annotated_tag_are_bound_to_expected_commit(self):
        for mutation in ("lightweight", "wrong_ref", "wrong_commit", "wrong_name"):
            with self.subTest(mutation=mutation):
                github = GitHub([(run(), [])])
                if mutation == "lightweight":
                    github.ref["object"]["type"] = "commit"
                elif mutation == "wrong_ref":
                    github.ref["ref"] = "refs/tags/v9.9.9"
                elif mutation == "wrong_commit":
                    github.tag["object"]["sha"] = "c" * 40
                else:
                    github.tag["tag"] = "v9.9.9"
                result, sleeps, _, errors = self.observe(github, once=True)
                self.assertEqual((result, sleeps), (2, []))
                self.assertIn("ERROR", errors)

    def test_attempt_change_is_rejected(self):
        changed = run()
        changed["run_attempt"] = 2
        github = GitHub([(run(), []), (changed, [])])
        result, sleeps, _, errors = self.observe(github)
        self.assertEqual((result, sleeps), (2, [10]))
        self.assertIn("run attempt changed", errors)

    def test_run_completing_during_job_fetch_retries_coherently(self):
        class TransitionGitHub(GitHub):
            def __call__(self, endpoint, timeout):
                result = super().__call__(endpoint, timeout)
                if endpoint.endswith(f"/runs/{RUN_ID}") and self.index == 1 and not self.in_snapshot:
                    result["status"], result["conclusion"] = "completed", "success"
                return result

        github = TransitionGitHub([(run(), []), (run("completed", "success"), gates())])
        result, sleeps, output, errors = self.observe(github)
        self.assertEqual((result, sleeps), (0, [5]))
        self.assertEqual(output.count("Run 123 attempt"), 1)
        self.assertIn("run changed while reading jobs", errors)

    def test_unchanged_backoff_is_bounded_and_sleeps_to_deadline(self):
        github = GitHub([(run(), [])])
        result, sleeps, output, errors = self.observe(github, timeout_seconds=90)
        self.assertEqual((result, sleeps), (5, [10, 15, 22.5, 30, 12.5]))
        self.assertEqual(output.count("Run 123 attempt"), 1)
        self.assertIn("TIMEOUT", errors)
        self.assertTrue(all(0 < timeout <= 30 for _, timeout in github.requests))

    def test_transport_errors_back_off_and_exhaust_or_recover_without_losing_snapshot(self):
        outage = GitHub([(run(), [])])
        outage.fail_at = {1, 2, 3}
        result, sleeps, _, errors = self.observe(outage)
        self.assertEqual((result, sleeps), (6, [5, 10]))
        self.assertIn("observation unavailable", errors)
        one = GitHub([(run(), [])])
        one.fail_at = {1}
        self.assertEqual(self.observe(one, once=True)[:2], (6, []))
        recovery = GitHub([(run(), []), (run(), []), (run("completed", "success"), gates())])
        recovery.fail_at = {6}
        result, sleeps, output, errors = self.observe(recovery)
        self.assertEqual((result, sleeps), (0, [10, 5, 15]))
        self.assertEqual(output.count("Run 123 attempt"), 2)
        self.assertIn("observation recovered", output)
        self.assertIn("ALERT", errors)

    def test_paginated_jobs_are_all_checked(self):
        jobs = [job(number, f"job {number}", "completed", "success") for number in range(1, 102)]
        jobs.append(job(102, "CI required", "completed", "failure",
                        [{"number": 1, "name": "fail", "conclusion": "failure"}]))
        github = GitHub([(run(), jobs)])
        result, _, _, errors = self.observe(github, once=True)
        self.assertEqual(result, 1)
        self.assertIn("step 1: fail", errors)
        self.assertTrue(any("page=2" in url for url, _ in github.requests))

    def test_subprocess_is_get_only_bounded_and_does_not_expose_stderr(self):
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps({"ok": True}).encode(), stderr=b"")
        with mock.patch.object(watch.subprocess, "run", return_value=result) as process:
            self.assertEqual(watch.gh_json("repos/a/b/actions/runs/1", 12), {"ok": True})
        args, kwargs = process.call_args
        self.assertEqual(args[0], ["gh", "api", "--hostname", "github.com", "--method", "GET",
                                   "repos/a/b/actions/runs/1"])
        self.assertEqual(kwargs["timeout"], 12)
        self.assertNotIn("GH_DEBUG", kwargs["env"])
        self.assertNotIn("shell", kwargs)
        result.returncode, result.stderr = 1, b"credential-secret"
        with mock.patch.object(watch.subprocess, "run", return_value=result):
            with self.assertRaises(watch.TransportError) as error:
                watch.gh_json("repos/a/b/actions/runs/1", 12)
        self.assertNotIn("credential-secret", str(error.exception))

    def test_invalid_cli_arguments_are_rejected_before_api_access(self):
        with mock.patch.object(watch, "watch") as monitor, mock.patch("sys.stderr", new_callable=io.StringIO):
            with self.assertRaises(SystemExit) as error:
                watch.main(["--run-id", "123", "--repository", REPO, "--expected-tag", TAG,
                            "--expected-commit", "short"])
        self.assertEqual(error.exception.code, 2)
        monitor.assert_not_called()


if __name__ == "__main__":
    unittest.main()
