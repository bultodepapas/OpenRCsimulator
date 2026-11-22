"""Bounded ownership of an existing debug-frame watch during a GOD TEST run."""
from __future__ import annotations

from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import threading
import time
from typing import Any

from tools.debug.frame_watch import WatchError, WatchPolicy, Watcher

ROOT = Path(__file__).resolve().parents[2]
SOURCE_PATHS = ("tools/godtest/frame_monitor.py", "tools/debug/frame_watch.py",
                "tools/debug/frame_capture.py", "tools/debug/debugctl.py")
READY_FORMAT = "openrc-godtest-watch-ready-v1"
COVERAGE_SCOPE = "after_bridge_arm_until_owner_stop; earlier startup is not observed"
TOTALS = {"relative_stutter_total", "stall_total", "hitch_total"}


def _hash_sources() -> dict[str, str]:
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCE_PATHS}


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


class FrameMonitor:
    """Attach a passive watch to the runner's already-owned bridge session.

    The readiness file is published only after a valid cursor and identity are
    observed. The background thread has bounded socket requests and is joined
    before the owner stops the application.
    """

    def __init__(self, bridge: Any, port: int, run_dir: Path, *, timeout_s: float):
        self.bridge, self.port, self.run_dir = bridge, int(port), Path(run_dir)
        self.out = self.run_dir / "frame-watch"
        self.ready_path = self.run_dir / "frame-watch.ready.json"
        if self.ready_path.exists() or self.out.exists():
            raise ValueError("frame watch output already exists")
        self.policy = WatchPolicy(duration_s=min(86_400, max(1.0, float(timeout_s) + 30.0)), snapshot_rows=0)
        self.policy.validate()
        self.source_hashes = _hash_sources()
        self.stop_event = threading.Event()
        self.armed_event = threading.Event()
        self.finished_event = threading.Event()
        self.arm: dict[str, Any] | None = None
        self.result: dict[str, Any] | None = None
        self.exception: str | None = None
        self.watcher = Watcher(self.policy, self._fetch, self.out, now=time.monotonic,
                               sleep=self.stop_event.wait)
        self.thread = threading.Thread(target=self._run, name="godtest-frame-watch", daemon=True)

    def _fetch(self, command: str, args: dict, timeout: float) -> dict:
        try:
            return self.bridge.result_of(command, args, timeout=timeout, to_port=self.port)
        except self.bridge.Refused as error:
            if "timed out" in str(error).lower() or "timeout" in str(error).lower():
                raise TimeoutError(str(error)) from error
            raise WatchError(f"bridge refused {command}: {error}") from error

    def _publish_ready(self, arm: dict[str, Any]) -> None:
        ready = {"format": READY_FORMAT, "run_id": self.run_dir.name,
                 "identity": arm["identity"], "cursor": arm["cursor"],
                 "request_usec": arm["request_usec"], "coverage_scope": COVERAGE_SCOPE}
        temporary = self.ready_path.with_name(self.ready_path.name + ".pending")
        with temporary.open("x", encoding="utf-8") as stream:
            json.dump(ready, stream, allow_nan=False)
            stream.write("\n")
        os.replace(temporary, self.ready_path)
        self.arm = ready
        self.armed_event.set()

    def _run(self) -> None:
        try:
            self.result = self.watcher.run(should_stop=self.stop_event.is_set, on_armed=self._publish_ready)
        except Exception as error:  # retain monitor failure without losing runner cleanup
            self.exception = f"{type(error).__name__}: {error}"
        finally:
            self.finished_event.set()

    def start(self) -> None:
        self.thread.start()

    def early_failure(self) -> str | None:
        if not self.finished_event.is_set():
            return None
        if self.exception:
            return self.exception
        result = self.result or {}
        return f"watch ended before owner stop: {result.get('outcome', 'missing result')}: {result.get('error') or ''}"

    def stop(self, *, join_timeout: float = 15.0) -> dict[str, Any]:
        self.stop_event.set()
        self.thread.join(join_timeout)
        alive = self.thread.is_alive()
        result = self.result or {}
        segments = result.get("segments", [])
        frames = sum(segment.get("overall", {}).get("frames", 0) for segment in segments)
        gaps = result.get("gaps", [])
        problems = []
        if alive:
            problems.append("watch thread did not stop within the join deadline")
        if self.exception:
            problems.append(self.exception)
        if result.get("outcome") != "owner_stopped":
            problems.append(f"unexpected watch outcome: {result.get('outcome', 'missing')}")
        if result.get("error"):
            problems.append(str(result["error"]))
        if result.get("final_poll") != "complete":
            problems.append("final frame poll was not completed")
        if self.arm is None:
            problems.append("watch did not publish its armed cursor")
        if not frames:
            problems.append("watch observed no frames")
        if gaps:
            problems.append("watch recorded frame gaps")
        if len(segments) != 1:
            problems.append("watch did not retain one continuous launch and epoch")
        arm_identity = (self.arm or {}).get("identity")
        if result.get("identity") != arm_identity or result.get("stop_identity") != arm_identity:
            problems.append("watch arm and final poll identities do not match")
        for segment in segments:
            identity = {key: segment.get(key) for key in ("launch_instance", "capture_id", "epoch")}
            if identity != arm_identity:
                problems.append("watch segment identity differs from its armed identity")
            reconciliation = segment.get("reconciliation", {})
            if (set(reconciliation) != TOTALS or
                    any(item.get("agrees") is not True for item in reconciliation.values())):
                problems.append("watched frame counts did not reconcile with all bridge totals")
        arm_usec = (self.arm or {}).get("request_usec")
        stop_usec = result.get("stop_request_usec")
        observed_end = segments[-1].get("last_end_usec") if segments else None
        if (type(arm_usec) is not int or type(stop_usec) is not int or stop_usec < arm_usec or
                (observed_end is not None and stop_usec < observed_end)):
            problems.append("watch engine-clock arm or final bound is unavailable or inconsistent")
        try:
            changed = _hash_sources() != self.source_hashes
        except OSError:
            changed = True
        if changed:
            problems.append("frame-watch sources changed during the run")
        report = self.out / "watch.json"
        try:
            report_hash = _hash_file(report)
        except OSError:
            report_hash = None
            problems.append("final watch report could not be hashed")
        return {"requested": True, "status": "incomplete" if problems else "complete",
                "outcome": result.get("outcome", "thread_unavailable"),
                "error": "; ".join(problems) if problems else None,
                "run_id": self.run_dir.name, "coverage_scope": COVERAGE_SCOPE,
                "arm_request_usec": arm_usec, "stop_request_usec": stop_usec, "observed_end_usec": observed_end,
                "identity": arm_identity, "stop_identity": result.get("stop_identity"), "policy": asdict(self.policy),
                "frames_observed": frames, "gaps": gaps, "final_poll": result.get("final_poll"),
                "report_path": str(report) if report_hash else None, "report_sha256": report_hash,
                "html_path": str(self.out / "report.html") if (self.out / "report.html").is_file() else None,
                "source_sha256": self.source_hashes, "source_changed": changed, "thread_alive": alive}
