#!/usr/bin/env python3
"""Refresh DT-00-R2 research metadata and validate documentation, without running the app."""

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
assert len(reports) == 12, f"Expected 12 reports, found {len(reports)}"
assert [p.name[:2] for p in reports] == [f"{i:02d}" for i in range(1, 13)]
sources = {}
for report in reports:
    for target in LINK.findall(report.read_text()):
        url = urlsplit(target)
        if url.scheme in ("http", "https"):
            canonical = urlunsplit((url.scheme, url.netloc, url.path, url.query, ""))
            sources.setdefault(canonical, set()).add(report.name)
write("sources.json", {
    "format": "openrc-desktop-source-inventory v1", "step": "DT-00-R2",
    "consulted_date": "2026-10-07",
    "scope": "Cited references deduplicated without URL fragments; access limits remain in reports. "
             "Not an automated remote availability check.",
    "sources": [{"url": url, "reports": sorted(names)} for url, names in sorted(sources.items())],
})
audited = [
    "app/project.godot", "app/export.sh", "app/export_presets.cfg", "app/get-godot.sh",
    "app/get-templates.sh", "app/test.sh", ".github/workflows/ci.yml",
    "app/tests/check_macos_export.py", "app/tests/check_trimmed_flight.py",
    "app/tests/replay_policy.gd", "app/tests/bench_physics.gd",
    "app/app_root.gd", "app/main.gd", "app/render/engine_sound.gd",
    "app/render/frame_samples.gd", "app/render/tree_assets.gd",
    "app/app_state/build_info.gd", "app/input/rc_input.gd", "app/input/rc_calibration.gd",
    "app/input/input_report.gd", "app/sim/simulation.gd", "app/sim/flight_session.gd",
    "research/native-slipstream/build.py", "research/native-slipstream/toolchain-lock.json",
]
scripts = sorted((ROUND / "probes").glob("*.py"))
write("audit-snapshot.json", {
    "format": "openrc-desktop-audit v3", "step": "DT-00-R2", "date": "2026-10-07",
    "head": git("rev-parse", "HEAD"), "describe": git("describe", "--tags", "--always", "--dirty"),
    "scope": "End-of-round source/probe inventory in a concurrent working tree. "
             "Not a clean release candidate or Mac execution result. "
             "Existing ignored export metadata has its own artifact digest, unknown source provenance.",
    "working_tree_status": git("status", "--porcelain=v1", "--untracked-files=all"),
    "source_sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in audited},
    "probe_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in scripts},
})
write("validation.json", {"status": "running"})
documents = [PLAN, *sorted(ROUND.glob("*.md"))]
targets, errors = set(), []
for document in documents:
    for target in LINK.findall(document.read_text()):
        parsed = urlsplit(target)
        if parsed.scheme or not parsed.path:
            continue
        destination = (document.parent / unquote(parsed.path)).resolve()
        if not destination.exists():
            errors.append(f"Missing: {document.relative_to(ROOT)} -> {target}")
        targets.add(str(destination.relative_to(ROOT)))
ignored = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--stdin"],
                         input="\n".join(sorted(targets)) + "\n", text=True, capture_output=True)
assert ignored.returncode in (0, 1), ignored.stderr
if ignored.stdout.strip():
    errors.append("Ignored targets: " + ignored.stdout.strip())
steps = re.findall(r"^\| (DT-[A-Za-z0-9-]+) \|", PLAN.read_text(), re.M)
assert len(steps) == len(set(steps))
assert "Revision 3" in PLAN.read_text()
registry = (ROOT / "docs/README.md").read_text().split("**Desktop delivery**")[1].splitlines()[0]
assert "(en, rev 3)" in registry
for name in ("docs/README.md", "docs/research/README.md", "LEARNINGS.md"):
    assert "desktop-delivery-investigations/DT-00-R2/README.md" in (ROOT / name).read_text(), name
for script in scripts:
    ast.parse(script.read_text(), filename=str(script))
for path in [PLAN, *sorted(ROUND.rglob("*"))]:
    if path.is_file() and path.suffix in (".md", ".py", ".json"):
        if path.suffix == ".json":
            json.loads(path.read_text())
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if line.rstrip() != line:
                errors.append(f"Trailing whitespace: {path.relative_to(ROOT)}:{number}")
result = {"step": "DT-00-R2", "date": "2026-10-07", "passed": not errors,
          "reports": len(reports), "external_references": len(sources),
          "documents_checked": len(documents), "local_targets": len(targets),
          "unique_plan_steps": len(steps), "python_scripts_parsed": len(scripts),
          "json_parsing": "passed", "registry_revision": 3, "errors": errors,
          "limits": "File targets only, not Markdown anchors/remote availability. No native Mac or app checks."}
write("validation.json", result)
print(json.dumps(result, indent=2))
raise SystemExit(0 if not errors else 1)
