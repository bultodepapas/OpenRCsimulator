# D1-R5 verification tools

**Status:** implemented, 2026-10-08. [Evidence and limits](../../../docs/research/aircraft-validation/D1-R5/README.md).

`verify.py --baseline /path/to/pre-change-aircraft_data.gd --output /tmp/new-proof`
compares 96 complete fleet loader results, injects three final-map faults in private
loader copies, and verifies a failing control with residual acceptance removed.
Use `--loader` to test a candidate before integrating it. The output directory must
not exist. No shared source file is changed. Requires Python's standard library and
the repository's pinned Godot.

`app/tests/test_induced_integrity.gd` covers source-data refusals, supported search
boundaries, lift calibration and failed flight reloads. It runs in `app/test.sh`.
