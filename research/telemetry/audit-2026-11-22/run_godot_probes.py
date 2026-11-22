#!/usr/bin/env python3
"""Copy exact source dependencies to a disposable project and run audit probes.

Exit zero means the baseline defects reproduced, not that telemetry is correct.
Use the repository-pinned Godot returned by app/get-godot.sh. The normal checked
runner and any host-admission enforcement remain active. No project/user profile
or production endpoint is used. Logs and the source hash manifest stay in --out.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[2]
    output = args.out.resolve()
    if output.is_relative_to(root):
        parser.error("--out must be outside the repository")
    if not args.godot.resolve().is_file():
        parser.error("--godot must identify the verified repository-pinned executable")
    output.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="telemetry-audit-", dir=output))
    project = work / "app"
    project.mkdir()
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Telemetry audit"\n'
        'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="openrc-audit-isolated"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    names = ["context_boundary_probe", "epoch_boundary_probe", "crash_revision_probe",
             "pending_age_probe", "inflight_ttl_probe", "consent_failure_probe"]
    pending = [here / f"{name}.gd" for name in names]
    seen = set()
    manifest = {}
    while pending:
        source = pending.pop().resolve()
        if source in seen:
            continue
        seen.add(source)
        relative = source.relative_to(root)
        manifest[str(relative)] = hashlib.sha256(source.read_bytes()).hexdigest()
        if source.is_relative_to(root / "app"):
            destination = project / source.relative_to(root / "app")
        else:
            destination = project / "audit_probes" / source.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        references = re.findall(r'(?:preload|load)\(\s*["\']res://([^"\']+)["\']\s*\)',
                                source.read_text(encoding="utf-8"))
        for reference in references:
            dependency = (root / "app" / reference).resolve()
            if not dependency.is_relative_to(root / "app") or not dependency.is_file():
                raise ValueError(f"unresolved source dependency: {reference}")
            pending.append(dependency)
    (output / "source-sha256.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                                              encoding="utf-8")
    sys.path.insert(0, str(root))
    from tools.godot.run_checked import run_checked

    command = [str(args.godot.resolve()), "--headless", "--path", str(project), "--audio-driver", "Dummy"]
    outcomes = []
    imported = run_checked(command + ["--import"], out_dir=output / "logs", timeout=60,
                           label="isolated-import")
    outcomes.append({"probe": "isolated-import", **imported})
    if imported["ok"]:
        for name in names:
            extra = []
            locked = None
            if name == "consent_failure_probe":
                if os.name != "posix" or os.geteuid() == 0:
                    outcomes.append({"probe": name, "status": "skipped",
                                     "reason": "requires a non-root POSIX user"})
                    continue
                locked = work / "synthetic-consent"
                locked.mkdir()
                consent = locked / "grant.cfg"
                contract = (root / "app/telemetry/telemetry_contract.gd").read_text(encoding="utf-8")
                notice = re.search(r'const NOTICE_VERSION\s*:?=\s*"([^"]+)"', contract).group(1)
                consent.write_text('[telemetry]\nformat="openrc-telemetry-consent v1"\n'
                                   f'choice="enabled"\nnotice="{notice}"\n', encoding="utf-8")
                locked.chmod(0o555)
                extra = ["--", f"--consent-path={consent}"]
            try:
                report = run_checked(command + ["--script", f"res://audit_probes/{name}.gd"] + extra,
                                     out_dir=output / "logs", timeout=45, label=name,
                                     required=["REPRODUCED:"])
                outcomes.append({"probe": name, **report})
                print(f"{name}: {report['reason']}", flush=True)
            finally:
                if locked is not None:
                    locked.chmod(0o755)
    (output / "results.json").write_text(json.dumps(outcomes, indent=2) + "\n", encoding="utf-8")
    return 0 if all(item.get("ok") or item.get("status") == "skipped" for item in outcomes) else 1


if __name__ == "__main__":
    raise SystemExit(main())
