#!/usr/bin/env python3
"""Extract the pinned, unmodified Quaternius vegetation source into the Godot app."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
from zipfile import BadZipFile, ZipFile


ROOT = Path(__file__).resolve().parents[3]
ARCHIVE = ROOT / "assets/landscape/vegetation/source/quaternius_stylized_nature_megakit_standard.zip"
SOURCE_LICENSE = ROOT / "assets/landscape/vegetation/source/License_Standard.txt"
RUNTIME = ROOT / "app/assets/landscape/vegetation"
RUNTIME_MODELS = RUNTIME / "models"
RUNTIME_LICENSE = RUNTIME / "LICENSE.txt"
RUNTIME_CATALOG = RUNTIME / "catalog.json"

ARCHIVE_SHA256 = "298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9"
ARCHIVE_BYTES = 104_088_529
LICENSE_ENTRY = "License_Standard.txt"
LICENSE_SHA256 = "120710e542c3ebaf83856c4eb55b4a1e680593b39302eba7fdc5d942dfe78c58"
SOURCE_URL = "https://quaternius.itch.io/stylized-nature-megakit"
SOURCE_UPLOAD_ID = "11055123"
RETRIEVED = "2026-10-13"

# These are direct glTF mesh exports from the Standard archive. The pipeline
# copies them byte-for-byte; it does not author or rebuild plant geometry.
ASSETS = (
    ("common_tree_1", "CommonTree_1", "tree", "mature broadleaf tree"),
    ("pine_1", "Pine_1", "tree", "mature pine tree"),
    ("bush_common", "Bush_Common", "shrub", "leafy shrub"),
    ("bush_common_flowers", "Bush_Common_Flowers", "shrub", "flowering shrub"),
    ("grass_common_short", "Grass_Common_Short", "grass", "short meadow grass clump"),
    ("grass_common_tall", "Grass_Common_Tall", "grass", "tall meadow grass clump"),
    ("grass_wispy_tall", "Grass_Wispy_Tall", "grass", "wispy tall grass clump"),
    ("fern_1", "Fern_1", "herb", "fern"),
    ("flower_3_group", "Flower_3_Group", "flower", "flower group, family 3"),
    ("flower_4_group", "Flower_4_Group", "flower", "flower group, family 4"),
    ("clover_1", "Clover_1", "flower", "clover groundcover"),
)


class BuildError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def archive_path(value: str) -> str:
    """Accept only a safe, archive-relative POSIX path."""
    parsed = PurePosixPath(value)
    if parsed.is_absolute() or not parsed.parts or any(part in ("", ".", "..") for part in parsed.parts):
        raise BuildError(f"unsafe archive path: {value!r}")
    if "\\" in value or "\x00" in value:
        raise BuildError(f"unsafe archive path: {value!r}")
    return parsed.as_posix()


def read_member(archive: ZipFile, name: str) -> bytes:
    safe_name = archive_path(name)
    try:
        return archive.read(safe_name)
    except KeyError as exc:
        raise BuildError(f"missing source archive member: {safe_name}") from exc


def gltf_metadata(archive: ZipFile, source_name: str, gltf_bytes: bytes) -> dict:
    try:
        gltf = json.loads(gltf_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BuildError(f"invalid JSON in glTF {source_name}: {exc}") from exc

    triangles = 0
    surfaces = 0
    material_indices: set[int] = set()
    min_y = float("inf")
    max_y = float("-inf")
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            surfaces += 1
            index = primitive.get("indices")
            if index is not None:
                accessors = gltf.get("accessors", [])
                if index >= len(accessors):
                    raise BuildError(f"{source_name}: primitive index accessor {index} is missing")
                count = accessors[index].get("count", 0)
            else:
                position = primitive.get("attributes", {}).get("POSITION")
                accessors = gltf.get("accessors", [])
                if position is None or position >= len(accessors):
                    raise BuildError(f"{source_name}: primitive has no usable index or position accessor")
                count = accessors[position].get("count", 0)
            if count % 3 != 0:
                raise BuildError(f"{source_name}: triangle index count {count} is not divisible by three")
            triangles += count // 3

            material = primitive.get("material")
            if material is not None:
                material_indices.add(material)
            position_index = primitive.get("attributes", {}).get("POSITION")
            if position_index is None or position_index >= len(accessors):
                raise BuildError(f"{source_name}: primitive has no usable position accessor")
            bounds = accessors[position_index]
            if len(bounds.get("min", [])) < 3 or len(bounds.get("max", [])) < 3:
                raise BuildError(f"{source_name}: position accessor has no 3D bounds")
            min_y = min(min_y, float(bounds["min"][1]))
            max_y = max(max_y, float(bounds["max"][1]))

    if triangles <= 0 or surfaces <= 0 or not (min_y < max_y):
        raise BuildError(f"{source_name}: glTF has no measurable triangle geometry")

    textures: list[dict] = []
    for image in gltf.get("images", []):
        uri = image.get("uri")
        if not isinstance(uri, str):
            raise BuildError(f"{source_name}: embedded or missing image URIs are unsupported")
        uri = archive_path(uri)
        textures.append({"uri": uri, "source_entry": f"glTF/{uri}"})

    buffers: list[str] = []
    for buffer in gltf.get("buffers", []):
        uri = buffer.get("uri")
        if not isinstance(uri, str):
            raise BuildError(f"{source_name}: embedded or missing buffer URIs are unsupported")
        buffers.append(archive_path(uri))

    model_base = PurePosixPath(source_name).parent
    dependencies = [source_name]
    dependencies.extend((model_base / buffer).as_posix() for buffer in buffers)
    dependencies.extend((model_base / item["uri"]).as_posix() for item in textures)

    # The source pack uses direct mesh nodes. Refuse transforms that would make
    # raw accessor bounds differ from the imported scene's local bounds.
    for node in gltf.get("nodes", []):
        if "mesh" in node and any(key in node for key in ("matrix", "translation", "rotation", "scale")):
            raise BuildError(f"{source_name}: transformed mesh node requires explicit bounds review")

    return {
        "source_triangles": triangles,
        "source_surfaces": surfaces,
        "source_materials": len(material_indices),
        "source_bounds_m": {
            "min_y": round(min_y, 6),
            "max_y": round(max_y, 6),
            "height": round(max_y - min_y, 6),
            "ground_offset": round(-min_y, 6),
        },
        "textures": sorted(textures, key=lambda item: item["uri"].lower()),
        "dependencies": sorted(set(dependencies), key=str.lower),
    }


def catalog_for(archive: ZipFile) -> tuple[dict, dict[str, bytes]]:
    license_bytes = read_member(archive, LICENSE_ENTRY)
    if sha256_bytes(license_bytes) != LICENSE_SHA256:
        raise BuildError("embedded Standard license hash does not match the pinned CC0 evidence")

    pending_files: dict[str, bytes] = {"LICENSE.txt": license_bytes}
    sources: dict[str, bytes] = {}
    assets: list[dict] = []
    for asset_id, model_name, role, description in ASSETS:
        source_entry = f"glTF/{model_name}.gltf"
        gltf_bytes = read_member(archive, source_entry)
        metadata = gltf_metadata(archive, source_entry, gltf_bytes)
        runtime_scene = f"res://assets/landscape/vegetation/models/{model_name}.gltf"
        file_entries = list(metadata["dependencies"])

        for entry in file_entries:
            if entry not in sources:
                sources[entry] = read_member(archive, entry)
            relative = PurePosixPath(entry).relative_to("glTF")
            runtime_path = f"models/{relative.as_posix()}"
            pending_files[runtime_path] = sources[entry]

        assets.append(
            {
                "id": asset_id,
                "source_name": model_name,
                "description": description,
                "role": role,
                "scene": runtime_scene,
                "source_entry": source_entry,
                "source_sha256": sha256_bytes(gltf_bytes),
                **metadata,
                "lod": {"source_supplied": False, "godot_import_generate": True},
            }
        )

    file_records = [
        {
            "path": runtime_path,
            "source_entry": f"glTF/{PurePosixPath(runtime_path).relative_to('models').as_posix()}" if runtime_path.startswith("models/") else LICENSE_ENTRY,
            "bytes": len(data),
            "sha256": sha256_bytes(data),
        }
        for runtime_path, data in sorted(pending_files.items(), key=lambda item: item[0].lower())
    ]
    # Shared textures are present once in the runtime directory. Record every
    # upstream member explicitly so package updates cannot silently replace them.
    for record in file_records:
        if record["path"].startswith("models/"):
            record["source_entry"] = f"glTF/{PurePosixPath(record['path']).relative_to('models').as_posix()}"

    catalog = {
        "format": "openrc-imported-vegetation v1",
        "source": {
            "title": "Quaternius Stylized Nature MegaKit Standard",
            "author": "Quaternius",
            "url": SOURCE_URL,
            "upload_id": SOURCE_UPLOAD_ID,
            "retrieved": RETRIEVED,
            "archive": "assets/landscape/vegetation/source/quaternius_stylized_nature_megakit_standard.zip",
            "archive_bytes": ARCHIVE_BYTES,
            "archive_sha256": ARCHIVE_SHA256,
            "license": "CC0-1.0, embedded License_Standard.txt",
            "license_sha256": LICENSE_SHA256,
        },
        "import": {
            "format": "glTF 2.0",
            "geometry_policy": "unmodified downloaded geometry",
            "lod_policy": "Godot 4.7.2 ResourceImporterScene automatic mesh LODs enabled",
            "shared_material_policy": "original downloaded glTF materials and textures; shared source files extracted once",
        },
        "counts": {
            "trees": 2,
            "shrubs": 2,
            "grass_and_herbs": 4,
            "flowers": 3,
            "source_triangles_one_of_each": sum(
                item["source_triangles"] for item in assets
            ),
        },
        "files": file_records,
        "assets": assets,
    }
    return catalog, pending_files


def write_if_changed(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() == data:
        return
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify archive and generated files without writing")
    args = parser.parse_args()

    if not ARCHIVE.is_file():
        raise BuildError(f"missing pinned source archive: {ARCHIVE}")
    archive_size = ARCHIVE.stat().st_size
    archive_hash = sha256_file(ARCHIVE)
    if archive_size != ARCHIVE_BYTES or archive_hash != ARCHIVE_SHA256:
        raise BuildError(
            "source archive does not match the pinned Standard upload: "
            f"bytes={archive_size}, sha256={archive_hash}"
        )

    try:
        with ZipFile(ARCHIVE) as archive:
            catalog, runtime_files = catalog_for(archive)
    except BadZipFile as exc:
        raise BuildError(f"source archive is not a valid ZIP: {exc}") from exc

    expected: dict[Path, bytes] = {
        RUNTIME / relative: data for relative, data in runtime_files.items()
    }
    expected[RUNTIME_CATALOG] = (json.dumps(catalog, indent=2, ensure_ascii=False) + "\n").encode("utf-8")

    if args.check:
        errors: list[str] = []
        for path, expected_bytes in expected.items():
            if not path.is_file():
                errors.append(f"missing generated file: {path.relative_to(ROOT).as_posix()}")
                continue
            actual = path.read_bytes()
            if actual != expected_bytes:
                errors.append(f"generated file differs: {path.relative_to(ROOT).as_posix()}")
        if errors:
            raise BuildError("\n".join(errors))
    else:
        for path, data in expected.items():
            write_if_changed(path, data)
        write_if_changed(SOURCE_LICENSE, runtime_files["LICENSE.txt"])

    print(
        f"{len(catalog['assets'])} imported vegetation assets, "
        f"{catalog['counts']['source_triangles_one_of_each']:,} source triangles, "
        f"{len(catalog['files'])} verified files; archive SHA-256 {archive_hash}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BuildError as exc:
        print(f"vegetation build failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
