# D1-R4 — Stall-envelope boundary verification

2026-10-08 · Offline verification tools for the loader's solved-envelope boundary. [Results and limits](../../../docs/research/aircraft-validation/D1-R4/README.md).

```sh
python3 research/aircraft-data/d1-r4/verify.py --output /tmp/d1-r4-proof
```

Use a new, empty output directory. The runner selects the pinned engine through `app/get-godot.sh`, isolates user settings, rejects engine errors and records input/evidence SHA-256 hashes. It runs the app regression, reproduces the old acceptance bug, compares 48 complete fleet load results and tests solver faults on temporary script copies. Production files are never mutated.

`reference_envelope.txt` freezes only the original `_envelope()` function from the pre-D1-R4 loader (including DATA-2a). The runner substitutes this boundary into a copy of the current loader; solver, metadata and unrelated validation stay identical. `probe.gd` exercises finite lift slopes; `fault_probe.gd` verifies refusal of every fleet model after deliberate solver corruption. The focused application test is `app/tests/test_envelope_integrity.gd`; normal app checks discover it automatically.

Timings are alternating warm loader calls, not startup benchmarks. The proof checks exact result equality, not performance acceptance. This is model-domain verification, not independent aerodynamic calibration.
