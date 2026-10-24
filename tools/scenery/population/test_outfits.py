"""SC-HUM-07/01 guards for the field-people outfits, the pilots' transmitter and their shipped assets (stdlib only, no Blender).

Checks the outfit specifications, that Population.OUTFITS and the shipped GLBs agree in both directions,
that rejected assets do not return, and that the source and runtime manifests still describe the files.
    python3 tools/scenery/population/test_outfits.py
"""
import hashlib
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUTFITS_DIR = ROOT / "tools/scenery/population/outfits"
POPULATION_GD = ROOT / "app/scenery/population.gd"
PEOPLE_DIR = ROOT / "app/assets/scenery/population/people"
RUNTIME_ROOT = ROOT / "app/assets/scenery/population"
HUMAN_SOURCES = ROOT / "assets/scenery/population/HUMAN_SOURCES.json"
RUNTIME_MANIFEST = ROOT / "assets/scenery/population/RUNTIME_MANIFEST.json"
TRANSMITTER_DIR = ROOT / "assets/source-deliveries/radiolink-t12d"
POSES = {"standing", "sitting", "pilot", "working"}
SUBDIRS = {"eyes", "eyebrows", "eyelashes", "hair", "clothes"}
# Rejected in SC-HUM-07: political slogan, no material line, 26k triangles, women's short shorts.
REJECTED = {"toigo_maga_hat.mhclo", "jujube_newsboy_cap.mhclo", "toigo_flats.mhclo", "cortu_jeans_shorts.mhclo"}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def population_outfits():
    """Pose -> outfit ids from OUTFITS and ZONE_OUTFITS in population.gd."""
    text = POPULATION_GD.read_text()
    used = {}
    for block in ("OUTFITS", "ZONE_OUTFITS"):
        body = re.search(r"const %s := \{(.*?)\n\}" % block, text, re.S).group(1)
        for pose, names in re.findall(r'"(standing|sitting|pilot|working)":\s*\[([^\]]*)\]', body):
            used.setdefault(pose, set()).update(re.findall(r'"([a-z_]+)"', names))
    return used


class OutfitSpecs(unittest.TestCase):
    def setUp(self):
        self.specs = {path.stem: json.loads(path.read_text()) for path in sorted(OUTFITS_DIR.glob("*.json"))}

    def test_specs_are_complete_and_bounded(self):
        self.assertGreaterEqual(len(self.specs), 6)
        for stem, spec in self.specs.items():
            with self.subTest(outfit=stem):
                self.assertEqual(spec["id"], stem)
                self.assertEqual(spec["height"], "natural")
                self.assertTrue(spec["proxy"].endswith(".proxy"))
                self.assertTrue(spec["skin"].endswith(".mhmat"))
                for key, value in spec["macros"].items():
                    if key == "race":
                        self.assertAlmostEqual(sum(value.values()), 1.0, places=6)
                    else:
                        self.assertTrue(0.0 <= value <= 1.0, key)
                files = [asset[1] for asset in spec["assets"]]
                self.assertIn("low-poly.mhclo", files, "the head rig needs the low-poly eye proxy")
                for subdir, name, kind in spec["assets"]:
                    self.assertIn(subdir, SUBDIRS)
                    self.assertTrue(name.endswith(".mhclo"))
                    self.assertNotIn(name, REJECTED)
                    self.assertIn(kind, {"Eyes", "Eyebrows", "Eyelashes", "Hair", "Clothes"})
                for ratio in spec["decimate"].values():
                    self.assertTrue(0.0 < ratio <= 1.0)
                for edge in spec["image_max_edge"].values():
                    self.assertIn(edge, {128, 256, 512, 1024})
                for pose_kind in spec.get("pose_files", {}):
                    self.assertIn(pose_kind, {"standing", "seated", "pilot", "working"})

    def test_population_and_shipped_files_agree(self):
        used = population_outfits()
        self.assertEqual(set(used), POSES)
        expected = set()
        for pose, outfits in used.items():
            for outfit in outfits:
                self.assertIn(outfit, self.specs, "Population lists an outfit without a spec: " + outfit)
                expected.add("%s_%s.glb" % (outfit, pose))
        self.assertEqual({o for names in used.values() for o in names}, set(self.specs), "every outfit spec is used")
        shipped = {path.name for path in PEOPLE_DIR.glob("*.glb")}
        self.assertEqual(shipped, expected, "shipped people GLBs must match Population exactly (no missing, no orphans)")
        for name in shipped:
            self.assertTrue((PEOPLE_DIR / (name + ".import")).is_file(), name + " needs its import settings")


class Manifests(unittest.TestCase):
    def test_outfit_spec_hashes_are_current(self):
        recorded = json.loads(HUMAN_SOURCES.read_text())["sc_hum_07_outfits"]["outfit_specs_sha256"]
        current = {path.name: sha256(path) for path in sorted(OUTFITS_DIR.glob("*.json"))}
        self.assertEqual(recorded, current, "regenerate the people and update HUMAN_SOURCES.json after editing an outfit")

    def test_runtime_manifest_matches_people_files(self):
        files = json.loads(RUNTIME_MANIFEST.read_text())["files"]
        recorded = {f["path"]: f["sha256"] for f in files if f["path"].startswith("people/")}
        current = {str(path.relative_to(RUNTIME_ROOT)): sha256(path)
                   for path in sorted(PEOPLE_DIR.rglob("*")) if path.is_file()}
        self.assertEqual(recorded, current, "RUNTIME_MANIFEST.json people entries are stale")

    def test_transmitter_delivery_is_the_one_baked_into_the_pilots(self):
        recorded = json.loads(HUMAN_SOURCES.read_text())["sc_hum_01_transmitter"]["files"]
        current = {path.name: sha256(path) for path in sorted(TRANSMITTER_DIR.glob("Radiolink_T12D.*"))}
        self.assertEqual({name: entry["sha256"] for name, entry in recorded.items()}, current,
                         "a new transmitter delivery: regenerate both pilots, merge all poses and update HUMAN_SOURCES.json")

    def test_atlas_imports_are_compressed_with_mipmaps(self):
        for path in sorted((PEOPLE_DIR / "textures").glob("*.png.import")):
            with self.subTest(texture=path.name):
                text = path.read_text()
                self.assertIn("compress/mode=2", text)
                self.assertIn("mipmaps/generate=true", text)


if __name__ == "__main__":
    unittest.main(verbosity=1)
