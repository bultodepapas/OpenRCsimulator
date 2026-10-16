#!/usr/bin/env python3
"""Fetch and verify the CC0 RC ground textures from Poly Haven and ambientCG."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any
from zipfile import BadZipFile, ZipFile


API_ROOT = "https://api.polyhaven.com"
LICENSE = "CC0 1.0 Universal"
LICENSE_URL = "https://polyhaven.com/license"
CC0_TEXT_URL = "https://creativecommons.org/publicdomain/zero/1.0/"
USER_AGENT = "OpenRCsimulator RC ground asset importer/1.0"

ASSETS: dict[str, dict[str, Any]] = {
    "dirt": {
        "runtime_names": {
            "Diffuse": "dirt-albedo.jpg",
            "nor_gl": "dirt-normal.jpg",
            "Rough": "dirt-roughness.jpg",
        },
        "map_names": {
            "Diffuse": "albedo",
            "nor_gl": "normal (OpenGL, +Y)",
            "Rough": "roughness",
        },
    },
    "sparse_grass": {
        "map_names": {
            "Diffuse": "albedo",
            "nor_gl": "normal (OpenGL, +Y)",
            "Rough": "roughness",
        },
        "candidate_reason": (
            "Rejected for the maintained runway turf slot: the 2k diffuse is "
            "brown, rooty, and leaves frequent bare-soil gaps. Keep its source "
            "metadata as a possible rough field-edge comparison only."
        ),
    },
}

RESOLUTIONS = ("2k", "4k")
AMBIENTCG_API_URL = (
    "https://ambientcg.com/api/v2/full_json?id=Grass001"
    "&include=downloadData,displayData,dimensionsData,tagData"
)
AMBIENTCG_ASSET_URL = "https://ambientcg.com/view?id=Grass001"
AMBIENTCG_LICENSE_URL = "https://docs.ambientcg.com/license/"
LICENSE_EVIDENCE_DATE = "2026-10-15"
RUNTIME_RELATIVE_PATH = "app/assets/landscape/rc-ground"
RUNTIME_MANIFEST_RELATIVE = f"{RUNTIME_RELATIVE_PATH}/manifest.json"
RUNTIME_LICENSES_RELATIVE = f"{RUNTIME_RELATIVE_PATH}/LICENSES.txt"
SOURCE_MANIFEST_RELATIVE = "assets/landscape/rc-ground/manifest.json"
AMBIENTCG_MAPS = {
    "Color": ("grass-albedo.jpg", "albedo"),
    "NormalGL": ("grass-normal.jpg", "normal (OpenGL, +Y)"),
    "Roughness": ("grass-roughness.jpg", "roughness"),
}


def fetch_json(url: str) -> Any:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def hash_file(path: Path) -> tuple[int, str, str]:
    md5 = hashlib.md5()
    sha256 = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            size += len(chunk)
            md5.update(chunk)
            sha256.update(chunk)
    return size, md5.hexdigest(), sha256.hexdigest()


def jpeg_dimensions(path: Path) -> tuple[int, int]:
    """Read JPEG dimensions from a SOF marker without an imaging dependency."""
    with path.open("rb") as source:
        if source.read(2) != b"\xff\xd8":
            raise ValueError(f"Not a JPEG file: {path}")
        while True:
            marker_start = source.read(1)
            if not marker_start:
                break
            if marker_start != b"\xff":
                continue
            marker_byte = source.read(1)
            while marker_byte == b"\xff":
                marker_byte = source.read(1)
            if not marker_byte:
                break
            marker = marker_byte[0]
            if marker in (0xD8, 0xD9, 0x01) or 0xD0 <= marker <= 0xD7:
                continue
            length_bytes = source.read(2)
            if len(length_bytes) != 2:
                break
            segment_length = int.from_bytes(length_bytes, "big")
            if segment_length < 2:
                raise ValueError(f"Invalid JPEG segment in {path}")
            if marker in {
                0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
            }:
                frame = source.read(segment_length - 2)
                if len(frame) < 5:
                    break
                height = int.from_bytes(frame[1:3], "big")
                width = int.from_bytes(frame[3:5], "big")
                return width, height
            source.seek(segment_length - 2, os.SEEK_CUR)
    raise ValueError(f"JPEG has no supported frame header: {path}")


def download_verified(path: Path, file_info: dict[str, Any]) -> tuple[int, str, str]:
    expected_size = int(file_info["size"])
    expected_md5 = str(file_info["md5"]).lower()
    if path.exists():
        size, md5, sha256 = hash_file(path)
        if size == expected_size and md5 == expected_md5:
            return size, md5, sha256

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".part")
    try:
        request = urllib.request.Request(
            str(file_info["url"]), headers={"User-Agent": USER_AGENT}
        )
        with urllib.request.urlopen(request, timeout=120) as response:
            with temporary.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
        size, md5, sha256 = hash_file(temporary)
        if size != expected_size:
            raise ValueError(
                f"Size mismatch for {path}: got {size}, API says {expected_size}"
            )
        if md5 != expected_md5:
            raise ValueError(
                f"MD5 mismatch for {path}: got {md5}, API says {expected_md5}"
            )
        os.replace(temporary, path)
        return size, md5, sha256
    finally:
        if temporary.exists():
            temporary.unlink()


def selected_file(files: dict[str, Any], map_key: str, resolution: str) -> dict[str, Any]:
    try:
        return files[map_key][resolution]["jpg"]
    except (KeyError, TypeError) as exc:
        raise ValueError(
            f"Poly Haven no longer publishes {map_key} {resolution} JPG"
        ) from exc


def ambientcg_download(asset: dict[str, Any], attribute: str) -> dict[str, Any]:
    downloads = asset["downloadFolders"]["default"]["downloadFiletypeCategories"]["zip"]["downloads"]
    for download in downloads:
        if download.get("attribute") == attribute:
            return download
    raise ValueError(f"AmbientCG no longer publishes {attribute} JPG ZIP")


def download_archive(download: dict[str, Any], target: Path) -> tuple[int, str, str]:
    expected_size = int(download["size"])
    request = urllib.request.Request(
        str(download["fullDownloadPath"]), headers={"User-Agent": USER_AGENT}
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        resolved_url = response.geturl()
        with target.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
    size, md5, sha256 = hash_file(target)
    if size != expected_size:
        raise ValueError(
            f"Size mismatch for {download['fileName']}: got {size}, API says {expected_size}"
        )
    # The AmbientCG API provides archive size but no checksum. The local SHA-256
    # and ZIP CRC check below identify and validate the exact retrieved package.
    download["resolvedUrl"] = resolved_url
    return size, md5, sha256


def extract_ambientcg_map(
    archive: ZipFile,
    asset_id: str,
    resolution: str,
    source_map: str,
    target: Path,
) -> dict[str, Any]:
    member_name = f"{asset_id}_{resolution}-JPG_{source_map}.jpg"
    matches = [entry for entry in archive.infolist() if Path(entry.filename).name == member_name]
    if len(matches) != 1:
        raise ValueError(
            f"Expected exactly one {member_name} in AmbientCG archive, found {len(matches)}"
        )
    data = archive.read(matches[0])
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".part")
    try:
        temporary.write_bytes(data)
        width, height = jpeg_dimensions(temporary)
        expected_dimension = 2048 if resolution == "2K" else 4096
        if (width, height) != (expected_dimension, expected_dimension):
            raise ValueError(
                f"Unexpected dimensions in {member_name}: {width}x{height}"
            )
        size, md5, sha256 = hash_file(temporary)
        os.replace(temporary, target)
        return {
            "archive_member": matches[0].filename,
            "size_bytes": size,
            "dimensions_px": [width, height],
            "md5": md5,
            "sha256": sha256,
        }
    finally:
        if temporary.exists():
            temporary.unlink()


def import_ambientcg_grass(
    repo_root: Path,
    include_4k: bool,
    previous_manifest: dict[str, Any],
) -> dict[str, Any]:
    payload = fetch_json(AMBIENTCG_API_URL)
    found = payload.get("foundAssets", [])
    asset = next((entry for entry in found if entry.get("assetId") == "Grass001"), None)
    if asset is None:
        raise ValueError("AmbientCG API returned no Grass001 asset")

    runtime_dir = repo_root / "app" / "assets" / "landscape" / "rc-ground"
    source_dir = repo_root / "assets" / "landscape" / "rc-ground" / "source" / "ambientcg"
    previous = previous_manifest.get("ambientcg_grass", {})
    previous_files = {
        record.get("source_map"): record
        for record in previous.get("files", [])
        if record.get("resolution") == "2K"
    }
    previous_sources = {
        record.get("source_map"): record
        for record in previous.get("files", [])
        if record.get("resolution") == "4K"
    }
    file_records: list[dict[str, Any]] = []
    archive_records: list[dict[str, Any]] = []

    resolutions = [("2K", runtime_dir)]
    if include_4k:
        resolutions.append(("4K", source_dir))

    for resolution, target_dir in resolutions:
        source_records = previous_files if resolution == "2K" else previous_sources
        expected_names = [source_map for source_map in AMBIENTCG_MAPS]
        can_reuse = True
        for source_map in expected_names:
            prior = source_records.get(source_map)
            if prior is None:
                can_reuse = False
                break
            output_name = AMBIENTCG_MAPS[source_map][0] if resolution == "2K" else prior.get("archive_member", "")
            target = target_dir / output_name
            if not target.is_file():
                can_reuse = False
                break
            _, _, sha256 = hash_file(target)
            if sha256 != prior.get("sha256"):
                can_reuse = False
                break
        if can_reuse:
            file_records.extend(
                source_records[source_map]
                for source_map in expected_names
            )
            archive_records.append(previous["archives"][resolution])
            continue

        download = ambientcg_download(asset, f"{resolution}-JPG")
        with tempfile.NamedTemporaryFile(
            prefix=f"ambientcg-grass001-{resolution.lower()}-",
            suffix=".zip",
            delete=False,
        ) as temporary_file:
            archive_path = Path(temporary_file.name)
        try:
            archive_size, archive_md5, archive_sha256 = download_archive(download, archive_path)
            with ZipFile(archive_path, "r") as archive:
                corrupt_member = archive.testzip()
                if corrupt_member is not None:
                    raise BadZipFile(f"Corrupt ZIP member: {corrupt_member}")
                for source_map, (runtime_name, map_name) in AMBIENTCG_MAPS.items():
                    if resolution == "2K":
                        target = runtime_dir / runtime_name
                        relative_path = target.relative_to(repo_root).as_posix()
                    else:
                        member_name = f"Grass001_4K-JPG_{source_map}.jpg"
                        target = source_dir / member_name
                        relative_path = target.relative_to(repo_root).as_posix()
                    extracted = extract_ambientcg_map(
                        archive, "Grass001", resolution, source_map, target
                    )
                    file_records.append(
                        {
                            "map": map_name,
                            "source_map": source_map,
                            "resolution": resolution,
                            "format": "jpg",
                            "path": relative_path,
                            "url": download["fullDownloadPath"],
                            **extracted,
                        }
                    )
                    print(
                        f"{relative_path}  {extracted['dimensions_px'][0]}x"
                        f"{extracted['dimensions_px'][1]}  sha256:{extracted['sha256']}"
                    )
            archive_records.append(
                {
                    "attribute": download["attribute"],
                    "file_name": download["fileName"],
                    "download_url": download["fullDownloadPath"],
                    "resolved_url": download["resolvedUrl"],
                    "size_bytes": archive_size,
                    "md5": archive_md5,
                    "sha256": archive_sha256,
                    "crc_verified": True,
                    "retained": False,
                }
            )
            print(f"{download['fileName']}  sha256:{archive_sha256}  (temporary ZIP; extracted maps retained)")
        finally:
            archive_path.unlink(missing_ok=True)

    existing_archive_records = previous.get("archives", {})
    archives_by_resolution = dict(existing_archive_records)
    for record in archive_records:
        resolution = "2K" if record["attribute"].startswith("2K") else "4K"
        archives_by_resolution[resolution] = record

    # Keep only records for resolutions produced in this run. Existing 4K records
    # are reused only when the matching source maps are present and hash-identical.
    return {
        "name": asset.get("displayName", "Grass 001"),
        "author": "ambientCG (no individual creator name is listed in the asset API)",
        "creation_method": asset.get("creationMethodName"),
        "tags": asset.get("tags", []),
        "api_dimensions": {
            "x": asset.get("dimensionX"),
            "y": asset.get("dimensionY"),
            "api_unit": "AmbientCG page describes this as approximately 1.4 m × 1.4 m",
            "tile_dimensions_m_approx": [1.4, 1.4],
        },
        "asset_url": AMBIENTCG_ASSET_URL,
        "api_url": AMBIENTCG_API_URL,
        "license": LICENSE,
        "license_url": AMBIENTCG_LICENSE_URL,
        "archives": archives_by_resolution,
        "files": file_records,
    }


def import_assets(
    repo_root: Path,
    include_4k: bool,
    previous_manifest: dict[str, Any],
) -> dict[str, Any]:
    runtime_dir = repo_root / "app" / "assets" / "landscape" / "rc-ground"
    source_dir = repo_root / "assets" / "landscape" / "rc-ground" / "source"
    manifest_assets: dict[str, Any] = {}
    candidates: dict[str, Any] = {}

    for asset_id, definition in ASSETS.items():
        info_url = f"{API_ROOT}/info/{asset_id}"
        files_url = f"{API_ROOT}/files/{asset_id}"
        info = fetch_json(info_url)
        files = fetch_json(files_url)
        file_records: list[dict[str, Any]] = []
        candidate_records: list[dict[str, Any]] = []

        for map_key in definition["map_names"]:
            for resolution in RESOLUTIONS:
                if resolution == "4k" and not include_4k:
                    continue
                file_info = selected_file(files, map_key, resolution)
                runtime_name = definition.get("runtime_names", {}).get(map_key)
                if resolution == "2k" and runtime_name:
                    target = runtime_dir / runtime_name
                    relative_path = target.relative_to(repo_root).as_posix()
                else:
                    original_name = Path(str(file_info["url"])).name
                    target = source_dir / asset_id / original_name
                    relative_path = target.relative_to(repo_root).as_posix()

                if not runtime_name:
                    candidate_records.append(
                        {
                            "map": definition["map_names"][map_key],
                            "map_key": map_key,
                            "resolution": resolution,
                            "format": "jpg",
                            "source_url": file_info["url"],
                            "api_size_bytes": int(file_info["size"]),
                            "api_md5": str(file_info["md5"]).lower(),
                        }
                    )
                    continue

                size, md5, sha256 = download_verified(target, file_info)
                width, height = jpeg_dimensions(target)
                file_records.append(
                    {
                        "map": definition["map_names"][map_key],
                        "map_key": map_key,
                        "resolution": resolution,
                        "format": "jpg",
                        "path": relative_path,
                        "url": file_info["url"],
                        "size_bytes": size,
                        "dimensions_px": [width, height],
                        "md5": md5,
                        "sha256": sha256,
                    }
                )
                print(f"{relative_path}  {width}x{height}  sha256:{sha256}")

        asset_record = {
            "name": info.get("name"),
            "author": info.get("authors", {}),
            "description": info.get("description"),
            "category": info.get("category"),
            "api_dimensions_px": info.get("dimensions"),
            "api_max_resolution_px": info.get("max_resolution"),
            "api_files_hash": info.get("files_hash"),
            "asset_url": f"https://polyhaven.com/a/{asset_id}",
            "info_api_url": info_url,
            "files_api_url": files_url,
            "files": file_records,
        }
        if definition.get("runtime_names"):
            manifest_assets[asset_id] = asset_record
        if candidate_records:
            old_sparse = previous_manifest.get("candidates", {}).get(asset_id, {})
            old_screening = old_sparse.get("screening", {})
            if not old_screening:
                # The first intake pass downloaded this candidate before the
                # visual review rejected it. Preserve the verified 2k hashes as
                # screening evidence without retaining those unused image files.
                prior_asset = previous_manifest.get("assets", {}).get(asset_id, {})
                prior_files = prior_asset.get("files", [])
                old_screening = {
                    "reviewed_resolution": "2k",
                    "visual_review": definition["candidate_reason"],
                    "screened_sha256": {
                        record.get("map_key"): record.get("sha256")
                        for record in prior_files
                        if record.get("resolution") == "2k"
                    },
                }
            candidates[asset_id] = {
                "name": info.get("name"),
                "author": info.get("authors", {}),
                "description": info.get("description"),
                "category": info.get("category"),
                "api_dimensions_px": info.get("dimensions"),
                "api_max_resolution_px": info.get("max_resolution"),
                "api_files_hash": info.get("files_hash"),
                "asset_url": f"https://polyhaven.com/a/{asset_id}",
                "info_api_url": info_url,
                "files_api_url": files_url,
                "runtime_selected": False,
                "assessment": definition["candidate_reason"],
                "screening": old_screening,
                "files": candidate_records,
            }

    ambientcg_grass = import_ambientcg_grass(repo_root, include_4k, previous_manifest)

    return {
        "schema_version": 1,
        "sources": ["Poly Haven", "ambientCG"],
        "license": LICENSE,
        "license_url": LICENSE_URL,
        "license_evidence": {
            "checked_date": LICENSE_EVIDENCE_DATE,
            "references": [
                {
                    "provider": "Poly Haven",
                    "asset_url": "https://polyhaven.com/a/dirt",
                    "license": LICENSE,
                    "license_url": LICENSE_URL,
                    "license_text_url": CC0_TEXT_URL,
                },
                {
                    "provider": "ambientCG",
                    "asset_url": AMBIENTCG_ASSET_URL,
                    "license": LICENSE,
                    "license_url": AMBIENTCG_LICENSE_URL,
                    "license_text_url": CC0_TEXT_URL,
                },
            ],
        },
        "api_roots": [API_ROOT, "https://ambientcg.com/api/v2"],
        "importer": "tools/ground/import_rc_ground.py",
        "runtime_policy": {
            "resolution": "2k",
            "format": "original JPGs from the publisher packages; no pixel transformation",
            "texture_import": "Godot VRAM compressed with mipmaps",
            "albedo_color_space": "sRGB (shader sampler hint is assigned by the material owner)",
            "normal_map": "OpenGL tangent-space (+Y), imported with Godot normal-map compression",
        },
        "source_policy": {
            "resolution": "4k",
            "format": "only original maps used by the material are retained for A/B comparisons",
            "ambientcg_archives": "downloaded and CRC-checked; ZIP identity is recorded, then only used original JPG maps are retained",
        },
        "assets": manifest_assets,
        "candidates": candidates,
        "ambientcg_grass": ambientcg_grass,
    }


def runtime_manifest_from_source(source: dict[str, Any]) -> dict[str, Any]:
    """Build the shipped metadata as a deterministic subset of source records."""
    dirt = source.get("assets", {}).get("dirt")
    grass = source.get("ambientcg_grass")
    if not isinstance(dirt, dict) or not isinstance(grass, dict):
        raise ValueError("Source manifest is missing the selected Dirt or Grass001 asset")

    dirt_files = [
        record
        for record in dirt.get("files", [])
        if record.get("resolution") == "2k"
        and str(record.get("path", "")).startswith(f"{RUNTIME_RELATIVE_PATH}/")
    ]
    grass_files = [
        record
        for record in grass.get("files", [])
        if record.get("resolution") == "2K"
        and str(record.get("path", "")).startswith(f"{RUNTIME_RELATIVE_PATH}/")
    ]
    expected_dirt = set(ASSETS["dirt"]["runtime_names"].values())
    expected_grass = {mapping[0] for mapping in AMBIENTCG_MAPS.values()}
    actual_dirt = {Path(str(record.get("path", ""))).name for record in dirt_files}
    actual_grass = {Path(str(record.get("path", ""))).name for record in grass_files}
    if len(dirt_files) != len(expected_dirt) or actual_dirt != expected_dirt:
        raise ValueError("Source manifest does not contain the exact Dirt runtime map set")
    if len(grass_files) != len(expected_grass) or actual_grass != expected_grass:
        raise ValueError("Source manifest does not contain the exact Grass001 runtime map set")

    dirt_entry = {
        key: dirt[key]
        for key in ("name", "author", "asset_url", "api_dimensions_px")
        if key in dirt
    }
    dirt_entry.update(
        {
            "license": source["license"],
            "license_url": source["license_url"],
            "files": dirt_files,
        }
    )
    grass_entry = {
        key: grass[key]
        for key in (
            "name",
            "author",
            "asset_url",
            "api_dimensions",
            "license",
            "license_url",
        )
        if key in grass
    }
    grass_entry["files"] = grass_files
    return {
        "schema_version": 1,
        "generated_by": source.get("importer", "tools/ground/import_rc_ground.py"),
        "source_manifest": SOURCE_MANIFEST_RELATIVE,
        "license_evidence": source.get("license_evidence", {}),
        "assets": {"dirt": dirt_entry, "grass001": grass_entry},
    }


def json_text(data: Any) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def write_runtime_package(repo_root: Path, source: dict[str, Any]) -> None:
    runtime_dir = repo_root / RUNTIME_RELATIVE_PATH
    runtime_dir.mkdir(parents=True, exist_ok=True)
    runtime_manifest_path = repo_root / RUNTIME_MANIFEST_RELATIVE
    write_text_atomic(runtime_manifest_path, json_text(runtime_manifest_from_source(source)))
    licenses_path = repo_root / RUNTIME_LICENSES_RELATIVE
    write_text_atomic(licenses_path, license_notice_text(source))
    print(f"Wrote runtime package metadata: {RUNTIME_MANIFEST_RELATIVE}")
    print(f"Wrote runtime license notice: {RUNTIME_LICENSES_RELATIVE}")


def write_text_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)


def license_notice_text(source: dict[str, Any]) -> str:
    """Render the shipped attribution notice from the canonical source manifest."""
    runtime = runtime_manifest_from_source(source)
    dirt = runtime["assets"]["dirt"]
    grass = runtime["assets"]["grass001"]
    lines = [
        "RC ground textures — license and attribution",
        "",
        f"License evidence checked: {source['license_evidence']['checked_date']}",
        "The original texture files are unchanged and are available under CC0 1.0 Universal.",
        "Attribution is not required; these credits are included voluntarily.",
        f"CC0 legal text: {CC0_TEXT_URL}",
        "",
        f"Dirt — {', '.join(dirt['author'])} (Poly Haven)",
        f"Asset: {dirt['asset_url']}",
        f"License: {dirt['license']} — {dirt['license_url']}",
    ]
    for record in dirt["files"]:
        source_url = record.get("url", "")
        lines.append(
            f"  {Path(record['path']).name}: {record['map']} from {source_url}"
        )
    lines.extend(
        [
            "",
            "Grass 001 — ambientCG (the asset API lists no individual creator).",
            f"Asset: {grass['asset_url']}",
            f"License: {grass['license']} — {grass['license_url']}",
        ]
    )
    for record in grass["files"]:
        source_url = record.get("url", "")
        lines.append(
            f"  {Path(record['path']).name}: {record['map']} from {source_url}"
            f" (archive member {record['archive_member']})"
        )
    lines.extend(
        [
            "",
            "Map meanings: albedo/Color is sRGB base color; normal is tangent-space OpenGL (+Y);",
            "roughness is a linear data map. The 4K originals are source-only A/B references,",
            "not part of the runtime package.",
            "",
        ]
    )
    return "\n".join(lines)


def checked_repo_file(repo_root: Path, relative_path: str) -> Path:
    root = repo_root.resolve()
    target = (root / relative_path).resolve()
    try:
        target.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"Manifest path escapes repository root: {relative_path}") from exc
    return target


def check_manifest(repo_root: Path, manifest_path: Path) -> None:
    """Verify retained bytes and Godot import settings without network or writes."""
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    records: list[tuple[str, dict[str, Any]]] = []
    for asset_id, asset in manifest.get("assets", {}).items():
        records.extend((asset_id, record) for record in asset.get("files", []))
    for asset_id, asset in manifest.get("ambientcg_grass", {}).items():
        if asset_id == "files" and isinstance(asset, list):
            records.extend(("ambientCG Grass001", record) for record in asset)

    if not records:
        raise ValueError("Manifest has no retained file records")

    for label, record in records:
        target = checked_repo_file(repo_root, str(record["path"]))
        if not target.is_file():
            raise ValueError(f"Missing retained texture for {label}: {record['path']}")
        size, md5, sha256 = hash_file(target)
        if size != record.get("size_bytes"):
            raise ValueError(f"Size mismatch for {record['path']}: got {size}")
        if md5 != record.get("md5") or sha256 != record.get("sha256"):
            raise ValueError(f"Hash mismatch for {record['path']}")
        dimensions = list(jpeg_dimensions(target))
        if dimensions != record.get("dimensions_px"):
            raise ValueError(f"Dimension mismatch for {record['path']}: {dimensions}")
        print(f"verified {record['path']}  {size} bytes  sha256:{sha256}")

    runtime_names = [
        name
        for definition in ASSETS.values()
        for name in definition.get("runtime_names", {}).values()
    ] + [mapping[0] for mapping in AMBIENTCG_MAPS.values()]
    import_dir = repo_root / "app" / "assets" / "landscape" / "rc-ground"
    for name in runtime_names:
        source = f"res://assets/landscape/rc-ground/{name}"
        sidecar = import_dir / f"{name}.import"
        if not sidecar.is_file():
            raise ValueError(f"Missing Godot import settings: {sidecar.relative_to(repo_root)}")
        config = sidecar.read_text(encoding="utf-8")
        expected_normal = 1 if "-normal." in name else 2
        for setting, expected in (
            ("compress/mode", "2"),
            ("compress/normal_map", str(expected_normal)),
            ("mipmaps/generate", "true"),
            ("detect_3d/compress_to", "1"),
        ):
            if f"{setting}={expected}" not in config:
                raise ValueError(
                    f"{sidecar.relative_to(repo_root)} must set {setting}={expected}"
                )
        if f'source_file="{source}"' not in config:
            raise ValueError(
                f"{sidecar.relative_to(repo_root)} has the wrong source_file remap"
            )
        has_uid = 'uid="uid://' in config
        has_imported_path = any(
            line.startswith("path.") and '="res://.godot/imported/' in line
            for line in config.splitlines()
        )
        if not has_uid or not has_imported_path:
            raise ValueError(
                f"{sidecar.relative_to(repo_root)} is missing Godot-generated remap metadata"
            )
        print(f"verified Godot import settings for {name}")

    runtime_manifest_path = repo_root / RUNTIME_MANIFEST_RELATIVE
    if not runtime_manifest_path.is_file():
        raise ValueError(f"Missing generated runtime manifest: {RUNTIME_MANIFEST_RELATIVE}")
    expected_runtime_manifest = json_text(runtime_manifest_from_source(manifest))
    actual_runtime_manifest = runtime_manifest_path.read_text(encoding="utf-8")
    if actual_runtime_manifest != expected_runtime_manifest:
        raise ValueError(
            f"{RUNTIME_MANIFEST_RELATIVE} is stale or differs from the exact source-manifest subset; "
            "run the importer with --emit-runtime"
        )
    print(f"verified exact source subset in {RUNTIME_MANIFEST_RELATIVE}")

    runtime_licenses_path = repo_root / RUNTIME_LICENSES_RELATIVE
    if not runtime_licenses_path.is_file():
        raise ValueError(f"Missing runtime license notice: {RUNTIME_LICENSES_RELATIVE}")
    if runtime_licenses_path.read_text(encoding="utf-8") != license_notice_text(manifest):
        raise ValueError(
            f"{RUNTIME_LICENSES_RELATIVE} differs from the source manifest; "
            "run the importer with --emit-runtime"
        )
    print(f"verified {RUNTIME_LICENSES_RELATIVE}")


def retained_4k_paths(source: dict[str, Any]) -> list[str]:
    """Return retained 4K file paths that --runtime-only would omit."""
    records: list[dict[str, Any]] = []
    for asset in source.get("assets", {}).values():
        records.extend(asset.get("files", []))
    records.extend(source.get("ambientcg_grass", {}).get("files", []))
    return [
        str(record["path"])
        for record in records
        if record.get("path") and str(record.get("resolution", "")).lower() == "4k"
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root (defaults to the parent of tools/)",
    )
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument(
        "--runtime-only",
        action="store_true",
        help="omit 4K source maps on a fresh intake; refuses to overwrite a manifest that records retained 4K files",
    )
    modes.add_argument(
        "--check",
        action="store_true",
        help="verify the manifest, retained files and import settings offline without writing",
    )
    modes.add_argument(
        "--emit-runtime",
        action="store_true",
        help="regenerate the runtime manifest and license notice offline from the source manifest",
    )
    args = parser.parse_args()
    root = args.root.resolve()
    manifest_path = root / "assets" / "landscape" / "rc-ground" / "manifest.json"
    if args.check:
        if not manifest_path.is_file():
            raise ValueError(f"Missing provenance manifest: {manifest_path}")
        check_manifest(root, manifest_path)
        print("All retained RC ground assets and import settings match the manifest.")
        return 0
    if args.emit_runtime:
        if not manifest_path.is_file():
            raise ValueError(f"Missing provenance manifest: {manifest_path}")
        source_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        write_runtime_package(root, source_manifest)
        return 0
    previous_manifest: dict[str, Any] = {}
    if manifest_path.is_file():
        try:
            previous_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            raise ValueError(f"Invalid existing manifest {manifest_path}: {error}") from error
    if args.runtime_only:
        retained_sources = retained_4k_paths(previous_manifest)
        if retained_sources:
            paths = ", ".join(retained_sources)
            raise ValueError(
                "--runtime-only would drop retained 4K records from the source manifest. "
                "Run the full importer to preserve them, or start with a fresh source manifest. "
                f"Recorded files: {paths}"
            )
    manifest = import_assets(
        root,
        include_4k=not args.runtime_only,
        previous_manifest=previous_manifest,
    )
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    write_text_atomic(manifest_path, json_text(manifest))
    print(f"Wrote provenance manifest: {manifest_path.relative_to(root).as_posix()}")
    write_runtime_package(root, manifest)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (BadZipFile, OSError, TypeError, urllib.error.URLError, ValueError, KeyError) as error:
        print(f"import_rc_ground.py: error: {error}", file=sys.stderr)
        raise SystemExit(1)
