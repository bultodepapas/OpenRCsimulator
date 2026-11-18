import io
import json
import os
import threading
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from openrc_telemetry import report
from openrc_telemetry.cli import main
from openrc_telemetry.contract import ContractError, load_contracts
from openrc_telemetry.publisher import GitHub, canonical_repository, publish
from openrc_telemetry.storage import AggStore

from .support import RELEASE, SCHEMA_DIR, TempDir, unix

WEEK = "2027-W02"
NOW = unix("2027-01-19T00:00:00Z")  # after Sunday 2027-01-17 + 47 h
REPO = "Owner/telemetry-ops"
BOT = "openrc-bot[bot]"
TOKEN = "ghp_FAKE_TOKEN_for_tests_0123456789"
contracts = load_contracts(SCHEMA_DIR)


class FakeGitHub:
    """Local GitHub issues API double with injectable failure modes."""

    def __init__(self):
        self.issues = []
        self.requests = []
        self.post_mode = "ok"       # ok | drop_after | drop_before | slow_after | 500_after | 422 | wrong_body
        self.list_mode = "ok"       # ok | 500 | redirect
        self.on_post = None
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _send(self, status, payload=None, headers=None):
                data = json.dumps(payload).encode() if payload is not None else b""
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                for name, value in (headers or {}).items():
                    self.send_header(name, value)
                self.end_headers()
                self.wfile.write(data)

            def _authorized(self):
                owner.requests.append((self.command, self.path))
                if self.headers.get("Authorization") != f"Bearer {TOKEN}":
                    self._send(401, {"message": "bad credentials"})
                    return False
                return True

            def do_GET(self):
                if not self._authorized():
                    return
                if owner.list_mode == "500":
                    return self._send(500, {})
                if owner.list_mode == "redirect":
                    return self._send(302, {}, {"Location": "http://127.0.0.1:9/elsewhere"})
                query = parse_qs(urlparse(self.path).query)
                per, page = int(query["per_page"][0]), int(query["page"][0])
                self._send(200, owner.issues[(page - 1) * per: page * per])

            def do_POST(self):
                if not self._authorized():
                    return
                payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if owner.on_post:
                    owner.on_post(payload)
                mode = owner.post_mode
                if mode == "drop_before":
                    self.connection.close()
                    return
                if mode == "422":
                    return self._send(422, {"message": "Validation Failed"})
                issue = owner.add_issue(payload["title"], payload["body"])
                if mode == "drop_after":
                    self.connection.close()
                elif mode == "slow_after":
                    time.sleep(1.0)
                elif mode == "500_after":
                    self._send(500, {})
                elif mode == "wrong_body":
                    self._send(201, {**issue, "body": "tampered"})
                else:
                    self._send(201, issue)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=lambda: self.server.serve_forever(poll_interval=0.02), daemon=True)
        self.thread.start()
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"

    def add_issue(self, title, body, login=BOT, **extra):
        issue = {"number": len(self.issues) + 1, "title": title, "body": body, "user": {"login": login},
                 "state": "open", **extra}
        self.issues.append(issue)
        return issue

    def count(self, method):
        return sum(1 for m, _ in self.requests if m == method)

    def close(self):
        self.server.shutdown()
        self.server.server_close()


class PublisherCase(unittest.TestCase):
    def setUp(self):
        self._tmp = TempDir()
        self.dir = self._tmp.__enter__()
        self.agg = AggStore(self.dir / "aggregates.sqlite")
        self.fake = FakeGitHub()
        self.github = GitHub(self.fake.url, TOKEN, timeout=0.4)
        self.agg.put_day("2027-01-11", RELEASE, "gpu", "ready",
                         [{"gpu_family": "nvidia_rtx", "session_observations": 20,
                           "interval_sum_us": 20 * 600_000_000, "rendered_frames": 20 * 600 * 60}], NOW)
        self.title, self.body, self.digest = report.material(contracts, self.agg, WEEK, RELEASE)
        self.key = report.report_key(WEEK, RELEASE)

    def tearDown(self):
        self.fake.close()
        self.agg.close()
        self._tmp.__exit__()

    def go(self, *, execute=True, digest=None, now=NOW, github="default", bot=BOT, releases=frozenset({RELEASE})):
        return publish(self.agg, contracts, week=WEEK, release=RELEASE, repository=REPO,
                       approved_digest=digest or self.digest, execute=execute, now=now, releases=releases,
                       bot_author=bot, github=self.github if github == "default" else github)

    def intent(self):
        return self.agg.get_publication(canonical_repository(REPO), self.key)


class GuardTests(PublisherCase):
    def test_dry_run_prints_plan_without_side_effects(self):
        result = self.go(execute=False, github=None)
        self.assertEqual((result.outcome, result.exit_code), ("dry_run", 0))
        self.assertIn(self.digest, result.message)
        self.assertIn(REPO.lower(), result.message)
        self.assertIsNone(self.intent())
        self.assertEqual(self.fake.requests, [])

    def test_digest_mismatch_refuses_before_any_write(self):
        for digest in ("0" * 64, self.digest.upper(), ""):
            result = self.go(digest=digest or "x")
            self.assertEqual((result.outcome, result.exit_code), ("digest_mismatch", 2))
        self.assertIsNone(self.intent())
        self.assertEqual(self.fake.requests, [])

    def test_open_week_refused(self):
        result = self.go(now=unix("2027-01-18T22:59:59Z"))
        self.assertEqual(result.outcome, "not_closed")
        self.assertEqual(self.fake.requests, [])

    def test_unapproved_release_and_bad_inputs(self):
        with self.assertRaises(ContractError):
            self.go(releases=frozenset({"v9.9.9"}))
        with self.assertRaises(ContractError):
            publish(self.agg, contracts, week=WEEK, release=RELEASE, repository="not a repo",
                    approved_digest=self.digest, execute=False, now=NOW, releases=frozenset())
        with self.assertRaises(ContractError):  # an empty allowlist publishes nothing
            publish(self.agg, contracts, week=WEEK, release=RELEASE, repository=REPO,
                    approved_digest=self.digest, execute=False, now=NOW, releases=frozenset())
        self.assertEqual(self.go(bot="", github=self.github).outcome, "config_error")
        self.assertEqual(self.go(github=None).outcome, "config_error")

    def test_github_base_url_must_be_https_or_loopback(self):
        for url in ("http://example.com", "ftp://x", "file:///etc", "https://"):
            with self.assertRaises(ContractError):
                GitHub(url, TOKEN)
        GitHub("https://api.github.com", TOKEN)


class CreateTests(PublisherCase):
    def test_creates_once_records_intent_first_and_is_idempotent(self):
        seen = {}
        self.fake.on_post = lambda payload: seen.update(intent=self.intent(), payload=payload)
        result = self.go()
        self.assertEqual((result.outcome, result.issue_number, result.exit_code), ("published", 1, 0))
        # The durable intent existed, with the attempt flagged, before the POST arrived.
        self.assertEqual((seen["intent"]["state"], seen["intent"]["create_attempts"]), ("creating", 1))
        self.assertEqual(seen["payload"], {"title": self.title, "body": self.body, "labels": ["telemetry"]})
        self.assertEqual(self.intent()["state"], "published")
        self.assertEqual(self.intent()["issue_number"], 1)
        before = list(self.fake.requests)
        again = self.go()
        self.assertEqual((again.outcome, again.issue_number), ("noop", 1))
        self.assertEqual(self.fake.requests, before)
        self.assertEqual(len(self.fake.issues), 1)

    def test_changed_report_after_intent_needs_review(self):
        self.fake.list_mode = "500"
        self.assertEqual(self.go().outcome, "pending")
        self.agg.put_day("2027-01-12", RELEASE, "gpu", "suppressed", [], NOW)
        _, _, new_digest = report.material(contracts, self.agg, WEEK, RELEASE)
        result = self.go(digest=new_digest)
        self.assertEqual((result.outcome, result.exit_code), ("review_required", 3))
        self.assertEqual(self.go(digest=new_digest).outcome, "review_required")  # sticky
        self.assertEqual(self.fake.count("POST"), 0)

    def test_pagination_finds_issue_on_a_later_page(self):
        for n in range(250):
            self.fake.add_issue(f"unrelated {n}", "x", login="someone")
        self.fake.add_issue(self.title, self.body)
        result = self.go()
        self.assertEqual((result.outcome, result.issue_number), ("published", 251))
        self.assertEqual(self.fake.count("POST"), 0)
        self.assertEqual(self.fake.count("GET"), 3)

    def test_pull_requests_and_other_authors_do_not_block_or_bind(self):
        self.fake.add_issue(self.title, self.body, pull_request={"url": "x"})
        self.fake.add_issue(self.title, self.body, login="intruder")
        result = self.go()
        self.assertEqual((result.outcome, result.issue_number), ("published", 3))
        self.assertEqual(self.fake.count("POST"), 1)

    def test_crlf_and_trailing_newline_normalisation_still_matches(self):
        self.fake.add_issue(self.title, self.body.replace("\n", "\r\n").rstrip() )
        result = self.go()
        self.assertEqual((result.outcome, self.fake.count("POST")), ("published", 0))


class ReconcileTests(PublisherCase):
    def test_exact_existing_issue_is_bound_without_creating(self):
        self.fake.add_issue(self.title, self.body)
        result = self.go()
        self.assertEqual((result.outcome, result.issue_number), ("published", 1))
        self.assertEqual(self.fake.count("POST"), 0)

    def test_altered_same_key_issue_requires_review_and_is_sticky(self):
        for title, body in ((self.title, "edited body"),
                            ("different title", self.body),
                            ("another", f"hello <!-- openrc-telemetry:{self.key} --> world")):
            self.setUp_clean()
            self.fake.add_issue(title, body)
            result = self.go()
            self.assertEqual((result.outcome, result.exit_code), ("review_required", 3), title)
            self.assertEqual(self.go().outcome, "review_required")
            self.assertEqual(self.fake.count("POST"), 0)

    def setUp_clean(self):
        self.fake.issues.clear()
        self.fake.requests.clear()
        with self.agg.transaction() as conn:
            conn.execute("DELETE FROM publications")

    def test_exact_plus_altered_or_duplicate_exact_requires_review(self):
        self.fake.add_issue(self.title, self.body)
        self.fake.add_issue(self.title, "altered")
        self.assertEqual(self.go().outcome, "review_required")
        self.setUp_clean()
        self.fake.add_issue(self.title, self.body)
        self.fake.add_issue(self.title, self.body)
        self.assertEqual(self.go().outcome, "review_required")
        self.assertEqual(self.fake.count("POST"), 0)

    def test_incomplete_discovery_never_creates(self):
        self.fake.list_mode = "500"
        result = self.go()
        self.assertEqual((result.outcome, result.exit_code), ("pending", 4))
        self.assertEqual(self.fake.count("POST"), 0)
        self.fake.list_mode = "redirect"   # redirects are never followed
        self.assertEqual(self.go().outcome, "pending")
        self.assertEqual(self.fake.requests.count(("GET", "/repos/owner/telemetry-ops/issues?state=all&per_page=100&page=1")), 2)
        self.assertEqual(self.fake.count("POST"), 0)
        self.fake.list_mode = "ok"
        self.assertEqual(self.go().outcome, "published")

    def test_definitive_refusal_allows_a_clean_retry(self):
        self.fake.post_mode = "422"
        result = self.go()
        self.assertEqual((result.outcome, result.exit_code), ("rejected", 5))
        self.assertEqual((self.intent()["state"], self.intent()["create_attempts"]), ("creating", 0))
        self.fake.post_mode = "ok"
        self.assertEqual(self.go().outcome, "published")
        self.assertEqual(len(self.fake.issues), 1)

    def test_created_issue_that_differs_from_the_report_needs_review(self):
        self.fake.post_mode = "wrong_body"
        self.assertEqual(self.go().outcome, "review_required")


class UnknownOutcomeTests(PublisherCase):
    def assert_unknown_then_reconciled(self, mode, create_visible=True):
        self.fake.post_mode = mode
        first = self.go()
        self.assertEqual((first.outcome, first.exit_code), ("unknown", 4), mode)
        self.assertEqual(self.intent()["state"], "unknown")
        self.assertEqual(self.fake.count("POST"), 1)
        self.fake.post_mode = "ok"
        second = self.go()
        self.assertEqual(self.fake.count("POST"), 1, "must reconcile instead of creating again")
        if create_visible:
            self.assertEqual((second.outcome, second.issue_number), ("published", 1))
            self.assertEqual(self.intent()["state"], "published")
        else:
            self.assertEqual(second.outcome, "unknown")
            self.assertEqual(self.go().outcome, "unknown")
            self.assertEqual(self.fake.count("POST"), 1)

    def test_connection_dropped_after_server_created_issue(self):
        self.assert_unknown_then_reconciled("drop_after")

    def test_read_timeout_after_server_created_issue(self):
        self.assert_unknown_then_reconciled("slow_after")

    def test_gateway_error_after_server_created_issue(self):
        self.assert_unknown_then_reconciled("500_after")

    def test_dropped_before_creation_stays_unknown_and_never_recreates(self):
        self.assert_unknown_then_reconciled("drop_before", create_visible=False)
        self.assertEqual(len(self.fake.issues), 0)

    def test_crash_between_attempt_mark_and_result_is_treated_as_unknown(self):
        self.agg.create_publication(canonical_repository(REPO), self.key, self.digest, self.title, self.body,
                                    BOT.lower(), NOW)
        self.agg.update_publication(canonical_repository(REPO), self.key, NOW, create_attempts=1)
        result = self.go()
        self.assertEqual(result.outcome, "unknown")
        self.assertEqual(self.fake.count("POST"), 0)

    def test_token_is_sent_only_as_bearer_and_never_printed(self):
        self.fake.post_mode = "drop_after"
        result = self.go()
        self.assertNotIn(TOKEN, result.message)


class CliTests(PublisherCase):
    def run_cli(self, *argv, token=TOKEN):
        env = {"OPENRC_TELEMETRY_DATA_DIR": str(self.dir), "OPENRC_TELEMETRY_SCHEMA_DIR": str(SCHEMA_DIR),
               "OPENRC_TELEMETRY_RELEASES": RELEASE, "OPENRC_TELEMETRY_GITHUB_API": self.fake.url,
               "OPENRC_TELEMETRY_BOT_AUTHOR": BOT, "GITHUB_TOKEN": token}
        saved = {k: os.environ.get(k) for k in env}
        os.environ.update(env)
        out, err = io.StringIO(), io.StringIO()
        try:
            with redirect_stdout(out), redirect_stderr(err):
                code = main(list(argv))
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        return code, out.getvalue() + err.getvalue()

    PAST_WEEK = "2026-W40"   # 2026-09-28 .. 2026-10-04, closed in real time

    def past_digest(self):
        self.agg.put_day("2026-09-29", RELEASE, "gpu", "ready",
                         [{"gpu_family": "nvidia_rtx", "session_observations": 20,
                           "interval_sum_us": 20 * 600_000_000, "rendered_frames": 20 * 600 * 60}], NOW)
        return report.material(contracts, self.agg, self.PAST_WEEK, RELEASE)

    def test_default_dry_run_then_execute_posts_once(self):
        title, body, digest = self.past_digest()
        base = ["publish", "--week", self.PAST_WEEK, "--release", RELEASE, "--repo", REPO]
        code, output = self.run_cli(*base, "--approved-digest", digest)
        self.assertEqual((code, self.fake.requests), (0, []))
        self.assertIn("dry_run: dry-run: would post", output)
        code, output = self.run_cli(*base, "--approved-digest", "0" * 64, "--execute")
        self.assertEqual((code, self.fake.requests), (2, []))
        self.assertIn("digest_mismatch", output)
        code, output = self.run_cli(*base, "--approved-digest", digest, "--execute")
        self.assertEqual(code, 0)
        self.assertIn("published: created issue #1", output)
        self.assertNotIn(TOKEN, output)
        self.assertEqual(self.fake.issues[0]["title"], title)
        code, output = self.run_cli(*base, "--approved-digest", digest, "--execute")
        self.assertEqual((code, self.fake.count("POST")), (0, 1))
        self.assertIn("noop", output)

    def test_execute_without_token_is_a_config_error(self):
        _, _, digest = self.past_digest()
        code, output = self.run_cli("publish", "--week", self.PAST_WEEK, "--release", RELEASE, "--repo", REPO,
                                    "--approved-digest", digest, "--execute", token="")
        self.assertEqual(code, 2)
        self.assertIn("config_error", output)

    def test_cli_rejects_both_flags(self):
        with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
            main(["publish", "--week", WEEK, "--release", RELEASE, "--repo", REPO, "--approved-digest", "x",
                  "--dry-run", "--execute"])


if __name__ == "__main__":
    unittest.main()
