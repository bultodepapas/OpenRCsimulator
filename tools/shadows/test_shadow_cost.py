"""Unit checks for the shadow cost matrix summary (no engine): python -m unittest tools.shadows.test_shadow_cost -v"""
from __future__ import annotations

import unittest

from tools.shadows import shadow_cost


def run(technique: str, median: float, repeat: int, offscreen: float = 0.0, view: str = "aircraftground") -> dict:
    return {"ok": True, "profile": "high", "renderer": "forward_plus", "gpu_name": "test", "technique": technique,
            "view": view, "width": 1920, "repeat": repeat, "gpu_median_ms": median, "gpu_p95_ms": median + 0.1,
            "counters": {"draw_calls": 10},
            "subviewports": {"World/AircraftShadow/ProjectedShadow/Silhouette256":
                             {"size": [256, 256], "gpu_ms_median": offscreen, "gpu_ms_max": offscreen,
                              "update_modes": {"1": 5}}}}


class SummaryTest(unittest.TestCase):
    def test_delta_against_off_uses_the_median_of_run_medians(self) -> None:
        rows = shadow_cost.summarize([run("off", 1.0, 0), run("off", 1.2, 1), run("off", 1.1, 2),
                                      run("projected", 1.3, 0, 0.06), run("projected", 1.2, 1, 0.05),
                                      run("projected", 1.6, 2, 0.07)])
        by_technique = {row["technique"]: row for row in rows}
        self.assertAlmostEqual(by_technique["off"]["gpu_median_ms"], 1.1)
        self.assertAlmostEqual(by_technique["projected"]["gpu_median_ms"], 1.3)
        self.assertAlmostEqual(by_technique["projected"]["delta_vs_off_ms"], 0.2)
        self.assertAlmostEqual(by_technique["projected"]["gpu_median_spread_ms"], 0.4)

    def test_offscreen_passes_that_never_redrew_are_not_listed(self) -> None:
        rows = shadow_cost.summarize([run("off", 1.0, 0), run("projected", 1.2, 0, 0.06)])
        by_technique = {row["technique"]: row for row in rows}
        self.assertEqual(by_technique["off"]["offscreen_gpu_ms"], {})
        self.assertEqual(list(by_technique["projected"]["offscreen_gpu_ms"].values()), [0.06])

    def test_failed_runs_and_missing_baselines_are_explicit(self) -> None:
        rows = shadow_cost.summarize([{"ok": False, "label": "x"}, run("native", 1.4, 0)])
        self.assertEqual(len(rows), 1)
        self.assertIsNone(rows[0]["delta_vs_off_ms"])
        self.assertIn("—", shadow_cost.markdown(rows, {"gpu": "test", "runs": 2, "repeats": 1, "seconds": 8}))

    def test_quantile_is_nearest_rank(self) -> None:
        self.assertEqual(shadow_cost.quantile([1.0, 2.0, 3.0, 4.0], 0.95), 4.0)
        self.assertEqual(shadow_cost.quantile([5.0], 0.5), 5.0)


if __name__ == "__main__":
    unittest.main()
