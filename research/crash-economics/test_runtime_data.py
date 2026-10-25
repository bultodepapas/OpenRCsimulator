"""Focused contract tests for the generated runtime economics sidecar."""

from __future__ import annotations

import copy
import json
import hashlib
import unittest
from pathlib import Path
from unittest.mock import patch

import build_runtime
import build_catalog


# CR-39d: every Stik hull/gear contact opens its single airframe coverage group; GP-07b: the spinner and the
# side-mounted engine's exposed points also inspect the engine. Expected rows come from the Stik's own hull data.
_STIK_SOURCE = json.loads((Path(__file__).resolve().parents[2] / "app/data/aircraft/jensen_ugly_stik_60.json").read_bytes())
STIK_CONTACTS = {
    "propeller/propulsion_main": ["propeller"],
    **{contact_id: ["covered_airframe_and_installation_hardware"] + (
        ["engine_and_muffler"] if contact_id.startswith(("probe_spinner", "probe_engine")) else [])
       for contact_id in _STIK_SOURCE["crash_hull_ids"]},
    **{contact_id: ["covered_airframe_and_installation_hardware"] for contact_id in (
        "contact_main_left", "contact_main_right", "contact_nose")},
}
# Independent anchors: the legacy ids that keep their meaning and the GP-07b points a lost feature would drop.
assert {"probe_wing_left_tip", "probe_wing_right_tip", "probe_spinner_tip", "probe_tail_end", "probe_fin_top",
        "probe_stabilizer_left_tip", "probe_stabilizer_right_tip", "probe_tail_skid", "probe_engine_head"} <= set(STIK_CONTACTS)
assert STIK_CONTACTS["probe_engine_head"] == ["covered_airframe_and_installation_hardware", "engine_and_muffler"]


class RuntimeEconomicsTests(unittest.TestCase):
    def test_price_generator_rejects_crlf_sources_before_hashing(self) -> None:
        original = Path.read_bytes
        target = build_catalog.HERE / build_catalog.SOURCES[0]

        def stale_checkout(path):
            data = original(path)
            return data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n") if path == target else data

        with patch.object(Path, "read_bytes", stale_checkout):
            with self.assertRaisesRegex(ValueError, "use LF line endings"):
                build_catalog.build()

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

    def test_aircraft_catalog_discovery_identity_normalizes_line_endings(self) -> None:
        source = (
            'const ENTRIES := [\n'
            '\t{\n'
            '\t\tid = "example-aircraft",\n'
            '\t\tdata = "res://data/aircraft/example-aircraft.json",\n'
            '\t},\n'
            ']\n'
        ).encode("utf-8")
        crlf_source = source.replace(b"\n", b"\r\n")

        lf_hash, lf_routes = build_runtime._aircraft_catalog_discovery_identity(source)
        crlf_hash, crlf_routes = build_runtime._aircraft_catalog_discovery_identity(crlf_source)

        self.assertEqual(crlf_hash, lf_hash)
        self.assertEqual(crlf_routes, lf_routes)
        self.assertEqual(lf_routes, {"example-aircraft": "res://data/aircraft/example-aircraft.json"})

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

    def test_liquid_fuel_fill_state_is_not_a_saleable_identity(self) -> None:
        # FUEL-05a: a different start fill or tank height keeps the same BOM; any other change still differs.
        source = {"inventory": [
            {"id": "item_fuel_main", "name": "fuel", "energy_source": "glow_fuel",
             "mass": {"value": 0.12}, "position": {"value": [-0.1, 0.0, 0.0]}},
            {"id": "item_fuel_tank", "name": "fuel tank", "mass": {"value": 0.055}, "position": {"value": [-0.1, 0.0, 0.0]}},
        ]}
        refilled = copy.deepcopy(source)
        refilled["inventory"][0]["mass"]["value"] = 0.3
        refilled["inventory"][0]["position"]["value"] = [-0.1, 0.0, 0.02]
        self.assertEqual(build_runtime._inventory_signature(source, "fixture"),
                         build_runtime._inventory_signature(refilled, "fixture"))
        moved_shell = copy.deepcopy(source)
        moved_shell["inventory"][1]["position"]["value"] = [-0.1, 0.0, 0.02]
        self.assertNotEqual(build_runtime._inventory_signature(source, "fixture"),
                            build_runtime._inventory_signature(moved_shell, "fixture"))

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
            if aircraft_id in {"jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t"}:
                continue
            self.assertFalse(dossier["complete"], aircraft_id)
            self.assertTrue(dossier["missing"], aircraft_id)
            if aircraft_id in {"gp-extra-300s-60", "turbo-lumber-evolution", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx",
                               "f4u-corsair-250"}:
                continue
            self.assertEqual(dossier["components"], [], aircraft_id)
            self.assertEqual(dossier["propeller_component_id"], "", aircraft_id)
            self.assertEqual(dossier["propeller_inspection_ids"], [], aircraft_id)

    def test_fleet_part_subtotals_do_not_claim_full_aircraft_prices(self) -> None:
        cases = {"turbo-lumber-evolution": 46587, "p51d-mustang-120": 245671,
                 "sebart-avanti-s-a200-p100rx": 655912}
        for aircraft_id, subtotal in cases.items():
            dossier = self.dossiers[aircraft_id]
            self.assertFalse(dossier["complete"])
            self.assertTrue(dossier["missing"])
            parts = dossier["components"]
            self.assertEqual(sum(row["quantity"] * (row["unit_minor"] or 0) for row in parts), subtotal)
            bound = [pid for row in parts for pid in row["physical_inventory_ids"]]
            excluded = [pid for row in dossier["exclusions"] for pid in row["physical_inventory_ids"]]
            source_ids = {row["id"] for row in self.context["route_sources"][aircraft_id]["inventory_rows"]}
            self.assertEqual(len(bound), len(set(bound)))
            self.assertEqual(set(bound + excluded), source_ids)
            self.assertTrue(any(row["unit_minor"] is None for row in parts))
        electric = self.dossiers["turbo-lumber-evolution"]
        # The physical inventory combines blade and spinner, while economics separates
        # the automatic blade replacement from the separately inspected spinner value.
        self.assertEqual(electric["propeller_component_id"], "propeller_main")
        self.assertEqual(electric["contact_components"]["propeller/propulsion_main"], ["propeller_main"])
        self.assertEqual(electric["contact_components"]["probe_spinner_tip"], ["spinner_main", "motor_main", "fuselage_main"])
        self.assertEqual(electric["propeller_inspection_ids"], ["spinner_main", "motor_main", "fuselage_main"])
        prop = next(row for row in electric["components"] if row["id"] == "propeller_main")
        self.assertEqual(prop["unit_minor"], 799)
        self.assertEqual(prop["offer_id"], "timber_evolution_propeller_efl5962_horizon_20261020")
        self.assertEqual(prop["price_basis"], "price_proxy")
        self.assertEqual(prop["physical_inventory_ids"], ["propeller_main"])
        spinner = next(row for row in electric["components"] if row["id"] == "spinner_main")
        self.assertEqual(spinner["quantity"], 1)
        self.assertEqual(spinner["unit_minor"], 899)
        self.assertEqual(spinner["offer_id"], "timber_evolution_spinner_efl17553_horizon_20261020")
        self.assertEqual(spinner["price_basis"], "price_proxy")
        self.assertEqual(spinner["physical_inventory_ids"], [])
        battery = next(row for row in electric["components"] if row["id"] == "battery_main")
        self.assertEqual(battery["offer_id"], "timber_evolution_battery_proxy_horizon_20261020")
        self.assertEqual(battery["unit_minor"], 6999)
        self.assertEqual(self.context["offer_by_id"][battery["offer_id"]]["availability"], "Backorder; estimated October 2026")
        selected = {row["offer_id"] for row in electric["components"]}
        self.assertNotIn("timber_evolution_pnp_aircraft_horizon_20261020", selected)
        self.assertNotIn("timber_evolution_bnf_aircraft_horizon_20261020", selected)
        current_timber_offers = [
            offer for offer_id, offer in self.context["offer_by_id"].items()
            if offer_id.startswith("timber_evolution_") and offer_id.endswith("_horizon_20261020")
        ]
        self.assertEqual(len(current_timber_offers), 21)
        self.assertTrue(all(offer["observed_on"] == "2026-10-20" for offer in current_timber_offers))
        source_cost = build_catalog.read(build_catalog.HERE / "aircraft-costing.json")
        timber_candidates = next(
            row["price_observations"] for row in source_cost["fleet"]
            if row["aircraft_id"] == "turbo-lumber-evolution"
        )
        self.assertEqual(len(timber_candidates), 21)
        self.assertTrue(all(offer_id.endswith("_horizon_20261020") for offer_id in timber_candidates))
        self.assertTrue(set(timber_candidates).issubset(self.context["offer_by_id"]))
        # Historical quotes remain in the dated evidence catalog, but no longer
        # appear as current Turbo Timber candidates alongside their replacements.
        self.assertIn("timber_evolution_battery_proxy", self.context["offer_by_id"])
        self.assertNotIn("timber_evolution_battery_proxy", timber_candidates)
        self.assertEqual(self.context["price_date"], "2026-10-20")
        self.assertEqual(self.dossiers["xcell-60-research"]["components"], [])

    def test_p51_canister_count_and_selected_variant_do_not_close_exhaust_scope(self) -> None:
        dossier = self.dossiers["p51d-mustang-120"]
        line = next(row for row in dossier["components"] if row["id"] == "muffler_pair")
        self.assertEqual(line["quantity"], 2)
        self.assertEqual(line["unit_minor"], 22500)
        self.assertEqual(line["quantity"] * line["unit_minor"], 45000)
        self.assertEqual(line["price_basis"], "price_proxy")
        offers = self.context["offer_by_id"]
        canister = offers[line["offer_id"]]
        self.assertIn("variant=5330902529", canister["source_url"])
        self.assertEqual(canister["observed_on"], "2026-10-16")
        comparison_id = "da120_slimline_pair_desert_aircraft_20261016"
        self.assertEqual(offers[comparison_id]["amount_minor"], 21000)
        self.assertNotIn(comparison_id, {row["offer_id"] for row in dossier["components"]})
        self.assertFalse(dossier["complete"])
        self.assertTrue(any("headers" in reason for reason in dossier["missing"]))
        old_offer = offers["jetcat-p100-rx-850100-carf"]
        self.assertEqual(old_offer["observed_on"], "2026-10-15")
        self.assertEqual(old_offer["amount_minor"], 278000)

    def test_service_parts_do_not_duplicate_whole_engine_or_servo_costs(self) -> None:
        records = build_catalog.read(build_catalog.HERE / "price-research-components.json")
        parts = [row for row in records if "service_compatibility" in row]
        self.assertEqual(len(parts), 8)
        installed_offers = {row["offer_id"] for dossier in self.dossiers.values() for row in dossier["components"]}
        for part in parts:
            with self.subTest(part=part["id"]):
                self.assertNotIn(part["id"], installed_offers)
                offer = self.context["offer_by_id"][part["id"]]
                self.assertEqual(offer["amount_minor"], build_catalog.cents(part["amount_usd"]))
                self.assertEqual(offer["observed_on"], "2026-10-16")
                self.assertIn(part["whole_unit_reference"], self.context["offer_by_id"])
                self.assertTrue(part["service_compatibility"]["target_model"])

    def test_packaged_repair_recipes_match_authored_snapshot(self) -> None:
        self.assertEqual((build_runtime.ROOT / build_runtime.REPAIR_OUTPUT_PATH).read_bytes(),
                         build_runtime.render_repair_book())

    def test_composite_prices_retain_constituents_and_use_live_catalog_arithmetic(self) -> None:
        source = build_catalog.read(build_catalog.HERE / "aircraft-costing.json")
        fleet = next(row for row in source["fleet"] if row["aircraft_id"] == "turbo-lumber-evolution")
        wing = next(row for row in fleet["dossier"]["lines"] if row["id"] == "wing_main")
        offers = copy.deepcopy(self.context["offer_by_id"])
        result = build_runtime._baseline_components({"lines": [wing]}, offers)[0]
        self.assertEqual(result["unit_minor"], 11595)
        self.assertIn("4 x timber_evolution_servo_spmsa370_horizon_20261020", result["notes"])
        self.assertIn("Backorder", result["notes"])
        self.assertIn("https://", result["notes"])
        offers[wing["price_constituents"][1]["offer_id"]]["amount_minor"] += 1
        self.assertEqual(build_runtime._baseline_components({"lines": [wing]}, offers)[0]["unit_minor"], 11599)

    def test_composite_references_counts_and_overrides_fail_closed(self) -> None:
        source = build_catalog.read(build_catalog.HERE / "aircraft-costing.json")
        fleet = next(row for row in source["fleet"] if row["aircraft_id"] == "turbo-lumber-evolution")
        line = next(row for row in fleet["dossier"]["lines"] if row["id"] == "wing_main")
        variants = []
        for quantity in [0, -1, True, 1.5, 1000001]:
            candidate = copy.deepcopy(line)
            candidate["price_constituents"][0]["quantity"] = quantity
            variants.append(candidate)
        for field, value in [("estimated_unit_minor", 1), ("price_observation", "apc-lp12060"), ("evidence_kind", "exact_product_price")]:
            candidate = copy.deepcopy(line)
            candidate[field] = value
            variants.append(candidate)
        candidate = copy.deepcopy(line)
        candidate["price_constituents"].append(candidate["price_constituents"][0])
        variants.append(candidate)
        candidate = copy.deepcopy(line)
        candidate["price_constituents"][0]["offer_id"] = "missing"
        variants.append(candidate)
        for candidate in variants:
            with self.assertRaises(build_runtime.ContractError):
                build_runtime._baseline_components({"lines": [candidate]}, self.context["offer_by_id"])

    def test_mixed_observation_dates_preserve_history(self) -> None:
        catalog = build_catalog.build()["catalog.json"]
        offers = {row["id"]: row for row in catalog["observations"]}
        self.assertEqual(catalog["observed_on"], "2026-10-20")
        self.assertEqual(offers["apc-lp12060"]["observed_on"], "2026-10-15")
        self.assertEqual(offers["timber_evolution_wheel_set_efl5258_horizon_20261016"]["observed_on"], "2026-10-16")
        self.assertEqual(offers["timber_evolution_battery_proxy_horizon_20261020"]["observed_on"], "2026-10-20")
        self.assertEqual(offers["timber_evolution_battery_proxy_horizon_20261020"]["availability"], "Backorder; estimated October 2026")
        self.assertIn("superseded", offers["timber_evolution_battery_proxy"]["notes"].lower())

    def test_new_offer_date_requires_matching_dated_evidence(self) -> None:
        original = build_catalog.read
        def modified(path):
            data = original(path)
            if path.name == "price-research-fleet.json":
                data[0]["observed_on"] = "2026-02-30"
            return data
        with patch.object(build_catalog, "read", side_effect=modified):
            with self.assertRaises(ValueError):
                build_catalog.build()

    def test_recipe_prices_cannot_drift_from_reusable_catalog(self) -> None:
        read = build_runtime._read_json
        for field, value in [("package_price_minor", 1), ("offer_id", "unknown-offer")]:
            def mutated(path, field=field, value=value):
                document, raw = read(path)
                if path == build_runtime.ROOT / build_runtime.REPAIR_SOURCE_PATH:
                    document["recipes"][0]["materials"][0][field] = value
                return document, raw
            with patch.object(build_runtime, "_read_json", side_effect=mutated):
                with self.assertRaises(build_runtime.ContractError):
                    build_runtime.render_repair_book()

    def test_independent_extra_maps_five_servos_without_inventing_full_price(self) -> None:
        dossier = self.dossiers["gp-extra-300s-60"]
        parts = {row["id"]: row for row in dossier["components"]}
        self.assertEqual(parts["fuselage_servos"]["quantity"], 3)
        self.assertEqual(parts["aileron_servos"]["quantity"], 2)
        self.assertEqual(sum(row["quantity"] * (row["unit_minor"] or 0) for row in parts.values()), 17534)
        self.assertEqual(parts["propeller"]["unit_minor"], 539)
        self.assertIsNone(parts["muffler_main"]["unit_minor"])
        self.assertIsNone(parts["engine_main"]["unit_minor"])
        self.assertEqual(dossier["contact_components"]["propeller/propulsion_main"], ["propeller"])
        self.assertEqual(dossier["contact_components"]["probe_wing_left_le"], ["wing_main"])
        self.assertEqual(dossier["contact_components"]["contact_tail"], ["landing_gear_tail"])
        covered = [item for row in parts.values() for item in row["physical_inventory_ids"]]
        source_ids = {row["id"] for row in self.context["route_sources"]["gp-extra-300s-60"]["inventory_rows"]}
        self.assertEqual(set(covered) | {"ballast_reference"}, source_ids)
        self.assertEqual(len(covered), len(set(covered)))
        self.assertFalse(dossier["complete"])

    def test_independent_authoring_refuses_drift_and_ambiguous_inheritance(self) -> None:
        aircraft_id = "gp-extra-300s-60"
        mutations = [
            lambda row: row["dossier"].update(expected_source_sha256="0" * 64),
            lambda row: row.update(inherits="jensen-das-ugly-stik-60"),
            lambda row: row["dossier"].pop("propeller_inspection_ids"),
            lambda row: row["dossier"].update(lines=[]),
        ]
        for mutate in mutations:
            changed = copy.deepcopy(self.context)
            mutate(changed["fleet"][aircraft_id])
            with self.assertRaises(build_runtime.ContractError):
                build_runtime._build_dossiers(changed)

    def test_independent_unknown_prices_cannot_claim_complete_coverage(self) -> None:
        changed = copy.deepcopy(self.context)
        changed["fleet"]["gp-extra-300s-60"]["missing"] = []
        changed["fleet"]["gp-extra-300s-60"]["price_observations"] = []
        dossier = next(row for row in build_runtime._build_dossiers(changed) if row["aircraft_id"] == "gp-extra-300s-60")
        self.assertFalse(dossier["complete"])
        self.assertTrue(any("No replacement price" in reason for reason in dossier["missing"]))
        document = copy.deepcopy(self.document)
        next(row for row in document["aircraft"] if row["aircraft_id"] == "gp-extra-300s-60")["complete"] = True
        with self.assertRaisesRegex(build_runtime.ContractError, "missing prices"):
            build_runtime.validate_runtime_document(document, self.context)

    def test_variant_groups_replace_donor_parts_once(self) -> None:
        base = {row["id"]: row for row in self.dossiers["jensen-das-ugly-stik-60"]["components"]}
        cases = {
            "stik-glow-55ax-2t": ("os-max55ax-osmg0557", "apc-lp12070"),
            "stik-glow-fs64v-4t": ("os-fs64v-osmg901", "ma-k14x6"),
        }
        for aircraft_id, (engine_offer, prop_offer) in cases.items():
            with self.subTest(aircraft_id=aircraft_id):
                dossier = self.dossiers[aircraft_id]
                parts = {row["id"]: row for row in dossier["components"]}
                self.assertTrue(dossier["complete"])
                self.assertFalse(dossier["missing"])
                self.assertEqual(len(parts), 9)
                self.assertEqual(parts["engine_and_muffler"]["offer_id"], engine_offer)
                self.assertEqual(parts["propeller"]["offer_id"], prop_offer)
                self.assertEqual(parts["propeller"]["unit_minor"], self.context["offer_by_id"][prop_offer]["amount_minor"])
                for component_id in base.keys() - {"engine_and_muffler", "propeller"}:
                    self.assertEqual(parts[component_id], base[component_id])
                self.assertEqual(dossier["contact_components"], STIK_CONTACTS)
                self.assertEqual(parts["engine_and_muffler"]["physical_inventory_ids"], ["item_engine_main", "item_muffler_main"])

    def test_variant_identity_guards_refuse_unreviewed_hardware(self) -> None:
        aircraft_id = "stik-glow-55ax-2t"
        for item_id, field in [("item_engine_main", "name"), ("item_propeller_main", "mass"),
                               ("item_muffler_main", "position"), ("item_wing_airframe", "name")]:
            with self.subTest(item_id=item_id, field=field):
                changed = copy.deepcopy(self.context)
                row = next(row for row in changed["route_sources"][aircraft_id]["source"]["inventory"] if row["id"] == item_id)
                if field == "name":
                    row["name"] = "unreviewed hardware"
                elif field == "mass":
                    row["mass"]["value"] += 0.001
                else:
                    row["position"]["value"][0] += 0.001
                with self.assertRaisesRegex(build_runtime.ContractError, "identity mismatch|unreviewed inherited"):
                    build_runtime._build_dossiers(changed)
        changed = copy.deepcopy(self.context)
        changed["route_sources"][aircraft_id]["source"]["propulsion"]["propeller"]["name"] = "unreviewed rotor"
        with self.assertRaisesRegex(build_runtime.ContractError, "expected_propulsion"):
            build_runtime._build_dossiers(changed)

    def test_variant_authoring_rejects_partial_or_duplicate_overrides(self) -> None:
        aircraft_id = "stik-glow-fs64v-4t"
        mutations = [
            lambda row: row.pop("expected_propulsion"),
            lambda row: row["expected_inventory"].pop(),
            lambda row: row["expected_inventory"].append(copy.deepcopy(row["expected_inventory"][0])),
            lambda row: row["component_overrides"].append(copy.deepcopy(row["component_overrides"][0])),
            lambda row: row["component_overrides"][0]["physical_inventory_ids"].pop(),
            lambda row: row["component_overrides"][0].update(quantity=2),
            lambda row: row["component_overrides"][0].update(price_observation="unknown-offer"),
            lambda row: row.pop("inherits"),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                changed = copy.deepcopy(self.context)
                mutate(changed["fleet"][aircraft_id])
                with self.assertRaises(build_runtime.ContractError):
                    build_runtime._build_dossiers(changed)

    def test_variant_price_refresh_keeps_physical_identity_and_baseline(self) -> None:
        changed = copy.deepcopy(self.context)
        changed["offer_by_id"]["ma-k14x6"]["amount_minor"] += 100
        dossiers = {row["aircraft_id"]: row for row in build_runtime._build_dossiers(changed)}
        aircraft_id = "stik-glow-fs64v-4t"
        before = self.dossiers[aircraft_id]
        after = dossiers[aircraft_id]
        self.assertEqual(after["source_sha256"], before["source_sha256"])
        self.assertEqual(dossiers["jensen-das-ugly-stik-60"], self.dossiers["jensen-das-ugly-stik-60"])
        self.assertEqual(next(r for r in after["components"] if r["id"] == "propeller")["unit_minor"],
                         next(r for r in before["components"] if r["id"] == "propeller")["unit_minor"] + 100)

    def test_stik_propeller_event_bindings_resolve_to_component_ids(self) -> None:
        for aircraft_id in ("jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t"):
            dossier = self.dossiers[aircraft_id]
            self.assertEqual(dossier["contact_components"], STIK_CONTACTS)
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
