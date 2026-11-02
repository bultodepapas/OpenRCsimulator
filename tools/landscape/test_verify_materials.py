"""Identity checks for current and historical landscape capture evidence."""
from pathlib import Path
import unittest
from unittest.mock import patch

from tools.landscape import verify_materials as checker


def capture(version: str, commit: str) -> dict:
    return {
        "engine": {"string": version, "hash": commit},
        "renderer": "gl_compatibility",
        "width": 1920,
        "height": 1080,
        "adapter": "fixture",
        "cases": {"fixture": {"exposure": 1.0, "draws": 10}},
    }


class EngineIdentityTests(unittest.TestCase):
    def test_current_and_explicit_historical_identity_both_fail_closed(self):
        for selected in ("beta1", "beta2"):
            expected = checker.ENGINE_IDENTITIES[selected]
            other = checker.ENGINE_IDENTITIES["beta1" if selected == "beta2" else "beta2"]
            with self.subTest(selected=selected):
                checks = []
                checker._check_capture_identity(checks, "capture", capture(*expected), expected)
                self.assertTrue(all(item["passed"] for item in checks))
                for actual in (other, (expected[0], "0" * 40)):
                    checks = []
                    checker._check_capture_identity(checks, "capture", capture(*actual), expected)
                    self.assertFalse(checks[0]["passed"])

    def test_mixed_engine_capture_pair_is_rejected(self):
        checks = []
        checker._check_reports_matched(checks, "pair", capture(*checker.ENGINE_IDENTITIES["beta1"]),
                                       capture(*checker.ENGINE_IDENTITIES["beta2"]), ("fixture",))
        self.assertFalse(checks[0]["passed"])

    def test_default_and_historical_selection_reach_both_checks(self):
        seen = []

        def check_group(root, checks, engine_identity):
            seen.append(engine_identity)
            checks.append({"passed": True})
            return {}

        with patch.object(checker, "_check_day_materials", side_effect=check_group), \
                patch.object(checker, "_check_twilight", side_effect=check_group):
            current = checker.verify(Path("fixture"))
            historical = checker.verify(Path("fixture"), "beta1")
        self.assertEqual(seen, [checker.ENGINE_IDENTITIES["beta2"]] * 2
                         + [checker.ENGINE_IDENTITIES["beta1"]] * 2)
        self.assertEqual(current["engine_pin"]["selection"], "beta2")
        self.assertEqual(historical["engine_pin"]["selection"], "beta1")
        with self.assertRaises(ValueError):
            checker.verify(Path("fixture"), "unknown")


if __name__ == "__main__":
    unittest.main()
