"""Reproduce the NR integration check on the pre-night/failure-integration application snapshot.

Only the destination changes. This diagnostic copy does not repair or qualify the concurrent working tree.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
BASE = "7562dba6"
OVERLAYS = [
    "scenarios", "data/scenarios", "ui/natural_random_screen.gd", "i18n/es.po",
    "tests/test_natural_random_config.gd", "tests/test_natural_random_generator.gd",
    "tests/test_natural_random_screen.gd", "tests/test_natural_random_flight.gd",
    "tests/test_ui_natural_random.gd",
]


def add_authoring(destination: Path) -> None:
    paths: set[str] = set()

    def visit(value: object) -> None:
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "path" and isinstance(item, str) and item.startswith("assets/aircraft/"):
                    paths.add(item)
                visit(item)
        elif isinstance(value, list):
            for item in value:
                visit(item)

    for manifest in (destination / "app/data/aircraft_models").glob("*.json"):
        visit(json.loads(manifest.read_text(encoding="utf-8")))
    archive = subprocess.check_output(["git", "archive", BASE, *sorted(paths)], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as entries:
        entries.extractall(destination, filter="data")


def seal(destination: Path) -> None:
    """Record the exact diagnostic sources, excluding engine import caches."""
    files = {path.relative_to(destination).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
             for folder in [destination / "app", destination / "assets"]
             for path in sorted(folder.rglob("*")) if path.is_file() and ".godot" not in path.parts}
    (destination / "snapshot.json").write_text(json.dumps({"base": BASE, "overlays": OVERLAYS,
        "scope": "isolated integration evidence; not current working-tree acceptance", "files": files}, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    destination = args.out.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    archive = subprocess.check_output(["git", "archive", BASE, "app"], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as entries:
        entries.extractall(destination, filter="data")
    add_authoring(destination)
    for relative in OVERLAYS:
        source = ROOT / "app" / relative
        target = destination / "app" / relative
        if source.is_dir():
            shutil.copytree(source, target, dirs_exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    # Match today's overridable launch factory signature without bringing in unfinished vehicle routing.
    root_script = destination / "app/app_root.gd"
    text = root_script.read_text(encoding="utf-8")
    text = text.replace("func _create_flight() -> Node:", "func _create_flight(_aircraft_id: String = \"\") -> Node:")
    root_script.write_text(text, encoding="utf-8")
    home_script = destination / "app/ui/home.gd"
    text = home_script.read_text(encoding="utf-8").replace('_button("Aircraft Workshop", "")', '_button("Workshop", "")')
    home_script.write_text(text, encoding="utf-8")
    # Bound diagnostic worker contention on a workstation shared by several simultaneous Godot checks.
    (destination / "app/override.cfg").write_text("[threading]\nworker_pool/max_threads=2\n", encoding="utf-8")
    seal(destination)
    print(destination)


if __name__ == "__main__":
    main()
