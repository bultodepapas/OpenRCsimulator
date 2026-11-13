#!/usr/bin/env python3
"""Run the NK-3 oracle headless against the reference GDScript in app/ and print the evidence tables.

Build first with build.py (and build.py --mutant for the negative control). The oracle runs in the pinned Godot
editor through tools/godot/run_checked.py with `--path app`, loads the extension from tmp/native-kernel/ at run
time and writes its JSON there. `--mutant` runs the deliberately mutated library, which must FAIL the oracle.
"""

from __future__ import annotations

import argparse
import configparser
import hashlib
import importlib.util
import json
import os
import platform
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
# Platform builders share the oracle protocol and keep their output roots independent.
TOOL_ROOT = Path(os.environ.get("OPENRC_NK_TOOL_ROOT", ROOT / "tmp/native-kernel"))


def host_platform_key(system: str | None = None, architecture: str | None = None) -> str:
    """Select the real process slice; never treat Darwin or an unknown CPU as Linux."""
    system = sys.platform if system is None else system
    architecture = platform.machine().lower() if architecture is None else architecture.lower()
    if system == "darwin" and architecture in {"arm64", "aarch64"}:
        return "macos.arm64"
    if architecture in {"amd64", "x86_64"}:
        if system == "win32":
            return "windows.x86_64"
        if system.startswith("linux"):
            return "linux.x86_64"
    raise ValueError(f"No qualified native oracle target for {system}/{architecture}")


def default_godot(platform_key: str) -> Path:
    paths = {
        "windows.x86_64": ".tools/Godot_v4.8-beta2_win64_console.exe",
        "linux.x86_64": ".tools/Godot_v4.8-beta2_linux.x86_64",
        "macos.arm64": ".tools/Godot_v4.8-beta2_macos.arm64/Godot.app/Contents/MacOS/Godot",
    }
    return ROOT / paths[platform_key]


try:
    PLATFORM_KEY = host_platform_key()
except ValueError:
    PLATFORM_KEY = ""  # Reading existing evidence is still useful on an unsupported host.
GODOT = default_godot(PLATFORM_KEY) if PLATFORM_KEY else ROOT / ".tools/no-native-oracle-engine"
HARNESS_OPTIONS = {
    "oracle.gd": set(), "stage_oracle.gd": set(),
    "propeller_oracle.gd": set(),
    "weather_oracle.gd": set(), "electric_oracle.gd": set(),
    "wake_oracle.gd": set(), "weather_stage_oracle.gd": {"ticks", "include-spatial"}, "glow_oracle.gd": set(),
    "wake_spatial_oracle.gd": set(),
    "helicopter_oracle.gd": set(), "helicopter_stage_oracle.gd": {"ticks"}, "liquid_oracle.gd": set(), "gear_oracle.gd": set(),
    "electric_stage_oracle.gd": {"ticks"}, "liquid_stage_oracle.gd": {"ticks"}, "glow_stage_oracle.gd": {"ticks"},
    "prescribed_stage_oracle.gd": {"ticks"},
    "legacy_ground_oracle.gd": {"ticks"},
    "trajectory.gd": {"ticks", "pairs", "warmup", "samples", "timing-cases", "skip-timing", "only", "repeats"},
    "fleet.gd": {"warmup", "samples", "aircraft", "weather", "soft-hull", "vehicle"},
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reference_source_paths() -> list[str]:
    """Use the current build roster, not a narrower oracle-specific list."""
    spec = importlib.util.spec_from_file_location("openrc_native_kernel_build_identity", HERE / "build.py")
    if spec is None or spec.loader is None:
        raise ValueError("Cannot load native build source roster")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    paths = module.REFERENCE_SOURCES
    if not isinstance(paths, list) or not paths or any(not isinstance(name, str) or not name.startswith("app/")
                                                      for name in paths) or len(set(paths)) != len(paths):
        raise ValueError("Invalid or repeated native build source paths")
    return paths


def checked_run_matches(report: dict, mutant: bool) -> bool:
    """An expected oracle failure is not permission to ignore engine errors or incomplete capture."""
    return (report.get("complete") is True and report.get("counts", {}).get("error") == 0
            and report.get("missing_required_text") == []
            and report.get("process_exit") == (1 if mutant else 0)
            and report.get("reason") == ("process_exit" if mutant else "passed")
            and (mutant or report.get("ok") is True))


def selected_binary(descriptor: Path, project: Path | None = None) -> Path:
    config = configparser.ConfigParser(interpolation=None)
    config.read(descriptor)
    name = config["libraries"][PLATFORM_KEY].strip('"')
    app = ROOT / "app" if project is None else project
    return ((app / name.removeprefix("res://")) if name.startswith("res://")
            else descriptor.parent / name).resolve()


def macos_engine_matches(receipt: dict, executable_sha256: str) -> bool:
    """A research Mac receipt binds the exact host, not only its version label."""
    engine = receipt.get("engine")
    return (receipt.get("platform") == "macos" and receipt.get("architecture") == "arm64"
            and isinstance(engine, dict) and engine.get("sha256") == executable_sha256
            and receipt.get("engine_sha256") == executable_sha256)


def _project_inventory(app: Path) -> list[dict]:
    entries = []
    for path in sorted(app.rglob("*")):
        relative = path.relative_to(app)
        if any(part in {".godot", ".tools", "__pycache__"} for part in relative.parts) \
                or relative.parts[0] in {"captures", "tmp"}:
            continue
        if path.is_symlink():
            raise ValueError(f"Project inventory contains a link: {relative}")
        if path.is_file():
            entries.append({"path": relative.as_posix(), "bytes": path.stat().st_size, "sha256": sha256(path)})
    entries.sort(key=lambda item: item["path"])
    return entries


def _inventory_hash(entries: list[dict]) -> str:
    return hashlib.sha256(json.dumps(entries, ensure_ascii=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


NATIVE_INSTALL_OUTPUTS = {"native/kernel/" + name for name in (
    ".gdignore", "LICENSE.godot-cpp.md", "libopenrc_native_kernel.so", "openrc_native_kernel.dll", "libopenrc_native_kernel.dylib",
    "openrc_native_kernel.gdextension", "openrc_native_kernel_windows.gdextension", "openrc_native_kernel_macos.gdextension",
    "build-receipt.json", "build-receipt-windows.json", "build-receipt-macos.json", "package.json", "package-macos.json")}


def _prepared_source_inventory(canonical: list[dict], source: dict) -> list[dict]:
    """Installation outputs may advance in the canonical app; the executed copy stays frozen."""
    if "native_kernel_inventory" not in source:
        return canonical  # Historical receipts retain their original, stricter comparison.
    retained = source["native_kernel_inventory"]
    if not isinstance(retained, list) or len(retained) > 4096:
        raise ValueError("Malformed prepared native-kernel inventory")
    paths = []
    for item in retained:
        if (not isinstance(item, dict) or set(item) != {"path", "bytes", "sha256"}
                or not isinstance(item["path"], str) or not item["path"].startswith("native/kernel/")
                or "\\" in item["path"] or any(part in {"", ".", ".."} for part in item["path"].split("/"))
                or type(item["bytes"]) is not int or item["bytes"] < 0
                or not isinstance(item["sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", item["sha256"])):
            raise ValueError("Malformed prepared native-kernel inventory entry")
        paths.append(item["path"])
    if paths != sorted(set(paths)):
        raise ValueError("Repeated or unordered prepared native-kernel inventory")
    # The original full preparation hash still proves every retained entry. No
    # target file is omitted: the prepared copy must contain exactly its original
    # native artifacts, and its complete execution inventory is checked on both sides.
    return sorted([item for item in canonical if item["path"] not in NATIVE_INSTALL_OUTPUTS]
                  + [item for item in retained if item["path"] in NATIVE_INSTALL_OUTPUTS], key=lambda item: item["path"])


def validate_project(project: Path) -> dict:
    """An isolated run may change only the existing research tool's two settings."""
    if project == (ROOT / "app").resolve():
        return {}
    receipt = json.loads((project.parent / "research-preparation.json").read_text(encoding="utf-8"))
    if not isinstance(receipt, dict) or not isinstance(receipt.get("destination"), dict):
        raise ValueError("Malformed research preparation receipt")
    destination = receipt.get("destination", {})
    name = destination.get("project_name", "")
    if (receipt.get("format") != "openrc-graphics-research-preparation v1"
            or receipt.get("complete") is not True
            or Path(destination.get("app", "")).resolve() != project
            or not re.fullmatch(r"OpenRC-Research-[0-9a-f]{32}", name)):
        raise ValueError("Project is not an identified isolated research preparation")
    original = (ROOT / "app/project.godot").read_bytes()
    name_line = b'config/name="OpenRC Simulator"'
    if original.count(name_line) != 1:
        raise ValueError("Canonical project name changed")
    expected = original.replace(name_line, f'config/name="{name}"'.encode(), 1)
    expected = expected.replace(b"lights_and_shadows/multi_bounce_occlusion/enabled=true",
                                b"lights_and_shadows/multi_bounce_occlusion/enabled=false", 1)
    actual = (project / "project.godot").read_bytes()
    if (actual != expected or sha256(project / "project.godot") != destination.get("project_sha256")
            or any((project / name).exists() for name in ("override.cfg", "project.binary"))):
        raise ValueError("Isolated project settings differ from the verified research edits")
    canonical = _project_inventory(ROOT / "app")
    source = receipt.get("source", {})
    if not isinstance(source, dict):
        raise ValueError("Malformed preparation source identity")
    canonical = _prepared_source_inventory(canonical, source)
    if _inventory_hash(canonical) != source.get("copied_app_manifest_sha256"):
        raise ValueError("Canonical app changed since isolated research preparation")
    # Importers can regenerate UID/import descriptors. Their imported outputs
    # live in .godot and remain outside this source/content comparison; all
    # executed code, fixtures, scenes, data and asset payloads must still match.
    generated = {".uid", ".import"}
    expected_entries = []
    for item in canonical:
        if Path(item["path"]).suffix in generated:
            continue
        item = dict(item)
        if item["path"] == "project.godot":
            item.update(bytes=len(expected), sha256=hashlib.sha256(expected).hexdigest())
        expected_entries.append(item)
    observed = [item for item in _project_inventory(project) if Path(item["path"]).suffix not in generated]
    if expected_entries != observed:
        raise ValueError("Isolated project content differs from its prepared canonical app")
    return {"canonical_manifest_sha256": _inventory_hash(canonical),
            "executed_project_content_sha256": _inventory_hash(observed),
            "checked_files": len(observed), "excluded_generated_suffixes": sorted(generated),
            "canonical_native_artifacts_from_preparation": "native_kernel_inventory" in source}


def project_file(path: Path, project: Path) -> Path:
    """Keep logical repository keys while hashing the files actually executed."""
    app = ROOT / "app"
    return project / path.relative_to(app) if path.is_relative_to(app) else path


def validate_options(script: str, options: list[str]) -> None:
    seen = set()
    for option in options:
        name, separator, value = option.partition("=")
        if not separator or not value or name not in HARNESS_OPTIONS[script] or name in seen:
            raise ValueError(f"invalid or repeated option for {script}: {option}")
        seen.add(name)


def render(results: dict) -> str:
    lines = ["| Component | Compared | Identical | Finite ulp (max) | ±0 | NaN bits | Class | Shape |",
             "| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |"]
    for name, c in sorted(results["components"].items()):
        lines.append(f"| {name} | {c['count']} | {c['identical']} | {c['finite_ulp']} ({c['max_ulp']}) | "
                     f"{c['zero_sign']} | {c['nan_bits']} | {c['class_mismatch']} | {c['shape']} |")
    lines += ["", "| Component call | Reference µs | Native via binding µs | Native kernel µs | × binding | × kernel |",
              "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for name, t in results["timing"].items():
        if "reference_us" not in t:
            continue
        kernel = t["native_kernel_us"]
        kernel_text = "—" if kernel is None else f"{kernel:.3f}"
        speed = "—" if kernel is None else f"{t['speedup_kernel']:.0f}"
        lines.append(f"| {name} | {t['reference_us']:.2f} | {t['native_binding_us']:.3f} | {kernel_text} | "
                     f"{t['speedup_binding']:.0f} | {speed} |")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--states", type=int, default=12000)
    parser.add_argument("--variant-states", type=int, default=1500)
    parser.add_argument("--timing-rounds", type=int, default=15)
    parser.add_argument("--seed", type=int, default=20261027)
    parser.add_argument("--timeout", type=float, default=1800)
    parser.add_argument("--mutant", action="store_true", help="run the negative-control library; expect failure")
    parser.add_argument("--godot", type=Path, default=GODOT)
    parser.add_argument("--project", type=Path, default=ROOT / "app",
                        help="canonical app or a verified isolated research preparation")
    parser.add_argument("--experimental-native-macos", action="store_true",
                        help="explicitly opt fixed-wing research sessions into qualified Mac source admission")
    parser.add_argument("--app-library", action="store_true",
                        help="use the installed res://native/kernel library (build.py --install-app) instead of tmp/")
    parser.add_argument("--render", type=Path, help="only render tables from an existing results JSON")
    parser.add_argument("--script", default="oracle.gd", choices=tuple(HARNESS_OPTIONS),
                        help="harness to run (all extend oracle.gd and print the same verdict line)")
    parser.add_argument("--option", action="append", default=[], metavar="NAME=VALUE",
                        help="extra harness option, passed as --NAME=VALUE (repeatable)")
    args = parser.parse_args()
    try:
        validate_options(args.script, args.option)
    except ValueError as error:
        parser.error(str(error))
    if args.render:
        print(render(json.loads(args.render.read_text(encoding="utf-8"))))
        return 0
    if not PLATFORM_KEY:
        parser.error("This process has no supported native oracle target")
    project = args.project.expanduser().resolve()
    try:
        project_identity_before = validate_project(project)
    except (OSError, ValueError, TypeError) as error:
        parser.error(str(error))
    variant = "_mutant" if args.mutant else ""
    descriptor = TOOL_ROOT / f"openrc_native_kernel{variant}.gdextension"
    # Each platform has a distinct manual descriptor/receipt beside the Linux installation.
    platform_name = PLATFORM_KEY.split(".", 1)[0]
    app_suffix = "" if platform_name == "linux" else "_" + platform_name
    app_descriptor = project / f"native/kernel/openrc_native_kernel{app_suffix}.gdextension"
    receipt_suffix = "" if platform_name == "linux" else "-" + platform_name
    app_receipt = project / f"native/kernel/build-receipt{receipt_suffix}.json"
    if args.app_library:
        if args.mutant:
            parser.error("--app-library never holds the mutant")
        if not app_descriptor.is_file():
            raise SystemExit("No app install; run build.py (or build_windows.py) --install-app first.")
        descriptor = f"res://native/kernel/{app_descriptor.name}"
    elif not descriptor.is_file():
        raise SystemExit(f"Missing {descriptor}; run build.py{' --mutant' if args.mutant else ''} first.")
    descriptor_file = app_descriptor if args.app_library else descriptor
    binary = selected_binary(descriptor_file, project)
    receipt_path = app_receipt if args.app_library else TOOL_ROOT / f"build-receipt{variant}.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    if args.app_library:
        receipt = receipt["platforms"][platform_name]
    binary_before = sha256(binary)
    engine_before = sha256(args.godot)
    # NK-4: on Windows the console wrapper starts the sibling GUI executable, which is the engine that runs the
    # oracle and the one the installed receipt binds; record it too.
    engine_executable = args.godot.with_name(args.godot.name.replace("_console.exe", ".exe")) \
        if args.godot.name.endswith("_console.exe") else args.godot
    engine_executable_before = sha256(engine_executable)
    if platform_name == "macos" and not macos_engine_matches(receipt, engine_executable_before):
        raise SystemExit("Mac oracle requires the exact ARM64 Godot executable bound by the build receipt.")
    if binary_before != receipt["binary_sha256"]:
        raise SystemExit("The descriptor's binary differs from its build receipt; rebuild/reinstall first.")
    paths = reference_source_paths()
    reference_sources_before = {name: sha256(project_file(ROOT / name, project)) for name in paths}
    built_sources = receipt.get("reference_sources_sha256", receipt.get("mirrored_sources", {}))
    if reference_sources_before != built_sources:
        raise SystemExit("Current mirrored sources differ from the selected build receipt; rebuild/reinstall first.")
    harness_paths = [HERE / name for name in ("oracle.gd", "stage_oracle.gd", "stage_adapter.gd", "trajectory.gd",
                                              "fleet.gd", "propeller_oracle.gd", "build.py", "run.py")]
    native_helpers = ROOT / "app/sim/native"
    harness_paths += [native_helpers / name for name in (
        "stage_config.gd", "weather_adapter.gd", "native_weather.gd", "native_configuration.gd",
        "electric_stage_adapter.gd", "liquid_stage_adapter.gd", "glow_stage_adapter.gd", "helicopter_stage_adapter.gd",
        "prescribed_stage_adapter.gd")]
    harness_paths += [HERE / args.script] if HERE / args.script not in harness_paths else []
    if args.script == "wake_spatial_oracle.gd":
        harness_paths += [HERE / "weather_oracle.gd", HERE / "wake_oracle.gd"]
    if args.script == "helicopter_stage_oracle.gd":
        harness_paths += [HERE / "helicopter_oracle.gd"]
    if args.script == "electric_stage_oracle.gd":
        harness_paths += [HERE / "electric_oracle.gd"]
    harness_paths += [ROOT / "app/sim/native_stage.gd", ROOT / "tools/godot/run_checked.py"]
    if platform_name == "macos":
        harness_paths.append(HERE / "build_macos.py")
    harness_sources = {str(path.relative_to(ROOT)): sha256(project_file(path, project)) for path in harness_paths}
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    stem = {"oracle.gd": "results", "stage_oracle.gd": "stage", "trajectory.gd": "trajectory",
            "fleet.gd": "fleet", "propeller_oracle.gd": "propeller",
            "weather_oracle.gd": "weather", "electric_oracle.gd": "electric",
            "wake_oracle.gd": "wake", "weather_stage_oracle.gd": "weather-stage",
            "glow_oracle.gd": "glow", "wake_spatial_oracle.gd": "wake-spatial",
            "glow_stage_oracle.gd": "glow-stage", "liquid_stage_oracle.gd": "liquid-stage", "liquid_oracle.gd": "liquid", "gear_oracle.gd": "gear", "helicopter_stage_oracle.gd": "helicopter-stage", "helicopter_oracle.gd": "helicopter", "electric_stage_oracle.gd": "electric-stage",
            "prescribed_stage_oracle.gd": "prescribed-stage", "legacy_ground_oracle.gd": "legacy-ground"}[args.script]
    output = TOOL_ROOT / f"{stem}{variant}-{stamp}.json"
    marker = "NK3_ORACLE verdict=fail" if args.mutant else "NK3_ORACLE verdict=pass"
    checks = TOOL_ROOT / "checks"
    checks.mkdir(parents=True, exist_ok=True)
    check_directory = Path(tempfile.mkdtemp(prefix=f"{stem}{variant}-", dir=checks))
    command = [sys.executable, str(ROOT / "tools/godot/run_checked.py"), "--out-dir", str(check_directory),
               "--label", f"nk3-{stem}{variant}", "--timeout", str(args.timeout), "--require-text", marker, "--",
               str(args.godot), "--headless", "--path", str(project), "--audio-driver", "Dummy",
               "--script", str(HERE / args.script), "--",
               f"--extension={descriptor}", f"--output={output}", f"--seed={args.seed}", f"--states={args.states}",
               f"--variant-states={args.variant_states}", f"--timing-rounds={args.timing_rounds}",
               f"--experimental-native-macos={'true' if args.experimental_native_macos else 'false'}",
               *[f"--{option}" for option in args.option]]
    completed = subprocess.run(command, cwd=ROOT)
    if not output.is_file():
        raise SystemExit(f"Oracle wrote no results ({completed.returncode}); see {TOOL_ROOT / 'checks'}.")
    results = json.loads(output.read_text(encoding="utf-8"))
    reports = list(check_directory.glob("*/report.json"))
    checked = json.loads(reports[0].read_text()) if len(reports) == 1 else {}
    results["build_receipt"] = receipt
    results["binary_sha256_before"] = binary_before
    results["binary_sha256_after"] = sha256(binary)
    results["engine_sha256_before"] = engine_before
    results["engine_sha256_after"] = sha256(args.godot)
    results["engine_executable_sha256_before"] = engine_executable_before
    results["engine_executable_sha256_after"] = sha256(engine_executable)
    results["harness_sources"] = harness_sources
    results["reference_sources_before"] = reference_sources_before
    results["checked_run"] = checked
    results["project"] = str(project)
    results["project_inventory_before"] = project_identity_before
    results["reference_sources_after"] = {
        name: sha256(project_file(ROOT / name, project)) for name in paths}
    results["sources_after"] = {name: sha256(project / name.removeprefix("res://"))
                                for name in results["sources"]}
    unchanged = (results["binary_sha256_after"] == binary_before and results["engine_sha256_after"] == engine_before
                 and results["engine_executable_sha256_after"] == engine_executable_before
                 and results["sources_after"] == results["sources"]
                 and results["reference_sources_after"] == reference_sources_before
                 and all(sha256(project_file(ROOT / name, project)) == digest for name, digest in harness_sources.items()))
    try:
        results["project_inventory_after"] = validate_project(project)
        unchanged = unchanged and results["project_inventory_after"] == project_identity_before
    except (OSError, ValueError, TypeError):
        unchanged = False
    run_ok = checked_run_matches(checked, args.mutant) and completed.returncode == (1 if args.mutant else 0)
    results["run_valid"] = unchanged and run_ok
    output.write_text(json.dumps(results, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(render(results))
    print(f"\nverdict={results['verdict']} compared={results['total']['compared']} "
          f"identical={results['total']['identical']} results={output}")
    expected = "fail" if args.mutant else "pass"
    if not results["run_valid"]:
        print("Run rejected: incomplete/erroring Godot process or sources/binary changed during the run.", file=sys.stderr)
    detected_difference = not args.mutant or results["total"]["mismatched"] > 0
    return 0 if results["verdict"] == expected and results["run_valid"] and detected_difference else 1


if __name__ == "__main__":
    raise SystemExit(main())
