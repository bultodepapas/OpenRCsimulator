#!/usr/bin/env python3
"""F4U-16: install the delivered g1.13 livery GLBs as runtime assets.

Copies each frozen livery GLB (source-manifest.json `livery_glbs`) byte for byte to
app/assets/aircraft/f4u-corsair-250/ and gives it the default model's import settings. A new
sidecar carries only the [remap] importer and the [params] block; Godot's import adds its uid
and destination. The default livery (midnight) is the existing f4u_corsair.glb and is only checked.

    python3 research/f4u-corsair/F4U-16/install_liveries.py [--check]
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "assets/aircraft/f4u-corsair-250/source-manifest.json"
RUNTIME = ROOT / "app/assets/aircraft/f4u-corsair-250"
DEFAULT_LIVERY = "midnight"
DEFAULT_GLB = RUNTIME / "f4u_corsair.glb"


def runtime_glb(livery: str) -> Path:
    return DEFAULT_GLB if livery == DEFAULT_LIVERY else RUNTIME / f"f4u_corsair_{livery}.glb"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def params(sidecar: Path) -> list[str]:
    lines = sidecar.read_text(encoding="utf-8").splitlines()
    start = lines.index("[params]")
    return [line for line in lines[start:] if line.strip()]


def sidecar_template() -> str:
    return '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n' + "\n".join(params(Path(str(DEFAULT_GLB) + ".import"))) + "\n"


def main() -> int:
    check = "--check" in sys.argv
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    delivery = ROOT / manifest["delivery_root"]
    template = params(Path(str(DEFAULT_GLB) + ".import"))
    problems = []
    for livery, record in manifest["livery_glbs"].items():
        source = delivery / record["path"]
        target = runtime_glb(livery)
        if sha256(source) != record["sha256"]:
            problems.append(f"frozen {record['path']} differs from source-manifest.json")
            continue
        if not target.exists() or sha256(target) != record["sha256"]:
            if check or livery == DEFAULT_LIVERY:
                problems.append(f"{target.relative_to(ROOT).as_posix()} is not the delivered {record['path']}")
                continue
            shutil.copyfile(source, target)
            print(f"copied {record['path']} -> {target.relative_to(ROOT).as_posix()}")
        sidecar = Path(str(target) + ".import")
        if not sidecar.exists():
            if check:
                problems.append(f"{sidecar.relative_to(ROOT).as_posix()} is missing")
                continue
            sidecar.write_text(sidecar_template(), encoding="utf-8", newline="\n")
            print(f"wrote {sidecar.relative_to(ROOT).as_posix()} (run Godot --import to assign its uid)")
        elif params(sidecar) != template:
            problems.append(f"{sidecar.relative_to(ROOT).as_posix()} import settings differ from f4u_corsair.glb.import")
    if problems:
        sys.exit("\n".join(problems))
    print(f"{len(manifest['livery_glbs'])} livery GLBs match the frozen delivery with the default import settings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
