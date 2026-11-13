#!/usr/bin/env python3
"""Check H7's isolated import-cache dependencies without launching Godot."""
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
APP = HERE.parent
spec = importlib.util.spec_from_file_location("h7_imports", HERE / "check_math_sensitivity.py")
h7 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h7)


class H7ImportsTest(unittest.TestCase):
    def setUp(self):
        temporary = APP.parent / "tmp"
        temporary.mkdir(exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(prefix="h7-imports-", dir=temporary)
        self.addCleanup(self.tmp.cleanup)
        self.source = Path(self.tmp.name) / "source"
        self.destination = Path(self.tmp.name) / "destination"
        for folder in ("render", "scenery", "i18n", "assets/models", "assets/fonts", ".godot/imported"):
            (self.source / folder).mkdir(parents=True)
        (self.source / "scenery/scenes.gd").write_text(
            'const A = preload("res://assets/models/test.gltf")\n'
            'const B = preload("res://assets/models/test.glb")\n', encoding="utf-8")
        (self.source / "i18n/fonts.gd").write_text(
            'func font(): return load("res://assets/fonts/cjk.otf")\n', encoding="utf-8")
        (self.source / "assets/models/test.gltf").write_text(json.dumps({"images": [
            {"uri": "texture%20one.png"}, {"bufferView": 0}, {"uri": "data:image/png;base64,AA=="}]}),
            encoding="utf-8")
        doc = json.dumps({"images": [{"uri": "texture-two.png"}, {"bufferView": 1}]}).encode("utf-8")
        doc += b" " * (-len(doc) % 4)
        (self.source / "assets/models/test.glb").write_bytes(
            struct.pack("<4sIII4s", b"glTF", 2, 20 + len(doc), len(doc), b"JSON") + doc)
        for relative in ("assets/models/texture one.png", "assets/models/texture-two.png", "assets/fonts/cjk.otf"):
            (self.source / relative).write_bytes(b"source resource")
        for relative, cache in (("assets/models/test.gltf", "scene.scn"),
                                ("assets/models/test.glb", "binary.scn"),
                                ("assets/models/texture one.png", "one.ctex"),
                                ("assets/models/texture-two.png", "two.ctex"),
                                ("assets/fonts/cjk.otf", "font.fontdata")):
            Path(str(self.source / relative) + ".import").write_text(
                f'[remap]\npath="res://.godot/imported/{cache}"\n', encoding="utf-8")
            (self.source / ".godot/imported" / cache).write_bytes(("cache:" + cache).encode())
        (self.source / ".godot/imported/one.ctex.md5").write_bytes(b"source metadata")
        shutil.copytree(self.source, self.destination, ignore=h7.IGNORED)

    def test_external_gltf_glb_and_font_caches_are_copied(self):
        h7.stage_render_imports(self.source, self.destination)
        for name in ("scene.scn", "binary.scn", "one.ctex", "two.ctex", "font.fontdata", "one.ctex.md5"):
            with self.subTest(name=name):
                self.assertEqual((self.destination / ".godot/imported" / name).read_bytes(),
                                 (self.source / ".godot/imported" / name).read_bytes())

    def test_missing_image_or_import_cache_fails_closed(self):
        image = self.source / "assets/models/texture one.png"
        image.unlink()
        with self.assertRaisesRegex(RuntimeError, "image is missing"):
            h7.stage_render_imports(self.source, self.destination)
        image.write_bytes(b"source resource")
        remap = self.source / "assets/fonts/cjk.otf.import"
        original = remap.read_bytes()
        remap.unlink()
        with self.assertRaisesRegex(RuntimeError, "required imported resource or remap is missing"):
            h7.stage_render_imports(self.source, self.destination)
        remap.write_bytes(original)
        (self.source / ".godot/imported/font.fontdata").unlink()
        with self.assertRaisesRegex(RuntimeError, "imported cache is missing"):
            h7.stage_render_imports(self.source, self.destination)

    def test_scene_cannot_reference_outside_project(self):
        (self.source / "assets/models/test.gltf").write_text(
            json.dumps({"images": [{"uri": "../../../outside.png"}]}), encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "outside the project"):
            h7.stage_render_imports(self.source, self.destination)

    def test_actual_referenced_scenes_and_fonts_have_image_remaps(self):
        resources = set()
        for folder in ("render", "scenery", "i18n"):
            for script in (APP / folder).rglob("*.gd"):
                resources.update(h7.RESOURCE_PRELOAD.findall(script.read_text(encoding="utf-8")))
        fonts = {path for path in resources if path.startswith("assets/fonts/NotoSansCJK") and path.endswith(".otf")}
        self.assertEqual(len(fonts), 2)
        scenes = {path for path in resources if path.lower().endswith((".gltf", ".glb"))}
        images = set().union(*(h7.scene_image_resources(APP, scene) for scene in scenes))
        self.assertIn("assets/landscape/airfield_detail/quaternius_rocks/Rocks_Diffuse.png", images)
        self.assertIn("assets/landscape/night-lighting/Textures/colormap.png", images)
        self.assertIn("assets/landscape/airfield_detail/flower_empodium/textures/flower_empodium_arm_1k.jpg", images)
        for resource in fonts | images:
            with self.subTest(resource=resource):
                self.assertTrue(Path(str(APP / resource) + ".import").is_file())


if __name__ == "__main__":
    unittest.main()
