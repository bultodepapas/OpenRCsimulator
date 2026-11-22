# Current-main audit reproductions

## Paused-view pixel-cost model

The sixth pass fits `T(s) = A + B*s²` to the pinned UHD 630 report's minimal-view FPS table at native and 75% scale, holding out Mobile's 67% observation. It reads the report from main `85a2475f60029a4b6b09f23f643119bceea84a45` with Git, records script/report SHA-256 values, and writes the exact rows, coefficients, range-endpoint sensitivity and illustrative 240 Hz arithmetic. It uses only the Python standard library and Git:

```sh
python3 research/performance/graphics-audit-2026-11-22/reproduce_pixel_model.py \
  --out tmp/graphics-audit-2026-11-22/pixel-model-fresh.json
```

The output path must be new. `--repo /absolute/path/to/checkout` selects the source repository; it must contain the pinned `85a2475f60029a4b6b09f23f643119bceea84a45` main Git object (fetch main if using a single-branch clone). A clone containing only the divergent audit-branch history cannot read the pinned report until that object is available. This is offline arithmetic over retained rounded summaries, not an engine launch, application test or new benchmark. The source profile is paused, with **RC track Off**. The intercept is not measured CPU time; endpoint sensitivity is not a statistical interval; the withheld observation is not independent replication. Nominal squared scales do not establish actual rounded internal dimensions. See [sixth-pass analysis](../../../docs/research/graphics-audit-2026-11-22/sixth-pass.md) and [retained receipt](../../../docs/research/graphics-audit-2026-11-22/sixth-pass-pixel-model.json).

## Solver-source pin witness

`reproduce_solver_pin.py` translates the pinned production `canonical_solver_identity` over sorted ASCII `res://` paths and UTF-8 source with LF normalization. It selects only `.gd` Git blobs under physics/sim/failures; it does not materialize assets, launch Godot or qualify a tape. Two accepted 203-source snapshots are controls; `ee46d96b` demonstrates the subsequent pin mismatch.

```sh
python3 research/performance/graphics-audit-2026-11-22/reproduce_solver_pin.py \
  --out tmp/graphics-audit-2026-11-22/solver-pin-fresh.json
```

The output must be new. The selected `--repo` must contain all three pinned Git commits named in the script; fetch main and graphics-audit histories as necessary. The receipt records full computed/stored identities and loader, script and configuration identities. A successful witness means the expected matches/mismatch were reproduced; it does not approve replacing the stale pin. See [I01 and its qualification boundary](../../../docs/research/graphics-audit-2026-11-22/sixth-pass.md#i01--later-presentation-refactor-leaves-the-older-companion-solver-pin) and [retained receipt](../../../docs/research/graphics-audit-2026-11-22/sixth-pass-solver-pin.json).

## Phase/focus witness

This source-bound witness exercises the existing GOD TEST reducer with synthetic frame packets. It reproduces two phase-attribution counterexamples and checks four focus receipts, including an existing later-loss rejection. It does not run Godot, touch an interactive desktop, submit a shared-host job, or benchmark FPS.

Run from a checkout containing the audited main and the prior audit history, using the Python dependencies required by the [GOD TEST tool](../../../tools/godtest/README.md):

```sh
python3 research/performance/graphics-audit-2026-11-22/reproduce_phase_focus.py \
  --out tmp/graphics-audit-2026-11-22/phase-focus-fresh.json
```

The output path must be new. `--repo /absolute/path/to/checkout` can explicitly select the source checkout. The script refuses if the listed reducer, fixture-helper or driver bytes differ from `7940a4081e10994f34c858c4acac3d7a1a271464`. It creates temporary fixture packets, calls the unmodified production reducer, writes a compact JSON receipt and cleans up the packets. Output timestamps and draw/focus values are fabricated test inputs; expected distributions are computed from exactly aligned selection intervals.

The final retained result is [phase-focus-evidence.json](../../../docs/research/graphics-audit-2026-11-22/phase-focus-evidence.json). Its probe hash must match the script. See [measurement-integrity.md](../../../docs/research/graphics-audit-2026-11-22/measurement-integrity.md) for source paths, arithmetic, controls, limitations and the required physical-host follow-up.

This reproducer is a dated audit artifact, not a replacement for the owning GOD TEST regression suite. No application optimization or measurement repair is implemented by this branch.

## Nitro numeric rig sampler

The fourth pass adds an isolated four-arm comparison of the pinned Nitro numeric sampler, a packed-typed transform helper, shared coordinate preparation, and their combination. It uses real pinned rig bytes and 186 synthetic finite authored input sets; no GLB or full application is imported. See the [experiment report](../../../docs/research/graphics-audit-2026-11-22/rig-sampler-experiment.md) and [raw evidence](../../../docs/research/graphics-audit-2026-11-22/rig-sampler-evidence.json) for scope, results, source hashes and the retained preliminary harness failure.

On an unenrolled Linux x86_64 environment with the exact official Godot `4.8.beta2.official.cafc17a19` binary, or an appropriately admitted performance attempt:

```sh
python3 research/performance/graphics-audit-2026-11-22/reproduce_rig_sampler.py \
  --out tmp/graphics-audit-2026-11-22/rig-sampler-fresh \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64
```

The output directory must be new or empty. The script verifies the pinned engine hash, extracts source and assets from Git at `7940a408`, checks the actual binary against its manifest, isolates XDG state and uses `tools/godot/run_checked.py` for a checked import and component run. It refuses an enrolled or pool-configured performance launch without inherited performance admission. Use the repository's existing performance admission route on shared hosts; the reproducer neither creates a lease nor submits a pool job.

The four original declarations/bodies are unchanged apart from trailing separator whitespace. Experimental alternatives exist only in the disposable fixture. The script retains manifests, raw blocks, byte parity, engine diagnostics and before/after identity checks. Timing measures the 209-track numeric batch, including candidate per-batch coordinate preparation, dispatch and checksum consumption. It is not full visual parity, native vehicle qualification, GPU timing or FPS. Valid pinned metadata is the candidate's only qualified input domain; live scene mutation/reentry and fallback behavior need separate production tests.
