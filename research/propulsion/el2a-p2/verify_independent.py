#!/usr/bin/env python3
"""Run the pinned independent EL1d and EL2a scalar checks on one candidate app."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import platform
import re
import subprocess
import sys
from importlib.metadata import version
from pathlib import Path
from types import ModuleType


PINNED = {"numpy": "1.26.4", "scipy": "1.11.4"}
GODOT_VERSION = "4.7.2.stable.official.ed1daf0bf"
ROOT = Path(__file__).resolve().parents[3]
ERROR_LINE = re.compile(r"^(?:SCRIPT |SHADER )?ERROR:", re.MULTILINE)
PROBES = (
    {
        "name": "el1d_scalar",
        "module_path": ROOT / "research/propulsion/el1/verify_scalar.py",
        "prefix": "EL1D_SCALAR_JSON:",
        "probe": ROOT / "research/propulsion/el1/scalar_probe.gd",
    },
    {
        "name": "el2a_battery",
        "module_path": ROOT / "research/propulsion/el2/verify_battery.py",
        "prefix": "EL2_BATTERY_JSON:",
        "probe": ROOT / "research/propulsion/el2/scalar_probe.gd",
    },
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_verifier(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    require(spec is not None and spec.loader is not None, f"could not load verifier: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def pinned_versions() -> dict[str, str]:
    observed = {name: version(name) for name in PINNED}
    require(observed == PINNED,
            f"use the pinned research environment {PINNED}; observed {observed}")
    return observed


def run_version(godot_path: Path, timeout: float) -> dict:
    command = [str(godot_path), "--version"]
    process = subprocess.run(command, text=True, capture_output=True,
                             encoding="utf-8", errors="replace", timeout=timeout)
    combined = process.stdout + process.stderr
    require(process.returncode in (0, 1),
            f"Godot --version exited {process.returncode}:\n{combined}")
    require(process.stdout.strip() == GODOT_VERSION and not process.stderr.strip(),
            "Godot version output did not exactly match the pinned official build: "
            f"{combined!r}")
    require(not ERROR_LINE.search(combined), f"Godot --version logged an error:\n{combined}")
    # Godot's Linux 4.7.2 binary may use either 0 or 1 for --version. A nonzero
    # result is accepted only for the exact official version string above.
    return {
        "command": command,
        "returncode": process.returncode,
        "stdout": process.stdout,
        "stderr": process.stderr,
        "version": process.stdout.strip(),
        "nonzero_exit_allowed_for_exact_version_only": process.returncode == 1,
    }


def run_probe(godot_path: Path, app_path: Path, probe_path: Path,
              prefix: str, timeout: float) -> dict:
    command = [str(godot_path), "--headless", "--path", str(app_path),
               "--audio-driver", "Dummy", "--script", str(probe_path)]
    process = subprocess.run(command, text=True, capture_output=True,
                             encoding="utf-8", errors="replace", timeout=timeout)
    combined = process.stdout + process.stderr
    require(process.returncode == 0,
            f"{probe_path.name} exited {process.returncode}:\n{combined}")
    require(not ERROR_LINE.search(combined),
            f"{probe_path.name} logged a Godot error:\n{combined}")
    records = [line[len(prefix):] for line in combined.splitlines()
               if line.startswith(prefix)]
    require(len(records) == 1,
            f"expected one {prefix.rstrip(':')} record, got {len(records)}")
    try:
        raw = json.loads(records[0])
    except json.JSONDecodeError as error:
        raise RuntimeError(f"invalid JSON from {probe_path.name}: {error}") from error
    require(isinstance(raw, dict), f"{probe_path.name} result must be a JSON object")
    return {
        "command": command,
        "returncode": process.returncode,
        "stdout": process.stdout,
        "stderr": process.stderr,
        "raw": raw,
    }


def checks_for_el1(raw: dict, module: ModuleType) -> tuple[dict, dict]:
    reference = module.independent_reference()
    checks = module.check_probe(raw, reference)
    return reference, checks


def checks_for_el2(raw: dict, module: ModuleType) -> tuple[dict, dict]:
    module.fixture_matches(raw["fixture"])
    auxiliary_reference = module.aux_event_reference()
    smooth_reference = module.smooth_reference()
    auxiliary_checks = module.check_auxiliary_only(
        raw["auxiliary_only"], auxiliary_reference)
    smooth_checks = module.check_smooth(raw["smooth"], smooth_reference)
    return (
        {"auxiliary_only": auxiliary_reference, "smooth": smooth_reference},
        {"auxiliary_only": auxiliary_checks, "smooth": smooth_checks},
    )


def code_hashes(app_path: Path) -> dict:
    el1 = load_verifier(PROBES[0]["module_path"], "openrc_el1_scalar_hash_manifest")
    el2 = load_verifier(PROBES[1]["module_path"], "openrc_el2_battery_hash_manifest")
    production_paths = set(el1.PRODUCTION_PATHS) | set(el2.PRODUCTION_PATHS)
    production_paths.update({
        "physics/electric_battery_step.gd",
        "physics/electric_stop.gd",
        "physics/event_bracket.gd",
    })
    source_hashes = {}
    for relative in sorted(production_paths):
        path = app_path / relative
        require(path.is_file(), f"required production source is missing: {path}")
        source_hashes[relative] = sha256(path)

    probe_hashes = {
        str(spec["probe"].relative_to(ROOT).as_posix()): sha256(spec["probe"])
        for spec in PROBES
    }
    verifier_paths = [
        PROBES[0]["module_path"],
        PROBES[1]["module_path"],
        Path(__file__).resolve(),
    ]
    verifier_hashes = {
        str(path.relative_to(ROOT).as_posix()): sha256(path)
        for path in verifier_paths
    }
    requirements_path = ROOT / "research/propulsion/el1a-r2/requirements.txt"
    return {
        "production_sources_sha256": source_hashes,
        "probes_sha256": probe_hashes,
        "verifiers_sha256": verifier_hashes,
        "requirements_sha256": sha256(requirements_path),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    godot_path = args.godot.resolve()
    app_path = args.app.resolve()
    output_path = args.out.resolve()
    require(godot_path.is_file(), f"Godot executable not found: {godot_path}")
    require((app_path / "project.godot").is_file(), f"Godot app not found: {app_path}")
    versions = pinned_versions()
    godot = run_version(godot_path, args.timeout)

    loaded = {
        "el1d_scalar": load_verifier(PROBES[0]["module_path"], "openrc_el1_scalar_check"),
        "el2a_battery": load_verifier(PROBES[1]["module_path"], "openrc_el2_battery_check"),
    }
    runs = {}
    references = {}
    checks = {}
    for specification in PROBES:
        name = specification["name"]
        probe_path = specification["probe"]
        require(probe_path.is_file(), f"probe not found: {probe_path}")
        runs[name] = run_probe(godot_path, app_path, probe_path,
                               specification["prefix"], args.timeout)
        raw = runs[name]["raw"]
        if name == "el1d_scalar":
            references[name], checks[name] = checks_for_el1(raw, loaded[name])
        else:
            references[name], checks[name] = checks_for_el2(raw, loaded[name])

    manifest = code_hashes(app_path)
    evidence = {
        "format": "openrc-el2a-p2-independent-scalar-evidence-v1",
        "status": "independent synthetic scalar checks; no aircraft, motor, or battery calibration",
        "ok": True,
        "python": platform.python_version(),
        "python_dependencies": versions,
        "godot": godot,
        "app_path": str(app_path),
        "independent_references": references,
        "checks": checks,
        "probe_runs": runs,
        "hashes": manifest,
        "limitations": [
            "EL1d and EL2a expected values and acceptance tolerances are computed by the existing pinned research verifiers.",
            "The fixtures are synthetic scalar motor, rotor, and battery cases; they do not establish aircraft or hardware calibration.",
            "The EL2a auxiliary-only reference is an exact constant-current final-tick case; the smooth reference is an independent SciPy DOP853 integration.",
        ],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_name(output_path.name + ".tmp")
    temporary_path.write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n",
                              encoding="utf-8")
    temporary_path.replace(output_path)
    print(json.dumps({
        "ok": True,
        "output": str(output_path),
        "godot": godot["version"],
        "probes": {name: {"returncode": run["returncode"], "checks": "passed"}
                   for name, run in runs.items()},
        "production_source_hashes": len(manifest["production_sources_sha256"]),
    }))


if __name__ == "__main__":
    main()
