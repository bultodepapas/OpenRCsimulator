"""Focused stdlib checks for the image-only X8 package prototype."""

import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
import zlib

import pack_image


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
            path, width, height = pack_image.pack_image(source, output, "Test paint")
            self.assertEqual((path, width, height), (output, 2, 1))
            with zipfile.ZipFile(path) as archive:
                self.assertEqual(set(archive.namelist()), {"manifest.json", "texture-01.png"})
                self.assertEqual(archive.read("texture-01.png"), data)
                manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(manifest["format"], "openrc-skin")
            self.assertEqual(manifest["version"], 1)
            self.assertEqual(manifest["aircraft_id"], "skywalker-x8")
            self.assertEqual(manifest["base_asset_sha256"], pack_image.BASE_ASSET_SHA256)
            self.assertEqual(manifest["label"], "Test paint")
            self.assertEqual(manifest["materials"], [{"name": "x8_livery", "base_color": [1, 1, 1, 1], "texture": "texture-01.png"}])

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
                pack_image.pack_image(source, output, "Test")
            self.assertEqual(output.read_bytes(), b"keep")
            source.write_bytes(png())
            for label in ("", "a" * 49, "line\nbreak"):
                with self.subTest(label=label), self.assertRaises(ValueError):
                    pack_image.pack_image(source, output, label)
            self.assertEqual(output.read_bytes(), b"keep")


if __name__ == "__main__":
    unittest.main()
