#!/usr/bin/env python3
"""Verifier failure controls; no Godot process or production mutation is needed."""
import subprocess
import unittest
from pathlib import Path
import verify_motor as verifier


def process(output, code=0):
    return subprocess.CompletedProcess([], code, output, "")


class MotorVerifierTests(unittest.TestCase):
    def test_output_must_not_be_inside_source_app(self):
        app = Path("fixture-app").resolve()
        for output in (app, app / "results", app / "nested" / "result"):
            with self.assertRaises(verifier.VerifyError):
                verifier.verify_output_location(app, output)
        verifier.verify_output_location(app, app.parent / "results")

    def test_frozen_source_accepts_both_checkout_line_endings(self):
        lf = verifier.FROZEN_MOTOR.read_bytes().replace(b"\r\n", b"\n")
        verifier.verify_frozen_source(lf)
        verifier.verify_frozen_source(lf.replace(b"\n", b"\r\n"))

    def test_frozen_source_rejects_code_edit(self):
        with self.assertRaises(verifier.VerifyError):
            verifier.verify_frozen_source(verifier.FROZEN_MOTOR.read_bytes() + b"# changed\n")

    def test_exact_completion_count_required(self):
        count = verifier.EXPECTED_ORACLE_COMPARISONS
        for actual in (count - 1, count + 1):
            with self.assertRaises(verifier.VerifyError):
                verifier.require_clean_output(process(
                    f"EL2a-P3 motor oracle: {actual} byte comparisons, 0 failures, samples=10000"),
                    "oracle", count)
        verifier.require_clean_output(process(
            f"EL2a-P3 motor oracle: {count} byte comparisons, 0 failures, samples=10000"), "oracle", count)

    def test_engine_failure_does_not_count_as_mutation_detection(self):
        output = ("SCRIPT ERROR: Parse Error: broken\n"
                  "EL2a-P3 motor oracle: 20043 byte comparisons, 1 failures, samples=10000\n"
                  "first mismatch: fixture")
        with self.assertRaises(verifier.VerifyError):
            verifier.require_mutation_rejection(process(output, 1), "first mismatch: fixture")

    def test_mutation_requires_intended_failure_and_nonzero_exit(self):
        output = ("EL2a-P3 motor oracle: 20043 byte comparisons, 1 failures, samples=10000\n"
                  "first mismatch: intended fixture")
        verifier.require_mutation_rejection(process(output, 1), "first mismatch: intended fixture")
        for code, evidence in ((0, "intended fixture"), (1, "another fixture")):
            with self.assertRaises(verifier.VerifyError):
                verifier.require_mutation_rejection(process(output, code), evidence)

    def test_missing_completion_line_rejected(self):
        with self.assertRaises(verifier.VerifyError):
            verifier.require_clean_output(process("PASS"), "oracle", verifier.EXPECTED_ORACLE_COMPARISONS)

    def test_mutation_requires_unique_anchor_for_both_checkout_styles(self):
        for newline in (b"\n", b"\r\n"):
            self.assertEqual(verifier.replace_once(b"one" + newline, b"one\n", b"two\n", "fixture"),
                             b"two" + newline)
        for source in (b"zero\n", b"one\none\n"):
            with self.assertRaises(verifier.VerifyError):
                verifier.replace_once(source, b"one\n", b"two\n", "fixture")


if __name__ == "__main__":
    unittest.main()
