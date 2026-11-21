"""Bounded, offline simulation pace from the GOD TEST frame stream.

Feed one observation per frame to :class:`PaceWindowAccumulator`, regardless of
chunking, then call ``finish()``.  Keys are the stream's phase indexes, rendered
as strings.  A consumer must choose which phase indexes are active flight; this
module deliberately does not classify phases or declare a performance target.

The stream timestamps the callback before reading the simulation state.  These
are callback observations, not display-presentation timestamps or interpolated
simulation progress.  The first observation in a phase or after an excluded
hold/unknown sample is an origin, not an interval.  Paused/crashed observations
and both adjacent intervals are excluded.  An active phase containing a hold is
therefore ineligible even when some windows remain useful as diagnostics.

Each contiguous observed active segment has a one-second grid beginning at its
first observation.  An interval is assigned only when both endpoints fit in
one grid cell; an interval crossing a cell boundary is excluded from both cells,
never split.  A cell is full only after its end has been observed or crossed;
a segment's final shorter cell is flagged partial.  Full cells need at least
0.9 seconds of included wall time AND two included intervals to be supported.
Only supported full cells participate in worst/fastest pace.  This is a declared
screening support rule, not a confidence interval or hardware qualification.
Phase coverage is sufficient for this screen only when all full cells are
supported, supported full cells cover at least 90% of observed active wall
time, and no cell-boundary exclusion exceeds 100 ms.  An excluded first phase
interval is reported separately: the stream cannot establish its phase split,
so it also cannot exceed 100 ms for the phase screen to be available.

Simulation progress is derived from verified integer tick differences at the
fixed 240 Hz rate; the reported simulation-time channel must independently agree
with the producer's tick-times-dt clock within bounded serialization tolerance.
The maximum accumulated lag is max(0, elapsed wall - elapsed simulation) at the
actual observed endpoints of each active segment, anchored at zero at that
segment's first observation.  It includes intervals crossing grid boundaries,
but does not span phase, hold, missing-sample, or clock-reset boundaries.  It
cannot reveal an unobserved peak between callbacks.  The summary retains only
extrema, the latest partial cell, and counts: memory is independent of the number
of frames and windows.  At most 10,001 monotonically ordered phases can be
retained, matching the frame reducer's phase-index bound.
"""
from __future__ import annotations

import math

WINDOW_USEC = 1_000_000
MIN_WINDOW_USEC = 900_000
MIN_INTERVALS = 2
MIN_PHASE_COVERAGE = 0.90
MAX_BOUNDARY_EXCLUSION_USEC = 100_000
MAX_PHASE_INDEX = 10_000
MAX_EXACT_TICK = 2**53 - 1  # stream metrics are stored as float64
MAX_CLOCK_USEC = 2**63 - 1  # Godot's monotonic clock is a signed integer
LAG_TIE_EPSILON_S = 1e-9  # below the microsecond wall-clock resolution
PHYSICS_HZ = 240
# The serialized producer clock is tick * (1 / 240). Four floating-point ULPs
# cover multiplication and float64 JSON round trips; 10 ns covers small values.
# Refuse epochs where that allowance exceeds 100 us (1% of the 10 ms width of
# the one-second ±1% screen), rather than permit tolerance to grow without bound.
MIN_SIM_CLOCK_TOLERANCE_S = 1e-8
MAX_SIM_CLOCK_TOLERANCE_S = 1e-4
REQUIRED_METRICS = ("sim_tick", "sim_time_s", "paused", "crashed")


def _finite_number(value) -> bool:
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def _integral(value) -> bool:
    return _finite_number(value) and value == int(value)


def _empty_window(index: int, origin: int) -> dict:
    start = origin + index * WINDOW_USEC
    return {"window_start_usec": start, "window_end_usec": start + WINDOW_USEC,
            "support_start_usec": None, "support_end_usec": None,
            "wall_usec": 0, "sim_ticks": 0, "interval_count": 0}


class _Phase:
    def __init__(self, index: int):
        self.index = index
        self.issues: set[str] = set()
        self.samples = 0
        self.segments = 0
        self.boundary_wall_usec = 0
        self.hold_samples = 0
        self.hold_intervals = 0
        self.hold_wall_usec = 0
        self.unknown_intervals = 0
        self.unknown_wall_usec = 0
        self.active_intervals = 0
        self.active_wall_usec = 0
        self.active_sim_ticks = 0
        self.window_boundary_intervals = 0
        self.window_boundary_wall_usec = 0
        self.max_window_boundary_usec = 0
        self.full_windows = 0
        self.supported_windows = 0
        self.supported_window_wall_usec = 0
        self.insufficient_windows = 0
        self.partial_windows = 0
        self.last_partial = None
        self.worst = None
        self.fastest = None
        self.maximum_lag_s = None
        self.maximum_lag_at_usec = None
        self.previous = None
        self.origin_usec = None
        self.origin_tick = None
        self.window_index = None
        self.window = None
        self.segment_last_usec = None

    def _start_segment(self, sample: dict) -> None:
        self.segments += 1
        self.origin_usec = sample["end_usec"]
        self.origin_tick = int(sample["sim_tick"])
        self.segment_last_usec = sample["end_usec"]
        self.window_index = 0
        self.window = _empty_window(0, self.origin_usec)

    def _window_result(self, partial: bool, segment_end_usec=None) -> dict:
        value = self.window
        wall = value["wall_usec"]
        sim = value["sim_ticks"] / PHYSICS_HZ
        supported = (not partial and wall >= MIN_WINDOW_USEC
                     and value["interval_count"] >= MIN_INTERVALS)
        return {"window_start_usec": value["window_start_usec"],
                "window_end_usec": value["window_end_usec"],
                "support_start_usec": value["support_start_usec"],
                "support_end_usec": value["support_end_usec"],
                "segment_end_usec": segment_end_usec,
                "wall_seconds": wall / 1_000_000,
                "sim_seconds": sim if wall else None,
                "interval_count": value["interval_count"],
                "simulation_wall_ratio": sim * 1_000_000 / wall if wall else None,
                "partial": partial, "supported": supported}

    def _close_full(self) -> None:
        result = self._window_result(False)
        self.full_windows += 1
        if not result["supported"]:
            self.insufficient_windows += 1
            return
        self.supported_windows += 1
        self.supported_window_wall_usec += self.window["wall_usec"]
        if self.worst is None or result["simulation_wall_ratio"] < self.worst["simulation_wall_ratio"]:
            self.worst = result
        if self.fastest is None or result["simulation_wall_ratio"] > self.fastest["simulation_wall_ratio"]:
            self.fastest = result

    def _advance_to(self, index: int) -> None:
        """Close preceding grid cells, counting large empty gaps in O(1)."""
        if index <= self.window_index:
            return
        self._close_full()
        skipped = index - self.window_index - 1
        self.full_windows += skipped
        self.insufficient_windows += skipped
        self.window_index = index
        self.window = _empty_window(index, self.origin_usec)

    def _end_segment(self) -> None:
        if self.origin_usec is None:
            return
        # An observation exactly at the next grid boundary does not create an
        # empty tail. Otherwise retain one partial description, not one per cell.
        if self.segment_last_usec > self.window["window_start_usec"]:
            self.partial_windows += 1
            self.last_partial = self._window_result(True, self.segment_last_usec)
        self.origin_usec = self.origin_tick = self.segment_last_usec = None
        self.window_index = self.window = None

    def _add_active_interval(self, start: dict, end: dict) -> None:
        before, after = start["end_usec"], end["end_usec"]
        wall = after - before
        tick_delta = int(end["sim_tick"]) - int(start["sim_tick"])
        self.active_intervals += 1
        self.active_wall_usec += wall
        self.active_sim_ticks += tick_delta
        # This includes crossing intervals, but evaluates only observed endpoints.
        lag = max(0.0, (after - self.origin_usec) / 1_000_000
                  - (int(end["sim_tick"]) - self.origin_tick) / PHYSICS_HZ)
        if self.maximum_lag_s is None or lag > self.maximum_lag_s + LAG_TIE_EPSILON_S:
            self.maximum_lag_s = lag
            self.maximum_lag_at_usec = after
        first_cell = (before - self.origin_usec) // WINDOW_USEC
        # Endpoints exactly on a boundary may close the preceding cell.
        last_cell = (after - self.origin_usec - 1) // WINDOW_USEC
        self._advance_to(first_cell)
        if first_cell == last_cell:
            value = self.window
            if value["support_start_usec"] is None:
                value["support_start_usec"] = before
            value["support_end_usec"] = after
            value["wall_usec"] += wall
            value["sim_ticks"] += tick_delta
            value["interval_count"] += 1
        else:
            self.window_boundary_intervals += 1
            self.window_boundary_wall_usec += wall
            self.max_window_boundary_usec = max(self.max_window_boundary_usec, wall)
        self.segment_last_usec = after
        self._advance_to((after - self.origin_usec) // WINDOW_USEC)

    def add(self, wall_usec: int, end_usec: int, values: dict) -> None:
        self.samples += 1
        issues = set()
        for name in REQUIRED_METRICS:
            value = values[name]
            if value is None:
                issues.add("missing_" + name)
            elif not _finite_number(value):
                issues.add("invalid_" + name)
        tick, sim = values["sim_tick"], values["sim_time_s"]
        if tick is not None and _finite_number(tick):
            if not _integral(tick) or tick < -1 or tick > MAX_EXACT_TICK:
                issues.add("invalid_sim_tick")
            elif tick == -1:
                issues.add("no_simulation")
        if sim is not None and _finite_number(sim) and sim < 0:
            issues.add("invalid_sim_time_s")
        for name in ("paused", "crashed"):
            value = values[name]
            if value is not None and _finite_number(value) and value not in (0, 1):
                issues.add("invalid_" + name)
        # The GOD TEST driver rejects physics rates other than 240 Hz, and
        # Simulation.time() returns tick * dt(). Never let a relative tolerance
        # grow to a meaningful fraction of a one-second pace target.
        if not issues:
            expected = int(tick) * (1.0 / PHYSICS_HZ)
            tolerance = max(MIN_SIM_CLOCK_TOLERANCE_S, 4 * max(math.ulp(expected), math.ulp(float(sim))))
            if tolerance > MAX_SIM_CLOCK_TOLERANCE_S:
                issues.add("simulation_clock_insufficient_precision")
            elif abs(float(sim) - expected) > tolerance:
                issues.add("simulation_clock_inconsistent")
        self.issues.update(issues)
        # A known positive hold remains an observation even if another metric
        # is missing; it never repairs the unknown segment's eligibility.
        held = any(_finite_number(values[name]) and values[name] == 1
                   for name in ("paused", "crashed"))
        current = {"end_usec": end_usec, **values, "valid": not issues, "held": held}
        if current["held"]:
            self.hold_samples += 1
        previous = self.previous
        if previous is None:
            # The interval ending at the first phase sample lacks a same-phase
            # starting observation, including the bootstrap sample.
            self.boundary_wall_usec += wall_usec
        else:
            if previous["valid"] and current["valid"]:
                tick_delta = current["sim_tick"] - previous["sim_tick"]
                sim_delta = current["sim_time_s"] - previous["sim_time_s"]
                if tick_delta < 0 or sim_delta < 0:
                    self.issues.add("simulation_clock_regressed")
                    current["reset"] = True
                elif (tick_delta == 0) != (sim_delta == 0):
                    self.issues.add("simulation_clock_inconsistent")
                    current["reset"] = True
            if not previous["valid"] or not current["valid"] or current.get("reset"):
                self.unknown_intervals += 1
                self.unknown_wall_usec += wall_usec
                self._end_segment()
            elif previous["held"] or current["held"]:
                self.hold_intervals += 1
                self.hold_wall_usec += wall_usec
                self._end_segment()
            else:
                self._add_active_interval(previous, current)
        if current["valid"] and not current["held"] and self.origin_usec is None:
            self._start_segment(current)
        self.previous = current

    def finish(self) -> dict:
        self._end_segment()
        coverage = (self.supported_window_wall_usec / self.active_wall_usec
                    if self.active_wall_usec else None)
        coverage_reasons = []
        if not self.supported_windows:
            coverage_reasons.append("no_supported_full_windows")
        if self.insufficient_windows:
            coverage_reasons.append("unsupported_full_windows")
        if self.max_window_boundary_usec > MAX_BOUNDARY_EXCLUSION_USEC:
            coverage_reasons.append("long_window_boundary_exclusion")
        if self.boundary_wall_usec > MAX_BOUNDARY_EXCLUSION_USEC:
            coverage_reasons.append("long_phase_boundary_exclusion")
        if coverage is None or coverage < MIN_PHASE_COVERAGE:
            coverage_reasons.append("less_than_90_percent_active_wall_supported")
        if any(issue.startswith("missing_") for issue in self.issues):
            status = "unavailable_missing_channels"
        elif any(issue.startswith("invalid_") for issue in self.issues):
            status = "unavailable_invalid_sample"
        elif any(issue.startswith("simulation_clock_") for issue in self.issues):
            status = "unavailable_simulation_clock_discontinuity"
        elif "no_simulation" in self.issues:
            status = "unavailable_no_simulation"
        elif self.hold_samples:
            status = "unavailable_hold_observed"
        elif not self.supported_windows:
            status = "unavailable_insufficient_support"
        elif coverage_reasons:
            status = "unavailable_incomplete_coverage"
        else:
            status = "available"
        holds_complete = not any(issue in self.issues for issue in
                                 ("missing_paused", "invalid_paused", "missing_crashed", "invalid_crashed"))
        return {"status": status, "issues": sorted(self.issues),
                "samples": self.samples, "active_segments": self.segments,
                "phase_boundary_or_first_interval_excluded_wall_seconds": self.boundary_wall_usec / 1_000_000,
                "hold_channels_complete": holds_complete,
                "observed_hold_samples": self.hold_samples,
                "hold_excluded_intervals": self.hold_intervals if holds_complete else None,
                "hold_excluded_wall_seconds": self.hold_wall_usec / 1_000_000 if holds_complete else None,
                "unknown_excluded_intervals": self.unknown_intervals,
                "unknown_excluded_wall_seconds": self.unknown_wall_usec / 1_000_000,
                "active_intervals": self.active_intervals,
                "active_wall_seconds": self.active_wall_usec / 1_000_000 if self.active_intervals else None,
                "active_sim_seconds": self.active_sim_ticks / PHYSICS_HZ if self.active_intervals else None,
                "window_boundary_excluded_intervals": self.window_boundary_intervals,
                "window_boundary_excluded_wall_seconds": self.window_boundary_wall_usec / 1_000_000 if self.active_intervals else None,
                "maximum_window_boundary_excluded_seconds": self.max_window_boundary_usec / 1_000_000 if self.active_intervals else None,
                "full_windows": self.full_windows, "supported_windows": self.supported_windows,
                "insufficient_windows": self.insufficient_windows,
                "supported_window_wall_seconds": self.supported_window_wall_usec / 1_000_000 if self.supported_windows else None,
                "supported_window_fraction_of_active_wall": coverage,
                "coverage_reasons": coverage_reasons,
                "partial_windows": self.partial_windows, "last_partial_window": self.last_partial,
                "worst_window": self.worst, "fastest_window": self.fastest,
                "maximum_lag_seconds": self.maximum_lag_s,
                "maximum_lag_at_usec": self.maximum_lag_at_usec,
                "method": {"window_seconds": WINDOW_USEC / 1_000_000,
                           "minimum_wall_seconds": MIN_WINDOW_USEC / 1_000_000,
                           "minimum_intervals": MIN_INTERVALS,
                           "minimum_phase_supported_wall_fraction": MIN_PHASE_COVERAGE,
                           "maximum_boundary_exclusion_seconds": MAX_BOUNDARY_EXCLUSION_USEC / 1_000_000,
                           "maximum_phase_boundary_exclusion_seconds": MAX_BOUNDARY_EXCLUSION_USEC / 1_000_000,
                           "simulation_clock": "verified integer tick deltas divided by 240 Hz; bounded tick/time consistency tolerance",
                           "assignment": "whole interval only when both observations are within one phase/segment grid cell",
                           "lag": "maximum observed wall-minus-simulation elapsed since each active-segment origin; no interpolation"}}


class PaceWindowAccumulator:
    """Stream frame observations and return bounded per-phase diagnostic summaries.

    ``add(phase_index, wall_usec, end_usec, sim_tick, sim_time_s, paused,
    crashed)`` accepts the actual v1 frame-stream channels.  A missing metric is
    passed as ``None``.  Phase indexes must be monotonic (gaps are permitted),
    and frame intervals must be positive, ordered and contiguous; violations
    raise ValueError.  Bad, missing or regressing simulation channels make that
    phase unavailable and break the active segment.  Pauses/crashes are recorded
    and excluded conservatively.  ``finish()`` finalizes the last phase, returning
    the same summary on repeated calls; adding after it raises ValueError.
    """

    def __init__(self):
        self._previous_end = None
        self._phase = None
        self._results = {}
        self._finished = False

    def add(self, phase_index, wall_usec, end_usec, sim_tick=None,
            sim_time_s=None, paused=None, crashed=None) -> None:
        if self._finished:
            raise ValueError("pace accumulator is finished")
        if not _integral(phase_index) or not 0 <= phase_index <= MAX_PHASE_INDEX:
            raise ValueError("invalid pace phase index")
        if (type(wall_usec) is not int or type(end_usec) is not int
                or not 0 < wall_usec <= end_usec <= MAX_CLOCK_USEC):
            raise ValueError("invalid pace frame clock")
        if self._previous_end is not None and end_usec - wall_usec != self._previous_end:
            raise ValueError("pace frame intervals are not contiguous")
        index = int(phase_index)
        if self._phase is not None and index < self._phase.index:
            raise ValueError("pace phase index regressed")
        if self._phase is None or index != self._phase.index:
            if self._phase is not None:
                self._results[str(self._phase.index)] = self._phase.finish()
            self._phase = _Phase(index)
        self._phase.add(wall_usec, end_usec, {"sim_tick": sim_tick, "sim_time_s": sim_time_s,
                                              "paused": paused, "crashed": crashed})
        self._previous_end = end_usec

    def finish(self) -> dict:
        if not self._finished:
            if self._phase is not None:
                self._results[str(self._phase.index)] = self._phase.finish()
            self._finished = True
        return self._results
