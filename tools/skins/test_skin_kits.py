"""Validate catalog coverage and the shipped image-only skin kits.

Run from the repository root: python tools/skins/test_skin_kits.py
"""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib

import pack_image


ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "app/assets/skin-kit/models.json"
APP = ROOT / "app"


def local_path(resource):
    if not resource.startswith("res://"):
        raise ValueError("Expected a res:// resource path")
    path = (APP / resource[6:]).resolve()
    if not path.is_relative_to(APP.resolve()):
        raise ValueError("Resource path escapes app/")
    return path


def uv_has_interior_marks(data, width, height):
    # The generated UV references are 8-bit grayscale, filter 0, non-interlaced.
    offset, parts = 8, []
    while offset + 12 <= len(data):
        size = int.from_bytes(data[offset:offset + 4], "big")
        kind = data[offset + 4:offset + 8]
        if kind == b"IDAT":
            parts.append(data[offset + 8:offset + 8 + size])
        offset += 12 + size
        if kind == b"IEND":
            break
    pixels = zlib.decompress(b"".join(parts))
    if len(pixels) != (width + 1) * height:
        return False
    for y in range(2, height - 2):
        row = pixels[y * (width + 1):(y + 1) * (width + 1)]
        if row[0] != 0:
            return False
        if any(value != 255 for value in row[3:-2]):
            return True
    return False


class SkinKits(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = json.loads(REGISTRY.read_text(encoding="utf-8"))
        if source.get("format") != "openrc-skin-kits-v1":
            raise ValueError("Unsupported registry format")
        cls.models = source["models"]

    def test_catalog_coverage(self):
        families = {json.loads(path.read_text(encoding="utf-8"))["family_id"]
                    for path in (APP / "data/aircraft_models").glob("*.json")
                    if json.loads(path.read_text(encoding="utf-8")).get("schema") == "openrc-aircraft-model"}
        families.add("hx-700")
        self.assertEqual(set(self.models), families)

    def test_kits_and_roundtrip_image_packages(self):
        for family, model in self.models.items():
            with self.subTest(family=family), tempfile.TemporaryDirectory(prefix="openrc-kit-test-") as scratch:
                archive_path = local_path(model["kit"])
                with zipfile.ZipFile(archive_path) as archive:
                    self.assertIsNone(archive.testzip())
                    kit = json.loads(archive.read("kit.json"))
                    self.assertEqual(kit["format"], "openrc-skin-kit-v1")
                    self.assertEqual(kit["aircraft_id"], family)
                    self.assertEqual(kit["stock_sha256"], model["stock_sha256"])
                    self.assertEqual(kit["template_kind"], model.get("template_kind", "stock_atlas"))
                    self.assertEqual(kit["paints"], model["paints"])
                    self.assertEqual(archive.read("pack_image.py"), (ROOT / "tools/skins/pack_image.py").read_bytes())
                    self.assertEqual(archive.read("Export OpenRC Skin.py"), (ROOT / "tools/skins/export_openrc_skin.py").read_bytes())
                    guide = (APP / "assets/skin-kit/guide.html").read_bytes()
                    stamped = guide.replace(b'data-aircraft-id=""', f'data-aircraft-id="{family}"'.encode("ascii"), 1)
                    self.assertEqual(archive.read("guide.html"), stamped)
                    self.assertIn("Aircraft.blend", archive.namelist())
                    names = []
                    total_pixels = 0
                    for paint in kit["paints"]:
                        size = paint["width"], paint["height"]
                        total_pixels += size[0] * size[1]
                        self.assertEqual(pack_image.inspect_png(archive.read(paint["image"])), size)
                        reference = archive.read(paint["uv"])
                        self.assertEqual(pack_image.inspect_png(reference), size)
                        self.assertTrue(uv_has_interior_marks(reference, *size), paint["uv"])
                        names.extend(paint["materials"])
                    self.assertLessEqual(total_pixels, pack_image.MAX_PIXELS)
                    self.assertEqual(len(names), len(set(names)))
                    self.assertLessEqual(len(names), 9)
                    archive.extractall(scratch)
                out = Path(scratch) / "paint.orskin"
                result = subprocess.run([sys.executable, str(Path(scratch) / "pack_image.py"),
                                         "--output", str(out), "--label", "Kit test"],
                                        text=True, capture_output=True, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                with zipfile.ZipFile(out) as archive:
                    manifest = json.loads(archive.read("manifest.json"))
                    self.assertEqual(manifest["aircraft_id"], family)
                    self.assertEqual(manifest["base_asset_sha256"], model["stock_sha256"])
                    self.assertEqual([record["name"] for record in manifest["materials"]], names)
                    for index, paint in enumerate(kit["paints"], 1):
                        texture = f"texture-{index:02d}.png"
                        self.assertEqual(archive.read(texture), (Path(scratch) / paint["image"]).read_bytes())
                        for name in paint["materials"]:
                            record = next(record for record in manifest["materials"] if record["name"] == name)
                            self.assertEqual(record["texture"], texture)
                            self.assertEqual(record["base_color"], paint["base_colors"][name])


if __name__ == "__main__":
    unittest.main()
