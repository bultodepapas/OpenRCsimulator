"""Scratch: interleaved native loading A/B for the A33 world resource hold (End flight -> Home)."""
import os
import subprocess
from pathlib import Path

REPO = Path(r"C:\DEVELOPMENT\OpenRCsimulator")
APP = REPO / "app" / "app_root.gd"
GODOT = REPO / ".tools" / "Godot_v4.8-beta2_win64_console.exe"
OUT = Path("U:/loadab-a33-2")
OUT.mkdir(exist_ok=True)
ON = "_departing_world_resources = WorldResourceHold.collect(flight) # Home reuses them instead of reloading"
OFF = "_departing_world_resources = [] # A/B BASELINE (temporary)"
env = dict(os.environ, TEMP="U:/tmp", TMP="U:/tmp")


def run(tag: str) -> None:
    out = OUT / f"{tag}.json"
    cmd = [str(GODOT), "--path", "app", "--audio-driver", "Dummy", "--resolution", "1920x1080", "--windowed",
           "--script", str(REPO / "research/performance/loading_probe.gd"), "--",
           f"--output={out.as_posix()}", "--cycles=3"]
    proc = subprocess.run(cmd, cwd=REPO, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900)
    (OUT / f"{tag}.log").write_bytes(proc.stdout)
    print(tag, "exit", proc.returncode, flush=True)


original = APP.read_bytes()
assert original.decode("utf-8").count(ON) == 1
try:
    for rep in (1, 2, 3):
        run(f"hold-r{rep}")
        APP.write_bytes(original.decode("utf-8").replace(ON, OFF).encode("utf-8"))
        try:
            run(f"base-r{rep}")
        finally:
            APP.write_bytes(original)
finally:
    APP.write_bytes(original)
print("restored", APP.read_bytes() == original)
