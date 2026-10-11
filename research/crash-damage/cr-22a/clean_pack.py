"""Verify crash assets/notices after importing and packing a clean disposable clone."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", required=True, type=Path)
args = parser.parse_args()
engine = str(args.godot.resolve())
work = Path(tempfile.mkdtemp(prefix="crash-clean-pack-", dir=ROOT / ".tools"))
source, clone = work / "source", work / "clone"
source.mkdir()
shutil.copytree(ROOT / "app", source / "app", ignore=shutil.ignore_patterns(".godot", "captures"))
(source / ".gitignore").write_text(".godot/\ncaptures/\n")


def run(label, command, cwd=source):
    result = subprocess.run(command, cwd=cwd, capture_output=True, timeout=180)
    log = result.stdout + result.stderr
    (work / (label + ".log")).write_bytes(log)
    if result.returncode or b"ERROR:" in log:
        raise RuntimeError(f"{label} failed; see {work}")


run("init", ["git", "init", "-q"])
run("stage", ["git", "add", "."])
run("snapshot", ["git", "-c", "user.name=Crash validation", "-c", "user.email=validation@example.invalid", "commit", "-qm", "Disposable source fixture for clean import and pack validation"])
run("clone", ["git", "clone", "--no-local", str(source), str(clone)], work)
run("import", [engine, "--headless", "--path", str(clone / "app"), "--import"], clone)
pack = work / "crash.pck"
run("export", [engine, "--headless", "--path", str(clone / "app"), "--export-pack", "Linux", str(pack)], clone)
run("check", [engine, "--headless", "--audio-driver", "Dummy", "--main-pack", str(pack), "--script", str(ROOT / "research/crash-damage/cr-22a/check_pack.gd")], clone)
evidence = ROOT / "docs/research/crash-damage-investigations/CR-22a/evidence"
for name in ["import", "export", "check"]:
    shutil.copy2(work / (name + ".log"), evidence / ("clean-pack-" + name + ".log"))
print("Clean clone imported/exported successfully; 18 crash assets/notices load from PCK")
print(work)
