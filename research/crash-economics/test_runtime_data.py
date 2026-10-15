"""Focused contract tests for the generated runtime economics sidecar."""

from __future__ import annotations

import copy
import hashlib
import unittest
from pathlib import Path

import build_runtime


class RuntimeEconomicsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.document, cls.context = build_runtime.build_runtime_data()
        cls.dossiers = {row["aircraft_id"]: row for row in cls.document["aircraft"]}

    def test_generated_sidecar_is_current_and_route_coverage_is_dynamic(self) -> None:
        output = build_runtime.ROOT / build_runtime.OUTPUT_PATH
        self.assertEqual(output.read_bytes(), build_runtime.render_runtime_json(self.document))
        self.assertEqual(set(self.dossiers), set(self.context["routes"]))
        self.assertEqual(len(self.dossiers), len(self.context["routes"]))
        build_runtime.validate_runtime_document(self.document, self.context)

    def test_source_hashes_match_exact_physical_json_bytes(self) -> None:
        for aircraft_id, route in self.context["route_sources"].items():
            relative = route["data_uri"].removeprefix("res://")
            source_path = build_runtime.ROOT / "app" / Path(*relative.split("/"))
            exact_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
            self.assertEqual(route["source_sha256"], exact_hash, aircraft_id)
            self.assertEqual(self.dossiers[aircraft_id]["source_sha256"], exact_hash, aircraft_id)

    def test_stik_bom_covers_real_inventory_and_keeps_four_servos_separate(self) -> None:
        dossier = self.dossiers["jensen-das-ugly-stik-60"]
        self.assertTrue(dossier["complete"])
        components = {row["id"]: row for row in dossier["components"]}
        self.assertEqual(len(components), 9)
        self.assertEqual(components["fuselage_servos"]["quantity"], 3)
        self.assertEqual(components["central_aileron_servo"]["quantity"], 1)
        self.assertEqual(components["fuselage_servos"]["unit_minor"], 3399)
        self.assertEqual(components["central_aileron_servo"]["unit_minor"], 3399)
        self.assertEqual(components["final_assembly_and_commissioning"]["quantity"], 1)
        self.assertEqual(components["final_assembly_and_commissioning"]["physical_inventory_ids"], [])
        covered = {
            physical_id
            for component in components.values()
            for physical_id in component["physical_inventory_ids"]
        }
        excluded = {
            physical_id
            for row in dossier["exclusions"]
            for physical_id in row["physical_inventory_ids"]
        }
        source_ids = {row["id"] for row in self.context["route_sources"][dossier["aircraft_id"]]["inventory_rows"]}
        self.assertEqual(covered | excluded, source_ids)
        self.assertNotIn("item_balance_mass_virtual", covered)
        self.assertIn("item_balance_mass_virtual", excluded)

    def test_inherited_61fx_has_distinct_source_hash_and_only_reconciled_bom(self) -> None:
        baseline = self.dossiers["jensen-das-ugly-stik-60"]
        variant = self.dossiers["stik-glow-61fx-2t"]
        self.assertTrue(variant["complete"])
        self.assertNotEqual(variant["source_sha256"], baseline["source_sha256"])
        self.assertEqual(variant["components"], baseline["components"])
        self.assertEqual(variant["contact_components"], baseline["contact_components"])
        self.assertEqual(variant["propeller_component_id"], "propeller")

        changed_context = copy.deepcopy(self.context)
        changed_source = changed_context["route_sources"]["stik-glow-61fx-2t"]["source"]
        changed_source["inventory"][0]["name"] = "unreconciled replacement engine"
        with self.assertRaisesRegex(build_runtime.ContractError, "not reconciled"):
            build_runtime._build_dossiers(changed_context)

    def test_all_other_routes_stay_explicitly_incomplete(self) -> None:
        for aircraft_id, dossier in self.dossiers.items():
            if aircraft_id in {"jensen-das-ugly-stik-60", "stik-glow-61fx-2t"}:
                continue
            self.assertFalse(dossier["complete"], aircraft_id)
            self.assertTrue(dossier["missing"], aircraft_id)
            self.assertEqual(dossier["components"], [], aircraft_id)
            self.assertEqual(dossier["propeller_component_id"], "", aircraft_id)
            self.assertEqual(dossier["propeller_inspection_ids"], [], aircraft_id)

    def test_stik_propeller_event_bindings_resolve_to_component_ids(self) -> None:
        for aircraft_id in ("jensen-das-ugly-stik-60", "stik-glow-61fx-2t"):
            dossier = self.dossiers[aircraft_id]
            self.assertEqual(dossier["contact_components"], {"propeller/propulsion_main": ["propeller"]})
            self.assertEqual(dossier["propeller_component_id"], "propeller")
            self.assertEqual(
                dossier["propeller_inspection_ids"],
                ["engine_and_muffler", "covered_airframe_and_installation_hardware"],
            )

    def test_duplicate_inventory_coverage_is_rejected(self) -> None:
        damaged = copy.deepcopy(self.document)
        baseline = next(row for row in damaged["aircraft"] if row["aircraft_id"] == "jensen-das-ugly-stik-60")
        baseline["components"][0]["physical_inventory_ids"].append("item_propeller_main")
        with self.assertRaisesRegex(build_runtime.ContractError, "duplicate physical coverage"):
            build_runtime.validate_runtime_document(damaged, self.context)

    def test_unknown_offer_and_unmapped_component_references_are_rejected(self) -> None:
        damaged_offer = copy.deepcopy(self.document)
        baseline = next(row for row in damaged_offer["aircraft"] if row["aircraft_id"] == "jensen-das-ugly-stik-60")
        baseline["components"][0]["offer_id"] = "missing-offer"
        with self.assertRaisesRegex(build_runtime.ContractError, "unknown offer reference"):
            build_runtime.validate_runtime_document(damaged_offer, self.context)

        damaged_mapping = copy.deepcopy(self.document)
        baseline = next(row for row in damaged_mapping["aircraft"] if row["aircraft_id"] == "jensen-das-ugly-stik-60")
        baseline["contact_components"]["propeller/propulsion_main"] = ["missing-component"]
        with self.assertRaisesRegex(build_runtime.ContractError, "unknown component ID"):
            build_runtime.validate_runtime_document(damaged_mapping, self.context)

    def test_minor_units_are_bounded_integer_cents(self) -> None:
        fractional = copy.deepcopy(self.document)
        fractional["offers"][0]["amount_minor"] = 1.5
        with self.assertRaisesRegex(build_runtime.ContractError, "integer"):
            build_runtime.validate_runtime_document(fractional, self.context)

        overflow = copy.deepcopy(self.document)
        overflow["offers"][0]["amount_minor"] = build_runtime.MAX_MINOR + 1
        with self.assertRaisesRegex(build_runtime.ContractError, "within|integer"):
            build_runtime.validate_runtime_document(overflow, self.context)

    def test_stale_physical_source_hash_and_missing_route_are_rejected(self) -> None:
        damaged_hash = copy.deepcopy(self.document)
        baseline = next(row for row in damaged_hash["aircraft"] if row["aircraft_id"] == "jensen-das-ugly-stik-60")
        baseline["source_sha256"] = "0" * 64
        with self.assertRaisesRegex(build_runtime.ContractError, "stale or mismatched"):
            build_runtime.validate_runtime_document(damaged_hash, self.context)

        damaged_routes = copy.deepcopy(self.document)
        damaged_routes["aircraft"].pop()
        with self.assertRaisesRegex(build_runtime.ContractError, "route coverage"):
            build_runtime.validate_runtime_document(damaged_routes, self.context)

    def test_arbitrary_or_traversing_aircraft_paths_are_rejected(self) -> None:
        with self.assertRaisesRegex(build_runtime.ContractError, "fixed aircraft data path"):
            build_runtime._parse_aircraft_routes(
                'const ENTRIES := [\n\t{\n\t\tid = "unsafe",\n\t\tdata = "res://../../outside.json",\n\t},\n]\n'
            )


if __name__ == "__main__":
    unittest.main()
