"""AS-08/09/10 checks for generated visual-family model manifests."""

from __future__ import annotations

import copy
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from build_models import (
    ModelManifestError,
    _normal_bytes,
    _validate_articulation,
    build_manifest,
    validate_dependency_hashes,
    validate_registry,
)


ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = ROOT / "assets" / "aircraft" / "model-bindings.json"
OUTPUT_DIR = ROOT / "app" / "data" / "aircraft_models"
FAMILIES = {
    "jensen-das-ugly-stik-60",
    "gp-extra-300s-60",
    "p51d-mustang-120",
    "sebart-avanti-s-a200-p100rx",
    "turbo-lumber-evolution",
}


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class AircraftModelManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = load_json(REGISTRY_PATH)
        cls.by_family = {item["family_id"]: item for item in cls.registry["families"]}
        cls.manifests = {path.stem: load_json(path) for path in OUTPUT_DIR.glob("*.json")}

    def test_generated_manifests_are_current_and_cover_five_visual_builders(self):
        result = subprocess.run(
            [sys.executable, "research/aircraft-standardization/build_models.py", "--check"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(set(self.by_family), FAMILIES)
        self.assertEqual(set(self.manifests), FAMILIES)
        self.assertEqual(self.registry["version"], 2)
        imported = {"turbo-lumber-evolution", "sebart-avanti-s-a200-p100rx"}
        for family_id, manifest in self.manifests.items():
            self.assertEqual(manifest["version"], 2 if family_id in imported else 1)
        self.assertFalse(validate_registry(self.registry))

    def test_fleet_values_and_existing_visual_adapters_are_preserved(self):
        expected = {
            "jensen-das-ugly-stik-60": (-0.115, -0.005, 0.3048, "euler_hinges"),
            "gp-extra-300s-60": (-0.1088, 0.0, 0.3048, "euler_hinges"),
            "p51d-mustang-120": (0.0, 0.0, 0.6604, "euler_hinges"),
            "sebart-avanti-s-a200-p100rx": (0.0, 0.0, 0.0, "imported_glb"),
            # R2's measured mesh radius is 0.14032 m (geometry.json), independent of physical propeller sizing.
            "turbo-lumber-evolution": (0.0, 0.0, 0.28064, "imported_glb"),
        }
        for family_id, (datum_z, datum_y, diameter, adapter) in expected.items():
            with self.subTest(family=family_id):
                manifest = self.manifests[family_id]
                self.assertEqual(manifest["builder"]["adapter"], adapter)
                self.assertEqual(manifest["datum"]["model_z_le"], datum_z)
                self.assertEqual(manifest["datum"]["model_y_thrust"], datum_y)
                self.assertEqual(manifest["bindings"]["rotor"]["authored_diameter_m"], diameter)
                self.assertEqual(
                    set(manifest["bindings"]["controls"]),
                    {"aileron_left", "aileron_right", "elevator", "rudder"}
                    | ({"flap_left", "flap_right"} if family_id in {"sebart-avanti-s-a200-p100rx", "turbo-lumber-evolution"} else set()),
                )
        avanti = self.manifests["sebart-avanti-s-a200-p100rx"]
        self.assertEqual(
            [(hinge["key"], hinge["node"]) for hinge in avanti["bindings"]["controls"]["elevator"]["hinges"]],
            [("elevator_left", "elevator_left_hinge"), ("elevator_right", "elevator_right_hinge")],
        )

    def test_timber_bindings_reference_generated_articulations_without_copying_them(self):
        timber = self.manifests["turbo-lumber-evolution"]
        construction = timber["construction"]
        geometry = load_json(ROOT / self.by_family["turbo-lumber-evolution"]["geometry"]["source"])
        for role, binding in timber["bindings"]["controls"].items():
            for hinge in binding["hinges"]:
                self.assertEqual(hinge["source"], "geometry_articulation")
                _, articulation_key = hinge["geometry_ref"].split(".", 1)
                referenced = geometry["articulations"][articulation_key]
                self.assertEqual(hinge["node"], referenced["node"])
                self.assertEqual(hinge["geometry_ref"], "articulations." + articulation_key)
                self.assertNotIn("positive", hinge)
                self.assertNotIn("range_deg", hinge)
        self.assertEqual(timber["bindings"]["rotor"]["geometry_ref"], "articulations.propeller_spin")
        self.assertEqual(construction["rotor"], {"frame_node": "thrust_frame", "geometry_ref": "thrust", "axis": "+X"})
        for gear in construction["gear"]:
            _, articulation_key = gear["geometry_ref"].split(".", 1)
            articulation = geometry["articulations"][articulation_key]
            self.assertEqual(articulation["node"], gear["node"])
            self.assertIsNone(articulation.get("app_sign"))
            if gear["role"] != "steering":
                self.assertIsNone(articulation.get("range_deg"))
        self.assertEqual(construction["material_grow"], [{"node": "cowl", "materials": ["black", "red"], "amount_m": 0.0008}])
        self.assertEqual(timber["bindings"]["crash"]["provider"], "gltf_extras")
        self.assertFalse(any(dep["role"] == "crash_metadata" for dep in timber["dependencies"]))

    def test_construction_schema_mutations_reject(self):
        def reject_mutation(mutate, label):
            candidate = copy.deepcopy(self.registry)
            family = next(item for item in candidate["families"] if item["family_id"] == "turbo-lumber-evolution")
            mutate(family)
            with self.subTest(mutation=label):
                self.assertTrue(validate_registry(candidate), label)

        reject_mutation(lambda family: family["construction"].update(version=True), "boolean construction version")
        reject_mutation(lambda family: family["construction"].update(future_mode="guess"), "unknown construction field")
        reject_mutation(lambda family: family["construction"]["gear"][1].update(wrapper=family["construction"]["gear"][0]["wrapper"]), "duplicate gear wrapper")
        reject_mutation(lambda family: family["construction"]["gear"][0].update(geometry_ref="articulations..missing"), "malformed geometry reference")
        reject_mutation(
            lambda family: family["construction"]["gear"][0].update(node=family["bindings"]["controls"]["aileron_left"]["hinges"][0]["node"]),
            "cross-role node collision",
        )
        reject_mutation(
            lambda family: family["construction"]["gear"][2].update(node=family["construction"]["gear"][1]["wrapper"] + "_mount"),
            "gear wrapper mount collision",
        )
        reject_mutation(lambda family: family["construction"]["material_grow"].append(copy.deepcopy(family["construction"]["material_grow"][0])), "duplicate material node/material pair")
        reject_mutation(lambda family: family["construction"]["material_grow"][0].update(amount_m=float("inf")), "non-finite material growth")

    def test_retraction_accepts_a_steered_tail_wheel_and_rejects_mixed_layouts(self):
        # F4U-02: a sampled rig steers a nose wheel (tricycle) or a tail wheel (taildragger), never both or neither.
        def registry_errors(keys):
            candidate = copy.deepcopy(self.registry)
            family = next(item for item in candidate["families"] if item["family_id"] == "sebart-avanti-s-a200-p100rx")
            family["bindings"]["gear"]["keys"] = {key: key for key in keys}
            return validate_registry(candidate)

        self.assertFalse(registry_errors(["left", "right", "tail", "steering"]))
        self.assertTrue(registry_errors(["left", "right", "nose", "tail", "steering"]))
        self.assertTrue(registry_errors(["left", "right", "steering"]))
        family = copy.deepcopy(self.by_family["sebart-avanti-s-a200-p100rx"])
        family["bindings"]["gear"]["keys"] = {"left": "left", "right": "right", "tail": "tail", "steering": "steering"}
        with self.assertRaisesRegex(ModelManifestError, "must match the family's gear bindings"):
            build_manifest(ROOT, REGISTRY_PATH, family)

    def test_construction_references_resolve_and_gear_does_not_require_control_metadata(self):
        family = copy.deepcopy(self.by_family["turbo-lumber-evolution"])
        family["construction"]["gear"][0]["geometry_ref"] = "articulations.missing_gear"
        with self.assertRaisesRegex(ModelManifestError, "missing source field"):
            build_manifest(ROOT, REGISTRY_PATH, family)

        family = copy.deepcopy(self.by_family["turbo-lumber-evolution"])
        manifest = build_manifest(ROOT, REGISTRY_PATH, family)
        self.assertEqual(manifest["version"], 2)

    def test_source_registry_v1_remains_readable(self):
        legacy = copy.deepcopy(self.registry)
        legacy["version"] = 1
        timber = next(item for item in legacy["families"] if item["family_id"] == "turbo-lumber-evolution")
        timber.pop("construction")
        timber["builder"]["script"] = "res://aircraft/timber_model.gd"
        avanti = next(item for item in legacy["families"] if item["family_id"] == "sebart-avanti-s-a200-p100rx")
        avanti.pop("construction")
        avanti["builder"]["script"] = "res://aircraft/avanti_s_model.gd"
        self.assertFalse(validate_registry(legacy))

    def test_multiple_imported_family_ids_can_share_the_generic_builder(self):
        multi_registry = copy.deepcopy(self.registry)
        source_family = next(item for item in multi_registry["families"] if item["family_id"] == "turbo-lumber-evolution")
        copied_family = copy.deepcopy(source_family)
        copied_family["family_id"] = "turbo-lumber-evolution-copy"
        multi_registry["families"].append(copied_family)
        self.assertFalse(validate_registry(multi_registry))

        with tempfile.TemporaryDirectory(prefix="multi-imported-family-", dir=ROOT / "assets" / "aircraft") as raw_temp:
            copied_registry_path = Path(raw_temp) / "model-bindings.json"
            copied_registry_path.write_text(json.dumps(multi_registry, indent=2) + "\n", encoding="utf-8", newline="\n")
            first = build_manifest(ROOT, copied_registry_path, source_family)
            second = build_manifest(ROOT, copied_registry_path, copied_family)
        self.assertEqual(first["version"], 2)
        self.assertEqual(second["version"], 2)
        self.assertEqual(first["builder"]["script"], second["builder"]["script"])
        self.assertNotEqual(first["family_id"], second["family_id"])

    def test_control_articulation_ranges_require_finite_increasing_numbers(self):
        geometry = load_json(ROOT / self.by_family["turbo-lumber-evolution"]["geometry"]["source"])
        articulation = geometry["articulations"]["aileron_left_hinge"]
        articulation["range_deg"] = [True, 22.0]
        with self.assertRaisesRegex(ModelManifestError, "finite number"):
            _validate_articulation(geometry, "articulations.aileron_left_hinge", "aileron_left_hinge", "test control")
        articulation["range_deg"] = [22.0, -22.0]
        with self.assertRaisesRegex(ModelManifestError, "must be increasing"):
            _validate_articulation(geometry, "articulations.aileron_left_hinge", "aileron_left_hinge", "test control")

    def test_gltf_sections_require_an_imported_asset_without_a_triangle_map(self):
        procedural = copy.deepcopy(self.registry)
        procedural["families"][0]["bindings"]["crash"] = {
            "provider": "gltf_extras", "metadata_script": "", "asset_node": ""
        }
        self.assertTrue(validate_registry(procedural))
        ambiguous = copy.deepcopy(self.registry)
        timber = next(f for f in ambiguous["families"] if f["family_id"] == "turbo-lumber-evolution")
        timber["bindings"]["crash"]["metadata_script"] = "res://aircraft/timber_crash_sections.gd"
        self.assertTrue(validate_registry(ambiguous))

    def test_unknown_roles_missing_roles_and_duplicate_hinges_reject(self):
        unknown_role = copy.deepcopy(self.registry)
        unknown_role["families"][0]["bindings"]["controls"]["future_surface"] = copy.deepcopy(
            unknown_role["families"][0]["bindings"]["controls"]["rudder"]
        )
        self.assertTrue(validate_registry(unknown_role))

        missing_role = copy.deepcopy(self.registry)
        del missing_role["families"][0]["bindings"]["controls"]["rudder"]
        self.assertTrue(validate_registry(missing_role))

        duplicate_hinge = copy.deepcopy(self.registry)
        controls = duplicate_hinge["families"][0]["bindings"]["controls"]
        controls["rudder"]["hinges"][0]["key"] = controls["elevator"]["hinges"][0]["key"]
        self.assertTrue(validate_registry(duplicate_hinge))

    def test_geometry_articulation_reference_cannot_dangle(self):
        family = copy.deepcopy(self.by_family["turbo-lumber-evolution"])
        family["bindings"]["controls"]["aileron_left"]["hinges"][0]["geometry_ref"] = "articulations.future_hinge"
        with self.assertRaisesRegex(ModelManifestError, "missing source field"):
            build_manifest(ROOT, REGISTRY_PATH, family)

    def test_dependency_hash_and_path_mutations_reject(self):
        manifest = copy.deepcopy(self.manifests["jensen-das-ugly-stik-60"])
        manifest["dependencies"][0]["sha256"] = "0" * 64
        diagnostics = validate_dependency_hashes(ROOT, manifest)
        self.assertTrue(any("SHA-256 mismatch" in item["message"] for item in diagnostics), diagnostics)

        manifest = copy.deepcopy(self.manifests["jensen-das-ugly-stik-60"])
        manifest["dependencies"][0]["path"] = "res://aircraft/../outside.gd"
        diagnostics = validate_dependency_hashes(ROOT, manifest)
        self.assertTrue(diagnostics, "unsafe dependency paths must not be normalized or ignored")

    def test_lf_text_hashing_is_independent_of_checkout_line_endings(self):
        with self.subTest(mode="lf_text"):
            source = ROOT / "assets" / "aircraft" / "model-bindings.json"
            raw = source.read_bytes()
            lf = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
            crlf = lf.replace(b"\n", b"\r\n")
            self.assertEqual(_normal_bytes(source, "lf_text"), lf)
            self.assertEqual(lf, crlf.replace(b"\r\n", b"\n"))
        with tempfile.TemporaryDirectory(prefix="model-hash-") as directory:
            path = Path(directory) / "source.bin"
            path.write_bytes(b"model\r\nbytes")
            self.assertEqual(_normal_bytes(path, "raw"), b"model\r\nbytes")

    def test_fresh_git_clones_regenerate_in_lf_and_crlf_checkouts(self):
        relative_files = {
            ".gitattributes",
            "assets/aircraft/model-bindings.json",
            "research/aircraft-standardization/build_models.py",
        }
        relative_files.update(
            path.relative_to(ROOT).as_posix() for path in OUTPUT_DIR.glob("*.json")
        )
        for manifest in self.manifests.values():
            relative_files.add(manifest["source_registry"]["path"])
            relative_files.add(manifest["geometry"]["source"]["path"])
            relative_files.update(source["path"] for source in manifest["authoring_sources"])
            for dependency in manifest["dependencies"]:
                resource = dependency["path"]
                self.assertTrue(resource.startswith("res://"), resource)
                relative_files.add("app/" + resource.removeprefix("res://"))

        temp_parent = (ROOT / ".tools").resolve()
        workspace = ROOT.resolve()
        temp_parent.mkdir(parents=True, exist_ok=True)
        self.assertTrue(temp_parent.is_relative_to(workspace), temp_parent)
        with tempfile.TemporaryDirectory(prefix="model-clone-proof-", dir=temp_parent) as raw_temp:
            temp_root = Path(raw_temp).resolve()
            self.assertEqual(temp_root.parent, temp_parent)
            seed = temp_root / "seed"
            seed.mkdir()
            for relative in sorted(relative_files):
                source = ROOT / Path(relative)
                self.assertTrue(source.is_file(), f"missing clone fixture source: {relative}")
                destination = seed / Path(relative)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)

            self._run_checked(["git", "init", "-q"], seed)
            self._run_checked(["git", "config", "user.name", "Model manifest tests"], seed)
            self._run_checked(["git", "config", "user.email", "model-tests@example.invalid"], seed)
            self._run_checked(["git", "add", "--all"], seed)
            self._run_checked(["git", "commit", "-q", "-m", "manifest checkout fixture"], seed)

            for name, autocrlf in (("lf", "false"), ("crlf", "true")):
                with self.subTest(checkout=name):
                    checkout = temp_root / ("clone-" + name)
                    self._run_checked(["git", "clone", "--quiet", "--no-checkout", str(seed), str(checkout)], temp_root)
                    self._run_checked(["git", "config", "core.autocrlf", autocrlf], checkout)
                    self._run_checked(["git", "checkout", "--quiet", "--force", "HEAD"], checkout)

                    source_registry = (checkout / "assets/aircraft/model-bindings.json").read_bytes()
                    if autocrlf == "true":
                        self.assertIn(b"\r\n", source_registry, "CRLF clone should exercise normalized text hashes")
                    else:
                        self.assertNotIn(b"\r", source_registry, "LF clone should retain LF source bytes")
                    for manifest_path in (checkout / "app/data/aircraft_models").glob("*.json"):
                        self.assertNotIn(b"\r", manifest_path.read_bytes(), f"generated manifest must stay LF: {manifest_path}")

                    result = subprocess.run(
                        [sys.executable, "research/aircraft-standardization/build_models.py", "--check"],
                        cwd=checkout,
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def _run_checked(self, command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, f"{command!r} failed in {cwd}:\n{result.stdout}{result.stderr}")
        return result


if __name__ == "__main__":
    unittest.main()
