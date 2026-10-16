"""Snapshot price deltas must retain package scope and historical evidence."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import compare_prices


def snapshot():
    return {"format": "openrc-price-review v1", "currency": "USD", "as_of": "2026-10-16",
        "observations": [{"offer_id": "one", "brand": "Example", "sku": "S-1", "product": "Servo",
            "currency": "USD", "package_description": "One servo", "source_url": "https://example.org/servo",
            "observed_on": "2026-10-15", "availability_at_observation": "In stock", "amount_minor": 3399,
            "price_kind": "unit_price", "condition": "new_listing", "market": "USD storefront", "tax_shipping": "Excluded",
            "uses": [{"aircraft_id": "stik", "component_id": "servos", "role": "unit_price",
                      "installed_quantity": 4, "quantity_per_component_unit": 1}]}]}


class PriceComparisonTests(unittest.TestCase):
    def test_signed_delta_is_per_package_and_inputs_are_detached(self):
        before = snapshot()
        after = copy.deepcopy(before)
        after["observations"][0]["amount_minor"] = 2999
        unchanged = copy.deepcopy((before, after))
        result = compare_prices.compare(before, after)
        self.assertEqual(result["changes"][0]["price_delta_minor"], -400)
        self.assertEqual(result["changes"][0]["change"], "price_changed")
        self.assertEqual((before, after), unchanged)
        result["changes"][0]["before"]["uses"][0]["installed_quantity"] = 99
        self.assertEqual(before["observations"][0]["uses"][0]["installed_quantity"], 4)
        self.assertIn("-4.00", compare_prices.render_markdown(result))

    def test_added_and_removed_are_never_zero_price_comparisons(self):
        before, after = snapshot(), snapshot()
        after["observations"][0]["offer_id"] = "new"
        rows = compare_prices.compare(before, after)["changes"]
        self.assertEqual({row["change"] for row in rows}, {"added", "removed"})
        self.assertTrue(all(row["price_delta_minor"] is None for row in rows))
        self.assertFalse(any(row["same_offer_price_comparable"] for row in rows))

    def test_product_package_or_seller_changes_block_a_price_delta(self):
        for field in ("brand", "sku", "product", "package_description", "source_url"):
            before, after = snapshot(), snapshot()
            after["observations"][0][field] += " changed"
            after["observations"][0]["amount_minor"] = 100
            with self.subTest(field=field):
                row = compare_prices.compare(before, after)["changes"][0]
                self.assertEqual(row["change"], "terms_changed")
                self.assertIsNone(row["price_delta_minor"])

    def test_availability_and_date_refresh_are_explicit_without_claiming_stock(self):
        before, after = snapshot(), snapshot()
        after["observations"][0].update(observed_on="2026-10-16", availability_at_observation="Sold out")
        row = compare_prices.compare(before, after)["changes"][0]
        self.assertEqual(row["change"], "evidence_changed")
        self.assertEqual(row["price_delta_minor"], 0)
        self.assertEqual(row["before"]["availability_at_observation"], "In stock")
        self.assertEqual(row["after"]["availability_at_observation"], "Sold out")

    def test_future_and_regressing_observation_dates_block_comparison(self):
        for date in ("2026-10-14", "2026-10-17"):
            before, after = snapshot(), snapshot()
            after["observations"][0]["observed_on"] = date
            self.assertIsNone(compare_prices.compare(before, after)["changes"][0]["price_delta_minor"])
        before, after = snapshot(), snapshot()
        after["as_of"] = "2026-10-15"
        with self.assertRaisesRegex(ValueError, "precedes"):
            compare_prices.compare(before, after)

    def test_aging_alone_and_input_order_do_not_create_price_changes(self):
        before, after = snapshot(), snapshot()
        after["as_of"] = "2027-10-16"
        after["observations"][0]["review_status"] = "stale"
        result = compare_prices.compare(before, after)
        self.assertEqual(result["summary"]["unchanged_offers"], 1)
        self.assertEqual(result["changes"], [])
        self.assertIn("No offer", compare_prices.render_markdown(result))

    def test_reference_reallocation_is_not_hidden_by_unchanged_prices(self):
        before, after = snapshot(), snapshot()
        after["observations"][0]["uses"][0].update(role="reference_only", quantity_per_component_unit=None)
        row = compare_prices.compare(before, after)["changes"][0]
        self.assertEqual(row["change"], "allocation_changed")
        self.assertEqual(row["price_delta_minor"], 0)
        self.assertEqual(row["after"]["uses"][0]["role"], "reference_only")

    def test_invalid_amounts_currency_ids_and_use_quantities_are_rejected(self):
        for amount in (None, True, 0.5, -1, float("nan"), 9000000000000001):
            bad = snapshot()
            bad["observations"][0]["amount_minor"] = amount
            with self.subTest(amount=amount), self.assertRaises(ValueError):
                compare_prices.compare(snapshot(), bad)
        bad = snapshot()
        bad["observations"].append(copy.deepcopy(bad["observations"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate offer"):
            compare_prices.compare(snapshot(), bad)
        for field, value in (("currency", "EUR"), ("sku", "")):
            bad = snapshot()
            bad["observations"][0][field] = value
            with self.assertRaises(ValueError):
                compare_prices.compare(snapshot(), bad)
        for quantity in (None, False, 0, 1.5):
            bad = snapshot()
            bad["observations"][0]["uses"][0]["installed_quantity"] = quantity
            with self.assertRaises(ValueError):
                compare_prices.compare(snapshot(), bad)

    def test_known_zero_price_is_valid(self):
        before, after = snapshot(), snapshot()
        before["observations"][0]["amount_minor"] = 0
        self.assertEqual(compare_prices.compare(before, after)["changes"][0]["price_delta_minor"], 3399)

    def test_sale_condition_and_missing_legacy_terms_prevent_false_price_deltas(self):
        for field in compare_prices.COMMERCIAL:
            before, after = snapshot(), snapshot()
            after["observations"][0][field] += " changed"
            self.assertIsNone(compare_prices.compare(before, after)["changes"][0]["price_delta_minor"])
            before["observations"][0].pop(field)
            self.assertEqual(compare_prices.compare(before, after)["changes"], [])
            after["observations"][0]["amount_minor"] = 1999
            self.assertIsNone(compare_prices.compare(before, after)["changes"][0]["price_delta_minor"])

    def test_cli_preserves_inputs_and_refuses_output_collisions(self):
        with tempfile.TemporaryDirectory() as folder:
            before, after, output = [Path(folder) / name for name in ("before.json", "after.json", "changes.json")]
            before.write_text(json.dumps(snapshot()), encoding="utf-8")
            after.write_bytes(before.read_bytes())
            original = before.read_bytes()
            self.assertEqual(compare_prices.main(["--before", str(before), "--after", str(after), "--out", str(output)]), 0)
            self.assertEqual(before.read_bytes(), original)
            self.assertEqual(json.loads(output.read_text())["summary"]["changed_offers"], 0)
            self.assertTrue(output.with_suffix(".md").exists())
            compare_prices.validate_output(output, [before, after])
            for destination in (before, after, output.with_suffix(".md")):
                with self.assertRaises(ValueError):
                    compare_prices.validate_output(destination, [before, after])
            output.write_text('{"format":"unrelated"}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "unrelated"):
                compare_prices.validate_output(output, [before, after])

    def test_reader_rejects_duplicate_keys_and_nonfinite_json(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "bad.json"
            for value in ('{"a":1,"a":2}', '{"a":NaN}'):
                path.write_text(value, encoding="utf-8")
                with self.assertRaises(ValueError):
                    compare_prices.read_snapshot(path)

    def test_historical_review_is_accepted_without_rewriting_it(self):
        path = Path(__file__).resolve().parents[2] / "docs/research/crash-damage-investigations/CR-31g/price-review-2026-10-16.json"
        before = path.read_bytes()
        document, digest = compare_prices.read_snapshot(path)
        result = compare_prices.compare(document, document)
        self.assertEqual(result["summary"]["before_offers"], 71)
        self.assertEqual(result["changes"], [])
        self.assertEqual(len(digest), 64)
        self.assertEqual(before, path.read_bytes())


if __name__ == "__main__":
    unittest.main()
