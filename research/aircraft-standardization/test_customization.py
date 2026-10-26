#!/usr/bin/env python3
"""Focused reproducibility and schema checks for authored aircraft customization bindings."""

from __future__ import annotations

import copy
import hashlib
import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_customization as generator


class CustomizationGeneratorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = generator.ROOT
        self.source = json.loads((self.root / generator.SOURCE_PATH).read_text(encoding="utf-8"))
        model_source = json.loads((self.root / generator.MODEL_SOURCE_PATH).read_text(encoding="utf-8"))
        self.families = {item["family_id"] for item in model_source["families"]}

    def _v3_source(self) -> dict[str, object]:
        source = copy.deepcopy(self.source)
        source["version"] = 3
        for family in source["families"]:
            family["lighting_layout"] = generator.empty_lighting_layout()
        return source

    def test_presentation_source_versions_keep_closed_legacy_sets(self) -> None:
        legacy = generator.LEGACY_PRESENTATION_SOURCE_PATHS
        v2 = generator.PRESENTATION_SOURCE_PATHS_V2
        v3 = generator.PRESENTATION_SOURCE_PATHS_V3
        self.assertEqual(len(legacy), 7)
        self.assertEqual(len(v2), 10)
        self.assertEqual(len(v3), 28)
        self.assertEqual(tuple(sorted(v3)), v3)
        self.assertTrue(set(legacy).issubset(v2))
        self.assertTrue(set(v2).issubset(v3))
        self.assertEqual(generator.PRESENTATION_SOURCE_PATHS, v3)
        gd_sources = (self.root / "app/render/presentation_sources.gd").read_text(encoding="utf-8")
        for constant_name, expected in (("SOURCE_PATHS", legacy), ("SOURCE_PATHS_V2", v2), ("SOURCE_PATHS_V3", v3)):
            match = re.search(rf"const {constant_name} := \[(.*?)\n\]", gd_sources, re.DOTALL)
            self.assertIsNotNone(match, constant_name)
            actual = re.findall(r'"(res://[^\"]+)"', match.group(1))
            self.assertEqual(actual, list(expected), constant_name)

    def test_historical_sources_default_to_an_empty_lighting_layout(self) -> None:
        source_v2 = copy.deepcopy(self.source)
        source_v2["version"] = 2
        for family in source_v2["families"]:
            family.pop("lighting_layout", None)
        slots_v2 = generator.validate_source(source_v2, self.families)
        self.assertTrue(all(slots["lighting_layout"] == generator.empty_lighting_layout() for slots in slots_v2.values()))

        source_v1 = {
            "format": generator.SOURCE_FORMAT,
            "version": 1,
            "families": [{
                "visual_family": "historical-fixture",
                "paint_slots": [],
                "marking_slots": [],
                "smoke_slots": [
                    {"id": "wing_left", "label": "Left", "kind": "show", "pair": "wing_tips", "role": "wing_tip_left",
                     "node_path": ".", "position_m": [-0.5, 0, 0], "direction": [0, 0, 1]},
                    {"id": "wing_right", "label": "Right", "kind": "show", "pair": "wing_tips", "role": "wing_tip_right",
                     "node_path": ".", "position_m": [0.5, 0, 0], "direction": [0, 0, 1]},
                    {"id": "tail", "label": "Tail", "kind": "show", "pair": "", "role": "tail",
                     "node_path": ".", "position_m": [0, 0, 1], "direction": [0, 0, 1]},
                ],
            }],
        }
        slots_v1 = generator.validate_source(source_v1, {"historical-fixture"})
        self.assertEqual(slots_v1["historical-fixture"]["lighting_layout"], generator.empty_lighting_layout())

    def test_skin_bindings_reference_stable_albedo_targets(self) -> None:
        slots = generator.validate_source(self.source, self.families)
        layout = slots["jensen-das-ugly-stik-60"]["lighting_layout"]
        self.assertEqual(layout["version"], 2)
        self.assertEqual(layout["skins"], [
            {
                "zone_id": "strip_left",
                "paint_slot_id": "wing",
                "target_ids": ["wing_left_0_skin", "wing_left_1_skin", "wing_left_2_skin"],
                "mask_profile_id": "jensen_stik_film_bays_v1",
            },
            {
                "zone_id": "strip_right",
                "paint_slot_id": "wing",
                "target_ids": ["wing_right_0_skin", "wing_right_1_skin", "wing_right_2_skin"],
                "mask_profile_id": "jensen_stik_film_bays_v1",
            },
        ])

        invalid_source = copy.deepcopy(self.source)
        stik = next(item for item in invalid_source["families"] if item["visual_family"] == "jensen-das-ugly-stik-60")
        stik["lighting_layout"]["skins"][0]["target_ids"][0] = "unregistered_surface"
        with self.assertRaises(generator.CustomizationError):
            generator.validate_source(invalid_source, self.families)

        invalid_source = copy.deepcopy(self.source)
        stik = next(item for item in invalid_source["families"] if item["visual_family"] == "jensen-das-ugly-stik-60")
        stik["lighting_layout"]["skins"][0]["mask_profile_id"] = "res://textures/arbitrary.png"
        with self.assertRaises(generator.CustomizationError):
            generator.validate_source(invalid_source, self.families)

        invalid_source = copy.deepcopy(self.source)
        stik = next(item for item in invalid_source["families"] if item["visual_family"] == "jensen-das-ugly-stik-60")
        stik["lighting_layout"]["skins"][1]["target_ids"][0] = stik["lighting_layout"]["skins"][0]["target_ids"][0]
        with self.assertRaises(generator.CustomizationError):
            generator.validate_source(invalid_source, self.families)

    def test_generated_registry_is_current(self) -> None:
        self.assertEqual(generator.generate(self.root, True), 0)

    def test_companions_pin_exact_manifest_bytes_and_self_hash_slots(self) -> None:
        registry = json.loads((self.root / generator.OUTPUT_PATH).read_text(encoding="utf-8"))
        authored_layouts = {item["visual_family"]: item.get("lighting_layout", generator.empty_lighting_layout())
                            for item in self.source["families"]}
        self.assertEqual(registry["format"], generator.REGISTRY_FORMAT)
        self.assertEqual({item["visual_family"] for item in registry["families"]}, self.families)
        for companion in registry["families"]:
            family = companion["visual_family"]
            self.assertEqual(companion["version"], 4)
            self.assertEqual(companion["source_proof_version"], 3)
            if family == "jensen-das-ugly-stik-60":
                self.assertEqual(companion["lighting_layout"], {
                    "version": 2,
                    "anchors": authored_layouts[family]["anchors"],
                    "strips": [],
                    "skins": [
                        {
                            "zone_id": "strip_left",
                            "paint_slot_id": "wing",
                            "target_ids": ["wing_left_0_skin", "wing_left_1_skin", "wing_left_2_skin"],
                            "mask_profile_id": "jensen_stik_film_bays_v1",
                        },
                        {
                            "zone_id": "strip_right",
                            "paint_slot_id": "wing",
                            "target_ids": ["wing_right_0_skin", "wing_right_1_skin", "wing_right_2_skin"],
                            "mask_profile_id": "jensen_stik_film_bays_v1",
                        },
                    ],
                })
            else:
                self.assertEqual(companion["lighting_layout"], authored_layouts[family])
            self.assertEqual(companion["presentation_engine_version"], generator.PRESENTATION_ENGINE_VERSION)
            self.assertEqual([item["path"] for item in companion["presentation_sources"]],
                             list(generator.PRESENTATION_SOURCE_PATHS))
            manifest = self.root / generator.MODEL_OUTPUT_DIR / f"{family}.json"
            self.assertEqual(companion["model_manifest_sha256"], hashlib.sha256(manifest.read_bytes()).hexdigest())
            unsigned = copy.deepcopy(companion)
            digest = unsigned.pop("slots_sha256")
            self.assertEqual(digest, hashlib.sha256(generator.canonical_bytes(unsigned)).hexdigest())

    def test_presentation_source_hashes_are_lf_normalized(self) -> None:
        records = generator.presentation_sources(self.root)
        self.assertEqual([item["path"] for item in records], sorted(generator.PRESENTATION_SOURCE_PATHS))
        for record in records:
            self.assertEqual(set(record), {"path", "sha256"})
            self.assertRegex(record["sha256"], r"^[0-9a-f]{64}$")
            source_path = self.root / "app" / record["path"].removeprefix("res://")
            text = source_path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
            self.assertEqual(record["sha256"], hashlib.sha256(text.encode("utf-8")).hexdigest())

    def test_presentation_changes_repin_slots_without_changing_physical_manifest_pin(self) -> None:
        slots = generator.validate_source(self.source, self.families)["jensen-das-ugly-stik-60"]
        original_sources = [{"path": path, "sha256": "0" * 64} for path in generator.PRESENTATION_SOURCE_PATHS]
        changed_sources = copy.deepcopy(original_sources)
        changed_sources[0]["sha256"] = "1" * 64
        manifest_hash = "a" * 64
        original = generator.build_companion("jensen-das-ugly-stik-60", manifest_hash, slots, original_sources)
        changed = generator.build_companion("jensen-das-ugly-stik-60", manifest_hash, slots, changed_sources)
        self.assertEqual(original["model_manifest_sha256"], changed["model_manifest_sha256"])
        self.assertNotEqual(original["slots_sha256"], changed["slots_sha256"])

    def test_canonical_hash_normalizes_integral_float_numbers(self) -> None:
        self.assertEqual(generator.canonical_bytes({"b": [1.0], "a": 2}),
                         generator.canonical_bytes({"a": 2.0, "b": [1]}))

    def test_source_outlets_share_one_stable_source_without_positional_selectors(self) -> None:
        slots = generator.validate_source(self.source, self.families)
        stik = slots["jensen-das-ugly-stik-60"]["smoke_slots"]
        ordinary = next(slot for slot in stik if slot["id"] == "source_exhaust")
        pump = next(slot for slot in stik if slot["id"] == "show_exhaust")
        self.assertEqual(ordinary["source_id"], pump["source_id"])
        self.assertEqual(ordinary["anchor_id"], "physical_exit")
        self.assertEqual(pump["activation_policy"], "source_and_request")
        self.assertNotIn("source_anchor_ref", ordinary)
        self.assertEqual(slots["gp-extra-300s-60"]["smoke_slots"][0]["kind"], "show")

    def test_v3_rejects_unknown_keys_invalid_source_and_unbounded_mounts(self) -> None:
        changes = ({"radius_m": True}, {"radius_m": 0.2}, {"anchor_id": "../escape"},
                   {"source_id": "res://run.gd"}, {"source_kind": "gasoline_guess"},
                   {"activation_policy": "independent_request"}, {"provenance": "validated"},
                   {"arbitrary": 1})
        for change in changes:
            bad = copy.deepcopy(self.source)
            slot = next(s for s in bad["families"][0]["smoke_slots"] if s["kind"] == "source")
            slot.update(change)
            with self.subTest(change=change), self.assertRaises(generator.CustomizationError):
                generator.validate_source(bad, self.families)

    def test_v3_lighting_layout_sorts_ids_and_preserves_strip_point_order(self) -> None:
        source = self._v3_source()
        family = source["families"][0]
        family["lighting_layout"] = {
            "version": 1,
            "anchors": [
                {"id": "nav_right", "node_path": "wing_frame_right", "position_m": [1, 0, 0], "gear_gated": False},
                {"id": "nav_left", "node_path": ".", "position_m": [-1, 0, 0], "gear_gated": False},
                {"id": "nav_tail", "node_path": ".", "position_m": [0, 0, 1], "gear_gated": False},
            ],
            "strips": [{
                "id": "strip_top_left", "node_path": "wing_frame_left",
                "points_m": [[0.8, 0, 0], [-0.8, 0, 0]], "face": [0, 1, 0], "width_m": 0.01,
            }, {
                "id": "strip_belly", "node_path": ".",
                "points_m": [[0, 0, 0.2], [0, 0, -0.2]], "face": [1, 0, 0], "width_m": 0.02,
            }],
        }
        slots = generator.validate_source(source, self.families)
        layout = slots[family["visual_family"]]["lighting_layout"]
        self.assertEqual([item["id"] for item in layout["anchors"]], ["nav_left", "nav_right", "nav_tail"])
        self.assertEqual([item["id"] for item in layout["strips"]], ["strip_belly", "strip_top_left"])
        self.assertEqual(layout["strips"][1]["points_m"], [[0.8, 0, 0], [-0.8, 0, 0]])

    def test_v3_lighting_layout_rejects_malformed_paths_duplicates_nonfinite_and_bounds(self) -> None:
        anchor = {"id": "nav_left", "node_path": ".", "position_m": [0, 0, 0], "gear_gated": False}
        strip = {"id": "strip_left", "node_path": ".", "points_m": [[0, 0, 0], [1, 0, 0]], "face": [0, 1, 0], "width_m": 0.01}
        bad_layouts = []

        bad = generator.empty_lighting_layout()
        bad["anchors"] = [dict(anchor, node_path="../wing")]
        bad_layouts.append(("path traversal", bad))

        bad = generator.empty_lighting_layout()
        bad["anchors"] = [dict(anchor, node_path="a" * (generator.LIGHT_NODE_PATH_MAX_CHARS + 1))]
        bad_layouts.append(("long path", bad))

        bad = generator.empty_lighting_layout()
        bad["anchors"] = [anchor, copy.deepcopy(anchor)]
        bad_layouts.append(("duplicate anchor id", bad))

        bad = generator.empty_lighting_layout()
        bad["anchors"] = [dict(anchor, position_m=[0, float("nan"), 0])]
        bad_layouts.append(("nonfinite anchor position", bad))

        bad = generator.empty_lighting_layout()
        bad["anchors"] = [dict(anchor, position_m=[10 ** 1000, 0, 0])]
        bad_layouts.append(("unrepresentable anchor position", bad))

        bad = generator.empty_lighting_layout()
        bad["anchors"] = [dict(anchor, position_m=[5.001, 0, 0])]
        bad_layouts.append(("anchor bound", bad))

        bad = generator.empty_lighting_layout()
        bad["anchors"] = [dict(anchor, id="tail")]
        bad_layouts.append(("unsupported legacy anchor alias", bad))

        bad = generator.empty_lighting_layout()
        bad["anchors"] = [{**anchor, "id": "strobe_dorsal", "gear_gated": True}]
        bad_layouts.append(("invalid gear gating", bad))

        bad = generator.empty_lighting_layout()
        bad["strips"] = [strip, copy.deepcopy(strip)]
        bad_layouts.append(("duplicate strip id", bad))

        bad = generator.empty_lighting_layout()
        bad["strips"] = [dict(strip, node_path="wing//left")]
        bad_layouts.append(("malformed strip path", bad))

        bad = generator.empty_lighting_layout()
        bad["strips"] = [dict(strip, points_m=[[0, 0, 0], [float("inf"), 0, 0]])]
        bad_layouts.append(("nonfinite strip point", bad))

        bad = generator.empty_lighting_layout()
        bad["strips"] = [dict(strip, points_m=[[0, 0, 0], [5.01, 0, 0]])]
        bad_layouts.append(("strip point bound", bad))

        bad = generator.empty_lighting_layout()
        bad["strips"] = [dict(strip, points_m=[[0, 0, 0], [0.000009, 0, 0]])]
        bad_layouts.append(("adjacent points too close", bad))

        bad = generator.empty_lighting_layout()
        bad["strips"] = [dict(strip, face=[1, 0, 0])]
        bad_layouts.append(("degenerate segment face", bad))

        bad = generator.empty_lighting_layout()
        bad["strips"] = [dict(strip, width_m=True)]
        bad_layouts.append(("boolean width", bad))

        bad = generator.empty_lighting_layout()
        bad["strips"] = [dict(strip, width_m=10 ** 1000)]
        bad_layouts.append(("unrepresentable width", bad))

        for name, layout in bad_layouts:
            source = self._v3_source()
            source["families"][0]["lighting_layout"] = layout
            with self.subTest(case=name), self.assertRaises(generator.CustomizationError):
                generator.validate_source(source, self.families)

    def test_v3_lighting_layout_requires_exact_shape_and_supported_versions(self) -> None:
        source = self._v3_source()
        source["families"][0].pop("lighting_layout")
        with self.assertRaises(generator.CustomizationError):
            generator.validate_source(source, self.families)

        source = self._v3_source()
        source["families"][0]["lighting_layout"]["unused"] = True
        with self.assertRaises(generator.CustomizationError):
            generator.validate_source(source, self.families)

        source = self._v3_source()
        source["families"][0]["lighting_layout"]["version"] = True
        with self.assertRaises(generator.CustomizationError):
            generator.validate_source(source, self.families)

        source = self._v3_source()
        source["families"][0]["lighting_layout"]["version"] = 1.0
        slots = generator.validate_source(source, self.families)
        self.assertEqual(slots[source["families"][0]["visual_family"]]["lighting_layout"], generator.empty_lighting_layout())

        source = self._v3_source()
        source["families"][0]["lighting_layout"]["version"] = 10 ** 1000
        with self.assertRaises(generator.CustomizationError):
            generator.validate_source(source, self.families)

    def test_two_authored_outlets_can_share_one_engine(self) -> None:
        candidate = copy.deepcopy(self.source)
        slots = candidate["families"][0]["smoke_slots"]
        extra = copy.deepcopy(next(s for s in slots if s["kind"] == "source"))
        extra.update(id="source_exhaust_right", anchor_id="right_exit")
        slots.append(extra)
        validated = generator.validate_source(candidate, self.families)
        sources = [s for s in validated[candidate["families"][0]["visual_family"]]["smoke_slots"] if s["kind"] == "source"]
        self.assertEqual(len(sources), 2)
        self.assertEqual(len({s["source_id"] for s in sources}), 1)

    def test_source_rejects_duplicate_target_and_missing_family(self) -> None:
        bad = copy.deepcopy(self.source)
        paint = bad["families"][0]["paint_slots"]
        paint[0]["targets"].append(copy.deepcopy(paint[0]["targets"][0]))
        with self.assertRaises(generator.CustomizationError):
            generator.validate_source(bad, self.families)

    def test_registration_mounts_are_authored_and_bounded(self) -> None:
        slots = generator.validate_source(self.source, self.families)
        registrations = {
            family: items["marking_slots"]
            for family, items in slots.items()
            if items["marking_slots"]
        }
        self.assertEqual(
            set(registrations),
            {"jensen-das-ugly-stik-60", "gp-extra-300s-60", "turbo-lumber-evolution", "f4u-corsair-250"},
        )
        for family_slots in registrations.values():
            self.assertEqual(len(family_slots), 1)
            slot = family_slots[0]
            self.assertEqual(slot["id"], "registration")
            self.assertEqual(slot["max_chars"], 12)
            self.assertEqual(len(slot["targets"]), 2)
            for target in slot["targets"]:
                self.assertEqual(set(target), {"node_path", "position_m", "direction", "up", "width_m", "height_m"})
                dot = sum(a * b for a, b in zip(target["direction"], target["up"]))
                self.assertAlmostEqual(dot, 0.0, places=3)

    def test_avanti_tailpipe_is_a_distinct_show_mount_at_the_authored_outlet(self) -> None:
        slots = generator.validate_source(self.source, self.families)
        smoke = {slot["id"]: slot for slot in slots["sebart-avanti-s-a200-p100rx"]["smoke_slots"]}
        geometry = json.loads((self.root / "assets/aircraft/avanti-s-a200/blender-geometry.json").read_text(encoding="utf-8"))
        pipe = smoke["show_tailpipe"]
        self.assertEqual(pipe["kind"], "show")
        self.assertEqual(pipe["position_m"], geometry["turbine"]["outlet_position"])
        self.assertEqual(pipe["direction"], geometry["turbine"]["outlet_direction"])
        self.assertNotEqual(pipe["position_m"], smoke["show_tail"]["position_m"])
        for change in ({"pair": "wing_tips"}, {"role": "exhaust"}, {"role": "tail"}):
            bad = copy.deepcopy(self.source)
            family = next(f for f in bad["families"] if f["visual_family"] == "sebart-avanti-s-a200-p100rx")
            next(s for s in family["smoke_slots"] if s["id"] == "show_tailpipe").update(change)
            with self.assertRaises(generator.CustomizationError):
                generator.validate_source(bad, self.families)

    def test_source_rejects_invalid_marking_count_axes_and_extent(self) -> None:
        for key, value in (
            ("max_chars", 13),
            ("max_chars", True),
        ):
            bad = copy.deepcopy(self.source)
            slot = next(f for f in bad["families"] if f["visual_family"] == "jensen-das-ugly-stik-60")["marking_slots"][0]
            slot[key] = value
            with self.assertRaises(generator.CustomizationError):
                generator.validate_source(bad, self.families)

        for key, value in (
            ("up", [-1, 0, 0]),
            ("width_m", 1.01),
            ("height_m", 0.009),
            ("position_m", [0, 0, 5.01]),
        ):
            bad = copy.deepcopy(self.source)
            target = next(f for f in bad["families"] if f["visual_family"] == "jensen-das-ugly-stik-60")["marking_slots"][0]["targets"][0]
            target[key] = value
            with self.assertRaises(generator.CustomizationError):
                generator.validate_source(bad, self.families)

        bad = copy.deepcopy(self.source)
        bad["families"].pop()
        with self.assertRaises(generator.CustomizationError):
            generator.validate_source(bad, self.families)


if __name__ == "__main__":
    unittest.main()
