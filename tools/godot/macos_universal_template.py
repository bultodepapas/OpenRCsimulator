#!/usr/bin/env python3
"""Prepare a project-local universal-only workaround for Godot 4.8-beta1 #124744.

The official editor selects the opposite debug/release payload for universal
exports. Swap those four payloads in a separate ZIP; never modify installed
templates. Remove the custom preset paths and this preparation when upgrading
to an engine containing upstream PR #124757.
"""
from __future__ import annotations

import argparse
import configparser
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile

VERSION = "4.8-beta1"
OFFICIAL_ARCHIVE_SHA512 = "fa53ad6883ae6c78ee9d2f8d14ca4d34852fa21c462d1f4b0f599138d7de40897cc058f15083a1fa80c7d4b7590b2222dea6f056be7b49e3a584eb64fc30b0b7"
MACOS_ZIP_SHA512 = "a36d2fd593a591b19358274ad8100684740fff83cf13ad04c5a3d593c3f4bd08a266f0725bda33344d00f30a56942e726d50b74109e8d50ed4794bbd917e0363"
RELATIVE_OUTPUT = Path(".godot/export_templates/macos-universal-4.8-beta1.zip")
RESOURCE_OUTPUT = "res://" + RELATIVE_OUTPUT.as_posix()
FORMAT = "openrc-macos-universal-template v1"
PREFIX = "macos_template.app/Contents/MacOS/godot_macos_"
SWAPS = {PREFIX + mode + "." + arch: PREFIX + other + "." + arch
         for mode, other in (("release", "debug"), ("debug", "release"))
         for arch in ("arm64", "x86_64")}


def digest(path: Path, algorithm: str = "sha256") -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def validate_project(project: Path) -> None:
    presets = configparser.ConfigParser(interpolation=None)
    presets.read(project / "export_presets.cfg", encoding="utf-8")
    sections = [section for section in presets.sections()
                if presets[section].get("platform") == '"macOS"']
    if len(sections) != 1:
        raise RuntimeError("expected exactly one macOS export preset")
    option_section = sections[0] + ".options"
    if not presets.has_section(option_section):
        raise RuntimeError("macOS export preset options are missing")
    options = presets[option_section]
    if options.get("binary_format/architecture") != '"universal"':
        raise RuntimeError("beta1 template workaround is only valid for universal macOS exports")
    for mode in ("debug", "release"):
        if options.get("custom_template/" + mode) != json.dumps(RESOURCE_OUTPUT):
            raise RuntimeError("macOS custom_template/" + mode + " does not select the project-local workaround")


def prepare_template(source: Path, output: Path) -> dict:
    source = source.resolve()
    output = output.resolve()
    if source == output:
        raise RuntimeError("the official source ZIP must never be overwritten")
    if digest(source, "sha512") != MACOS_ZIP_SHA512:
        raise RuntimeError("macOS source ZIP does not match the pinned official 4.8-beta1 template")
    receipt_path = output.with_suffix(".zip.receipt.json")
    previous = None
    if output.exists() or receipt_path.exists():
        if not output.is_file() or not receipt_path.is_file():
            raise RuntimeError("refusing to overwrite an unreceipted project-local template")
        try:
            previous = json.loads(receipt_path.read_text(encoding="utf-8"))
        except (ValueError, OSError) as error:
            raise RuntimeError("project-local template receipt is invalid") from error
        if not isinstance(previous, dict) or previous.get("format") != FORMAT or previous.get("output_sha256") != digest(output):
            raise RuntimeError("project-local template differs from its receipt")
    identity = {"format": FORMAT, "engine": VERSION, "architecture": "universal",
                "official_archive_sha512": OFFICIAL_ARCHIVE_SHA512,
                "source_zip_sha512": MACOS_ZIP_SHA512,
                "helper_sha256": digest(Path(__file__)), "workaround_for": "godotengine/godot#124744",
                "removed_by_upstream": "https://github.com/godotengine/godot/pull/124757"}
    if previous and all(previous.get(key) == value for key, value in identity.items()):
        return previous
    with zipfile.ZipFile(source) as original:
        entries = original.infolist()
        names = [entry.filename for entry in entries]
        if len(set(names)) != len(names) or any(name not in names for name in SWAPS):
            raise RuntimeError("official template has duplicate entries or lacks a required binary")
        binaries = {name for name in names if name.startswith(PREFIX)}
        if binaries != set(SWAPS):
            raise RuntimeError("unexpected official macOS binary layout")
        payloads = {name: original.read(name) for name in SWAPS}
        identity["binary_payloads"] = {
            name: {"source_entry": source_name, "sha256": hashlib.sha256(payloads[source_name]).hexdigest()}
            for name, source_name in SWAPS.items()
        }
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(prefix="macos-template-", suffix=".zip", dir=output.parent, delete=False) as stream:
            temporary = Path(stream.name)
        try:
            with zipfile.ZipFile(temporary, "w") as corrected:
                corrected.comment = original.comment
                for entry in entries:
                    content = payloads[SWAPS[entry.filename]] if entry.filename in SWAPS else original.read(entry)
                    corrected.writestr(copy.copy(entry), content, compress_type=entry.compress_type, compresslevel=9)
            identity["output_sha256"] = digest(temporary)
            temporary.replace(output)
        finally:
            temporary.unlink(missing_ok=True)
    # Write the receipt last; interrupted output/receipt pairs fail closed next time.
    receipt_path.write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")
    return identity


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="unmodified official 4.8-beta1 macos.zip")
    parser.add_argument("--project", type=Path, required=True, help="project containing the universal custom-template preset")
    args = parser.parse_args()
    try:
        validate_project(args.project)
        output = args.project / RELATIVE_OUTPUT
        prepare_template(args.source, output)
    except (OSError, RuntimeError, zipfile.BadZipFile, configparser.Error) as error:
        parser.exit(1, str(error) + "\n")
    print(output.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
