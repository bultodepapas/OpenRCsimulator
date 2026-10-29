"""Verify the derivative geometry contract and fail-closed accessor comparison."""
from __future__ import annotations
import copy
import json
import unittest
from pathlib import Path
import build_moonrunner_geometry as geometry

ROOT = Path(__file__).resolve().parents[2]

class MoonRunnerGeometryTests(unittest.TestCase):
    def test_outputs_are_current_and_preserve_measurements(self):
        geometry.generate(ROOT, True)
        old = json.loads((ROOT / geometry.SOURCE).read_text(encoding="utf-8"))
        new = json.loads((ROOT / geometry.OUT_JSON).read_text(encoding="utf-8"))
        for key in old:
            if key not in {"catalog_id", "revision", "source_alias", "status", "generator", "inputs", "liveries"}:
                self.assertEqual(new[key], old[key], key)
        for key in old["inputs"]:
            if key != "glb_sha256": self.assertEqual(new["inputs"][key], old["inputs"][key], key)
        self.assertEqual(new["liveries"][1]["glb_sha256"], old["liveries"][1]["glb_sha256"])

    def test_geometry_or_uv_mutation_is_rejected(self):
        old, old_bin = geometry.glb(ROOT / geometry.OLD_GLB, geometry.ORIGINAL)
        new, new_bin = geometry.glb(ROOT / geometry.NEW_GLB, geometry.DERIVATIVE)
        geometry.verify_equivalence(old, old_bin, new, new_bin)
        uv_index = next(v for m in new["meshes"] for p in m["primitives"] for k,v in p["attributes"].items() if k.startswith("TEXCOORD_"))
        accessor = new["accessors"][uv_index]
        view = new["bufferViews"][accessor["bufferView"]]
        tampered = bytearray(new_bin)
        tampered[view.get("byteOffset", 0)] ^= 1
        with self.assertRaisesRegex(ValueError, "accessor"):
            geometry.verify_equivalence(old, old_bin, new, tampered)
        wrong_node = copy.deepcopy(new)
        wrong_node["nodes"][0]["name"] = "tampered"
        with self.assertRaisesRegex(ValueError, "nodes"):
            geometry.verify_equivalence(old, old_bin, wrong_node, new_bin)
        with self.assertRaisesRegex(ValueError, "identity"):
            geometry.glb(ROOT / geometry.NEW_GLB, "0" * 64)

if __name__ == "__main__": unittest.main()
