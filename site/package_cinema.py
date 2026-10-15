#!/usr/bin/env python3
"""Package the native Godot cinema capture into a poster and silent web video.

Requires Pillow==12.3.0 and FFmpeg with libx264. All PNG frames are generated
outside the repository by ``capture_cinema.gd``; this script writes only
``site/assets/cinema`` (or the explicitly selected asset directory).
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from PIL import Image, __version__ as pillow_version


PINNED_PILLOW_VERSION = "12.3.0"
POSTER_SIZE = (1600, 1000)
VIDEO_SIZE = (1280, 800)
FRAME_RATE = 24
DURATION_SECONDS = 12
FRAME_COUNT = FRAME_RATE * DURATION_SECONDS
BACKGROUND = "#101820"
AIRCRAFT = {
    "stik": {
        "id": "jensen-das-ugly-stik-60",
        "name": "Jensen Das Ugly Stik 60",
        "prefix": "stik",
        "manifest": "cinema.json",
    },
    "jet": {
        "id": "sebart-avanti-s-a200-p100rx",
        "name": "Ventage Jet",
        "prefix": "jet",
        "manifest": "jet-cinema.json",
    },
}
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ASSET_DIR = ROOT / "site" / "assets" / "cinema"
DEFAULT_MANIFEST = DEFAULT_ASSET_DIR / "cinema.json"
SOURCE_FILES = (
    Path("app/project.godot"),
    Path("app/render/airplane.gd"),
    Path("app/app_state/aircraft_catalog.gd"),
    Path("app/physics/aircraft_data.gd"),
)
SOURCE_DIRECTORIES = (
    Path("app/aircraft"),
    Path("app/assets/aircraft"),
    Path("app/data/aircraft"),
    Path("app/data/aircraft_models"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--aircraft",
        choices=sorted(AIRCRAFT),
        default="stik",
        help="Catalog model to capture (default: stik)",
    )
    parser.add_argument(
        "--capture-dir",
        required=True,
        type=Path,
        help="Directory produced by site/capture_cinema.gd; jet packaging also reads its details mode captures",
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
        help="Output directory for cinema media",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        help="Output JSON provenance manifest (defaults to the selected aircraft's manifest)",
    )
    parser.add_argument(
        "--ffmpeg",
        type=Path,
        help="FFmpeg executable (defaults to ffmpeg found on PATH)",
    )
    parser.add_argument(
        "--webm",
        action="store_true",
        help="Also encode a VP9 WebM fallback",
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
            raise FileNotFoundError(f"Required cinema source is missing: {path}")
        paths.add(path)
    for relative in SOURCE_DIRECTORIES:
        directory = project_root / relative
        if not directory.is_dir():
            raise FileNotFoundError(f"Required aircraft source directory is missing: {directory}")
        paths.update(path for path in directory.rglob("*") if path.is_file())
    for relative in (Path("site/capture_cinema.gd"), Path("site/package_cinema.py")):
        path = project_root / relative
        if not path.is_file():
            raise FileNotFoundError(f"Required cinema pipeline source is missing: {path}")
        paths.add(path)
    export_script = project_root / "site/export_web_models.gd"
    if export_script.is_file():
        paths.add(export_script)
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


def checked_image(path: Path, expected_size: tuple[int, int]) -> Image.Image:
    if not path.is_file():
        raise FileNotFoundError(f"Missing capture image: {path}")
    with Image.open(path) as opened:
        opened.load()
        if opened.size != expected_size:
            raise ValueError(
                f"{path.name} is {opened.width}x{opened.height}; "
                f"expected {expected_size[0]}x{expected_size[1]}"
            )
        return opened.convert("RGB")


def write_poster(image: Image.Image, destination: Path) -> int:
    quality = 92
    while quality >= 72:
        image.save(destination, format="WEBP", quality=quality, method=6)
        if destination.stat().st_size < 200_000:
            return quality
        quality -= 4
    raise ValueError("Could not compress the poster below 200 kB without excessive quality loss")


def executable_version(executable: Path) -> str:
    result = subprocess.run(
        [str(executable), "-version"],
        check=True,
        capture_output=True,
        text=True,
    )
    first_line = result.stdout.splitlines()[0] if result.stdout.splitlines() else ""
    if "ffmpeg version" not in first_line.casefold():
        raise ValueError(f"Unexpected FFmpeg version output: {first_line!r}")
    return first_line.strip()


def ffprobe_for(ffmpeg: Path) -> Path:
    sibling = ffmpeg.with_name("ffprobe.exe" if ffmpeg.suffix.casefold() == ".exe" else "ffprobe")
    discovered = shutil.which("ffprobe")
    if sibling.is_file():
        return sibling
    if discovered:
        return Path(discovered)
    raise FileNotFoundError("ffprobe must be beside ffmpeg or available on PATH")


def portable_arguments(command: list[str]) -> list[str]:
    """Keep encoder flags while removing machine-specific input/output paths."""
    arguments = command[1:-1]
    input_index = arguments.index("-i") + 1
    arguments[input_index] = "frames/%04d.png"
    return arguments


def encode_video(
    ffmpeg: Path,
    frames_dir: Path,
    output: Path,
    aircraft_name: str,
    webm: bool = False,
) -> tuple[list[str], dict[str, object]]:
    input_pattern = str(frames_dir / "%04d.png")
    if webm:
        command = [
            str(ffmpeg),
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-framerate",
            str(FRAME_RATE),
            "-start_number",
            "0",
            "-i",
            input_pattern,
            "-frames:v",
            str(FRAME_COUNT),
            "-c:v",
            "libvpx-vp9",
            "-deadline",
            "good",
            "-cpu-used",
            "3",
            "-crf",
            "34",
            "-b:v",
            "0",
            "-row-mt",
            "1",
            "-pix_fmt",
            "yuv420p",
            "-an",
            "-metadata",
            f"title=OpenRC {aircraft_name} studio presentation",
            "-metadata",
            "comment=Not gameplay or flight validation",
            str(output),
        ]
    else:
        command = [
            str(ffmpeg),
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-framerate",
            str(FRAME_RATE),
            "-start_number",
            "0",
            "-i",
            input_pattern,
            "-frames:v",
            str(FRAME_COUNT),
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            "23",
            "-profile:v",
            "high",
            "-level:v",
            "4.0",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            "-an",
            "-metadata",
            f"title=OpenRC {aircraft_name} studio presentation",
            "-metadata",
            "comment=Not gameplay or flight validation",
            str(output),
        ]
    subprocess.run(command, check=True, capture_output=True, text=True, timeout=1800)

    probe = subprocess.run(
        [
            str(ffprobe_for(ffmpeg)),
            "-v",
            "error",
            "-show_entries",
            "stream=codec_type,codec_name,width,height,avg_frame_rate,nb_frames:format=duration",
            "-of",
            "json",
            str(output),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    info = json.loads(probe.stdout)
    streams = info.get("streams", [])
    if len(streams) != 1:
        raise ValueError(f"Expected one silent video stream in {output.name}; found {len(streams)} streams")
    stream = streams[0]
    expected_codec = "vp9" if webm else "h264"
    if (
        stream.get("codec_type") != "video"
        or stream.get("codec_name") != expected_codec
        or int(stream.get("width", 0)) != VIDEO_SIZE[0]
        or int(stream.get("height", 0)) != VIDEO_SIZE[1]
        or stream.get("avg_frame_rate") != f"{FRAME_RATE}/1"
        or int(stream.get("nb_frames", 0)) != FRAME_COUNT
    ):
        raise ValueError(f"Encoded video metadata is unexpected: {stream}")
    duration = float(info.get("format", {}).get("duration", 0))
    if abs(duration - DURATION_SECONDS) > 0.02:
        raise ValueError(f"Encoded duration is {duration:.3f}s; expected {DURATION_SECONDS}s")
    return command, {
        "codec": expected_codec,
        "width": VIDEO_SIZE[0],
        "height": VIDEO_SIZE[1],
        "frame_rate": FRAME_RATE,
        "frame_count": FRAME_COUNT,
        "duration_seconds": duration,
        "has_audio": False,
        "bytes": output.stat().st_size,
        "sha256": sha256_file(output),
    }


def main() -> int:
    if pillow_version != PINNED_PILLOW_VERSION:
        print(
            f"This asset script requires Pillow=={PINNED_PILLOW_VERSION}; found {pillow_version}.",
            file=sys.stderr,
        )
        return 2

    args = parse_args()
    aircraft = AIRCRAFT[args.aircraft]
    aircraft_id = aircraft["id"]
    aircraft_name = aircraft["name"]
    prefix = aircraft["prefix"]
    project_root = args.project_root.resolve()
    capture_dir = args.capture_dir.resolve()
    asset_dir = args.asset_dir.resolve()
    manifest_path = args.manifest.resolve() if args.manifest else (asset_dir / aircraft["manifest"]).resolve()
    capture_manifest_path = capture_dir / "capture.json"
    if not capture_manifest_path.is_file():
        raise FileNotFoundError(f"Missing Godot capture manifest: {capture_manifest_path}")
    capture = json.loads(capture_manifest_path.read_text(encoding="utf-8"))
    if capture.get("format") != "openrc-cinema-capture-v1":
        raise ValueError("Unsupported cinema capture manifest format")
    if "not gameplay or flight validation" not in capture.get("purpose", ""):
        raise ValueError("Capture manifest does not state its presentation-only purpose")
    if capture.get("aircraft_key", args.aircraft) != args.aircraft:
        raise ValueError(f"Capture aircraft key does not match --aircraft={args.aircraft}")
    if capture.get("aircraft_id") != aircraft_id:
        raise ValueError(f"Unexpected aircraft ID: {capture.get('aircraft_id')!r}")
    if capture.get("frame_size") != list(VIDEO_SIZE):
        raise ValueError(f"Unexpected video frame size: {capture.get('frame_size')!r}")
    if int(capture.get("frame_rate", 0)) != FRAME_RATE:
        raise ValueError("Capture manifest has an unexpected frame rate")
    if int(capture.get("frame_count", 0)) != FRAME_COUNT:
        raise ValueError("Capture manifest has an unexpected frame count")
    if float(capture.get("duration_seconds", 0)) != DURATION_SECONDS:
        raise ValueError("Capture manifest has an unexpected duration")
    if capture.get("background") != BACKGROUND:
        raise ValueError(f"Capture background must be {BACKGROUND}")

    poster = checked_image(capture_dir / "poster.png", POSTER_SIZE)
    frames_dir = capture_dir / "frames"
    for index in range(FRAME_COUNT):
        checked_image(frames_dir / f"{index:04d}.png", VIDEO_SIZE)

    if args.ffmpeg is None:
        ffmpeg_on_path = shutil.which("ffmpeg")
        if not ffmpeg_on_path:
            raise FileNotFoundError("FFmpeg was not found; pass --ffmpeg <path> or add it to PATH")
        ffmpeg = Path(ffmpeg_on_path).resolve()
    else:
        ffmpeg = args.ffmpeg.resolve()
    if not ffmpeg.is_file():
        raise FileNotFoundError(f"FFmpeg executable does not exist: {ffmpeg}")
    ffmpeg_version = executable_version(ffmpeg)

    asset_dir.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    poster_path = asset_dir / f"{prefix}-hero.webp"
    poster_quality = write_poster(poster, poster_path)
    mp4_path = asset_dir / f"{prefix}-hero.mp4"
    mp4_command, mp4_info = encode_video(ffmpeg, frames_dir, mp4_path, aircraft_name)
    webm_info = None
    webm_command: list[str] | None = None
    if args.webm:
        webm_path = asset_dir / f"{prefix}-hero.webm"
        webm_command, webm_info = encode_video(ffmpeg, frames_dir, webm_path, aircraft_name, webm=True)

    hashes = source_inputs(project_root)
    jet_source_paths = (
        Path("app/app_state/aircraft_catalog.gd"),
        Path("app/render/airplane.gd"),
        Path("app/aircraft/model_registry.gd"),
        Path("app/aircraft/imported_model.gd"),
        Path("app/aircraft/avanti_s_model.gd"),
        Path("app/aircraft/avanti_s_blender_geometry.gd"),
        Path("app/data/aircraft_models/sebart-avanti-s-a200-p100rx.json"),
        Path("app/data/aircraft/sebart_avanti_s_a200.json"),
        Path("app/assets/aircraft/avanti-s-a200/avanti_s.glb.import"),
        Path("app/assets/aircraft/avanti-s-a200/avanti_s.glb"),
        Path("app/physics/aircraft_data.gd"),
    )
    missing_sources = [path.as_posix() for path in jet_source_paths if path.as_posix() not in hashes]
    if args.aircraft == "jet" and missing_sources:
        raise FileNotFoundError(f"Jet provenance is missing source hashes: {missing_sources}")
    pipeline_hashes = {
        "site/capture_cinema.gd": sha256_file(project_root / "site/capture_cinema.gd"),
        "site/package_cinema.py": sha256_file(project_root / "site/package_cinema.py"),
    }
    outputs: dict[str, dict[str, object]] = {
        "poster": {
            "path": poster_path.relative_to(project_root).as_posix(),
            "width": POSTER_SIZE[0],
            "height": POSTER_SIZE[1],
            "format": "WebP",
            "quality": poster_quality,
            "bytes": poster_path.stat().st_size,
            "sha256": sha256_file(poster_path),
        },
        "mp4": {
            "path": mp4_path.relative_to(project_root).as_posix(),
            **mp4_info,
        },
    }
    views_path: Path | None = None
    if args.aircraft == "jet":
        detail_captures = capture.get("camera", {}).get("detail_shots", {})
        detail_keys = ("cockpit", "wing", "tail")
        views: dict[str, dict[str, object]] = {}
        for key in detail_keys:
            if key not in detail_captures:
                raise ValueError(f"Capture manifest is missing the {key} camera preset")
            detail_image = checked_image(capture_dir / "details" / f"{key}.png", VIDEO_SIZE)
            detail_path = asset_dir / f"jet-{key}.webp"
            detail_quality = write_poster(detail_image, detail_path)
            outputs[key] = {
                "path": detail_path.relative_to(project_root).as_posix(),
                "width": VIDEO_SIZE[0],
                "height": VIDEO_SIZE[1],
                "format": "WebP",
                "quality": detail_quality,
                "bytes": detail_path.stat().st_size,
                "sha256": sha256_file(detail_path),
            }
            camera_record = detail_captures[key]["camera"]
            orbit = camera_record["model_viewer_orbit_degrees"]
            views[key] = {
                "target": camera_record["target_centered_model_m"],
                "orbit": [orbit["theta"], orbit["phi"], orbit["radius_m"]],
                "fov": detail_captures[key]["fov_degrees"],
            }
        views_path = asset_dir / "jet-views.json"
        views_path.write_text(json.dumps(views, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        outputs["views"] = {
            "path": views_path.relative_to(project_root).as_posix(),
            "bytes": views_path.stat().st_size,
            "sha256": sha256_file(views_path),
        }
    if webm_info is not None:
        assert webm_command is not None
        outputs["webm"] = {
            "path": (asset_dir / f"{prefix}-hero.webm").relative_to(project_root).as_posix(),
            **webm_info,
        }
    output_manifest = {
        "format": "openrc-cinema-assets-v1",
        "purpose": "Studio model presentation; not gameplay or flight validation",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": git_revision(project_root),
        "aircraft_key": args.aircraft,
        "aircraft_id": aircraft_id,
        "aircraft_name": aircraft_name,
        "engine": capture.get("engine", ""),
        "renderer": capture.get("renderer", ""),
        "capture": capture,
        "capture_manifest_sha256": sha256_file(capture_manifest_path),
        "pillow": pillow_version,
        "ffmpeg": ffmpeg_version,
        "source_tree_sha256": source_tree_digest(hashes),
        "source_files": hashes,
        "aircraft_source_files": (
            {path.as_posix(): hashes[path.as_posix()] for path in jet_source_paths}
            if args.aircraft == "jet"
            else {}
        ),
        "pipeline_sha256": pipeline_hashes,
        "encoding": {
            "mp4": {
                "arguments": portable_arguments(mp4_command),
                "audio": "none",
            },
            **(
                {"webm": {"arguments": portable_arguments(webm_command), "audio": "none"}}
                if webm_command is not None
                else {}
            ),
        },
        "assets": outputs,
    }
    manifest_path.write_text(
        json.dumps(output_manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"{poster_path.relative_to(project_root)}: {poster_path.stat().st_size:,} bytes, 1600x1000 WebP")
    print(f"{mp4_path.relative_to(project_root)}: {mp4_path.stat().st_size:,} bytes, H.264, silent, 12 s")
    if args.webm:
        webm_path = asset_dir / f"{prefix}-hero.webm"
        print(f"{webm_path.relative_to(project_root)}: {webm_path.stat().st_size:,} bytes, VP9, silent")
    if args.aircraft == "jet":
        for key in ("cockpit", "wing", "tail"):
            detail_path = asset_dir / f"jet-{key}.webp"
            print(f"{detail_path.relative_to(project_root)}: {detail_path.stat().st_size:,} bytes, 1280x800 WebP")
        assert views_path is not None
        print(f"{views_path.relative_to(project_root)}: model-viewer camera presets")
    print(f"{manifest_path.relative_to(project_root)}: {len(hashes)} source hashes")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        print(f"cinema packaging failed: {error}", file=sys.stderr)
        raise SystemExit(1)
