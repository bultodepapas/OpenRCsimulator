"""Run this audit's diagnostic probes serially with the existing checked runner.

These are counterexample witnesses, not tests claiming the production defects
have been repaired. Native refusal has an explicitly reduced-coverage outcome.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


CASES = {
    "box": ("scenery_shell.gd", "SCENERY_SHELL", False),
    "capsule": ("capsule_seam.gd", "CAPSULE_SEAM", False),
    "race": ("race_replay_outbox.gd", "RACE_OUTBOX_COUNTEREXAMPLE=true", True),
    "identity": ("unresolved_replay_identity.gd", "UNRESOLVED_ADAPTER_COUNTEREXAMPLE=true", True),
    "downwash": ("downwash_transport.gd", "DOWNWASH_TRANSPORT", False),
    "fold": ("fold_probe.gd", "CORSAIR_FOLD_CADENCE_CONFIRMED", False),
    "fold-scene": ("fold_scene_probe.gd", "CORSAIR_FOLD_SCENE_CONFIRMED", False),
    "hud": ("hud_probe.gd", "HUD_EAGER_CONTROLS_CONFIRMED", False),
    "lighting": ("lighting_probe.gd", "HIDDEN_RGB_SHADER_WRITES_CONFIRMED", False),
    "native-refusal": ("prepare_refusal_probe.gd", "REFUSAL_PROBE_COMPLETED", False),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True,
                        help="The imported project's pinned official engine executable")
    parser.add_argument("--case", choices=["all", *CASES], default="all")
    parser.add_argument("--out", type=Path,
                        help="New output directory; default is a unique directory under repo/tmp")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    repo = here.parents[1]
    engine = args.godot.resolve()
    if not engine.is_file():
        parser.error("--godot must name the existing pinned executable")
    if args.out:
        out = args.out.resolve()
        out.mkdir(parents=True, exist_ok=False)
    else:
        (repo / "tmp").mkdir(exist_ok=True)
        out = Path(tempfile.mkdtemp(prefix="swarm-audit-2026-11-28-", dir=repo / "tmp"))
    version = subprocess.check_output([str(engine), "--version"], text=True).strip()
    if version != "4.8.beta2.official.cafc17a19":
        parser.error("The audited probes require 4.8.beta2.official.cafc17a19")
    summary = {"audited_source": "71306784a250d634854f0c8bab3a927cc46a61b8",
               "checkout_head": subprocess.check_output(
                   ["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
               "engine": version, "results": []}
    selected = CASES if args.case == "all" else {args.case: CASES[args.case]}
    failed = False
    for name, (filename, marker, needs_output) in selected.items():
        script = here / "probes" / filename
        checked = out / name
        command = [sys.executable, str(repo / "tools/godot/run_checked.py"),
                   "--label", "swarm-" + name, "--timeout", "120",
                   "--require-text", marker, "--out-dir", str(checked), "--",
                   str(engine), "--headless", "--path", str(repo / "app"),
                   "--audio-driver", "Dummy", "--script", str(script)]
        if needs_output:
            command.extend(["--", "--out=" + str(out / (name + "-data"))])
        with (out / (name + "-console.log")).open("wb") as console:
            result = subprocess.run(command, cwd=repo, stdout=console,
                                    stderr=subprocess.STDOUT, check=False)
        reports = list(checked.glob("*/report.json"))
        if len(reports) != 1:
            raise RuntimeError("Expected exactly one checked receipt for " + name)
        report = json.loads(reports[0].read_text())
        log = reports[0].with_name("engine.log").read_text()
        coverage = ("counterexample_or_observation_reproduced"
                    if result.returncode == 0 and report["ok"]
                    else "probe_failed_or_inconclusive")
        if name == "native-refusal":
            if any(line.startswith("REFUSAL_NATIVE_RESULT ") for line in log.splitlines()):
                # Native may have executed and violated the expected postcondition.
                # Retain both that coverage and the separate failed result.
                coverage = "qualified_native_exercised"
            elif report["ok"] and any(line.startswith("REFUSAL_NATIVE_UNAVAILABLE ")
                                      for line in log.splitlines()):
                coverage = "native_unavailable_outer_refusal_unverified"
            else:
                coverage = "probe_failed_or_inconclusive"
        row = {key: report[key] for key in
               ["ok", "exit_code", "reason", "counts", "elapsed_seconds", "log_sha256"]}
        row.update({"case": name, "coverage": coverage,
                    "probe": str(script.relative_to(repo)),
                    "probe_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
                    "report": str(reports[0].relative_to(out))})
        summary["results"].append(row)
        failed |= result.returncode != 0 or not report["ok"]
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"{name}: {'PASS' if report['ok'] else 'FAIL'}; {coverage}", flush=True)
    print("Evidence: " + str(out), flush=True)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
