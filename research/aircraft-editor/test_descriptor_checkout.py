"""AE-01: exact-byte descriptor bindings survive fresh LF/CRLF Git checkouts."""
from pathlib import Path
from copy import deepcopy
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "research" / "aircraft-editor"))
import build_descriptors


class CheckoutBindings(unittest.TestCase):
    def test_fresh_checkouts_keep_exact_bindings(self):
        tools = (ROOT / ".tools").resolve()
        tools.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="workshop-checkout-", dir=tools) as directory:
            work = Path(directory).resolve()
            self.assertTrue(work.is_relative_to(tools))
            source = work / "source"
            source.mkdir()
            paths = [Path(".gitattributes"), Path("app/app_state/aircraft_catalog.gd"),
                     Path("app/data/ground/wheel_profiles.json"),
                     Path("app/data/schema/aircraft-modules-v1.json"),
                     Path("research/aircraft-standardization/modules.py"),
                     Path("research/aircraft-standardization/physical_identity.py"),
                     Path("research/aircraft-editor/build_descriptors.py")]
            paths.extend(path.relative_to(ROOT) for path in (ROOT / "app/data/aircraft").glob("*.json"))
            paths.extend(path.relative_to(ROOT) for path in (ROOT / "app/data/workshop").glob("*.json"))
            paths.extend(path.relative_to(ROOT) for path in (ROOT / "app/data/aircraft_models").glob("*.json"))
            for relative in paths:
                target = source / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)

            def git(cwd, *args):
                return subprocess.run(["git", "-c", "user.name=Workshop checkout test", "-c",
                                       "user.email=workshop-test@localhost", *args], cwd=cwd,
                                      check=True, capture_output=True, text=True)

            git(source, "init", "--quiet")
            git(source, "add", ".")
            git(source, "commit", "--quiet", "-m", "Disposable byte-binding fixture")
            for mode in ("false", "true"):
                clone = work / ("clone-" + mode)
                git(work, "-c", "core.autocrlf=" + mode, "clone", "--quiet", str(source), str(clone))
                result = subprocess.run([sys.executable, "research/aircraft-editor/build_descriptors.py", "--check"],
                                        cwd=clone, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                # This companion is part of every variant's dependency manifest.
                wheel = Path("app/data/ground/wheel_profiles.json")
                self.assertEqual((clone / wheel).read_bytes(), (ROOT / wheel).read_bytes())


class InventoryBindings(unittest.TestCase):
    def test_identity_version_emits_id_only_bindings(self):
        source = identified_source()
        descriptor_format, bindings = build_descriptors.inventory_binding_contract("fixture", source)
        self.assertEqual(descriptor_format, "openrc-aircraft-workshop v3")
        self.assertEqual(bindings, [{"key": "battery"}, {"key": "fuselage"}])
        self.assertTrue(all(set(binding) == {"key"} for binding in bindings))

        source["physical_identity_version"] = 1.0
        float_format, float_bindings = build_descriptors.inventory_binding_contract("fixture", source)
        self.assertEqual(float_format, "openrc-aircraft-workshop v3")
        self.assertEqual(float_bindings, bindings)

    def test_reordered_and_renamed_inventory_keeps_the_same_binding_keys(self):
        original = identified_source()
        changed = deepcopy(original)
        changed["inventory"].reverse()
        changed["inventory"][0]["name"] = "Renamed fuselage assembly"
        original_format, original_bindings = build_descriptors.inventory_binding_contract("fixture", original)
        changed_format, changed_bindings = build_descriptors.inventory_binding_contract("fixture", changed)
        self.assertEqual((original_format, changed_format), (
            "openrc-aircraft-workshop v3", "openrc-aircraft-workshop v3"))
        self.assertEqual({item["key"] for item in original_bindings}, {"battery", "fuselage"})
        self.assertEqual({item["key"] for item in changed_bindings}, {"battery", "fuselage"})
        self.assertEqual({item["key"] for item in original_bindings},
                         {item["key"] for item in changed_bindings})

    def test_idless_historical_sources_keep_exact_v2_bindings(self):
        source = {"inventory": [{"name": "Wing"}, {"name": "Battery"}]}
        descriptor_format, bindings = build_descriptors.inventory_binding_contract("legacy-fixture", source)
        self.assertEqual(descriptor_format, "openrc-aircraft-workshop v2")
        self.assertEqual([set(item) for item in bindings], [
            {"key", "index", "name_sha256"}, {"key", "index", "name_sha256"}])
        self.assertEqual([item["index"] for item in bindings], [0, 1])

    def test_partial_duplicate_and_invalid_identity_sets_are_rejected(self):
        source = identified_source()
        del source["inventory"][0]["id"]
        with self.assertRaisesRegex(ValueError, "physical identities"):
            build_descriptors.inventory_binding_contract("fixture", source)

        source = identified_source()
        source["landing_gear"]["contacts"][0]["id"] = "battery"
        with self.assertRaisesRegex(ValueError, "physical identities"):
            build_descriptors.inventory_binding_contract("fixture", source)

        source = identified_source()
        source["inventory"][1]["id"] = "bad-ID"
        with self.assertRaisesRegex(ValueError, "physical identities"):
            build_descriptors.inventory_binding_contract("fixture", source)

        source = identified_source()
        source["inventory"][1]["id"] = "a" * 81
        with self.assertRaisesRegex(ValueError, "physical identities"):
            build_descriptors.inventory_binding_contract("fixture", source)

    def test_unversioned_ids_and_unknown_identity_versions_are_rejected(self):
        source = identified_source()
        del source["physical_identity_version"]
        with self.assertRaisesRegex(ValueError, "require physical_identity_version=1"):
            build_descriptors.inventory_binding_contract("fixture", source)

        source = identified_source()
        source["physical_identity_version"] = 2
        with self.assertRaisesRegex(ValueError, "unsupported physical_identity_version"):
            build_descriptors.inventory_binding_contract("fixture", source)

        source = identified_source()
        source["physical_identity_version"] = True
        with self.assertRaisesRegex(ValueError, "unsupported physical_identity_version"):
            build_descriptors.inventory_binding_contract("fixture", source)


def identified_source():
    return {
        "physical_identity_version": 1,
        "inventory": [
            {"id": "battery", "name": "Battery"},
            {"id": "fuselage", "name": "Fuselage"},
        ],
        "landing_gear": {"contacts": [{"id": "nose_gear"}]},
        "propulsion": {"id": "powerplant"},
        "crash_hull": {"value": [[0.0, 0.0, 0.0]]},
        "crash_hull_ids": ["hull_nose"],
        "controls": {"surface_ids": {
            "aileron_left": "aileron_left",
            "aileron_right": "aileron_right",
            "elevator": "elevator",
            "rudder": "rudder",
        }},
    }


if __name__ == "__main__":
    unittest.main()
