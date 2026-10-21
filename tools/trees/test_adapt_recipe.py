#!/usr/bin/env python3
"""Non-GPU tests for pinned source recipes and transform-preserving normalization."""

from __future__ import annotations

import hashlib
import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "tools" / "trees" / "adapt.mjs"


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_fixture(folder: Path) -> Path:
    folder.mkdir(parents=True)
    vertices = [
        (-1.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 2.0, 0.0),
        (-0.5, 1.0, 1.0), (0.5, 1.0, 1.0), (0.0, 2.0, 1.0),
    ]
    binary = b"".join(struct.pack("<3f", *vertex) for vertex in vertices)
    binary += struct.pack("<3H", 0, 1, 2)
    binary += struct.pack("<3H", 3, 4, 5)
    (folder / "tree.bin").write_bytes(binary)
    source = {
        "asset": {"version": "2.0", "generator": "pinned-recipe fixture"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [
            {"name": "transformed_root", "translation": [3.0, 2.0, -1.0],
             "scale": [2.0, 2.0, 1.0], "children": [1]},
            {"name": "mesh_node", "translation": [1.0, 0.0, 0.0], "mesh": 0},
        ],
        "materials": [
            {"name": "Fixture_Bark", "alphaMode": "OPAQUE",
             "pbrMetallicRoughness": {"metallicFactor": 0.0}},
            {"name": "Fixture_Leaves", "alphaMode": "MASK", "alphaCutoff": 0.5,
             "doubleSided": True, "pbrMetallicRoughness": {"metallicFactor": 0.0}},
        ],
        "meshes": [{"name": "fixture_tree", "primitives": [
            {"attributes": {"POSITION": 0}, "indices": 1, "material": 0, "mode": 4},
            {"attributes": {"POSITION": 0}, "indices": 2, "material": 1, "mode": 4},
        ]}],
        "buffers": [{"uri": "tree.bin", "byteLength": len(binary)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 72, "target": 34962},
            {"buffer": 0, "byteOffset": 72, "byteLength": 6, "target": 34963},
            {"buffer": 0, "byteOffset": 78, "byteLength": 6, "target": 34963},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 6, "type": "VEC3",
             "min": [-1.0, 0.0, 0.0], "max": [1.0, 2.0, 1.0]},
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR",
             "min": [0], "max": [2]},
            {"bufferView": 2, "componentType": 5123, "count": 3, "type": "SCALAR",
             "min": [3], "max": [5]},
        ],
    }
    model_path = folder / "tree.gltf"
    model_path.write_text(json.dumps(source), encoding="utf-8")
    recipe = {
        "format": "openrc-tree-source-recipe v1",
        "recipe_id": "nonidentity-fixture-v1",
        "species": [
            {
                "id": "CommonTree_1", "source_asset_id": "fixture:transformed-tree",
                "source_path": str(model_path), "source_sha256": _sha(model_path),
                "dependencies": [{"uri": "tree.bin", "sha256": _sha(folder / "tree.bin")}],
                "pinned_files": [], "bark_material_name": "Fixture_Bark",
                "foliage_material_name": "Fixture_Leaves",
                "provenance": {
                    "creator": "Fixture Author", "license": "CC BY 4.0",
                    "source_url": "https://example.invalid/fixture",
                    "source_revision": "fixture-v1",
                },
            },
            {
                "id": "CommonTree_3", "source_asset_id": "fixture:tree-3",
                "source_path": str(model_path), "source_sha256": _sha(model_path),
                "dependencies": [{"uri": "tree.bin", "sha256": _sha(folder / "tree.bin")}],
                "pinned_files": [], "bark_material_name": "Fixture_Bark",
                "foliage_material_name": "Fixture_Leaves",
                "provenance": {
                    "creator": "Fixture Author", "license": "CC BY 4.0",
                    "source_url": "https://example.invalid/fixture",
                    "source_revision": "fixture-v1",
                },
            },
            {
                "id": "Pine_1", "source_asset_id": "fixture:pine",
                "source_path": str(model_path), "source_sha256": _sha(model_path),
                "dependencies": [{"uri": "tree.bin", "sha256": _sha(folder / "tree.bin")}],
                "pinned_files": [], "bark_material_name": "Fixture_Bark",
                "foliage_material_name": "Fixture_Leaves",
                "provenance": {
                    "creator": "Fixture Author", "license": "CC BY 4.0",
                    "source_url": "https://example.invalid/fixture",
                    "source_revision": "fixture-v1",
                },
            },
        ],
    }
    recipe_path = folder / "recipe.json"
    recipe_path.write_text(json.dumps(recipe, indent=2), encoding="utf-8")
    return recipe_path


def _read_glb_json(path: Path) -> dict:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise AssertionError(f"not a GLB: {path}")
    json_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise AssertionError(f"missing GLB JSON chunk: {path}")
    return json.loads(data[20:20 + json_length].decode("utf-8").rstrip(" \0"))


class PinnedRecipeAdapterTests(unittest.TestCase):
    def _run_adapter(self, recipe: Path, output: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["node", str(ADAPTER), "--source-recipe", str(recipe), "--out", str(output)],
            cwd=ROOT, text=True, capture_output=True, timeout=120, check=False,
        )

    def test_nonidentity_node_hierarchy_is_preserved_under_a_1m_normalization_wrapper(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            recipe = _write_fixture(folder / "source")
            output = folder / "derived"

            result = self._run_adapter(recipe, output)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads((output / "validation.json").read_text(encoding="utf-8"))
            tree = report["species"][0]
            self.assertEqual(tree["triangles"], 2)
            self.assertEqual(tree["source_material_names"], ["Fixture_Bark", "Fixture_Leaves"])
            self.assertEqual(tree["normalization"]["source_height_m"], 4.0)
            self.assertEqual(tree["normalization"]["scale"], 0.25)
            self.assertEqual(tree["derived_validation"]["issues"]["numErrors"], 0)

            source_reference = _read_glb_json(output / "CommonTree_1-reference.glb")
            reference_root = source_reference["nodes"][0]
            self.assertEqual(reference_root["translation"], [3.0, 2.0, -1.0])
            self.assertEqual(reference_root["scale"], [2.0, 2.0, 1.0])

            derived = _read_glb_json(output / "CommonTree_1.glb")
            scene_root_index = derived["scenes"][0]["nodes"][0]
            wrapper = derived["nodes"][scene_root_index]
            self.assertEqual(wrapper["name"], "OpenRC_Normalization")
            self.assertEqual(wrapper["scale"], [0.25, 0.25, 0.25])
            self.assertEqual(wrapper["translation"], [-1.25, -0.5, 0.125])
            transformed_root = derived["nodes"][wrapper["children"][0]]
            self.assertEqual(transformed_root["translation"], [3.0, 2.0, -1.0])
            self.assertEqual(transformed_root["scale"], [2.0, 2.0, 1.0])
            recipe_output = json.loads((output / "bake-recipe.json").read_text(encoding="utf-8"))
            self.assertEqual(recipe_output["species"][0]["source_asset_id"], "fixture:transformed-tree")

    def test_dependency_hash_drift_is_rejected_before_adaptation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            recipe = _write_fixture(folder / "source")
            binary_path = recipe.parent / "tree.bin"
            binary_path.write_bytes(binary_path.read_bytes() + b"x")

            result = self._run_adapter(recipe, folder / "derived")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("dependency tree.bin: source hash drift", result.stderr)


if __name__ == "__main__":
    unittest.main()
