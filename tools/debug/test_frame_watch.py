"""Deterministic contracts for the PT1h-R15-S2 frame watcher against a simulated bridge (no app, no timing)."""
from __future__ import annotations

import json
import math
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))  # `tools.debug.frame_capture` imports, as under debugctl

from tools.debug import frame_watch as fw  # noqa: E402
from tools.debug import frame_capture as capture  # noqa: E402


class FakeBridge:
    """Implements the bridge's `frames` (window/since/epoch/lean/samples) and `ping` contracts on synthetic frames.

    `frames` is a generator of (wall_usec, route) or ("freeze", seconds). Time advances only through the fake clock.
    Flags follow the bridge rules: relative stutter (preceding 60-frame upper median, >= 8 samples), absolute stall
    (> 50 ms), legacy hitch, over budget (60 FPS + 0.5 ms) and the diagnostic-query flag after each `frames` query.
    """

    def __init__(self, frames, *, heavy_fetch_extra_us=0):
        self.source = iter(frames)
        self.t = 0.0
        self.clock_us = 1_000_000
        self.rows = []  # dicts with sequence
        self.total = 0
        self.epoch = 1
        self.launch = "a" * 32
        self.engine_frame = 100
        self.query_pending = False
        self.frozen_until = None
        self.carry_us = 0  # wall time already elapsed toward the next frame
        self.pending = None
        self.dead = False
        self.heavy_fetch_extra_us = heavy_fetch_extra_us
        self.extra_next_us = 0
        self.totals = dict.fromkeys(fw._TOTALS, 0)
        self.calls = []

    # -- time --
    def now(self):
        return self.t

    def sleep(self, seconds):
        self.advance(seconds)

    def advance(self, seconds):
        target = self.t + seconds
        while True:
            if self.frozen_until is not None:
                if self.frozen_until > target:
                    self.t = target
                    return
                # The frozen callback resumes: one long interval covers the whole freeze.
                self.t = self.frozen_until
                self.frozen_until = None
                self._record(self.pending_freeze_us, self.pending_route)
                continue
            if self.pending is None:
                try:
                    self.pending = next(self.source)
                except StopIteration:
                    self.pending = (16_000, "flight")
            if self.pending[0] == "freeze":
                self.pending_freeze_us = int(self.pending[1] * 1e6)
                self.pending_route = self.rows[-1]["route"] if self.rows else "flight"
                self.frozen_until = self.t + self.pending[1]
                self.pending = None
                continue
            wall = int(self.pending[0]) + self.extra_next_us
            remaining = (wall - self.carry_us) / 1e6
            if self.t + remaining > target:
                self.carry_us += int((target - self.t) * 1e6)
                self.t = target
                return
            self.t += remaining
            self.carry_us = 0
            self.extra_next_us = 0
            self._record(wall, self.pending[1])
            self.pending = None

    def _record(self, wall, route):
        self.clock_us += wall
        self.engine_frame += 1
        self.total += 1
        previous = [r["wall_usec"] for r in self.rows[-60:]] if self.rows and self.rows[-1]["epoch"] == self.epoch else []
        baseline = sorted(previous)[len(previous) // 2] / 1000 if previous else 0.0
        ms = wall / 1000
        flags = 0
        if len(previous) >= 8 and ms > 1.5 * baseline and ms - baseline > 4:
            flags |= fw.RELATIVE_STUTTER
            self.totals["relative_stutter_total"] += 1
        if ms > 50:
            flags |= fw.ABSOLUTE_STALL
            self.totals["stall_total"] += 1
        if ms > max(50, 3 * baseline):
            flags |= fw.LEGACY_HITCH
            self.totals["hitch_total"] += 1
        if flags & 7:
            self.totals["event_total"] += 1
        if ms > 1000 / 60 + 0.5:
            flags |= fw.OVER_BUDGET
        if self.query_pending:
            flags |= fw.DIAGNOSTIC_QUERY
        self.query_pending = False
        self.rows.append({"sequence": self.total, "epoch": self.epoch, "end_usec": self.clock_us, "wall_usec": wall,
                          "process_frame": self.engine_frame, "physics_ticks": 4, "gpu_ms": -1.0,
                          "baseline_ms": baseline, "flags": flags, "observer_usec": 20, "route": route})
        if len(self.rows) > fw.RING:
            del self.rows[0]

    # -- protocol --
    def reset_epoch(self):
        self.epoch += 1
        self.total = 0
        self.rows = []
        self.totals = dict.fromkeys(fw._TOTALS, 0)

    def restart(self):
        self.reset_epoch()
        self.epoch = 1
        self.launch = "b" * 32

    def fetch(self, cmd, args, timeout):
        self.calls.append((cmd, dict(args)))
        if self.dead:
            self.advance(timeout)
            raise ConnectionError("refused")
        if cmd == "ping":
            return {"frame": self.engine_frame, "launch_instance": self.launch}
        assert cmd == "frames"
        if self.frozen_until is not None:
            self.advance(timeout)
            if self.frozen_until is not None:
                raise TimeoutError("timed out")
        epoch_rows = self.rows
        available = len(epoch_rows)
        window = int(args.get("window", available))
        status = ""
        if "since" in args:
            since = int(args["since"])
            if "epoch" in args and args["epoch"] != self.epoch:
                window, status = 0, "epoch_changed"
            elif since > self.total:
                window, status = 0, "cursor_ahead_of_history"
            else:
                after = self.total - since
                window = min(after, window)
                status = "rows_evicted_after_cursor" if after > available else "contiguous"
        window = min(window, available)
        selected = epoch_rows[available - window:] if window else []
        self.query_pending = True
        samples = {c: [r[c] for r in selected] for c in fw.COLUMNS}
        common = {"epoch": self.epoch, "capture_id": f"9-1-{self.epoch}", "frames_total": self.total,
                  "first_sequence": selected[0]["sequence"] if selected else 0,
                  "last_sequence": self.total if selected else 0, "frames": len(selected),
                  "retained_frames": available, "since_status": status, "target_fps": 60.0,
                  "budget_tolerance_ms": 0.5, "stutter_factor": 1.5, "stutter_min_extra_ms": 4.0, "stall_ms": 50.0,
                  "hitch_ms": 50.0, "factor": 3.0, **self.totals, "samples": samples}
        if args.get("lean"):
            return {"format": fw.ROWS_FORMAT, "launch_instance": self.launch, **common}
        self.extra_next_us = self.heavy_fetch_extra_us
        flags = samples["flags"]
        walls = samples["wall_usec"]
        return {**common, "format": capture.FORMAT, "version": 1, "clock": "godot_ticks_usec",
                "timing_scope": "bridge_process_wall_intervals_not_presentation",
                "frames_evicted": max(0, self.total - fw.RING), "budget_ms": 1000 / 60, "slow_threshold_ms": 1000 / 60 + 0.5,
                "sample_start_usec": samples["end_usec"][0] - walls[0], "sample_end_usec": samples["end_usec"][-1],
                "duration_s": sum(walls) / 1e6, "flag_bits": dict(capture.FLAG_BITS),
                "source": {"display_server": "headless", "launch_instance": self.launch},
                "hitches": [], "stutters": [], "p50_ms": 16.0,
                "over_budget_frames": sum(bool(f & 8) for f in flags)}


def steady(seconds, wall_us=16_000, route="flight"):
    return [(wall_us, route)] * int(seconds * 1e6 / wall_us)


def watch(frames, *, tmp, bridge=None, **policy):
    bridge = bridge or FakeBridge(frames)
    options = {"duration_s": 30.0, "snapshot_rows": 0}
    options.update(policy)
    p = fw.WatchPolicy(**options)
    w = fw.Watcher(p, bridge.fetch, Path(tmp) / "watch", now=bridge.now, sleep=bridge.sleep)
    return w.run(), bridge, Path(tmp) / "watch"


class FrameWatchTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()

    def test_steady_flight_has_no_incident_and_exact_reconciliation(self):
        summary, bridge, out = watch(steady(40), tmp=self.tmp)
        self.assertEqual(summary["outcome"], "duration_reached")
        self.assertEqual(summary["incidents"], [])
        seg = summary["segments"][0]
        self.assertEqual(seg["coverage"], "contiguous")
        self.assertGreater(seg["overall"]["frames"], 1700)
        self.assertEqual(seg["overall"]["fps_mean"], 62.5)
        self.assertTrue(all(item["agrees"] for item in seg["reconciliation"].values()))
        self.assertTrue((out / "report.html").is_file() and (out / "seconds.csv").is_file())
        polls = [args for cmd, args in bridge.calls if cmd == "frames"]
        self.assertTrue(all(a.get("lean") and a.get("passive") for a in polls))
        self.assertTrue(all("epoch" in a for a in polls[1:]))

    def test_single_stall_opens_one_incident_with_lead_and_recovery(self):
        frames = steady(15) + [(80_000, "flight")] + steady(20)
        summary, _, out = watch(frames, tmp=self.tmp)
        self.assertEqual(len(summary["incidents"]), 1)
        inc = summary["incidents"][0]
        self.assertEqual(inc["outcome"], "complete")
        self.assertEqual(inc["trigger_counts"], {"stall": 1})
        self.assertEqual(inc["lead_rows"], 600)
        self.assertEqual(inc["recovery_rows"], 300)
        self.assertAlmostEqual(inc["worst_ms"], 80.0)
        rows = json.loads((out / "incident-001" / "incident.json").read_text())
        self.assertEqual(rows["format"], fw.INCIDENT_FORMAT)
        self.assertEqual(len(rows["rows"]["wall_usec"]), inc["frames"])
        self.assertEqual(rows["rows"]["sequence"][0], inc["first_sequence"])

    def test_small_stutter_below_stall_threshold_is_caught(self):
        frames = steady(10) + [(33_000, "flight")] + steady(10)
        summary, _, _ = watch(frames, tmp=self.tmp)
        self.assertEqual(summary["incidents"][0]["trigger_counts"], {"stutter": 1})

    def test_sustained_low_fps_triggers_budget_run_and_drop_in_one_incident(self):
        frames = steady(15) + steady(5, 25_000) + steady(15)
        summary, _, _ = watch(frames, tmp=self.tmp)
        self.assertEqual(len(summary["incidents"]), 1)
        counts = summary["incidents"][0]["trigger_counts"]
        self.assertEqual(counts.get("sustained"), 1)
        self.assertEqual(counts.get("drop"), 1)

    def test_drop_above_target_budget_is_detected(self):
        frames = steady(15, 7_143) + steady(5, 13_333) + steady(15, 7_143)
        summary, _, _ = watch(frames, tmp=self.tmp)
        self.assertEqual(len(summary["incidents"]), 1)
        inc = summary["incidents"][0]
        # The step is also a burst of relative stutters until the bridge's median adapts; no budget run exists.
        self.assertEqual(inc["trigger_counts"].get("drop"), 1)
        self.assertNotIn("sustained", inc["trigger_counts"])
        self.assertNotIn("stall", inc["trigger_counts"])
        drop = next(t for t in inc["triggers"] if t["kind"] == "drop")
        self.assertGreater(drop["baseline_fps"], 135)
        self.assertLessEqual(drop["window_fps"], 140 * 0.75 + 0.1)  # fires when the 1 s mean crosses the 25% line
        self.assertGreaterEqual(drop["drop_percent"], 25.0)
        seg = summary["segments"][0]
        self.assertEqual(seg["overall"]["over_budget_frames"], 0)

    def test_route_change_is_not_a_drop(self):
        frames = steady(15, 3_000, "home") + steady(20, 10_000, "flight")
        summary, _, _ = watch(frames, tmp=self.tmp, triggers=("drop",))
        self.assertEqual(summary["incidents"], [])
        self.assertEqual(set(summary["segments"][0]["routes"]), {"home", "flight"})

    def test_slow_drift_inside_menu_noise_does_not_trigger_drop(self):
        frames = steady(15, 1_000, "home") + steady(10, 1_500, "home")  # 33% slower but only +0.5 ms: below drop_min_ms
        summary, _, _ = watch(frames, tmp=self.tmp, triggers=("drop",))
        self.assertEqual(summary["incidents"], [])

    def test_late_polls_count_evicted_rows_as_gaps(self):
        frames = steady(30, 1_000)  # 1000 FPS for a 10 s poll interval: 10,000 rows > 7,200-row ring
        summary, _, _ = watch(frames, tmp=self.tmp, poll_s=10.0, duration_s=25.0, triggers=("stall",))
        seg = summary["segments"][0]
        self.assertGreater(seg["rows_lost"], 0)
        self.assertEqual(seg["coverage"], "gaps_counts_are_lower_bounds")
        self.assertTrue(all(item["agrees"] is None for item in seg["reconciliation"].values()))
        self.assertTrue(summary["gaps"] and summary["gaps"][0]["reason"] == "rows_evicted_after_cursor")

    def test_epoch_reset_starts_a_new_segment_and_reads_its_first_rows(self):
        bridge = FakeBridge(steady(60))
        original = bridge.sleep
        done = []

        def sleep(seconds):
            original(seconds)
            if bridge.t > 10 and not done:
                done.append(1)
                bridge.reset_epoch()
        bridge.sleep = sleep
        summary, _, _ = watch(None, tmp=self.tmp, bridge=bridge, duration_s=20.0)
        self.assertEqual([s["reason"] for s in summary["segments"]], ["start", "epoch_changed"])
        second = summary["segments"][1]
        self.assertEqual(second["first_sequence"], 1)
        self.assertEqual(second["coverage"], "contiguous")
        self.assertTrue(all(item["agrees"] for item in second["reconciliation"].values()))

    def test_process_restart_with_the_same_epoch_number_is_a_new_segment(self):
        bridge = FakeBridge(steady(60))
        original = bridge.sleep
        done = []

        def sleep(seconds):
            original(seconds)
            if bridge.t > 10 and not done:
                done.append(1)
                bridge.restart()
                bridge.advance(3.0)  # the new process already has rows when the watcher next polls
        bridge.sleep = sleep
        summary, _, _ = watch(None, tmp=self.tmp, bridge=bridge, duration_s=20.0)
        self.assertEqual([s["reason"] for s in summary["segments"]], ["start", "launch_changed"])
        self.assertEqual(summary["segments"][1]["first_sequence"], 1)
        self.assertEqual(summary["segments"][1]["epoch"], 1)

    def test_main_thread_freeze_is_seen_through_ping_and_recovers_as_a_stall(self):
        frames = steady(10) + [("freeze", 5.0)] + steady(20)
        summary, _, _ = watch(frames, tmp=self.tmp)
        self.assertEqual(len(summary["hangs"]), 1)
        hang = summary["hangs"][0]
        self.assertTrue(hang["resolved"])
        self.assertGreaterEqual(hang["observed_s"], 2.0)
        self.assertLessEqual(hang["observed_s"], 5.0)
        counts = summary["incidents"][0]["trigger_counts"]
        self.assertEqual(counts.get("hang"), 1)
        self.assertEqual(counts.get("stall"), 1)
        self.assertAlmostEqual(summary["incidents"][0]["worst_ms"], 5000.0)

    def test_freeze_shorter_than_hang_s_is_only_a_measured_stall(self):
        frames = steady(10) + [("freeze", 1.5)] + steady(20)
        summary, _, _ = watch(frames, tmp=self.tmp)
        self.assertEqual(summary["hangs"], [])
        self.assertEqual(summary["incidents"][0]["trigger_counts"], {"stall": 1})

    def test_one_long_stall_is_not_also_a_drop(self):
        frames = steady(15, 7_000) + [(300_000, "flight")] + steady(15, 7_000)
        summary, _, _ = watch(frames, tmp=self.tmp)
        self.assertEqual(summary["incidents"][0]["trigger_counts"], {"stall": 1})

    def test_lost_bridge_ends_the_watch_and_keeps_results(self):
        bridge = FakeBridge(steady(60))
        original = bridge.sleep

        def sleep(seconds):
            original(seconds)
            if bridge.t > 5:
                bridge.dead = True
        bridge.sleep = sleep
        summary, _, out = watch(None, tmp=self.tmp, bridge=bridge, duration_s=60.0, lost_s=4.0)
        self.assertEqual(summary["outcome"], "bridge_lost")
        self.assertLess(summary["elapsed_s"], 15)
        self.assertTrue((out / "watch.json").is_file())

    def test_overlapping_lead_up_does_not_inherit_the_previous_worst_frame(self):
        frames = steady(12) + [(80_000, "flight")] + steady(6) + [(33_000, "flight")] + steady(10)
        summary, _, _ = watch(frames, tmp=self.tmp)
        first, second = summary["incidents"]
        self.assertEqual(second["trigger_counts"], {"stutter": 1})
        self.assertEqual(second["lead_overlaps_incident"], first["id"])
        self.assertAlmostEqual(second["worst_ms"], 33.0)
        self.assertAlmostEqual(second["lead_worst_ms"], 80.0)

    def test_menu_drift_with_zero_floor_does_trigger(self):
        frames = steady(15, 1_000, "home") + steady(10, 1_500, "home")  # proves the floor, not the ratio, held above
        summary, _, _ = watch(frames, tmp=self.tmp, triggers=("drop",), drop_min_ms=0.0)
        self.assertEqual(len(summary["incidents"]), 1)

    def test_uncapped_spikes_within_budget_are_counted_not_captured(self):
        frames = (steady(12, 4_000) + [(13_000, "flight")] + steady(3, 4_000) + [(30_000, "flight")]
                  + steady(20, 4_000))  # longer than the 30 s watch: no padding frames
        summary, _, _ = watch(frames, tmp=self.tmp, triggers=("stutter",))
        self.assertEqual(len(summary["incidents"]), 1)  # only the 30 ms spike breaks the 60 FPS budget
        self.assertAlmostEqual(summary["incidents"][0]["worst_ms"], 30.0)
        self.assertEqual(summary["segments"][0]["overall"]["relative_stutter_frames"], 2)
        sensitive, _, _ = watch(frames, tmp=tempfile.mkdtemp(dir=self.tmp), triggers=("stutter",), stutter_min_ms=0.0)
        self.assertEqual(len(sensitive["incidents"]), 2)

    def test_stutter_only_policy_still_reports_a_stall_frame(self):
        frames = steady(10) + [(300_000, "flight")] + steady(10)
        summary, _, _ = watch(frames, tmp=self.tmp, triggers=("stutter",))
        self.assertEqual(summary["incidents"][0]["trigger_counts"], {"stutter": 1})

    def test_second_drop_after_recovery_uses_a_clean_baseline(self):
        frames = (steady(15, 7_000) + steady(4, 14_000) + steady(12, 7_000) + steady(4, 14_000)
                  + steady(10, 7_000))
        summary, _, _ = watch(frames, tmp=self.tmp, triggers=("drop",), duration_s=45.0)
        self.assertEqual([i["trigger_counts"] for i in summary["incidents"]], [{"drop": 1}, {"drop": 1}])
        self.assertGreater(summary["incidents"][1]["triggers"][0]["baseline_fps"], 135)
        self.assertEqual(summary["drop_blind_s"], 6.0)

    def test_protocol_error_mid_run_keeps_every_result(self):
        frames = steady(12) + [(80_000, "flight")] + steady(30)
        bridge = FakeBridge(frames)
        original = bridge.fetch

        def fetch(cmd, args, timeout):
            reply = original(cmd, args, timeout)
            if cmd == "frames" and bridge.t > 20 and reply.get("frames"):
                reply["samples"]["end_usec"][0] += 1  # a broken interval chain mid-session
            return reply
        bridge.fetch = fetch
        summary, _, out = watch(None, tmp=self.tmp, bridge=bridge)
        self.assertEqual(summary["outcome"], "protocol_error")
        self.assertIn("not contiguous", summary["error"])
        self.assertEqual(len(summary["incidents"]), 1)
        for name in ("watch.json", "report.html", "seconds.csv"):
            self.assertTrue((out / name).is_file(), name)

    def test_a_slow_poll_with_an_advancing_engine_is_not_a_freeze(self):
        bridge = FakeBridge(steady(40))
        original = bridge.fetch
        slow = []

        def fetch(cmd, args, timeout):
            if cmd == "frames" and 10 < bridge.t < 10.6 and not slow:
                slow.append(1)
                bridge.advance(timeout)  # transport stalls while the game keeps running
                raise TimeoutError("timed out")
            return original(cmd, args, timeout)
        bridge.fetch = fetch
        summary, _, _ = watch(None, tmp=self.tmp, bridge=bridge)
        self.assertEqual(summary["hangs"], [])
        self.assertEqual(summary["slow_polls"], 1)
        self.assertEqual(summary["incidents"], [])

    def test_refused_connections_never_count_as_freezes(self):
        bridge = FakeBridge(steady(40))
        original = bridge.fetch

        def fetch(cmd, args, timeout):
            if cmd == "frames" and 10 < bridge.t < 14:
                raise ConnectionError("closed without a reply")  # e.g. MAX_CLIENTS reached
            return original(cmd, args, timeout)
        bridge.fetch = fetch
        summary, _, _ = watch(None, tmp=self.tmp, bridge=bridge)
        self.assertEqual(summary["hangs"], [])
        self.assertGreater(summary["poll_failures"], 0)

    def test_observer_marker_does_not_survive_an_epoch_change(self):
        bridge = FakeBridge(steady(60))
        watcher = fw.Watcher(fw.WatchPolicy(duration_s=5, snapshot_rows=0), bridge.fetch, Path(self.tmp) / "w",
                             now=bridge.now, sleep=bridge.sleep)
        watcher.observer_fetch_after = 5
        watcher._new_segment(bridge.fetch("frames", {"lean": True, "since": 1 << 52}, 1), "epoch_changed")
        self.assertIsNone(watcher.observer_fetch_after)

    def test_lows_beyond_the_exact_tail_use_a_labelled_histogram_estimate(self):
        stats = fw.Stats()
        for _ in range(600_000):
            stats.add(5_000, 0, 17_166, 16_667)
        for _ in range(6_000):
            stats.add(20_000, 0, 17_166, 16_667)
        report = stats.report()
        self.assertEqual(report["low_1pct_status"], "histogram_approximation")
        exact = 1000 * 6060 / (6000 * 20 + 60 * 5)  # 1% tail = 6,060 intervals: every 20 ms one plus 60 of 5 ms
        self.assertAlmostEqual(report["fps_1pct_low"], exact, delta=0.2)  # bin midpoints: within 0.05 ms per interval
        self.assertEqual(report["low_01pct_status"], "available")
        self.assertEqual(report["fps_01pct_low"], 50.0)

    def test_incident_limit_counts_later_triggers(self):
        frames = steady(12) + [(80_000, "flight")] + steady(12) + [(90_000, "flight")] + steady(10)
        summary, _, _ = watch(frames, tmp=self.tmp, max_incidents=1)
        self.assertEqual(len(summary["incidents"]), 1)
        self.assertEqual(summary["triggers_not_captured"], {"stall": 1})

    def test_snapshot_exports_v1_and_its_own_query_cannot_retrigger(self):
        frames = steady(12) + [(80_000, "flight")] + steady(20)
        bridge = FakeBridge(frames, heavy_fetch_extra_us=60_000)  # the fetch makes the next interval a stall
        summary, _, out = watch(None, tmp=self.tmp, bridge=bridge, snapshot_rows=1200)
        self.assertEqual(len(summary["incidents"]), 1)
        self.assertEqual(summary["observer_excluded_rows"], 1)
        inc = summary["incidents"][0]
        self.assertNotIn("capture_error", inc)
        report = capture.read_capture(out / inc["capture"]["json"])
        self.assertLessEqual(report["first_sequence"], inc["first_trigger_sequence"])
        self.assertTrue((out / inc["capture"]["html"]).is_file())
        snapshot_calls = [a for c, a in bridge.calls if c == "frames" and not a.get("lean")]
        self.assertEqual(len(snapshot_calls), 1)
        self.assertTrue(snapshot_calls[0]["passive"] and snapshot_calls[0]["window"] == 1200)

    def test_policy_validation_and_parsing(self):
        p = fw.policy_from_args({"triggers": "stall,drop", "sustained_frames": 45, "drop_fraction": 0.3})
        self.assertEqual(p.triggers, ("stall", "drop"))
        self.assertEqual(p.sustained_frames, 45)
        for bad in [{"triggers": "stall,boom"}, {"sustained_frames": 2.5}, {"poll_s": 0}, {"nope": 1},
                    {"drop_baseline_s": 0.5}, {"lead_frames": 5000, "recovery_frames": 5000}, {"hang_s": True}]:
            with self.assertRaises(fw.WatchError, msg=str(bad)):
                fw.policy_from_args(bad)

    def test_existing_output_is_refused(self):
        (Path(self.tmp) / "watch").mkdir()
        with self.assertRaises(fw.WatchError):
            watch(steady(5), tmp=self.tmp)

    def test_streaming_statistics_lows_and_percentile_resolution(self):
        stats = fw.Stats()
        walls = [10_000] * 990 + [40_000] * 10
        for wall in walls:
            stats.add(wall, 0, 17_166, 16_667)
        report = stats.report()
        self.assertEqual(report["fps_1pct_low"], 25.0)  # exact mean of the 10 slowest
        self.assertEqual(report["fps_01pct_low"], 25.0)
        resolution = fw._FINE + 1e-9  # a histogram percentile is the bin's upper edge
        self.assertAlmostEqual(report["p50_ms"], 10.0, delta=resolution)
        ordered = sorted(w / 1000 for w in walls)  # the bridge's nearest-rank definition: ceil(q * N), 1-based
        self.assertAlmostEqual(report["p99_ms"], ordered[math.ceil(0.99 * len(walls)) - 1], delta=resolution)
        self.assertAlmostEqual(report["p999_ms"], ordered[math.ceil(0.999 * len(walls)) - 1], delta=resolution)
        self.assertEqual(report["max_ms"], 40.0)
        self.assertEqual(report["over_budget_frames"], 10)


if __name__ == "__main__":
    unittest.main()
