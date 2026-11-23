"""Startup failures must not turn the container or real-client smoke test green."""
from __future__ import annotations

import io
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.telemetry import wait_for_health as health


class Clock:
    def __init__(self):
        self.now = 0.0
        self.sleeps = []

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


def response(status=200, body=b'{"status":"ok"}'):
    result = io.BytesIO(body)
    result.status = status
    return result


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.monotonic = patch.object(health.time, "monotonic", lambda: self.clock.now)
        self.sleep = patch.object(health.time, "sleep", self.clock.sleep)
        self.monotonic.start()
        self.sleep.start()
        self.addCleanup(self.monotonic.stop)
        self.addCleanup(self.sleep.stop)

    def wait(self, **kwargs):
        health.wait_for_health("http://127.0.0.1:8787/healthz", timeout=1, interval=0.25, **kwargs)

    def test_positive_contract_finishes_without_sleep(self):
        with patch.object(health, "_open_health", return_value=response()) as request:
            self.wait()
        request.assert_called_once()
        self.assertEqual(self.clock.sleeps, [])

    def test_startup_connection_failure_then_healthy(self):
        with patch.object(health, "_open_health", side_effect=[OSError("starting"), response()]) as request:
            self.wait()
        self.assertEqual(request.call_count, 2)
        self.assertEqual(self.clock.sleeps, [0.25])

    def test_failed_requests_exhaust_deadline_instead_of_succeeding(self):
        with patch.object(health, "_open_health", side_effect=OSError("unavailable")) as request:
            with self.assertRaisesRegex(TimeoutError, "not healthy"):
                self.wait()
        self.assertEqual(request.call_count, 4)
        self.assertEqual(self.clock.now, 1.0)

    def test_non_200_success_statuses_also_have_deadline_and_backoff(self):
        for status in (201, 202, 204):
            with self.subTest(status=status):
                self.clock.now = 0
                self.clock.sleeps.clear()
                with patch.object(health, "_open_health", side_effect=lambda *a, **k: response(status)):
                    with self.assertRaises(TimeoutError):
                        self.wait()
                self.assertEqual(self.clock.sleeps, [0.25] * 4)

    def test_invalid_or_unhealthy_bodies_cannot_signal_ready(self):
        for body in (b"", b"not json", b"[]", b"null", b"{}", b'{"status":"down"}', b"x" * 4097):
            with self.subTest(body=body[:30]):
                self.clock.now = 0
                with patch.object(health, "_open_health", side_effect=lambda *a, **k: response(body=body)):
                    with self.assertRaises(TimeoutError):
                        self.wait()

    def test_http_error_does_not_bypass_deadline(self):
        error = urllib.error.HTTPError("http://127.0.0.1/healthz", 503, "starting", {}, None)
        with patch.object(health, "_open_health", side_effect=error):
            with self.assertRaises(TimeoutError):
                self.wait()

    def test_exited_receiver_stops_without_network_attempt(self):
        with patch.object(health, "_open_health") as request:
            with self.assertRaisesRegex(RuntimeError, "receiver exited"):
                self.wait(is_alive=lambda: False)
        request.assert_not_called()

    def test_single_request_timeout_never_exceeds_remaining_budget(self):
        with patch.object(health, "_open_health", side_effect=OSError("starting")) as request:
            with self.assertRaises(TimeoutError):
                self.wait(request_timeout=10)
        self.assertEqual([call.kwargs["timeout"] for call in request.call_args_list], [1, 0.75, 0.5, 0.25])

    def test_late_positive_response_is_rejected(self):
        def late(*args, **kwargs):
            self.clock.now = 2
            return response()
        with patch.object(health, "_open_health", side_effect=late):
            with self.assertRaisesRegex(TimeoutError, "after the deadline"):
                self.wait()

    def test_invalid_budgets_are_rejected(self):
        for name in ("timeout", "interval", "request_timeout"):
            for value in (0, -1, float("nan"), float("inf")):
                with self.subTest(name=name, value=value), self.assertRaises(ValueError):
                    health.wait_for_health("http://127.0.0.1/healthz", **{name: value})

    def test_redirect_does_not_pass_at_an_unrelated_endpoint(self):
        paths = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                paths.append(self.path)
                if self.path == "/healthz":
                    self.send_response(302)
                    self.send_header("Location", "/unrelated")
                    self.end_headers()
                else:
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b'{"status":"ok"}')

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with self.assertRaises(TimeoutError):
                health.wait_for_health(f"http://127.0.0.1:{server.server_port}/healthz", timeout=1, interval=0.25)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertEqual(paths, ["/healthz"] * 4)


if __name__ == "__main__":
    unittest.main()
