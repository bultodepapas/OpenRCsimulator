"""SC-HUM-07/01 guards for the field-people outfits, the pilots' transmitter and their shipped assets (stdlib only, no Blender).

Checks the outfit specifications, that Population.OUTFITS and the shipped GLBs agree in both directions,
that rejected assets do not return, and that the source and runtime manifests still describe the files.
    python3 tools/scenery/population/test_outfits.py
"""
import hashlib
import json
import re
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

if __package__:
    from . import install_people
else:
    import install_people

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
        current = {path.relative_to(RUNTIME_ROOT).as_posix(): sha256(path)
                   for path in sorted(PEOPLE_DIR.rglob("*")) if path.is_file()}
        self.assertEqual(recorded, current, "RUNTIME_MANIFEST.json people entries are stale")

    def test_transmitter_delivery_is_the_one_baked_into_the_pilots(self):
        recorded = json.loads(HUMAN_SOURCES.read_text())["sc_hum_01_transmitter"]["files"]
        current = {path.name: sha256(path) for path in sorted(TRANSMITTER_DIR.glob("Radiolink_T12D.*"))}
        self.assertEqual({name: entry["sha256"] for name, entry in recorded.items()}, current,
                         "a new transmitter delivery: regenerate both pilots, merge all poses and update HUMAN_SOURCES.json")

    def test_atlas_imports_match_their_material_role(self):
        # The normal atlas must import as a normal map and the diffuse atlas must not (a swapped pair renders yellow skin).
        roles = {}
        for glb in sorted(PEOPLE_DIR.glob("*.glb")):
            data = glb.read_bytes()
            length = struct.unpack_from("<I", data, 12)[0]
            document = json.loads(data[20:20 + length])
            uris = [document["images"][texture["source"]]["uri"] for texture in document["textures"]]
            for material in document["materials"]:
                if "normalTexture" in material:
                    roles.setdefault(uris[material["normalTexture"]["index"]], set()).add("normal")
                base = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
                if base:
                    roles.setdefault(uris[base["index"]], set()).add("diffuse")
        self.assertTrue(roles)
        for uri, used_as in roles.items():
            with self.subTest(texture=uri):
                self.assertEqual(len(used_as), 1, "a texture is both diffuse and normal")
                text = (PEOPLE_DIR / (uri + ".import")).read_text()
                self.assertIn("compress/normal_map=%d" % (1 if used_as == {"normal"} else 0), text)
                # People are seen at 2-32 px heads; a 2048 diffuse / 1024 normal import is indistinguishable at
                # 5 m and saves 13.7 MB of VRAM (optimization round, 2026-10-25).
                self.assertIn("process/size_limit=%d" % (1024 if used_as == {"normal"} else 2048), text)

    def test_atlas_imports_are_compressed_with_mipmaps(self):
        for path in sorted((PEOPLE_DIR / "textures").glob("*.png.import")):
            with self.subTest(texture=path.name):
                text = path.read_text()
                self.assertIn("compress/mode=2", text)
                self.assertIn("mipmaps/generate=true", text)


class ManifestRefresh(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.runtime_root = base / "app/assets/scenery/population"
        self.people_dir = self.runtime_root / "people"
        self.manifest_path = base / "assets/scenery/population/RUNTIME_MANIFEST.json"
        self.human_sources = base / "assets/scenery/population/HUMAN_SOURCES.json"
        self.packaged = base / ".tools/sc-hum-authoring/packaged-people/people"
        self.packaged.mkdir(parents=True)
        self.people_dir.mkdir(parents=True)
        (self.people_dir / "textures").mkdir()
        self.manifest_path.parent.mkdir(parents=True)
        self.human_sources.write_bytes(b"leave source provenance unchanged\n")

        self.runtime_files = {
            "people/member.glb": b"test glb bytes",
            "people/member.glb.import": b"model importer settings\n",
            "people/textures/albedo.png": b"test texture bytes",
            "people/textures/albedo.png.import": b"texture importer settings\n",
        }
        for relative, contents in self.runtime_files.items():
            path = self.runtime_root.joinpath(*relative.split("/"))
            path.write_bytes(contents)

        self.assets = {
            "people/member.glb": {"step": "unchanged people provenance"},
            "scenery/other.glb": {"step": "unchanged nonpeople provenance"},
        }
        self.nonpeople_files = [
            {"path": "aircraft/other.json", "bytes": 4, "sha256": "preserve-this-row"},
        ]
        self.manifest = {
            "schema": "fixture",
            "assets": self.assets,
            "files": self.nonpeople_files + [
                {"path": path, "bytes": 0, "sha256": "stale"}
                for path in self.runtime_files
            ],
        }
        self.manifest_path.write_bytes((json.dumps(self.manifest, indent=2) + "\r\n").encode("utf-8"))

    def _run_refresh(self):
        with patch.multiple(
            install_people,
            RUNTIME_ROOT=self.runtime_root,
            PEOPLE=self.people_dir,
            RUNTIME_MANIFEST=self.manifest_path,
            HUMAN_SOURCES=self.human_sources,
            PACKAGED=self.packaged,
        ):
            return install_people.main(["--refresh-manifest"])

    def test_refresh_uses_portable_paths_and_preserves_other_manifest_data(self):
        original_runtime_bytes = {
            relative: self.runtime_root.joinpath(*relative.split("/")).read_bytes()
            for relative in self.runtime_files
        }
        original_sources = self.human_sources.read_bytes()

        self.assertEqual(self._run_refresh(), 0)

        raw = self.manifest_path.read_bytes()
        self.assertTrue(raw.endswith(b"\n"))
        self.assertNotIn(b"\r\n", raw)
        refreshed = json.loads(raw)
        self.assertEqual(refreshed["assets"], self.assets)
        self.assertEqual(
            [record for record in refreshed["files"] if not install_people._is_people_path(record["path"])],
            self.nonpeople_files,
        )

        people_records = [record for record in refreshed["files"] if install_people._is_people_path(record["path"])]
        self.assertEqual({record["path"] for record in people_records}, set(self.runtime_files))
        self.assertEqual(len(people_records), len(self.runtime_files))
        for record in people_records:
            with self.subTest(path=record["path"]):
                self.assertNotIn("\\", record["path"])
                path = self.runtime_root.joinpath(*record["path"].split("/"))
                contents = path.read_bytes()
                self.assertEqual(record["bytes"], len(contents))
                self.assertEqual(record["sha256"], hashlib.sha256(contents).hexdigest())
        self.assertEqual(original_runtime_bytes, {
            relative: self.runtime_root.joinpath(*relative.split("/")).read_bytes()
            for relative in self.runtime_files
        })
        self.assertEqual(self.human_sources.read_bytes(), original_sources)

    def test_refresh_refuses_missing_expected_file_without_writing_manifest(self):
        missing_path = self.people_dir / "member.glb.import"
        missing_path.unlink()
        original_manifest = self.manifest_path.read_bytes()

        with self.assertRaisesRegex(SystemExit, "missing: people/member.glb.import"):
            self._run_refresh()

        self.assertEqual(self.manifest_path.read_bytes(), original_manifest)

    def test_refresh_refuses_empty_expected_inventory(self):
        for path in self.people_dir.rglob("*"):
            if path.is_file():
                path.unlink()
        self.manifest["files"] = self.nonpeople_files
        self.manifest_path.write_bytes((json.dumps(self.manifest, indent=2) + "\n").encode("utf-8"))
        original_manifest = self.manifest_path.read_bytes()

        with self.assertRaisesRegex(SystemExit, "no expected people file paths"):
            self._run_refresh()

        self.assertEqual(self.manifest_path.read_bytes(), original_manifest)


if __name__ == "__main__":
    unittest.main(verbosity=1)
