# E0b6p — Stage-local thrust/torque experiment

2026-10-07 · **Status: reproducible experiment; candidate not adopted.**

`run.py` copies the supplied app into a temporary directory, installs baseline and candidate script resources in the same process, and compares them with alternating timing batches. It never edits the supplied app. `candidate.patch` records the proposed application change. The candidate passes the existing `[thrust, torque, J]` result from each Dynamics evaluation to propulsion and wake loads; no values survive that evaluation. Optional supplied results are a private experiment contract, not a validated public API.

`probe.gd` checks 1,216 varying load inputs and 30 flights, including all four catalog aircraft, twelve smooth-wake cases, axial transport and stopped residual wash. Each flight compares initial state plus 240 boundaries, including body, auxiliary, continuous and load arrays. Direct batches contain 64 calls; flight batches contain 24 ticks. Timings exclude comparison/hashing, checkpoint restoration and fixture setup. `mechanism.gd` runs afterward with temporary call counters, then two deliberate mutations prove that lost sharing and changed thrust are rejected. Four malformed-report probes check the Python comparator.

```sh
# Production GDScript backend:
python3 research/propwash/e0b6p/stage-sharing/run.py \
  --godot "$(app/get-godot.sh)" --output /tmp/stage-sharing-gd

# Optional research backend, built with the existing locked native toolchain:
python3 research/propwash/e0b6p/native/build.py --jobs 2
python3 research/propwash/e0b6p/stage-sharing/run.py \
  --godot "$(app/get-godot.sh)" \
  --library .tools/native-smooth-wake/libopenrc_slipstream.so \
  --output /tmp/stage-sharing-native
```

Use distinct output directories. `--project /path/to/stable/app` selects a source snapshot; `--keep-work` retains the temporary project for inspection. Retained copies contain diagnostic counters installed **after** timing; restage before measuring them again. Parse preflight, process exit status, engine-error scanning, report roster, finite values, coverage counts and matching trajectory hashes all gate success. Patch anchors fail explicitly when the source layout changes.

[Results, decision and limits](../../../../docs/research/propwash/E0b6p/stage-sharing/README.md). All code is project-owned under the repository MIT license. No new dependency, runtime configuration or aircraft data is introduced.
