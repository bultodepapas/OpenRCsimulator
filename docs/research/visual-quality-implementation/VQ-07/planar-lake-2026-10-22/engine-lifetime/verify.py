"""Verify retained lifecycle and endpoint evidence; does not launch Godot."""
from pathlib import Path
import gzip
import json
import re
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(Path.cwd() / "research/performance"))
from native_summary import validate_native_report


def receipt(label):
    matches = list((HERE / "checks").glob(label + "-*/report.json"))
    assert len(matches) == 1, (label, matches)
    path = matches[0]
    data = json.loads(path.read_text())
    assert data["ok"] and data["counts"]["error"] == 0, label
    return path.with_name("engine.log").read_text()


for label, expected in {
    "minimal-no-probe": 0, "minimal-probe": 7,
    "isolated-probe-one": 7, "isolated-probe-four": 28,
    "isolated-no-probe-four": 0, "explicit-once-four": 28,
}.items():
    log = receipt(label)
    counts = re.findall(r'(\d+) RIDs of type "Texture" were leaked', log)
    assert [int(n) for n in counts] == ([expected] if expected else []), label
    print(label, "leaked Texture RIDs:", expected)

for case in ("hold", "failsafe", "resumed"):
    receipt("endpoint-" + case)
    raw = HERE / (case + ".json")
    data = json.loads(raw.read_bytes() if raw.exists() else gzip.decompress(Path(str(raw) + ".gz").read_bytes()))
    errors, _ = validate_native_report(data)
    assert not errors, errors
    context = data["session_at_report"]
    assert context["scope"] == "end of collection only; not pause history"
    assert context["holds"] == (["endpoint diagnostic hold"] if case == "hold" else [])
    assert context["pause_reason"] == ("endpoint diagnostic failsafe" if case == "failsafe" else "")
    assert context["crashed"] is False
    assert data["simulation"]["paused"] == (case != "resumed")
    assert data["camera"]["viewport"] == [1920, 1080]
    print(case, context)

print("Retained lifecycle and endpoint evidence verified; no performance qualification claimed.")
