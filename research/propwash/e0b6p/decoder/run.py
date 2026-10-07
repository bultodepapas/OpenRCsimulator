#!/usr/bin/env python3
"""Verify and measure the E0b6p required-field decoding experiment in a disposable app."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import re
import shutil
import math
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SPEC = importlib.util.spec_from_file_location("native_runner", HERE.parent / "native/run.py")
native = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(native)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace(source: str, old: str, new: str) -> str:
    if source.count(old) != 1:
        raise RuntimeError(f"Expected one staging anchor: {old!r}")
    return source.replace(old, new, 1)


def summarize_profile(profile: dict) -> dict:
    if profile.get("format") != "openrc-e0b6p-requiredfield-profile v1" or profile.get("status") != "pass" or profile.get("failures") != 0:
        raise RuntimeError("Paired profile failed or has an unexpected format")
    summaries = {}
    regimes = ["forward", "stall", "static", "spin", "reverse_fade", "reverse_off"]
    for key, count, pairs in (("direct_rows", 6, 24), ("flight_rows", 12, 15)):
        rows = profile.get(key, [])
        expected = regimes if key == "direct_rows" else [(r, s) for r in regimes for s in (0.0, 0.4)]
        roster = [r.get("regime") for r in rows] if key == "direct_rows" else [(r.get("regime"), r.get("swirl_factor")) for r in rows]
        if len(rows) != count or roster != expected:
            raise RuntimeError(f"Unexpected {key} roster")
        result = []
        for row in rows:
            baseline = row["baseline_samples_us"]
            candidate = row["candidate_samples_us"]
            if len(baseline) != pairs or len(candidate) != pairs or any(
                isinstance(v, bool) or not isinstance(v, (float, int)) or not math.isfinite(v) or v <= 0
                for v in baseline + candidate
            ):
                raise RuntimeError("Malformed paired timing samples")
            deltas = [b - c for b, c in zip(baseline, candidate, strict=True)]
            result.append({"regime": row["regime"], "swirl_factor": row.get("swirl_factor", 0.4),
                           "baseline_median_us": statistics.median(baseline),
                           "candidate_median_us": statistics.median(candidate),
                           "paired_saving_median_us": statistics.median(deltas),
                           "candidate_faster_pairs": sum(d > 0 for d in deltas),
                           "pairs": pairs, "paired_savings_us": deltas})
        summaries[key] = result
    return summaries


def execute(godot: str, app: Path, script: Path, output: Path, report: bool = True) -> None:
    command = [godot, "--headless", "--path", str(app), "--script", str(script)]
    # Exit code alone does not detect all GDScript parse failures.
    parsed = subprocess.run(command + ["--check-only"], capture_output=True, text=True, timeout=30)
    parse_log = parsed.stdout + parsed.stderr
    output.with_suffix(".parse.log").write_text(parse_log)
    if parsed.returncode or native.ERROR_RE.search(parse_log):
        raise RuntimeError(f"Parse preflight failed: {script}\n{parse_log}")
    if report:
        command += ["--", str(output)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    log = result.stdout + result.stderr
    output.with_suffix(".log").write_text(log)
    if result.returncode or native.ERROR_RE.search(log):
        raise RuntimeError(f"Godot failed: {script}\n{log}")
    if report and not output.is_file():
        raise RuntimeError(f"Missing report: {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "app")
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / ".tools/native-decoder/build.json")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    app = Path(tempfile.mkdtemp(prefix="work-", dir=output)) / "app"
    godot = native._resolve_godot(args.godot)
    build = json.loads(args.build.read_text())
    libraries = {key: Path(value["library"]) for key, value in build["variants"].items()}
    for key, library in libraries.items():
        if sha(library) != build["variants"][key]["library_sha256"]:
            raise RuntimeError(f"Library differs from build manifest: {key}")
    native._copy_project(args.project.resolve(), app)
    probe = native._install_probe(app, libraries["baseline"])
    candidate_name = "candidate" + libraries["candidate"].suffix
    shutil.copy2(libraries["candidate"], probe / candidate_name)
    (probe / "candidate.gdextension").write_text(
        '[configuration]\nentry_symbol = "openrc_smooth_wake_candidate_library_init"\n'
        'compatibility_minimum = "4.7"\nreloadable = false\n\n[libraries]\n'
        f'{native._platform_key()} = "res://tests/e0b6p_native/{candidate_name}"\n')
    for name in ("profile.gd", "verify_fields.gd"):
        shutil.copy2(HERE / name, probe / ("decoder_" + name))
    source_hashes = native._source_hashes(app)
    source_hashes.update({str(p.relative_to(ROOT)): sha(p) for p in HERE.iterdir()
                          if p.suffix in (".py", ".gd")})
    # Record all 297 output byte strings to compare both native versions directly.
    verifier = probe / "verify.gd"
    text = verifier.read_text()
    text = replace(text, "var _checks: int = 0", "var _native_samples: Array[Dictionary] = []\nvar _checks: int = 0")
    text = replace(text, "\t_compared += 1", '\t_native_samples.append({label = label, bytes = actual.to_byte_array().hex_encode()})\n\t_compared += 1')
    text = replace(text, '\t\t"coverage": _coverage,', '\t\t"native_samples": _native_samples,\n\t\t"coverage": _coverage,')
    verifier.write_text(text)
    baseline_adapter = (probe / "adapter.gd").read_text()
    candidate_adapter = baseline_adapter.replace('res://tests/e0b6p_native/smooth_wake.gdextension',
                                                'res://tests/e0b6p_native/candidate.gdextension')
    candidate_adapter = candidate_adapter.replace('"OpenRCSmoothWake"', '"OpenRCSmoothWakeCandidate"')
    evidence = {"format": "openrc-e0b6p-decoder-evidence v1", "status": "running",
                "build": build, "source_sha256": source_hashes, "host": platform.platform(),
                "godot": godot, "staged_app": str(app), "reports": {}}
    try:
        for label, adapter in (("baseline", baseline_adapter), ("candidate", candidate_adapter)):
            (probe / "adapter.gd").write_text(adapter)
            for name, script in (("verification", verifier), ("fields", probe / "decoder_verify_fields.gd")):
                path = output / f"{label}-{name}.json"
                execute(godot, app, script, path)
                value = native._read_json(path)
                if value.get("failures" if name == "verification" else "failed") != 0:
                    raise RuntimeError(f"Failed {label} {name}: {value}")
                if name == "fields" and (value.get("required_field_count") != 34 or value.get("cases", 0) < 160):
                    raise RuntimeError("Incomplete decoder field coverage")
                if name == "verification" and (value.get("compared_loads") != 297 or value.get("random_cases") != 256):
                    raise RuntimeError("Incomplete native verifier")
                evidence["reports"][f"{label}-{name}"] = path.name
        old = native._read_json(output / "baseline-verification.json")["native_samples"]
        new = native._read_json(output / "candidate-verification.json")["native_samples"]
        if len(old) != 297 or old != new or any(not re.fullmatch(r"[0-9a-f]{96}", row["bytes"]) for row in new):
            raise RuntimeError("Native output byte comparison failed")
        evidence["exact_native_load_comparisons"] = len(new)
        accuracy = app / "tests/test_swirl_accuracy.gd"
        accuracy.write_text(replace(accuracy.read_text(),
            'preload("res://physics/slipstream.gd")', 'preload("res://tests/e0b6p_native/adapter.gd")'))
        execute(godot, app, accuracy, output / "accuracy.json", report=False)
        if "41 checks, 0 failed" not in (output / "accuracy.log").read_text():
            raise RuntimeError("Dense accuracy checks incomplete")
        evidence["dense_accuracy_checks"] = 41
        (probe / "adapter.gd").write_text(baseline_adapter)
        native._replace_dynamics_slipstream(app, True)
        execute(godot, app, probe / "decoder_profile.gd", output / "profile.json")
        profile = native._read_json(output / "profile.json")
        evidence["timing_summary"] = summarize_profile(profile)
        evidence["reports"]["profile"] = "profile.json"
        evidence["status"] = "pass"
    except Exception as error:
        evidence["status"] = "fail"
        evidence["error"] = str(error)
        raise
    finally:
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n")
    print(f"Decoder experiment passed: {output / 'evidence.json'}")


if __name__ == "__main__":
    main()
