#!/usr/bin/env python3
"""Stage two complete Poly Haven shrub clumps as external-only atlas sources.

The supplier's 1K glTF, buffer and maps remain immutable. Reuse the existing
understory conversion machinery to extract an entire mesh node, remove only its
gallery translation, and pack the separate 16-bit alpha map into diffuse RGBA8.
The original double-sided MASK material and 0.5 cutoff are retained. No output
is copied into the application or used as a runtime 3D placement.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import convert_realistic_understory as base


ROOT = Path(__file__).resolve().parents[3]
SOURCE_RELATIVE = Path("assets/landscape/vegetation/source/woodland_shrubs_2026")
DERIVED_RELATIVE = Path("assets/landscape/vegetation/derived/woodland_shrubs_2026")
RECEIPT = SOURCE_RELATIVE / "download_manifest.json"
NOTICE = SOURCE_RELATIVE / "SOURCE_LICENSE.md"
LEGAL = SOURCE_RELATIVE / "CC0-1.0-legalcode.en.html"
CATALOG = "external_catalog.json"
MANIFEST = "conversion_manifest.json"

PINNED_INPUTS = {
    "shrub_03/polyhaven_files.json": "01c34bcc8da5e97b9a84350254de868016d348f067df98782a368e7fca088a03",
    "shrub_03/polyhaven_info.json": "205d16658cecb8b7bad59ed98d04baeb84f70671c3114cda5f7280435d9ea450",
    "shrub_03/shrub_03_1k.gltf": "b76d7c14bc027e834e82d3f984c32b5d060e62908aa90ff9420a637ca253a8ea",
    "shrub_03/shrub_03.bin": "bf4df21e6d2a2bc5f00b4c9142f776171fe7da00cf960001825748067af542b6",
    "shrub_03/textures/shrub_03_alpha_1k.png": "daef00278879a024fd05216aaa1376067a5f25f1b911d08d9bbdc50fda4a0d66",
    "shrub_03/textures/shrub_03_diff_1k.jpg": "3cadc7aba46d3aabbd7d6d2b1d04aa32e2a7da0bc87c2d38ef3cb1ee42cb03ec",
    "shrub_03/textures/shrub_03_nor_gl_1k.jpg": "ff856bacfce859b8a7555dd9a3b92fbd36b2e775d486be71df485afb4235d6c9",
    "shrub_03/textures/shrub_03_arm_1k.jpg": "3e2b16812a623037138eedace958210c5f3443a827bbe69663045bba5612f815",
}
RECEIPT_SHA256 = "32eb24d0b4dcc67615bf6d03ee70393d122cc7c196a452e132e5f9e0bccf3de5"
NOTICE_SHA256 = "0fb47f4e64068a7903e9b44a048b88d82b2c296ba82f5bbf9c4d60be09bad9db"
LEGAL_SHA256 = "b43732f4c1463b087cf10d4daf8d8766514b2bf8f21bc5ef50905f95be227726"


def variant(letter: str, mesh: str, triangles: int) -> dict[str, Any]:
    return {
        "id": f"polyhaven_shrub_03_{letter}",
        "source_id": "polyhaven_shrub_03",
        "source_asset": "shrub_03",
        "source_name": f"shrub_03_{letter}",
        "source_node_name": f"shrub_03_{letter}",
        "source_mesh_name": mesh,
        "source_page": "https://polyhaven.com/a/shrub_03",
        "role": "shrub",
        "expected_triangles": triangles,
        "source_material_mode": "MASK",
        "output_material_mode": "MASK",
        "output_alpha_cutoff": 0.5,
        "source_gltf": "shrub_03/shrub_03_1k.gltf",
        "source_bin": "shrub_03/shrub_03.bin",
        "source_diffuse": "shrub_03/textures/shrub_03_diff_1k.jpg",
        "source_alpha": "shrub_03/textures/shrub_03_alpha_1k.png",
        "source_normal": "shrub_03/textures/shrub_03_nor_gl_1k.jpg",
        "source_arm": "shrub_03/textures/shrub_03_arm_1k.jpg",
        "output_gltf": f"shrub_03_{letter}.gltf",
        "output_bin": "shrub_03.bin",
        "output_diffuse": "textures/shrub_03_base_color_alpha_1k.png",
        "output_normal": "textures/shrub_03_nor_gl_1k.jpg",
        "output_arm": "textures/shrub_03_arm_1k.jpg",
        "output_mesh_lod": {
            "source_supplied": False,
            "godot_import_generate": False,
            "note": "The 1K glTF names four separate gallery clumps, not LOD levels; only this complete clump is selected.",
        },
    }


VARIANTS = [variant("a", "Plane.002", 2385), variant("b", "Plane.054", 2134)]


def verify_sources(repo: Path, source_root: Path) -> list[dict[str, Any]]:
    # The shared conversion functions use these paths only within this process.
    base.SOURCE_RELATIVE = SOURCE_RELATIVE
    base.DERIVED_RELATIVE = DERIVED_RELATIVE
    base.DOWNLOAD_MANIFEST = RECEIPT
    base.CC0_LEGALCODE = LEGAL
    base.CC0_LEGALCODE_SHA256 = LEGAL_SHA256
    base.PINNED_SOURCE_SHA256 = PINNED_INPUTS
    for path, expected in ((repo / RECEIPT, RECEIPT_SHA256), (repo / NOTICE, NOTICE_SHA256), (repo / LEGAL, LEGAL_SHA256)):
        if not path.is_file() or base.sha256_file(path) != expected:
            raise base.ConversionError(f"source evidence missing or changed: {path}")
    receipt = base.verify_download_receipt(source_root, repo)
    files = base.read_json(source_root / "shrub_03/polyhaven_files.json")
    supplier_gltf = files["gltf"]["1k"]["gltf"]
    supplier = {
        "shrub_03_1k.gltf": supplier_gltf,
        **supplier_gltf["include"],
        "textures/shrub_03_alpha_1k.png": files["Alpha"]["1k"]["png"],
    }
    records = {(str(item.get("asset")), str(item.get("path"))): item for item in receipt}
    for name, expected in supplier.items():
        item = records.get(("shrub_03", name), {})
        if item.get("url") != expected.get("url") or item.get("api_md5") != expected.get("md5") \
                or item.get("size_bytes") != expected.get("size"):
            raise base.ConversionError(f"download receipt differs from supplier API snapshot: {name}")
    inputs = []
    for relative in sorted(PINNED_INPUTS):
        path = base.source_path(source_root, relative)
        inputs.append({"path": (SOURCE_RELATIVE / relative).as_posix(), "bytes": path.stat().st_size,
                       "sha256": base.sha256_file(path)})
    for relative in (RECEIPT, NOTICE, LEGAL):
        path = repo / relative
        inputs.append({"path": relative.as_posix(), "bytes": path.stat().st_size, "sha256": base.sha256_file(path)})
    return inputs


def json_bytes(data: Any) -> bytes:
    return (json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")


def build_outputs(repo: Path, source_root: Path, output_root: Path) -> dict[Path, bytes]:
    if base.PILLOW_VERSION != "12.3.0":
        raise base.ConversionError(f"Pillow 12.3.0 is pinned; found {base.PILLOW_VERSION}")
    inputs = verify_sources(repo, source_root)
    outputs: dict[Path, bytes] = {}
    variants = []
    for choice in VARIANTS:
        files, record = base.build_variant(source_root, output_root, repo, choice)
        for path, data in files.items():
            if path in outputs and outputs[path] != data:
                raise base.ConversionError(f"different outputs share a path: {path}")
            outputs[path] = data
        # Baker reads this external scene by repo-relative path; no runtime model is installed.
        record.pop("runtime_model_relative_path", None)
        record["scene"] = (DERIVED_RELATIVE / choice["output_gltf"]).as_posix()
        record["description"] = f"Poly Haven Shrub 03 complete clump {choice['source_name']}; external atlas source"
        variants.append(record)
    info = base.read_json(source_root / "shrub_03/polyhaven_info.json")
    source = {
        "id": "polyhaven_shrub_03",
        "title": "Shrub 03",
        "author": ", ".join(info.get("authors", {})),
        "url": "https://polyhaven.com/a/shrub_03",
        "license": "CC0-1.0",
        "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
        "license_statement_url": "https://polyhaven.com/license",
        "license_evidence": NOTICE.as_posix(),
        "license_sha256": NOTICE_SHA256,
        "api_info": (SOURCE_RELATIVE / "shrub_03/polyhaven_info.json").as_posix(),
        "api_files": (SOURCE_RELATIVE / "shrub_03/polyhaven_files.json").as_posix(),
    }
    catalog = {"format": "openrc-external-vegetation-catalog v1", "sources": [source], "assets": variants}
    catalog_path = base.output_path(output_root, CATALOG)
    outputs[catalog_path] = json_bytes(catalog)
    output_records = [{"path": path.relative_to(output_root).as_posix(), "bytes": len(data),
                       "sha256": base.sha256_bytes(data)}
                      for path, data in sorted(outputs.items(), key=lambda item: item[0].as_posix())]
    manifest = {
        "format": "openrc-woodland-shrubs-conversion v1",
        "retrieved": "2026-11-09",
        "tool": {"script": Path(__file__).resolve().relative_to(repo).as_posix(),
                 "script_sha256": base.sha256_file(Path(__file__).resolve()),
                 "shared_converter": Path(base.__file__).resolve().relative_to(repo).as_posix(),
                 "shared_converter_sha256": base.sha256_file(Path(base.__file__).resolve()),
                 "pillow": base.PILLOW_VERSION},
        "sources": [source],
        "inputs": inputs,
        "outputs": output_records,
        "variants": variants,
        "scope": "External atlas-bake sources only; no runtime mesh import or placement.",
    }
    outputs[base.output_path(output_root, MANIFEST)] = json_bytes(manifest)
    return outputs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=ROOT)
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    source_root = (args.source_dir or repo / SOURCE_RELATIVE).resolve()
    output_root = (args.output_dir or repo / DERIVED_RELATIVE).resolve()
    if not output_root.is_relative_to(repo) or output_root == source_root or output_root.is_relative_to(source_root):
        raise base.ConversionError("output must be inside the repository and outside the immutable source")
    outputs = build_outputs(repo, source_root, output_root)
    if args.check:
        base.check_outputs(outputs)
    else:
        for path, data in outputs.items():
            base.write_if_changed(path, data)
    print(f"{'verified' if args.check else 'staged'} 2 external shrub sources: a=2385 triangles, b=2134 triangles")
    print(f"catalog={output_root / CATALOG}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (base.ConversionError, OSError, ValueError, KeyError, TypeError) as exc:
        print(f"woodland shrub conversion failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
