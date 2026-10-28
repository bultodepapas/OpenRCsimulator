"""Package fresh README studio stills and optional supplied screenshots.

The previous docs/media/manifest.json and aircraft-tour.gif are never rewritten.
Run the studio capture in a fresh directory, then package it with this script.
--image SOURCE[=NAME] can be repeated for separately captured PNG/JPEG/WebP
images; such images do not inherit the studio's renderer or source identity.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile

import PIL
from PIL import Image


RECEIPT_NAME = "readme-captures.json"
CURRENT_GIF = "aircraft-tour-current.gif"
SAFE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SAFE_IMAGE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*\.(?:png|jpe?g|webp)$", re.I)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def image_size(path):
    with Image.open(path) as image:
        image.load()
        return list(image.size)


def safe_image_name(name):
    if not SAFE_IMAGE.fullmatch(name):
        raise ValueError(f"Unsafe image filename: {name!r}")
    return name


def parse_image(value):
    source, separator, name = value.rpartition("=")
    if not separator:
        source, name = value, Path(value).name
    if not source:
        raise ValueError("Empty --image source")
    return Path(source), safe_image_name(name)


def read_receipt(destination):
    path = destination / RECEIPT_NAME
    if not path.exists():
        return {"format": "openrc-readme-media v2", "sessions": {}, "stills": {}, "images": {}}
    receipt = json.loads(path.read_text(encoding="utf-8"))
    if receipt.get("format") != "openrc-readme-media v2":
        raise ValueError(f"Unexpected receipt format: {path}")
    for section in ("stills", "images"):
        if not isinstance(receipt.get(section), dict):
            raise ValueError(f"Invalid receipt section: {section}")
    if not isinstance(receipt.get("sessions"), dict):
        raise ValueError("Invalid receipt sessions")
    records = list(receipt["stills"].values()) + list(receipt["images"].values())
    if receipt.get("animation"):
        records.append(receipt["animation"])
    for record in records:
        name = safe_image_name(record["file"]) if record["file"] != CURRENT_GIF else CURRENT_GIF
        existing = destination / name
        if not existing.is_file() or sha256(existing) != record["sha256"]:
            raise ValueError(f"Existing receipt no longer matches {existing}")
    return receipt


def load_capture(source):
    path = source / "manifest.json"
    raw = path.read_bytes()
    manifest = json.loads(raw)
    if manifest.get("format") != "openrc-readme-renders v2":
        raise ValueError("Expected a v2 studio capture manifest")
    for field in ("captured_utc", "engine", "renderer", "driver", "adapter"):
        if not isinstance(manifest.get(field), str) or not manifest[field]:
            raise ValueError(f"Missing capture identity: {field}")
    for field in ("source_start", "source_end"):
        identity = manifest.get(field)
        if not isinstance(identity, dict) or not re.fullmatch(r"[0-9a-f]{40,64}", identity.get("commit", "")):
            raise ValueError(f"Missing Git source identity: {field}")
    if manifest.get("stills_size") != [1920, 1080] or manifest.get("tour_size") != [800, 450]:
        raise ValueError("Unexpected capture dimensions")
    vehicles = manifest.get("vehicles")
    if not isinstance(vehicles, list) or not vehicles:
        raise ValueError("No captured vehicles")
    seen = set()
    frame_total = 0
    for vehicle in vehicles:
        vehicle_id = vehicle.get("id", "")
        if not SAFE_ID.fullmatch(vehicle_id) or vehicle_id in seen:
            raise ValueError(f"Invalid or duplicate vehicle ID: {vehicle_id!r}")
        seen.add(vehicle_id)
        if vehicle.get("still") != vehicle_id + ".png":
            raise ValueError(f"Unexpected still path for {vehicle_id}")
        still = source / vehicle["still"]
        if image_size(still) != [1920, 1080] or sha256(still) != vehicle.get("still_sha256"):
            raise ValueError(f"Still does not match capture receipt: {still}")
        frames = vehicle.get("frames")
        if type(frames) is not int or frames not in (0, 72):
            raise ValueError(f"Invalid frame count for {vehicle_id}")
        frame_total += frames
    if manifest.get("frame_count") != frame_total:
        raise ValueError("Capture frame total does not match vehicles")
    if frame_total and any(vehicle["frames"] != 72 for vehicle in vehicles):
        raise ValueError("Cannot assemble a partially animated capture")
    expected = [source / "frames" / f"{i:03d}.png" for i in range(frame_total)]
    actual = sorted((source / "frames").glob("*.png"))
    if set(actual) != set(expected):
        raise ValueError("Animation frames are missing or unexpected")
    return manifest, raw, expected


def build_animation(frame_paths, target):
    frames = []
    for path in frame_paths:
        with Image.open(path) as image:
            if image.size != (800, 450):
                raise ValueError(f"Wrong animation frame size: {path}")
            frames.append(image.convert("RGB").quantize(colors=64, dither=Image.Dither.NONE))
    frames[0].save(target, save_all=True, append_images=frames[1:],
                   duration=60, loop=0, optimize=True)
    with Image.open(target) as image:
        if image.n_frames != len(frames):
            raise ValueError("GIF dropped animation frames")
        duration = 0
        for i in range(image.n_frames):
            image.seek(i)
            duration += image.info["duration"]
    if target.stat().st_size > 12_000_000:
        raise ValueError("README animation exceeds 12 MB")
    return duration


def package(source, destination, supplied):
    manifest, raw, frames = load_capture(source)
    receipt = read_receipt(destination)
    packager_hash = sha256(Path(__file__))
    session_id = hashlib.sha256(raw).hexdigest()
    session = {key: value for key, value in manifest.items() if key != "vehicles"}
    session["capture_manifest_sha256"] = session_id

    copies = []
    targets = {}
    previous_still_names = {record["file"].casefold() for record in receipt["stills"].values()}
    previous_image_names = {record["file"].casefold() for record in receipt["images"].values()}
    for vehicle in manifest["vehicles"]:
        name = safe_image_name(f"studio-{vehicle['id']}.png")
        if name.casefold() in previous_image_names:
            raise ValueError(f"Studio still collides with a supplied image: {name}")
        copies.append((source / vehicle["still"], name))
        targets[name.casefold()] = name
    extras = []
    for value in supplied:
        path, name = parse_image(value)
        if name.casefold() in targets or name.casefold() in previous_still_names or name.casefold().startswith("studio-"):
            raise ValueError(f"Duplicate image destination: {name}")
        targets[name.casefold()] = name
        dimensions = image_size(path)
        digest = sha256(path)
        extras.append((path, name, dimensions, digest))
        copies.append((path, name))

    owned = {record["file"].casefold() for record in receipt["stills"].values()}
    owned.update(record["file"].casefold() for record in receipt["images"].values())
    if receipt.get("animation"):
        owned.add(receipt["animation"]["file"].casefold())
    if frames:
        targets[CURRENT_GIF.casefold()] = CURRENT_GIF
    for key, name in targets.items():
        if (destination / name).exists() and key not in owned:
            raise ValueError(f"Refusing to overwrite untracked media: {destination / name}")
    for path, name in copies:
        if path.resolve() == (destination / name).resolve():
            raise ValueError(f"Source and destination are the same: {path}")

    # Validate the GIF before touching the destination.
    with tempfile.TemporaryDirectory(prefix="readme-package-") as temp:
        gif = Path(temp) / CURRENT_GIF
        duration = build_animation(frames, gif) if frames else None
        destination.mkdir(parents=True, exist_ok=True)
        for path, name in copies:
            shutil.copyfile(path, destination / name)
        receipt["sessions"][session_id] = session
        for vehicle in manifest["vehicles"]:
            record = dict(vehicle)
            record["file"] = f"studio-{vehicle['id']}.png"
            record["sha256"] = vehicle["still_sha256"]
            record["session"] = session_id
            record["packager_sha256"] = packager_hash
            record.pop("still")
            record.pop("still_sha256")
            receipt["stills"][vehicle["id"]] = record
        for path, name, dimensions, digest in extras:
            receipt["images"][name] = {
                "file": name, "sha256": digest, "size": dimensions,
                "input_name": path.name, "provenance": "Supplied separately; studio session does not apply",
                "packager_sha256": packager_hash,
            }
        if frames:
            shutil.copyfile(gif, destination / CURRENT_GIF)
            receipt["animation"] = {
                "file": CURRENT_GIF, "sha256": sha256(gif), "session": session_id,
                "vehicle_ids": [vehicle["id"] for vehicle in manifest["vehicles"]],
                "frame_count": len(frames), "frame_duration_ms": 60,
                "duration_ms": duration, "pillow": PIL.__version__,
                "packager_sha256": packager_hash,
            }
        (destination / RECEIPT_NAME).write_text(
            json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    print(f"Packaged {len(manifest['vehicles'])} fresh stills, {len(extras)} supplied images, "
          f"{len(frames)} animation frames; receipt: {destination / RECEIPT_NAME}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Fresh studio capture directory")
    parser.add_argument("destination", type=Path, help="README media directory")
    parser.add_argument("--image", action="append", default=[], metavar="SOURCE[=NAME]",
                        help="Also copy a separately captured image, optionally renaming it")
    args = parser.parse_args()
    package(args.source, args.destination, args.image)


if __name__ == "__main__":
    main()
