#!/usr/bin/env python3
"""GP-07: do the AI companion's retained tapes fly the same with the GP-07 physics and the regenerated Stik hull?

tools/companions/rebind.py compares only the solver directories; the companion profile also pins the Stik's aircraft
data, which GP-07b changed (crash hull fields only). This replays the same tapes in candidate mode on (A) a copy with
the accepted solver revision and the Stik data from git HEAD before GP-07 (`--base-data-rev`) and (B) the current
tree, and compares CSV bytes. Identical tapes support re-pinning both identities; any difference needs a new
qualification. Parity on these airborne tapes only, as rebind.py states.

Usage: python3 research/ground-physics/gp07/companion_ab.py --base-data-rev <rev> [--report out.json]
"""
import argparse
import hashlib
import concurrent.futures
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "companions"))
import rebind  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--base-data-rev", required=True)
    ap.add_argument("--base-solver-rev", help="revision for the base solver directories (default: the accepted rev); "
                    "it must reproduce the accepted solver identity")
    ap.add_argument("--report", type=Path)
    ap.add_argument("--jobs", type=int, default=3)
    args = ap.parse_args()
    qualification = json.loads(rebind.QUALIFICATION.read_text(encoding="utf-8"))
    godot = rebind.default_godot()
    data = qualification["candidate_aircraft"]
    workspace = Path(tempfile.mkdtemp(prefix="gp07-companion-ab-", dir=ROOT / "tmp"))
    try:
        base = rebind.build_baseline(workspace, args.base_solver_rev or qualification["accepted"]["rev"],
                                     qualification["solver_directories"])
        base_identity = rebind.solver_identity(godot, base / "app")
        if base_identity != qualification["accepted"]["solver_sha256"]:
            print(f"base solver {base_identity[:8]} is not the accepted {qualification['accepted']['solver_sha256'][:8]}")
            return 2
        old = subprocess.run(["git", "show", f"{args.base_data_rev}:{data}"], cwd=ROOT, capture_output=True, check=True).stdout
        (base / data).write_bytes(old)
        tapes = [ROOT / tape for tape in qualification["tapes"]]
        work = {(side, tape): (project, workspace / side / tape.stem)
                for tape in tapes for side, project in (("base", base), ("head", ROOT))}
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = {key: pool.submit(rebind.replay, godot, project, key[1], data, out) for key, (project, out) in work.items()}
            outputs = {key: future.result() for key, future in futures.items()}
        results = []
        for tape in tapes:
            a, b = outputs[("base", tape)], outputs[("head", tape)]
            entry = {"tape": str(tape.relative_to(ROOT)), "rows": b["rows"], "identical": a["csv_sha256"] == b["csv_sha256"],
                     "base_csv_sha256": a["csv_sha256"], "head_csv_sha256": b["csv_sha256"]}
            if not entry["identical"]:
                entry["difference"] = rebind.csv_difference(a["csv"], b["csv"])
            results.append(entry)
            print(("identical " if entry["identical"] else "CHANGED   ") + Path(entry["tape"]).stem + f" ({entry['rows']} rows)")
        report = {"format": "openrc-gp07-companion-ab v1", "accepted_solver": qualification["accepted"],
                  "base_solver_rev": args.base_solver_rev or qualification["accepted"]["rev"], "base_solver_sha256": base_identity,
                  "base_aircraft_data_rev": args.base_data_rev,
                  "base_aircraft_data_sha256": hashlib.sha256(old).hexdigest(),
                  "head_aircraft_data_sha256": rebind.sha256_file(ROOT / data),
                  "head_solver_sha256": rebind.solver_identity(godot, ROOT / "app"),
                  "identical": all(r["identical"] for r in results), "tapes": results,
                  "limits": "Airborne companion tapes only; not exact replay, a new qualification or physical validation."}
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print("all identical" if report["identical"] else "behaviour changed")
        return 0 if report["identical"] else 1
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
