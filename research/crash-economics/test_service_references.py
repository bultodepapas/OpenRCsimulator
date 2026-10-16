"""Service crosswalk integrity without inferring an installed-aircraft repair."""
import copy
import unittest

import build_catalog
import build_runtime
import audit_prices


class ServiceReferenceTests(unittest.TestCase):
    def setUp(self):
        self.records = [{"id": "whole"}, {"id": "case", "whole_unit_reference": "whole",
            "service_compatibility": {"target_model": "Example servo", "status": "Named service reference",
                                      "manufacturer_source_url": "https://example.org/model"}}]

    def test_reference_is_detached_and_never_grants_aircraft_applicability(self):
        before = copy.deepcopy(self.records)
        rows = build_catalog.service_relationships(self.records)
        self.assertEqual(rows[0]["whole_unit_offer_id"], "whole")
        self.assertEqual(rows[0]["aircraft_applicability"], "not_established")
        self.assertFalse(rows[0]["automatic_repair_selection"])
        rows[0]["compatibility_evidence"]["target_model"] = "changed"
        self.assertEqual(self.records, before)

    def test_unknown_self_and_service_to_service_references_fail(self):
        for reference in [None, "missing", "case"]:
            with self.subTest(reference=reference):
                changed = copy.deepcopy(self.records)
                changed[1]["whole_unit_reference"] = reference
                with self.assertRaises(ValueError):
                    build_catalog.service_relationships(changed)
        self.records.append({"id": "screw", "whole_unit_reference": "case", "service_compatibility": self.records[1]["service_compatibility"]})
        with self.assertRaisesRegex(ValueError, "cannot be its whole-unit"):
            build_catalog.service_relationships(self.records)

    def test_missing_crosswalk_pair_and_unknown_evidence_keys_fail(self):
        for removed in ["whole_unit_reference", "service_compatibility"]:
            changed = copy.deepcopy(self.records)
            del changed[1][removed]
            with self.assertRaises(ValueError):
                build_catalog.service_relationships(changed)
        self.records[1]["service_compatibility"]["airworthy"] = "yes"
        with self.assertRaisesRegex(ValueError, "evidence fields"):
            build_catalog.service_relationships(self.records)

    def test_source_evidence_is_required_and_bounded(self):
        for bad in ["http://example.org/model", "javascript:alert(1)", "", "x" * 2049, {}, None]:
            changed = copy.deepcopy(self.records)
            changed[1]["service_compatibility"]["manufacturer_source_url"] = bad
            with self.subTest(bad=str(bad)[:25]), self.assertRaises(ValueError):
                build_catalog.service_relationships(changed)
        del self.records[1]["service_compatibility"]["manufacturer_source_url"]
        with self.assertRaisesRegex(ValueError, "source URL"):
            build_catalog.service_relationships(self.records)

    def test_duplicate_identity_fails(self):
        self.records.append({"id": "whole"})
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            build_catalog.service_relationships(self.records)

    def test_real_service_catalog_survives_generation_and_audit_without_bom_additions(self):
        document, context = build_runtime.build_runtime_data()
        result = audit_prices.build_audit(document, context, "2026-10-16")
        parts = result["service_parts"]
        self.assertEqual(len(parts), 5)
        selected = {row["offer_id"] for aircraft in document["aircraft"] for row in aircraft["components"]}
        for row in parts:
            self.assertNotIn(row["part_offer_id"], selected)
            self.assertIn(row["whole_unit_offer_id"], context["offer_by_id"])
        self.assertIn("cannot transfer mechanical fit", audit_prices.render_markdown(result))
        result["service_parts"][0]["compatibility_evidence"]["status"] = "changed"
        self.assertNotEqual(result["service_parts"], context["price_catalog"]["service_parts"])

    def test_runtime_generation_rejects_changed_or_missing_generated_crosswalks(self):
        catalog = build_catalog.read(build_catalog.HERE / "catalog.json")
        for defect in ["missing", "changed_target", "changed_reference"]:
            changed = copy.deepcopy(catalog)
            if defect == "missing":
                del changed["service_parts"]
            elif defect == "changed_target":
                changed["service_parts"][0]["compatibility_evidence"]["target_model"] = "Any engine"
            else:
                changed["service_parts"][0]["whole_unit_offer_id"] = "unrelated"
            with self.subTest(defect=defect), self.assertRaisesRegex(build_runtime.ContractError, "service references are stale"):
                build_runtime._validate_service_references(build_runtime.ROOT, changed)


if __name__ == "__main__":
    unittest.main()
