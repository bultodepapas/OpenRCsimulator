"""Reconcile requested rendering with bounded per-phase frame observations."""
from __future__ import annotations

from collections import Counter
import math


_MAX_COUNTER = 2**63 - 1
_MAX_PHASE_INDEX = 10000  # the frame-stream contract
_RESOLVED_ONLY = {"output_dir", "isolated_user_dir", "isolated_project_name"}


def _integer(value, maximum=_MAX_COUNTER):
    """Accept the numeric integral channels emitted by the frame collector."""
    if type(value) is int:
        return value if 0 <= value <= maximum else None
    if type(value) is float and math.isfinite(value) and 0 <= value <= maximum and value.is_integer():
        return int(value)
    return None


class RenderAccumulator:
    """Reduce frame observations without retaining the frame stream.

    Phase attribution is at the interval end. The first interval of every
    contiguous phase segment may begin in another phase, so it proves window
    drawability at its endpoint but cannot prove that phase made draw progress.
    Every segment, including a later re-entry, needs its own positive in-phase
    interval. At most 10,001 phase receipts are retained.
    """

    def __init__(self):
        self._phases = {}
        self._active = None
        self._previous_end = None
        self._previous_drawn = None
        self._segment_positive = False
        self._finished = False

    def _close_segment(self):
        if self._active is not None and not self._segment_positive:
            self._phases[self._active]["segments_without_draw"] += 1

    def _incomplete(self, key, reason):
        self._phases[key]["invalid"].add(reason)

    def add(self, phase_index, end_usec, wall_usec, render_frames_drawn=None,
            render_interval_draws=None, render_window_drawable=None, render_window_transition=None):
        if self._finished:
            raise ValueError("render accumulator is already finished")
        phase = _integer(phase_index, _MAX_PHASE_INDEX)
        end, wall = _integer(end_usec), _integer(wall_usec)
        if phase is None or end is None or wall is None or wall == 0 or wall > end:
            raise ValueError("invalid render frame phase or clock")
        key = str(phase)
        if key not in self._phases:
            self._phases[key] = {"frames": 0, "segments": 0, "segments_without_draw": 0,
                                 "positive_in_phase_intervals": 0, "undrawable_intervals": 0,
                                 "window_mode_transition_intervals": 0,
                                 "missing": set(), "invalid": set()}
        state = self._phases[key]
        previous_phase = self._active
        transition = key != previous_phase
        if transition:
            self._close_segment()
            self._active = key
            self._segment_positive = False
            state["segments"] += 1
        state["frames"] += 1
        if self._previous_end is not None and end - wall != self._previous_end:
            self._incomplete(key, "noncontiguous_frame_clock")
            if previous_phase is not None:
                self._incomplete(previous_phase, "noncontiguous_frame_clock")

        fields = {"render_frames_drawn": render_frames_drawn,
                  "render_interval_draws": render_interval_draws,
                  "render_window_drawable": render_window_drawable}
        normalized = {}
        for name, value in fields.items():
            if value is None:
                state["missing"].add(name)
                normalized[name] = None
                continue
            normalized[name] = _integer(value, 1 if name == "render_window_drawable" else _MAX_COUNTER)
            if normalized[name] is None:
                self._incomplete(key, "invalid_" + name)
        drawn = normalized["render_frames_drawn"]
        delta = normalized["render_interval_draws"]
        drawable = normalized["render_window_drawable"]
        # The driver labels only undrawable intervals within 2 s after an observed
        # window-mode change (the macOS fullscreen Space animation). Absent in older
        # streams, where every undrawable interval keeps invalidating the phase.
        window_transition = 0 if render_window_transition is None else _integer(render_window_transition, 1)
        if window_transition is None:
            self._incomplete(key, "invalid_render_window_transition")
        elif window_transition == 1 and drawable != 0:
            self._incomplete(key, "window_transition_without_undrawable_window")
        # A labeled interval must still show draw progress; a zero-draw stall stays a gap.
        if drawable == 0 and window_transition == 1 and isinstance(delta, int) and delta > 0:
            state["window_mode_transition_intervals"] += 1
        elif drawable == 0:
            state["undrawable_intervals"] += 1
            self._incomplete(key, "window_undrawable")
        if drawn is not None and delta is not None:
            if delta > drawn:
                self._incomplete(key, "invalid_draw_counter_delta")
            elif self._previous_end is not None and self._previous_drawn is None:
                state["missing"].add("previous_render_frames_drawn")
            elif self._previous_drawn is not None and drawn - self._previous_drawn != delta:
                self._incomplete(key, "draw_counter_delta_mismatch")
                if previous_phase is not None:
                    self._incomplete(previous_phase, "draw_counter_delta_mismatch")
            elif not transition and delta > 0:
                state["positive_in_phase_intervals"] += 1
                self._segment_positive = True
        self._previous_end = end
        self._previous_drawn = drawn

    def finish(self):
        """Return detached per-phase receipts; repeated calls are stable."""
        if not self._finished:
            self._close_segment()
            self._finished = True
        result = {}
        for key, state in self._phases.items():
            invalid, missing = sorted(state["invalid"]), sorted(state["missing"])
            no_draw = state["segments_without_draw"] > 0
            reasons = invalid + (["missing_" + name for name in missing])
            if no_draw and not missing:
                reasons.append("segment_without_in_phase_draw")
            status = "incomplete" if invalid or (no_draw and not missing) else "unavailable" if missing else "complete"
            result[key] = {"status": status, "reasons": reasons,
                           **{name: state[name] for name in ("frames", "segments", "segments_without_draw",
                                                             "positive_in_phase_intervals", "undrawable_intervals",
                                                             "window_mode_transition_intervals")},
                           "scope": "drawable interval endpoints and in-phase draw progress; physical presentation unverified"}
        return result


def _recorded_platform(execution):
    host = execution.get("host")
    name = host.get("platform") if isinstance(host, dict) else None
    if not isinstance(name, str):
        return None
    lowered = name.lower()
    if lowered.startswith(("macos", "darwin")):
        return "darwin"
    if lowered.startswith("windows"):
        return "win32"
    if lowered.startswith("linux"):
        return "linux"
    return None


def _expected_renderer(manifest, execution):
    """Mirror runner.rendering_options without consulting the report host OS."""
    method, driver = manifest.get("rendering_method"), manifest.get("rendering_driver")
    if method not in (None, "auto", "forward_plus", "mobile", "gl_compatibility"):
        return None, "invalid requested rendering method"
    if driver not in (None, "auto", "vulkan", "metal", "d3d12", "opengl3"):
        return None, "invalid requested rendering driver"
    host = _recorded_platform(execution)
    if (method == "auto" or driver == "auto") and host is None:
        return None, "cannot resolve automatic renderer without recorded host platform"
    if method == "auto":
        method = "mobile" if host == "darwin" else "forward_plus"
    if driver == "auto":
        driver = "opengl3" if method == "gl_compatibility" else "metal" if host == "darwin" else "vulkan"
    if (method == "gl_compatibility" and driver not in (None, "opengl3")
            or method in ("mobile", "forward_plus") and driver == "opengl3"
            or driver == "metal" and host is not None and host != "darwin"
            or driver == "d3d12" and host is not None and host != "win32"):
        return None, "requested renderer is incompatible with the recorded host or method"
    return {key: value for key, value in (("rendering_method", method), ("rendering_driver", driver)) if value}, None


def validate_rendering(requested_manifest, resolved_manifest, runtime, phases, raw_per_phase, execution):
    """Fail closed on inconsistent requested mode, launcher, and frame evidence."""
    issues = []
    result = {"requested_headless": None, "status": "incomplete", "requested_phases": 0,
              "issues": issues,
              "scope": "per-phase engine draw progress and drawable endpoints; physical presentation unverified"}
    if not isinstance(requested_manifest, dict) or not isinstance(resolved_manifest, dict):
        issues.append("requested or resolved manifest is missing or invalid")
        return result
    requested = requested_manifest.get("headless")
    if type(requested) is not bool:
        issues.append("original requested rendering mode is missing or invalid")
        return result
    result["requested_headless"] = requested
    if type(resolved_manifest.get("headless")) is not bool:
        issues.append("resolved rendering mode is missing or invalid")
    original_workload = {key: value for key, value in requested_manifest.items() if key not in _RESOLVED_ONLY}
    resolved_workload = {key: value for key, value in resolved_manifest.items() if key not in _RESOLVED_ONLY}
    if original_workload != resolved_workload:
        issues.append("original requested and resolved workloads differ")
    if not isinstance(phases, list):
        issues.append("phase records are missing or invalid")
        return result
    expected_names = requested_manifest.get("phases")
    cycles = _integer(requested_manifest.get("cycles"), 50)
    if (not isinstance(expected_names, list) or not expected_names
            or any(not isinstance(name, str) or not name for name in expected_names)
            or cycles is None or cycles < 1):
        issues.append("original requested phases or cycles are missing or invalid")
        return result
    selected = []
    indices = set()
    for phase in phases:
        if not isinstance(phase, dict) or type(phase.get("requested")) is not bool:
            issues.append("phase requested flag is missing or invalid")
            continue
        index = _integer(phase.get("index"), _MAX_PHASE_INDEX)
        if index is None or index in indices:
            issues.append("phase index is missing, invalid or repeated")
        else:
            indices.add(index)
        cycle = phase.get("cycle")
        if type(cycle) is not int or not 0 <= cycle < cycles:
            issues.append("phase cycle is missing or outside the original workload")
        if phase.get("id") != f"{cycle}-{index}-{phase.get('name')}":
            issues.append("phase id does not match its cycle, index and name")
        if phase.get("requested") is not (phase.get("name") in expected_names):
            issues.append(f"phase requested flag differs from the original workload: {phase.get('id', 'unknown')}")
        if phase.get("requested") is True:
            selected.append(phase)
    result["requested_phases"] = len(selected)
    expected_counts = Counter(expected_names)
    actual_counts = Counter(phase.get("name") for phase in selected if isinstance(phase.get("name"), str))
    for name, count in expected_counts.items():
        if name == "shutdown":  # shutdown is verified by the external supervisor
            continue
        required = 1 if name == "startup" else count * cycles
        if actual_counts[name] < required:
            issues.append(f"requested phase records are missing: {name}")
    if requested:
        if not issues:
            result["status"] = "not_requested"
        return result
    metrics = runtime.get("metrics") if isinstance(runtime, dict) else None
    if not isinstance(metrics, dict) or metrics.get("rendered") is not True:
        issues.append("requested rendered workload lacks a positive runtime render receipt")
    if not selected:
        issues.append("requested rendered workload has no requested phase render evidence")
    if not isinstance(raw_per_phase, dict):
        raw_per_phase = {}
    for phase in selected:
        phase_id = phase.get("id", "unknown")
        if phase.get("status") != "complete" or phase.get("rendered") is not True:
            issues.append(f"requested phase lacks complete runtime draw progress: {phase_id}")
        index = _integer(phase.get("index"), _MAX_PHASE_INDEX)
        raw = raw_per_phase.get(str(index)) if index is not None else None
        if not isinstance(raw, dict) or raw.get("status") != "complete":
            issues.append(f"requested phase lacks complete raw draw evidence: {phase_id}")
    if not isinstance(execution, dict):
        execution = {}
    expected, error = _expected_renderer(requested_manifest, execution)
    if error:
        issues.append(error)
    elif not isinstance(execution.get("rendering_requested"), dict) or execution["rendering_requested"] != expected:
        issues.append("launcher renderer receipt is missing or differs from the requested workload")
    diagnostic = runtime.get("identity", {}).get("diagnostics", {}) if isinstance(runtime, dict) and isinstance(runtime.get("identity"), dict) else {}
    if not isinstance(diagnostic, dict):
        diagnostic = {}
    if expected is not None:
        for key, value in expected.items():
            if diagnostic.get(key) != value:
                issues.append(f"actual {key} differs from requested workload")
    if not issues:
        result["status"] = "complete"
    return result
