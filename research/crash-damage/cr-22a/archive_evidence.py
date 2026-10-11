"""Archive a successful qualification and assert its scenario outcome matrix."""
from pathlib import Path
import argparse
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, default=ROOT / ".tools/crash-qualified-final")
args = parser.parse_args()
source = args.source.resolve()
dest = ROOT / "docs/research/crash-damage-investigations/CR-22a/evidence"
result = json.loads((source / "qualification.json").read_text())
assert result["passed"] and result["source_unchanged"]
expected = {"ugly-flown": 3, "jet-flown": 4, "scrape": 1, "wingtip": 3}
for name, level in expected.items():
    report = json.loads((source / (name + ".json")).read_text())
    stats = report["stats"]
    assert not report["failures"] and stats["report"]["class"] == level
    assert (stats["effects"]["fire"] > 0) == (name == "jet-flown")
    assert stats["wreck"]["sleeping_body_count"] == stats["wreck"]["active_body_count"]
    assert (stats["wreck"]["active_body_count"] == 1) == (name == "scrape")
    assert report["master_audio"]["captured"] and report["master_audio"]["discarded"] == 0
dest.mkdir(parents=True, exist_ok=True)
for path in source.iterdir():
    if path.suffix in {".json", ".log"} or path.name in {
        "ugly-flown-090.png", "ugly-flown-480.png", "jet-flown-090.png", "jet-flown-480.png",
        "ugly-flown-master.wav", "jet-flown-master.wav",
    }:
        shutil.copy2(path, dest / path.name)
for name in ["crash-ui-pause.log", "crash-ui-runway.log", "crash-baseline-suite.log"]:
    shutil.copy2(ROOT / ".tools" / name, dest / name)
parity = ROOT / ".tools/crash-trace-parity"
shutil.copy2(parity / "trace-parity.json", dest / "trace-parity.json")
with zipfile.ZipFile(dest / "healthy-traces.zip", "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in parity.iterdir():
        archive.write(path, path.name)
print("Archived four scenario outcomes, sleeping wrecks, native mix, focused tests and healthy traces")
