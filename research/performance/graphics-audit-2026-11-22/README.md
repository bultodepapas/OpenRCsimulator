# Current-main audit reproductions

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
