import importlib.util
import io
import json
import struct
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("texture_inventory.py")
SPEC = importlib.util.spec_from_file_location("texture_inventory", MODULE_PATH)
texture_inventory = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(texture_inventory)


def png_header(width=2, height=3, color_type=6):
    return (
        texture_inventory.PNG_SIGNATURE
        + struct.pack(">I", 13)
        + b"IHDR"
        + struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
        + b"\x00\x00\x00\x00"
    )


def glb_with_one_embedded_image():
    document = json.dumps(
        {"asset": {"version": "2.0"}, "images": [{"name": "map", "bufferView": 0, "mimeType": "image/png"}]},
        separators=(",", ":"),
    ).encode("utf-8")
    document += b" " * ((4 - len(document) % 4) % 4)
    binary_chunk = b"\x00\x00\x00\x00"
    total_length = 12 + 8 + len(document) + 8 + len(binary_chunk)
    return (
        struct.pack("<4sII", b"glTF", 2, total_length)
        + struct.pack("<II", len(document), texture_inventory.GLB_JSON_CHUNK)
        + document
        + struct.pack("<II", len(binary_chunk), 0x004E4942)
        + binary_chunk
    )


class ImportParserTests(unittest.TestCase):
    def test_parses_known_values_and_keeps_unknown_values(self):
        parsed = texture_inventory.parse_import_text(
            '[remap]\nimporter="texture"\n[params]\nmipmaps/generate=true\ncustom/value=Vector2(2, 4)\n'
        )
        self.assertEqual(parsed["remap"]["importer"], "texture")
        self.assertIs(parsed["params"]["mipmaps/generate"], True)
        self.assertEqual(parsed["params"]["custom/value"], "Vector2(2, 4)")

    def test_incomplete_or_strange_input_is_partial_and_nonfatal(self):
        parsed = texture_inventory.parse_import_text(
            'orphan="ignored"\n[params]\nbroken line\ncompress/mode=\n[broken\nkey="still parsed"\n'
        )
        self.assertEqual(parsed["params"]["compress/mode"], "")
        self.assertEqual(parsed["params"]["key"], "still parsed")


class ShaderInventoryTests(unittest.TestCase):
    def test_shader_samplers_without_hints_and_with_initializer_are_kept(self):
        samplers = texture_inventory._parse_shader_samplers(
            """
            uniform sampler2D plain_sampler;
            uniform sampler2D initialized_sampler = texture(TEXTURE, UV);
            uniform sampler2D normal_sampler : hint_normal, filter_linear, repeat_enable;
            """
        )
        by_name = {sampler["name"]: sampler for sampler in samplers}
        self.assertEqual(set(by_name), {"plain_sampler", "initialized_sampler", "normal_sampler"})
        self.assertEqual(by_name["plain_sampler"]["color_space_hint"], "unspecified")
        self.assertEqual(by_name["plain_sampler"]["filter_hints"], [])
        self.assertEqual(by_name["normal_sampler"]["normal_hint"], True)
        self.assertEqual(by_name["normal_sampler"]["repeat_hints"], ["repeat_enable"])

    def test_multiple_shader_materials_leave_parameter_hints_unattributed(self):
        material_text = '''
[ext_resource type="Shader" path="res://first.gdshader" id="shader_a"]
[ext_resource type="Shader" path="res://second.gdshader" id="shader_b"]
[ext_resource type="Texture2D" path="res://first.png" id="texture_a"]
[ext_resource type="Texture2D" path="res://second.png" id="texture_b"]

[sub_resource type="ShaderMaterial" id="material_a"]
shader = ExtResource("shader_a")
shader_parameter/map = ExtResource("texture_a")

[sub_resource type="ShaderMaterial" id="material_b"]
shader = ExtResource("shader_b")
shader_parameter/map = ExtResource("texture_b")
'''
        shaders = {
            "res://first.gdshader": {
                "samplers": [{"name": "map", "color_space_hint": "source_color"}]
            },
            "res://second.gdshader": {
                "samplers": [{"name": "map", "normal_hint": True}]
            },
        }
        uses = texture_inventory._material_uses("materials/mixed.tres", material_text, shaders)
        bindings = [use for use in uses if use["usage_kind"] == "material_binding"]
        self.assertEqual(len(bindings), 2)
        self.assertTrue(all(use["shader_context"] == "unknown_multiple_shader_assignments" for use in bindings))
        self.assertTrue(all(use["shader_path"] is None for use in bindings))
        self.assertTrue(all(use["sampler_hints"] is None for use in bindings))


class ImageHeaderTests(unittest.TestCase):
    def test_png_header_extracts_dimensions_channels_and_alpha(self):
        result = texture_inventory.parse_png_header(png_header())
        self.assertEqual(result["status"], "parsed")
        self.assertEqual((result["width"], result["height"]), (2, 3))
        self.assertEqual(result["channel_layout"], "RGBA")
        self.assertEqual(result["channel_count"], 4)

    def test_png_incomplete_and_invalid_headers_are_reported_not_raised(self):
        self.assertEqual(texture_inventory.parse_png_header(b"\x89PNG")["reason"], "truncated signature")
        self.assertEqual(texture_inventory.parse_png_header(PNG_HEADER_PREFIX)["reason"], "truncated IHDR")

    def test_jpeg_frame_header_is_read_without_image_payload(self):
        # SOI + SOF0 (precision, height, width, RGB components); payload ends here.
        payload = b"\x08\x00\x07\x00\x09\x03\x01\x11\x00\x02\x11\x00\x03\x11\x00"
        data = b"\xff\xd8\xff\xc0" + struct.pack(">H", len(payload) + 2) + payload
        result = texture_inventory.parse_jpeg_header(io.BytesIO(data))
        self.assertEqual(result["status"], "parsed")
        self.assertEqual((result["width"], result["height"], result["channel_count"]), (9, 7, 3))

    def test_jpeg_truncation_is_nonfatal(self):
        result = texture_inventory.parse_jpeg_header(io.BytesIO(b"\xff\xd8\xff\xc0\x00"))
        self.assertEqual(result["status"], "unreadable")


class InventoryFixtureTests(unittest.TestCase):
    def test_scan_is_deterministic_and_excludes_generated_and_capture_trees(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "app"
            app.mkdir()
            (app / "assets").mkdir()
            (app / "assets" / "z.png").write_bytes(png_header(4, 2, 2))
            (app / "assets" / "z.png.import").write_text(
                '[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n'
                '[deps]\nsource_file="res://assets/z.png"\n'
                '[params]\ncompress/mode=0\nmipmaps/generate=false\n',
                encoding="utf-8",
            )
            (app / "assets" / "a.png").write_bytes(png_header(1, 1, 0))
            (app / "assets" / "a.png.import").write_text(
                '[remap]\nimporter="texture"\n[deps]\nsource_file="res://assets/a.png"\n',
                encoding="utf-8",
            )
            (app / ".godot").mkdir()
            (app / ".godot" / "hidden.png.import").write_text('[remap]\nimporter="texture"\n', encoding="utf-8")
            (app / "captures").mkdir()
            (app / "captures" / "ignored.png.import").write_text('[remap]\nimporter="texture"\n', encoding="utf-8")

            first = texture_inventory.build_inventory(app)
            second = texture_inventory.build_inventory(app)
            self.assertEqual(first, second)
            self.assertEqual([item["source"] for item in first["textures"]], ["assets/a.png", "assets/z.png"])
            self.assertEqual(first["summary"]["import_sidecars"], 2)
            self.assertTrue(first["textures"][0]["source_image"]["channel_layout"] == "grayscale")

    def test_glb_json_counts_embedded_images_and_marks_payload_uninspected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "tiny.glb"
            path.write_bytes(glb_with_one_embedded_image())
            result = texture_inventory._parse_glb(path, "tiny.glb")
            self.assertEqual(result["status"], "parsed")
            self.assertEqual(result["embedded_image_count"], 1)
            self.assertEqual(result["images"][0]["inspection"], "UNINSPECTED")


PNG_HEADER_PREFIX = texture_inventory.PNG_SIGNATURE + struct.pack(">I", 13) + b"IHDR"


if __name__ == "__main__":
    unittest.main()
