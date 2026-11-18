"""VQ-07h: the shipped GPU capability table matches its generator and stays well formed."""
import json
import re
import unittest
from pathlib import Path

try:
    from . import build_gpu_capability as build
except ImportError:  # Also support `python tools/graphics/test_build_gpu_capability.py`.
    import build_gpu_capability as build  # type: ignore[no-redef]

TABLE = Path(__file__).resolve().parents[2] / "app" / "data" / "gpu" / "capability.json"


class GpuCapabilityTableTests(unittest.TestCase):
    def test_table_is_current(self) -> None:
        self.assertEqual(TABLE.read_text(encoding="utf-8"), build.render(),
                         "run python tools/graphics/build_gpu_capability.py")

    def test_rows_are_unique_and_valid(self) -> None:
        rows = json.loads(TABLE.read_text(encoding="utf-8"))["rows"]
        ids = [row["id"] for row in rows]
        self.assertEqual(len(ids), len(set(ids)))
        for row in rows:
            re.compile(row["match"])
            self.assertIn(row["class"], {"discrete", "laptop", "integrated", "software"})
            self.assertGreaterEqual(row["rel"], 0.0)

    def test_every_row_states_provenance_and_correction(self) -> None:
        document = json.loads(TABLE.read_text(encoding="utf-8"))
        levels = set(document["provenance_levels"])
        for row in document["rows"]:
            self.assertIn(row["provenance"].split(":")[0], levels, row["id"])
            self.assertGreater(row["correction"], 0.0, row["id"])
        by_id = {row["id"]: row for row in document["rows"]}
        self.assertTrue(by_id["rtx_3090"]["provenance"].startswith("measured:"))
        self.assertTrue(by_id["apple_m1"]["provenance"].startswith("measured-circular"))
        self.assertEqual(by_id["radeon_890m"]["provenance"], "benchmark-derived")

    def test_anchor_fit_reproduces_both_measurements(self) -> None:
        anchor = json.loads(TABLE.read_text(encoding="utf-8"))["anchor"]
        for pixels, measured in ((1920 * 1080, anchor["high_gpu_ms_1080p"]), (3840 * 2160, anchor["high_gpu_ms_2160p"])):
            predicted = anchor["fixed_ms"] + anchor["ms_per_megapixel"] * pixels / 1e6
            self.assertAlmostEqual(predicted, measured, delta=0.05)


if __name__ == "__main__":
    unittest.main()
