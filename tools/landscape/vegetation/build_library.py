#!/usr/bin/env python3
"""Extract the pinned, unmodified Quaternius vegetation source into the Godot app."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
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

CROPS_ARCHIVE = ROOT / "assets/landscape/vegetation/source/quaternius_lowpoly_crops_cc0.zip"
CROPS_ARCHIVE_SHA256 = "48de7f1e092750a3832501e79d1463abeec8218c76090fc4b81fa8dfccacdb52"
CROPS_ARCHIVE_BYTES = 13_368_975
CROPS_SOURCE_URL = "https://opengameart.org/content/lowpoly-crops-pack"
CROPS_SOURCE_ENTRY_PREFIX = "Nature Crops Pack - Jan 2020/OBJ/"
CROPS_NOTICE = ROOT / "assets/landscape/vegetation/source/Quaternius_Crops_CC0.txt"

REED_ARCHIVE = ROOT / "assets/landscape/vegetation/source/aredon_lowpoly_reed_cc0.zip"
REED_ARCHIVE_SHA256 = "03fd4f90d92618090829bac1152e4280327edb179139ae3f0c66542af31b89bd"
REED_ARCHIVE_BYTES = 140_207
REED_SOURCE_URL = "https://opengameart.org/content/lowpoly-reed"
REED_NOTICE = ROOT / "assets/landscape/vegetation/source/Aredon_Reed_CC0.txt"

SOURCE_NOTICES = {
    CROPS_NOTICE: (
        "Downloaded source: LowPoly Crops Pack\n"
        "Author: Quaternius\n"
        f"Source page: {CROPS_SOURCE_URL}\n"
        "License: CC0 1.0 Universal (license shown on the OpenGameArt source page).\n"
        "Original archive: quaternius_lowpoly_crops_cc0.zip\n"
        f"Retrieved: {RETRIEVED}\n"
        f"Bytes: {CROPS_ARCHIVE_BYTES}\n"
        f"SHA-256: {CROPS_ARCHIVE_SHA256}\n"
        "Selected files are copied byte-for-byte from the archive's OBJ directory.\n"
    ).encode("utf-8"),
    REED_NOTICE: (
        "Downloaded source: LowPoly Reed\n"
        "Author: Aredon\n"
        f"Source page: {REED_SOURCE_URL}\n"
        "License: CC0 Public Domain (license shown on the OpenGameArt source page).\n"
        "Original archive: aredon_lowpoly_reed_cc0.zip\n"
        f"Retrieved: {RETRIEVED}\n"
        f"Bytes: {REED_ARCHIVE_BYTES}\n"
        f"SHA-256: {REED_ARCHIVE_SHA256}\n"
        "Selected OBJ and MTL files are copied byte-for-byte from the archive.\n"
    ).encode("utf-8"),
}

# These are direct glTF mesh exports from the Standard archive. The pipeline
# copies them byte-for-byte; it does not author or rebuild plant geometry.
ASSETS = (
    ("common_tree_1", "CommonTree_1", "tree", "mature broadleaf tree"),
    ("common_tree_2", "CommonTree_2", "tree", "fuller branching broadleaf tree"),
    ("common_tree_3", "CommonTree_3", "tree", "upright broadleaf tree"),
    ("common_tree_4", "CommonTree_4", "tree", "sparse crown broadleaf tree"),
    ("pine_1", "Pine_1", "tree", "mature pine tree"),
    ("pine_2", "Pine_2", "tree", "broad-cone pine tree"),
    ("pine_3", "Pine_3", "tree", "open-lower-trunk pine tree"),
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

CROP_ASSETS = (
    ("corn_4", "Corn_4", "mature corn plant"),
    ("wheat_4", "Wheat_4", "mature wheat stalk"),
)

REED_ASSETS = (
    ("reed_aredon", "reed", "low-poly reed clump"),
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
    windows = PureWindowsPath(value)
    if (
        parsed.is_absolute()
        or windows.drive
        or windows.root
        or not parsed.parts
        or any(part in ("", ".", "..") for part in parsed.parts)
        or ":" in value
    ):
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
    minimum = [float("inf"), float("inf"), float("inf")]
    maximum = [float("-inf"), float("-inf"), float("-inf")]
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
            for axis in range(3):
                minimum[axis] = min(minimum[axis], float(bounds["min"][axis]))
                maximum[axis] = max(maximum[axis], float(bounds["max"][axis]))

    if triangles <= 0 or surfaces <= 0 or any(minimum[axis] >= maximum[axis] for axis in range(3)):
        raise BuildError(f"{source_name}: glTF has no measurable triangle geometry")

    height = maximum[1] - minimum[1]
    grounded_minimum = [minimum[0], 0.0, minimum[2]]
    grounded_maximum = [maximum[0], height, maximum[2]]

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
            "min": [round(value, 6) for value in minimum],
            "max": [round(value, 6) for value in maximum],
            "size": [round(maximum[axis] - minimum[axis], 6) for axis in range(3)],
            "height": round(height, 6),
            "ground_offset": round(-minimum[1], 6),
        },
        "grounded_bounds_m": {
            "min": [round(value, 6) for value in grounded_minimum],
            "max": [round(value, 6) for value in grounded_maximum],
            "size": [round(grounded_maximum[axis] - grounded_minimum[axis], 6) for axis in range(3)],
        },
        "textures": sorted(textures, key=lambda item: item["uri"].lower()),
        "dependencies": sorted(set(dependencies), key=str.lower),
    }


def obj_metadata(source_name: str, obj_bytes: bytes) -> dict:
    try:
        source_text = obj_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise BuildError(f"invalid UTF-8 in OBJ {source_name}: {exc}") from exc

    vertices: list[tuple[float, float, float]] = []
    triangles = 0
    material_names: set[str] = set()
    material_libraries: set[str] = set()
    for line_number, line in enumerate(source_text.splitlines(), start=1):
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "v":
            if len(fields) < 4:
                raise BuildError(f"{source_name}:{line_number}: malformed vertex")
            try:
                vertices.append((float(fields[1]), float(fields[2]), float(fields[3])))
            except ValueError as exc:
                raise BuildError(f"{source_name}:{line_number}: nonnumeric vertex") from exc
        elif fields[0] == "f":
            if len(fields) < 4:
                raise BuildError(f"{source_name}:{line_number}: face has fewer than three vertices")
            triangles += len(fields) - 3
        elif fields[0] == "usemtl" and len(fields) > 1:
            material_names.add(fields[1])
        elif fields[0] == "mtllib" and len(fields) > 1:
            material_libraries.update(archive_path(name) for name in fields[1:])

    if not vertices or triangles <= 0:
        raise BuildError(f"{source_name}: OBJ has no measurable triangle geometry")
    if not material_libraries:
        raise BuildError(f"{source_name}: OBJ is missing its MTL material library")

    minimum = [min(vertex[axis] for vertex in vertices) for axis in range(3)]
    maximum = [max(vertex[axis] for vertex in vertices) for axis in range(3)]
    if any(minimum[axis] >= maximum[axis] for axis in range(3)):
        raise BuildError(f"{source_name}: OBJ has degenerate 3D bounds")
    height = maximum[1] - minimum[1]
    grounded_minimum = [minimum[0], 0.0, minimum[2]]
    grounded_maximum = [maximum[0], height, maximum[2]]

    return {
        "source_triangles": triangles,
        "source_surfaces": max(1, len(material_names)),
        "source_materials": len(material_names),
        "source_bounds_m": {
            "min": [round(value, 6) for value in minimum],
            "max": [round(value, 6) for value in maximum],
            "size": [round(maximum[axis] - minimum[axis], 6) for axis in range(3)],
            "height": round(height, 6),
            "ground_offset": round(-minimum[1], 6),
        },
        "grounded_bounds_m": {
            "min": [round(value, 6) for value in grounded_minimum],
            "max": [round(value, 6) for value in grounded_maximum],
            "size": [round(grounded_maximum[axis] - grounded_minimum[axis], 6) for axis in range(3)],
        },
        "material_libraries": sorted(material_libraries, key=str.lower),
    }


def catalog_for(
    archive: ZipFile,
    crops_archive: ZipFile,
    reed_archive: ZipFile,
) -> tuple[dict, dict[str, bytes]]:
    license_bytes = read_member(archive, LICENSE_ENTRY)
    if sha256_bytes(license_bytes) != LICENSE_SHA256:
        raise BuildError("embedded Standard license hash does not match the pinned CC0 evidence")

    pending_files: dict[str, bytes] = {"LICENSE.txt": license_bytes}
    file_origins: dict[str, str] = {"LICENSE.txt": LICENSE_ENTRY}
    source_member_bytes: dict[str, bytes] = {}
    assets: list[dict] = []
    for asset_id, model_name, role, description in ASSETS:
        source_entry = f"glTF/{model_name}.gltf"
        gltf_bytes = read_member(archive, source_entry)
        metadata = gltf_metadata(archive, source_entry, gltf_bytes)
        runtime_scene = f"res://assets/landscape/vegetation/models/{model_name}.gltf"
        file_entries = list(metadata["dependencies"])

        for entry in file_entries:
            if entry not in source_member_bytes:
                source_member_bytes[entry] = read_member(archive, entry)
            relative = PurePosixPath(entry).relative_to("glTF")
            runtime_path = f"models/{relative.as_posix()}"
            pending_files[runtime_path] = source_member_bytes[entry]
            file_origins[runtime_path] = entry

        assets.append(
            {
                "id": asset_id,
                "source_id": "quaternius_standard",
                "source_name": model_name,
                "description": description,
                "role": role,
                "scene": runtime_scene,
                "source_entry": source_entry,
                "source_sha256": sha256_bytes(gltf_bytes),
                "source_format": "glTF 2.0",
                **metadata,
                "lod": {"source_supplied": False, "godot_import_generate": True},
            }
        )

    def add_obj_family(
        source_archive: ZipFile,
        source_id: str,
        source_prefix: str,
        runtime_subdir: str,
        family_assets: tuple[tuple[str, str, str], ...],
        role: str,
    ) -> None:
        for asset_id, model_name, description in family_assets:
            source_entry = f"{source_prefix}{model_name}.obj"
            obj_bytes = read_member(source_archive, source_entry)
            metadata = obj_metadata(source_entry, obj_bytes)
            parent = PurePosixPath(source_entry).parent
            dependency_entries = [source_entry]
            for material_library in metadata["material_libraries"]:
                dependency_entries.append((parent / material_library).as_posix())

            runtime_dir = f"models/additional/{runtime_subdir}"
            runtime_mesh = f"res://assets/landscape/vegetation/{runtime_dir}/{model_name}.obj"
            source_hashes: dict[str, str] = {"mesh": sha256_bytes(obj_bytes)}
            for entry in dependency_entries:
                data = obj_bytes if entry == source_entry else read_member(source_archive, entry)
                runtime_name = PurePosixPath(entry).name
                runtime_path = f"{runtime_dir}/{runtime_name}"
                pending_files[runtime_path] = data
                file_origins[runtime_path] = entry
                if entry != source_entry:
                    source_hashes[runtime_name] = sha256_bytes(data)

            assets.append(
                {
                    "id": asset_id,
                    "source_id": source_id,
                    "source_name": model_name,
                    "description": description,
                    "role": role,
                    "mesh": runtime_mesh,
                    "source_entry": source_entry,
                    "source_sha256": sha256_bytes(obj_bytes),
                    "source_dependency_sha256": source_hashes,
                    "source_format": "Wavefront OBJ",
                    "source_material_format": "Wavefront MTL",
                    **metadata,
                    "lod": {"source_supplied": False, "godot_import_generate": False},
                }
            )

    add_obj_family(
        crops_archive,
        "quaternius_crops",
        CROPS_SOURCE_ENTRY_PREFIX,
        "quaternius_crops",
        CROP_ASSETS,
        "crop",
    )
    add_obj_family(
        reed_archive,
        "aredon_reed",
        "",
        "aredon_reed",
        REED_ASSETS,
        "reed",
    )

    file_records = [
        {
            "path": runtime_path,
            "source_entry": file_origins[runtime_path],
            "bytes": len(data),
            "sha256": sha256_bytes(data),
        }
        for runtime_path, data in sorted(pending_files.items(), key=lambda item: item[0].lower())
    ]

    source_records = [
        {
            "id": "quaternius_standard",
            "title": "Quaternius Stylized Nature MegaKit Standard",
            "author": "Quaternius",
            "url": SOURCE_URL,
            "upload_id": SOURCE_UPLOAD_ID,
            "archive": "assets/landscape/vegetation/source/quaternius_stylized_nature_megakit_standard.zip",
            "archive_bytes": ARCHIVE_BYTES,
            "archive_sha256": ARCHIVE_SHA256,
            "license": "CC0-1.0, embedded License_Standard.txt",
            "license_sha256": LICENSE_SHA256,
            "license_evidence": "assets/landscape/vegetation/source/License_Standard.txt",
        },
        {
            "id": "quaternius_crops",
            "title": "LowPoly Crops Pack",
            "author": "Quaternius",
            "url": CROPS_SOURCE_URL,
            "archive": "assets/landscape/vegetation/source/quaternius_lowpoly_crops_cc0.zip",
            "archive_bytes": CROPS_ARCHIVE_BYTES,
            "archive_sha256": CROPS_ARCHIVE_SHA256,
            "license": "CC0-1.0, as shown on the OpenGameArt source page",
            "license_evidence": CROPS_NOTICE.relative_to(ROOT).as_posix(),
        },
        {
            "id": "aredon_reed",
            "title": "LowPoly Reed",
            "author": "Aredon",
            "url": REED_SOURCE_URL,
            "archive": "assets/landscape/vegetation/source/aredon_lowpoly_reed_cc0.zip",
            "archive_bytes": REED_ARCHIVE_BYTES,
            "archive_sha256": REED_ARCHIVE_SHA256,
            "license": "CC0-1.0, as shown on the OpenGameArt source page",
            "license_evidence": REED_NOTICE.relative_to(ROOT).as_posix(),
        },
    ]

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
        "sources": source_records,
        "import": {
            "format": "glTF 2.0 and Wavefront OBJ/MTL",
            "geometry_policy": "unmodified downloaded geometry",
            "lod_policy": "Godot 4.7.2 ResourceImporterScene automatic mesh LODs enabled for glTF assets; Wavefront OBJ assets use supplied geometry",
            "shared_material_policy": "original downloaded glTF materials and textures or OBJ/MTL diffuse materials; shared source files extracted once",
        },
        "counts": {
            "trees": sum(item["role"] == "tree" for item in assets),
            "shrubs": sum(item["role"] == "shrub" for item in assets),
            "grass_and_herbs": sum(item["role"] in ("grass", "herb") for item in assets),
            "flowers": sum(item["role"] == "flower" for item in assets),
            "crops": sum(item["role"] == "crop" for item in assets),
            "reeds": sum(item["role"] == "reed" for item in assets),
            "total_assets": len(assets),
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


def output_path(output_root: Path, relative: str) -> Path:
    """Resolve a generated relative path and refuse to write outside its root."""
    safe_relative = archive_path(relative)
    root = output_root.resolve()
    target = root.joinpath(*PurePosixPath(safe_relative).parts)
    try:
        target.resolve().relative_to(root)
    except ValueError as exc:
        raise BuildError(f"generated path escapes output root: {relative!r}") from exc
    return target


def expected_outputs(
    catalog: dict,
    library_files: dict[str, bytes],
    output_root: Path,
    *,
    write_source_evidence: bool,
) -> dict[Path, bytes]:
    expected = {
        output_path(output_root, relative): data
        for relative, data in library_files.items()
    }
    expected[output_path(output_root, "catalog.json")] = (
        json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"
    ).encode("utf-8")
    if write_source_evidence:
        expected[SOURCE_LICENSE] = library_files["LICENSE.txt"]
        expected.update(SOURCE_NOTICES)
    return expected


def display_path(path: Path) -> str:
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify archive and generated files without writing")
    parser.add_argument(
        "--output-root",
        type=Path,
        help=(
            "write the generated library here instead of app/assets/landscape/vegetation; "
            "relative paths are resolved from the repository root"
        ),
    )
    args = parser.parse_args(argv)
    output_root = args.output_root or RUNTIME
    if not output_root.is_absolute():
        output_root = ROOT / output_root
    output_root = output_root.resolve()

    pinned_archives = (
        (ARCHIVE, ARCHIVE_BYTES, ARCHIVE_SHA256, "Quaternius Standard"),
        (CROPS_ARCHIVE, CROPS_ARCHIVE_BYTES, CROPS_ARCHIVE_SHA256, "Quaternius crops"),
        (REED_ARCHIVE, REED_ARCHIVE_BYTES, REED_ARCHIVE_SHA256, "Aredon reed"),
    )
    for archive_path_value, expected_bytes, expected_hash, label in pinned_archives:
        if not archive_path_value.is_file():
            raise BuildError(f"missing pinned {label} source archive: {archive_path_value}")
        archive_size = archive_path_value.stat().st_size
        archive_hash = sha256_file(archive_path_value)
        if archive_size != expected_bytes or archive_hash != expected_hash:
            raise BuildError(
                f"{label} source archive does not match the pinned upload: "
                f"bytes={archive_size}, sha256={archive_hash}"
            )

    try:
        with ZipFile(ARCHIVE) as archive:
            with ZipFile(CROPS_ARCHIVE) as crops_archive, ZipFile(REED_ARCHIVE) as reed_archive:
                catalog, runtime_files = catalog_for(
                    archive,
                    crops_archive,
                    reed_archive,
                )
    except BadZipFile as exc:
        raise BuildError(f"source archive is not a valid ZIP: {exc}") from exc

    expected = expected_outputs(
        catalog,
        runtime_files,
        output_root,
        write_source_evidence=args.output_root is None,
    )

    if args.check:
        errors: list[str] = []
        for path, expected_bytes in expected.items():
            if not path.is_file():
                errors.append(f"missing generated file: {display_path(path)}")
                continue
            actual = path.read_bytes()
            if actual != expected_bytes:
                errors.append(f"generated file differs: {display_path(path)}")
        if errors:
            raise BuildError("\n".join(errors))
    else:
        for path, data in expected.items():
            write_if_changed(path, data)
    print(
        f"{len(catalog['assets'])} imported vegetation assets, "
        f"{catalog['counts']['source_triangles_one_of_each']:,} source triangles, "
        f"{len(catalog['files'])} verified runtime files; "
        f"{len(pinned_archives)} pinned source archives verified; "
        f"output={display_path(output_root)}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BuildError as exc:
        print(f"vegetation build failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
