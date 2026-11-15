"""CLI evidence contracts: an empty or ambiguous comparison cannot pass a gate."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def profile(results=None):
    return {"format": "ft-card-v5", "name": "Fixture", "results": results if results is not None else
            {"aero_sweep": {"valid": True, "metrics": {"value": 1.0}}}}


class ComparisonTests(unittest.TestCase):
    def compare(self, baseline, candidate, *arguments, manifests=None):
        with tempfile.TemporaryDirectory(prefix="ft-compare-", dir=ROOT / "tmp") as folder:
            root = Path(folder)
            for label, profiles in (("baseline", baseline), ("candidate", candidate)):
                target = root / label
                target.mkdir()
                if manifests and label in manifests:
                    (target / "run.json").write_text(json.dumps(manifests[label]))
                for name, content in profiles.items():
                    (target / name).mkdir()
                    (target / name / "profile.json").write_text(content if isinstance(content, str) else json.dumps(content), encoding="utf-8")
            report = root / "comparison.md"
            result = subprocess.run([sys.executable, str(HERE / "compare.py"), str(root / "baseline"), str(root / "candidate"),
                                     "--out", str(report), "--fail-on-change", *arguments], capture_output=True, text=True)
            return result.returncode, report.read_text() if report.exists() else result.stderr

    def test_empty_or_disjoint_aircraft_cannot_pass(self):
        for a, b in [({}, {}), ({"a": profile()}, {"b": profile()}), ({}, {"b": profile()})]:
            with self.subTest(baseline=list(a), candidate=list(b)):
                code, report = self.compare(a, b)
                self.assertEqual(code, 2)
                self.assertIn("no shared aircraft", report)

    def test_disjoint_tests_are_ineligible_even_with_shared_subset(self):
        a = profile({"one": {"valid": True}})
        b = profile({"two": {"valid": True}})
        for options in [(), ("--shared-tests",)]:
            with self.subTest(options=options):
                code, report = self.compare({"plane": a}, {"plane": b}, *options)
                self.assertEqual(code, 2)
                self.assertIn("no shared tests", report)

    def test_added_and_removed_aircraft_are_reported(self):
        for baseline, candidate in [({"plane": profile()}, {"plane": profile(), "added": profile()}),
                                    ({"plane": profile(), "removed": profile()}, {"plane": profile()})]:
            code, report = self.compare(baseline, candidate)
            self.assertEqual(code, 1)
            self.assertTrue("Added in the candidate" in report or "Missing from the candidate" in report)

    def test_baseline_scope_explicitly_reports_excluded_additions(self):
        code, report = self.compare({"plane": profile()}, {"plane": profile(), "added": profile()}, "--aircraft-scope", "baseline")
        self.assertEqual(code, 0)
        self.assertIn("Excluded candidate-only aircraft: added", report)

    def test_validity_only_and_null_results_remain_useful(self):
        for result in [{"valid": False}, {"valid": False, "skipped": True}, {"valid": True, "metrics": {"x": None}}]:
            with self.subTest(result=result):
                p = profile({"test": result})
                code, report = self.compare({"plane": p}, {"plane": p})
                self.assertEqual(code, 0)
                self.assertIn("validity/availability comparison only", report)

    def test_availability_boolean_type_and_numeric_changes_are_visible(self):
        for old, new in [(None, 0), (False, 0), (1.0, 2.0), (-1e308, 1e308), (-10 ** 308, 10 ** 308)]:
            with self.subTest(old=old, new=new):
                a = profile({"test": {"valid": True, "metrics": {"x": old}}})
                b = profile({"test": {"valid": True, "metrics": {"x": new}}})
                code, _ = self.compare({"plane": a}, {"plane": b})
                self.assertEqual(code, 1)

    def test_duplicate_case_and_missing_case_are_rejected(self):
        for table in [[{"case": "x", "value": 1}, {"case": "x", "value": 2}], [{"value": 1}]]:
            p = profile({"test": {"valid": True, "table": table}})
            code, report = self.compare({"plane": p}, {"plane": p})
            self.assertEqual(code, 2)
            self.assertIn("case", report)

    def test_duplicate_json_names_are_rejected(self):
        ambiguous = '{"format":"ft-card-v5","results":{"test":{"valid":true,"metrics":{"x":1,"x":2}}}}'
        code, report = self.compare({"plane": ambiguous}, {"plane": ambiguous})
        self.assertEqual(code, 2)
        self.assertIn("duplicate", report)

    def test_structured_field_identities_cannot_alias_across_profiles(self):
        for a, b in [({"metrics": {"wind": {"mps": 5}}}, {"metrics": {"wind.mps": 5}}),
                     ({"table": [{"case": "a", "b].c": 5}]}, {"table": [{"case": "a].b", "c": 5}]})]:
            baseline = profile({"test": dict(a, valid=True)})
            candidate = profile({"test": dict(b, valid=True)})
            code, report = self.compare({"plane": baseline}, {"plane": candidate})
            self.assertEqual(code, 1)
            self.assertIn("added/removed", report)
        p = profile({"test": {"valid": True, "metrics": {"a.b": 1, "a": {"b": 2}}}})
        code, report = self.compare({"plane": p}, {"plane": p})
        self.assertEqual(code, 0)
        self.assertIn("2 shared value keys", report)

    def test_failed_or_inconsistent_receipts_are_ineligible(self):
        good = {"aircraft": {"plane": {"exit": 0, "script_errors": 0, "tests": 1}}}
        cases = [{"exit": "timeout", "script_errors": 0}, {"exit": 0, "script_errors": 1},
                 {"exit": 0, "script_errors": 0, "data_identity_matches": False},
                 {"exit": 0, "script_errors": 0, "tests": 40}]
        for receipt in cases:
            code, _ = self.compare({"plane": profile()}, {"plane": profile()},
                                   manifests={"baseline": good, "candidate": {"aircraft": {"plane": receipt}}})
            self.assertEqual(code, 2)
        code, report = self.compare({"plane": profile()}, {"plane": profile()}, manifests={"baseline": good, "candidate": good})
        self.assertEqual(code, 0)
        self.assertIn("Unverified provenance fields", report)

    def test_declared_aircraft_identity_must_match_directory(self):
        code, report = self.compare({"plane": profile()}, {"plane": dict(profile(), aircraft="different")})
        self.assertEqual(code, 2)
        self.assertIn("disagrees with directory", report)

    def test_malformed_and_nonfinite_profiles_are_rejected(self):
        for p in [[], {"results": []}, profile({"test": {"valid": "yes"}}),
                  profile({"test": {"valid": True, "table": {}}}),
                  profile({"test": {"valid": True, "metrics": {"x": float("nan")}}}),
                  profile({"test": {"valid": True, "metrics": {"x": 10 ** 1000}}}),
                  '{"format":"ft-card-v5","results":{"test":{"valid":true,"metrics":{"x":1e400}}}}']:
            code, _ = self.compare({"plane": p}, {"plane": p})
            self.assertEqual(code, 2)

    def test_invalid_tolerances_are_rejected(self):
        for option in ("--rel", "--abs"):
            for value in ("nan", "inf", "-1"):
                with self.subTest(option=option, value=value):
                    code, report = self.compare({"plane": profile()}, {"plane": profile()}, option, value)
                    self.assertEqual(code, 2)
                    self.assertIn("finite and nonnegative", report)

    def test_shared_tests_and_card_override_are_explicit(self):
        a = profile({"test.with.dot": {"valid": True, "metrics": {"x": 1}}})
        b = dict(a, format="ft-card-v6", results=dict(a["results"], new={"valid": True}))
        self.assertEqual(self.compare({"plane": a}, {"plane": b})[0], 2)
        code, report = self.compare({"plane": a}, {"plane": b}, "--allow-card-change", "--shared-tests")
        self.assertEqual(code, 0)
        self.assertIn("1 shared tests; 1 shared value keys", report)
        self.assertIn("new (candidate only)", report)


if __name__ == "__main__":
    unittest.main()
