#!/usr/bin/env python3
"""Collect checked publication captures from two isolated, Git-verified app trees.

The baseline is reconstructed from the candidate using only changed historical
blobs. This collects evidence; it does not promote a fixture or change goldens.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "676be5351357c981d6500b17569aa38615a0c8cb"
PIN_FILE = ROOT / "app/tests/fixtures/publication_fixture_bridge.json"
PRIOR_RECEIPT = ROOT / "docs/research/release-readiness/PT1-CI-00/publication-rebind-2026-11-11.json"
CAPTURE_SCRIPTS = {"shaft": "audit_fixture_shaft_capture.gd", "weather": "audit_fixture_weather_capture.gd"}
EXCLUDE_DIRS = {".godot", ".tools", "__pycache__"}


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def script_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def git(args: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None,
        data: bytes | None = None) -> bytes:
    result = subprocess.run(["git", *args], cwd=ROOT if cwd is None else cwd, env=env, input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    return result.stdout


def tree(commit: str) -> dict[str, tuple[str, str]]:
    result = {}
    for record in git(["ls-tree", "-rz", "--full-tree", commit, "--", "app"]).split(b"\0"):
        if not record:
            continue
        metadata, path = record.split(b"\t", 1)
        mode, kind, oid = metadata.decode("ascii").split()
        name = path.decode("utf-8")
        if kind != "blob" or mode not in {"100644", "100755"} or "\n" in name or "\r" in name:
            raise ValueError(f"Unsupported tracked app entry: {name}")
        result[name] = (mode, oid)
    if not result:
        raise ValueError("The selected commit has no app tree")
    return result


def copy_ignore(directory: str, names: list[str]) -> set[str]:
    return {name for name in names if name in EXCLUDE_DIRS or
            (Path(directory) == ROOT / "app" and name in {"captures", "tmp", "native"})}


def reconstruct(baseline_root: Path, current: dict[str, tuple[str, str]],
                historical: dict[str, tuple[str, str]], index: Path) -> None:
    """Transform the disposable candidate copy into the complete baseline app."""
    app = (baseline_root / "app").resolve()
    # No deletions are allowed outside the newly created disposable app.
    if not app.is_relative_to(baseline_root.resolve()) or app == baseline_root.resolve():
        raise ValueError("Unexpected baseline app path")
    for name in sorted(set(current) - set(historical)):
        target = baseline_root / name
        if not target.resolve().is_relative_to(app) or target.is_symlink() or not target.is_file():
            raise ValueError(f"Unexpected disposable baseline file: {name}")
        target.unlink()
    (baseline_root / ".gitattributes").write_bytes(git(["show", BASELINE + ":.gitattributes"]))
    env = dict(os.environ, GIT_INDEX_FILE=str(index.resolve()), GIT_WORK_TREE=str(baseline_root.resolve()))
    git(["read-tree", BASELINE], env=env)
    changed = sorted(name for name, value in historical.items() if current.get(name) != value)
    if changed:
        git(["-c", "core.autocrlf=false", "-c", "core.eol=lf", "checkout-index", "--force", "-z", "--stdin"],
            env=env, data=b"\0".join(name.encode("utf-8") for name in changed) + b"\0")


def inventory(project_root: Path, commit: str, expected: dict[str, tuple[str, str]]) -> bytes:
    """Check the complete tracked set, Git-clean blob bytes and representable modes."""
    app = project_root / "app"
    attributes = (project_root / ".gitattributes").read_bytes()
    committed_attributes = git(["show", commit + ":.gitattributes"])
    if attributes.replace(b"\r\n", b"\n") != committed_attributes.replace(b"\r\n", b"\n"):
        raise ValueError("Project checkout attributes differ from the selected commit")
    observed = set()
    for path in app.rglob("*"):
        if ".godot" in path.relative_to(app).parts:
            continue
        if path.is_symlink():
            raise ValueError(f"Symlink in isolated app: {path}")
        if path.is_file():
            observed.add("app/" + path.relative_to(app).as_posix())
    if observed != set(expected):
        raise ValueError(f"Isolated app file set differs from {commit}: missing={sorted(set(expected)-observed)[:5]}, "
                         f"extra={sorted(observed-set(expected))[:5]}")
    names = sorted(expected)
    env = dict(os.environ, GIT_DIR=str((ROOT / ".git").resolve()), GIT_WORK_TREE=str(project_root.resolve()))
    hashes = git(["-c", "core.autocrlf=false", "-c", "core.eol=lf", "hash-object", "--stdin-paths"],
                 cwd=project_root, env=env, data=("\n".join(names) + "\n").encode()).decode().splitlines()
    if len(hashes) != len(names):
        raise ValueError("Git did not hash every isolated source file")
    files = {}
    for name, actual_oid in zip(names, hashes):
        mode, oid = expected[name]
        path = project_root / name
        if actual_oid != oid:
            raise ValueError(f"Isolated file differs from Git blob: {name}")
        if os.name != "nt" and bool(path.stat().st_mode & stat.S_IXUSR) != (mode == "100755"):
            raise ValueError(f"Isolated file executable mode differs: {name}")
        files[name] = {"git_blob": oid, "mode": mode, "sha256": sha256(path), "size": path.stat().st_size}
    value = {"format": "openrc-publication-source-inventory-v1", "commit": commit, "files": files,
             "attributes_sha256": hashlib.sha256(attributes.replace(b"\r\n", b"\n")).hexdigest()}
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def source_pins(project_root: Path, pins: dict) -> dict[str, str]:
    result = {}
    if len(pins) != 19:
        raise ValueError("Expected the 19 accepted source pins")
    for name, row in pins.items():
        value = (project_root / "app" / name).read_bytes()
        if row["mode"] == "script-lf":
            value = value.replace(b"\r\n", b"\n")
        elif row["mode"] != "exact":
            raise ValueError(f"Unknown source pin mode: {name}")
        result[name] = hashlib.sha256(value).hexdigest()
    return result


def checked(project: Path, engine: Path, out: Path, label: str, script: Path | None,
            marker: str, capture: Path | None, profile: Path) -> tuple[Path, Path]:
    check_dir = out / (label + "-checked")
    command = [sys.executable, str(ROOT / "tools/godot/run_checked.py"), "--out-dir", str(check_dir),
               "--label", label, "--timeout", "600"]
    if script is not None:
        command.append("--warnings-as-errors")
    if marker:
        command += ["--require-text", marker]
    command += ["--", str(engine), "--headless", "--path", str(project), "--audio-driver", "Dummy"]
    command += ["--import"] if script is None else ["--script", str(script)]
    profile.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, XDG_DATA_HOME=str(profile), APPDATA=str(profile), LOCALAPPDATA=str(profile))
    env.pop("OPENRC_AUDIT_CAPTURE", None)
    if capture is not None:
        env["OPENRC_AUDIT_CAPTURE"] = str(capture)
    print("Running " + label, flush=True)
    subprocess.run(command, cwd=ROOT, env=env, check=True)
    reports = list(check_dir.glob("*/report.json"))
    if len(reports) != 1:
        raise ValueError(f"Expected one checked report for {label}")
    report = json.loads(reports[0].read_text(encoding="utf-8"))
    if (report.get("complete") is not True or report.get("ok") is not True or report.get("process_exit") != 0
            or report.get("counts", {}).get("error") != 0 or report.get("missing_required_text") != []
            or (script is not None and report.get("counts", {}).get("warning") != 0)):
        raise ValueError(f"Checked run did not pass cleanly: {label}")
    log = Path(report["log"])
    if not log.is_file() or sha256(log) != report.get("log_sha256"):
        raise ValueError(f"Checked log is missing or changed: {label}")
    return reports[0], log


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="new windows/ or linux/ directory under tmp/")
    parser.add_argument("--candidate", required=True, help="exact checked-out 40-hex commit")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.candidate):
        parser.error("--candidate must be a full lowercase Git commit")
    out = args.out.resolve()
    platform = {"win32": "Windows", "linux": "Linux"}.get(sys.platform)
    if platform is None or out.name != platform.lower() or not out.is_relative_to((ROOT / "tmp").resolve()):
        parser.error("--out must be a new tmp/.../windows or tmp/.../linux directory on its matching host")
    if args.out.exists() or args.out.is_symlink():
        parser.error("--out already exists")
    engine = args.godot.resolve()
    actual_engine = engine.with_name(engine.name.replace("_console.exe", ".exe")) if platform == "Windows" else engine
    out.mkdir(parents=True, exist_ok=False)
    try:
        if git(["rev-parse", "HEAD"]).decode().strip() != args.candidate:
            raise ValueError("Candidate commit differs from the checked-out HEAD")
        if git(["status", "--porcelain=v1", "--untracked-files=all", "--", "app", ".gitattributes",
                "tools/godot/audit_fixture_shaft_capture.gd", "tools/godot/audit_fixture_weather_capture.gd"]).strip():
            raise ValueError("Capture source checkout is not clean")
        prior = json.loads(PIN_FILE.read_text(encoding="utf-8"))
        if prior.get("candidate_commit") != BASELINE:
            raise ValueError("Prior fixture is not anchored to the accepted baseline")
        pins = prior["source_pins"]
        receipt = json.loads(PRIOR_RECEIPT.read_text(encoding="utf-8"))
        expected_engines = receipt["engine"]["executable_sha256"]
        for item in (engine, actual_engine):
            if not item.is_file() or sha256(item) != expected_engines.get(item.name):
                raise ValueError(f"Engine is not the pinned beta2 executable: {item}")
        if subprocess.check_output([str(engine), "--version"], text=True).strip() != receipt["engine"]["version"]:
            raise ValueError("Pinned engine version differs")
        for name in [*("tools/godot/" + script for script in CAPTURE_SCRIPTS.values()),
                     "app/tests/test_shaft_publication.gd", "app/tests/test_weather_publication.gd"]:
            before = git(["show", BASELINE + ":" + name]).replace(b"\r\n", b"\n")
            after = git(["show", args.candidate + ":" + name]).replace(b"\r\n", b"\n")
            if before != after:
                raise ValueError(f"Shared capture/test script changed since baseline: {name}")
        current, historical = tree(args.candidate), tree(BASELINE)
        # Two full app copies plus bounded headroom for both Godot import caches.
        needed = 2 * sum((ROOT / name).stat().st_size for name in current) + 3 * 1024 ** 3
        if shutil.disk_usage(out).free < needed:
            raise ValueError(f"Insufficient free space for isolated app copies and imports: need {needed} bytes")
        candidate_root, baseline_root = out / "candidate", out / "baseline"
        candidate_root.mkdir()
        baseline_root.mkdir()
        shutil.copytree(ROOT / "app", candidate_root / "app", ignore=copy_ignore)
        shutil.copy2(ROOT / ".gitattributes", candidate_root / ".gitattributes")
        inventory(candidate_root, args.candidate, current)
        shutil.copytree(candidate_root / "app", baseline_root / "app")
        reconstruct(baseline_root, current, historical, out / "baseline.index")
        baseline_initial = inventory(baseline_root, BASELINE, historical)
        if source_pins(baseline_root, pins) != {name: row["sha256"] for name, row in pins.items()}:
            raise ValueError("Historical app does not match all 19 accepted baseline pins")
        del baseline_initial
        runs = {}
        for role, project_root, commit, expected in (("baseline", baseline_root, BASELINE, historical),
                                                    ("candidate", candidate_root, args.candidate, current)):
            project = project_root / "app"
            checked(project, engine, out, role + "-import", None, "", None, out / (role + "-profile"))
            for family, script_name in CAPTURE_SCRIPTS.items():
                label = role + "-" + family
                capture = out / (label + ".json")
                before = inventory(project_root, commit, expected)
                before_file = out / (label + "-inventory-before.json")
                before_file.write_bytes(before)
                before_pins = source_pins(project_root, pins)
                engine_before, executable_before = sha256(engine), sha256(actual_engine)
                script = ROOT / "tools/godot" / script_name
                script_before = script_sha256(script)
                checker_before = script_sha256(ROOT / "tools/godot/run_checked.py")
                marker = f"failures=0 cases={2 if family == 'shaft' else 4}"
                report, log = checked(project, engine, out, label, script, marker, capture, out / (role + "-profile"))
                after = inventory(project_root, commit, expected)
                after_file = out / (label + "-inventory-after.json")
                after_file.write_bytes(after)
                after_pins = source_pins(project_root, pins)
                engine_after, executable_after = sha256(engine), sha256(actual_engine)
                script_after = script_sha256(script)
                checker_after = script_sha256(ROOT / "tools/godot/run_checked.py")
                if (before != after or before_pins != after_pins or engine_before != engine_after
                        or executable_before != executable_after or script_before != script_after
                        or checker_before != checker_after or not capture.is_file()):
                    raise ValueError(f"Inputs changed or capture missing during {label}")
                rel = lambda path: path.relative_to(out.parent).as_posix()
                runs[label] = {"commit": commit, "project_path": str(project), "engine_path": str(engine),
                               "engine_executable": str(actual_engine), "capture": rel(capture),
                               "capture_script_sha256": script_before, "checked_runner_sha256": checker_before,
                               "capture_sha256": sha256(capture), "report": rel(report), "report_sha256": sha256(report),
                               "log": rel(log), "log_sha256": sha256(log),
                               "inventory_before": rel(before_file), "inventory_after": rel(after_file),
                               "before": {"engine_sha256": engine_before, "engine_executable_sha256": executable_before,
                                          "source_inventory_sha256": sha256(before_file), "source_pins": before_pins,
                                          "capture_script_sha256": script_before, "checked_runner_sha256": checker_before},
                               "after": {"engine_sha256": engine_after, "engine_executable_sha256": executable_after,
                                         "source_inventory_sha256": sha256(after_file), "source_pins": after_pins,
                                         "capture_script_sha256": script_after, "checked_runner_sha256": checker_after},
                               "composition": {"kind": role + "-commit-v1", "base_commit": commit,
                                               "overlay_commit": None, "overlay_paths": [], "overlay_tree_ids": {}}}
        manifest = {"format": "openrc-publication-rebind-capture-v1", "platform": platform, "runs": runs,
                    "mode_validation": "git-index-only-windows" if os.name == "nt" else "git-and-posix-executable"}
        with (out / "manifest.json").open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(manifest, stream, indent=2, sort_keys=True)
            stream.write("\n")
        print(f"Captured publication evidence: {out / 'manifest.json'}")
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"Capture failed; partial evidence retained under {out}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
