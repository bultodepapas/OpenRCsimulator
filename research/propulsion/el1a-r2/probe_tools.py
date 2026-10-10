#!/usr/bin/env python3
"""EL1a-R2: isolated tool experiments; no simulator or physical validation."""
import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from importlib.metadata import version
from pathlib import Path

import numpy as np
from scipy.integrate import solve_ivp
from scipy.optimize import least_squares


VERSIONS = {"numpy": "1.26.4", "scipy": "1.11.4"}
ROOT = Path(__file__).resolve().parents[3]


def headless_cases(godot: Path) -> dict:
    """Deliberate defects exist only inside a disposable standalone project."""
    scripts = {
        "control": 'extends SceneTree\nfunc _initialize() -> void:\n\tprint("EL-R2 COMPLETE 1 0")\n\tquit(0)\n',
        "explicit_failure": 'extends SceneTree\nfunc _initialize() -> void:\n\tprint("EL-R2 COMPLETE 1 1")\n\tquit(1)\n',
        "logged_runtime_error": 'extends SceneTree\nfunc _initialize() -> void:\n\tbroken_helper()\n\tprint("EL-R2 COMPLETE 1 0")\n\tquit(0)\nfunc broken_helper() -> void:\n\tvar values: Dictionary = {}\n\tprint(values["missing"])\n',
        "missing_completion": 'extends SceneTree\nfunc _initialize() -> void:\n\tprint("started")\n\tquit(0)\n',
        "parse_failure": 'extends SceneTree\nfunc _initialize() -> void:\n\tvar impossible = ???\n',
        "timeout": 'extends SceneTree\nfunc _initialize() -> void:\n\tpass\n',
    }
    results = {}
    with tempfile.TemporaryDirectory(prefix="openrc-el-r2-") as name:
        project = Path(name)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="EL R2 isolated probe"\n')
        for case, source in scripts.items():
            (project / "probe.gd").write_text(source)
            command = [str(godot), "--headless", "--audio-driver", "Dummy", "--path", str(project)]
            if case == "parse_failure":
                command.append("--check-only")
            command += ["--script", "res://probe.gd"]
            timed_out = False
            try:
                process = subprocess.run(command, text=True, capture_output=True, timeout=3 if case == "timeout" else 15)
                code, log = process.returncode, process.stdout + process.stderr
            except subprocess.TimeoutExpired as error:
                timed_out, code = True, None
                chunks = [error.stdout or b"", error.stderr or b""]
                log = "".join(v.decode(errors="replace") if isinstance(v, bytes) else v for v in chunks)
            summary = re.search(r"^EL-R2 COMPLETE (\d+) (\d+)$", log, re.M)
            engine_error = bool(re.search(r"^(?:SCRIPT |SHADER )?ERROR:", log, re.M))
            accepted = bool(not timed_out and code == 0 and not engine_error and summary and int(summary[1]) > 0 and int(summary[2]) == 0)
            assert accepted == (case == "control"), (case, log)
            results[case] = {"exit_code": code, "timed_out": timed_out, "completion": summary.group(0) if summary else None,
                             "engine_error": engine_error, "accepted": accepted,
                             "diagnostics": [line for line in log.splitlines() if re.match(r"^(?:SCRIPT |SHADER )?ERROR:", line)]}
        # This is the failure mode behind the repository's existing log gate.
        assert results["logged_runtime_error"]["exit_code"] == 0
        assert results["logged_runtime_error"]["engine_error"]
    return results


def independent_solvers() -> dict:
    # Original fixed-carrier, positive-speed no-prop fixture: tau=J*R/(Kt*Ke).
    kv, resistance, inertia, i0, effective_voltage = 800.0, 0.06, 0.0001, 1.0, 6.0
    kt = 60.0 / (2.0 * np.pi * kv)
    tau = inertia * resistance / (kt * kt)
    steady = (effective_voltage - resistance * i0) / kt
    initial = 1.0  # rad/s; does not cross the nonsmooth breakaway branch.
    times = np.linspace(0.0, 0.1, 101)
    exact = steady + (initial - steady) * np.exp(-times / tau)
    results, samples = {}, {}
    for method in ("DOP853", "Radau"):
        solution = solve_ivp(lambda _t, y: [(steady-y[0])/tau], (0.0, 0.1), [initial], method=method,
                             rtol=1e-11, atol=[1e-11], t_eval=times, max_step=0.01)
        error = float(np.max(np.abs(solution.y[0] - exact)))
        assert solution.success and solution.status == 0 and solution.t[-1] == times[-1]
        assert np.isfinite(solution.y).all() and error < 1e-7
        results[method] = {"success": bool(solution.success), "status": solution.status, "max_error_radps": error, "rhs_evaluations": solution.nfev}
        samples[method] = solution.y[0]
    # A dense output grid does not limit internal event-detection steps.
    def periodic_event(t, _y):
        return np.sin(4.0 * np.pi * (t - 0.05))
    event_results = {}
    for step in (1.0, 0.05):
        solution = solve_ivp(lambda _t, _y: [1.0], (0.0, 1.0), [0.0], first_step=step, max_step=step,
                             events=periodic_event, t_eval=np.linspace(0.0, 1.0, 1001), rtol=1e-10, atol=1e-12)
        roots = solution.t_events[0]
        assert solution.success
        if step == 1.0:
            assert len(roots) == 0
        else:
            assert len(roots) == 4 and np.max(np.abs(roots - [0.05, 0.3, 0.55, 0.8])) < 1e-10
        event_results[str(step)] = {"success": bool(solution.success), "output_samples": len(solution.t), "detected_times_s": roots.tolist()}
    return {"scope": "Independent numerical methods versus a derived smooth oracle, not Godot integration or physical measurements",
            "fixture": {"kv_rpm_per_v": kv, "resistance_ohm": resistance, "rotor_inertia_kgm2": inertia,
                        "i0_a": i0, "effective_voltage_v": effective_voltage, "initial_radps": initial, "tau_s": tau},
            "rtol": 1e-11, "atol_radps": 1e-11, "max_step_s": 0.01, "methods": results,
            "max_between_method_radps": float(np.max(np.abs(samples["DOP853"] - samples["Radau"]))),
            "synthetic_periodic_event_counterexample": event_results}


def identifiability() -> dict:
    # Normalized zero-I0 no-load speed depends on R*J; neither is identifiable
    # individually when all the observations are only this speed response.
    times = np.linspace(0.002, 0.12, 50)
    tau_reference = 0.04
    measured_speed = 1.0 - np.exp(-times/tau_reference)

    def residual(theta, measure_resistance=False):
        tau = tau_reference * np.exp(np.sum(theta))
        values = (1.0 - np.exp(-times/tau) - measured_speed) / 0.001
        return np.append(values, (np.exp(theta[0])-1.0)/0.01) if measure_resistance else values

    def jacobian(theta, measure_resistance=False):
        tau = tau_reference * np.exp(np.sum(theta))
        column = -(times/tau) * np.exp(-times/tau) / 0.001
        matrix = np.column_stack([column, column])
        return np.vstack([matrix, [np.exp(theta[0])/0.01, 0.0]]) if measure_resistance else matrix

    fits = []
    for start in ([0.5, 2.0], [2.0, 0.5]):
        result = least_squares(residual, np.log(start), jac=jacobian, bounds=(-3.0, 3.0), x_scale=[1.0, 1.0],
                               ftol=1e-12, xtol=1e-12, gtol=1e-12)
        assert result.success and np.max(np.abs(result.fun)) < 1e-8
        fits.append({"success": bool(result.success), "relative_R_J": np.exp(result.x).tolist(), "max_scaled_residual": float(np.max(np.abs(result.fun)))})
    rank_without = int(np.linalg.matrix_rank(jacobian(np.zeros(2))))
    result = least_squares(lambda t: residual(t, True), np.log([0.5, 2.0]), jac=lambda t: jacobian(t, True),
                           bounds=(-3.0, 3.0), x_scale=[1.0, 1.0], ftol=1e-12, xtol=1e-12, gtol=1e-12)
    rank_with = int(np.linalg.matrix_rank(jacobian(result.x, True)))
    assert rank_without == 1 and rank_with == 2 and result.success
    assert np.max(np.abs(np.exp(result.x)-1.0)) < 1e-8
    return {"scope": "Original noiseless synthetic local-identifiability example, not fitted Timber data",
            "parameterization": "theta=log([R/Rref, J/Jref]); normalized speed=1-exp(-t/(0.04*exp(sum(theta))))",
            "assumed_scales": {"normalized_speed": 0.001, "independent_relative_resistance": 0.01},
            "speed_only_fits": fits, "speed_only_rank": rank_without,
            "speed_only_singular_values": np.linalg.svd(jacobian(np.zeros(2)), compute_uv=False).tolist(),
            "with_resistance_rank": rank_with, "with_resistance_relative_R_J": np.exp(result.x).tolist(),
            "with_resistance_singular_values": np.linalg.svd(jacobian(result.x, True), compute_uv=False).tolist()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    observed = {name: version(name) for name in VERSIONS}
    if observed != VERSIONS:
        raise SystemExit(f"Use isolated research/propulsion/el1a-r2/requirements.txt versions: {observed}")
    protected = [ROOT/"app/physics/electric_motor.gd", ROOT/"app/tests/test_electric_motor.gd"]
    before = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    report = {"format": "openrc-electric-research-tools v1", "scope": "Research-only tool qualification; no production implementation or physical validation",
              "versions": observed, "godot": subprocess.check_output([str(args.godot.resolve()), "--version"],text=True).strip(),
              "headless": headless_cases(args.godot.resolve()), "solvers": independent_solvers(), "identifiability": identifiability()}
    after = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    assert before == after, "Electric implementation changed during isolated probes"
    report.update({"electric_files_unchanged_sha256": after, "probe_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "ok": True})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False)+"\n")
    print(json.dumps({"ok": True, "godot": report["godot"], "headless_cases": len(report["headless"]),
                      "solver_errors_radps": {k:v["max_error_radps"] for k,v in report["solvers"]["methods"].items()},
                      "sensitivity_ranks": [report["identifiability"]["speed_only_rank"],report["identifiability"]["with_resistance_rank"]]}))


if __name__ == "__main__":
    main()
