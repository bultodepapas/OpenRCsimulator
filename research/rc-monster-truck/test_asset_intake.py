#!/usr/bin/env python3
"""Standard-library tests for the local MT8 GLB intake gate."""

from __future__ import annotations

import contextlib
import copy
import io
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asset_intake as intake  # noqa: E402


PACKAGE = intake.DEFAULT_PACKAGE
DELIVERY = intake.DEFAULT_DELIVERY_GLB
SPEC_PATH = PACKAGE / "out" / "mt8_spec.json"
RIG_PATH = PACKAGE / "godot" / "mt8_rig.gd"
PACKAGE_GLB = PACKAGE / "out" / "MT8_Bisonte.glb"
HAS_DELIVERY = all(path.is_file() for path in (SPEC_PATH, RIG_PATH, PACKAGE_GLB, DELIVERY))


def encode_glb(document: dict, bin_chunk: bytes = b"\0\0\0\0") -> bytes:
	json_chunk = json.dumps(document, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")
	json_chunk += b" " * ((-len(json_chunk)) % 4)
	bin_chunk += b"\0" * ((-len(bin_chunk)) % 4)
	chunks = struct.pack("<II", len(json_chunk), 0x4E4F534A) + json_chunk
	if bin_chunk:
		chunks += struct.pack("<II", len(bin_chunk), 0x004E4942) + bin_chunk
	return b"glTF" + struct.pack("<II", 2, 12 + len(chunks)) + chunks


@unittest.skipUnless(HAS_DELIVERY, "user-supplied MT8 intake package is not present in this checkout")
class SuppliedModelTests(unittest.TestCase):
	@classmethod
	def setUpClass(cls) -> None:
		cls.glb_bytes = DELIVERY.read_bytes()
		cls.document, cls.bin_chunk = intake._parse_glb(cls.glb_bytes)
		cls.spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
		cls.rig = RIG_PATH.read_text(encoding="utf-8")

	def inspect(self, document=None, spec=None, rig=None):
		return intake.inspect_glb(encode_glb(document or self.document, self.bin_chunk), spec or self.spec, self.rig if rig is None else rig)

	def test_supplied_glb_passes_static_dimensions_and_articulation_intake(self) -> None:
		report = intake.inspect_glb(self.glb_bytes, self.spec, self.rig)
		self.assertTrue(report["self_contained"]["buffers"] >= 1)
		self.assertEqual(report["animation_count"], 0)
		self.assertEqual(report["material_count"], 19)
		self.assertEqual(report["visual_material_count"], 18)
		self.assertEqual(report["proxy_material_count"], 1)
		self.assertEqual(report["proxy_material_names"], ["MT8_COL_Proxy"])
		self.assertEqual(report["geometry"]["visual_triangle_count"], 72800)
		self.assertEqual(report["articulation"]["root_node"], "MT8_Root")
		self.assertLessEqual(report["articulation"]["root_identity_error"], 1.0e-5)
		verified_proxies = {item["name"]: item for item in report["collision_proxies"]["verified"]}
		self.assertEqual(report["collision_proxies"]["count"], 6)
		self.assertEqual(set(verified_proxies), set(self.spec["collision_boxes"]))
		for name, expected in self.spec["collision_boxes"].items():
			self.assertLessEqual(max(abs(a - b) for a, b in zip(verified_proxies[name]["center_m"], expected["center"])), 1.0e-3)
			self.assertLessEqual(max(abs(a - b) for a, b in zip(verified_proxies[name]["size_m"], expected["size"])), 1.0e-3)

	def test_external_buffer_and_external_image_are_rejected(self) -> None:
		bad_buffer = copy.deepcopy(self.document)
		bad_buffer["buffers"][0]["uri"] = "../outside.bin"
		with self.assertRaisesRegex(intake.IntakeError, "external resource URI"):
			self.inspect(bad_buffer)
		bad_image = copy.deepcopy(self.document)
		bad_image["images"] = [{"uri": "textures/body.png"}]
		with self.assertRaisesRegex(intake.IntakeError, "external resource URI"):
			self.inspect(bad_image)

	def test_duplicate_node_names_are_rejected(self) -> None:
		bad = copy.deepcopy(self.document)
		node_by_name = {node.get("name"): node for node in bad["nodes"]}
		self.assertIn("FL_Spin", node_by_name)
		self.assertIn("FR_Spin", node_by_name)
		node_by_name["FR_Spin"]["name"] = "FL_Spin"
		with self.assertRaisesRegex(intake.IntakeError, "duplicate node names"):
			self.inspect(bad)

	def test_negative_scale_and_baked_animation_are_rejected(self) -> None:
		bad_scale = copy.deepcopy(self.document)
		bad_scale["nodes"][0]["scale"] = [-1.0, 1.0, 1.0]
		with self.assertRaisesRegex(intake.IntakeError, "negative-scale"):
			self.inspect(bad_scale)
		bad_animation = copy.deepcopy(self.document)
		bad_animation["animations"] = [{"name": "unapproved", "channels": [], "samplers": []}]
		with self.assertRaisesRegex(intake.IntakeError, "unapproved animations"):
			self.inspect(bad_animation)

	def test_missing_node_pivot_and_spec_rig_identity_are_rejected(self) -> None:
		missing = copy.deepcopy(self.document)
		for node in missing["nodes"]:
			if node.get("name") == "FR_Spin":
				node["name"] = "FR_Spin_Missing"
				break
		with self.assertRaisesRegex(intake.IntakeError, "FR_Spin"):
			self.inspect(missing)
		bad_spec = copy.deepcopy(self.spec)
		bad_spec["corners"]["FR"]["wheel_center_rest"][0] += 0.01
		with self.assertRaisesRegex(intake.IntakeError, "pivot does not match spec"):
			self.inspect(spec=bad_spec)
		bad_dimensions = copy.deepcopy(self.spec)
		bad_dimensions["wheelbase"] += 0.01
		with self.assertRaisesRegex(intake.IntakeError, "wheelbase/track dimensions"):
			self.inspect(spec=bad_dimensions)
		bad_tire = copy.deepcopy(self.spec)
		bad_tire["tire_radius"] += 0.02
		with self.assertRaisesRegex(intake.IntakeError, "tire mesh dimensions"):
			self.inspect(spec=bad_tire)
		bad_proxy_spec = copy.deepcopy(self.spec)
		bad_proxy_spec["collision_boxes"]["COL_Roof"]["center"][1] += 0.002
		with self.assertRaisesRegex(intake.IntakeError, "COL_Roof imported proxy bounds mismatch"):
			self.inspect(spec=bad_proxy_spec)
		bad_proxy_glb = copy.deepcopy(self.document)
		roof = next(node for node in bad_proxy_glb["nodes"] if node.get("name") == "COL_Roof")
		roof["translation"][1] += 0.002
		with self.assertRaisesRegex(intake.IntakeError, "COL_Roof imported proxy bounds mismatch"):
			self.inspect(bad_proxy_glb)
		bad_rig = self.rig.replace("const ARM_L := 0.155", "const ARM_L := 0.156", 1)
		with self.assertRaisesRegex(intake.IntakeError, "rig/spec identity mismatch"):
			self.inspect(rig=bad_rig)

	def test_artifact_inventory_and_check_bytes_are_deterministic(self) -> None:
		first = intake.build_manifest()
		second = intake.build_manifest()
		first_bytes = intake._json_bytes(first)
		self.assertEqual(first_bytes, intake._json_bytes(second))
		artifacts = first["source"]["artifacts"]
		paths = [item["path"] for item in artifacts]
		self.assertEqual(paths, sorted(paths, key=str.casefold))
		self.assertTrue(all(len(item["sha256"]) == 64 and item["bytes"] >= 0 for item in artifacts))
		self.assertTrue(first["source"]["submitted_glb"]["matches_package_export"])
		self.assertEqual(first["acceptance"], "local-preview-only-pending-license-and-runtime-contract")
		self.assertFalse(first["inspection_performed"]["godot"])

		with tempfile.TemporaryDirectory() as directory:
			output = Path(directory) / "intake.json"
			output.write_bytes(first_bytes)
			stdout = io.StringIO()
			with contextlib.redirect_stdout(stdout):
				self.assertEqual(intake.main(["--check", "--output", str(output)]), 0)
			self.assertIn("matches", stdout.getvalue())
			original = output.read_bytes()
			output.write_bytes(original + b" ")
			changed = output.read_bytes()
			stderr = io.StringIO()
			with contextlib.redirect_stderr(stderr):
				self.assertEqual(intake.main(["--check", "--output", str(output)]), 1)
			self.assertIn("stale", stderr.getvalue())
			self.assertEqual(output.read_bytes(), changed, "--check must not rewrite stale files")


class ContainerTests(unittest.TestCase):
	def test_corrupt_and_wrong_version_containers_are_rejected(self) -> None:
		with self.assertRaisesRegex(intake.IntakeError, "header"):
			intake._parse_glb(b"not a glb")
		valid = encode_glb({"asset": {"version": "2.0"}})
		wrong_version = bytearray(valid)
		struct.pack_into("<I", wrong_version, 4, 1)
		with self.assertRaisesRegex(intake.IntakeError, "unsupported GLB version"):
			intake._parse_glb(bytes(wrong_version))
		with self.assertRaisesRegex(intake.IntakeError, "declared length"):
			intake._parse_glb(valid[:-4])

	def test_duplicate_json_keys_and_external_uris_are_rejected(self) -> None:
		body = b'{"asset":{"version":"2.0"},"asset":{"version":"2.0"}}'
		body += b" " * ((-len(body)) % 4)
		chunk = struct.pack("<II", len(body), 0x4E4F534A) + body
		duplicate_json = b"glTF" + struct.pack("<II", 2, len(chunk) + 12) + chunk
		with self.assertRaisesRegex(intake.IntakeError, "duplicate JSON object key"):
			intake._parse_glb(duplicate_json)
		with self.assertRaisesRegex(intake.IntakeError, "external resource URI"):
			intake._check_self_contained({"buffers": [{"uri": "mesh.bin", "byteLength": 4}], "images": [], "bufferViews": []}, b"\0\0\0\0")

	def test_duplicate_child_and_negative_transform_are_rejected(self) -> None:
		duplicate_child = {"nodes": [{"name": "root", "children": [1, 1]}, {"name": "child"}], "scenes": [{"nodes": [0]}], "scene": 0}
		with self.assertRaisesRegex(intake.IntakeError, "duplicate child indices"):
			intake._node_graph(duplicate_child)
		negative = {"nodes": [{"name": "root", "scale": [-1, 1, 1]}], "scenes": [{"nodes": [0]}], "scene": 0}
		nodes, _, _, world = intake._node_graph(negative)
		with self.assertRaisesRegex(intake.IntakeError, "negative-scale"):
			intake._check_node_transforms(nodes, world)


if __name__ == "__main__":
	unittest.main(verbosity=2)
