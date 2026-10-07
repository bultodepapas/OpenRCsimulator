#!/usr/bin/env python3
"""Refresh the research inventory/snapshot and validate this documentation round.

Run from any directory. Does not run Godot, export, or alter application files.
The snapshot records current files, not retroactive proof of an earlier probe.
"""

import ast
import hashlib
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit, urlunsplit


ROUND = Path(__file__).resolve().parents[1]
ROOT = ROUND.parents[3]
PLAN = ROOT / "docs/DESKTOP-DELIVERY-PLAN.md"
LINK = re.compile(r"\[[^\]]+\]\(([^)]+)\)")


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def write(name, value):
    (ROUND / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


reports = sorted(ROUND.glob("[0-9][0-9]-*.md"))
assert len(reports) == 12
assert [p.name[:2] for p in reports] == [f"{i:02d}" for i in range(1, 13)]
sources = {}
for report in reports:
    for target in LINK.findall(report.read_text()):
        url = urlsplit(target)
        if url.scheme in ("http", "https"):
            canonical = urlunsplit((url.scheme, url.netloc, url.path, url.query, ""))
            sources.setdefault(canonical, set()).add(report.name)
write("sources.json", {
    "format": "openrc-desktop-source-inventory v1",
    "step": "DT-00-R1",
    "consulted_date": "2026-10-07",
    "scope": "References cited in reports, deduplicated without URL fragments. "
             "Not an automated availability check; access method and limits remain in each report.",
    "sources": [{"url": url, "reports": sorted(names)} for url, names in sorted(sources.items())],
})

audited = [
    "app/project.godot", "app/export.sh", "app/export_presets.cfg",
    "app/get-godot.sh", "app/get-templates.sh", ".github/workflows/ci.yml",
    "app/app_root.gd", "app/main.gd", "app/app_state/preferences.gd",
    "app/app_state/aircraft_catalog.gd", "app/app_state/build_info.gd",
    "app/addons/build_info/export_plugin.gd", "app/ui/home.gd",
    "app/ui/home_scene.gd", "app/input/rc_input.gd", "app/input/rc_calibration.gd",
    "app/input/input_report.gd", "app/input/input_report_data.gd",
    "app/sim/flight_session.gd", "app/sim/simulation.gd", "app/sim/recorder.gd",
    "app/sim/trace.gd", "app/render/frame_samples.gd", "app/render/tree_assets.gd",
    "app/render/engine_sound.gd",
]
write("audit-snapshot.json", {
    "format": "openrc-desktop-audit v2", "step": "DT-00-R1", "date": "2026-10-07",
    "head": git("rev-parse", "HEAD"),
    "describe": git("describe", "--tags", "--always", "--dirty"),
    "working_tree_status": git("status", "--porcelain=v1", "--untracked-files=all"),
    "scope": "End-of-round inspected-file inventory in a concurrently edited tree. "
             "Does not identify a clean build or replace exact source hashes in executed probes. "
             "Input-report and calibration changes belong to the input owner and were not validated here.",
    "sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in audited},
})

# Create the output before checking the README link to it.
write("validation.json", {"status": "running"})
documents = [PLAN, *sorted(ROUND.glob("*.md"))]
checked_links = set()
errors = []
for document in documents:
    for target in LINK.findall(document.read_text()):
        parsed = urlsplit(target)
        if parsed.scheme or not parsed.path:
            continue
        destination = (document.parent / unquote(parsed.path)).resolve()
        if not destination.exists():
            errors.append(f"Missing: {document.relative_to(ROOT)} -> {target}")
        checked_links.add(str(destination.relative_to(ROOT)))
ignored = subprocess.run(
    ["git", "-C", str(ROOT), "check-ignore", "--stdin"],
    input="\n".join(sorted(checked_links)) + "\n", text=True, capture_output=True,
)
assert ignored.returncode in (0, 1), ignored.stderr
if ignored.stdout.strip():
    errors.append("Ignored link targets: " + ignored.stdout.strip())
steps = re.findall(r"^\| (DT-[A-Za-z0-9-]+) \|", PLAN.read_text(), re.M)
assert len(steps) == len(set(steps))
assert "(en, rev 2)" in (ROOT / "docs/README.md").read_text().split("**Desktop delivery**")[1].splitlines()[0]
for name in ("docs/README.md", "docs/research/README.md", "LEARNINGS.md"):
    assert "desktop-delivery-investigations/DT-00-R1/README.md" in (ROOT / name).read_text(), name
scripts = sorted((ROUND / "probes").glob("*.py"))
for script in scripts:
    ast.parse(script.read_text(), filename=str(script))
for path in [PLAN, *sorted(ROUND.rglob("*"))]:
    if path.is_file() and path.suffix in (".md", ".py", ".json"):
        if path.suffix == ".json":
            json.loads(path.read_text())
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if line.rstrip() != line:
                errors.append(f"Trailing whitespace: {path.relative_to(ROOT)}:{number}")
result = {
    "step": "DT-00-R1", "date": "2026-10-07", "passed": not errors,
    "reports": len(reports), "external_references": len(sources),
    "documents_checked": len(documents), "local_file_targets": len(checked_links),
    "unique_plan_steps": len(steps), "python_scripts_parsed": len(scripts),
    "json_parsing": "passed", "registry_revision": 2,
    "errors": errors,
    "limits": "Checks file targets, not Markdown anchors or external URL availability. "
              "Does not run the app or infer native/benchmark acceptance.",
}
write("validation.json", result)
print(json.dumps(result, indent=2))
raise SystemExit(0 if not errors else 1)
