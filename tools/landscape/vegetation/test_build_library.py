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
            library.open_oak_conversion_archive() as oak,
        ):
            catalog, library_files = library.catalog_for(standard, crops, reeds, oak)

            installed_catalog = json.loads(library.RUNTIME_CATALOG.read_text(encoding="utf-8"))
            candidate_ids = {asset["id"] for asset in catalog["assets"]}
            installed_ids = {asset["id"] for asset in installed_catalog["assets"]}
            expected_installed_ids = candidate_ids - {library.OAK_ASSET_ID}
            expected_installed_ids.add("maple_tree")
            if library.OAK_ASSET_ID in installed_ids:
                expected_installed_ids.add(library.OAK_ASSET_ID)
            self.assertEqual(installed_ids, expected_installed_ids)
            self.assertIn(library.OAK_ASSET_ID, candidate_ids)
            self.assertIn("maple_tree", candidate_ids)
            self.assertIn("maple_tree", installed_ids)
            self.assertTrue(set(library.LANDSCAPELAB_ASSETS).issubset(installed_ids))
            self.assertEqual(catalog["counts"]["total_assets"], 30)
            self.assertEqual(catalog["counts"]["trees"], 13)
            self.assertEqual(len(catalog["sources"]), 10)

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

    def test_landscapelab_tree_catalog_preserves_pinned_glbs_and_material_metadata(self) -> None:
        with (
            ZipFile(library.ARCHIVE) as standard,
            ZipFile(library.CROPS_ARCHIVE) as crops,
            ZipFile(library.REED_ARCHIVE) as reeds,
            library.open_oak_conversion_archive() as oak,
        ):
            catalog, library_files = library.catalog_for(standard, crops, reeds, oak)

        self.assertEqual(catalog["counts"]["total_assets"], 30)
        self.assertEqual(catalog["counts"]["trees"], 13)
        self.assertEqual(len(catalog["sources"]), 10)
        self.assertEqual(
            library.sha256_file(library.LANDSCAPELAB_MANIFEST),
            library.LANDSCAPELAB_MANIFEST_SHA256,
        )

        expected = {
            "landscapelab_quercus": {
                "filename": "quercus.glb",
                "sha256": "d4fb683939a0a6e28fb1ff409cbc73c306207f093bfcb40110ff1fe79fabbd1e",
                "triangles": 7016,
                "surfaces": 2,
                "materials": ["leaves", "branches"],
                "height": 59.555878,
                "normalized_scale": 0.016790953956,
            },
            "landscapelab_pine": {
                "filename": "pine_joined.glb",
                "sha256": "74d3d4d0f541522163b1e4d24931e76640df6fdd758db0f963d109faf1a9bcf8",
                "triangles": 4246,
                "surfaces": 2,
                "materials": ["branches.001", "leaves.001"],
                "height": 41.153725,
                "normalized_scale": 0.02429913715,
            },
            "landscapelab_fagus": {
                "filename": "Fagus.glb",
                "sha256": "32542974981ccdbb3cf984e3c8bc1c1d87524fbc08589a69ed2658aba9619cff",
                "triangles": 9312,
                "surfaces": 2,
                "materials": ["branches", "leaves"],
                "height": 1.019293,
                "normalized_scale": 0.981071877838,
            },
            "landscapelab_quercus2": {
                "filename": "quercus2.glb",
                "sha256": "e668ac1f03de63f1222754798802fae06620c3c0cac9993869bcaa87d33e0c6d",
                "triangles": 11144,
                "surfaces": 2,
                "materials": ["branches", "leaves"],
                "height": 71.853935,
                "normalized_scale": 0.013917122237,
            },
        }
        assets = {asset["id"]: asset for asset in catalog["assets"]}
        self.assertEqual(set(expected), set(library.LANDSCAPELAB_ASSETS))
        self.assertTrue(set(expected).issubset(assets))
        for asset_id, facts in expected.items():
            with self.subTest(asset=asset_id):
                asset = assets[asset_id]
                model_dir = library.LANDSCAPELAB_ASSETS[asset_id]["runtime_subdir"]
                runtime_path = "models/landscapelab_tree_2026/" + model_dir + "/" + facts["filename"]
                source_path = library.LANDSCAPELAB_SOURCE_DIR / facts["filename"]
                derived_path = library.LANDSCAPELAB_DERIVED_DIR / facts["filename"]
                source_bytes = source_path.read_bytes()
                self.assertEqual(source_bytes, derived_path.read_bytes())
                self.assertEqual(hashlib.sha256(source_bytes).hexdigest(), facts["sha256"])
                self.assertEqual(library_files[runtime_path], source_bytes)
                self.assertEqual(asset["source_sha256"], facts["sha256"])
                self.assertEqual(asset["role"], "tree")
                self.assertEqual(asset["source_triangles"], facts["triangles"])
                self.assertEqual(asset["source_surfaces"], facts["surfaces"])
                self.assertEqual(asset["source_material_names"], facts["materials"])
                self.assertEqual(asset["source_bounds_m"]["height"], facts["height"])
                self.assertEqual(
                    asset["normalized_bounds_1m"]["normalization_scale"],
                    facts["normalized_scale"],
                )
                self.assertEqual(asset["normalized_bounds_1m"]["min"][1], 0.0)
                self.assertEqual(asset["normalized_bounds_1m"]["max"][1], 1.0)
                self.assertEqual(asset["dependencies"], [])

        quercus = assets["landscapelab_quercus"]["source_material_conventions"]
        self.assertEqual(quercus[0]["alpha_mode"], "MASK")
        self.assertEqual(quercus[0]["alpha_cutoff"], 0.5)
        self.assertTrue(quercus[0]["double_sided"])
        pine = assets["landscapelab_pine"]["source_material_conventions"]
        pine_leaves = next(material for material in pine if material["name"] == "leaves.001")
        self.assertEqual(pine_leaves["alpha_mode"], "MASK")
        self.assertAlmostEqual(pine_leaves["alpha_cutoff"], 0.206521735)
        self.assertTrue(pine_leaves["double_sided"])
        for asset_id in ("landscapelab_fagus", "landscapelab_quercus2"):
            leaves = next(
                material
                for material in assets[asset_id]["source_material_conventions"]
                if material["name"] == "leaves"
            )
            self.assertEqual(leaves["alpha_mode"], "MASK")
            self.assertEqual(leaves["alpha_cutoff"], 0.5)
            self.assertTrue(leaves["double_sided"])

        # Fagus leaf photographs carry their own attribution, pinned per asset.
        fagus_license = assets["landscapelab_fagus"]["asset_license_evidence"]
        self.assertEqual(fagus_license["upstream_path"], "Natural/Plants/Trees/Fagus/LICENSE.md")
        fagus_license_bytes = (library.ROOT / fagus_license["path"]).read_bytes()
        self.assertEqual(len(fagus_license_bytes), fagus_license["bytes"])
        self.assertEqual(hashlib.sha256(fagus_license_bytes).hexdigest(), fagus_license["sha256"])
        self.assertIn(b"Krzysztof Golik", fagus_license_bytes)
        for asset_id in ("landscapelab_quercus", "landscapelab_pine", "landscapelab_quercus2"):
            self.assertNotIn("asset_license_evidence", assets[asset_id])

        source = next(item for item in catalog["sources"] if item["id"] == "landscapelab_tree_2026")
        self.assertEqual(source["revision"], library.LANDSCAPELAB_REVISION)
        self.assertEqual(source["license"], "CC BY-SA 4.0")
        self.assertEqual(source["conversion_proof_sha256"], library.LANDSCAPELAB_MANIFEST_SHA256)
        license_notice = library_files[library.LANDSCAPELAB_NOTICE]
        self.assertEqual(
            license_notice,
            (library.LANDSCAPELAB_SOURCE_DIR / library.LANDSCAPELAB_NOTICE_SOURCE).read_bytes(),
        )
        self.assertEqual(source["runtime_notice"], library.LANDSCAPELAB_SOURCE_DIR.relative_to(library.ROOT).as_posix()
                         + "/" + library.LANDSCAPELAB_NOTICE_SOURCE)
        self.assertIn(b"metallic set to 0.0", license_notice)
        self.assertIn(b"textures, alpha modes, and roughness remain unchanged", license_notice)
        self.assertIn(b"Krzysztof Golik", license_notice)

    def test_polyhaven_understory_catalog_preserves_candidate_receipts_and_alpha_policy(self) -> None:
        with (
            ZipFile(library.ARCHIVE) as standard,
            ZipFile(library.CROPS_ARCHIVE) as crops,
            ZipFile(library.REED_ARCHIVE) as reeds,
            library.open_oak_conversion_archive() as oak,
        ):
            catalog, library_files = library.catalog_for(standard, crops, reeds, oak)

        self.assertEqual(library.sha256_file(library.UNDERSTORY_MANIFEST), library.UNDERSTORY_MANIFEST_SHA256)
        self.assertEqual(catalog["counts"]["total_assets"], 30)
        self.assertEqual(catalog["counts"]["trees"], 13)
        self.assertEqual(len(catalog["sources"]), 10)
        manifest = json.loads(library.UNDERSTORY_MANIFEST.read_text(encoding="utf-8"))
        assets = {asset["id"]: asset for asset in catalog["assets"]}
        variants = {variant["id"]: variant for variant in manifest["variants"]}
        expected = {
            "polyhaven_fern_02_a": {
                "source_id": "polyhaven_fern_02",
                "source_name": "fern_02_a",
                "role": "herb",
                "triangles": 784,
                "source_sha256": "a0159c5a44a58a520d4e366deddfa1630326a8f91e068233d30ed8bd67acfda1",
                "proof_sha256": "6b159c4a1acfcb39158590776a0d1b74d74ea969e342c06784b5c76a6ce6d36c",
                "source_mode": "MASK",
                "output_mode": "MASK",
            },
            "polyhaven_flower_empodium_a": {
                "source_id": "polyhaven_flower_empodium",
                "source_name": "flower_empodium_a_LOD0",
                "role": "flower",
                "triangles": 758,
                "source_sha256": "3b310bc6483f6c0e3131bb47ec406c1fe14324e5fc06dddbacaaeb590831c88e",
                "proof_sha256": "76e3c6d0f68ff15bff0907fac173a24d79f9935b82c40b30b078fc3abbffc511",
                "source_mode": "BLEND",
                "output_mode": "MASK",
            },
        }
        self.assertTrue(set(expected).issubset(assets))
        for asset_id, facts in expected.items():
            with self.subTest(asset=asset_id):
                asset = assets[asset_id]
                variant = variants[asset_id]
                self.assertEqual(asset["source_id"], facts["source_id"])
                self.assertEqual(asset["source_name"], facts["source_name"])
                self.assertEqual(asset["role"], facts["role"])
                self.assertEqual(asset["source_triangles"], facts["triangles"])
                self.assertEqual(asset["source_sha256"], facts["source_sha256"])
                self.assertEqual(asset["source_conversion_proof"], variant["source_conversion_proof"])
                self.assertEqual(asset["source_conversion_proof_sha256"], facts["proof_sha256"])
                self.assertEqual(
                    asset["source_conversion_proof_sha256"],
                    hashlib.sha256((library.ROOT / variant["source_conversion_proof"]).read_bytes()).hexdigest(),
                )
                self.assertEqual(asset["source_dependency_sha256"], variant["source_dependency_sha256"])
                self.assertEqual(asset["source_bounds_m"], variant["source_bounds_m"])
                self.assertEqual(asset["grounded_bounds_m"], variant["grounded_bounds_m"])
                self.assertEqual(asset["dependencies"], variant["dependencies"])

                for dependency in variant["dependencies"]:
                    source_path = library.ROOT / dependency
                    relative = PurePosixPath(dependency).relative_to(
                        library.UNDERSTORY_DERIVED_DIR.relative_to(library.ROOT).as_posix()
                    )
                    runtime_path = "models/realistic_understory_2026/" + relative.as_posix()
                    self.assertEqual(library_files[runtime_path], source_path.read_bytes())

                alpha = asset["material_alpha"]
                self.assertEqual(alpha["source_alpha_mode"], facts["source_mode"])
                self.assertEqual(alpha["output_alpha_mode"], facts["output_mode"])
                self.assertEqual(alpha["output_alpha_cutoff"], 0.5)
                self.assertTrue(alpha["double_sided"])
                self.assertEqual(asset["visual_qualification"], "Not performed; staged source candidate only.")

        flower_alpha = assets["polyhaven_flower_empodium_a"]["material_alpha"]
        self.assertIn("Source BLEND changed to MASK", flower_alpha["mode_change"])
        for source_id in ("polyhaven_fern_02", "polyhaven_flower_empodium"):
            source = next(item for item in catalog["sources"] if item["id"] == source_id)
            source_variant = next(item for item in manifest["variants"] if item["source_id"] == source_id)
            self.assertEqual(source["license"], "CC0-1.0")
            self.assertEqual(
                source["conversion_proof_sha256"],
                source_variant["source_conversion_proof_sha256"],
            )
        self.assertEqual(
            library_files[library.UNDERSTORY_NOTICE],
            (library.UNDERSTORY_SOURCE_DIR / "SOURCE_LICENSE.md").read_bytes(),
        )

    def test_all_quaternius_tree_buffers_clamp_only_reviewed_color_components(self) -> None:
        with ZipFile(library.ARCHIVE) as standard, ZipFile(library.CROPS_ARCHIVE) as crops, ZipFile(
            library.REED_ARCHIVE
        ) as reeds, library.open_oak_conversion_archive() as oak:
            catalog, library_files = library.catalog_for(standard, crops, reeds, oak)
            trees = [
                asset
                for asset in catalog["assets"]
                if asset["role"] == "tree" and asset["source_id"] == "quaternius_standard"
            ]
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

    def test_oak_lod0_catalog_contract_and_source_provenance(self) -> None:
        with (
            ZipFile(library.ARCHIVE) as standard,
            ZipFile(library.CROPS_ARCHIVE) as crops,
            ZipFile(library.REED_ARCHIVE) as reeds,
            library.open_oak_conversion_archive() as oak_archive,
        ):
            catalog, library_files = library.catalog_for(
                standard,
                crops,
                reeds,
                oak_archive,
            )

        self.assertEqual(catalog["counts"]["total_assets"], 30)
        self.assertEqual(catalog["counts"]["trees"], 13)
        self.assertEqual(len(catalog["sources"]), 10)
        oak = next(asset for asset in catalog["assets"] if asset["id"] == library.OAK_ASSET_ID)
        self.assertEqual(oak["source_id"], library.OAK_SOURCE_ID)
        self.assertEqual(oak["source_triangles"], 5_303)
        self.assertEqual(oak["source_surfaces"], 1)
        self.assertEqual(oak["source_materials"], 1)
        self.assertEqual(oak["source_material_names"], ["M_Quercus"])
        self.assertEqual(oak["source_lod"], "LOD0 only; supplier LOD1 and LOD2 are excluded")
        self.assertTrue(oak["lod"]["source_supplied"])
        self.assertEqual(oak["lod"]["imported_supplied_levels"], ["LOD0"])
        self.assertEqual(oak["lod"]["alternate_source_lods_included"], [])
        self.assertTrue(oak["lod"]["godot_import_generate"])
        material_policy = catalog["import"]["shared_material_policy"]
        self.assertIn("oak legacy M_Quercus material", material_policy)
        self.assertIn("packed atlas", material_policy)
        self.assertIn("Principled BSDF base color", material_policy)
        self.assertIn("roughness 1.0", material_policy)
        self.assertIn("BLEND alpha", material_policy)
        self.assertIn("metallic_specular at its native 0.5 default", material_policy)
        self.assertIn("conversion proof", material_policy)
        self.assertEqual(oak["source_bounds_m"]["min"], [-5.828022, -0.858131, -4.772417])
        self.assertEqual(oak["source_bounds_m"]["max"], [5.003101, 10.793035, 4.425439])
        self.assertEqual(oak["source_bounds_m"]["size"], [10.831124, 11.651166, 9.197856])

        converted_gltf_path = library.OAK_CONVERSION_DIR / "oak_lod0.gltf"
        converted_gltf = json.loads(converted_gltf_path.read_text(encoding="utf-8"))
        self.assertEqual(len(converted_gltf["nodes"]), 1)
        self.assertIn("mesh", converted_gltf["nodes"][0])
        self.assertFalse(
            {"matrix", "translation", "rotation", "scale"}
            & set(converted_gltf["nodes"][0])
        )
        self.assertEqual(len(converted_gltf["meshes"]), 1)
        self.assertEqual(len(converted_gltf["meshes"][0]["primitives"]), 1)
        self.assertEqual(len(converted_gltf["materials"]), 1)
        converted_material = converted_gltf["materials"][0]
        self.assertEqual(converted_material["alphaMode"], "BLEND")
        self.assertEqual(converted_material["pbrMetallicRoughness"]["metallicFactor"], 0.0)
        self.assertEqual(converted_material["pbrMetallicRoughness"]["roughnessFactor"], 1.0)
        self.assertNotIn("KHR_materials_specular", converted_material.get("extensions", {}))

        output_files = {
            item["path"]: item
            for item in catalog["files"]
        }
        self.assertEqual(library_files[library.OAK_LICENSE_OUTPUT], library.OAK_LICENSE_SOURCE.read_bytes())
        self.assertEqual(
            hashlib.sha256(library_files[library.OAK_LICENSE_OUTPUT]).hexdigest(),
            library.OAK_LICENSE_SHA256,
        )
        self.assertEqual(library.sha256_file(library.OAK_ARCHIVE), library.OAK_ARCHIVE_SHA256)
        with ZipFile(library.OAK_ARCHIVE) as original_archive:
            original_blend = original_archive.read(library.OAK_BLEND_ENTRY)
        self.assertEqual(hashlib.sha256(original_blend).hexdigest(), library.OAK_BLEND_SHA256)
        self.assertEqual(library.OAK_BLEND.read_bytes(), original_blend)

        license_text = library_files[library.OAK_LICENSE_OUTPUT].decode("utf-8")
        for required_notice in (
            "Oak Tree by lauris71",
            library.OAK_SOURCE_URL,
            library.OAK_DOWNLOAD_URL,
            library.OAK_RETRIEVED,
            "CC BY-SA 3.0",
            library.OAK_LICENSE_URL,
            library.OAK_ARCHIVE_SHA256.upper(),
            library.OAK_BLEND_SHA256.upper(),
            "Changes made for OpenRCsimulator",
            "same license",
        ):
            self.assertIn(required_notice, license_text)

        for conversion_file in library.OAK_CONVERSION_FILES:
            source_path = library.OAK_CONVERSION_DIR / conversion_file["entry"]
            source_bytes = source_path.read_bytes()
            runtime_path = f"models/oak_tree/{conversion_file['entry']}"
            self.assertEqual(library_files[runtime_path], source_bytes)
            self.assertEqual(hashlib.sha256(source_bytes).hexdigest(), conversion_file["sha256"])
            self.assertEqual(output_files[runtime_path]["sha256"], conversion_file["sha256"])
            self.assertEqual(
                oak["source_dependency_sha256"][source_path.relative_to(library.ROOT).as_posix()],
                conversion_file["sha256"],
            )

        oak_source = next(source for source in catalog["sources"] if source["id"] == library.OAK_SOURCE_ID)
        self.assertEqual(oak_source["archive_sha256"], library.OAK_ARCHIVE_SHA256)
        self.assertEqual(oak_source["source_blend_sha256"], library.OAK_BLEND_SHA256)
        self.assertEqual(
            oak_source["conversion_proof_sha256"],
            library.OAK_CONVERSION_PROOF_SHA256,
        )
        self.assertEqual(
            oak_source["license_sha256"],
            library.OAK_LICENSE_SHA256,
        )
        proof = json.loads(library.OAK_CONVERSION_PROOF.read_text(encoding="utf-8"))
        conversion = oak_source["conversion"]
        self.assertEqual(conversion["source_parts_joined"], 36)
        self.assertEqual(conversion["source_triangles"], 5_303)
        self.assertEqual(conversion["baked_triangles"], 5_303)
        self.assertEqual(conversion["max_source_to_baked_loop_error"]["world_position_m"], 0.0)
        self.assertEqual(conversion["max_source_to_baked_loop_error"]["uv_unitless"], 0.0)
        self.assertAlmostEqual(
            conversion["max_source_to_baked_loop_error"]["normal_unit_vector"],
            0.00038462484739224553,
        )
        self.assertTrue(proof["conversion"]["polygons_preserved"])
        self.assertEqual(proof["conversion"]["baked_polygon_count"], 2_791)
        self.assertEqual(proof["material_mapping"]["glTF_roughness_factor"], 1.0)
        self.assertEqual(proof["material_mapping"]["alpha_mode"], "BLEND")
        self.assertIn("Godot 4.7 ignores it", proof["material_mapping"]["specular_note"])

    def test_maple_lod1_catalog_contract_and_conversion_provenance(self) -> None:
        with (
            ZipFile(library.ARCHIVE) as standard,
            ZipFile(library.CROPS_ARCHIVE) as crops,
            ZipFile(library.REED_ARCHIVE) as reeds,
            library.open_oak_conversion_archive() as oak_archive,
        ):
            catalog, library_files = library.catalog_for(standard, crops, reeds, oak_archive)

        maple = next(asset for asset in catalog["assets"] if asset["id"] == "maple_tree")
        self.assertEqual(maple["source_id"], "lolipop_maple_2026")
        self.assertEqual(maple["source_name"], "Acer_large_3_LOD1")
        self.assertEqual(maple["role"], "tree")
        self.assertEqual(maple["source_triangles"], 5_541)
        self.assertEqual(maple["source_surfaces"], 2)
        self.assertEqual(maple["source_materials"], 2)
        self.assertEqual(maple["lod"]["source_lod"], "LOD1")
        self.assertEqual(maple["lod"]["imported_supplied_levels"], ["LOD1"])
        self.assertEqual(maple["lod"]["alternate_source_lods_included"], [])
        self.assertEqual(
            maple["source_sha256"],
            hashlib.sha256(library_files["models/maple_tree/" + library.MAPLE_GLTF]).hexdigest(),
        )

        gltf_bytes = library_files["models/maple_tree/" + library.MAPLE_GLTF]
        gltf = json.loads(gltf_bytes)
        self.assertEqual(len(gltf["materials"]), 2)
        mask_materials = 0
        opaque_materials = 0
        for material in gltf["materials"]:
            with self.subTest(material=material.get("name", "")):
                if material.get("alphaMode", "OPAQUE") == "MASK":
                    mask_materials += 1
                    self.assertTrue(material.get("doubleSided", False))
                    alpha_cutoff = float(material.get("alphaCutoff", 0.5))
                    self.assertTrue(math.isfinite(alpha_cutoff))
                    self.assertGreaterEqual(alpha_cutoff, 0.0)
                    self.assertLessEqual(alpha_cutoff, 1.0)
                else:
                    opaque_materials += 1
                    self.assertEqual(material.get("alphaMode", "OPAQUE"), "OPAQUE")
                pbr = material["pbrMetallicRoughness"]
                self.assertIn("baseColorTexture", pbr)
                self.assertIn("normalTexture", material)
                self.assertIn("metallicRoughnessTexture", pbr)
                self.assertIn("occlusionTexture", material)
                self.assertEqual(
                    material["occlusionTexture"]["index"],
                    pbr["metallicRoughnessTexture"]["index"],
                )
                texture_infos = {
                    "albedo": pbr["baseColorTexture"],
                    "normal": material["normalTexture"],
                    "roughness": pbr["metallicRoughnessTexture"],
                    "occlusion": material["occlusionTexture"],
                }
                for map_name, texture_info in texture_infos.items():
                    texture = gltf["textures"][texture_info["index"]]
                    image = gltf["images"][texture["source"]]
                    runtime_path = "models/maple_tree/" + image["uri"]
                    with self.subTest(material=material.get("name", ""), map=map_name):
                        self.assertIn(runtime_path, library_files)
                        self.assertTrue(library_files[runtime_path])
                roughness = float(pbr.get("roughnessFactor", 1.0))
                metallic = float(pbr.get("metallicFactor", 1.0))
                self.assertTrue(math.isfinite(roughness))
                self.assertGreaterEqual(roughness, 0.0)
                self.assertLessEqual(roughness, 1.0)
                self.assertTrue(math.isfinite(metallic))
                self.assertGreaterEqual(metallic, 0.0)
                self.assertLessEqual(metallic, 1.0)
        self.assertEqual(mask_materials, 1)
        self.assertEqual(opaque_materials, 1)

        manifest = json.loads(library.MAPLE_MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(maple["source_conversion_proof_sha256"], library.sha256_file(library.MAPLE_MANIFEST))
        source = next(item for item in catalog["sources"] if item["id"] == "lolipop_maple_2026")
        self.assertEqual(source["conversion_proof_sha256"], library.sha256_file(library.MAPLE_MANIFEST))
        self.assertEqual(source["license_sha256"], library.sha256_file(library.MAPLE_SOURCE_DIR / "LICENSE_MAPLE.txt"))
        self.assertEqual(source["source"], manifest["source"])
        for input_item in manifest["inputs"]:
            input_path = library.MAPLE_SOURCE_DIR / input_item["path"]
            self.assertEqual(library.sha256_file(input_path), input_item["sha256"])
        for output_item in manifest["outputs"]:
            output_path = library.MAPLE_DERIVED_DIR / output_item["path"]
            self.assertEqual(library.sha256_file(output_path), output_item["sha256"])

        for dependency in maple["dependencies"]:
            source_path = library.ROOT / dependency
            self.assertEqual(
                hashlib.sha256(source_path.read_bytes()).hexdigest(),
                maple["source_dependency_sha256"][dependency],
            )
            source_prefix = library.MAPLE_DERIVED_DIR.relative_to(library.ROOT).as_posix() + "/"
            runtime_relative_path = PurePosixPath(dependency).relative_to(source_prefix)
            runtime_path = "models/maple_tree/" + runtime_relative_path.as_posix()
            self.assertIn(runtime_path, library_files)
            self.assertEqual(library_files[runtime_path], source_path.read_bytes())

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
            maple_manifest = json.loads(library.MAPLE_MANIFEST.read_text(encoding="utf-8"))
            landscapelab_manifest = json.loads(library.LANDSCAPELAB_MANIFEST.read_text(encoding="utf-8"))
            understory_manifest = json.loads(library.UNDERSTORY_MANIFEST.read_text(encoding="utf-8"))
            maple_source_paths = (
                library.MAPLE_MANIFEST,
                library.MAPLE_SOURCE_DIR / "LICENSE_MAPLE.txt",
                *(library.MAPLE_SOURCE_DIR / item["path"] for item in maple_manifest["inputs"]),
                *(library.MAPLE_DERIVED_DIR / item["path"] for item in maple_manifest["outputs"]),
            )
            landscapelab_source_paths = (
                library.LANDSCAPELAB_MANIFEST,
                library.LANDSCAPELAB_SOURCE_DIR / "README.md",
                library.LANDSCAPELAB_SOURCE_DIR / library.LANDSCAPELAB_NOTICE,
                library.LANDSCAPELAB_SOURCE_DIR / library.LANDSCAPELAB_NOTICE_SOURCE,
                library.LANDSCAPELAB_SOURCE_DIR / "LICENSE_Fagus.md",
                *(library.LANDSCAPELAB_SOURCE_DIR / item["filename"] for item in library.LANDSCAPELAB_ASSETS.values()),
                *(library.LANDSCAPELAB_DERIVED_DIR / item["filename"] for item in library.LANDSCAPELAB_ASSETS.values()),
            )
            understory_source_paths = (
                library.UNDERSTORY_MANIFEST,
                *(library.ROOT / item["path"] for item in understory_manifest["inputs"]),
                *(library.UNDERSTORY_DERIVED_DIR / item["path"] for item in understory_manifest["outputs"]),
            )
            source_evidence_before = {
                path: path.read_bytes()
                for path in (
                    library.SOURCE_LICENSE,
                    *library.SOURCE_NOTICES.keys(),
                    library.OAK_LICENSE_SOURCE,
                    *maple_source_paths,
                    *landscapelab_source_paths,
                    *understory_source_paths,
                )
            }
            source_archive_hashes_before = {
                path: hashlib.sha256(path.read_bytes()).hexdigest()
                for path in (
                    library.ARCHIVE,
                    library.CROPS_ARCHIVE,
                    library.REED_ARCHIVE,
                    library.OAK_ARCHIVE,
                    library.OAK_BLEND,
                    library.OAK_LICENSE_SOURCE,
                    library.OAK_CONVERSION_PROOF,
                    *(library.OAK_CONVERSION_DIR / item["entry"] for item in library.OAK_CONVERSION_FILES),
                    *maple_source_paths,
                    *landscapelab_source_paths,
                    *understory_source_paths,
                )
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
            self.assertEqual(catalog["counts"]["total_assets"], 30)
            self.assertEqual(catalog["counts"]["trees"], 13)
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
