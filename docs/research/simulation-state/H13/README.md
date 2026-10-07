# H13 — Allocation-free GDScript slipstream

2026-10-07 · **Status: implemented; bit-exact; Gate P still unmet (P-51 powered trim/stall only).** Main-line ROADMAP Phase H.

## Why

After [H12](../H12/README.md), the only fixtures over the 500 µs/tick budget were the P-51's powered trim and stall. Their extra cost is the tail-slipstream path, which cost 86–89 µs per load evaluation in GDScript. Per immersed tail piece (three on the P-51), `immersion()` built a `none` dictionary and two arrays even when they were not returned, and returned its result as a dictionary of arrays. The tail increment then ran through `M.add`/`M.cross` and two `_surface_with_flow` allocations, with about 30 dictionary lookups in all. This is the overhead pattern that H3 and H12 removed.

## Change

`Slipstream.loads` now inlines `immersion()` and `Aero.tail_surface_increment()` in scalars. Piece-independent wake, drift and tail-law values are read once per call. The free and washed tail loads are evaluated in the oracle's arithmetic, including `v + 0.0` for the free stream, the zero-flow branch (`not speed < 1e-10`, so NaN takes the oracle's branch) and the washed − free subtraction. All transcendental calls still go through `math3d`. `wake()`, `immersion()`, `Aero.tail_surface_load()` and `Aero.tail_surface_increment()` keep their public form for the benchmark. The `Slipstream` preload line and the `loads` signature are unchanged, so the Gate P native adapter still swaps in.

The previous path is frozen verbatim in [`slipstream_reference.gd`](../../../../app/tests/slipstream_reference.gd), copied from `99936a1` together with every Aero helper it reaches. It still calls the live `Propulsion.thrust_torque` and `axis`, which H13 does not change.

## Proof

- **Byte-exact oracle:** [`test_slipstream_scalar.gd`](../../../../app/tests/test_slipstream_scalar.gd) runs 10,000 seeded P-51 cases with 0 failures: 6,083 washed, 1,429 static run-ups (zero airspeed, so no drift), and 448 below `STOPPED_RPM` (each must be exactly zero). The cases also cover forward, reverse and sideslipping flow; rates up to 4 rad/s; random controls; and live CG and tail edits. A one-ulp comparator check and coverage floors prevent a vacuous pass.
- **Mutation check:** on a scratch copy, reassociating the washed-flow sum (`v0 + ((wash_0 - swirl_0) + rate_arm_0)`) fails 2,157 of 10,001 comparisons.
- **Trajectories:** 64/64 960-tick fingerprints (4 aircraft × 4 regimes × 4 runs) match the Gate P `oracle-1` hashes.
- **Full suite:** `app/test.sh` exits 0 with goldens unchanged. [Summary](results/suite-summary.log).

## Native slipstream on committed H12 (step 1 of H12's "Next")

`research/native-slipstream/run.py` was run on `99936a1` (H12 committed) with the verified library (`b7127ddf…`). It passed: 10,046 kernel checks, all trajectories, and the full native-copy suite. [Raw](results/native-on-h12/). Native P-51 trim measured 477.2 / 456.2 µs/tick and stall 509.7 / 520.2. Batch p95 values were 537.8–708.6. Every other fixture was within budget at median and batch p95.

## Cost on the target

Same host and method as H12. Four runs in sequence: HEAD `99936a1` (`git archive` copy), H13, H13, HEAD again. The xvfb capture renderer was still using one core. µs/tick, run 1 / run 2; **bold** exceeds 500. Raw: [before 1](results/base-1.json), [H13 1](results/h13-1.json), [H13 2](results/h13-2.json), [before 2](results/base-2.json).

| Aircraft / fixture | Before median | H13 median | Before batch p95 | H13 batch p95 |
| --- | ---: | ---: | ---: | ---: |
| P-51D / trim | **757.0** / **738.5** | **545.0** / **583.5** | **836.0** / **805.1** | **580.8** / **658.8** |
| P-51D / stall | **789.8** / **780.1** | **558.8** / **577.1** | **839.1** / **875.1** | **631.7** / **626.5** |
| P-51D / spin | 232.2 / 246.9 | 252.9 / 244.6 | 320.6 / 309.7 | 421.4 / 346.1 |
| P-51D / ground | 314.1 / 344.3 | 309.8 / 301.0 | 350.7 / 422.3 | 391.1 / 348.3 |

Every other aircraft and fixture stayed within budget in all four runs, at median and batch p95. Their engines are stopped or they have no slipstream data, so their differences are host noise.

Component profile at the P-51 fixtures' initial state (µs per call): `Slipstream.loads` 88.6 / 86.0 → 38.0 / 36.7 (trim / stall), about 2.3× faster; `Dynamics.loads` 159–160 → 104–113.

## Reading

- **Pure GDScript is now within about 60–90 µs/tick of native slipstream on the P-51** (trim 545–584 vs 456–477; stall 559–577 vs 510–520). The slipstream evaluation itself is 37 µs in GDScript against about 19 µs native.
- **Neither route meets Gate P for P-51 stall.** Both still exceed 500 at the stall median, or at batch p95.
- In the H13 stall fixture, one dynamics evaluation costs about 104 µs: slipstream 37, propulsion 19.6, aero 23.4, and about 24 in air data, assembly and the derivative. Four evaluations make about 420 µs/tick. The rest of the 559–577 is outside `Dynamics.loads`: pre-step shaft balance, validity guards, the Callable RK stages, `_remember_valid_state` copying seven arrays, and the `stepped` signal.

## Next (recommended)

About 80 µs/tick of identified, bounded GDScript work could close Gate P without a production native dependency or the Windows/macOS build burden:

1. **H14 — P-51 propulsion loads:** P-factor, shaft and thrust angles cost 19 µs per call, against 1–5 µs for the other aircraft. Scalarize with a frozen oracle. Compute `thrust_torque` once per evaluation and share it with slipstream, preserving the call order.
2. **H15 — step bookkeeping:** profile `Simulation.step` outside the loads for every aircraft. This is fleet-wide (about 90 µs/tick on the Stik). The H8 safety guarantees must stay: atomic rollback, checkpoints and per-stage validation.
3. Re-measure the fleet. Gate P stays open until every fixture meets the budget at median and batch p95. Keep the native experiment as a fallback if the GDScript margin proves too thin.
