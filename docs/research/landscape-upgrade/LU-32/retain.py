from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image
import numpy as np

root = Path.cwd()
scratch = root / "tmp/landscape-perf-r2"
target = root / "docs/research/landscape-upgrade/LU-32"
target.mkdir(parents=True, exist_ok=True)
parity = []
for suite in ["storm", "night"]:
    for before in sorted((scratch / f"{suite}-before").glob("*.png")):
        a = np.asarray(Image.open(before).convert("RGB")).astype(np.int16)
        b = np.asarray(Image.open(scratch / f"{suite}-after" / before.name).convert("RGB")).astype(np.int16)
        difference = np.abs(a - b)
        parity.append({
            "suite": suite, "image": before.name,
            "changed_rgb_pixels": int(np.any(difference != 0, axis=2).sum()),
            "max_channel_difference_8bit": int(difference.max()),
            "mean_absolute_channel_difference_8bit": float(difference.mean()),
        })
(scratch / "image-parity.json").write_text(json.dumps(parity, indent=2) + "\n")
for name in ["storm-before", "storm-after", "night-before", "night-after", "checks"]:
    shutil.copytree(scratch / name, target / name, dirs_exist_ok=True)
for name in ["storm_bank.before.gd", "airfield_lighting.before.gd", "bench_updates.gd",
             "prepare_probe.py", "retain.py", "performance.json", "image-parity.json"]:
    shutil.copy2(scratch / name, target / name)
paths = [
    "app/render/landscape_upgrade/airfield_lighting.gd",
    "app/render/weather/storm_bank.gd",
    "app/tests/test_landscape_lighting.gd",
    "app/tests/test_storm_bank.gd",
    "app/render/world/world.gd",
    "app/render/atmosphere.gd",
    "app/tests/capture_landscape_upgrade.gd",
    "tools/atmosphere/storm_bank_capture.gd",
    "tmp/landscape-perf-r2/airfield_lighting.before.gd",
    "tmp/landscape-perf-r2/storm_bank.before.gd",
]
identities = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in paths}
(target / "source-identity.json").write_text(json.dumps(identities, indent=2) + "\n")
print(json.dumps({"destination": str(target), "parity": parity}, indent=2))
