"""Verify a complete, finite, trimmed app flight against an externally requested duration.

Defaults match the three-second, 240 Hz smoke flight. Capture/export callers pass
--duration explicitly. The initial tick is a sample, not evidence of a flown tick.
"""
import argparse
import csv
import math
from pathlib import Path
import sys

COLUMNS = (
    "tick t_s north_m east_m down_m alt_m u_mps v_mps w_mps speed_mps "
    "qw qx qy qz yaw_deg pitch_deg roll_deg p_radps q_radps r_radps "
    "Fx_N Fy_N Fz_N Mx_Nm My_Nm Mz_Nm cmd_roll cmd_pitch cmd_yaw cmd_throttle "
    "engine_rpm srv_roll srv_pitch srv_yaw"
).split()
# Trace v3 prints time to nine decimal places. Allow rounding, not a missing tick.
TIME_TOLERANCE = 1e-9


def check(path: Path, duration: float, hz: int) -> str:
    if not math.isfinite(duration) or duration <= 0 or hz <= 0:
        raise ValueError("duration and tick rate must be finite and positive")
    tick_count = duration * hz
    if not math.isfinite(tick_count) or tick_count >= 2**63:
        raise ValueError("duration exceeds the tick counter")
    expected_ticks = math.floor(tick_count)
    if tick_count - expected_ticks >= 0.5:  # nearest tick; positive half-ties round up
        expected_ticks += 1
    if expected_ticks < 1:
        raise ValueError("duration must round to at least one physics tick")
    lines = path.read_text(encoding="utf-8").splitlines()
    metadata = {}
    for line in lines:
        if line.startswith("# ") and ": " in line:
            key, value = line[2:].split(": ", 1)
            if key in metadata:
                raise ValueError(f"duplicate metadata: {key}")
            metadata[key] = value
    if metadata.get("format") != "openrc-trace v3":
        raise ValueError("expected openrc-trace v3")
    try:
        dt = float(metadata["dt_s"])
    except (KeyError, ValueError) as error:
        raise ValueError("missing or invalid dt_s") from error
    if not math.isfinite(dt) or not math.isclose(dt, 1 / hz, rel_tol=1e-6, abs_tol=0):
        raise ValueError("dt_s does not match the requested tick rate")
    rows = list(csv.reader(line for line in lines if not line.startswith("#")))
    if not rows or rows[0] != COLUMNS:
        raise ValueError("missing or unexpected trace columns")
    if len(rows) - 1 != expected_ticks + 1:
        raise ValueError(f"expected {expected_ticks + 1} samples, got {len(rows) - 1}")
    data = []
    for index, row in enumerate(rows[1:]):
        if len(row) != len(COLUMNS):
            raise ValueError(f"sample {index}: wrong column count")
        try:
            values = [float(cell) for cell in row]
        except ValueError as error:
            raise ValueError(f"sample {index}: nonnumeric value") from error
        if not all(math.isfinite(value) for value in values):
            raise ValueError(f"sample {index}: non-finite value")
        sample = dict(zip(COLUMNS, values))
        if sample["tick"] != index:
            raise ValueError(f"sample {index}: discontinuous tick")
        if abs(sample["t_s"] - index / hz) > TIME_TOLERANCE:
            raise ValueError(f"sample {index}: wrong elapsed time")
        data.append(sample)
    first, last = data[0], data[-1]
    for key, tolerance in (("speed_mps", .01), ("pitch_deg", .05), ("alt_m", .05), ("engine_rpm", 1.0)):
        if abs(last[key] - first[key]) > tolerance:
            raise ValueError(f"{key} drifts {first[key]:.6f} -> {last[key]:.6f}")
    if not .05 < first["cmd_throttle"] < .95 or first["engine_rpm"] < 3000:
        raise ValueError("engine not at a trimmed setting")
    if abs(first["cmd_pitch"]) < 1e-6:
        raise ValueError("no elevator trim applied")
    ground = metadata.get("ground", "")
    if not ground:
        raise ValueError("no ground metadata")
    if "spring-damper" in ground and "field '" not in ground:
        raise ValueError("gear without the field's surfaces")
    return (f"trimmed level flight: {expected_ticks} ticks, {last['t_s']:.9f} s, all samples finite; "
            f"alt {first['alt_m']:.3f} -> {last['alt_m']:.3f} m, speed {last['speed_mps']:.4f} m/s")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--duration", type=float, default=3.0, help="requested flight seconds (default: 3)")
    parser.add_argument("--hz", type=int, default=240, help="requested physics ticks/s (default: 240)")
    args = parser.parse_args()
    try:
        print(check(args.trace, args.duration, args.hz))
    except (OSError, UnicodeError, ValueError, csv.Error) as error:
        print(f"FAIL {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
