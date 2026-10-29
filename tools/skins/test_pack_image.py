"""Focused stdlib checks for the image-only paint packer."""

import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
import zlib

import pack_image

KIT = {"aircraft_id": "skywalker-x8", "stock_sha256": "3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac",
       "paints": [{"image": "Paint-01.png", "materials": ["x8_livery"],
                   "base_colors": {"x8_livery": [1, 1, 1, 1]}}]}


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(data, zlib.crc32(kind)) & 0xFFFFFFFF)


def png(width=2, height=1, depth=8, color=6, raw=b"\0\xff\0\0\xff\0\xff\0\xff", before=b"", after=b"", interlaced=0):
    header = struct.pack(">IIBBBBB", width, height, depth, color, 0, 0, interlaced)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + before + chunk(b"IDAT", zlib.compress(raw)) + after + chunk(b"IEND", b"")


class ImageOnlyTests(unittest.TestCase):
    def test_pack_preserves_png_and_pinned_material_identity(self):
        data = png()
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder) / "paint.png", Path(folder) / "skin.orskin"
            source.write_bytes(data)
            path, sizes = pack_image.pack_image(source, output, "Test paint", KIT)
            self.assertEqual((path, sizes), (output, [(2, 1)]))
            with zipfile.ZipFile(path) as archive:
                self.assertEqual(set(archive.namelist()), {"manifest.json", "texture-01.png"})
                self.assertEqual(archive.read("texture-01.png"), data)
                manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(manifest["format"], "openrc-skin")
            self.assertEqual(manifest["version"], 1)
            self.assertEqual(manifest["aircraft_id"], "skywalker-x8")
            self.assertEqual(manifest["base_asset_sha256"], KIT["stock_sha256"])
            self.assertEqual(manifest["label"], "Test paint")
            self.assertEqual(manifest["materials"], [{"name": "x8_livery", "base_color": [1, 1, 1, 1], "texture": "texture-01.png"}])

    def test_multiple_images_and_shared_materials(self):
        kit = {"aircraft_id": "example", "stock_sha256": "a" * 64, "paints": [
            {"image": "Paint-01.png", "materials": ["wing", "door"],
             "base_colors": {"wing": [1, 1, 1, 1], "door": [0.1, 0.1, 0.1, 1]}},
            {"image": "Paint-02.png", "materials": ["fuselage"],
             "base_colors": {"fuselage": [1, 1, 1, 1]}},
        ]}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "Paint-01.png").write_bytes(png())
            (root / "Paint-02.png").write_bytes(png(width=1, color=0, raw=b"\0\x7f"))
            output = root / "paint.orskin"
            _, sizes = pack_image.pack_image(root, output, "Test", kit)
            self.assertEqual(sizes, [(2, 1), (1, 1)])
            with zipfile.ZipFile(output) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                self.assertEqual(set(archive.namelist()), {"manifest.json", "texture-01.png", "texture-02.png"})
            self.assertEqual([m["texture"] for m in manifest["materials"]], ["texture-01.png", "texture-01.png", "texture-02.png"])
            self.assertEqual(manifest["materials"][1]["base_color"], [0.1, 0.1, 0.1, 1])
            with self.assertRaises(ValueError):
                pack_image.pack_image(root / "Paint-01.png", output, "Test", kit)

    def test_standard_png_color_modes(self):
        samples = [
            png(width=1, color=0, raw=b"\0\x7f"),
            png(width=1, color=2, raw=b"\0\xff\x80\0"),
            png(width=1, color=3, depth=1, raw=b"\0\0", before=chunk(b"PLTE", b"\0\0\0\xff\xff\xff")),
            png(width=1, color=4, depth=16, raw=b"\0\x80\0\xff\xff"),
        ]
        for image in samples:
            with self.subTest(image=image[:40]):
                self.assertEqual(pack_image.inspect_png(image), (1, 1))

    def test_adam7_interlaced_png(self):
        # A 2x2 RGBA image uses Adam7 passes 1, 6 and 7: one, one and two pixels.
        raw = b"\0" + bytes(4) + b"\0" + bytes(4) + b"\0" + bytes(8)
        self.assertEqual(pack_image.inspect_png(png(width=2, height=2, raw=raw, interlaced=1)), (2, 2))

    def test_rejects_damaged_and_unsupported_data(self):
        valid = png()
        samples = [
            b"not a png",
            valid[:-2],
            valid + b"extra",
            valid[:40] + bytes([valid[40] ^ 1]) + valid[41:],
            png(width=4097),
            png(raw=b"\5\xff\0\0\xff\0\xff\0\xff"),
            png(raw=b"\0\xff"),
            png(raw=b"\0" + bytes(100)),
            png(before=chunk(b"iCCP", b"compressed metadata")),
            png(before=chunk(b"ABCD", b"unknown critical chunk")),
            png(color=3, depth=1, raw=b"\0\0"),
        ]
        for image in samples:
            with self.subTest(image=image[:40]):
                with self.assertRaises(ValueError):
                    pack_image.inspect_png(image)

    def test_rejection_does_not_replace_existing_output(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder) / "bad.png", Path(folder) / "keep.orskin"
            source.write_bytes(png(raw=b"\0\xff"))
            output.write_bytes(b"keep")
            with self.assertRaises(ValueError):
                pack_image.pack_image(source, output, "Test", KIT)
            self.assertEqual(output.read_bytes(), b"keep")
            source.write_bytes(png())
            for label in ("", "a" * 49, "line\nbreak"):
                with self.subTest(label=label), self.assertRaises(ValueError):
                    pack_image.pack_image(source, output, label, KIT)
            self.assertEqual(output.read_bytes(), b"keep")


if __name__ == "__main__":
    unittest.main()
