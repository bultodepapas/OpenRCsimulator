#!/usr/bin/env python3
"""Reproduce the pinned crash-economics audit in a small, isolated Godot project.

This is a test-fixture runner, not the production application or a physics validator.
It refuses altered inputs and leaves all output in a new caller-specified directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys

PIN = "f47d1dc6cccb141936407d0217eafdc465558190"
ENGINE_VERSION = "4.8.beta2.official.cafc17a19"
FILES = {
    "harness_manifest.json": "4237a5840cda7faf3fc67363ec8702fbf8e5c3632f75afc161a47939e4d82c72",
    "harness_project.godot": "96618faf0a25d6e280b09a7c1da6f68227196208712fc3bb092ed85c9891f9e3",
    "audit_probe.gd": "6dbb18f715a8d8776c0d4a4538dcab1dcc67a1578de84f4b03969b87f46f17ed",
}
MARKERS = {
    "test_economy_calculator": "67 checks, 0 failed",
    "test_economy_catalog": "102 checks, 0 failed",
    "test_economy_component_resolver": "ComponentResolver: 35 checks, 0 failed",
    "test_economy_cr39": "CR-39 economics: 52 checks, 0 failed",
    "test_economy_impact_budget": "36 checks, 0 failed",
    "test_economy_inspection": "83 checks, 0 failed",
    "test_economy_package_optimizer": "CR-31d package optimizer: 40 checks, 0 failures",
    "test_economy_repair_details": "economy repair details: 49 checks, 0 failed",
    "test_economy_repair_planner": "51 checks, 0 failed",
    "test_economy_replacement_quote": "CR-31e replacement quote: 45 checks, 0 failures",
    "test_economy_thermal_budget": "ThermalBudget tests passed: 68 checks",
    "test_accident_settlement": "accident settlement: 46 checks, 0 failed",
    "audit_probe": "AUDIT PROBES: 10 checks, 0 failed",
}
# This runtime-only branch is outside these fixtures. Its transitive closure
# imports the production flight/render tree; an invocation still fails closed.
EXCLUDED = ("app_state/aircraft_catalog.gd", "sim/flight_session.gd")
LITERAL_SCRIPT = re.compile(r'''(?<![\w.])(preload|load)\s*\(\s*["']res://([^"']+\.gd)["']''')
CLASS_NAME = re.compile(r"(?m)^\s*class_name\s+([A-Za-z_]\w*)")
LOCAL_NAME = re.compile(r"(?m)^\s*(?:const|var|class)\s+([A-Za-z_]\w*)")
STRINGS = re.compile(r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*' ''', re.X)


class ReproductionError(Exception):
    pass


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def digest_file(path: Path, algorithm: str = "sha256") -> str:
    h = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def git(repo: Path, *args: str, data: bytes | None = None) -> bytes:
    try:
        return subprocess.run(["git", "-C", str(repo), *args], input=data,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              check=True, timeout=120).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        raise ReproductionError(f"git {' '.join(args)} failed: {exc}") from exc


def safe_relative(value: str) -> Path:
    parsed = PurePosixPath(value)
    if parsed.is_absolute() or not parsed.parts or any(p in (".", "..") for p in parsed.parts):
        raise ReproductionError(f"unsafe path in manifest: {value!r}")
    return Path(*parsed.parts)


def regular(path: Path) -> None:
    if not path.is_file() or path.is_symlink():
        raise ReproductionError(f"missing or nonregular file: {path}")


def verify_manifest(repo: Path, manifest: dict) -> dict[str, str]:
    if manifest.get("source_commit") != PIN:
        raise ReproductionError("manifest baseline mismatch")
    entries = manifest.get("files", [])
    if len(entries) != 217:
        raise ReproductionError("expected the original 217-file manifest")
    expected: dict[str, str] = {}
    for item in entries:
        rel = str(safe_relative(item["path"]).as_posix())
        if rel in expected:
            raise ReproductionError(f"duplicate manifest path {rel}")
        path = repo / "app" / rel
        regular(path)
        if digest_file(path) != item["sha256"]:
            raise ReproductionError(f"manifest SHA-256 mismatch: app/{rel}")
        expected[rel] = item["sha256"]
    if {Path(x).stem for x in manifest["tests"]} != set(MARKERS) - {"audit_probe"}:
        raise ReproductionError("unexpected test roster")
    if any(x not in expected for x in manifest["tests"]):
        raise ReproductionError("test missing from pinned manifest")
    return expected


def closure(repo: Path, expected: dict[str, str], roots: list[str], probe: str) -> tuple[list[str], list[dict]]:
    text_by_path: dict[str, str] = {}
    classes: dict[str, str] = {}
    for rel in expected:
        if rel.endswith(".gd"):
            text = (repo / "app" / rel).read_text(encoding="utf-8")
            text_by_path[rel] = text
            match = CLASS_NAME.search(text)
            if match:
                if match.group(1) in classes:
                    raise ReproductionError(f"duplicate class_name {match.group(1)}")
                classes[match.group(1)] = rel
    pending = list(roots)
    pending += [path for _, path in LITERAL_SCRIPT.findall(probe)]
    selected: set[str] = set()
    excluded: list[dict] = []
    while pending:
        rel = pending.pop()
        if rel in selected:
            continue
        if rel not in text_by_path:
            raise ReproductionError(f"script dependency is missing from manifest: {rel}")
        selected.add(rel)
        text = text_by_path[rel]
        # All source is hash-pinned. Discard comment-only suffixes for the simple
        # class-reference scan; explicitly loaded literals are scanned separately.
        code = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
        aliases = set(LOCAL_NAME.findall(code))
        visible = STRINGS.sub("", code)
        for kind, dep in LITERAL_SCRIPT.findall(code):
            if (rel, dep) == EXCLUDED and kind == "load":
                excluded.append({"from": rel, "path": dep, "kind": kind,
                    "reason": "Runtime-only ground_start_support branch, not exercised by the pinned economy fixtures; full flight is excluded."})
            else:
                pending.append(dep)
        for class_name, dep in classes.items():
            if dep != rel and class_name not in aliases and re.search(r"\b" + re.escape(class_name) + r"\b", visible):
                pending.append(dep)
    if len(excluded) != 1:
        raise ReproductionError("expected exactly one known excluded runtime load")
    return sorted(selected), excluded


def tracked_data(repo: Path) -> list[str]:
    rows = git(repo, "ls-tree", "-r", "-z", PIN, "--", "app/data").split(b"\0")
    paths: list[str] = []
    for row in rows:
        if not row:
            continue
        meta, name = row.split(b"\t", 1)
        mode, kind, _ = meta.decode().split()
        rel = name.decode("utf-8")
        if rel.endswith(".json"):
            if mode != "100644" or kind != "blob":
                raise ReproductionError(f"unsupported tracked data file: {rel}")
            paths.append(rel)
    if len(paths) != 114:
        raise ReproductionError(f"unexpected data roster: {len(paths)} JSON files")
    return sorted(paths) + ["app/i18n/es.po", "research/crash-economics/repair-recipes.json",
                           "tools/godot/run_checked.py"]


def verify_tracked_data(repo: Path, paths: list[str]) -> dict[str, str]:
    # Compare against Git blobs while honoring the repository's declared CRLF
    # checkout convention. This preserves byte-sensitive aircraft identities.
    attrs_input = b"".join(os.fsencode(p) + b"\0" for p in paths)
    attrs = git(repo, "check-attr", "--cached", "-z", "--stdin", "eol", data=attrs_input).split(b"\0")
    eol = {attrs[i].decode(): attrs[i + 2].decode() for i in range(0, len(attrs) - 2, 3)}
    hashes = {}
    for rel in paths:
        path = repo / safe_relative(rel)
        regular(path)
        blob = git(repo, "show", f"{PIN}:{rel}")
        if eol.get(rel) == "crlf":
            blob = blob.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        actual = path.read_bytes()
        if actual != blob:
            raise ReproductionError(f"tracked input differs from pinned checkout bytes: {rel} (eol={eol.get(rel)})")
        hashes[rel] = digest(actual)
    return hashes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path, help="pinned repository checkout")
    parser.add_argument("--godot", required=True, type=Path, help="matching pinned Godot executable")
    parser.add_argument("--out-dir", required=True, type=Path, help="new isolated output directory")
    args = parser.parse_args()
    repo = args.repo.resolve()
    godot = args.godot.resolve()
    out = args.out_dir.resolve()
    evidence = Path(__file__).resolve().parent.parent / "evidence"
    if out.exists():
        raise ReproductionError(f"output path already exists: {out}")
    if out == repo or repo in out.parents:
        raise ReproductionError("output must be outside the repository checkout")
    regular(godot)
    for name, expected_hash in FILES.items():
        regular(evidence / name)
        if digest_file(evidence / name) != expected_hash:
            raise ReproductionError(f"bundled evidence SHA-256 mismatch: {name}")
    if git(repo, "rev-parse", "HEAD").decode().strip() != PIN:
        raise ReproductionError(f"repository HEAD must be exactly {PIN}")
    version = subprocess.run([str(godot), "--version"], capture_output=True, text=True, check=True, timeout=30).stdout.strip()
    if version != ENGINE_VERSION:
        raise ReproductionError(f"Godot version mismatch: {version!r}")
    godot_sha = digest_file(godot, "sha512")
    manifest = json.loads((evidence / "harness_manifest.json").read_text())
    expected = verify_manifest(repo, manifest)
    data_paths = tracked_data(repo)
    data_hashes = verify_tracked_data(repo, data_paths)
    selected, excluded = closure(repo, expected, manifest["tests"], (evidence / "audit_probe.gd").read_text())
    out.mkdir(parents=True, exist_ok=False)
    project = out / "economy_harness"
    project.mkdir()
    for rel in selected:
        dst = project / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(repo / "app" / rel, dst)
    for rel in data_paths:
        if rel == "tools/godot/run_checked.py":
            continue
        dst = (project / rel[4:]) if rel.startswith("app/") else (out / rel)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(repo / rel, dst)
    shutil.copyfile(evidence / "harness_project.godot", project / "project.godot")
    shutil.copyfile(evidence / "audit_probe.gd", project / "audit_probe.gd")
    selection = {"baseline": PIN, "engine_version": version, "engine_sha512": godot_sha,
                 "verified_manifest_files": len(expected), "selected_scripts": selected,
                 "excluded_runtime_loads": excluded, "tracked_data_sha256": data_hashes,
                 "limits": ["isolated 240 Hz no-autoload project", "no complete application or graphical flight",
                            "ground_start_support dynamic flight-session branch is excluded", "not physical validation"]}
    (out / "selection.json").write_text(json.dumps(selection, indent=2) + "\n")
    env = os.environ.copy()
    for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        path = out / "profile" / key
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    runner = repo / "tools/godot/run_checked.py"
    checks = out / "checks"
    results = []

    def checked(label: str, engine_args: list[str], marker: str | None = None) -> None:
        cmd = [sys.executable, str(runner), "--out-dir", str(checks), "--label", label,
               "--timeout", "180"]
        if marker:
            cmd += ["--require-text", marker]
        cmd += ["--", str(godot), "--headless", "--path", str(project), "--audio-driver", "Dummy", *engine_args]
        print(f"RUN {label}", flush=True)
        process = subprocess.run(cmd, env=env, cwd=repo, check=False)
        reports = sorted(checks.glob(label + "-*/report.json"))
        if len(reports) != 1:
            raise ReproductionError(f"{label}: expected one checked-runner report, found {len(reports)}")
        report = json.loads(reports[0].read_text())
        results.append({"label": label, "ok": report.get("ok"), "report": str(reports[0].relative_to(out))})
        if process.returncode != 0 or report.get("ok") is not True:
            raise ReproductionError(f"{label} failed; inspect {reports[0]}")

    try:
        checked("import", ["--import"])
        for test in manifest["tests"]:
            label = Path(test).stem
            checked(label, ["--script", "res://" + test], MARKERS[label])
        checked("audit_probe", ["--script", "res://audit_probe.gd"], MARKERS["audit_probe"])
        if git(repo, "rev-parse", "HEAD").decode().strip() != PIN:
            raise ReproductionError("repository HEAD changed during run")
        verify_manifest(repo, manifest)
        if verify_tracked_data(repo, data_paths) != data_hashes or digest_file(godot, "sha512") != godot_sha:
            raise ReproductionError("source data or engine changed during run")
        (out / "summary.json").write_text(json.dumps({"ok": True, "results": results,
            "historical_scripts": 12, "historical_assertions": 674, "current_behavior_probes": 10,
            "scope": "isolated reproduction; not a full-app or acceptance run"}, indent=2) + "\n")
        print(f"PASS: 12 historical scripts (674 assertions) and 10 current-behavior probes; {out}")
        return 0
    except Exception as exc:
        (out / "summary.json").write_text(json.dumps({"ok": False, "results": results, "error": str(exc)}, indent=2) + "\n")
        raise


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ReproductionError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(f"REPRODUCER ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
