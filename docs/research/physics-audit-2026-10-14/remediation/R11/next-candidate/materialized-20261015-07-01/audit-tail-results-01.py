#!/usr/bin/env python3
"""Audit negative-control return codes and Godot engine-error output for tail-01."""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys


EVIDENCE = Path(
    "/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/"
    "remediation/R11/next-candidate/materialized-20261015-07-01/diagnostic-tail-01"
)
source = json.loads((EVIDENCE / "results.json").read_text(encoding="utf-8"))
results = source["results"]
negative = [item for item in results if item["expect"] == "nonzero"]
negative_audit = []
for item in negative:
    code = item["returncode"]
    real_refusal = (
        not item["timed_out"]
        and code not in (None, 124, 137)
        and (not isinstance(code, int) or code >= 0)
    )
    log_text = Path(item["log"]).read_text(encoding="utf-8", errors="replace")
    negative_audit.append({
        "index": item["index"],
        "name": item["name"],
        "returncode": code,
        "runner_timed_out": item["timed_out"],
        "real_nonzero_refusal": real_refusal,
        "log_has_error_marker": bool(re.search(r"(?m)^(?:SCRIPT )?ERROR:", log_text)),
        "log": item["log"],
    })

error_pattern = re.compile(r"(?m)^(?:SCRIPT |SHADER )?ERROR:")
direct_engine = []
for item in results:
    command = item.get("command", [])
    if not any("Godot_v4.7.2-stable_linux.x86_64" in str(part) for part in command):
        continue
    log_text = Path(item["log"]).read_text(encoding="utf-8", errors="replace")
    matches = [line for line in log_text.splitlines() if error_pattern.match(line)]
    direct_engine.append({
        "index": item["index"],
        "name": item["name"],
        "expect": item["expect"],
        "returncode": item["returncode"],
        "status": item["status"],
        "engine_error_lines": matches,
        "log": item["log"],
    })

inner_timeout_like = [
    {"name": item["name"], "returncode": item["returncode"], "log": item["log"]}
    for item in results
    if item["returncode"] in (124, 137)
    or (isinstance(item["returncode"], int) and item["returncode"] < 0)
]
positive_with_engine_errors = [
    item for item in direct_engine
    if item["expect"] != "nonzero" and item["engine_error_lines"]
]
report = {
    "format": "R11 diagnostic tail outcome audit v1",
    "evidence": str(EVIDENCE),
    "step_count": len(results),
    "runner_summary": {
        "passed": source["passed"],
        "failed": source["failed"],
    },
    "negative_controls": negative_audit,
    "negative_controls_all_real_refusals": all(item["real_nonzero_refusal"] for item in negative_audit),
    "inner_timeout_or_signal_codes": inner_timeout_like,
    "direct_godot_commands": direct_engine,
    "positive_direct_godot_with_engine_errors": positive_with_engine_errors,
}
(EVIDENCE / "outcome-audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2))
if inner_timeout_like or positive_with_engine_errors or not report["negative_controls_all_real_refusals"]:
    sys.exit(1)
