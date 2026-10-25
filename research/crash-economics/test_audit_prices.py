"""Price age, fleet coverage, and composite traceability regressions."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import audit_prices
import build_runtime


class PriceAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.document, cls.context = build_runtime.build_runtime_data()

    def test_review_and_stale_boundaries_are_inclusive(self):
        for as_of, expected in [("2027-01-12", "within_review_window"), ("2027-01-13", "review_due"),
                                ("2027-04-12", "review_due"), ("2027-04-13", "stale")]:
            with self.subTest(as_of=as_of):
                self.assertEqual(audit_prices.observation_age("2026-10-15", as_of, 90, 180)["review_status"], expected)

    def test_future_prices_and_leap_day_are_explicit(self):
        self.assertEqual(audit_prices.observation_age("2026-10-16", "2026-10-15", 90, 180),
                         {"age_days": -1, "review_status": "future_observation"})
        self.assertEqual(audit_prices.observation_age("2024-02-28", "2024-03-01", 90, 180)["age_days"], 2)

    def test_malformed_dates_and_policies_are_rejected(self):
        for value in ["2026-02-29", "20261016", "2026-1-1", "today", None]:
            with self.subTest(value=value), self.assertRaises((ValueError, TypeError)):
                audit_prices.observation_age("2026-10-15", value, 90, 180)
        for thresholds in [(0, 180), (90, 90), (180, 90), (True, 180), (90.0, 180)]:
            with self.subTest(thresholds=thresholds), self.assertRaises(ValueError):
                audit_prices.observation_age("2026-10-15", "2026-10-16", *thresholds)

    def test_refresh_does_not_redate_older_offers(self):
        result = audit_prices.build_audit(self.document, self.context, "2027-01-13")
        rows = {row["offer_id"]: row for row in result["observations"]}
        self.assertEqual(rows["apc-lp12060"]["review_status"], "review_due")
        self.assertEqual(rows["da_ks3086_canister_desert_aircraft_20261016"]["review_status"], "within_review_window")
        self.assertEqual(result["catalog_snapshot_date"], "2026-10-25")

    def test_unknown_aircraft_total_is_not_zero(self):
        result = audit_prices.build_audit(self.document, self.context, "2026-10-16")
        aircraft = {row["aircraft_id"]: row for row in result["aircraft"]}
        self.assertIsNone(aircraft["xcell-60-research"]["known_subtotal_minor"])
        self.assertIsNone(aircraft["p51d-mustang-120"]["modeled_inventory_total_minor"])
        self.assertGreater(aircraft["p51d-mustang-120"]["known_subtotal_minor"], 0)
        self.assertEqual(aircraft["jensen-das-ugly-stik-60"]["modeled_inventory_total_minor"], 99433)
        self.assertTrue(aircraft["jensen-das-ugly-stik-60"]["approximate_component_ids"])

    def test_composite_references_preserve_quantity_and_no_invented_offer(self):
        result = audit_prices.build_audit(self.document, self.context, "2026-10-16")
        aircraft = next(row for row in result["aircraft"] if row["aircraft_id"] == "turbo-lumber-evolution")
        wing = next(row for row in aircraft["components"] if row["id"] == "wing_main")
        servo = next(row for row in wing["references"] if "spmsa370" in row["offer_id"])
        self.assertEqual(servo["role"], "composite_constituent")
        self.assertEqual(servo["quantity_per_component_unit"], 4)
        self.assertEqual(wing["line_minor"], 11595)
        self.assertFalse(any(row["role"] == "unit_price" for row in wing["references"]))

    def test_variant_uses_its_own_engine_and_prop_prices(self):
        result = audit_prices.build_audit(self.document, self.context, "2026-10-16")
        aircraft = next(row for row in result["aircraft"] if row["aircraft_id"] == "stik-glow-fs64v-4t")
        rows = {row["id"]: row for row in aircraft["components"]}
        self.assertEqual(rows["engine_and_muffler"]["references"][0]["offer_id"], "os-fs64v-osmg901")
        self.assertEqual(rows["propeller"]["references"][0]["offer_id"], "ma-k14x6")

    def test_output_is_deterministic_and_does_not_mutate_inputs(self):
        document, context = copy.deepcopy(self.document), copy.deepcopy(self.context)
        before = json.dumps(document, sort_keys=True), repr(context)
        result = audit_prices.build_audit(document, context, "2026-10-16")
        self.assertEqual(result, audit_prices.build_audit(document, context, "2026-10-16"))
        self.assertEqual(before, (json.dumps(document, sort_keys=True), repr(context)))
        context["fleet"]["turbo-lumber-evolution"]["dossier"]["lines"][0]["reference_observation"] = "missing-offer"
        with self.assertRaisesRegex(ValueError, "Unknown authored price reference"):
            audit_prices.build_audit(document, context, "2026-10-16")

    def test_comparison_offers_are_not_silently_installed(self):
        result = audit_prices.build_audit(self.document, self.context, "2026-10-16")
        offer = next(row for row in result["observations"] if row["offer_id"] == "da120_slimline_pair_desert_aircraft_20261016")
        self.assertEqual(offer["uses"], [])
        self.assertIn("not a live stock", audit_prices.render_markdown(result))

    def test_sale_quotes_require_recheck_even_inside_the_age_window(self):
        document, context = copy.deepcopy(self.document), copy.deepcopy(self.context)
        document["offers"][0]["price_kind"] = "live_us_retailer_sale_price"
        result = audit_prices.build_audit(document, context, "2026-10-16")
        row = next(row for row in result["observations"] if row["offer_id"] == document["offers"][0]["id"])
        self.assertTrue(row["sale_recheck_required"])
        self.assertEqual(row["review_status"], "within_review_window")
        self.assertEqual(row["condition"], "new_listing")
        self.assertIn("Sale quotes requiring recheck", audit_prices.render_markdown(result))
        context["price_catalog"]["policy"]["sale_price_requires_refresh"] = False
        result = audit_prices.build_audit(document, context, "2026-10-16")
        self.assertEqual(result["summary"]["sale_observations_requiring_recheck"], 0)

    def test_output_cannot_overwrite_unrelated_json_or_markdown(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            output.write_text('{"format":"openrc-runtime-economics v1"}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Refusing"):
                audit_prices.validate_output_paths(output)
            output.unlink()
            output.with_suffix(".md").write_text("# Aircraft contract", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Refusing"):
                audit_prices.validate_output_paths(output)

    def test_repeat_report_paths_are_allowed_and_companions_stay_distinct(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            audit_prices.validate_output_paths(output)
            output.write_text('{"format":"openrc-price-review v1"}', encoding="utf-8")
            output.with_suffix(".md").write_text("# Price review queue\n", encoding="utf-8")
            audit_prices.validate_output_paths(output)
            with self.assertRaisesRegex(ValueError, "must end in .json"):
                audit_prices.validate_output_paths(output.with_suffix(".md"))


if __name__ == "__main__":
    unittest.main()
