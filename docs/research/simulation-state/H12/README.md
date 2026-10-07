# H12 — Allocation-free local-strip aerodynamics

2026-10-07 · **Status: implemented; bit-exact; Gate P still unmet (P-51 powered trim/stall).** Main-line ROADMAP Phase H.

## Why

The [Gate P](../Gate-P/README.md) profiles showed that every aircraft spends 64–69 µs per load evaluation in `Aero._local_loads` whenever flow leaves the attached oracle (stall, spin, high-α falls). RK4 evaluates loads four times per tick, so this one path cost ~260 µs/tick, more than half the 500 µs budget. It evaluates only 8 surfaces (6 wing stations, 2 tails). The cost was GDScript overhead, not arithmetic: per surface about 20 helper calls, 5 `PackedFloat64Array` allocations and 15 dictionary lookups. H3 had removed the same pattern from `RB.derivative` (21.2 → 2.8 µs).

## Change

`Aero._local_loads` is now written in scalars. Dictionary values are read once per call. Flow, force and moment are computed inline, and loads are summed in six accumulators. Every product and sum keeps the vector form's order. This includes the `+ 0.0` in the wing arm, which turns `-0.0` into `+0.0`. All transcendental calls still go through `math3d` (the H6 guard passes). A surface with zero flow is skipped: the old form added `+0.0` to sums that start at `+0.0`, and such a sum can never become `-0.0`. The unused `_add_load` helper was removed. The tail-increment helpers used by slipstream are unchanged.

The previous implementation is frozen verbatim, with its own copies of every helper, as `local_loads` in [`aero_flow_reference.gd`](../../../../app/tests/aero_flow_reference.gd).

## Proof

- **Byte-exact oracle:** [`test_aero_flow.gd`](../../../../app/tests/test_aero_flow.gd) compares all six load components byte for byte on 10,000 seeded cases (2,500 per aircraft). The cases include 7,305 beyond stall onset, 2,000 exact zero-flow cases, reverse flow and sideslip, rates up to 6 rad/s, random controls, and live CG and tail-position edits. Station incidence is exercised by the P-51 and Avanti. Result: 0 failures. A one-ulp comparator self-check and a coverage floor prevent a vacuous pass.
- **Mutation check:** on a scratch copy, reassociating a single product (`lift_q*(plane_speed*plane_speed)*…`) fails 5,201 of 10,001 comparisons.
- **Trajectories:** 64/64 960-tick fingerprints (4 aircraft × 4 regimes × 4 runs) match the Gate P `oracle-1` hashes recorded at `fe26ef0`, for both the unchanged and the H12 tree.
- **Full suite:** `app/test.sh` exits 0: all goldens replay unchanged (none re-recorded), and the trimmed real-app flight and the 30/60/144 fps independence check pass. [Summary](results/suite-summary.log).

## Cost on the target

Owner-confirmed target: Linux KVM, Intel i5-10500, 12 logical CPUs, Godot 4.7.2 official. [`bench_regimes.gd`](../../../../app/tests/bench_regimes.gd) was run four times in sequence: unchanged HEAD (a `git archive` copy), H12, H12, then HEAD again. No other test engine ran. The same pre-existing xvfb capture renderer documented in Gate P kept one core busy throughout. Values are µs/tick, run 1 / run 2; the p95 is over 16 batch averages of 120 ticks. **Bold** exceeds 500. Raw: [before 1](results/base-1.json), [H12 1](results/h12-1.json), [H12 2](results/h12-2.json), [before 2](results/base-2.json).

| Aircraft / fixture | Before median | H12 median | Before batch p95 | H12 batch p95 | `_local_loads` µs/call |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ugly Stik / trim | 281.9 / 288.5 | 295.4 / 328.3 | 323.4 / 383.3 | 384.3 / 415.2 | 64.2/62.1 → 22.0/21.1 |
| Ugly Stik / stall | 353.8 / 347.0 | 309.7 / 327.2 | 387.4 / 463.1 | 388.0 / 434.1 | 72.0/66.8 → 23.4/22.0 |
| Ugly Stik / spin | 444.3 / 420.8 | 247.5 / 252.3 | **520.9** / **502.9** | 375.6 / 298.9 | 67.5/66.2 → 23.5/22.8 |
| Ugly Stik / ground | 330.4 / 319.6 | 343.2 / 335.4 | **546.6** / 338.7 | 397.8 / 411.2 | 63.3/63.6 → 29.2/19.9 |
| Extra 300S / trim | 309.2 / 280.4 | 296.9 / 288.6 | 319.3 / 342.2 | 341.5 / 328.5 | 68.0/65.2 → 20.0/19.8 |
| Extra 300S / stall | 348.6 / 350.5 | 311.2 / 330.2 | 392.6 / 406.2 | 354.1 / 483.4 | 70.6/64.3 → 23.8/20.9 |
| Extra 300S / spin | 439.2 / 434.9 | 254.7 / 271.2 | 482.0 / 467.2 | 305.4 / 385.1 | 72.0/70.7 → 21.9/20.8 |
| Extra 300S / ground | 459.6 / 432.5 | 242.3 / 236.5 | **559.6** / **538.8** | 302.2 / 322.2 | 74.9/62.1 → 18.2/21.8 |
| P-51D / trim | **858.1** / **763.3** | **780.0** / **841.3** | **969.7** / **974.1** | **890.6** / **958.6** | 68.4/62.3 → 19.9/19.6 |
| P-51D / stall | **940.1** / **853.9** | **798.5** / **801.7** | **1147.7** / **1037.0** | **989.6** / **913.7** | 74.8/66.6 → 21.2/21.8 |
| P-51D / spin | 457.8 / 447.1 | 276.1 / 244.2 | **626.5** / **549.7** | 342.0 / 346.6 | 67.5/64.7 → 21.8/22.7 |
| P-51D / ground | **525.4** / 478.5 | 355.3 / 322.0 | **583.2** / **543.2** | 489.2 / 388.4 | 62.3/63.5 → 20.6/20.7 |
| Avanti S / trim | 334.5 / 323.1 | 351.0 / 346.1 | 384.6 / 350.7 | 378.5 / 444.2 | 68.8/64.3 → 20.7/19.4 |
| Avanti S / stall | 435.4 / 410.7 | 345.0 / 324.6 | **500.7** / **538.1** | 492.2 / **500.8** | 72.8/67.7 → 22.9/23.8 |
| Avanti S / spin | 478.0 / 426.1 | 269.8 / 236.4 | **526.4** / **536.5** | 363.5 / 312.2 | 75.4/67.5 → 23.6/20.5 |
| Avanti S / ground | 458.3 / 445.4 | 232.2 / 231.3 | **543.9** / **564.9** | 280.6 / 273.4 | 68.0/64.2 → 20.9/20.4 |

## Reading

- The local path is about 3× cheaper: 62–75 → 18–29 µs per call.
- Fixtures that stay in local flow gain the most. Spin falls 38–45% for every aircraft. The gearless Extra and Avanti "ground" fixtures fall 45–49%: they drop through high α, so they are not ground handling. P-51 ground falls about 32%.
- The stall fixture gains less (Stik/Extra 6–12%, Avanti 16–21%). It starts at α 15° and recovers toward attached flow within the batch, so not every tick uses the local path. The trim fixture never leaves the attached oracle, so its differences are host noise; the two HEAD runs differ by up to 95 µs.
- Outside the P-51's powered fixtures, the only remaining overrun is Avanti stall at 500.8 µs, a batch p95 within 1 µs of the budget. Before H12, 15 batch-p95 values in 8 such fixtures exceeded 500.
- **Gate P remains unmet.** P-51 powered trim and stall stay at 780–841 µs/tick in GDScript. Their cost is the tail-slipstream path (about 93 µs per evaluation in GDScript, about 19 µs native) plus propulsion (about 20 µs). H12 and the native slipstream experiment have not been measured together: the native runner clones committed HEAD. Do not add their savings arithmetically.

## Next

1. Commit H12, then rerun `research/native-slipstream/run.py` so native slipstream is measured on top of H12.
2. H13: apply the same scalar, allocation-free, bit-exact treatment to the GDScript slipstream path (`Slipstream.loads`, `Aero.tail_surface_increment`, immersion), with a frozen oracle. If it approaches the native cost, Gate P may close without a production native dependency or the three-platform build burden.
3. The suite now takes about 10 minutes on this host, not the "~45 s" in AGENTS.md. Both runs shared the host with the capture renderer; a separate measurement should locate the cost.
