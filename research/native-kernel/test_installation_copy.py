#!/usr/bin/env python3
"""Verify the disposable loader fixture includes external glTF resources."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location("native_installation_copy_test", HERE / "test_installation.py")
installation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installation)


class InstallationCopyTest(unittest.TestCase):
    def setUp(self):
        (ROOT / "tmp").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="nk3-copy-test-", dir=ROOT / "tmp")
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.app = self.workspace / "source/app"
        self.project = self.workspace / "project"
        (self.app / "models/textures").mkdir(parents=True)
        self.project.mkdir()
        (self.app / "root.gd").write_text('const Scene = preload("res://models/scene.gltf")\n')
        (self.app / "models/mesh buffer.bin").write_bytes(b"\x00\x01exact binary\xff")
        (self.app / "models/textures/image.png").write_bytes(b"exact image")
        self.scene = self.app / "models/scene.gltf"
        self.document = {"buffers": [{"uri": "mesh%20buffer.bin"}, {"uri": "data:application/octet-stream;base64,AA=="}],
                         "images": [{"uri": "textures/image.png"}, {"bufferView": 0}]}

    def copy(self):
        self.scene.write_text(json.dumps(self.document), encoding="utf-8")
        with mock.patch.object(installation, "ROOT", self.workspace / "source"):
            installation.copy_preload_dependencies(self.project, ("root.gd",))

    def test_external_buffers_and_images_are_copied_exactly(self):
        self.copy()
        for name in ("root.gd", "models/scene.gltf", "models/mesh buffer.bin", "models/textures/image.png"):
            with self.subTest(name=name):
                self.assertEqual((self.project / name).read_bytes(), (self.app / name).read_bytes())

    def test_missing_external_resource_refuses_copy(self):
        (self.app / "models/mesh buffer.bin").unlink()
        with self.assertRaisesRegex(ValueError, "Missing qualification dependency"):
            self.copy()

    def test_uri_cannot_escape_or_request_network(self):
        for uri in ("../../outside.bin", "https://example.test/image.bin", "/absolute.bin", "C:/outside.bin"):
            with self.subTest(uri=uri):
                self.document["buffers"] = [{"uri": uri}]
                with self.assertRaises(ValueError):
                    self.copy()

    def test_real_airfield_sources_name_existing_resources(self):
        app = ROOT / "app"
        scenes = [*(app / "assets/landscape/airfield_detail/quaternius_rocks").glob("Rock_Medium_*.gltf"),
                  app / "assets/landscape/airfield_detail/flower_empodium/flower_empodium_1k.gltf"]
        self.assertEqual(len(scenes), 4)
        installation.copy_preload_dependencies(self.project, ("scenery/airfield_detail.gd",))
        for scene in scenes:
            dependencies = installation.gltf_dependencies(app, scene)
            with self.subTest(scene=scene.name):
                self.assertTrue(any(name.endswith(".bin") for name in dependencies))
                for name in dependencies:
                    self.assertTrue((app / name).is_file(), name)
                    self.assertEqual((self.project / name).read_bytes(), (app / name).read_bytes(), name)


if __name__ == "__main__":
    unittest.main()
