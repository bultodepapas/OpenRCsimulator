"""Executable DRS design specimen; no engine, settings, collector or physics I/O.

This is a research reference, not production DRS. The adapter must prove provider
eligibility, coherent completed GPU samples and actual execution independently.
See README.md for the exact source boundary and unqualified parameters.
"""

from dataclasses import dataclass
import math
import struct


Size = tuple[int, int]


def _finite(value: object) -> bool:
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def _size(value: Size) -> bool:
    return (isinstance(value, tuple) and len(value) == 2
            and all(type(axis) is int and 0 < axis <= 16384 for axis in value))


def _f32(value: float) -> float:
    return struct.unpack("!f", struct.pack("!f", value))[0]


@dataclass(frozen=True)
class Level:
    scale: float
    size: Size


@dataclass(frozen=True)
class Ladder:
    output: Size
    minimum: Size
    maximum: Size
    alignment: Size
    levels: tuple[Level, ...]


def nominal_extent(output: Size, scale: float) -> Size:
    """Model cafc17a19's accepted <=1 temporal/spatial scalar path only.

    C++ uses a float scale and truncates positive float products to int. This
    neither proves that the selected mode survived fallback nor reports SDK
    dispatch/allocation size. Compatibility, forks and provider limits need their
    own qualification. Outputs are deliberately bounded to this specimen's scope.
    """
    if not _size(output) or not _finite(scale) or not 0.1 <= scale <= 1.0:
        raise ValueError("invalid output or scale for the nominal source model")
    actual_scalar = _f32(scale)
    return tuple(max(1, int(_f32(_f32(axis) * actual_scalar))) for axis in output)


def legal_ladder(output: Size, scales: tuple[float, ...], minimum: Size,
                 maximum: Size, alignment: Size = (1, 1)) -> Ladder:
    """Intersect a bounded scalar ladder with caller-proven per-axis limits.

    minimum includes the pilot floor and provider bounds; maximum includes the
    user's fixed-choice pixel ceiling and provider bounds. Never raise that
    ceiling, lower that floor, or round width and height independently. Alignment
    is supplied by the verified provider; (1,1) is not a vendor-wide promise.
    """
    if not all(_size(value) for value in (output, minimum, maximum, alignment)):
        raise ValueError("invalid integer extent or alignment")
    if any(lo > hi or hi > out for lo, hi, out in zip(minimum, maximum, output)):
        raise ValueError("empty or invalid input range")
    if not isinstance(scales, tuple) or not 1 <= len(scales) <= 32:
        raise ValueError("provide 1..32 candidate scalar values")
    candidates = [(scale, nominal_extent(output, scale)) for scale in scales]
    levels: list[Level] = []
    seen: set[Size] = set()
    for scale, size in sorted(candidates):
        if all(lo <= axis <= hi and axis % align == 0
               for axis, lo, hi, align in zip(size, minimum, maximum, alignment)):
            if size not in seen:
                levels.append(Level(_f32(scale), size))
                seen.add(size)
            else:
                # Preserve the highest scalar for this extent, including an
                # explicitly supplied fixed ceiling; emit no duplicate extent.
                levels[-1] = Level(_f32(scale), size)
    if not levels:
        raise ValueError("no scalar realizes a legal input extent")
    return Ladder(output, minimum, maximum, alignment, tuple(levels))


@dataclass(frozen=True)
class Tuning:
    target_fps: float = 60.0
    minimum_samples: int = 120
    window_ms: float = 2000.0
    maximum_samples: int = 1_000_000
    down_ratio: float = 0.90
    up_ratio: float = 0.75
    high_windows: int = 2
    down_dwell_ms: float = 5000.0
    up_dwell_ms: float = 10000.0
    recovery_ms: float = 10000.0
    max_age_ms: float = 100.0
    max_gap_ms: float = 250.0
    apply_timeout_ms: float = 1000.0

    def __post_init__(self) -> None:
        numbers = (self.target_fps, self.window_ms, self.down_dwell_ms,
                   self.up_dwell_ms, self.recovery_ms, self.max_age_ms,
                   self.max_gap_ms, self.apply_timeout_ms)
        if not all(_finite(value) and value > 0 for value in numbers):
            raise ValueError("all timing parameters and target must be finite and positive")
        if not 1 <= self.target_fps <= 1000:
            raise ValueError("the reference target must be explicit and within 1..1000 FPS")
        if (type(self.maximum_samples) is not int or type(self.minimum_samples) is not int
                or not 2 <= self.minimum_samples <= self.maximum_samples <= 1_000_000
                or type(self.high_windows) is not int or not 1 <= self.high_windows <= 8
                or not all(_finite(x) for x in (self.up_ratio, self.down_ratio))
                or not 0 < self.up_ratio < self.down_ratio < 1):
            raise ValueError("invalid bounded window or thresholds")


@dataclass(frozen=True)
class Sample:
    completed_id: int | None
    generation: int
    size: Size
    recorded_ms: float | None
    gpu_ms: float | None


@dataclass(frozen=True)
class Change:
    request_id: int
    source_generation: int
    target: Level
    reason: str


@dataclass(frozen=True)
class Decision:
    state: str
    reason: str
    change: Change | None = None
    restore_fixed: bool = False


class Controller:
    """One bounded decision owner with proposal -> observed-apply acknowledgement.

    completed_id, recorded_ms, generation and size must refer to the SAME actual
    GPU work. Poll counters, frame_post_draw or a separate viewport getter cannot
    synthesize that contract. Successful acknowledge() is not capability proof.
    """

    def __init__(self, ladder: Ladder, generation: int,
                 observed_fixed: Level, started_ms: float = 0.0,
                 tuning: Tuning = Tuning()) -> None:
        if not isinstance(ladder, Ladder):
            raise ValueError("a validated nominal ladder is required")
        levels = ladder.levels
        if (not isinstance(levels, tuple) or not 1 <= len(levels) <= 32
                or type(generation) is not int or generation < 0
                or not _finite(started_ms) or started_ms < 0):
            raise ValueError("invalid initial contract")
        for index, level in enumerate(levels):
            if not isinstance(level, Level) or not _size(level.size):
                raise ValueError("invalid level")
            if not _finite(level.scale) or not 0.1 <= level.scale <= 1:
                raise ValueError("invalid level scale")
            if index:
                prior = levels[index - 1]
                if (level.scale <= prior.scale or level.size == prior.size
                        or any(a < b for a, b in zip(level.size, prior.size))):
                    raise ValueError("ladder must strictly grow without duplicate extents")
        if not isinstance(observed_fixed, Level) or observed_fixed != levels[-1]:
            raise ValueError("the top rung must match the observed fixed scalar AND extent")
        rebuilt = legal_ladder(ladder.output, tuple(level.scale for level in levels),
                               ladder.minimum, ladder.maximum, ladder.alignment)
        if rebuilt != ladder:
            raise ValueError("forged scalar/extent ladder")
        self.levels, self.generation, self.tuning = levels, generation, tuning
        self.index = len(levels) - 1
        self.last_change_ms = self.last_now_ms = float(started_ms)
        self.pending: Change | None = None
        self.pending_since_ms = 0.0
        self.next_request_id = 1
        self.fault = ""
        self.last_id: int | None = None
        self.last_recorded_ms: float | None = None
        self.window_count = self.above_high = self.below_low = 0
        self.window_begin_ms: float | None = None
        self.high_count = 0
        self.low_since_ms: float | None = None

    @property
    def confirmed(self) -> Level:
        """Last acknowledged level, NOT a live effective-state query after fault."""
        return self.levels[self.index]

    def _reset_evidence(self) -> None:
        self._clear_window()
        self.high_count = 0
        self.low_since_ms = None

    def _clear_window(self) -> None:
        self.window_count = self.above_high = self.below_low = 0
        self.window_begin_ms = None

    def _clock(self, now_ms: float) -> bool:
        if not _finite(now_ms) or now_ms < self.last_now_ms:
            self.fault = "invalid_or_reversed_clock"
            self._reset_evidence()
            return False
        self.last_now_ms = float(now_ms)
        return True

    def _suspend(self, reason: str, restore: bool = True) -> Decision:
        self._reset_evidence()
        if restore:
            # Fixed restoration changes actual state. Retire this epoch so that
            # neither old samples nor a late callback can revive it afterward.
            self.fault = self.fault or reason
        return Decision("suspended", reason, restore_fixed=restore)

    def step(self, sample: Sample | None, now_ms: float, *,
             gpu_limited: bool, blocked_reason: str = "") -> Decision:
        """gpu_limited is a previously proven pixel-sensitive admission, not FPS.

        blocked_reason covers loading, pause, minimize, preview, history/reset,
        lost viewport and unsupported provider. The external reconstruction owner
        handles fixed restoration and cancels/drains outstanding work safely.
        """
        if not self._clock(now_ms) or self.fault:
            return self._suspend(self.fault)
        if blocked_reason:
            if self.pending is not None:
                self.fault = "transition_during_pending_apply"
            return self._suspend(blocked_reason)
        if self.pending is not None:
            if now_ms - self.pending_since_ms >= self.tuning.apply_timeout_ms:
                self.fault = "apply_timeout"
                return self._suspend(self.fault)
            return Decision("waiting", "apply_pending")
        if len(self.levels) == 1:
            return self._suspend("one_legal_extent_is_static", restore=False)
        if gpu_limited is not True:
            return self._suspend("pixel_gpu_bottleneck_not_proven", restore=False)
        if not isinstance(sample, Sample) or type(sample.completed_id) is not int or sample.completed_id < 0:
            return self._suspend("completed_identity_unavailable")
        if sample.generation != self.generation or type(sample.generation) is not int:
            return self._suspend("generation_mismatch")
        if sample.size != self.confirmed.size or not _size(sample.size):
            return self._suspend("extent_mismatch")
        if self.last_id is not None and sample.completed_id <= self.last_id:
            # A duplicate's rewritten payload cannot refresh the original sample.
            if self.last_recorded_ms is None or now_ms - self.last_recorded_ms > self.tuning.max_age_ms:
                return self._suspend("fresh_feedback_expired")
            return Decision("hold", "duplicate_or_out_of_order")
        self.last_id = sample.completed_id
        if (not _finite(sample.recorded_ms) or not _finite(sample.gpu_ms)
                or sample.gpu_ms <= 0 or sample.recorded_ms < 0):
            return self._suspend("invalid_gpu_sample")
        age = now_ms - sample.recorded_ms
        if age < 0 or age > self.tuning.max_age_ms:
            return self._suspend("sample_age_invalid")
        if self.last_recorded_ms is not None:
            gap = sample.recorded_ms - self.last_recorded_ms
            if gap <= 0:
                return self._suspend("recording_clock_not_increasing")
            if gap > self.tuning.max_gap_ms:
                self._reset_evidence()
        self.last_recorded_ms = sample.recorded_ms
        # Exact fixed-threshold p90 predicates need counts, not a retained array
        # or periodic subsampling that can alias alternating expensive frames.
        if self.window_count >= self.tuning.maximum_samples:
            self.fault = "window_capacity_contract_failed"
            return self._suspend(self.fault)
        if self.window_begin_ms is None:
            self.window_begin_ms = sample.recorded_ms
        budget = 1000.0 / self.tuning.target_fps
        self.window_count += 1
        self.above_high += int(sample.gpu_ms > self.tuning.down_ratio * budget)
        self.below_low += int(sample.gpu_ms < self.tuning.up_ratio * budget)
        span = sample.recorded_ms - self.window_begin_ms
        if self.window_count < self.tuning.minimum_samples or span < self.tuning.window_ms:
            return Decision("warming", "window_incomplete")
        begin, end = self.window_begin_ms, sample.recorded_ms
        rank = (9 * self.window_count + 9) // 10
        high = self.window_count - self.above_high < rank
        low = self.below_low >= rank
        self._clear_window()
        elapsed = now_ms - self.last_change_ms
        if high:
            self.high_count = min(self.high_count + 1, self.tuning.high_windows)
            self.low_since_ms = None
            if self.index == 0:
                return Decision("hold", "floor_target_miss")
            if self.high_count >= self.tuning.high_windows and elapsed >= self.tuning.down_dwell_ms:
                return self._propose(self.index - 1, "sustained_gpu_over_budget", now_ms)
            return Decision("hold", "high_window_or_dwell")
        if low:
            self.high_count = 0
            if self.low_since_ms is None:
                self.low_since_ms = begin
            if self.index == len(self.levels) - 1:
                return Decision("hold", "at_user_ceiling")
            if (end - self.low_since_ms >= self.tuning.recovery_ms
                    and elapsed >= self.tuning.up_dwell_ms):
                return self._propose(self.index + 1, "sustained_gpu_headroom", now_ms)
            return Decision("hold", "recovery_window_or_dwell")
        self.high_count = 0
        self.low_since_ms = None
        return Decision("hold", "deadband")

    def _propose(self, index: int, reason: str, now_ms: float) -> Decision:
        self.pending = Change(self.next_request_id, self.generation, self.levels[index], reason)
        self.next_request_id += 1
        self.pending_since_ms = now_ms
        self._reset_evidence()
        return Decision("propose", reason, self.pending)

    def acknowledge(self, change: Change, generation: int, observed: Size,
                    now_ms: float, *, accepted: bool) -> Decision:
        """Consume only the matching request; stale callbacks cannot apply it.

        accepted means the separately qualified adapter observed the actual
        provider/extent and required history readiness. Setter success is weaker.
        A timeout/failure requires fixed fallback and a new owner/controller epoch.
        """
        if not self._clock(now_ms) or self.fault:
            return self._suspend(self.fault)
        if self.pending is None:
            return Decision("ignored", "no_pending_change")
        # The exact in-process object is the opaque transaction token. Numeric
        # IDs alone can collide after owner replacement; copied/old tokens fail.
        if change is not self.pending:
            return Decision("ignored", "stale_acknowledgement")
        if now_ms - self.pending_since_ms >= self.tuning.apply_timeout_ms:
            self.fault = "apply_timeout"
            return self._suspend(self.fault)
        if (accepted is not True or type(generation) is not int
                or generation <= self.generation or not _size(observed)
                or observed != self.pending.target.size):
            self.fault = "apply_rejected_or_unverified"
            return self._suspend(self.fault)
        self.index = self.levels.index(self.pending.target)
        self.generation = generation
        self.last_change_ms = now_ms
        self.pending = None
        self.last_id = None
        self.last_recorded_ms = None
        self._reset_evidence()
        return Decision("accepted", "observed_apply")
