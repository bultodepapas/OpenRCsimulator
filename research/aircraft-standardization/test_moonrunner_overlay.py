"""Versioned MoonRunner overlay: deterministic output and closed registration."""
from __future__ import annotations

import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import build_models as models
import build_customization as custom

ROOT = Path(__file__).resolve().parents[2]


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class ModelOverlayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="moonrunner-overlay-")
        cls.root = Path(cls.temporary.name)
        manifest = read(ROOT / models.OVERLAY_OUTPUT_DIR / "moonrunner-x99.json")
        overlay = read(ROOT / custom.OVERLAY_OUTPUT_DIR / "moonrunner-x99.json")
        resources = {models.REGISTRY_PATH.as_posix(), models.OVERLAY_SOURCE.as_posix(), custom.OVERLAY_SOURCE.as_posix(),
                     custom.SOURCE_PATH.as_posix(), custom.OUTPUT_PATH.as_posix()}
        resources.update(path.relative_to(ROOT).as_posix() for path in (ROOT / models.OUTPUT_DIR).glob("*.json"))
        records = [manifest["geometry"]["source"], *manifest["authoring_sources"], *manifest["dependencies"]]
        records += [{"path": manifest["asset"]["path"]}]
        for livery in manifest.get("liveries", []):
            records.extend([{"path": livery["path"]}, {"path": livery["path"] + ".import"}])
        records += overlay["families"][0]["presentation_sources"]
        records += read(ROOT / "assets/aircraft/moonrunner-x99-overlay/runtime-proof.json")["sources"]
        for record in records:
            path = record["path"]
            resources.add("app/" + path.removeprefix("res://") if path.startswith("res://") else path)
        for resource in resources:
            source = ROOT / resource
            target = cls.root / resource
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        # The Windows checkout uses CRLF for this LF-generated aggregate. A fresh
        # LF checkout must check current without touching the shared source file.
        aggregate = cls.root / custom.OUTPUT_PATH
        aggregate.write_bytes(aggregate.read_bytes().replace(b"\r\n", b"\n"))

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_base_aggregate_is_current_and_unchanged(self):
        aggregate = self.root / custom.OUTPUT_PATH
        original = aggregate.read_bytes()
        self.assertEqual(custom.generate(self.root, True), 0)
        self.assertEqual(models.generate_overlay(self.root, False), 0)
        self.assertEqual(custom.generate_overlay(self.root, False), 0)
        self.assertEqual(aggregate.read_bytes(), original)
        self.assertEqual(custom.generate(self.root, True), 0)
        self.assertEqual(custom.main(["--check", "--root", str(self.root)]), 0)

    def test_repeatability_and_legacy_content(self):
        self.assertEqual(models.generate_overlay(self.root, False), 0)
        self.assertEqual(custom.generate_overlay(self.root, False), 0)
        for relative in (models.OVERLAY_OUTPUT_DIR / "moonrunner-x99.json", custom.OVERLAY_OUTPUT_DIR / "moonrunner-x99.json"):
            self.assertEqual((self.root / relative).read_bytes(), (ROOT / relative).read_bytes())
        self.assertEqual(models.generate_overlay(self.root, True), 0)
        self.assertEqual(custom.generate_overlay(self.root, True), 0)
        old = read(ROOT / "app/data/aircraft_models/skywalker-x8.json")
        new = read(self.root / models.OVERLAY_OUTPUT_DIR / "moonrunner-x99.json")
        for key in ("schema", "version", "builder", "surface_method", "datum", "coordinates", "root_node", "bindings", "construction"):
            self.assertEqual(old[key], new[key], key)
        self.assertEqual(old["asset"]["sha256"], "3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac")
        self.assertEqual(new["asset"]["sha256"], "54d67d9bbfe4ce4abdc4bafa523c3bf812422d6336ba1d0f151a2970e087b0f0")
        self.assertEqual(new["liveries"][1]["sha256"], old["liveries"][1]["sha256"])
        self.assertNotEqual(new["liveries"][1]["path"], old["liveries"][1]["path"])
        self.assertEqual(new["geometry"]["datum_source"], old["geometry"]["datum_source"])
        self.assertIn(old["geometry"]["source"]["path"], [item["path"] for item in new["authoring_sources"]])
        self.assertEqual([source["role"] for source in new["authoring_sources"]],
                         ["geometry", "asset_identity", "overlay_customization_source", "overlay_runtime_proof", "historical_geometry_source"])
        old_registry = read(ROOT / "app/data/aircraft_customization.json")
        old = next(item for item in old_registry["families"] if item["visual_family"] == "skywalker-x8")
        new = read(self.root / custom.OVERLAY_OUTPUT_DIR / "moonrunner-x99.json")["families"][0]
        for key in old:
            if key not in {"visual_family", "model_manifest_sha256", "slots_sha256"}:
                self.assertEqual(old[key], new[key], key)
        model_bytes = (self.root / models.OVERLAY_OUTPUT_DIR / "moonrunner-x99.json").read_bytes()
        self.assertEqual(new["model_manifest_sha256"], hashlib.sha256(model_bytes).hexdigest())

    def test_unexpected_outputs_and_stale_model_fail_closed(self):
        self.assertEqual(models.generate_overlay(self.root, False), 0)
        self.assertEqual(custom.generate_overlay(self.root, False), 0)
        for directory, generate in ((models.OVERLAY_OUTPUT_DIR, models.generate_overlay),
                                    (custom.OVERLAY_OUTPUT_DIR, custom.generate_overlay)):
            unexpected = self.root / directory / "unexpected.txt"
            unexpected.write_text("not registered", encoding="utf-8")
            try:
                self.assertEqual(generate(self.root, True), 1)
                self.assertEqual(generate(self.root, False), 1)
            finally:
                unexpected.unlink()
        model_path = self.root / models.OVERLAY_OUTPUT_DIR / "moonrunner-x99.json"
        original = model_path.read_bytes()
        try:
            model_path.write_bytes(original + b" ")
            self.assertEqual(models.generate_overlay(self.root, True), 1)
            self.assertEqual(custom.generate_overlay(self.root, True), 1)
        finally:
            model_path.write_bytes(original)

    def test_base_registry_family_collision_is_rejected(self):
        self.assertEqual(models.generate_overlay(self.root, False), 0)
        source = self.root / models.REGISTRY_PATH
        original = source.read_bytes()
        try:
            parsed = json.loads(original)
            duplicate = next(item for item in parsed["families"] if item["family_id"] == "skywalker-x8").copy()
            duplicate["family_id"] = "moonrunner-x99"
            parsed["families"].append(duplicate)
            source.write_text(json.dumps(parsed), encoding="utf-8")
            self.assertEqual(models.generate_overlay(self.root, True), 1)
            self.assertEqual(custom.generate_overlay(self.root, True), 1)
        finally:
            source.write_bytes(original)

    def test_wrong_or_duplicate_family_is_rejected(self):
        for relative, generate, key in ((models.OVERLAY_SOURCE, models.generate_overlay, "family_id"),
                                        (custom.OVERLAY_SOURCE, custom.generate_overlay, "visual_family")):
            source = self.root / relative
            original = source.read_bytes()
            try:
                parsed = json.loads(original)
                parsed["families"][0][key] = "other-family"
                source.write_text(json.dumps(parsed), encoding="utf-8")
                self.assertEqual(generate(self.root, True), 1)
                parsed["families"].append(parsed["families"][0])
                source.write_text(json.dumps(parsed), encoding="utf-8")
                self.assertEqual(generate(self.root, True), 1)
            finally:
                source.write_bytes(original)


if __name__ == "__main__":
    unittest.main()
