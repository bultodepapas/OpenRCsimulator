#!/usr/bin/env python3
"""H7: replay air goldens with exact adjacent-float math perturbations and branch tapes."""

from __future__ import annotations

import json
import hashlib
import os
import platform
import re
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path


APP_ROOT = Path(__file__).resolve().parents[1]
IGNORED = shutil.ignore_patterns(".godot", "captures")
PROBE = '''extends SceneTree

const M := preload("res://physics/math3d.gd")
const Aero := preload("res://physics/aero.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Golden := preload("res://tests/golden_flights.gd")
const Policy := preload("res://tests/replay_policy.gd")

func _f64_bits(value: float) -> int:
    var bytes := PackedByteArray()
    bytes.resize(8)
    bytes.encode_double(0, value)
    return bytes.decode_u64(0)

func _initialize() -> void:
    var base_sin: float = sin(0.375)
    var wrapped_sin: float = M.sin_(0.375)
    var base_atan2: float = atan2(0.5, 1.0)
    var wrapped_atan2: float = M.atan2_(0.5, 1.0)
    var report := {
        "sin_builtin_bits": _f64_bits(base_sin),
        "sin_wrapper_bits": _f64_bits(wrapped_sin),
        "atan2_builtin_bits": _f64_bits(base_atan2),
        "atan2_wrapper_bits": _f64_bits(wrapped_atan2),
        "tolerances": {
            "pos": Golden.TOL_POS, "vel": Golden.TOL_VEL, "att": Golden.TOL_ATT,
            "rate": Golden.TOL_RATE,
            "rpm": float(Policy.COMPONENTS["rpm"]["absolute"]),
            "servo": float(Policy.COMPONENTS["servo"]["absolute"]),
        },
        "goldens": {},
    }
    var session: Node = FlightSession.new()
    session.setup()
    root.add_child(session)
    for name in Golden.NAMES:
        var text: String = FileAccess.get_file_as_string(Golden.path(name))
        var golden: Variant = JSON.parse_string(text) if text != "" else null
        if typeof(golden) != TYPE_DICTIONARY:
            printerr("H7 could not read golden: %s" % name)
            quit(1)
            return
        var sim: Node = session.sim
        var trajectory_hash := HashingContext.new()
        trajectory_hash.start(HashingContext.HASH_SHA256)
        var sample := func(_tick: int, _t: float, state: PackedFloat64Array, _loads: PackedFloat64Array,
                _inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
            trajectory_hash.update(state.to_byte_array())
            trajectory_hash.update(aux.to_byte_array())
            trajectory_hash.update(sim.modes.to_byte_array())
        sim.stepped.connect(sample)
        var replay: Dictionary = Golden.replay(session, golden)
        sim.stepped.disconnect(sample)
        replay["trajectory_sha256"] = trajectory_hash.finish().hex_encode()
        replay["branch_signature"] = {
            "aero": Aero.h7_branch_tape.duplicate(),
            "ground": Ground.h7_branch_tape.duplicate(),
            "propulsion": Propulsion.h7_branch_tape.duplicate(),
        }
        report.goldens[name] = replay
    var base_alpha_text: String = OS.get_environment("OPENRC_H7_BASELINE_ATAN2")
    var threshold_text: String = OS.get_environment("OPENRC_H7_BRANCH_THRESHOLD")
    if not base_alpha_text.is_empty() and not threshold_text.is_empty():
        var base_alpha: float = base_alpha_text.to_float()
        var threshold: float = threshold_text.to_float()
        var ulp: float = threshold - base_alpha
        var envelope := { a1 = base_alpha - 16.0 * ulp, a2 = threshold, n1 = -1.0, n2 = -2.0 }
        var base_weight: float = Aero.stall_weight(base_alpha, envelope)
        var perturbed_alpha: float = M.atan2_(0.5, 1.0)
        var perturbed_weight: float = Aero.stall_weight(perturbed_alpha, envelope)
        report["branch_probe"] = {
            "baseline_alpha": base_alpha, "perturbed_alpha": perturbed_alpha, "threshold": threshold,
            "baseline_alpha_bits": _f64_bits(base_alpha), "perturbed_alpha_bits": _f64_bits(perturbed_alpha),
            "threshold_bits": _f64_bits(threshold),
            "baseline_weight": base_weight, "perturbed_weight": perturbed_weight,
            "baseline_full_stall": base_weight == 1.0, "perturbed_full_stall": perturbed_weight == 1.0,
        }
    session.free()
    var result_path: String = OS.get_environment("OPENRC_H7_RESULT")
    if result_path.is_empty():
        printerr("OPENRC_H7_RESULT is required")
        quit(1)
        return
    var result_file: FileAccess = FileAccess.open(result_path, FileAccess.WRITE)
    if result_file == null:
        printerr("cannot open H7 result: %s" % result_path)
        quit(1)
        return
    result_file.store_string(JSON.stringify(report, "\\t"))
    result_file.close()
    quit(0)
'''


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"expected one {label} anchor, found {count}")
    return source.replace(old, new, 1)


def instrument_branches(project: Path) -> None:
    aero_path = project / "physics" / "aero.gd"
    aero = aero_path.read_text(encoding="utf-8")
    aero = replace_once(
        aero,
        "const WING_STATIONS_PER_SIDE := 3\n",
        "const WING_STATIONS_PER_SIDE := 3\nstatic var h7_branch_tape: Array[int] = []\n",
        "aero branch tape declaration",
    )
    aero = replace_once(
        aero,
        "if blend == 1.0:\n\t\treturn blend\n",
        "if blend == 1.0:\n\t\th7_branch_tape.append(10)\n\t\treturn blend\n\th7_branch_tape.append(11)\n",
        "initial local-flow saturation branch",
    )
    aero = replace_once(
        aero,
        "\t\tif blend == 1.0:\n\t\t\treturn blend\n",
        "\t\tif blend == 1.0:\n\t\t\th7_branch_tape.append(12)\n\t\t\treturn blend\n\t\th7_branch_tape.append(13)\n",
        "wing-strip saturation branch",
    )
    aero = replace_once(
        aero,
        "\tif blend == 0.0:\n\t\treturn _global_loads(s, air, d, model, rho, downwash_cl)\n",
        "\tif blend == 0.0:\n\t\th7_branch_tape.append(20)\n\t\treturn _global_loads(s, air, d, model, rho, downwash_cl)\n\th7_branch_tape.append(21)\n",
        "global-aero branch",
    )
    aero = replace_once(
        aero,
        "\tif blend == 1.0:\n\t\treturn local\n",
        "\tif blend == 1.0:\n\t\th7_branch_tape.append(22)\n\t\treturn local\n\th7_branch_tape.append(23)\n",
        "local-aero branch",
    )
    aero_path.write_text(aero, encoding="utf-8")

    ground_path = project / "physics" / "ground_contact.gd"
    ground = ground_path.read_text(encoding="utf-8")
    ground = replace_once(
        ground,
        "extends RefCounted\n",
        "extends RefCounted\n\nstatic var h7_branch_tape: Array[int] = []\n",
        "ground branch tape declaration",
    )
    ground = replace_once(
        ground,
        "\tif gear.is_empty() or -s[RB.POS + 2] > gear.reach:\n\t\treturn PackedFloat64Array()\n",
        "\tif gear.is_empty() or -s[RB.POS + 2] > gear.reach:\n\t\th7_branch_tape.append(30)\n\t\treturn PackedFloat64Array()\n\th7_branch_tape.append(31)\n",
        "gear reach branch",
    )
    ground = replace_once(
        ground,
        "\t\tif compression <= 0.0:\n\t\t\tcontinue\n",
        "\t\tif compression <= 0.0:\n\t\t\th7_branch_tape.append(32)\n\t\t\tcontinue\n\t\th7_branch_tape.append(33)\n",
        "wheel compression branch",
    )
    ground = replace_once(
        ground,
        "\t\tif f_up <= 0.0:\n\t\t\tcontinue # a damper never pulls the wheel into the ground\n",
        "\t\tif f_up <= 0.0:\n\t\t\th7_branch_tape.append(34)\n\t\t\tcontinue # a damper never pulls the wheel into the ground\n\t\th7_branch_tape.append(35)\n",
        "normal-load branch",
    )
    ground_path.write_text(ground, encoding="utf-8")

    prop_path = project / "physics" / "propulsion.gd"
    prop = prop_path.read_text(encoding="utf-8")
    prop = replace_once(
        prop,
        "extends RefCounted\n",
        "extends RefCounted\n\nstatic var h7_branch_tape: Array[int] = []\n",
        "propulsion branch tape declaration",
    )
    prop = replace_once(
        prop,
        "\tif Turbine.is_turbine(prop): # AV-05\n\t\treturn Turbine.loads(v_air, rpm, prop, rho)\n\tif rpm < STOPPED_RPM:\n\t\treturn PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])\n",
        "\tif Turbine.is_turbine(prop): # AV-05\n\t\th7_branch_tape.append(40)\n\t\treturn Turbine.loads(v_air, rpm, prop, rho)\n\th7_branch_tape.append(41)\n\tif rpm < STOPPED_RPM:\n\t\th7_branch_tape.append(42)\n\t\treturn PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])\n\th7_branch_tape.append(43)\n",
        "propulsion type/stopped branches",
    )
    prop_path.write_text(prop, encoding="utf-8")

    # Reset instrumentation after trim and initial-load setup, immediately before the golden's ticks.
    golden_path = project / "tests" / "golden_flights.gd"
    golden = golden_path.read_text(encoding="utf-8")
    golden = replace_once(
        golden,
        "\tsession.reset()\n\tvar sim: Node = session.sim\n",
        "\tsession.reset()\n\tAero.h7_branch_tape.clear()\n\tGround.h7_branch_tape.clear()\n\tPropulsion.h7_branch_tape.clear()\n\tvar sim: Node = session.sim\n",
        "golden replay instrumentation reset",
    )
    golden = replace_once(
        golden,
        "const RB := preload(\"res://physics/rigid_body.gd\")\n",
        "const RB := preload(\"res://physics/rigid_body.gd\")\nconst Aero := preload(\"res://physics/aero.gd\")\nconst Ground := preload(\"res://physics/ground_contact.gd\")\nconst Propulsion := preload(\"res://physics/propulsion.gd\")\n",
        "golden instrumentation imports",
    )
    golden_path.write_text(golden, encoding="utf-8")

    (project / "tests" / "h7_probe.gd").write_text(PROBE, encoding="utf-8")


def perturb_math3d(project: Path) -> None:
    path = project / "physics" / "math3d.gd"
    source = path.read_text(encoding="utf-8")
    source = replace_once(source, "\treturn sin(a)\n", "\treturn _h7_next_up(sin(a))\n", "sin perturbation")
    source = replace_once(source, "\treturn atan2(y, x)\n", "\treturn _h7_next_up(atan2(y, x))\n", "atan2 perturbation")
    source += '''

static func _h7_next_up(value: float) -> float:
	if value != value or value == INF:
		return value
	var bytes := PackedByteArray()
	bytes.resize(8)
	if value == 0.0:
		bytes.encode_u64(0, 1)
	else:
		bytes.encode_double(0, value)
		var bits: int = bytes.decode_u64(0)
		bits += -1 if value < 0.0 else 1
		bytes.encode_u64(0, bits)
	return bytes.decode_double(0)
'''
    path.write_text(source, encoding="utf-8")


def restore_direct_builtins(project: Path) -> None:
    wrappers = {
        "sin_": "sin", "cos_": "cos", "tan_": "tan", "asin_": "asin", "acos_": "acos",
        "atan_": "atan", "atan2_": "atan2", "sqrt_": "sqrt", "pow_": "pow", "log_": "log",
        "exp_": "exp", "sinh_": "sinh", "cosh_": "cosh", "tanh_": "tanh", "asinh_": "asinh",
        "acosh_": "acosh", "atanh_": "atanh",
    }
    pattern = re.compile(r"(?<![\w.])M\.([A-Za-z0-9_]+)(?=\s*\()")
    for folder in (project / "physics", project / "sim"):
        for path in folder.rglob("*.gd"):
            if path.name == "math3d.gd":
                continue
            source = path.read_text(encoding="utf-8")
            source = pattern.sub(lambda match: wrappers.get(match.group(1), match.group(0)), source)
            path.write_text(source, encoding="utf-8")


def mutate_branch(project: Path) -> None:
    path = project / "physics" / "aero.gd"
    source = path.read_text(encoding="utf-8")
    source = replace_once(
        source,
        "\tif blend == 0.0:\n\t\th7_branch_tape.append(20)\n",
        "\tif blend < 0.0:\n\t\th7_branch_tape.append(20)\n",
        "controlled global-aero branch mutation",
    )
    path.write_text(source, encoding="utf-8")


def make_copy(source: Path, destination: Path, mutation: str) -> None:
    shutil.copytree(source, destination, ignore=IGNORED)
    instrument_branches(destination)
    if mutation == "ulp":
        perturb_math3d(destination)
    elif mutation == "branch":
        mutate_branch(destination)
    elif mutation == "direct":
        restore_direct_builtins(destination)


def run_probe(project: Path, godot: str, result_path: Path, baseline_alpha: float | None = None,
              branch_threshold: float | None = None) -> dict:
    environment = os.environ.copy()
    environment["OPENRC_H7_RESULT"] = str(result_path)
    if baseline_alpha is not None and branch_threshold is not None:
        environment["OPENRC_H7_BASELINE_ATAN2"] = repr(baseline_alpha)
        environment["OPENRC_H7_BRANCH_THRESHOLD"] = repr(branch_threshold)
    command = [godot, "--headless", "--path", str(project), "--audio-driver", "Dummy", "--script", "res://tests/h7_probe.gd"]
    run = subprocess.run(command, text=True, capture_output=True, env=environment, check=False, timeout=120)
    output = run.stdout + run.stderr
    if run.returncode != 0 or "SCRIPT ERROR:" in output or "Parse Error:" in output or not result_path.is_file():
        raise RuntimeError(f"H7 Godot probe failed ({run.returncode}):\n{output[-6000:]}")
    return json.loads(result_path.read_text(encoding="utf-8"))


def _max_scaled_error(record: dict) -> tuple[float, str]:
    worst = record["worst"]
    worst_ratio = 0.0
    worst_name = ""
    for name in ("pos", "vel", "att", "rate"):
        tolerance = record["tolerances"][name]
        ratio = float(worst[name]) / (float(tolerance) / 1000.0)
        if ratio > worst_ratio:
            worst_ratio = ratio
            worst_name = name
    return worst_ratio, worst_name


def check_variant(name: str, report: dict) -> None:
    for golden_name, result in report["goldens"].items():
        if not result.get("ok", False):
            raise AssertionError(f"{name} golden {golden_name} replay failed: {result.get('message')}")
        ratio, component = _max_scaled_error({"worst": result["worst"], "tolerances": report["tolerances"]})
        if ratio >= 1.0:
            raise AssertionError(f"{name} golden {golden_name} {component} error reached tolerance/1000: {ratio:.6g}")


def main() -> int:
    godot = os.environ.get("OPENRC_TEST_GODOT", "")
    if not godot:
        raise SystemExit("OPENRC_TEST_GODOT must name the repository-pinned Godot binary")
    with tempfile.TemporaryDirectory(prefix="openrc-h7-") as temporary:
        root = Path(temporary)
        variants: dict[str, dict] = {}
        for name, mutation in (("baseline", "none"), ("direct_builtin", "direct"),
                               ("ulp", "ulp"), ("branch_mutation", "branch")):
            project = root / name
            make_copy(APP_ROOT, project, mutation)
            result_path = root / f"{name}.json"
            variants[name] = run_probe(project, godot, result_path)

        baseline = variants["baseline"]
        direct_builtin = variants["direct_builtin"]
        perturbed = variants["ulp"]
        check_variant("baseline", baseline)
        check_variant("direct-built-in comparison", direct_builtin)
        if baseline["sin_builtin_bits"] != baseline["sin_wrapper_bits"] or baseline["atan2_builtin_bits"] != baseline["atan2_wrapper_bits"]:
            raise AssertionError("default math3d wrappers differ from the same built-ins")
        for golden_name in baseline["goldens"]:
            if baseline["goldens"][golden_name]["trajectory_sha256"] != direct_builtin["goldens"][golden_name]["trajectory_sha256"]:
                raise AssertionError(f"routing wrappers changed the same-machine state/aux/mode fingerprint: {golden_name}")
        if perturbed["sin_wrapper_bits"] != baseline["sin_wrapper_bits"] + 1:
            raise AssertionError("sin_ mutation was not exactly one adjacent float up")
        if perturbed["atan2_wrapper_bits"] != baseline["atan2_wrapper_bits"] + 1:
            raise AssertionError("atan2_ mutation was not exactly one adjacent float up")

        baseline_alpha = struct.unpack("<d", struct.pack("<Q", baseline["atan2_wrapper_bits"]))[0]
        threshold = struct.unpack("<d", struct.pack("<Q", baseline["atan2_wrapper_bits"] + 1))[0]
        perturbed = run_probe(root / "ulp", godot, root / "ulp_fixture.json",
                              baseline_alpha, threshold)
        check_variant("one-ulp", perturbed)
        for golden_name in baseline["goldens"]:
            before = baseline["goldens"][golden_name]["branch_signature"]
            after = perturbed["goldens"][golden_name]["branch_signature"]
            if before != after:
                raise AssertionError(f"one-ulp math changed the actual golden branch signature: {golden_name}")

        fixture = perturbed.get("branch_probe", {})
        if not (fixture.get("baseline_alpha_bits") + 1 == fixture.get("threshold_bits") == fixture.get("perturbed_alpha_bits")
                and not fixture.get("baseline_full_stall") and fixture.get("perturbed_full_stall")):
            raise AssertionError(f"adjacent-float stall threshold fixture did not cross its branch: {fixture}")

        changed = []
        branch_report = variants["branch_mutation"]
        check_variant("controlled branch mutation", branch_report)
        for golden_name in baseline["goldens"]:
            signature = baseline["goldens"][golden_name]["branch_signature"]
            if not signature["aero"] or not signature["ground"] or not signature["propulsion"]:
                raise AssertionError(f"branch tape missed a physics subsystem during golden replay: {golden_name}")
            if baseline["goldens"][golden_name]["branch_signature"] != branch_report["goldens"][golden_name]["branch_signature"]:
                changed.append(golden_name)
        if not changed:
            raise AssertionError("controlled branch-path mutation escaped the actual golden branch signatures")
        max_ratio = max(_max_scaled_error({"worst": record["worst"], "tolerances": branch_report["tolerances"]})[0]
                        for record in branch_report["goldens"].values())
        if max_ratio >= 1.0:
            raise AssertionError("controlled branch fixture did not isolate branch divergence from state error")

        max_ratio = max(_max_scaled_error({"worst": record["worst"], "tolerances": perturbed["tolerances"]})[0]
                        for record in perturbed["goldens"].values())
        ulp_ratio_by_golden = {
            golden_name: _max_scaled_error({"worst": result["worst"], "tolerances": perturbed["tolerances"]})[0]
            for golden_name, result in perturbed["goldens"].items()
        }
        mutation_ratio_by_golden = {
            golden_name: _max_scaled_error({"worst": result["worst"], "tolerances": branch_report["tolerances"]})[0]
            for golden_name, result in branch_report["goldens"].items()
        }
        baseline_branch_hashes = {
            golden_name: hashlib.sha256(json.dumps(result["branch_signature"], separators=(",", ":")).encode()).hexdigest()
            for golden_name, result in baseline["goldens"].items()
        }
        mutation_branch_hashes = {
            golden_name: hashlib.sha256(json.dumps(result["branch_signature"], separators=(",", ":")).encode()).hexdigest()
            for golden_name, result in branch_report["goldens"].items()
        }
        ulp_branch_hashes = {
            golden_name: hashlib.sha256(json.dumps(result["branch_signature"], separators=(",", ":")).encode()).hexdigest()
            for golden_name, result in perturbed["goldens"].items()
        }
        evidence = {
            "format": "openrc-numerics-sensitivity v1",
            "host": {"platform": platform.platform(), "machine": platform.machine()},
            "godot": subprocess.run([godot, "--version"], text=True, capture_output=True, check=True).stdout.strip(),
            "same_machine_wrapper_fingerprints": {
                name: baseline["goldens"][name]["trajectory_sha256"] for name in baseline["goldens"]
            },
            "same_machine_direct_builtin_fingerprints": {
                name: direct_builtin["goldens"][name]["trajectory_sha256"] for name in direct_builtin["goldens"]
            },
            "same_machine_fingerprints_match": True,
            "one_ulp": {
                "perturbations": ["sin_ next-float-up", "atan2_ next-float-up"],
                "max_error_over_tolerance_div_1000": max_ratio,
                "per_golden_error_ratios": ulp_ratio_by_golden,
                "branch_signatures_match": True,
                "branch_signature_sha256": ulp_branch_hashes,
            },
            "adjacent_float_stall_branch_fixture": fixture,
            "controlled_golden_branch_mutation": {
                "mutation": "aero blend == 0.0 -> blend < 0.0",
                "goldens_with_branch_signature_divergence": changed,
                "baseline_branch_signature_sha256": baseline_branch_hashes,
                "mutated_branch_signature_sha256": mutation_branch_hashes,
                "max_error_over_tolerance_div_1000": max(mutation_ratio_by_golden.values()),
                "per_golden_error_ratios": mutation_ratio_by_golden,
            },
        }
        evidence_path = os.environ.get("OPENRC_H7_REPORT", "")
        if evidence_path:
            Path(evidence_path).write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        print("H7: exact next-float-up sin_/atan2_ perturbations replay all four air goldens")
        print("H6: same-machine SHA-256 trajectories match isolated direct-built-in call-site copies")
        print(f"maximum component error / (golden tolerance / 1000) = {max_ratio:.6g}")
        print(f"adjacent-float full-stall branch fixture crossed: {fixture['baseline_weight']:.9g} -> {fixture['perturbed_weight']:.9g}")
        print(f"controlled branch-path mutation detected in actual golden replay(s): {', '.join(changed)}")
        print(f"mutation state error stayed below tolerance/1000 (worst ratio {max(_max_scaled_error({'worst': record['worst'], 'tolerances': branch_report['tolerances']})[0] for record in branch_report['goldens'].values()):.6g})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
