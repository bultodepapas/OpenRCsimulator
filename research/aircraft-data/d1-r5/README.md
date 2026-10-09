# D1-R5 verification tools

**Status:** integrated and verified, 2026-10-09. [Current integration proof](../../../docs/research/aircraft-validation/D1-R5/integration/README.md); [earlier evidence](../../../docs/research/aircraft-validation/D1-R5/README.md) is retained.

`verify.py --baseline /path/to/pre-change-aircraft_data.gd --output /tmp/new-proof`
compares 96 complete fleet loader results, injects three final-map faults in private
loader copies, and verifies that removing residual acceptance actually allows four
incorrect all-ones maps to load. Completed pair/fault summaries are required.
Use `--loader` to test a candidate before integrating it. The output directory must
not exist. No shared source file is changed. Requires Python's standard library and
the repository's pinned Godot.

`app/tests/test_induced_integrity.gd` now supplies 168 checks of source-data refusals,
supported search boundaries, lift calibration and failed flight reloads. It runs
automatically in `app/test.sh`; the earlier 115-check source was not tracked.
