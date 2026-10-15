#!/usr/bin/env python3
"""Package native Godot turntable frames into browser-ready WebP sprite sheets.

Requires Pillow==12.3.0. The input frames are retained by the capture process
outside the website tree; this script writes only the turntable website assets.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from PIL import Image, __version__ as pillow_version


PINNED_PILLOW_VERSION = "12.3.0"
FRAME_WIDTH = 640
FRAME_HEIGHT = 360
COLUMNS = 6
ROWS = 6
FRAME_COUNT = COLUMNS * ROWS
MODEL_KEYS = ("stik", "extra", "mustang", "jet", "timber", "heli")
BACKGROUND = "#101820"
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ASSET_DIR = ROOT / "site" / "assets" / "turntables"
DEFAULT_MANIFEST = ROOT / "site" / "assets" / "turntables.json"
SOURCE_FILES = (
    Path("app/project.godot"),
    Path("app/render/airplane.gd"),
    Path("app/app_state/aircraft_catalog.gd"),
)
SOURCE_DIRECTORIES = (
    Path("app/aircraft"),
    Path("app/assets/aircraft"),
    Path("app/data/aircraft"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--capture-dir",
        required=True,
        type=Path,
        help="Directory produced by site/capture_turntables.gd",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=ROOT,
        help="Repository root used for source hashes (default: this repository)",
    )
    parser.add_argument(
        "--asset-dir",
        type=Path,
        default=DEFAULT_ASSET_DIR,
        help="Output directory for the six WebP sprite sheets",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="Output JSON manifest consumed by the website",
    )
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def source_inputs(project_root: Path) -> dict[str, str]:
    paths: set[Path] = set()
    for relative in SOURCE_FILES:
        path = project_root / relative
        if not path.is_file():
            raise FileNotFoundError(f"Required capture source is missing: {path}")
        paths.add(path)
    for relative in SOURCE_DIRECTORIES:
        directory = project_root / relative
        if not directory.is_dir():
            raise FileNotFoundError(f"Required model source directory is missing: {directory}")
        paths.update(path for path in directory.rglob("*") if path.is_file())

    capture_script = project_root / "site" / "capture_turntables.gd"
    package_script = project_root / "site" / "package_turntables.py"
    for path in (capture_script, package_script):
        if not path.is_file():
            raise FileNotFoundError(f"Required media pipeline source is missing: {path}")
        paths.add(path)

    return {
        path.relative_to(project_root).as_posix(): sha256_file(path)
        for path in sorted(paths, key=lambda item: item.as_posix().casefold())
    }


def source_tree_digest(files: dict[str, str]) -> str:
    digest = hashlib.sha256()
    for relative_path, file_digest in sorted(files.items()):
        digest.update(relative_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(file_digest.encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def git_revision(project_root: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=project_root,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return result.stdout.strip() or None


def capture_model_by_key(capture: dict) -> dict[str, dict]:
    records = capture.get("models")
    if not isinstance(records, list):
        raise ValueError("Capture manifest is missing its models list.")
    indexed: dict[str, dict] = {}
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("key"), str):
            raise ValueError("Capture manifest contains an invalid model record.")
        key = record["key"]
        if key in indexed:
            raise ValueError(f"Capture manifest repeats model key {key!r}.")
        indexed[key] = record
    if tuple(key for key in MODEL_KEYS if key in indexed) != MODEL_KEYS:
        raise ValueError(
            "Capture must contain the six website models in this set: "
            + ", ".join(MODEL_KEYS)
        )
    return indexed


def background_rgb(value: str) -> tuple[int, int, int]:
    color = value.removeprefix("#")
    if len(color) != 6:
        raise ValueError(f"Expected a six-digit RGB background, got {value!r}.")
    try:
        return tuple(int(color[index : index + 2], 16) for index in (0, 2, 4))  # type: ignore[return-value]
    except ValueError as error:
        raise ValueError(f"Invalid RGB background {value!r}.") from error


def frame_directory(capture_dir: Path, relative: str) -> Path:
    candidate = (capture_dir / relative).resolve()
    try:
        candidate.relative_to(capture_dir)
    except ValueError as error:
        raise ValueError(f"Frame directory escapes capture output: {relative!r}") from error
    if not candidate.is_dir():
        raise FileNotFoundError(f"Frame directory does not exist: {candidate}")
    return candidate


def package_sheet(
    key: str,
    record: dict,
    capture_dir: Path,
    asset_dir: Path,
    background: tuple[int, int, int],
) -> dict:
    if int(record.get("frames", -1)) != FRAME_COUNT:
        raise ValueError(f"{key}: expected {FRAME_COUNT} frames in the capture manifest.")
    frame_dir = frame_directory(capture_dir, str(record.get("frame_directory", "")))
    sheet = Image.new(
        "RGB",
        (FRAME_WIDTH * COLUMNS, FRAME_HEIGHT * ROWS),
        background,
    )
    poster_frame: Image.Image | None = None
    for index in range(FRAME_COUNT):
        frame_path = frame_dir / f"{index:02d}.png"
        if not frame_path.is_file():
            raise FileNotFoundError(f"{key}: missing orbit frame {index}: {frame_path}")
        with Image.open(frame_path) as opened:
            opened.load()
            if opened.size != (FRAME_WIDTH, FRAME_HEIGHT):
                raise ValueError(
                    f"{key} frame {index} has size {opened.width}x{opened.height}; "
                    f"expected {FRAME_WIDTH}x{FRAME_HEIGHT}."
                )
            frame = opened.convert("RGB")
        if index == 4:
            poster_frame = frame.copy()
        column = index % COLUMNS
        row = index // COLUMNS
        sheet.paste(frame, (column * FRAME_WIDTH, row * FRAME_HEIGHT))

    destination = asset_dir / f"{key}.webp"
    sheet.save(
        destination,
        format="WEBP",
        quality=95,
        method=6,
    )
    if poster_frame is None:
        raise ValueError(f"{key}: no poster frame was captured.")
    poster_path = asset_dir / f"{key}-poster.webp"
    poster_frame.save(
        poster_path,
        format="WEBP",
        quality=95,
        method=6,
    )
    return {
        "src": f"assets/turntables/{key}.webp",
        "poster": f"assets/turntables/{key}-poster.webp",
        "id": str(record["id"]),
        "name": str(record.get("name", key)),
        "status": str(record.get("status", "")),
        "vehicle": str(record.get("vehicle", "airplane")),
        "width": sheet.width,
        "height": sheet.height,
        "frame_count": FRAME_COUNT,
        "sha256": sha256_file(destination),
        "bytes": destination.stat().st_size,
        "poster_sha256": sha256_file(poster_path),
        "poster_bytes": poster_path.stat().st_size,
        "bounds": record.get("bounds", {}),
    }


def main() -> int:
    if pillow_version != PINNED_PILLOW_VERSION:
        print(
            f"This asset script requires Pillow=={PINNED_PILLOW_VERSION}; "
            f"found {pillow_version}.",
            file=sys.stderr,
        )
        return 2
    if not Image.registered_extensions().get(".webp"):
        print("This Pillow installation does not support WebP.", file=sys.stderr)
        return 2

    args = parse_args()
    project_root = args.project_root.resolve()
    capture_dir = args.capture_dir.resolve()
    asset_dir = args.asset_dir.resolve()
    manifest_path = args.manifest.resolve()
    capture_manifest_path = capture_dir / "manifest.json"
    if not capture_manifest_path.is_file():
        raise FileNotFoundError(f"Missing Godot capture manifest: {capture_manifest_path}")
    capture = json.loads(capture_manifest_path.read_text(encoding="utf-8"))
    if capture.get("format") != "openrc-turntable-capture-v1":
        raise ValueError("Unsupported capture manifest format.")
    if capture.get("frame_size") != [FRAME_WIDTH, FRAME_HEIGHT]:
        raise ValueError(f"Unexpected capture frame size: {capture.get('frame_size')!r}")
    if int(capture.get("frame_count_per_model", -1)) != FRAME_COUNT:
        raise ValueError("Capture manifest has the wrong orbit frame count.")
    if capture.get("background") != BACKGROUND:
        raise ValueError(f"Capture background must be {BACKGROUND}.")
    models_by_key = capture_model_by_key(capture)

    asset_dir.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    rendered_models: dict[str, dict] = {}
    background = background_rgb(BACKGROUND)
    for key in MODEL_KEYS:
        rendered_models[key] = package_sheet(
            key,
            models_by_key[key],
            capture_dir,
            asset_dir,
            background,
        )
        asset_path = asset_dir / f"{key}.webp"
        print(
            f"{asset_path.relative_to(project_root)}: "
            f"{asset_path.stat().st_size:,} bytes, 3840x2160, "
            "36-frame WebP quality 95"
        )

    hashes = source_inputs(project_root)
    capture_script_path = project_root / "site" / "capture_turntables.gd"
    package_script_path = project_root / "site" / "package_turntables.py"
    output_manifest = {
        "format": "openrc-turntables-v1",
        "frame_width": FRAME_WIDTH,
        "frame_height": FRAME_HEIGHT,
        "columns": COLUMNS,
        "rows": ROWS,
        "frame_count": FRAME_COUNT,
        "frame_order": "row-major; frame 0 starts at 0 degrees and each next frame advances 10 degrees around world Y",
        "background": BACKGROUND,
        "background_mode": capture.get("background_mode", ""),
        "ambient_light": capture.get("ambient_light", {}),
        "camera": capture.get("camera", {}),
        "lighting": capture.get("lighting", []),
        "models": rendered_models,
        "provenance": {
            "purpose": capture.get("purpose", ""),
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "git_head": git_revision(project_root),
            "engine": capture.get("engine", ""),
            "renderer": capture.get("renderer", ""),
            "pillow": pillow_version,
            "webp_quality": 95,
            "capture_script_sha256": sha256_file(capture_script_path),
            "package_script_sha256": sha256_file(package_script_path),
            "source_tree_sha256": source_tree_digest(hashes),
            "source_files": hashes,
        },
    }
    manifest_path.write_text(
        json.dumps(output_manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(
        f"{manifest_path.relative_to(project_root)}: "
        f"{len(hashes)} source hashes, tree {output_manifest['provenance']['source_tree_sha256']}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"turntable packaging failed: {error}", file=sys.stderr)
        raise SystemExit(1)
