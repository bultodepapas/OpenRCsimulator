# H14 — Allocation-free tilted-shaft propulsion loads

2026-10-07 · **Status: implemented; bit-exact; Gate P still unmet (P-51 powered trim/stall, 14–41 µs/tick over at the median).** Main-line ROADMAP Phase H.

## Why

After [H13](../H13/README.md), `Propulsion.loads` cost 19–21 µs per call on the P-51, against 1–5 µs elsewhere. Its tilted shaft (down/right thrust) adds the normal force and P-factor moment. Each came from a separate `_crossflow()` call, which repeated the speed, axis projection, crossflow vector, advance ratio and `pow(D, n)`. Each call also allocated four to six `PackedFloat64Array`s, and the force and moment were assembled with `M.add`/`M.sub`/`M.cross`/`M.scale`.

## Change

The tilted-shaft branch of `Propulsion.loads` now calls `_tilted_loads()`, a scalar form that computes the shared crossflow terms once. Each value keeps the oracle's expression, so sharing changes no bits. Zero crossflow terms are still added as `+0.0`, and the speed test is written `not speed < 1e-6`, so NaN takes the oracle's branch. `thrust_torque()`, `normal_force()`, `pfactor_moment()`, the default untilted path and the turbine path are unchanged. The old path is frozen verbatim with every helper it reaches in [`propulsion_reference.gd`](../../../../app/tests/propulsion_reference.gd), copied from `77cdae9`.

## Proof

- **Byte-exact oracle:** [`test_propulsion_scalar.gd`](../../../../app/tests/test_propulsion_scalar.gd) compares 20,000 seeded cases (5,000 per catalog aircraft) with 0 failures. They include 9,537 tilted-shaft evaluations (8,166 with crossflow), 2,860 still-air run-ups and 921 cases below `STOPPED_RPM`. Rpm runs to 1.3× the trimmed value and density varies from 0.8 to 1.05 × sea level. Default and turbine aircraft are compared too, as a regression check. A one-ulp comparator check and coverage floors prevent a vacuous pass.
- **Mutation check:** on a scratch copy, reassociating the roll-moment sum fails 190 of 20,001 comparisons.
- **Trajectories:** 64/64 960-tick fingerprints (4 aircraft × 4 regimes × 4 runs) match the Gate P `oracle-1` hashes.
- **Full suite:** `app/test.sh` on the H14 working tree exits 0 (90 sections, 714 s), goldens unchanged. [Summary](results/suite-summary.log).

## Cost on the target

Same host and method as H12 and H13. Four runs in sequence: HEAD `77cdae9` (`git archive` copy), H14, H14, then HEAD again. The xvfb capture renderer was still using one core. µs/tick, run 1 / run 2; **bold** exceeds 500. Raw: [before 1](results/base-1.json), [H14 1](results/h14-1.json), [H14 2](results/h14-2.json), [before 2](results/base-2.json).

| P-51D fixture | Before median | H14 median | Before batch p95 | H14 batch p95 |
| --- | ---: | ---: | ---: | ---: |
| trim | **576.8** / **571.1** | **520.0** / **513.5** | **683.0** / **711.2** | **591.3** / **611.4** |
| stall | **577.8** / **583.6** | **540.1** / **541.1** | **740.9** / **699.0** | **694.8** / **591.2** |
| spin | 241.5 / 257.1 | 246.7 / 242.8 | 254.8 / 350.9 | 340.0 / 282.8 |
| ground | 337.2 / 320.1 | 322.3 / 329.5 | 434.6 / 346.7 | 360.1 / **524.1** |

`Propulsion.loads` at the fixtures' initial state: 18.6–20.7 → 8.7–14.4 µs per call. Every other aircraft and fixture stayed within budget in all four runs. The P-51 spin and ground fixtures stop the engine, so propulsion returns before the changed code. Their single 524.1 batch-p95 value is therefore host noise, not an H14 effect, but it is still an overrun on this target.

## Reading

- The P-51 is now 14–41 µs/tick over budget at the median and 91–195 µs over at batch p95.
- The largest bounded cost left is outside the aircraft loads, in `Simulation.step` itself: validity guards, Callable RK stages, `_remember_valid_state` copying seven arrays, and the `stepped` signal. It is about 90 µs/tick on the Stik and about 150 on the P-51. `Propulsion.thrust_torque` is still evaluated twice per load evaluation (propulsion and slipstream).

## Next

1. **H15 — step bookkeeping** (retargeted by measurement to the attached-flow path; see [H15](../H15/README.md)): profile `Simulation.step` and `FlightSession._pre_step` outside the loads for every aircraft, and remove repeated work while keeping every H8 guarantee (atomic rollback, checkpoints, per-stage validation). The work is fleet-wide and should close the P-51 median gap.
2. Share `thrust_torque` between propulsion and slipstream within one evaluation, only if it stays byte-exact and keeps Dynamics simple.
3. Then re-measure. Gate P needs every fixture within budget at both median and batch p95. The p95 also reflects the shared host, so record noise controls (repeat HEAD runs) next to every result.
