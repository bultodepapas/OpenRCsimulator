"""Exercise the numerical comparator's rejection and first-divergence reporting."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("gdu04_run", Path(__file__).with_name("run.py"))
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


class NumericComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="gdu04-comparison-test-")
        self.addCleanup(self.temporary.cleanup)
        self.left = Path(self.temporary.name) / "baseline.bin"
        self.right = Path(self.temporary.name) / "candidate.bin"
        self.descriptor = {"rows": 2, "layout": [
            {"field": "state", "count": 2, "kind": "float64"},
            {"field": "modes", "count": 1, "kind": "int64"},
        ]}
        self.payload = struct.pack("<ddqddq", 1.0, -0.0, -1, 3.0, 4.0, -9223372036854775808)
        self.left.write_bytes(self.payload)
        self.right.write_bytes(self.payload)

    def compare(self):
        return RUN.compare_case(self.left, self.right, self.descriptor)

    def test_identical_full_stream_passes(self):
        self.assertTrue(self.compare()["identical"])

    def test_signed_zero_difference_is_detected(self):
        self.right.write_bytes(struct.pack("<ddqddq", 1.0, 0.0, -1, 3.0, 4.0, -9223372036854775808))
        result = self.compare()
        self.assertFalse(result["identical"])
        self.assertEqual({key: result["first_difference"][key] for key in ("tick", "field", "component")},
                         {"tick": 0, "field": "state", "component": 1})

    def test_int64_rng_divergence_reports_exact_value(self):
        self.right.write_bytes(struct.pack("<ddqddq", 1.0, -0.0, -1, 3.0, 4.0, -9223372036854775807))
        first = self.compare()["first_difference"]
        self.assertEqual((first["tick"], first["field"], first["component"], first["candidate"]),
                         (1, "modes", 0, -9223372036854775807))

    def test_incomplete_prefix_is_rejected(self):
        self.right.write_bytes(self.payload[:-8])
        with self.assertRaisesRegex(RuntimeError, "incomplete stream"):
            self.compare()


if __name__ == "__main__":
    unittest.main()
