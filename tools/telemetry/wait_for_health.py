"""Bounded readiness for the local telemetry receiver and its container smoke test."""
from __future__ import annotations

import argparse
import http.client
import json
import math
import time
import urllib.request


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


def _open_health(url, *, timeout):
    # The requested endpoint must be healthy; an unrelated redirected endpoint
    # must not satisfy the contract or receive a request from an offline check.
    return urllib.request.build_opener(_NoRedirect()).open(url, timeout=timeout)


def wait_for_health(url: str, *, timeout: float = 30, interval: float = 0.2,
                    request_timeout: float = 1, is_alive=None) -> None:
    """Require HTTP 200 and the receiver's positive health contract before the deadline.

    Retries apply only to service startup, never to a failed test or batch submission.
    Check the deadline and process state on *every* response, including other 2xx
    statuses and invalid JSON; an HTTP response alone does not establish readiness.
    The caller must also bound the whole process: urllib's socket timeout is an
    inactivity limit, not a hard total deadline for an arbitrarily slow response.
    """
    if any(not math.isfinite(value) or value <= 0
           for value in (timeout, interval, request_timeout)):
        raise ValueError("health timeouts and interval must be finite and positive")
    deadline = time.monotonic() + timeout
    last_error = "no response"
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"receiver not healthy after {timeout:g}s: {last_error}")
        if is_alive is not None and not is_alive():
            raise RuntimeError("receiver exited before becoming healthy")
        try:
            with _open_health(url, timeout=min(request_timeout, remaining)) as response:
                body = response.read(4097)
                if response.status == 200 and len(body) <= 4096:
                    payload = json.loads(body)
                    if isinstance(payload, dict) and payload.get("status") == "ok":
                        if time.monotonic() < deadline:
                            return
                        last_error = "health response arrived after the deadline"
                    else:
                        last_error = "unexpected health JSON"
                else:
                    last_error = f"unexpected HTTP status or oversized body ({response.status})"
        except (OSError, ValueError, http.client.HTTPException) as error:
            # Report the category, not an arbitrary response body or request URL.
            last_error = type(error).__name__
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"receiver not healthy after {timeout:g}s: {last_error}")
        time.sleep(min(interval, remaining))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    try:
        wait_for_health(args.url, timeout=args.timeout)
    except (TimeoutError, RuntimeError, ValueError) as error:
        parser.exit(1, f"Telemetry readiness failed: {error}\n")
    print("Receiver health contract passed (HTTP 200, status=ok).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
