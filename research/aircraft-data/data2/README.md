# DATA-2a — Exact sampled stall-peak search

**Status:** verification tooling for the bounded aircraft-loader optimization. [Proof and limits](../../../docs/research/aircraft-validation/DATA-2a/README.md). No aircraft parameters or aerodynamic curve changes.

From the repository root:

```sh
python3 research/aircraft-data/data2/run.py --output /tmp/data2-evidence
```

Uses the pinned Godot from `app/get-godot.sh`; `--godot /path/to/binary` overrides it. The Python runner needs only the standard library. Runtime is roughly two minutes, depending on shared-host load.

The runner checks the actual production loader against `reference.gd`, a frozen copy of the old 60-bisection/801-grid implementation. It runs the focused app test, constructs a temporary old-solver loader from the current file (preserving all unrelated loader behavior), compares 12 alternating full loads per aircraft, rejects three deliberately incorrect copies, and checks 1,000 seeded envelope solves. Malformed engine runs, wrong result counts, nonzero exits and inputs changing during verification fail the run. Source mutations only exist in disposable directories.

`verification.json` records raw paired times, complete loader-result equality, source/data hashes, mutation outcomes and sweep counts. Times are wall-clock milliseconds, including parsing/validation/derivation, with warm OS file caches; no application model cache is introduced. They are not total startup or uncached-disk measurements. Timing is diagnostic and does not fail on the DATA-2 15 ms target. Preserve the raw spreads; shared-host scheduling prevents interpreting one sample as a hardware guarantee.

The focused regression lives in `app/tests/test_stall_solver.gd` and is included automatically by `app/test.sh`. The full sweep is offline to avoid adding a minute to every application test run. Both compare exact float results, stronger than the roadmap's 1e-12 rad tolerance. This proves legacy-grid equivalence, not the physical fidelity or continuous-curve peak accuracy of the original stall model.
