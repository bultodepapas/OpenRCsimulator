import importlib.util
import hashlib
import io
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock


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


def make_glb(document, binary_payload=b"", *, pad_binary=True):
    json_chunk = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_chunk += b" " * ((4 - len(json_chunk) % 4) % 4)
    binary_chunk = binary_payload
    if pad_binary:
        binary_chunk += b"\x00" * ((4 - len(binary_chunk) % 4) % 4)
    total_length = 12 + 8 + len(json_chunk) + (8 + len(binary_chunk) if binary_chunk else 0)
    glb = (
        struct.pack("<4sII", b"glTF", 2, total_length)
        + struct.pack("<II", len(json_chunk), texture_inventory.GLB_JSON_CHUNK)
        + json_chunk
    )
    if binary_chunk:
        glb += struct.pack("<II", len(binary_chunk), texture_inventory.GLB_BIN_CHUNK) + binary_chunk
    return glb


def glb_with_one_embedded_image(payload=None):
    payload = payload if payload is not None else png_header()
    document = {
        "asset": {"version": "2.0"},
        "buffers": [{"byteLength": len(payload)}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(payload)}],
        "images": [{"name": "map", "bufferView": 0, "mimeType": "image/png"}],
    }
    return make_glb(document, payload)


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

    def test_glb_inspects_embedded_png_header_and_streamed_sha256(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "tiny.glb"
            payload = png_header(13, 7, 2)
            path.write_bytes(glb_with_one_embedded_image(payload))
            result = texture_inventory._parse_glb(path, "tiny.glb")
            self.assertEqual(result["status"], "parsed")
            self.assertEqual(result["embedded_image_count"], 1)
            image = result["images"][0]
            self.assertEqual(image["inspection"], "INSPECTED")
            self.assertEqual(image["header_status"], "parsed")
            self.assertEqual((image["header"]["width"], image["header"]["height"]), (13, 7))
            self.assertEqual(image["header"]["channel_count"], 3)
            self.assertEqual(image["payload_bytes"], len(payload))
            self.assertEqual(image["payload_sha256"], hashlib.sha256(payload).hexdigest())

    def test_glb_jpeg_view_is_bounded_and_extracts_channels(self):
        payload = b"\xff\xd8\xff\xc0\x00\x11\x08\x00\x07\x00\x09\x03\x01\x11\x00\x02\x11\x00\x03\x11\x00"
        document = {
            "buffers": [{"byteLength": len(payload)}],
            "bufferViews": [{"buffer": 0, "byteLength": len(payload)}],
            "images": [{"bufferView": 0, "mimeType": "image/jpeg"}],
        }
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "tiny.glb"
            path.write_bytes(make_glb(document, payload))
            result = texture_inventory._parse_glb(path, "tiny.glb")
        image = result["images"][0]
        self.assertEqual(image["header_status"], "parsed")
        self.assertEqual((image["header"]["width"], image["header"]["height"]), (9, 7))
        self.assertEqual(image["header"]["channel_count"], 3)

    def test_glb_reports_invalid_buffer_types_and_ranges_as_uninspected(self):
        payload = png_header()
        documents = [
            (
                "boolean bufferView index",
                {
                    "buffers": [{"byteLength": len(payload)}],
                    "bufferViews": [{"buffer": 0, "byteLength": len(payload)}],
                    "images": [{"bufferView": True, "mimeType": "image/png"}],
                },
                "bufferView is not a non-negative integer",
                payload,
            ),
            (
                "bufferView index outside array",
                {
                    "buffers": [{"byteLength": len(payload)}],
                    "bufferViews": [{"buffer": 0, "byteLength": len(payload)}],
                    "images": [{"bufferView": 3, "mimeType": "image/png"}],
                },
                "bufferView index is outside the bufferViews array",
                payload,
            ),
            (
                "boolean buffer 0 byteLength",
                {
                    "buffers": [{"byteLength": True}],
                    "bufferViews": [{"buffer": 0, "byteLength": len(payload)}],
                    "images": [{"bufferView": 0, "mimeType": "image/png"}],
                },
                "buffer 0 byteLength is not a non-negative integer",
                payload,
            ),
            (
                "negative offset",
                {
                    "buffers": [{"byteLength": len(payload)}],
                    "bufferViews": [{"buffer": 0, "byteOffset": -1, "byteLength": len(payload)}],
                    "images": [{"bufferView": 0, "mimeType": "image/png"}],
                },
                "byteOffset is not a non-negative integer",
                payload,
            ),
            (
                "view beyond buffer 0",
                {
                    "buffers": [{"byteLength": len(payload) + 1}],
                    "bufferViews": [{"buffer": 0, "byteLength": len(payload) + 2}],
                    "images": [{"bufferView": 0, "mimeType": "image/png"}],
                },
                "bufferView range exceeds buffer 0 byteLength",
                payload + b"\x00\x00",
            ),
            (
                "view selects external buffer",
                {
                    "buffers": [{"byteLength": len(payload)}],
                    "bufferViews": [{"buffer": 1, "byteLength": len(payload)}],
                    "images": [{"bufferView": 0, "mimeType": "image/png"}],
                },
                "uses buffer 1",
                payload,
            ),
            (
                "BIN shorter than buffer 0 declaration",
                {
                    "buffers": [{"byteLength": len(payload) + 8}],
                    "bufferViews": [{"buffer": 0, "byteLength": len(payload)}],
                    "images": [{"bufferView": 0, "mimeType": "image/png"}],
                },
                "BIN chunk length does not match buffer 0",
                payload,
            ),
        ]
        with tempfile.TemporaryDirectory() as temporary:
            for label, document, expected_reason, binary in documents:
                with self.subTest(label=label):
                    path = Path(temporary) / "bad.glb"
                    path.write_bytes(make_glb(document, binary))
                    result = texture_inventory._parse_glb(path, "bad.glb")
                    image = result["images"][0]
                    self.assertEqual(result["status"], "parsed")
                    self.assertEqual(image["inspection"], "UNINSPECTED")
                    self.assertIn(expected_reason, image["reason"])

    def test_glb_rejects_malformed_chunk_length_and_trailing_bytes(self):
        document = {"images": []}
        malformed_chunk = make_glb(document, b"\x00", pad_binary=False)
        trailing = make_glb(document) + b"extra"
        payload = png_header()
        image_glb = bytearray(
            make_glb(
                {
                    "buffers": [{"byteLength": len(payload)}],
                    "bufferViews": [{"buffer": 0, "byteLength": len(payload)}],
                    "images": [{"bufferView": 0, "mimeType": "image/png"}],
                },
                payload,
            )
        )
        json_chunk_length = struct.unpack_from("<I", image_glb, 12)[0]
        bin_chunk_header = 12 + 8 + json_chunk_length
        struct.pack_into("<I", image_glb, bin_chunk_header, 0xFFFFFFFC)
        with tempfile.TemporaryDirectory() as temporary:
            for label, data, expected_reason in (
                ("unaligned BIN chunk", malformed_chunk, "not 4-byte aligned"),
                ("file longer than declared length", trailing, "does not match the file length"),
                ("BIN chunk exceeds file", bytes(image_glb), "GLB chunk exceeds declared GLB length"),
            ):
                with self.subTest(label=label):
                    path = Path(temporary) / "bad.glb"
                    path.write_bytes(data)
                    result = texture_inventory._parse_glb(path, "bad.glb")
                    self.assertEqual(result["status"], "unparsed")
                    self.assertIn(expected_reason, result["reason"])

    def test_unsupported_and_uri_images_are_explicitly_uninspected(self):
        payload = b"not-a-decoded-image"
        document = {
            "buffers": [{"byteLength": len(payload)}],
            "bufferViews": [{"buffer": 0, "byteLength": len(payload)}],
            "images": [
                {"bufferView": 0, "mimeType": "image/ktx2"},
                {"uri": "data:image/png;base64,AA=="},
                {"uri": "https://example.invalid/map.png"},
                {"uri": 17},
            ],
        }
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "sources.glb"
            path.write_bytes(make_glb(document, payload))
            result = texture_inventory._parse_glb(path, "sources.glb")
        self.assertEqual(result["embedded_image_count"], 2)
        self.assertEqual(result["external_image_count"], 1)
        self.assertEqual(result["invalid_image_count"], 1)
        self.assertEqual(result["images"][0]["inspection"], "UNINSPECTED")
        self.assertIn("unsupported embedded image MIME", result["images"][0]["reason"])
        self.assertIn("data URI", result["images"][1]["reason"])
        self.assertIn("no network access", result["external_images"][0]["reason"])
        self.assertEqual(result["external_images"][0]["material_roles"], [])
        self.assertIn("uri is not a non-empty string", result["invalid_images"][0]["reason"])

    def test_core_material_roles_declare_channels_and_preserve_reuse_ambiguity(self):
        document = {
            "textures": [{"source": 0}],
            "materials": [
                {
                    "name": "paint",
                    "normalTexture": {"index": 0},
                    "occlusionTexture": {"index": 0},
                    "emissiveTexture": {"index": 0},
                    "pbrMetallicRoughness": {
                        "baseColorTexture": {"index": 0},
                        "metallicRoughnessTexture": {"index": 0},
                    },
                }
            ],
        }
        roles = texture_inventory._glb_material_roles(document)[0]
        by_role = {role["role"]: role for role in roles}
        self.assertEqual(by_role["base_color"]["channels"], ["R", "G", "B", "A"])
        self.assertEqual(
            by_role["base_color"]["declared_color_semantics"],
            [
                {"channels": ["R", "G", "B"], "meaning": "base color", "color_space": "sRGB"},
                {"channels": ["A"], "meaning": "alpha", "color_space": "linear"},
            ],
        )
        self.assertEqual(by_role["metallic_roughness"]["channels"], ["G", "B"])
        self.assertEqual(
            [item["meaning"] for item in by_role["metallic_roughness"]["declared_color_semantics"]],
            ["roughness", "metallic"],
        )
        self.assertEqual(by_role["normal"]["declared_color_semantics"][0]["color_space"], "linear")
        self.assertEqual(by_role["occlusion"]["declared_color_semantics"][0]["channels"], ["R"])
        self.assertEqual(by_role["emissive"]["declared_color_semantics"][0]["color_space"], "sRGB")
        summary = texture_inventory._summarize_glb_color_semantics(roles)
        self.assertEqual(summary["status"], "ambiguous")
        self.assertEqual({item["channel"] for item in summary["conflicts"]}, {"B", "G", "R"})
        no_channel_conflict = texture_inventory._glb_material_roles(
            {
                "textures": [{"source": 0}],
                "materials": [
                    {
                        "pbrMetallicRoughness": {"metallicRoughnessTexture": {"index": 0}},
                        "occlusionTexture": {"index": 0},
                    }
                ],
            }
        )[0]
        reused_summary = texture_inventory._summarize_glb_color_semantics(no_channel_conflict)
        self.assertEqual(reused_summary["conflicts"], [])
        self.assertTrue(reused_summary["role_reuse"])
        self.assertEqual(reused_summary["status"], "ambiguous")

    def test_glb_inspection_result_is_deterministic(self):
        payload = png_header(20, 10, 6)
        document = {
            "buffers": [{"byteLength": len(payload)}],
            "bufferViews": [{"buffer": 0, "byteLength": len(payload)}],
            "images": [{"name": "body", "bufferView": 0, "mimeType": "image/png"}],
            "textures": [{"source": 0}],
            "materials": [{"emissiveTexture": {"index": 0}, "normalTexture": {"index": 0}}],
        }
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "repeat.glb"
            path.write_bytes(make_glb(document, payload))
            first = texture_inventory._parse_glb(path, "repeat.glb")
            second = texture_inventory._parse_glb(path, "repeat.glb")
        self.assertEqual(first, second)
        self.assertEqual(first["images"][0]["declared_color_semantics"]["status"], "ambiguous")

    def test_glb_image_hash_reads_are_chunked_and_size_limited(self):
        class RecordingStream(io.BytesIO):
            def __init__(self, value):
                super().__init__(value)
                self.requested_sizes = []

            def read(self, size=-1):
                self.requested_sizes.append(size)
                return super().read(size)

        payload = b"x" * (texture_inventory.GLB_IMAGE_HASH_CHUNK_SIZE * 2 + 17)
        stream = RecordingStream(payload)
        digest, status = texture_inventory._hash_stream_range(stream, 0, len(payload), len(payload))
        self.assertEqual(status, "hashed")
        self.assertEqual(digest, hashlib.sha256(payload).hexdigest())
        self.assertLessEqual(max(stream.requested_sizes), texture_inventory.GLB_IMAGE_HASH_CHUNK_SIZE)

        with mock.patch.object(texture_inventory, "GLB_MAX_IMAGE_HASH_BYTES", len(payload) - 1):
            digest, status = texture_inventory._hash_stream_range(stream, 0, len(payload), len(payload))
        self.assertEqual((digest, status), (None, "skipped_size_limit"))

    def test_inventory_summary_distinguishes_header_inspection_from_runtime_gaps(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "app"
            app.mkdir()
            payload = png_header(8, 6, 6)
            (app / "embedded.glb").write_bytes(glb_with_one_embedded_image(payload))
            inventory = texture_inventory.build_inventory(app)

        self.assertEqual(inventory["summary"]["embedded_glb_images_counted_from_json"], 1)
        self.assertEqual(inventory["summary"]["embedded_glb_images_inspected"], 1)
        self.assertEqual(inventory["summary"]["embedded_glb_image_headers_parsed"], 1)
        self.assertTrue(
            any(
                "runtime import/transcode" in gap["gap"]
                for gap in inventory["coverage_gaps"]
            )
        )
        self.assertFalse(
            any(
                "header/hash inspection is incomplete" in gap["gap"]
                for gap in inventory["coverage_gaps"]
            )
        )


PNG_HEADER_PREFIX = texture_inventory.PNG_SIGNATURE + struct.pack(">I", 13) + b"IHDR"


if __name__ == "__main__":
    unittest.main()
