"""Watch a running session for FPS drops, stutters, stalls and freezes (PT1h-R15-S2).

The watcher polls the debug bridge with cheap incremental ``frames since=<cursor> lean=true passive=true``
reads, keeps every received row in a bounded client buffer and evaluates its triggers on the raw
``wall_usec`` intervals across poll boundaries. A trigger opens one incident; when its recovery has been
observed, the incident's rows are written from client memory and, optionally, one bounded
``openrc-debug-frames v1`` snapshot adds the bridge's event context and the standard HTML/Perfetto export.

Everything measured is a wall interval between bridge process callbacks: not presented frames, CPU busy
time or GPU completion. Triggers are screening rules, not perceptual thresholds or causes.
"""
from __future__ import annotations

import bisect
import collections
import heapq
import html
import json
import math
import os
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable

WATCH_FORMAT = "openrc-debug-frame-watch v1"
INCIDENT_FORMAT = "openrc-debug-frame-incident v1"
ROWS_FORMAT = "openrc-debug-frame-rows v1"
RELATIVE_STUTTER, ABSOLUTE_STALL, LEGACY_HITCH, OVER_BUDGET, DIAGNOSTIC_QUERY = 1, 2, 4, 8, 16
COLUMNS = ("end_usec", "wall_usec", "process_frame", "physics_ticks", "gpu_ms", "baseline_ms", "flags",
           "observer_usec", "route")
_TOTALS = ("relative_stutter_total", "stall_total", "hitch_total", "event_total")
TRIGGERS = ("stall", "stutter", "sustained", "drop", "hang")
RING = 7200
MAX_INCIDENT_ROWS = 7200
MAX_TRIGGERS_PER_INCIDENT = 200
TOP_FRAMES = 5000  # exact slowest-frame tail kept for 1% / 0.1% lows
MAX_SECONDS = 86_400
MAX_ROUTES = 32
MAX_SEGMENTS = 1000
DROP_MIN_BASELINE_S = 3.0
FINAL_FILES_RESERVE = 16 << 20  # output kept free for watch.json, report.html and seconds.csv
FREEZE_CONFIRM_S = 0.25  # second ping after a timed-out poll; an unchanged engine frame confirms a freeze
# Histogram: 0.05 ms bins to 50 ms, then 1 ms bins to 1 s, then one overflow bin (exact max kept separately).
_FINE, _FINE_END, _COARSE, _COARSE_END = 0.05, 50.0, 1.0, 1000.0
_BINS = int(_FINE_END / _FINE) + int((_COARSE_END - _FINE_END) / _COARSE) + 1


class WatchError(ValueError):
    """Invalid policy, protocol violation or a refused output."""


@dataclass
class WatchPolicy:
    triggers: tuple[str, ...] = TRIGGERS
    target_fps: float | None = None      # None: use the bridge's target (read, never changed)
    stutter_min_ms: float | None = None  # a stutter opens an incident only above this; None: the target budget
    sustained_frames: int = 30           # consecutive intervals above target budget + tolerance
    rearm_frames: int = 30               # consecutive in-budget intervals before the run trigger re-arms
    drop_fraction: float = 0.25          # mean callback rate falls by at least this fraction ...
    drop_min_ms: float = 1.0             # ... and the mean interval grows by at least this many ms
    drop_window_s: float = 1.0           # short window compared with ...
    drop_baseline_s: float = 10.0        # ... the median interval of the preceding baseline (same route)
    drop_settle_s: float = 2.0           # no drop screening this long after start, a route change or a gap
    hang_s: float = 2.0                  # a frames poll (main thread) unanswered this long while ping answers
    lead_frames: int = 600               # rows kept before the first trigger
    recovery_frames: int = 300           # rows observed after the last trigger before the incident closes
    max_incident_frames: int = 3600      # an incident longer than this closes as span_capped
    snapshot_rows: int = 1200            # bounded v1 fetch at close; 0 disables it (rows are kept regardless)
    max_incidents: int = 10              # later triggers are counted, not captured
    poll_s: float = 0.5
    duration_s: float = 600.0
    request_timeout_s: float = 2.0
    lost_s: float = 10.0                 # no answer at all (frames or ping) this long ends the watch
    max_output_bytes: int = 256 << 20

    def validate(self) -> None:
        unknown = set(self.triggers) - set(TRIGGERS)
        if not self.triggers or unknown:
            raise WatchError(f"triggers must be a nonempty subset of {','.join(TRIGGERS)}")
        checks = [
            (self.target_fps is None or 1 <= self.target_fps <= 1000, "target_fps must be in [1, 1000]"),
            (self.stutter_min_ms is None or 0 <= self.stutter_min_ms <= 10_000, "stutter_min_ms must be in [0, 10000]"),
            (1 <= self.sustained_frames <= RING, f"sustained_frames must be in [1, {RING}]"),
            (1 <= self.rearm_frames <= RING, f"rearm_frames must be in [1, {RING}]"),
            (0.05 <= self.drop_fraction <= 0.9, "drop_fraction must be in [0.05, 0.9]"),
            (0 <= self.drop_min_ms <= 1000, "drop_min_ms must be in [0, 1000]"),
            (0.1 <= self.drop_window_s <= 30, "drop_window_s must be in [0.1, 30]"),
            (self.drop_window_s < self.drop_baseline_s <= 120, "drop_baseline_s must exceed drop_window_s, at most 120"),
            (0 <= self.drop_settle_s <= 120, "drop_settle_s must be in [0, 120]"),
            (0.2 <= self.hang_s <= 600, "hang_s must be in [0.2, 600]"),
            (0 <= self.lead_frames <= RING, f"lead_frames must be in [0, {RING}]"),
            (1 <= self.recovery_frames <= RING, f"recovery_frames must be in [1, {RING}]"),
            (self.lead_frames + self.recovery_frames < self.max_incident_frames <= MAX_INCIDENT_ROWS,
             f"max_incident_frames must exceed lead + recovery and be at most {MAX_INCIDENT_ROWS}"),
            (0 <= self.snapshot_rows <= RING, f"snapshot_rows must be in [0, {RING}]"),
            (0 <= self.max_incidents <= 100, "max_incidents must be in [0, 100]"),
            (0.05 <= self.poll_s <= 10, "poll_s must be in [0.05, 10]"),
            (1 <= self.duration_s <= MAX_SECONDS, f"duration_s must be in [1, {MAX_SECONDS}]"),
            (0.2 <= self.request_timeout_s <= 120, "request_timeout_s must be in [0.2, 120]"),
            (self.request_timeout_s <= self.lost_s <= 3600, "lost_s must be at least request_timeout_s, at most 3600"),
            (2 * FINAL_FILES_RESERVE <= self.max_output_bytes <= 4 << 30, "max_output_bytes must be in [32 MiB, 4 GiB]"),
        ]
        for ok, message in checks:
            if not ok:
                raise WatchError(message)


def policy_from_args(args: dict[str, Any]) -> WatchPolicy:
    """Build a policy from debugctl key=value arguments (already JSON-decoded)."""
    policy = WatchPolicy()
    names = {f for f in policy.__dataclass_fields__}
    for key, value in args.items():
        if key not in names:
            raise WatchError(f"unknown watch option {key!r}")
        if key == "triggers":
            if type(value) is not str:
                raise WatchError("triggers must be a comma-separated list")
            value = tuple(item.strip() for item in value.split(",") if item.strip())
        elif type(value) is bool or type(value) not in (int, float):
            raise WatchError(f"{key} must be a number")
        elif isinstance(getattr(policy, key), int) and key not in ("target_fps", "stutter_min_ms"):
            if value != int(value):
                raise WatchError(f"{key} must be an integer")
            value = int(value)
        else:
            value = float(value)
            if not math.isfinite(value):
                raise WatchError(f"{key} must be finite")
        setattr(policy, key, value)
    policy.validate()
    return policy


# ---- streaming statistics -----------------------------------------------------------------------------------------

def _bin(ms: float) -> int:
    if ms < _FINE_END:
        return int(ms / _FINE)
    if ms < _COARSE_END:
        return int(_FINE_END / _FINE) + int((ms - _FINE_END) / _COARSE)
    return _BINS - 1


def _bin_upper(index: int) -> float:
    fine = int(_FINE_END / _FINE)
    if index < fine:
        return (index + 1) * _FINE
    if index < _BINS - 1:
        return _FINE_END + (index - fine + 1) * _COARSE
    return math.inf


@dataclass
class Stats:
    """Exact counts plus histogram percentiles (stated resolution) and an exact bounded slow tail."""
    frames: int = 0
    wall_us: int = 0
    over_budget_frames: int = 0
    slow_us: int = 0
    excess_us: float = 0.0
    relative_stutter_frames: int = 0
    stall_frames: int = 0
    hitch_frames: int = 0
    diagnostic_query_frames: int = 0
    max_us: int = 0
    hist: list[int] = field(default_factory=lambda: [0] * _BINS)
    top: list[int] = field(default_factory=list)

    def add(self, wall_us: int, flags: int, slow_threshold_us: float, budget_us: float) -> None:
        self.frames += 1
        self.wall_us += wall_us
        if wall_us > slow_threshold_us:
            self.over_budget_frames += 1
            self.slow_us += wall_us
            self.excess_us += wall_us - budget_us
        self.relative_stutter_frames += bool(flags & RELATIVE_STUTTER)
        self.stall_frames += bool(flags & ABSOLUTE_STALL)
        self.hitch_frames += bool(flags & LEGACY_HITCH)
        self.diagnostic_query_frames += bool(flags & DIAGNOSTIC_QUERY)
        self.max_us = max(self.max_us, wall_us)
        self.hist[_bin(wall_us / 1000)] += 1
        if len(self.top) < TOP_FRAMES:
            heapq.heappush(self.top, wall_us)
        elif wall_us > self.top[0]:
            heapq.heapreplace(self.top, wall_us)

    def _percentile(self, q: float) -> float | None:
        rank = max(1, math.ceil(q * self.frames))
        seen = 0
        for index, count in enumerate(self.hist):
            seen += count
            if seen >= rank:
                upper = _bin_upper(index)
                return round(self.max_us / 1000 if math.isinf(upper) else min(upper, self.max_us / 1000), 3)
        return None

    def _low(self, fraction: float) -> tuple[float | None, int, str]:
        tail = max(1, math.floor(self.frames * fraction))
        status = "available" if self.frames >= round(1 / fraction) else "short_sample"
        if tail <= len(self.top):
            slowest = heapq.nlargest(tail, self.top)
            return round(1_000_000 * tail / sum(slowest), 1), tail, status
        # Beyond the exact retained tail: sum the slowest bins at their midpoints (the exact max for the overflow).
        remaining, total_ms = tail, 0.0
        for index in range(_BINS - 1, -1, -1):
            take = min(remaining, self.hist[index])
            if take:
                upper = _bin_upper(index)
                lower = _bin_upper(index - 1) if index else 0.0
                total_ms += take * (self.max_us / 1000 if math.isinf(upper) else (lower + upper) / 2)
                remaining -= take
            if not remaining:
                break
        return round(1000 * tail / total_ms, 1), tail, "histogram_approximation"

    def report(self) -> dict[str, Any]:
        if self.frames == 0:
            return {"frames": 0}
        low1, n1, s1 = self._low(0.01)
        low01, n01, s01 = self._low(0.001)
        return {
            "frames": self.frames, "duration_s": round(self.wall_us / 1e6, 3),
            "fps_mean": round(self.frames * 1e6 / self.wall_us, 1),
            "fps_1pct_low": low1, "low_1pct_frames": n1, "low_1pct_status": s1,
            "fps_01pct_low": low01, "low_01pct_frames": n01, "low_01pct_status": s01,
            "p50_ms": self._percentile(0.5), "p95_ms": self._percentile(0.95), "p99_ms": self._percentile(0.99),
            "p999_ms": self._percentile(0.999), "max_ms": round(self.max_us / 1000, 3),
            "percentile_method": "nearest rank on a histogram; value is the bin upper edge capped by the exact max",
            "percentile_resolution_ms": {"below_50_ms": _FINE, "50_to_1000_ms": _COARSE},
            "over_budget_frames": self.over_budget_frames,
            "over_budget_percent": round(100 * self.over_budget_frames / self.frames, 3),
            "slow_time_percent": round(100 * self.slow_us / self.wall_us, 3),
            "budget_excess_ms": round(self.excess_us / 1000, 3),
            "relative_stutter_frames": self.relative_stutter_frames, "stall_frames": self.stall_frames,
            "hitch_frames": self.hitch_frames, "diagnostic_query_frames": self.diagnostic_query_frames,
        }


# ---- triggers -----------------------------------------------------------------------------------------------------

class DropDetector:
    """Sustained relative slowdown on wall time: catches FPS drops that stay above the target budget.

    Duration windows (not row counts) keep 60 and 240 FPS comparable. The short window's median interval is compared
    with the baseline, the median interval of the
    preceding ``drop_baseline_s`` (at least ``DROP_MIN_BASELINE_S`` observed) of the same route, recomputed every
    250 ms of data time and frozen while a drop is active, so a long drop cannot absorb itself.

    After a start, route change, gap, new segment or a recovered drop, intervals during ``drop_settle_s`` are ignored
    and screening resumes once ``drop_window_s`` plus the minimum baseline have been observed: with the defaults the
    detector is blind for 2 + 1 + 3 = 6 s. A recovered drop rebuilds its baseline from post-recovery intervals only.
    """

    def __init__(self, policy: WatchPolicy):
        self.p = policy
        self.reset(None)

    def blind_s(self) -> float:
        return self.p.drop_settle_s + self.p.drop_window_s + min(self.p.drop_baseline_s, DROP_MIN_BASELINE_S)

    def reset(self, start_us: int | None) -> None:
        self.rows: collections.deque[tuple[int, int]] = collections.deque()  # (end_us, wall_us), baseline+window
        self.short: collections.deque[tuple[int, int]] = collections.deque()
        self.settle_until = None if start_us is None else start_us + int(self.p.drop_settle_s * 1e6)
        self.observed_from = start_us
        self.baseline_ms: float | None = None
        self.baseline_at = 0
        self.checked_at = 0
        self.active_ref: float | None = None

    def feed(self, end_us: int, wall_us: int) -> dict[str, Any] | None:
        if self.observed_from is None:
            self.reset(end_us - wall_us)
        if end_us <= self.settle_until:
            return None  # transitional intervals (loading, route switch) never enter the baseline
        window_us = int(self.p.drop_window_s * 1e6)
        span_us = window_us + int(self.p.drop_baseline_s * 1e6)
        self.rows.append((end_us, wall_us))
        while self.rows and self.rows[0][0] - self.rows[0][1] < end_us - span_us:
            self.rows.popleft()
        self.short.append((end_us, wall_us))
        while self.short and self.short[0][0] - self.short[0][1] < end_us - window_us:
            self.short.popleft()
        minimum_us = window_us + int(min(self.p.drop_baseline_s, DROP_MIN_BASELINE_S) * 1e6)
        if end_us - self.settle_until < minimum_us:
            return None
        # Medians make one long stall a stall, not a drop: a drop moves most intervals. Evaluate every 50 ms of
        # data time so a 1000 FPS menu does not sort a window per row.
        if end_us - self.checked_at < 50_000:
            return None
        self.checked_at = end_us
        if self.active_ref is None and (self.baseline_ms is None or end_us - self.baseline_at >= 250_000):
            cutoff = end_us - window_us
            values = sorted(w for e, w in self.rows if e <= cutoff)
            if values:
                self.baseline_ms = values[len(values) // 2] / 1000
                self.baseline_at = end_us
        if self.baseline_ms is None or not self.short:
            return None
        current = sorted(w for _, w in self.short)
        median_ms = current[len(current) // 2] / 1000
        if self.active_ref is not None:
            if median_ms < self.active_ref / (1 - self.p.drop_fraction / 2):
                # Recovered (hysteresis: half the trigger drop). The baseline window still holds the slow level:
                # rebuild it from post-recovery intervals so a second drop is measured against normal pacing.
                self.reset(end_us - int(self.p.drop_settle_s * 1e6))
            return None
        if (median_ms >= self.baseline_ms / (1 - self.p.drop_fraction)
                and median_ms - self.baseline_ms >= self.p.drop_min_ms):
            self.active_ref = self.baseline_ms
            return {"baseline_ms": round(self.baseline_ms, 3), "window_median_ms": round(median_ms, 3),
                    "baseline_fps": round(1000 / self.baseline_ms, 1), "window_fps": round(1000 / median_ms, 1),
                    "drop_percent": round(100 * (1 - self.baseline_ms / median_ms), 1)}
        return None


# ---- the watcher --------------------------------------------------------------------------------------------------

Fetch = Callable[[str, dict, float], dict]


class Watcher:
    """One owned watch session. ``fetch(cmd, args, timeout)`` returns the bridge result or raises."""

    def __init__(self, policy: WatchPolicy, fetch: Fetch, out: Path, *, now: Callable[[], float],
                 sleep: Callable[[float], None], log: Callable[[str], None] = lambda text: None):
        policy.validate()
        self.p, self.fetch, self.now, self.sleep, self.log = policy, fetch, now, sleep, log
        self.out = Path(out)
        if self.out.exists():
            raise WatchError(f"watch directory already exists: {self.out}")
        self.rows: collections.deque[dict[str, Any]] = collections.deque(maxlen=RING)
        self.segments: list[dict[str, Any]] = []
        self.segment: dict[str, Any] | None = None
        self.incidents: list[dict[str, Any]] = []
        self.incident: dict[str, Any] | None = None
        self.triggers_not_captured: collections.Counter = collections.Counter()
        self.gaps: list[dict[str, Any]] = []
        self.hangs: list[dict[str, Any]] = []
        self.bytes_written = 0
        self.polls = self.poll_failures = 0
        self.poll_rows_max = 0
        self.outcome = "running"
        self.identity: dict[str, Any] = {}
        self.observer_fetch_after: int | None = None
        self.observer_excluded_rows = 0
        self.slow_polls = 0
        self.error: str | None = None
        self._poll_sent = 0.0
        self._poll_timed_out = False

    # -- segment and row handling --

    def _new_segment(self, reply: dict[str, Any], reason: str) -> None:
        if self.incident is not None:
            self._close_incident("partial", f"segment_ended:{reason}")
        if len(self.segments) >= MAX_SEGMENTS:
            raise WatchError(f"more than {MAX_SEGMENTS} epoch/launch segments: the recorder keeps resetting")
        self.observer_fetch_after = None  # a sequence of the old epoch means nothing in the new one
        policy = {k: reply[k] for k in ("target_fps", "budget_tolerance_ms", "stutter_factor", "stutter_min_extra_ms",
                                        "stall_ms", "hitch_ms", "factor")}
        target = self.p.target_fps or float(policy["target_fps"])
        budget_us = 1e6 / target
        self.segment = {
            "index": len(self.segments) + 1, "reason": reason, "epoch": reply["epoch"],
            "capture_id": reply["capture_id"], "launch_instance": reply["launch_instance"],
            "bridge_policy": policy, "target_fps": target, "budget_ms": budget_us / 1000,
            "slow_threshold_ms": budget_us / 1000 + float(policy["budget_tolerance_ms"]),
            "cursor": None, "first_sequence": None, "last_sequence": None, "rows_lost": 0,
            "totals_start": None, "totals_end": None, "origin_usec": None, "last_end_usec": None,
            "stats": Stats(), "routes": {}, "seconds": [], "run": 0, "good": 0, "run_armed": True,
            "drop": DropDetector(self.p), "last_route": None,
        }
        if reason != "start":
            # A new epoch or launch began after the watch was armed: all its rows are new evidence.
            self.segment.update(cursor=0, totals_start=dict.fromkeys(_TOTALS, 0), totals_end=dict.fromkeys(_TOTALS, 0))
        self.segments.append(self.segment)
        self.rows.clear()

    def _totals(self, reply: dict[str, Any]) -> dict[str, int]:
        return {k: int(reply[k]) for k in _TOTALS}

    def _accept(self, reply: dict[str, Any]) -> None:
        """Validate one lean reply against the current segment and feed its rows."""
        if reply.get("format") != ROWS_FORMAT:
            raise WatchError("the bridge does not support lean incremental frames (update the app)")
        seg = self.segment
        if seg is None:
            self._new_segment(reply, "start")
            seg = self.segment
        elif reply["launch_instance"] != seg["launch_instance"]:
            # Another process may reuse the same epoch number: never read its rows with the old cursor.
            self._new_segment(reply, "launch_changed")
            return
        elif reply["since_status"] == "epoch_changed" or reply["epoch"] != seg["epoch"]:
            self._new_segment(reply, "epoch_changed")
            return  # rows (if any) belong to a request made with the old cursor: re-poll from the new epoch
        if seg["cursor"] is None:
            # First reply of a segment: start after the newest row; history before arming is not screened.
            seg["cursor"] = int(reply["frames_total"])
            seg["totals_start"] = self._totals(reply)
            seg["totals_end"] = self._totals(reply)
            return
        status = reply["since_status"]
        if status == "cursor_ahead_of_history":
            raise WatchError("bridge history moved backwards inside one epoch")
        n = int(reply["frames"])
        if n:
            first = int(reply["first_sequence"])
            if first <= seg["cursor"]:
                raise WatchError("bridge returned rows at or before the cursor")
            lost = first - seg["cursor"] - 1
            if lost:
                seg["rows_lost"] += lost
                self.gaps.append({"segment": seg["index"], "after_sequence": seg["cursor"], "rows": lost,
                                  "reason": status})
                self._interrupt(seg, "gap")
            samples = reply["samples"]
            if any(len(samples[c]) != n for c in COLUMNS):
                raise WatchError("lean reply columns disagree with its frame count")
            for i in range(n):
                row = {c: samples[c][i] for c in COLUMNS}
                row["sequence"] = first + i
                self._feed(seg, row, contiguous=(i > 0 or not lost))
        seg["cursor"] = int(reply["frames_total"])
        seg["totals_end"] = self._totals(reply)

    def _interrupt(self, seg: dict[str, Any], why: str) -> None:
        seg["run"] = 0
        seg["good"] = 0
        seg["run_armed"] = True
        seg["drop"].reset(None)
        seg["last_end_usec"] = None
        if self.incident is not None and why == "gap":
            self.incident["gaps"] += 1

    def _feed(self, seg: dict[str, Any], row: dict[str, Any], contiguous: bool) -> None:
        end, wall = int(row["end_usec"]), int(row["wall_usec"])
        if wall <= 0 or (contiguous and seg["last_end_usec"] is not None and end - wall != seg["last_end_usec"]):
            raise WatchError(f"rows are not contiguous wall intervals at sequence {row['sequence']}")
        seg["last_end_usec"] = end
        if seg["origin_usec"] is None:
            seg["origin_usec"] = end - wall
            seg["first_sequence"] = row["sequence"]
        seg["last_sequence"] = row["sequence"]
        self.rows.append(row)
        flags, route = int(row["flags"]), str(row["route"])
        slow_us, budget_us = seg["slow_threshold_ms"] * 1000, seg["budget_ms"] * 1000
        seg["stats"].add(wall, flags, slow_us, budget_us)
        if route not in seg["routes"] and len(seg["routes"]) >= MAX_ROUTES:
            route = "(other)"
        seg["routes"].setdefault(route, Stats()).add(wall, flags, slow_us, budget_us)
        second = (end - seg["origin_usec"]) // 1_000_000
        if second < MAX_SECONDS:
            while len(seg["seconds"]) <= second:
                seg["seconds"].append([0, 0, 0, 0, 0])  # frames, wall_us, max_us, over_budget, events
            bucket = seg["seconds"][second]
            bucket[0] += 1
            bucket[1] += wall
            bucket[2] = max(bucket[2], wall)
            bucket[3] += wall > slow_us
            bucket[4] += bool(flags & (RELATIVE_STUTTER | ABSOLUTE_STALL))
        if seg["last_route"] is not None and route != seg["last_route"]:
            seg["drop"].reset(None)  # a different workload is not a drop
        seg["last_route"] = route
        found = []
        # The watcher's own bounded snapshot fetch lands on the next interval it flags: never let it trigger. The
        # drop detector still sees it (one interval cannot move a median); run counters are left unchanged.
        if (self.observer_fetch_after is not None and row["sequence"] > self.observer_fetch_after
                and flags & DIAGNOSTIC_QUERY):
            self.observer_fetch_after = None
            self.observer_excluded_rows += 1
            seg["drop"].feed(end, wall)
        else:
            if "stall" in self.p.triggers and flags & ABSOLUTE_STALL:
                found.append({"kind": "stall", "ms": wall / 1000})
            # Uncapped sessions flag many relative spikes that still meet the target budget (13 ms after 8 ms
            # frames); they stay counted in the statistics but only a budget-breaking stutter opens an incident.
            stutter_floor_ms = seg["slow_threshold_ms"] if self.p.stutter_min_ms is None else self.p.stutter_min_ms
            if ("stutter" in self.p.triggers and flags & RELATIVE_STUTTER and wall / 1000 > stutter_floor_ms
                    and not (flags & ABSOLUTE_STALL and "stall" in self.p.triggers)):
                found.append({"kind": "stutter", "ms": wall / 1000, "baseline_ms": row["baseline_ms"]})
            if wall > slow_us:
                seg["run"] += 1
                seg["good"] = 0
                if "sustained" in self.p.triggers and seg["run_armed"] and seg["run"] >= self.p.sustained_frames:
                    seg["run_armed"] = False
                    found.append({"kind": "sustained", "frames": seg["run"], "target_fps": seg["target_fps"]})
            else:
                seg["run"] = 0
                seg["good"] += 1
                if seg["good"] >= self.p.rearm_frames:
                    seg["run_armed"] = True
            drop = seg["drop"].feed(end, wall)
            if drop and "drop" in self.p.triggers:
                found.append({"kind": "drop", **drop})
        for trigger in found:
            trigger.update(sequence=row["sequence"], end_usec=end, route=route,
                           diagnostic_query=bool(flags & DIAGNOSTIC_QUERY))
            self._trigger(seg, trigger)
        if self.incident is not None:
            inc = self.incident
            inc["last_sequence"] = row["sequence"]
            if row["sequence"] - inc["last_trigger_sequence"] >= self.p.recovery_frames:
                self._close_incident("complete", "recovered")
            elif row["sequence"] - inc["first_sequence"] + 1 >= self.p.max_incident_frames:
                self._close_incident("partial", "span_capped")

    def _trigger(self, seg: dict[str, Any], trigger: dict[str, Any]) -> None:
        inc = self.incident
        if inc is None:
            if len(self.incidents) >= self.p.max_incidents or seg["first_sequence"] is None:
                self.triggers_not_captured[trigger["kind"]] += 1
                return
            first = max(seg["first_sequence"], trigger["sequence"] - self.p.lead_frames)
            buffered = self.rows[0]["sequence"] if self.rows else trigger["sequence"]
            inc = self.incident = {
                "id": len(self.incidents) + 1, "segment": seg["index"], "epoch": seg["epoch"],
                "capture_id": seg["capture_id"], "first_sequence": max(first, buffered),
                "requested_first_sequence": trigger["sequence"] - self.p.lead_frames,
                "first_trigger_sequence": trigger["sequence"], "last_trigger_sequence": trigger["sequence"],
                "last_sequence": trigger["sequence"], "triggers": [], "trigger_counts": collections.Counter(),
                "gaps": 0, "opened_at_s": round(self.now() - self.started, 3),
            }
            self.log(f"incident {inc['id']}: {trigger['kind']} at sequence {trigger['sequence']}"
                     f" ({trigger.get('ms', trigger.get('window_fps', ''))})")
        inc["last_trigger_sequence"] = trigger["sequence"]
        inc["trigger_counts"][trigger["kind"]] += 1
        if len(inc["triggers"]) < MAX_TRIGGERS_PER_INCIDENT:
            inc["triggers"].append({k: (round(v, 3) if isinstance(v, float) else v) for k, v in trigger.items()})

    def _close_incident(self, outcome: str, reason: str) -> None:
        inc, self.incident = self.incident, None
        rows = [r for r in self.rows if inc["first_sequence"] <= r["sequence"] <= inc["last_sequence"]]
        lead_missing = max(0, inc["first_sequence"] - max(1, inc["requested_first_sequence"]))
        inc.update(outcome=outcome if not inc["gaps"] else "partial", close_reason=reason,
                   lead_rows=inc["first_trigger_sequence"] - inc["first_sequence"],
                   lead_rows_missing=lead_missing, recovery_rows=inc["last_sequence"] - inc["last_trigger_sequence"],
                   trigger_counts=dict(inc["trigger_counts"]), frames=len(rows))
        previous = self.incidents[-1] if self.incidents else None
        if previous is not None and previous["segment"] == inc["segment"] and previous["last_sequence"] >= inc["first_sequence"]:
            inc["lead_overlaps_incident"] = previous["id"]  # context only: worst_ms below excludes the lead-up
        if rows:
            walls = [int(r["wall_usec"]) for r in rows]
            own = [int(r["wall_usec"]) for r in rows if r["sequence"] >= inc["first_trigger_sequence"]]
            lead = [int(r["wall_usec"]) for r in rows if r["sequence"] < inc["first_trigger_sequence"]]
            inc["worst_ms"] = max(own) / 1000 if own else None
            inc["lead_worst_ms"] = max(lead) / 1000 if lead else None
            inc["start_usec"] = int(rows[0]["end_usec"]) - walls[0]
            inc["end_usec"] = int(rows[-1]["end_usec"])
            inc["routes"] = sorted({str(r["route"]) for r in rows})
        self.incidents.append(inc)  # recorded first: an interrupt during the files below cannot lose it
        directory = self.out / f"incident-{inc['id']:03d}"
        incident_cap = self.p.max_output_bytes - FINAL_FILES_RESERVE
        # After the segment ended the bridge may describe another epoch or process: keep the client rows only.
        snapshot = None
        if reason.startswith("segment_ended"):
            inc["capture_error"] = "segment ended before the snapshot"
        elif self.bytes_written > incident_cap - (8 << 20):
            inc["capture_error"] = "output budget reserved for the session report"
        else:
            snapshot = self._snapshot(inc)
        if snapshot is not None:
            try:
                from tools.debug.frame_capture import write_capture
                paths = write_capture(snapshot, directory / "capture")
                inc["capture"] = {k: os.path.relpath(v, self.out) for k, v in paths.items()}
                self.bytes_written += sum(Path(v).stat().st_size for v in paths.values())
            except (ValueError, OSError) as error:
                inc["capture_error"] = str(error)
        payload = {"format": INCIDENT_FORMAT, "version": 1, "identity": self.identity, "incident": inc,
                   "columns": list(COLUMNS) + ["sequence"],
                   "rows": {c: [r[c] for r in rows] for c in list(COLUMNS) + ["sequence"]},
                   "notes": ["Rows are copied from lean bridge polls; this is not an openrc-debug-frames v1 snapshot.",
                             "Wall callback intervals, not presented frames; triggers are screening rules, not causes."]}
        try:
            self._write(directory / "incident.json", payload, limit=incident_cap)
        except WatchError as error:
            inc["rows_file_error"] = str(error)  # the summary still lists the incident
        self.log(f"incident {inc['id']} {inc['outcome']} ({reason}): {inc['frames']} rows, worst "
                 f"{inc.get('worst_ms') or 0:.1f} ms from the first trigger -> {directory}")

    def _snapshot(self, inc: dict[str, Any]) -> dict[str, Any] | None:
        """One bounded v1 newest-window snapshot covering the incident, for event context and the HTML export."""
        if self.p.snapshot_rows == 0:
            return None
        seg = self.segment
        since = max(inc["first_sequence"] - 1, seg["cursor"] - self.p.snapshot_rows)
        try:
            report = self.fetch("frames", {"since": since, "epoch": inc["epoch"], "window": self.p.snapshot_rows,
                                           "samples": True, "events": 200, "passive": True},
                                self.p.request_timeout_s * 4)
        except Exception as error:  # noqa: BLE001 - recorded, the client rows remain the evidence
            inc["capture_error"] = f"snapshot request failed: {error}"
            return None
        self.observer_fetch_after = int(report.get("frames_total", seg["cursor"]))
        if (report.get("epoch") != inc["epoch"] or report.get("since_status") == "epoch_changed"
                or report.get("source", {}).get("launch_instance") != seg["launch_instance"]):
            inc["capture_error"] = "epoch or launch changed before the snapshot"
            return None
        if not report.get("frames"):
            inc["capture_error"] = "snapshot selected no rows"
            return None
        inc["capture_first_sequence"] = report["first_sequence"]
        inc["capture_last_sequence"] = report["last_sequence"]
        # A long incident can exceed snapshot_rows: the capture then holds its newest part only.
        inc["capture_covers_first_trigger"] = report["first_sequence"] <= inc["first_trigger_sequence"]
        return report

    def _write(self, path: Path, payload: Any, limit: int | None = None) -> None:
        data = (json.dumps(payload, ensure_ascii=True, allow_nan=False, separators=(",", ":")) + "\n").encode()
        if self.bytes_written + len(data) > (self.p.max_output_bytes if limit is None else limit):
            raise WatchError("watch output would exceed max_output_bytes")
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("xb") as stream:
            stream.write(data)
        self.bytes_written += len(data)

    # -- polling --

    def _poll(self) -> bool:
        """One incremental read. Returns False when the bridge did not answer."""
        seg = self.segment
        args: dict[str, Any] = {"lean": True, "passive": True}
        if seg is not None and seg["cursor"] is not None:
            args.update(since=seg["cursor"], epoch=seg["epoch"])
        else:
            args.update(since=1 << 52)  # an empty, cheap first read: identity and cursor only
        self._poll_sent = self.now()
        self._poll_timed_out = False
        try:
            # The main thread answers `frames` within one callback; waiting hang_s without an answer is the freeze test.
            reply = self.fetch("frames", args, self.p.hang_s)
        except WatchError:
            raise
        except TimeoutError:  # socket.timeout is TimeoutError; debugctl maps a managed-session timeout to it
            self.poll_failures += 1
            self._poll_timed_out = True
            return False
        except Exception:  # noqa: BLE001 - refused/closed/garbled: liveness only, never a freeze by itself
            self.poll_failures += 1
            return False
        self.polls += 1
        self.poll_rows_max = max(self.poll_rows_max, int(reply.get("frames", 0)))
        self._accept(reply)
        if not self.identity:
            self.identity = {"launch_instance": reply["launch_instance"], "capture_id": reply["capture_id"],
                             "epoch": reply["epoch"]}
        return True

    def _ping(self) -> dict[str, Any] | None:
        try:
            return self.fetch("ping", {"passive": True}, min(1.0, self.p.request_timeout_s))
        except Exception:  # noqa: BLE001 - no answer at all
            return None

    def _observe_freeze(self, ping: dict[str, Any]) -> None:
        """`ping` is answered by the bridge network thread, `frames` by the main thread within one callback. A
        `frames` poll unanswered for `hang_s` while ping answers is a main-thread freeze of at least that long. Its
        duration is a client-side lower bound (poll sent .. last ping), not a measured frame; when the main thread
        resumes, the recorder's next interval measures the real length."""
        frame, now = int(ping.get("frame", -1)), self.now()
        if self.segment is not None and ping.get("launch_instance") not in (None, self.segment["launch_instance"]):
            return  # another launch answers: the next frames poll starts a new segment
        freeze = self._freeze
        if freeze is None:
            if not self._poll_timed_out:
                return  # a refused or closed connection is not evidence of a frozen main thread
            # Confirm with a second ping: an engine frame counter that does not move is a frozen main thread; one
            # that moves means the poll itself was slow (transport, admission), not the game.
            self.sleep(FREEZE_CONFIRM_S)
            again = self._ping()
            if again is None or int(again.get("frame", -1)) != frame:
                self.slow_polls += 1
                return
            now = self.now()
            seg = self.segment
            hang = {"engine_frame": frame, "detected_at_s": round(now - self.started, 3),
                    "segment": seg["index"] if seg else None, "sequence_before": seg["cursor"] if seg else None,
                    "observed_s": round(now - self._poll_sent, 3), "engine_frame_advanced": False, "resolved": False}
            self._freeze = {"frame": frame, "since": self._poll_sent, "last_seen": now, "hang": hang}
            self.hangs.append(hang)
            self.log(f"main thread unresponsive for at least {now - self._poll_sent:.1f} s (engine frame {frame})")
            if "hang" in self.p.triggers and seg is not None and seg["cursor"]:
                self._trigger(seg, {"kind": "hang", "sequence": seg["cursor"], "engine_frame": frame,
                                    "route": seg["last_route"], "diagnostic_query": False, "end_usec": None})
            return
        freeze["last_seen"] = now
        freeze["hang"]["observed_s"] = round(now - freeze["since"], 3)
        freeze["hang"]["engine_frame_advanced"] |= frame != freeze["frame"]

    def _end_freeze(self) -> None:
        freeze, self._freeze = self._freeze, None
        if freeze is not None:
            freeze["hang"]["resolved"] = True

    def run(self) -> dict[str, Any]:
        self.started = self.now()
        self._freeze: dict[str, Any] | None = None
        self.out.mkdir(parents=True, exist_ok=False)
        last_answer = self.started
        try:
            while self.now() - self.started < self.p.duration_s:
                tick = self.now()
                if self._poll():
                    last_answer = self.now()
                    self._end_freeze()  # the main thread answered: any freeze is over
                else:
                    ping = self._ping()
                    if ping is None:
                        if self.now() - last_answer >= self.p.lost_s:
                            self.outcome = "bridge_lost"
                            break
                    else:
                        last_answer = self.now()
                        self._observe_freeze(ping)
                self.sleep(max(0.0, self.p.poll_s - (self.now() - tick)))
            else:
                self.outcome = "duration_reached"
                self._poll()  # one last read so the rows after the previous poll are observed too
        except KeyboardInterrupt:
            self.outcome = "interrupted"
        except WatchError as error:  # protocol violation or output cap: keep everything gathered so far
            self.outcome, self.error = "protocol_error", str(error)
            self.log(f"watch stopped: {error}")
        except Exception as error:  # noqa: BLE001 - never lose an hour of watching to an unexpected failure
            self.outcome, self.error = "internal_error", f"{type(error).__name__}: {error}"
            self.log(f"watch stopped: {self.error}")
        if self.incident is not None:
            try:
                self._close_incident("partial", "watch_ended")
            except (KeyboardInterrupt, Exception) as error:  # noqa: BLE001
                self.error = self.error or f"closing the last incident: {error}"
        summary = self.summary()
        self._write(self.out / "watch.json", summary)
        self._write_text(self.out / "report.html", build_html(summary))
        self._write_seconds_csv()
        return summary

    def _write_text(self, path: Path, text: str) -> None:
        data = text.encode("utf-8")
        if self.bytes_written + len(data) > self.p.max_output_bytes:
            raise WatchError("watch output would exceed max_output_bytes")
        with path.open("xb") as stream:
            stream.write(data)
        self.bytes_written += len(data)

    def _write_seconds_csv(self) -> None:
        lines = ["segment,second,frames,fps,max_ms,over_budget_frames,stutter_or_stall_frames"]
        for seg in self.segments:
            for second, (frames, wall, worst, over, events) in enumerate(seg["seconds"]):
                fps = f"{frames * 1e6 / wall:.1f}" if wall else ""
                lines.append(f"{seg['index']},{second},{frames},{fps},{worst / 1000:.3f},{over},{events}")
        self._write_text(self.out / "seconds.csv", "\n".join(lines) + "\n")

    def summary(self) -> dict[str, Any]:
        segments = []
        for seg in self.segments:
            exact = seg["rows_lost"] == 0 and seg["totals_start"] is not None
            reconcile = {}
            if seg["totals_start"] is not None:
                stats = seg["stats"]
                seen = {"relative_stutter_total": stats.relative_stutter_frames, "stall_total": stats.stall_frames,
                        "hitch_total": stats.hitch_frames}
                for key, value in seen.items():
                    bridge = seg["totals_end"][key] - seg["totals_start"][key]
                    reconcile[key] = {"watched_rows": value, "bridge_delta": bridge,
                                      "agrees": value == bridge if exact else None}
            segments.append({
                "index": seg["index"], "reason": seg["reason"], "epoch": seg["epoch"], "capture_id": seg["capture_id"],
                "launch_instance": seg["launch_instance"], "bridge_policy": seg["bridge_policy"],
                "target_fps": seg["target_fps"], "budget_ms": round(seg["budget_ms"], 4),
                "slow_threshold_ms": round(seg["slow_threshold_ms"], 4),
                "first_sequence": seg["first_sequence"], "last_sequence": seg["last_sequence"],
                "origin_usec": seg["origin_usec"], "rows_lost": seg["rows_lost"],
                "coverage": "contiguous" if seg["rows_lost"] == 0 else "gaps_counts_are_lower_bounds",
                "overall": seg["stats"].report(),
                "routes": {route: stats.report() for route, stats in seg["routes"].items()},
                "reconciliation": reconcile,
                "seconds": [[i, b[0], round(b[0] * 1e6 / b[1], 1) if b[1] else None, round(b[2] / 1000, 3), b[3], b[4]]
                            for i, b in enumerate(seg["seconds"])],
            })
        return {
            "format": WATCH_FORMAT, "version": 1, "outcome": self.outcome, "error": self.error,
            "identity": self.identity, "slow_polls": self.slow_polls,
            "drop_blind_s": DropDetector(self.p).blind_s(),
            "policy": {k: (list(v) if isinstance(v, tuple) else v) for k, v in asdict(self.p).items()},
            "elapsed_s": round(self.now() - self.started, 3), "polls": self.polls,
            "poll_failures": self.poll_failures, "poll_rows_max": self.poll_rows_max,
            "observer_excluded_rows": self.observer_excluded_rows,
            "gaps": self.gaps, "hangs": self.hangs,
            "incidents": [{k: v for k, v in i.items() if k not in ("trigger_counts",)} | {"trigger_counts": i["trigger_counts"]}
                          for i in self.incidents],
            "triggers_not_captured": dict(self.triggers_not_captured),
            "segments": segments,
            "seconds_columns": ["second", "frames", "fps", "max_ms", "over_budget_frames", "stutter_or_stall_frames"],
            "notes": [
                "Wall callback intervals between bridge process callbacks: not presented frames, CPU or GPU time.",
                "Statistics are per segment (epoch/launch) and per route; menus, loading and flight are not pooled.",
                "Percentiles come from a fixed histogram (stated resolution); 1%/0.1% lows use the exact slowest tail.",
                "Rows evicted before a poll are counted as gaps; counts in a segment with gaps are lower bounds.",
                "A hang is a ping-observed frozen engine frame counter; its duration is a client-side lower bound.",
                "Triggers are screening rules, not perceptual thresholds or causes.",
            ],
        }


# ---- HTML session report --------------------------------------------------------------------------------------------

def _svg_series(seconds: list[list[Any]], incidents: list[dict[str, Any]], origin: int | None, target: float) -> str:
    width, height, pad = 960, 220, 32
    points = [(s[0], s[2]) for s in seconds if s[2] is not None]
    if not points:
        return "<p>No complete seconds recorded.</p>"
    top = max(max(p[1] for p in points), target) * 1.1
    span = max(1, seconds[-1][0])
    x = lambda second: pad + (width - 2 * pad) * second / span  # noqa: E731
    y = lambda fps: height - pad - (height - 2 * pad) * fps / top  # noqa: E731
    path = " ".join(f"{'M' if i == 0 else 'L'}{x(s):.1f},{y(f):.1f}" for i, (s, f) in enumerate(points))
    marks = []
    for inc in incidents:
        if origin is not None and inc.get("start_usec") is not None:
            start = (inc["start_usec"] - origin) / 1e6
            end = (inc["end_usec"] - origin) / 1e6
            marks.append(f'<rect class="inc" x="{x(start):.1f}" y="{pad}" width="{max(2.0, x(end) - x(start)):.1f}" '
                         f'height="{height - 2 * pad}"><title>incident {inc["id"]}</title></rect>')
    return (f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="Callback FPS per second">'
            f'{"".join(marks)}<line class="target" x1="{pad}" x2="{width - pad}" y1="{y(target):.1f}" y2="{y(target):.1f}"/>'
            f'<path class="fps" d="{path}"/><text x="{pad}" y="{pad - 8}">FPS per second (max {top / 1.1:.0f}); '
            f'dashed: target {target:g}; shaded: incidents</text></svg>')


def build_html(summary: dict[str, Any]) -> str:
    e = lambda value: html.escape(str(value))  # noqa: E731
    stopped = f" Stopped by: {e(summary['error'])}." if summary.get("error") else ""
    parts = [f"<h1>Frame watch</h1><p>Outcome <b>{e(summary['outcome'])}</b>{stopped} {e(summary['elapsed_s'])} s, "
             f"{len(summary['incidents'])} incident(s), {len(summary['gaps'])} gap(s), {len(summary['hangs'])} freeze(s).</p>"]
    for seg in summary["segments"]:
        o = seg["overall"]
        parts.append(f"<h2>Segment {seg['index']} ({e(seg['reason'])}, epoch {seg['epoch']}, {e(seg['coverage'])})</h2>")
        incidents = [i for i in summary["incidents"] if i["segment"] == seg["index"]]
        parts.append(_svg_series(seg["seconds"], incidents, seg.get("origin_usec"), seg["target_fps"]))
        if o.get("frames"):
            parts.append("<table><tr><th>Route</th><th>Frames</th><th>s</th><th>FPS</th><th>1% low</th><th>0.1% low</th>"
                         "<th>p99 ms</th><th>max ms</th><th>over budget</th><th>stutters</th><th>stalls</th></tr>")
            for name, r in [("(all)", o)] + sorted(seg["routes"].items()):
                if not r.get("frames"):
                    continue
                parts.append(f"<tr><td>{e(name)}</td><td>{r['frames']}</td><td>{r['duration_s']}</td><td>{r['fps_mean']}</td>"
                             f"<td>{e(r['fps_1pct_low'])}</td><td>{e(r['fps_01pct_low'])}</td><td>{r['p99_ms']}</td>"
                             f"<td>{r['max_ms']}</td><td>{r['over_budget_percent']}%</td>"
                             f"<td>{r['relative_stutter_frames']}</td><td>{r['stall_frames']}</td></tr>")
            parts.append("</table>")
    if summary["incidents"]:
        parts.append("<h2>Incidents</h2><table><tr><th>#</th><th>Outcome</th><th>Triggers</th><th>Rows</th>"
                     "<th>Worst ms</th><th>Routes</th><th>Files</th></tr>")
        for inc in summary["incidents"]:
            link = inc.get("capture", {}).get("html")
            files = f'<a href="{e(link)}">report</a>' if link else e(inc.get("capture_error", "rows only"))
            parts.append(f"<tr><td>{inc['id']}</td><td>{e(inc['outcome'])} ({e(inc['close_reason'])})</td>"
                         f"<td>{e(inc['trigger_counts'])}</td><td>{inc['frames']}</td><td>{e(inc.get('worst_ms'))}</td>"
                         f"<td>{e(', '.join(inc.get('routes', [])))}</td><td>{files}</td></tr>")
        parts.append("</table>")
    parts.append("<ul>" + "".join(f"<li>{e(n)}</li>" for n in summary["notes"]) + "</ul>")
    return _HTML.replace("__BODY__", "\n".join(parts))


_HTML = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Frame watch</title><style>
:root{--bg:#fff;--fg:#1d2330;--muted:#5b6475;--line:#d7dbe3;--fps:#2563eb;--inc:rgba(220,38,38,.18);--target:#16a34a}
@media (prefers-color-scheme:dark){:root{--bg:#12151c;--fg:#e6e9ef;--muted:#9aa3b5;--line:#2c3240;--fps:#7aa2ff;--inc:rgba(248,113,113,.22);--target:#4ade80}}
body{background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,sans-serif;margin:0 auto;max-width:1000px;padding:16px}
table{border-collapse:collapse;width:100%;margin:8px 0 16px;font-variant-numeric:tabular-nums}
th,td{border-bottom:1px solid var(--line);padding:4px 6px;text-align:left}th{color:var(--muted);font-weight:600}
svg{width:100%;height:auto}svg text{fill:var(--muted);font-size:12px}.fps{fill:none;stroke:var(--fps);stroke-width:1.5}
.inc{fill:var(--inc)}.target{stroke:var(--target);stroke-dasharray:4 4}li{color:var(--muted)}a{color:var(--fps)}
</style></head><body>__BODY__</body></html>
"""
