#!/usr/bin/env python3
"""Run the production P-51 shaft-integration refinement sweep and write its evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[4]
APP = ROOT / "app"
SCRIPT = Path(__file__).with_name("refinement.gd").resolve()
DEFAULT_RATES = [60, 120, 240, 480, 960, 1920, 3840]
DEFAULT_MODES = ["coupled-rk4", "split"]
REFERENCE_HZ = 3840
RESULT_DATE = "2026-10-09"
METRICS = ["position_m", "velocity_mps", "rate_radps", "attitude_rad", "rpm"]
SOURCE_PATHS = [
    "app/data/aircraft/p51d_mustang_120.json",
    "app/input/commands.gd",
    "app/physics/aircraft_data.gd",
    "app/physics/aero.gd",
    "app/physics/air_data.gd",
    "app/physics/ground_contact.gd",
    "app/physics/ground_surfaces.gd",
    "app/physics/integrator.gd",
    "app/physics/math3d.gd",
    "app/sim/flight_session.gd",
    "app/sim/scenarios.gd",
    "app/sim/simulation.gd",
    "app/physics/rotor_coupling.gd",
    "app/physics/propulsion.gd",
    "app/physics/dynamics.gd",
    "app/physics/rigid_body.gd",
    "app/physics/wash_transport.gd",
    "app/physics/wind_config.gd",
    "app/physics/wind_field.gd",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Godot executable; defaults to PATH, then app/get-godot.sh")
    parser.add_argument("--rates", default=",".join(map(str, DEFAULT_RATES)))
    parser.add_argument("--reference-hz", type=int, default=REFERENCE_HZ)
    parser.add_argument("--duration", type=float, default=0.5)
    parser.add_argument("--modes", default=",".join(DEFAULT_MODES), help="comma-separated: coupled-rk4,split")
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("results.json"))
    parser.add_argument("--report", type=Path, default=Path(__file__).with_name("report.md"))
    return parser.parse_args()


def resolve_godot(requested: str | None) -> str:
    if requested:
        return requested
    on_path = shutil.which("godot")
    if on_path:
        return on_path
    launcher = APP / "get-godot.sh"
    result = subprocess.run([str(launcher)], check=True, text=True, capture_output=True)
    candidate = result.stdout.strip().splitlines()[-1]
    if not Path(candidate).is_file():
        raise RuntimeError(f"get-godot.sh did not return an executable: {candidate}")
    return candidate


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_identity() -> str:
    try:
        return subprocess.run(
            ["git", "describe", "--always", "--dirty"],
            cwd=ROOT,
            check=True,
            text=True,
            capture_output=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def run_probe(godot: str, mode: str, rates: list[int], duration: float) -> dict[str, Any]:
    command = [
        godot,
        "--headless",
        "--path",
        str(APP),
        "--script",
        str(SCRIPT),
        "--",
        f"--mode={mode}",
        f"--rates={','.join(map(str, rates))}",
        f"--duration={duration:.17g}",
    ]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    marker = "REFINEMENT_JSON:"
    candidates = [line.split(marker, 1)[1] for line in completed.stdout.splitlines() if marker in line]
    if completed.returncode != 0 or not candidates:
        details = "\n".join(part for part in [completed.stdout, completed.stderr] if part.strip())
        raise RuntimeError(
            f"Godot refinement probe failed for {mode} (exit {completed.returncode}).\n{details}"
        )
    try:
        payload = json.loads(candidates[-1])
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Could not parse Godot result for {mode}: {exc}\n{candidates[-1]}") from exc
    if not payload.get("ok"):
        raise RuntimeError(f"Godot probe returned failure for {mode}: {payload}")
    if payload.get("mode") != mode:
        raise RuntimeError(f"Godot probe mode mismatch: expected {mode}, got {payload.get('mode')}")
    return payload


def vector_norm(values: list[float]) -> float:
    return math.sqrt(sum(value * value for value in values))


def quaternion_distance(left: list[float], right: list[float]) -> float:
    ql = left[6:10]
    qr = right[6:10]
    nl = vector_norm(ql)
    nr = vector_norm(qr)
    if nl == 0 or nr == 0:
        return math.nan
    ql = [value / nl for value in ql]
    qr = [value / nr for value in qr]
    dot = sum(a * b for a, b in zip(ql, qr))
    sign = 1.0 if dot >= 0.0 else -1.0
    chord = vector_norm([a - sign * b for a, b in zip(ql, qr)])
    return 4.0 * math.asin(min(1.0, chord / 2.0))


def state_errors(run: dict[str, Any], reference: dict[str, Any]) -> dict[str, float]:
    state = run["state"]
    ref_state = reference["state"]
    return {
        "position_m": vector_norm([state[i] - ref_state[i] for i in range(0, 3)]),
        "velocity_mps": vector_norm([state[i] - ref_state[i] for i in range(3, 6)]),
        "rate_radps": vector_norm([state[i] - ref_state[i] for i in range(10, 13)]),
        "attitude_rad": quaternion_distance(state, ref_state),
        "rpm": abs(float(run["rpm"]) - float(reference["rpm"])),
    }


def observed_order(errors: dict[int, dict[str, float]], rate: int, metric: str) -> float | None:
    fine_rate = rate * 2
    if rate not in errors or fine_rate not in errors:
        return None
    coarse = errors[rate][metric]
    fine = errors[fine_rate][metric]
    if not math.isfinite(coarse) or not math.isfinite(fine) or coarse <= 1e-15 or fine <= 1e-15:
        return None
    return math.log2(coarse / fine)


def build_analysis(runs: list[dict[str, Any]], reference_hz: int) -> dict[str, Any]:
    grouped: dict[tuple[str, str], dict[int, dict[str, Any]]] = {}
    for run in runs:
        grouped.setdefault((run["mode"], run["case"]), {})[int(run["rate_hz"])] = run
    analysis: dict[str, Any] = {}
    for (mode, case), by_rate in sorted(grouped.items()):
        if reference_hz not in by_rate:
            raise RuntimeError(f"Missing {reference_hz} Hz reference for {mode}/{case}")
        reference = by_rate[reference_hz]
        errors = {rate: state_errors(row, reference) for rate, row in by_rate.items()}
        orders = {
            metric: {
                str(rate): observed_order(errors, rate, metric)
                for rate in sorted(errors)
                if rate < reference_hz and rate * 2 in errors
            }
            for metric in METRICS
        }
        analysis.setdefault(mode, {})[case] = {
            "reference_hz": reference_hz,
            "errors": {str(rate): errors[rate] for rate in sorted(errors)},
            "observed_order_by_coarse_hz": orders,
        }
    return analysis


def validate_results(analysis: dict[str, Any], runs: list[dict[str, Any]]) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    failures: list[str] = []

    def add(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "passed": passed, "detail": detail})
        if not passed:
            failures.append(f"{name}: {detail}")

    coupled = analysis.get("coupled-rk4", {})
    throttle = coupled.get("throttle_step", {})
    order_data = throttle.get("observed_order_by_coarse_hz", {})
    missing_orders: list[str] = []
    out_of_range: list[str] = []
    for metric in METRICS:
        for rate in [60, 120, 240]:
            value = order_data.get(metric, {}).get(str(rate))
            if value is None:
                missing_orders.append(f"{metric}@{rate}")
            elif not 3.75 <= float(value) <= 4.25:
                out_of_range.append(f"{metric}@{rate}={float(value):.3f}")
    passed_order = not missing_orders and not out_of_range
    detail = "all five errors have p in [3.75, 4.25] at 60/120/240 Hz"
    if missing_orders or out_of_range:
        detail = ", ".join(missing_orders + out_of_range)
    add("smooth throttle-step order", passed_order, detail)

    rpm_errors: dict[str, float] = {}
    for case in ["throttle_step", "smooth_gust", "practical_punch"]:
        try:
            rpm_errors[case] = float(coupled[case]["errors"]["240"]["rpm"])
        except (KeyError, TypeError, ValueError):
            rpm_errors[case] = math.inf
    max_rpm_error = max(rpm_errors.values(), default=math.inf)
    passed_rpm = max_rpm_error <= 2e-4
    add("coupled 240 Hz RPM bound", passed_rpm,
        f"max error {max_rpm_error:.8g} rpm <= 0.0002 rpm; cases {rpm_errors}")

    punch = next((row for row in runs if row.get("mode") == "coupled-rk4"
        and row.get("case") == "practical_punch" and row.get("rate_hz") == 240), None)
    if punch is None:
        passed_knots = False
        knot_detail = "missing coupled practical_punch run at 240 Hz"
    else:
        crossings = punch.get("stage_queries", {}).get("endpoint_crossings", {})
        covered = {key: crossings.get(key, []) for key in ["cp_j", "ct_j", "shaft_rpm"]}
        passed_knots = all(covered[key] for key in covered)
        knot_detail = f"endpoint crossings: {covered}"
    add("0.8 punch table-knot coverage", passed_knots, knot_detail)

    return {"passed": not failures, "checks": checks, "failures": failures}


def fmt(value: float | None, digits: int = 6) -> str:
    if value is None or not math.isfinite(value):
        return "—"
    if abs(value) == 0.0:
        return "0"
    return f"{value:.{digits}g}"


def write_report(payload: dict[str, Any], output_path: Path, report_path: Path) -> None:
    analysis = payload["analysis"]
    rates = payload["rates_hz"]
    ref_hz = payload["reference_hz"]
    lines = [
        "# G2a RK4 refinement",
        "",
        f"Status: measured {payload['date']}; step G2a-RK4.",
        "",
        "This measures final-state convergence of the production P-51 flight session over exact 0.5 s runs. The servo inputs stay at the trimmed commands; `throttle_step` applies `trim + 0.03` at the initial boundary, `smooth_gust` applies a raised-cosine gust over the run, and `practical_punch` holds throttle at 0.8. Each integration mode is compared only with its own separate high-rate run.",
        "",
        f"Rates: {', '.join(map(str, rates))} Hz; reference: {ref_hz} Hz; simulated duration: {payload['duration_s']} s. All durations are integer tick counts. Errors are endpoint position, body velocity, body rate, quaternion angle, and RPM relative to the matching mode's reference.",
        "",
        "The observed orders use error-to-reference ratios between adjacent rates. Piecewise propulsion tables and their knots prevent a global fourth-order claim; table-knot diagnostics below show where the production load evaluations sampled ranges spanning knots.",
        "",
        f"Measurement gates: **{'PASS' if payload['validation']['passed'] else 'FAIL'}**. Smooth throttle-step order must remain within 3.75–4.25 for all five metrics at 60/120/240 Hz; coupled 240 Hz RPM error must stay at or below 0.0002 rpm in all cases; the 0.8 punch must cross propeller Cp/Ct and shaft power knots.",
        "",
        "## Coupled RK4",
        "",
    ]
    _append_mode_report(lines, "coupled-rk4", analysis.get("coupled-rk4", {}), payload)
    lines.extend(["", "## Sampled split baseline", ""])
    _append_mode_report(lines, "split", analysis.get("split", {}), payload)
    lines.extend(["", "## Stage and table-knot coverage", "", "`Stage span` lists table abscissae within the min/max values passed to production RK load evaluations. `Endpoint crossed` lists abscissae crossed between consecutive committed tick endpoints; it does not assert that an RK stage landed exactly on a knot.", ""])
    lines.extend([
        "| Mode | Case | Stage queries | J range | RPM range | Cp J stage span | Ct J stage span | Shaft RPM stage span | Endpoint crossings (Cp / Ct / shaft) |",
        "| --- | --- | ---: | ---: | ---: | --- | --- | --- | --- |",
    ])
    by_key = {(run["mode"], run["case"], run["rate_hz"]): run for run in payload["runs"]}
    for mode in payload["modes"]:
        for case in ["throttle_step", "smooth_gust", "practical_punch"]:
            row = by_key[(mode, case, 240)]
            diag = row["stage_queries"]
            lo_j = diag["stage_j_min"]
            hi_j = diag["stage_j_max"]
            lo_rpm = diag["stage_rpm_min"]
            hi_rpm = diag["stage_rpm_max"]
            spans = [row["stage_j_knots_in_range"], row["stage_ct_knots_in_range"], row["stage_shaft_rpm_knots_in_range"]]
            crossings = diag["endpoint_crossings"]
            lines.append(
                f"| {mode} | {case} | {diag['stage_query_count']} | {fmt(lo_j, 5)}–{fmt(hi_j, 5)} | {fmt(lo_rpm, 5)}–{fmt(hi_rpm, 5)} | "
                f"{_list_text(spans[0])} | {_list_text(spans[1])} | {_list_text(spans[2])} | "
                f"{_list_text(crossings['cp_j'])} / {_list_text(crossings['ct_j'])} / {_list_text(crossings['shaft_rpm'])} |"
            )
    output_link = Path(os.path.relpath(output_path.resolve(), report_path.parent.resolve())).as_posix()
    lines.extend(["", "## Reproduction", "", "```sh", "python3 docs/research/propulsion/G2a-RK4/refinement.py", "```", "", f"Machine-readable run and source hashes: [`{output_path.name}`]({output_link}).", ""])
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines), encoding="utf-8")


def _append_mode_report(lines: list[str], mode: str, mode_data: dict[str, Any], payload: dict[str, Any]) -> None:
    if not mode_data:
        lines.append("No run recorded.")
        return
    lines.extend([
        "Errors are final-state norms in the units shown; observed order `p` at a coarse rate uses that error divided by the next finer rate's error.",
        "",
    ])
    for case in ["throttle_step", "smooth_gust", "practical_punch"]:
        case_data = mode_data[case]
        errors = case_data["errors"]
        orders = case_data["observed_order_by_coarse_hz"]
        lines.extend([f"### {case}", "", "| Hz | Position (m) | Velocity (m/s) | Rate (rad/s) | Attitude (rad) | RPM | p position | p velocity | p rate | p attitude | p RPM |", "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"])
        for rate in payload["rates_hz"]:
            e = errors[str(rate)]
            order_values = [orders[metric].get(str(rate)) for metric in METRICS]
            lines.append(
                f"| {rate} | {fmt(e['position_m'])} | {fmt(e['velocity_mps'])} | {fmt(e['rate_radps'])} | {fmt(e['attitude_rad'])} | {fmt(e['rpm'])} | "
                + " | ".join(fmt(value, 3) for value in order_values)
                + " |"
            )
        lines.append("")


def _list_text(values: list[Any]) -> str:
    return ", ".join(fmt(float(value), 5) for value in values) if values else "—"


def main() -> int:
    args = parse_args()
    try:
        rates = sorted({int(token) for token in args.rates.split(",")})
        modes = [value.strip() for value in args.modes.split(",") if value.strip()]
    except ValueError as exc:
        print(f"invalid rates: {exc}", file=sys.stderr)
        return 2
    if not rates or any(rate <= 0 for rate in rates):
        print("rates must be positive integers", file=sys.stderr)
        return 2
    if args.reference_hz not in rates or args.reference_hz != max(rates):
        print("reference-hz must be the highest rate and appear in --rates", file=sys.stderr)
        return 2
    if not math.isfinite(args.duration) or args.duration <= 0:
        print("duration must be positive and finite", file=sys.stderr)
        return 2
    for rate in rates:
        if abs(args.duration * rate - round(args.duration * rate)) > 1e-9:
            print(f"duration {args.duration} is not an integer number of ticks at {rate} Hz", file=sys.stderr)
            return 2
    if not modes or any(mode not in {"coupled-rk4", "split"} for mode in modes):
        print("modes must be a comma-separated subset of coupled-rk4,split", file=sys.stderr)
        return 2
    try:
        godot = resolve_godot(args.godot)
        outputs = [run_probe(godot, mode, rates, args.duration) for mode in modes]
    except (OSError, subprocess.CalledProcessError, RuntimeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    runs = [row for output in outputs for row in output["rows"]]
    analysis = build_analysis(runs, args.reference_hz)
    hashes = {relative: sha256(ROOT / relative) for relative in SOURCE_PATHS}
    hashes["docs/research/propulsion/G2a-RK4/refinement.gd"] = sha256(SCRIPT)
    hashes["docs/research/propulsion/G2a-RK4/refinement.py"] = sha256(Path(__file__).resolve())
    validation = validate_results(analysis, runs)
    result = {
        "format": "openrc-g2a-rk4-refinement-results v1",
        "date": RESULT_DATE,
        "date_basis": "client date requested for this measurement record",
        "git_identity": git_identity(),
        "godot_executable": godot,
        "modes": modes,
        "rates_hz": rates,
        "reference_hz": args.reference_hz,
        "duration_s": args.duration,
        "cases": ["throttle_step", "smooth_gust", "practical_punch"],
        "source_sha256": hashes,
        "analysis": analysis,
        "validation": validation,
        "runs": runs,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    write_report(result, args.output, args.report)
    print(f"Wrote {args.output} and {args.report}")
    if not validation["passed"]:
        for failure in validation["failures"]:
            print(f"Measurement gate failed: {failure}", file=sys.stderr)
        return 1
    print("Measurement gates passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
