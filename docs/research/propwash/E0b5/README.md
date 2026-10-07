# E0b5 — Continuous axial wash transport

2026-10-07 · **Status: complete for experimental axial speed transport.** Experimental fixture only; production Stik remains unconfigured.

## Model and scope

[Selig 2010, §III, printed p. 7](https://m-selig.ae.illinois.edu/pubs/Selig-2010-AIAA-2010-7638-PropAeroSim.pdf) describes first-order downstream speed lags depending on disc flow speed and propeller-to-surface distance. It does not give a calibrated Stik time constant. The implementation uses that model class with the explicit engineering approximation below. **The acceptance measurement is the 63.2% speed response, not a pure delay with zero response before arrival.** This distinction clarifies the roadmap's former “step delay” wording.

For each E0b3b profile piece, in metres and seconds:

```text
L_i = piece.root.x - hub.x
U_c = max(u + w_disc, transport_speed_floor)
tau_i = L_i / U_c
dv_i' = (dv_equilibrium - dv_i) / tau_i
```

`dv_equilibrium` is the existing `k_w * w_disc` law, or zero with a stopped source or fully reversed wake. Tail loads use the stage's `dv_i`; equilibrium and convection speed use that same stage's airspeed. Horizontal pieces share a 1.134176 m path; the fin's is 1.154176 m. Three states preserve the declared piece order without a representative-distance fit.

The opt-in quantity `slipstream.transport_speed_floor` requires provenance, units `m/s`, a value in `[0.1, 5]`, smooth profiles and zero swirl. The test uses **estimated** 1 m/s to let residual wash decay at zero flow. This floor and the distance/disc-speed law are not measurements. At static full fixture rpm, time constants are 74.662/75.979 ms; at 15 m/s full rpm they are 49.428/50.300 ms. These replace the earlier knowledge-base estimate using `u + 1.8w` for this implementation; they are not universal lag bounds.

This slice transports **axial speed only**. Radius, drift, direction and reverse occupancy remain instantaneous; body-local angular velocity still supplies the existing damping. A stopped source retains decaying axial speed, with instantaneous unpowered geometry. Delayed geometry/direction, swirling transport and a resolved wake history remain unmodelled. E0b6 must address the known centroid/swirl error before combining swirl with this mode.

## State ownership

`Simulation.continuous` is a separate float64 array. RK4 packs it after the 13 body entries internally, evaluates both derivatives together and commits both atomically. Body state, interpolation and CSV v3 remain 13-dimensional. RPM, servos, anchors and downwash retain their existing sampled policy: **this does not make the entire aircraft/shaft transient fourth order**.

The session initializes every wash entry at equilibrium for flight and runway resets. Native checkpoints include the continuous array and reject missing, nonfinite or incompatible layouts. All failure paths restore it with body, sampled and discrete state. Session load evaluation rejects a mismatched piece count before indexing. Trace metadata identifies transport and says its state is checkpoint-only; CSV is not an exact replay container. Existing golden files are unchanged; this experimental state is verified with native checkpoint replay and explicit tolerances in its focused tests.

## Verification

- [42 state checks](state-checks.log): analytic bidirectional coupling, stage time, malformed/nonfinite pre-step and k1–k4 load/derivative rollback, intermediate overflow, layout/reset rules and exact checkpoint continuation.
- [38 transport checks](transport-checks.log): provenance/schema rejection, exponential response, each piece's 63.2% crossing within 5%, stage-dependent loads, settled reset identity, engine-off residual, reverse cutoff, configured-field runway reset and aircraft switching. Real body/wash refinement with sampled inputs held gives error ratios **17.66 and 16.87** for 60→120→240 Hz against 960 Hz.
- [Frame comparison](frames.log): identical hashes of every body/wash/aux/load/input boundary through 480 ticks at 30/60/144 fps, using the real SceneTree scheduler; included in `app/test.sh`.
- [Mutation checks](mutations.log): wrong convection speed, ignored transported loads, frozen load state, frozen derivative body state and corrupted checkpoints are each rejected by assertions in disposable copies.
- [Full regression](suite-summary.log): `app/test.sh` exits 0 in a fresh clone with this step and its E0b3b/E0b4 prerequisites (112 sections, 87 GDScript test programs). Concurrent landscape/input edits are excluded. [Resource and scene checks](integration.json): zero errors, zero new-script diagnostics, three scene smokes pass; the broader project retains 184 existing validator warnings.
- [Fleet comparison](fleet-comparison.json): all 16 four-aircraft trim/stall/spin/ground fingerprints match the pre-E0b5 working-tree snapshot. No golden regeneration or production aircraft-data change.

## Cost and remaining work

[Paired experimental cost](transport-cost.json) records five measured batches after warm-up, 120 whole ticks each, with and without transport. [Fleet comparison](fleet-comparison.json) retains production before/after timings and host details. Shared-host timings are evidence, not owner-machine Gate P acceptance; some fleet batches overlapped other checks. The enabled profile already exceeded 500 µs/tick before transport. Calibration, source observations, swirl accuracy and enabled-path performance remain open.

| Fixture | Instantaneous wash, µs/tick | Transport, µs/tick |
| --- | ---: | ---: |
| forward | 765.8 | 868.4 |
| stall | 808.3 | 862.7 |
| static | 627.3 | 723.2 |
| spin | 807.9 | 901.8 |
| reverse_fade | 613.6 | 692.7 |
| reverse_off | 363.7 | 469.9 |

The production P-51 trim/stall medians in this run were 582.9/546.4 µs versus 494.0/508.2 before; broad batch ranges and concurrent work prevent isolating the cause from these runs. Gate P remains open.

## Reproduce

From the repository root:

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_continuous_state.gd
$(app/get-godot.sh) --headless --path app --script res://tests/test_wash_transport.gd
python3 research/propwash/e0b5/check_frames.py --godot "$(app/get-godot.sh)"
python3 research/propwash/e0b5/check_mutations.py --godot "$(app/get-godot.sh)"
$(app/get-godot.sh) --headless --path app --script "$PWD/research/propwash/e0b5/bench_transport.gd" -- /tmp/e0b5-cost.json
app/test.sh
```

Commit message: `E0b5: couple axial wash to RK4; prove 80 checks, 16 exact fleet hashes and full regression`
