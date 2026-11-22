#!/usr/bin/env python3
"""Run retained second-pass probes against a stable checkout, using synthetic data.

Exit zero means all requested baseline signatures reproduced, not that telemetry
is fixed. --godot adds the checked isolated client probe; --measure-rollup adds
the bounded local measurement series. No deployed service is contacted.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def client_probe(root, here, output, executable):
    work = Path(tempfile.mkdtemp(prefix="isolated-client-", dir=output))
    project = work / "app"
    project.mkdir()
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Telemetry second-pass audit"\n'
        'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="openrc-audit-round2"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    name = "errors_only_idle_probe.gd"
    pending = [here / name]
    seen = set()
    manifest = {}
    while pending:
        source = pending.pop().resolve()
        if source in seen:
            continue
        seen.add(source)
        manifest[str(source.relative_to(root))] = hashlib.sha256(source.read_bytes()).hexdigest()
        destination = (project / source.relative_to(root / "app")
                       if source.is_relative_to(root / "app") else project / "audit_probes" / source.name)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        references = re.findall(r'(?:preload|load)\(\s*["\']res://([^"\']+)["\']\s*\)',
                                source.read_text(encoding="utf-8"))
        for reference in references:
            dependency = (root / "app" / reference).resolve()
            if not dependency.is_relative_to(root / "app") or not dependency.is_file():
                raise ValueError(f"unresolved source dependency: {reference}")
            pending.append(dependency)
    write_json(output / "client-source-sha256.json", manifest)
    sys.path.insert(0, str(root))
    from tools.godot.run_checked import run_checked

    command = [str(executable), "--headless", "--path", str(project), "--audio-driver", "Dummy"]
    outcomes = []
    imported = run_checked(command + ["--import"], out_dir=output / "client-logs",
                           timeout=60, label="round2-import")
    outcomes.append({"probe": "isolated-import", **imported})
    if imported["ok"]:
        report = run_checked(command + ["--script", f"res://audit_probes/{name}"],
                             out_dir=output / "client-logs", timeout=45,
                             label="errors-only-idle", required=["REPRODUCED:"])
        outcomes.append({"probe": name, **report})
    write_json(output / "client-results.json", outcomes)
    return all(result["ok"] for result in outcomes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--godot", type=Path,
                        help="verified repository-pinned engine; existing admission checks remain active")
    parser.add_argument("--measure-rollup", action="store_true")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[3]
    output = args.out.resolve()
    if output.is_relative_to(root):
        parser.error("--out must be outside the repository")
    if output.exists():
        parser.error("choose a fresh --out directory to preserve earlier evidence")
    if args.godot and not args.godot.resolve().is_file():
        parser.error("--godot must identify the verified repository-pinned executable")
    output.mkdir(parents=True)
    temporary = output / "temp"
    temporary.mkdir()
    env = dict(os.environ, TMPDIR=str(temporary), TEMP=str(temporary), TMP=str(temporary),
               PYTHONDONTWRITEBYTECODE="1")
    outcomes = []
    for name, filename in (("receiver_boundaries_probe.py", "receiver-boundaries.json"),
                           ("operations_probe.py", "operations-result.json")):
        run = subprocess.run([sys.executable, str(here / name), "--repo", str(root)],
                             env=env, text=True, capture_output=True, timeout=60)
        (output / f"{name}.stdout.log").write_text(run.stdout, encoding="utf-8")
        (output / f"{name}.stderr.log").write_text(run.stderr, encoding="utf-8")
        ok = run.returncode == 0
        if ok:
            write_json(output / filename, json.loads(run.stdout))
        outcomes.append({"probe": name, "ok": ok, "exit_code": run.returncode})
        print(f"{name}: {'reproduced' if ok else 'FAILED'}", flush=True)
    if args.godot:
        # The fixture uses no player profile or real sender. The checked runner
        # owns engine launch/admission; its process log is part of the evidence.
        ok = client_probe(root, here, output, args.godot.resolve())
        outcomes.append({"probe": "errors_only_idle_probe.gd", "ok": ok})
        print(f"errors_only_idle_probe.gd: {'reproduced' if ok else 'FAILED'}", flush=True)
    if args.measure_rollup:
        run = subprocess.run([sys.executable, str(here / "rollup_cost_probe.py"), "--repo", str(root),
                              "--out", str(output / "rollup-cost.json")],
                             env=env, text=True, capture_output=True, timeout=600)
        (output / "rollup-cost.stdout.log").write_text(run.stdout, encoding="utf-8")
        (output / "rollup-cost.stderr.log").write_text(run.stderr, encoding="utf-8")
        outcomes.append({"probe": "rollup_cost_probe.py", "ok": run.returncode == 0,
                         "exit_code": run.returncode})
    write_json(output / "results.json", {"python": sys.version.split()[0], "outcomes": outcomes,
        "scope": "Synthetic local baseline counterexamples; no fix or production acceptance claim."})
    return 0 if all(item["ok"] for item in outcomes) else 1


if __name__ == "__main__":
    raise SystemExit(main())
