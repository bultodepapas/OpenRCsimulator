#!/usr/bin/env python3
"""AFC-02-R3: re-bind the AI companion solver qualification after a physics/sim/failures edit.

The companion profile pins a normalized identity of app/physics, app/sim and app/failures. This tool replays
the retained companion tapes (tools/companions/qualification.json) in candidate mode on two disposable
project copies that differ only in those directories: the accepted revision and the current tree. Identical
CSVs show that the edit leaves the qualified aircraft's behaviour unchanged on these tapes; --accept then
re-pins the profile and writes a receipt. Any difference stops: that is a behaviour change and needs a new
qualification, not a re-bind. Parity on these tapes is not exact replay or physical validation.

    python3 tools/companions/rebind.py             # report only
    python3 tools/companions/rebind.py --accept    # re-pin when every tape is identical

Exit codes: 0 qualified (already current, or identical), 1 behaviour changed, 2 setup or replay error.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import csv
import datetime
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUALIFICATION = ROOT / "tools" / "companions" / "qualification.json"
IDENTITY_SCRIPT = ROOT / "tools" / "companions" / "solver_identity.gd"
RECEIPT_FORMAT = "openrc-ai-solver-rebind v1"
COPY_IGNORE = shutil.ignore_patterns("captures")
DIFF_COLUMNS_REPORTED = 5


class SetupError(RuntimeError):
    """The comparison could not run; nothing about behaviour is known."""


def run(command: list[str], cwd: Path = ROOT, timeout: int = 600) -> subprocess.CompletedProcess:
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=timeout, env=env)


def git(*args: str) -> str:
    result = run(["git", *args])
    if result.returncode:
        raise SetupError(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def default_godot() -> str:
    result = run([str(ROOT / "app" / "get-godot.sh")])
    if result.returncode or not result.stdout.strip():
        raise SetupError("app/get-godot.sh did not return the pinned Godot binary")
    return result.stdout.strip().splitlines()[-1]


def solver_identity(godot: str, app: Path) -> str:
    result = run([godot, "--headless", "--path", str(app), "--audio-driver", "Dummy", "--script", str(IDENTITY_SCRIPT)])
    for line in result.stdout.splitlines():
        if line.startswith("SOLVER_IDENTITY "):
            identity = json.loads(line.removeprefix("SOLVER_IDENTITY "))
            if identity.get("ok"):
                return str(identity["sha256"])
            raise SetupError(f"solver identity unavailable in {app}: {identity.get('errors')}")
    raise SetupError(f"no solver identity from {app}:\n{result.stdout[-2000:]}{result.stderr[-2000:]}")


def pinned_identity(profile: Path) -> str:
    return str(json.loads(profile.read_text(encoding="utf-8"))["solver"]["sha256"])


def build_baseline(workspace: Path, rev: str, directories: list[str]) -> Path:
    """Current project with only the solver directories taken from the accepted revision."""
    base = workspace / "base"
    shutil.copytree(ROOT / "app", base / "app", symlinks=True, ignore=COPY_IGNORE)
    shutil.copytree(ROOT / "tools" / "flight_log", base / "tools" / "flight_log", symlinks=True)
    for directory in directories:
        shutil.rmtree(base / directory)
    archive = workspace / "base-solver.tar"
    with archive.open("wb") as handle:
        result = subprocess.run(["git", "archive", rev, *directories], cwd=ROOT, stdout=handle, stderr=subprocess.PIPE)
    if result.returncode:
        raise SetupError(f"git archive {rev}: {result.stderr.decode(errors='replace').strip()}")
    with tarfile.open(archive) as tar:
        tar.extractall(base, filter="data")
    archive.unlink()
    return base


def replay(godot: str, project: Path, tape: Path, candidate: str, out: Path) -> dict:
    command = [sys.executable, str(project / "tools" / "flight_log" / "flight_log.py"), "replay", str(tape),
               "--godot", godot, "--candidate", str(project / candidate), "--out", str(out)]
    result = run(command, timeout=900)
    report_path, csv_path = out / "replay.json", out / "flight.csv"
    report = json.loads(report_path.read_text()) if report_path.is_file() else {}
    if result.returncode or not report.get("complete") or not csv_path.is_file():
        log = (out / "godot.log").read_text(errors="replace") if (out / "godot.log").is_file() else ""
        detail = (result.stdout + result.stderr + log).strip().splitlines()
        raise SetupError(f"replay of {tape.name} in {project.name} failed: {' | '.join(detail[-4:])}")
    return {"csv": csv_path, "csv_sha256": sha256_file(csv_path), "rows": sum(1 for _ in csv_path.open()) - 1}


def csv_difference(base_csv: Path, head_csv: Path) -> dict:
    """First differing row and the columns with the largest absolute differences."""
    with base_csv.open(newline="") as a, head_csv.open(newline="") as b:
        base_rows, head_rows = list(csv.reader(a)), list(csv.reader(b))
    if not base_rows or not head_rows or base_rows[0] != head_rows[0]:
        return {"header_changed": True, "base_columns": len(base_rows[0]) if base_rows else 0,
                "head_columns": len(head_rows[0]) if head_rows else 0}
    header = base_rows[0]
    first_row, worst = None, {}
    for index, (left, right) in enumerate(zip(base_rows[1:], head_rows[1:]), start=1):
        if left == right:
            continue
        first_row = index if first_row is None else first_row
        for column, (x, y) in enumerate(zip(left, right)):
            if x == y:
                continue
            try:
                delta = abs(float(x) - float(y))
            except ValueError:
                delta = math.inf
            name = header[column] if column < len(header) else str(column)
            worst[name] = max(worst.get(name, 0.0), delta)
    largest = sorted(worst.items(), key=lambda item: -item[1])[:DIFF_COLUMNS_REPORTED]
    return {"header_changed": False, "rows_base": len(base_rows) - 1, "rows_head": len(head_rows) - 1,
            "first_differing_row": first_row, "columns_changed": len(worst),
            "largest_abs_differences": {name: (None if math.isinf(value) else value) for name, value in largest}}


def solver_tree_is_committed(directories: list[str]) -> bool:
    tracked = run(["git", "diff", "--quiet", "HEAD", "--", *directories]).returncode == 0
    untracked = git("ls-files", "--others", "--exclude-standard", "--", *directories)
    return tracked and not untracked


def repin_profile(profile: Path, old: str, new: str) -> None:
    text = profile.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SetupError(f"{profile} must contain the pinned identity exactly once")
    data = json.loads(text.replace(old, new))
    if data["solver"]["sha256"] != new:
        raise SetupError(f"{profile}: the replaced identity is not the solver pin")
    profile.write_text(text.replace(old, new), encoding="utf-8")


def compare(godot: str, qualification: dict, jobs: int, keep: bool,
            workspace_root: Path | None = None) -> tuple[list[dict], str]:
    accepted = qualification["accepted"]
    directories = qualification["solver_directories"]
    parent = (workspace_root if workspace_root is not None else ROOT / "tmp").resolve()
    parent.mkdir(parents=True, exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix="companion-rebind-", dir=parent))
    try:
        base = build_baseline(workspace, accepted["rev"], directories)
        base_identity = solver_identity(godot, base / "app")
        if base_identity != accepted["solver_sha256"]:
            raise SetupError(f"accepted rev {accepted['rev'][:8]} reproduces {base_identity[:8]}, "
                             f"not the accepted {accepted['solver_sha256'][:8]}; fix qualification.json")
        tapes = [ROOT / tape for tape in qualification["tapes"]]
        missing = [str(tape) for tape in tapes if not tape.is_file()]
        if missing:
            raise SetupError(f"missing tapes: {missing}")
        work = {(side, tape): (project, workspace / side / tape.stem)
                for tape in tapes for side, project in (("base", base), ("head", ROOT))}
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            futures = {key: pool.submit(replay, godot, project, key[1], qualification["candidate_aircraft"], out)
                       for key, (project, out) in work.items()}
            outputs = {key: future.result() for key, future in futures.items()}
        results = []
        for tape in tapes:
            base_out, head_out = outputs[("base", tape)], outputs[("head", tape)]
            identical = base_out["csv_sha256"] == head_out["csv_sha256"]
            entry = {"tape": str(tape.relative_to(ROOT)), "orfl_sha256": sha256_file(tape),
                     "rows": head_out["rows"], "base_csv_sha256": base_out["csv_sha256"],
                     "head_csv_sha256": head_out["csv_sha256"], "identical": identical}
            if not identical:
                entry["difference"] = csv_difference(base_out["csv"], head_out["csv"])
            results.append(entry)
        return results, str(workspace)
    finally:
        if not keep:
            shutil.rmtree(workspace, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--accept", action="store_true", help="re-pin the profile when every tape is identical")
    parser.add_argument("--godot", help="Godot executable (default: app/get-godot.sh)")
    parser.add_argument("--jobs", type=int, default=max(1, min(6, (os.cpu_count() or 2) // 2)))
    parser.add_argument("--report", type=Path, help="also write the full JSON report to this new file")
    parser.add_argument("--keep", action="store_true", help="keep the disposable copies under tmp/")
    parser.add_argument("--workspace-root", type=Path,
                        help="parent for disposable project copies (default: repository tmp/)")
    args = parser.parse_args()
    try:
        qualification = json.loads(QUALIFICATION.read_text(encoding="utf-8"))
        profile = ROOT / qualification["profile"]
        godot = args.godot or default_godot()
        pinned = pinned_identity(profile)
        if pinned != qualification["accepted"]["solver_sha256"]:
            raise SetupError(f"profile pins {pinned[:8]} but qualification.json accepts "
                             f"{qualification['accepted']['solver_sha256'][:8]}; they must agree")
        current = solver_identity(godot, ROOT / "app")
        if current == pinned:
            print(f"Companion qualification is current ({current[:8]}); nothing to re-bind.")
            return 0
        print(f"Solver identity changed: accepted {pinned[:8]} -> current {current[:8]}. "
              f"Replaying {len(qualification['tapes'])} tapes on both sides...", flush=True)
        results, workspace = compare(godot, qualification, args.jobs, args.keep, args.workspace_root)
    except (SetupError, OSError, KeyError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"rebind: setup error: {error}", file=sys.stderr)
        return 2

    identical = all(entry["identical"] for entry in results)
    for entry in results:
        status = "identical" if entry["identical"] else "CHANGED"
        print(f"  {status:9} {Path(entry['tape']).stem} ({entry['rows']} rows)")
        if not entry["identical"]:
            print(f"            {json.dumps(entry['difference'])}")
    changed_sources = git("diff", "--name-only", qualification["accepted"]["rev"], "--",
                          *qualification["solver_directories"]).splitlines()
    report = {"format": RECEIPT_FORMAT, "date": datetime.date.today().isoformat(),
              "accepted_before": qualification["accepted"], "current_solver_sha256": current,
              "head": git("rev-parse", "HEAD"), "solver_tree_committed": solver_tree_is_committed(
                  qualification["solver_directories"]), "changed_sources": changed_sources,
              "candidate_aircraft": qualification["candidate_aircraft"], "identical": identical, "tapes": results,
              "method": "Candidate replays of the retained tapes on two disposable copies differing only in the "
                        "solver directories (accepted rev vs current tree); CSV bytes compared.",
              "limits": "Parity on these tapes only; not exact replay, not a new qualification, not physical "
                        "validation."}
    if args.keep:
        report["workspace"] = workspace
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if not identical:
        print("Behaviour changed on the tapes above: this needs a new companion qualification, not a re-bind.")
        return 1
    if not args.accept:
        print("All tapes identical. Commit the physics change, then re-run with --accept to re-pin.")
        return 0
    if not report["solver_tree_committed"]:
        print("rebind: commit app/physics, app/sim and app/failures first; the accepted rev must hold them.",
              file=sys.stderr)
        return 2
    try:
        repin_profile(profile, pinned, current)
    except SetupError as error:
        print(f"rebind: {error}", file=sys.stderr)
        return 2
    qualification["accepted"] = {"solver_sha256": current, "rev": report["head"]}
    QUALIFICATION.write_text(json.dumps(qualification, indent=2) + "\n", encoding="utf-8")
    receipts = ROOT / qualification["receipts"]
    receipts.mkdir(parents=True, exist_ok=True)
    receipt = receipts / f"{report['date']}-{pinned[:8]}-to-{current[:8]}.json"
    receipt.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Re-pinned {profile.relative_to(ROOT)} to {current[:8]}; receipt {receipt.relative_to(ROOT)}.")
    print("Commit the profile, tools/companions/qualification.json and the receipt together.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
