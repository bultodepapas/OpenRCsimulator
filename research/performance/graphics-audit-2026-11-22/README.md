# Offline phase/focus audit witness

This source-bound witness exercises the existing GOD TEST reducer with synthetic frame packets. It reproduces two phase-attribution counterexamples and checks four focus receipts, including an existing later-loss rejection. It does not run Godot, touch an interactive desktop, submit a shared-host job, or benchmark FPS.

Run from a checkout containing the audited main and the prior audit history, using the Python dependencies required by the [GOD TEST tool](../../../tools/godtest/README.md):

```sh
python3 research/performance/graphics-audit-2026-11-22/reproduce_phase_focus.py \
  --out tmp/graphics-audit-2026-11-22/phase-focus-fresh.json
```

The output path must be new. `--repo /absolute/path/to/checkout` can explicitly select the source checkout. The script refuses if the listed reducer, fixture-helper or driver bytes differ from `7940a4081e10994f34c858c4acac3d7a1a271464`. It creates temporary fixture packets, calls the unmodified production reducer, writes a compact JSON receipt and cleans up the packets. Output timestamps and draw/focus values are fabricated test inputs; expected distributions are computed from exactly aligned selection intervals.

The final retained result is [phase-focus-evidence.json](../../../docs/research/graphics-audit-2026-11-22/phase-focus-evidence.json). Its probe hash must match the script. See [measurement-integrity.md](../../../docs/research/graphics-audit-2026-11-22/measurement-integrity.md) for source paths, arithmetic, controls, limitations and the required physical-host follow-up.

This reproducer is a dated audit artifact, not a replacement for the owning GOD TEST regression suite. No application optimization or measurement repair is implemented by this branch.
