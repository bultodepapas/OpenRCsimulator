# DR-03 reference oracles

`reference_oracles.py` is the standard-library Python reference harness embedded in [FPV/06 §E.4](../../../FPV/06_SOURCE_AUDIT_AND_EVIDENCE.md#e4-numerical-reference-suite), extracted byte for byte (SHA-256 `628a33a210269feb6db17fde2422089288bd3f7e0089eb7963d6180d7a1571ae`, the hash FPV/06 records). Nothing in it was changed. Its docstring still says `python3 validation/reference_oracles.py`; that path is the original handoff's, not this folder's.

It runs 20 synthetic cases with frozen expected constants: the Betaflight 4.5.2 Actual rate curve (commit `024f8e13d4e642eb6a380308685b9ea3aa3ef1a2`, `src/main/fc/rc.c`), the quad wrench matrix and its inverse, rotor momentum and work closure, the shared four-motor bus, disc clearance, FOV conversion, zero-order-hold phase, motor Kv/Kt units and Kelvin. These are arithmetic and convention checks on synthetic fixtures. They are **not** flight validation, hardware evidence or Betaflight firmware equivalence.

## Run

From this folder:

```sh
python reference_oracles.py
```

The script writes `reference_oracles.json` next to itself and prints the same report. The retained copy is `reference_oracles_report.json`.

## Observed result (2026-11-11)

Python 3.11.9 (MSC v.1938, 64-bit) on Windows 11 10.0.26100: `Reference checks: 20/20 passed, 0 failed`, exit 0. Two consecutive runs produced byte-identical JSON and stdout.

The report is not byte-identical to the one embedded in FPV/06 §E.5 (`757183c5…`). Four `actual` values differ in the last bit or two: `wrench_forward_frd_signs` (Python 3.12+ changed `sum()` of floats to compensated summation) and two `zoh_240hz_phase_and_magnitude` magnitudes (platform `sin`/`log10`). All are within the script's 1e-10 tolerances, and every `expected` value is identical. On Windows, `Path.write_text` writes CRLF line endings; the LF content of `reference_oracles_report.json` has SHA-256 `41ee4f3a3e04d4b1cce787cb3416f9757d2cdd4065a199355842255f3421330f`.

The script hashes its own bytes into the report, so a CRLF checkout of the `.py` changes `script_sha256`.

The runtime implementation these oracles cross-check is `app/physics/multirotor/rates.gd`, tested by `app/tests/test_mr_rates.gd`.
