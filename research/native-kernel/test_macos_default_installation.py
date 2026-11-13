#!/usr/bin/env python3
"""Exercise the source-editor Mac default and private installation fallbacks.

Requires an already imported, verified research preparation containing the
admission marker. Every launch uses a new APFS clone; the accepted project and
its installation are read-only inputs. This is not release/package acceptance.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager, redirect_stderr
import importlib.util
import io
import json
import os
import platform
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch
from typing import Any, Callable

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
TMP = ROOT / "tmp"
MARKER = "native/kernel/default-admission-macos.json"
RECEIPT = "native/kernel/build-receipt-macos.json"
LIBRARY = "native/kernel/libopenrc_native_kernel.dylib"
DESCRIPTOR = "native/kernel/openrc_native_kernel_macos.gdextension"
DOMAIN = "sim/native_macos_domain.gd"
MIRROR = "physics/aero.gd"
CASE_NAMES = ("missing-marker", "corrupt-marker", "stale-domain-hash", "missing-receipt",
              "corrupt-receipt", "missing-dylib", "tampered-dylib", "stale-mirrored-source", "wrong-slice")


def load(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError(f"cannot load {path}")
    result = importlib.util.module_from_spec(spec)
    original_path = sys.path[:]
    sys.path.insert(0, str(path.parent))
    try:
        spec.loader.exec_module(result)
    finally:
        sys.path[:] = original_path
    return result


ROUTE = load("macos_default_route", HERE / "test_default_route.py")
RUNNER = load("macos_default_source_runner", HERE / "run.py")
PREPARE = load("macos_default_preparation", ROOT / "tools/graphics/prepare_research.py")


def require(value: bool, detail: str) -> None:
    if not value:
        raise ValueError(detail)


def sha(path: Path) -> str:
    require(not path.is_symlink() and path.is_file(), f"missing or redirected file: {path}")
    return ROUTE.sha256_file(path)


def load_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"JSON object required: {path}")
    return value


def chosen_selection(marker: dict[str, Any]) -> dict[str, Any]:
    """The CLI trace is a production 0.5 trim and always disables soft hull."""
    rows = marker.get("allowed_selections")
    require(marker.get("format") == "openrc-macos-native-default v1"
            and marker.get("scope") == "source-editor-macos-arm64" and isinstance(rows, list),
            "missing or malformed source-editor admission marker")
    usable = [row for row in rows if isinstance(row, dict) and row.get("soft_hull") is False
              and row.get("trim_profile") == "production"
              and row.get("start") in ("airborne", "airborne_half_power", "runway", "hand_launch")
              and all(isinstance(row.get(key), str) and row[key] for key in ("aircraft", "battery", "weather"))]
    require(bool(usable), "marker has no trace-compatible admitted selection")
    # Prefer the ordinary Jensen airborne calm route when it actually qualified.
    return min(usable, key=lambda row: (row["aircraft"] != "jensen-das-ugly-stik-60",
                                        row["start"] != "airborne", row["weather"] != "calm",
                                        row["aircraft"], row["battery"], row["start"], row["weather"]))


def expected_identity(project: Path, engine: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    marker = load_object(project / MARKER)
    receipt = load_object(project / RECEIPT)
    row = receipt.get("platforms", {}).get("macos")
    require(isinstance(row, dict) and row.get("platform") == "macos" and row.get("architecture") == "arm64"
            and row.get("backend") == "native" and row.get("mutant", False) is False,
            "installed receipt is not a normal Mac ARM64 candidate")
    identity = {"backend": "native", "backend_version": row.get("backend_version"),
                "abi_version": row.get("abi_version"), "binary_sha256": row.get("binary_sha256"),
                "source_sha256": row.get("source_sha256"), "lock_sha256": row.get("lock_sha256")}
    require(identity["backend_version"] == "openrc-native-kernel-stage-v2" and identity["abi_version"] == 2
            and sha(project / RECEIPT) == marker.get("receipt_sha256")
            and sha(project / LIBRARY) == row.get("binary_sha256") == marker.get("binary_sha256")
            and sha(project / DOMAIN) == marker.get("domain_sha256")
            and sha(engine) == row.get("engine_sha256") == marker.get("engine_sha256")
            and row.get("source_sha256") == marker.get("source_sha256")
            and row.get("lock_sha256") == marker.get("lock_sha256")
            and row.get("runtime_os_version") == marker.get("os_version")
            and row.get("runtime_os_build") == marker.get("os_build")
            and marker.get("cpu") == "Apple M1" and marker.get("hardware_model") == "MacBookAir10,1",
            "marker, engine, installed binary, domain, or receipt identity differs")
    require(isinstance(row.get("mirrored_sources"), dict)
            and row["mirrored_sources"].get("app/" + MIRROR) == sha(project / MIRROR),
            "mirrored-source fixture is not bound to the installed receipt")
    sha(project / DESCRIPTOR)
    return marker, row, identity


def clone_project(source: Path, destination: Path, clone: Callable[[Path, Path], None]) -> None:
    """Clone every project/cache file without hardlinks or copy fallback."""
    require(not source.is_symlink() and source.is_dir() and not destination.exists(), "invalid clone endpoints")
    assets = source.parent / "assets"
    require(assets.is_dir(), "prepared project lacks its sibling authoring assets")
    destination.parent.mkdir(parents=True, exist_ok=False)
    (destination.parent / "assets").symlink_to(assets.resolve(), target_is_directory=True)

    def no_links(directory: str, names: list[str]) -> set[str]:
        for name in names:
            path = Path(directory) / name
            require(not PREPARE._is_link(path), f"project contains a link: {path}")
        return set()

    def clone_verified(src: str, dst: str) -> str:
        original, copied = Path(src), Path(dst)
        require(not PREPARE._is_link(original) and stat.S_ISREG(original.lstat().st_mode),
                f"clone input is not a regular file: {original}")
        before = sha(original)
        clone(original, copied)  # prepare_research._macos_clonefile is exclusive and never falls back.
        require(not PREPARE._is_link(copied) and stat.S_ISREG(copied.lstat().st_mode)
                and not os.path.samefile(original, copied), f"clone shares an inode or is not regular: {copied}")
        shutil.copystat(original, copied, follow_symlinks=False)
        require(sha(original) == before == sha(copied), f"clone/source bytes changed: {original}")
        return str(copied)

    shutil.copytree(source, destination, ignore=no_links, copy_function=clone_verified)


def mutate(project: Path, case: str) -> str:
    if case in ("missing-marker", "corrupt-marker", "stale-domain-hash"):
        relative = MARKER
    elif case in ("missing-receipt", "corrupt-receipt"):
        relative = RECEIPT
    elif case in ("missing-dylib", "tampered-dylib"):
        relative = LIBRARY
    elif case == "stale-mirrored-source":
        relative = MIRROR
    elif case == "wrong-slice":
        relative = DESCRIPTOR
    else:
        raise ValueError(f"unknown fixture: {case}")
    target = project / relative
    sha(target)  # Never create a replacement for an unexpectedly absent input.
    if case.startswith("missing-"):
        target.unlink()
    elif case in ("corrupt-marker", "corrupt-receipt"):
        target.write_text("{", encoding="utf-8")
    elif case == "stale-domain-hash":
        marker = load_object(target)
        old = marker.get("domain_sha256")
        require(isinstance(old, str) and len(old) == 64, "marker has no domain hash")
        marker["domain_sha256"] = ("1" if old[0] == "0" else "0") + old[1:]
        target.write_text(json.dumps(marker, sort_keys=True), encoding="utf-8")
    elif case == "tampered-dylib":
        with target.open("ab") as stream:
            stream.write(b"\nopenrc-private-admission-negative\n")
    elif case == "stale-mirrored-source":
        with target.open("a", encoding="utf-8", newline="\n") as stream:
            stream.write("\n# Private mirrored-source admission negative.\n")
    elif case == "wrong-slice":
        original = target.read_text(encoding="utf-8")
        require(original.count("macos.arm64 = ") == 1, "unexpected descriptor source slice")
        target.write_text(original.replace("macos.arm64 = ", "macos.x86_64 = ", 1), encoding="utf-8")
    return relative


def verify_single_mutation(before: list[dict], after: list[dict], relative: str, missing: bool) -> None:
    old = {item["path"]: item for item in before}
    new = {item["path"]: item for item in after}
    require(relative in old and ((relative not in new) if missing else (relative in new and new[relative] != old[relative]))
            and {key: value for key, value in old.items() if key != relative}
                == {key: value for key, value in new.items() if key != relative},
            f"fixture changed more than its intended file: {relative}")


@contextmanager
def isolated_environment(directory: Path):
    names = {name for name in os.environ if name in {"OPENRC_GODTEST_CONFIG", "OPENRC_RC_TRACK", "OPENRC_LAKE"}
             or name.startswith("OPENRC_SCENERY")}
    names |= {"HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"}
    saved = {name: os.environ.get(name) for name in names}
    try:
        for name in names:
            os.environ.pop(name, None)
        home = directory / "home"
        home.mkdir(parents=True, exist_ok=True)
        os.environ.update(HOME=str(home), XDG_DATA_HOME=str(home / "data"),
                          XDG_CONFIG_HOME=str(home / "config"), XDG_CACHE_HOME=str(home / "cache"))
        yield
    finally:
        for name in names:
            os.environ.pop(name, None)
        for name, value in saved.items():
            if value is not None:
                os.environ[name] = value


def run_trace(engine: Path, project: Path, output: Path, label: str, selection: dict[str, Any],
              *, explicit_reference: bool = False) -> tuple[dict, dict, list]:
    trace = output / f"{label}.csv"
    args = ["--quick-flight", f"--aircraft={selection['aircraft']}", f"--battery={selection['battery']}",
            f"--start={selection['start']}", f"--weather={selection['weather']}", "--t=.05", f"--trace={trace}"]
    if explicit_reference:
        args.append("--physics-backend=gdscript_reference")
    with isolated_environment(output / "homes" / label):
        checked, log = ROUTE.run_case(engine, project, output, label, args)
    require(checked.get("complete") is True and checked.get("ok") is True
            and checked.get("counts", {}).get("error") == 0 and checked.get("process_exit") == 0,
            f"{label}: checked Godot log did not complete cleanly")
    actual = ROUTE.status(log)
    metadata, rows = ROUTE.trace_parts(trace)
    require(rows and rows[0].count("tick") == 1 and all(len(item) == len(rows[0]) for item in rows[1:]),
            f"{label}: trace columns are missing or inconsistent")
    column = rows[0].index("tick")
    require([int(row[column]) for row in rows[1:]] == list(range(13)), f"{label}: trace did not complete ticks 0..12")
    return checked, {"status": actual, "metadata": metadata, "trace": str(trace), "trace_sha256": sha(trace)}, rows


def run(engine: Path, project: Path, output: Path) -> dict[str, Any]:
    require(sys.platform == "darwin" and platform.machine() == "arm64", "native macOS ARM64 Python is required")
    require(project != (ROOT / "app").resolve() and project.is_dir() and (project / ".godot").is_dir(),
            "an imported isolated research project is required")
    proof = RUNNER.validate_project(project)
    require(bool(proof), "source project lacks a valid preparation identity")
    marker, row, expected = expected_identity(project, engine)
    selection = chosen_selection(marker)
    source_before = RUNNER._project_inventory(project)
    source_hash = RUNNER._inventory_hash(source_before)
    preparation = project.parent / "research-preparation.json"
    preparation_sha = sha(preparation)
    engine_sha = sha(engine)
    clone = PREPARE._macos_clonefile()
    cases_root = output / "projects"
    cases_root.mkdir()

    def private(name: str) -> Path:
        target = cases_root / name / "app"
        clone_project(project, target, clone)
        require(RUNNER._project_inventory(target) == source_before, f"{name}: clone differs from accepted source")
        return target

    positive_project = private("positive")
    positive_check, positive, positive_rows = run_trace(engine, positive_project, output, "positive", selection)
    active = positive["status"]
    require(active.get("requested") == "native" and active.get("identity") == expected and active.get("reason") == "",
            f"default did not select the qualified native identity: {active}")
    native_metadata = positive["metadata"]
    require("stage_backend" in native_metadata
            and json.loads(native_metadata["stage_backend"].replace('&"', '"')) == expected,
            "positive trace does not bind the installed native backend")
    require(RUNNER._project_inventory(positive_project) == source_before, "positive launch changed project sources")

    reference_check, reference, reference_rows = run_trace(engine, positive_project, output, "reference", selection,
                                                           explicit_reference=True)
    require(reference["status"] == {"requested": "gdscript_reference", "identity": {"backend": "gdscript_reference"},
                                     "reason": ""} and "stage_backend" not in reference["metadata"]
            and reference_rows == positive_rows, "explicit reference did not match the complete native trace")
    require(RUNNER._project_inventory(positive_project) == source_before, "reference launch changed project sources")

    evidence = []
    for name in CASE_NAMES:
        fixture = private(name)
        mutated = mutate(fixture, name)
        changed_before = RUNNER._project_inventory(fixture)
        verify_single_mutation(source_before, changed_before, mutated, name.startswith("missing-"))
        checked, result, rows = run_trace(engine, fixture, output, name, selection)
        status = result["status"]
        reason_fragment = ("binary" if name in ("missing-dylib", "tampered-dylib") else
                           "mirrored source" if name == "stale-mirrored-source" else
                           "descriptor" if name == "wrong-slice" else "qualification")
        require(status.get("requested") == "native" and status.get("identity") == {"backend": "gdscript_reference"}
                and isinstance(status.get("reason"), str) and reason_fragment in status["reason"].lower()
                and "stage_backend" not in result["metadata"] and rows == reference_rows,
                f"{name}: did not complete the matching reference fallback: {status}")
        require(RUNNER._project_inventory(fixture) == changed_before, f"{name}: launch changed fixture sources")
        evidence.append({"case": name, "mutated": mutated, "checked": checked, "trace": result})
        print(f"PASS {name}: checked reference fallback, 12 ticks", flush=True)

    require(RUNNER._project_inventory(project) == source_before and sha(preparation) == preparation_sha
            and sha(engine) == engine_sha and RUNNER.validate_project(project) == proof,
            "accepted project, preparation, or engine changed during the fixture run")
    return {"format": "openrc-macos-default-installation-test v1", "verdict": "pass",
            "scope": "source-editor Mac ARM64 only; no public package qualification",
            "project": str(project), "project_manifest_sha256": source_hash, "preparation_sha256": preparation_sha,
            "engine_sha256": engine_sha, "marker_sha256": sha(project / MARKER),
            "receipt_sha256": sha(project / RECEIPT), "binary_sha256": row["binary_sha256"],
            "selection": selection, "ticks": 12, "positive": {"checked": positive_check, "trace": positive},
            "reference": {"checked": reference_check, "trace": reference}, "fallback_cases": evidence}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    try:
        engine_arg, project_arg, out_arg = (item.expanduser().absolute() for item in (args.godot, args.project, args.out))
        require(not engine_arg.is_symlink() and not project_arg.is_symlink() and not out_arg.exists()
                and not out_arg.is_symlink(), "engine/project must be regular inputs and output must be new")
        engine, project, output = engine_arg.resolve(), project_arg.resolve(), out_arg.resolve()
        temp_root = TMP.resolve()
        prepared_root = project.parent
        require(output.is_relative_to(temp_root) and output != temp_root and not output.is_relative_to(prepared_root)
                and not prepared_root.is_relative_to(output), "output must be a separate new directory under tmp/")
        require(sys.platform == "darwin" and platform.machine() == "arm64", "native macOS ARM64 Python is required")
        output.mkdir(parents=True, exist_ok=False)
        result = run(engine, project, output)
        report = output / "report.json"
        with report.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(result, stream, indent=2, sort_keys=True, allow_nan=False)
            stream.write("\n")
        print(f"MACOS_DEFAULT_INSTALLATION verdict=pass native_success=true ticks=12 cases={len(CASE_NAMES)} report={report}")
        return 0
    except (OSError, ValueError, KeyError, TypeError, AssertionError) as error:
        print(f"MACOS_DEFAULT_INSTALLATION verdict=fail: {error}", file=sys.stderr)
        return 1


class FixtureTests(unittest.TestCase):
    """Portable policy tests; executing the fixture itself still requires M1 macOS."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        for name, data in ((MARKER, json.dumps({"domain_sha256": "a" * 64})), (RECEIPT, "{\"macos\":true}"),
                           (LIBRARY, "original dylib"), (DESCRIPTOR, 'macos.arm64 = "lib.dylib"\n'),
                           (DOMAIN, "domain script\n"), (MIRROR, "aero script\n")):
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data, encoding="utf-8")
        self.original = RUNNER._project_inventory(self.source)

    def test_each_negative_changes_only_its_private_file(self) -> None:
        for name in CASE_NAMES:
            with self.subTest(case=name):
                fixture = self.root / name
                shutil.copytree(self.source, fixture)
                relative = mutate(fixture, name)
                changed = RUNNER._project_inventory(fixture)
                verify_single_mutation(self.original, changed, relative, name.startswith("missing-"))
                self.assertEqual(RUNNER._project_inventory(self.source), self.original)

    def test_extra_changed_file_and_missing_change_are_rejected(self) -> None:
        fixture = self.root / "extra"
        shutil.copytree(self.source, fixture)
        relative = mutate(fixture, "stale-domain-hash")
        (fixture / DOMAIN).write_text("changed", encoding="utf-8")
        with self.assertRaises(ValueError):
            verify_single_mutation(self.original, RUNNER._project_inventory(fixture), relative, False)
        with self.assertRaises(ValueError):
            verify_single_mutation(self.original, self.original, MARKER, False)

    def test_clone_writes_never_reach_the_accepted_source(self) -> None:
        (self.root / "assets").mkdir()
        destination = self.root / "private" / "app"
        # The production path supplies clonefile; ordinary copies exercise only
        # this helper's verification and mutation isolation on non-Mac hosts.
        with patch.object(Path, "symlink_to"):
            clone_project(self.source, destination, lambda source, target: shutil.copyfile(source, target))
        self.assertEqual(RUNNER._project_inventory(destination), self.original)
        mutate(destination, "tampered-dylib")
        self.assertEqual(RUNNER._project_inventory(self.source), self.original)

    def test_selection_requires_production_row_with_trace_hull(self) -> None:
        row = {"aircraft": "jensen-das-ugly-stik-60", "battery": "ideal", "weather": "calm",
               "start": "airborne", "trim_profile": "production", "soft_hull": False}
        marker = {"format": "openrc-macos-native-default v1", "scope": "source-editor-macos-arm64",
                  "allowed_selections": [dict(row, soft_hull=True), row]}
        self.assertEqual(chosen_selection(marker), row)
        marker["allowed_selections"] = [dict(row, soft_hull=True)]
        with self.assertRaises(ValueError):
            chosen_selection(marker)

    def test_unsupported_host_refuses_without_a_success_artifact(self) -> None:
        TMP.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=TMP) as directory:
            out = Path(directory) / "never-created"
            argv = ["test", "--godot", str(self.root / "godot"), "--project", str(self.root / "app"),
                    "--out", str(out)]
            with patch.object(sys, "argv", argv), patch.object(sys, "platform", "linux"), redirect_stderr(io.StringIO()):
                self.assertEqual(main(), 1)
            self.assertFalse(out.exists())


if __name__ == "__main__":
    raise SystemExit(main())
