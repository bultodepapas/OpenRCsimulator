#!/usr/bin/env python3
"""Independently check retained helicopter arming observations with stdlib.

This verifies logged commands, linkage arithmetic, selected curve values and
reported transaction outcomes. It does not rerun Godot, establish physical
radio input reachability, or decide whether the premix guard is intended.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


_EXPECTED = {
    "constructed_body_rates": "CONSTRUCTED",
    "moderate_bank_67": "TAPE",
    "large_bank_355": "TAPE",
    "six_tick_gaps_181": "SPACED_TAPE",
}


def _check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def _float(value: Any, context: str) -> float:
    _check(type(value) in (int, float), f"{context}: expected a number")
    result = float(value)
    _check(math.isfinite(result), f"{context}: nonfinite value")
    return result


def _close(actual: float, expected: float, context: str, tol: float = 2e-11) -> None:
    _check(math.isclose(actual, expected, rel_tol=tol, abs_tol=tol),
           f"{context}: {actual!r} does not match {expected!r}")


def _array(value: Any, length: int, context: str) -> list[float]:
    _check(isinstance(value, list) and len(value) == length,
           f"{context}: expected {length} values")
    return [_float(v, f"{context}[{i}]") for i, v in enumerate(value)]


def _quantity(node: dict[str, Any], name: str) -> float:
    value = node[name]
    _check(isinstance(value, dict) and "value" in value,
           f"stock quantity {name} lacks a value")
    return _float(value["value"], f"stock {name}")


def _curve_pitch(normal_pitch: list[float], throttle: float) -> float:
    """Independently interpolate the authored five-point collective curve."""
    _check(0.0 <= throttle <= 1.0, "collective throttle outside [0,1]")
    x = throttle * 4.0  # knots [0, 0.25, 0.5, 0.75, 1]
    if x >= 4.0:
        return normal_pitch[-1]
    lower = math.floor(x)
    return normal_pitch[lower] + (x - lower) * (normal_pitch[lower + 1] - normal_pitch[lower])


def verify(log_text: str, stock_json_dict: dict[str, Any]) -> dict[str, Any]:
    """Raise AssertionError on inconsistency; otherwise return observations.

    `log_text` is the checked Godot engine log; `stock_json_dict` is the
    parsed, unmodified X-Cell aircraft JSON. Arithmetic uses its authored
    normal curve and collective linkage quantities, not hard-coded gain.
    """
    _check(isinstance(log_text, str), "log is not text")
    _check(isinstance(stock_json_dict, dict), "stock data is not an object")
    _check(stock_json_dict.get("id") == "xcell-60-research", "wrong stock aircraft")
    electronics = stock_json_dict["electronics"]
    linkage = electronics["linkage"]
    gain = _quantity(linkage, "collective_rad_per_unit")
    collective_min = _quantity(linkage, "collective_min_rad")
    collective_max = _quantity(linkage, "collective_max_rad")
    _check(gain > 0.0 and collective_min < collective_max, "invalid stock linkage")
    curve = _array(electronics["curves_by_mode"]["normal"]["pitch"]["value"], 5,
                   "stock normal pitch curve")
    _check(all(-1.0 <= point <= 1.0 for point in curve), "invalid stock pitch curve")

    records: dict[str, dict[str, Any]] = {}
    for line in log_text.splitlines():
        prefix, separator, payload = line.partition(" ")
        if prefix not in set(_EXPECTED.values()):
            continue
        _check(bool(separator), f"{prefix}: missing payload")
        row = json.loads(payload)
        _check(isinstance(row, dict), f"{prefix}: expected JSON object")
        case = row.get("case")
        _check(case in _EXPECTED and prefix == _EXPECTED[case], f"unexpected record {case!r}")
        _check(case not in records, f"duplicate record {case}")
        records[case] = row
    _check(set(records) == set(_EXPECTED), "missing arming observation cases")
    _check(log_text.splitlines().count("R8 final arming observations: 22 checks, 0 failures") == 1,
           "missing or duplicate observation completion marker")

    computed: dict[str, Any] = {}
    logged_hash: str | None = None
    for case, row in records.items():
        _check(row.get("aircraft") == stock_json_dict["id"], f"{case}: wrong aircraft")
        row_hash = row.get("aircraft_sha256")
        _check(isinstance(row_hash, str) and len(row_hash) == 64
               and all(c in "0123456789abcdef" for c in row_hash), f"{case}: invalid aircraft hash")
        if logged_hash is None:
            logged_hash = row_hash
        _check(row_hash == logged_hash, f"{case}: aircraft hash differs from other records")
        _check(row.get("backend") == {"backend": "gdscript_reference"}, f"{case}: unexpected backend")
        _close(_float(row.get("dt_s"), f"{case} dt"), 1.0 / 240.0, f"{case} dt", 1e-14)
        _close(_float(row.get("guard_limit_deg"), f"{case} guard"), 1.0, f"{case} guard")
        _check(row.get("fault") == "" and row.get("crash") == {}, f"{case}: fault or crash")
        for key in ("accepted", "disarm_return", "rearm_return", "armed_in_hold", "hold_release_return"):
            _check(row.get(key) is True, f"{case}: {key} was not true")
        _array(row.get("state_after19"), 19, f"{case} after state")
        before_key = "pre_rearm_state19" if case == "six_tick_gaps_181" else "pre_action_state19"
        before = _array(row.get(before_key), 19, f"{case} before state")
        commands = _array(row.get("servo_commands"), 3, f"{case} raw servos")
        positions = _array(row.get("servo_positions"), 3, f"{case} limited servos")
        for i, command in enumerate(commands):
            _close(positions[i], max(-1.0, min(1.0, command)), f"{case} servo {i}")
        _check(any(abs(command) > 1.0 for command in commands), f"{case}: no servo clipping")

        # The mixer has zero-sum cyclic terms. Its raw mean yields premix;
        # the clipped mean is the collective delivered through the linkage.
        raw_rad = sum(commands) / 3.0 * gain
        post_rad = max(collective_min, min(collective_max, sum(positions) / 3.0 * gain))
        premix = math.degrees(raw_rad)
        postmix = math.degrees(post_rad)
        _close(_float(row.get("premix_deg"), f"{case} premix"), premix, f"{case} raw servo mean")
        _close(_float(row.get("postmix_from_stage_deg"), f"{case} stage postmix"), postmix,
               f"{case} limited servo mean")
        if "postmix_deg" in row:
            _close(_float(row["postmix_deg"], f"{case} postmix"), postmix, f"{case} postmix")
        _close(_float(row.get("direct_control_deg"), f"{case} direct control"), premix,
               f"{case} direct negative control")
        _check(abs(premix) < 1.0 and abs(postmix) > 1.0,
               f"{case}: does not cross reported arming threshold")

        if case == "constructed_body_rates":
            _check(row.get("reset_accepted") is True and row.get("trainer") is True,
                   "constructed reset/trainer not accepted")
            _close(before[10], -3.0, "constructed roll rate")
            _close(before[11], 3.0, "constructed pitch rate")
            _check(row.get("roll_pitch_yaw_input") == [0, 0, 0], "constructed pilot axes not centered")
            _close(_float(row.get("zero_feedback_deg"), "constructed zero feedback"), premix,
                   "constructed stationary negative control")
            _check(row.get("tick_before") == 0 and row.get("tick_after") == 1,
                   "constructed tick advancement")
        else:
            _array(row.get("initial_state19"), 19, f"{case} initial state")
            tape, next_command = row.get("input_tape"), row.get("next_command")
            _check(isinstance(tape, dict) and isinstance(next_command, dict), f"{case}: missing input tape")
            _check(tape.get("trainer") is False and next_command.get("trainer") is True,
                   f"{case}: wrong trainer transitions")
            expected_roll, expected_pitch = (-1.0, 1.0) if case == "large_bank_355" else (1.0, -1.0)
            _check(tape.get("roll") == expected_roll and tape.get("pitch") == expected_pitch
                   and tape.get("yaw") == 0.0, f"{case}: wrong input-tape axes")
            tape_throttle = _float(tape.get("throttle"), f"{case} tape throttle")
            _check(0.0 <= tape_throttle <= 1.0, f"{case}: tape throttle out of bounds")
            _check(all(next_command.get(key) == 0.0 for key in ("roll", "pitch", "yaw")),
                   f"{case}: pilot axes not centered")
            throttle = _float(next_command.get("throttle"), f"{case} throttle")
            expected_raw = _curve_pitch(curve, throttle) * gain
            _close(math.degrees(expected_raw), premix, f"{case} independent stock curve")
            if case == "six_tick_gaps_181":
                _check(tape.get("ticks") == 181 and row.get("delay_ticks") == 6,
                       f"{case}: wrong input or delay length")
                _check(row.get("pre_rearm_tick") == 187 and row.get("tick_after") == 199,
                       f"{case}: wrong pre/post rearm ticks")
                _check(row["pre_rearm_tick"] == tape["ticks"] + row["delay_ticks"]
                       and row["tick_after"] == row["pre_rearm_tick"] + 2 * row["delay_ticks"],
                       f"{case}: incorrect spaced transaction flow")
            else:
                expected_ticks = 67 if case == "moderate_bank_67" else 355
                _check(tape.get("ticks") == expected_ticks and row.get("tick_before") == expected_ticks
                       and row.get("tick_after") == expected_ticks + 1,
                       f"{case}: wrong tape or accepted tick")
        expected_sign = -1 if case == "large_bank_355" else 1
        _check(expected_sign * premix > 0.0 and expected_sign * postmix > 0.0,
               f"{case}: unexpected collective sign")
        computed[case] = {
            "premix_deg": premix,
            "postmix_deg": postmix,
            "excess_over_one_degree": abs(postmix) - 1.0,
            "raw_servos": commands,
            "limited_servos": positions,
        }
    return {
        "ok": True,
        "aircraft": stock_json_dict["id"],
        "logged_aircraft_sha256": logged_hash,
        "collective_gain_rad_per_unit": gain,
        "curve": curve,
        "cases": computed,
        "scope": "Arithmetic and logged transaction checks only; no Godot rerun, UI or hardware exercise, physical validation, or choice of arming contract.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--stock", type=Path, required=True)
    args = parser.parse_args()
    stock_bytes = args.stock.read_bytes()
    result = verify(args.log.read_text(), json.loads(stock_bytes))
    _check(hashlib.sha256(stock_bytes).hexdigest() == result["logged_aircraft_sha256"],
           "stock input bytes disagree with logged aircraft hash")
    print(json.dumps(result, indent=2, sort_keys=True, allow_nan=False))


if __name__ == "__main__":
    main()
