# Glow tick cost: measured breakdown and pending optimizations (NITRO-04)

2026-10-14. Software measurements on the shared development VM (llvmpipe host, 240 Hz, 120 warm-up + 600 measured ticks, `FlightSession` + `sim.step()`). The host is noisy: unchanged legacy code varied by ±10–14 % between rounds, and up to 630–1000 µs p50 in a later session.

## Cost before NITRO-05

| Case | Cruise p50 / p95 (µs) |
| --- | --- |
| Legacy Stik | 609–632 / 980–984 |
| Glow 2T (MAX-55AX) | 1587–1643 / 2544–2745 |
| Glow 4T (FS-64V) | 1619–1636 / 2551–2723 |

Where a glow 2T cruise tick went, from an instrumented disposable copy (about 1985 µs per tick; 4T within 3 %):

- **`GlowFlight.point()`, 5 calls (4 RK stages + endpoint): 790 µs.** Lifecycle 472 µs (source 177, `_state_error` 65, unit fuel flow 37, thermal 34, the rest Dictionary building); propeller 125; `air_data` 42; `unpack` 33.
- **`Dynamics.loads_from_air`, 4 calls: 245 µs.** Same as legacy.
- **Glue in `evaluate()`: 210 µs.** Fuel-mass properties 67, `datum_derivative` 46, `Coupling.response` 37.
- **`Life.accepted`: 81 µs**, 35 of them re-validating the immutable configuration.
- **Integrator and validation wrappers: 250 µs.**
- **Allocations: 2214 per tick**, against 783 for legacy.
- **math3d calls: 435 per tick**, against 137 for legacy; 300 of them come from the propeller.

## Applied (byte-identical)

- **X1:** `Life.accepted_prepared` validates the configuration once at prepare time.
- **X2:** the family kernels, thermal and lifecycle build their results with local finiteness checks. The order and the messages are unchanged.
- **NITRO-05:** the fuel-mass properties computed for the feed are reused by `evaluate()`.

Trajectory fingerprints (state, continuous and aux hashes over 1320 ticks, cruise and throttle steps, 2T and 4T) are identical before and after. Every `test_glow_*` passes.

With the fuel feed's endpoint airframe loads, the net cruise cost on the noisy host was 1.74–1.90 ms p50 (2T), against 0.63–1.0 ms for legacy. The 500 µs gate stays unmet.

## Pending (not applied)

These two patches were written against the tree before NITRO-05 and must be rebased; they do not apply as they stand.

- **`x3-endpoint-firing-only.patch`**, about −95 to −130 µs per tick, more since NITRO-05:
  - The accepted step only commits the endpoint firing fraction. This patch computes that fraction without the full `point()`, which would also skip the propeller, source, thermal and, since NITRO-05, the endpoint airframe loads.
  - **Owner decision:** an endpoint invalid only for the propeller, source or thermal law would then fault one tick later, after the state is committed.
- **`x4-packed-stage-kernel.patch`**, about −10 % more:
  - A Dictionary-free RK-stage path with the same float operations in the same order.
  - The rebase must pass `feed_factor` into `Life.stage_prepared` and return the airframe, fuel feed and mass from the stage branch.

Not tried (estimates):

- Validate the packed values without the `unpack` Dictionary: −40 to −60 µs.
- Drop repeated finiteness scans in `Simulation.f` → `Boundary` → `Stop`: −40 to −70 µs; this is shared with the electric path.
- Cache the `FlightSession` helpers (`wheel_count`, `downwash_index`): −25 to −40 µs; legacy benefits too.
- A prepared fuel-mass evaluator: −15 to −25 µs.

Rejected because they would change results:

- `pow(sin α, 2)` → `s*s` (differs in 195 of 200 000 samples).
- Bypassing the math3d wrappers (decision H6).
- Regrouping the propeller products.
- Reusing the endpoint as the next tick's first stage.
