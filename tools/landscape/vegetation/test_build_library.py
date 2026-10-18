#!/usr/bin/env python3
"""CPU-only contract tests for retained vegetation source intake."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import struct
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZipFile


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_library as library  # noqa: E402


RETAINED_TREE_FACTS = {
    "common_tree_2": {
        "sha256": "67160975f0ac991b4a2ffb2add4ab4037b5e9c1bef9f66dac5235fcf0ba9bd52",
        "triangles": 5648,
        "surfaces": 2,
        "size": [4.464302, 7.642996, 4.275852],
    },
    "common_tree_4": {
        "sha256": "ddf0e8837705702871d3f03de8cf7aeed61ad4bf8ee92052b6f95bdd771297b6",
        "triangles": 4066,
        "surfaces": 2,
        "size": [3.825526, 9.438381, 3.755373],
    },
    "pine_2": {
        "sha256": "57bd4732170b6c7e51bcf78fe5adaabf142f95a50378d8d3051d1f20a04d3c2f",
        "triangles": 3648,
        "surfaces": 2,
        "size": [5.728085, 7.376238, 5.221207],
    },
    "pine_3": {
        "sha256": "54c72a4d614f053dd4b3d4404076a361de6085ec6a34560e42a76d7e79d89830",
        "triangles": 4964,
        "surfaces": 2,
        "size": [3.611395, 7.392199, 3.995804],
    },
}


def file_snapshot(root: Path) -> dict[str, str]:
    if not root.exists():
        return {}
    return {
        path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def accessor_elements(gltf: dict, binary: bytes, accessor_index: int) -> list[bytes]:
    accessor = gltf["accessors"][accessor_index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    component_bytes = {
        5120: 1,
        5121: 1,
        5122: 2,
        5123: 2,
        5125: 4,
        5126: 4,
    }[accessor["componentType"]]
    component_count = {
        "SCALAR": 1,
        "VEC2": 2,
        "VEC3": 3,
        "VEC4": 4,
        "MAT2": 4,
        "MAT3": 9,
        "MAT4": 16,
    }[accessor["type"]]
    element_bytes = component_bytes * component_count
    stride = view.get("byteStride", element_bytes)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return [
        binary[start + index * stride : start + index * stride + element_bytes]
        for index in range(accessor["count"])
    ]


def color_accessor_offsets(gltf: dict, accessor_index: int) -> list[int]:
    accessor = gltf["accessors"][accessor_index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    component_count = {"VEC3": 3, "VEC4": 4}[accessor["type"]]
    stride = view.get("byteStride", component_count * 4)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return [
        start + vertex * stride + component * 4
        for vertex in range(accessor["count"])
        for component in range(component_count)
    ]


class BuildLibraryTests(unittest.TestCase):
    def test_archive_and_output_paths_reject_traversal(self) -> None:
        for unsafe in ("../outside", "/absolute/file", "folder\\file", "nul\x00byte"):
            with self.subTest(path=unsafe), self.assertRaises(library.BuildError):
                library.archive_path(unsafe)

        root = ROOT / "tmp/tree-retained-intake/path-check"
        for unsafe in ("../outside", "models/../../outside", "C:/outside"):
            with self.subTest(path=unsafe), self.assertRaises(library.BuildError):
                library.output_path(root, unsafe)

    def test_default_selection_and_reviewed_tree_sources_are_exact(self) -> None:
        with (
            ZipFile(library.ARCHIVE) as standard,
            ZipFile(library.CROPS_ARCHIVE) as crops,
            ZipFile(library.REED_ARCHIVE) as reeds,
        ):
            catalog, library_files = library.catalog_for(standard, crops, reeds)

            installed_catalog = json.loads(library.RUNTIME_CATALOG.read_text(encoding="utf-8"))
            self.assertEqual(
                [asset["id"] for asset in catalog["assets"]],
                [asset["id"] for asset in installed_catalog["assets"]],
            )
            self.assertEqual(catalog["counts"]["total_assets"], 19)
            self.assertEqual(catalog["counts"]["trees"], 7)

            candidates = {
                asset["id"]: asset
                for asset in catalog["assets"]
                if asset["id"] in RETAINED_TREE_FACTS
            }
            self.assertEqual(set(candidates), set(RETAINED_TREE_FACTS))
            for asset_id, facts in RETAINED_TREE_FACTS.items():
                with self.subTest(asset=asset_id):
                    asset = candidates[asset_id]
                    self.assertEqual(asset["source_sha256"], facts["sha256"])
                    self.assertEqual(asset["source_triangles"], facts["triangles"])
                    self.assertEqual(asset["source_surfaces"], facts["surfaces"])
                    self.assertEqual(asset["source_bounds_m"]["size"], facts["size"])

                    for dependency in asset["dependencies"]:
                        output_name = (
                            "models/"
                            + PurePosixPath(dependency).relative_to("glTF").as_posix()
                        )
                        source_bytes = standard.read(dependency)
                        if output_name == asset.get("buffer_derivation", {}).get("path"):
                            self.assertNotEqual(library_files[output_name], source_bytes)
                        else:
                            self.assertEqual(library_files[output_name], source_bytes)

    def test_all_tree_buffers_clamp_only_reviewed_color_components(self) -> None:
        with ZipFile(library.ARCHIVE) as standard, ZipFile(library.CROPS_ARCHIVE) as crops, ZipFile(
            library.REED_ARCHIVE
        ) as reeds:
            catalog, library_files = library.catalog_for(standard, crops, reeds)
            trees = [asset for asset in catalog["assets"] if asset["role"] == "tree"]
            self.assertEqual(len(trees), 7)

            for asset in trees:
                with self.subTest(tree=asset["id"]):
                    gltf_bytes = standard.read(asset["source_entry"])
                    gltf = json.loads(gltf_bytes)
                    derivation = asset["buffer_derivation"]
                    source_binary = standard.read(derivation["source_entry"])
                    runtime_binary = library_files[derivation["path"]]
                    for dependency in asset["dependencies"]:
                        runtime_path = (
                            "models/"
                            + PurePosixPath(dependency).relative_to("glTF").as_posix()
                        )
                        if runtime_path == derivation["path"]:
                            continue
                        self.assertEqual(library_files[runtime_path], standard.read(dependency))
                    self.assertEqual(
                        hashlib.sha256(source_binary).hexdigest(),
                        derivation["source_buffer_sha256"],
                    )
                    self.assertEqual(
                        hashlib.sha256(runtime_binary).hexdigest(),
                        derivation["runtime_buffer_sha256"],
                    )

                    colors: set[int] = set()
                    others: set[int] = set()
                    for mesh in gltf["meshes"]:
                        for primitive in mesh["primitives"]:
                            for semantic, index in primitive["attributes"].items():
                                (colors if semantic == "COLOR_0" else others).add(index)
                            if "indices" in primitive:
                                others.add(primitive["indices"])
                    self.assertTrue(colors)
                    self.assertFalse(colors & others)

                    expected_offsets: set[int] = set()
                    source_values_above_one = 0
                    for index in colors:
                        accessor = gltf["accessors"][index]
                        self.assertEqual(accessor["componentType"], 5126)
                        self.assertIn(accessor["type"], ("VEC3", "VEC4"))
                        for offset in color_accessor_offsets(gltf, index):
                            value = struct.unpack_from("<f", source_binary, offset)[0]
                            self.assertTrue(math.isfinite(value))
                            self.assertGreaterEqual(value, 0.0)
                            self.assertLessEqual(value, library.TREE_COLOR_OVERSHOOT_LIMIT)
                            if value > 1.0:
                                source_values_above_one += 1
                                expected_offsets.add(offset)
                                self.assertEqual(
                                    struct.unpack_from("<f", runtime_binary, offset)[0], 1.0
                                )
                            else:
                                self.assertEqual(
                                    struct.unpack_from("<f", runtime_binary, offset)[0], value
                                )
                    self.assertEqual(derivation["derivation_count"], source_values_above_one)
                    self.assertGreater(source_values_above_one, 0)

                    changed_byte_offsets = {
                        offset
                        for offset, (source_byte, runtime_byte) in enumerate(
                            zip(source_binary, runtime_binary, strict=True)
                        )
                        if source_byte != runtime_byte
                    }
                    expected_changed_byte_offsets = {
                        byte_offset
                        for component_offset in expected_offsets
                        for byte_offset in range(component_offset, component_offset + 4)
                        if source_binary[byte_offset] != runtime_binary[byte_offset]
                    }
                    self.assertEqual(changed_byte_offsets, expected_changed_byte_offsets)

                    for accessor_index in others:
                        self.assertEqual(
                            accessor_elements(gltf, source_binary, accessor_index),
                            accessor_elements(gltf, runtime_binary, accessor_index),
                            f"non-color accessor {accessor_index} changed",
                        )

                    file_record = next(
                        item for item in catalog["files"] if item["path"] == derivation["path"]
                    )
                    self.assertEqual(file_record["sha256"], derivation["runtime_buffer_sha256"])

    def test_tree_color_derivation_refuses_overshoot_beyond_reviewed_limit(self) -> None:
        with ZipFile(library.ARCHIVE) as standard:
            source_name = "glTF/Pine_1.gltf"
            gltf_bytes = standard.read(source_name)
            gltf = json.loads(gltf_bytes)
            buffer_uri = gltf["buffers"][0]["uri"]
            binary_name = (PurePosixPath(source_name).parent / buffer_uri).as_posix()
            binary = bytearray(standard.read(binary_name))
            color_index = next(
                primitive["attributes"]["COLOR_0"]
                for mesh in gltf["meshes"]
                for primitive in mesh["primitives"]
                if "COLOR_0" in primitive["attributes"]
            )
            offset = color_accessor_offsets(gltf, color_index)[0]
            struct.pack_into("<f", binary, offset, library.TREE_COLOR_OVERSHOOT_LIMIT + 0.01)
            with self.assertRaisesRegex(library.BuildError, "outside reviewed range"):
                library.derive_tree_color_buffer(source_name, gltf_bytes, bytes(binary), 0)

    def test_default_generation_check_and_repeat_are_deterministic(self) -> None:
        trial_root = ROOT / "tmp/tree-retained-intake"
        trial_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="build-library-test-", dir=trial_root) as temp:
            work_root = Path(temp)
            candidate_root = work_root / "candidate-library"
            relative_output = candidate_root.relative_to(ROOT).as_posix()
            script = ROOT / "tools/landscape/vegetation/build_library.py"
            command = [
                sys.executable,
                str(script),
                "--output-root",
                relative_output,
            ]

            production_before = file_snapshot(library.RUNTIME)
            source_evidence_before = {
                path: path.read_bytes()
                for path in (library.SOURCE_LICENSE, *library.SOURCE_NOTICES.keys())
            }
            source_archive_hashes_before = {
                path: hashlib.sha256(path.read_bytes()).hexdigest()
                for path in (library.ARCHIVE, library.CROPS_ARCHIVE, library.REED_ARCHIVE)
            }

            generated = subprocess.run(
                command,
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(generated.returncode, 0, generated.stderr)
            catalog = json.loads((candidate_root / "catalog.json").read_text(encoding="utf-8"))
            self.assertEqual(catalog["counts"]["total_assets"], 19)
            self.assertEqual(catalog["counts"]["trees"], 7)
            first_snapshot = file_snapshot(candidate_root)

            checked = subprocess.run(
                [*command[:2], "--check", *command[2:]],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(checked.returncode, 0, checked.stderr)
            self.assertEqual(file_snapshot(candidate_root), first_snapshot)

            repeated = subprocess.run(
                command,
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(repeated.returncode, 0, repeated.stderr)
            self.assertEqual(file_snapshot(candidate_root), first_snapshot)

            self.assertEqual(file_snapshot(library.RUNTIME), production_before)
            self.assertEqual(
                {path: path.read_bytes() for path in source_evidence_before},
                source_evidence_before,
            )
            self.assertEqual(
                {
                    path: hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in source_archive_hashes_before
                },
                source_archive_hashes_before,
            )


if __name__ == "__main__":
    unittest.main()
