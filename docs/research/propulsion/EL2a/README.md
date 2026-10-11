# EL2a — Coupled OCV/resistance battery state

2026-10-11 · **Status: synthetic integration, numerical, flight and product checks pass; full regression and cost measurement in progress. Identified battery data and physical acceptance remain open. Step prefix: EL.**

This branch adds a balanced aggregate OCV/resistance battery to the electric flight session. It integrates remaining charge, terminal energy and pack heat with the motor/rotor state. The existing fixed-voltage path retains its arithmetic and native Variant key types; the data checks compare normalized native bytes against the prior fixed-route representation.

For the positive-current branch, `Im = [d(OCV − Rpack Iaux) − Eback]/[Rm + d² Rpack]`, `Ipack = d Im + Iaux`, and `Vbus = OCV − Rpack Ipack`. The non-motoring branch has zero motor current and retains auxiliary draw. The ideal ESC's duty conversion applies to both voltage and current. The previous `battery_current_a` source field remains drive-input current; the new `pack_current_a` includes auxiliary loads. Neither represents phase RMS current.

## Data contract

`openrc-aircraft v1` accepts a closed `kind: "ocv_resistance"` battery object. Every scalar and each OCV knot value carries `{value, unit, kind, source}` provenance. Required quantities are `capacity_ah`, `resistance_ohm`, `auxiliary_current_a`, `initial_soc`, and `ocv_points` (`[{soc, voltage}, ...]`). The loader requires finite values; capacity > 0; resistance and auxiliary current ≥ 0; initial SOC in `(0, 1]`; OCV knots covering SOC 0 to 1 in strictly increasing SOC order with positive, nondecreasing voltage; finite slopes and coulomb values; and a positive feasible bus at minimum OCV (`R × Iaux < OCVmin`). Unknown and mixed battery fields are refused. Normalization stores the OCV pairs as `PackedFloat64Array([SOC, V, ...])`; reference RPM is `Kv × maximum OCV`. No governor is added.

The two named demo fixtures are authored synthetic inputs, not Timber data or measured LiPo fits:

| Demo | Capacity | Pack R | Pack-side auxiliary load | Initial SOC | OCV endpoints |
| --- | ---: | ---: | ---: | ---: | ---: |
| 4S | 3.2 Ah | 0.030 Ω | 0.20 A | 0.95 | 12.0–16.8 V |
| 6S | 2.2 Ah | 0.045 Ω | 0.15 A | 0.95 | 18.0–25.2 V |

Each uses one linear OCV segment, the earlier synthetic motor and the Stik's inherited mass, inertia, propeller and visual. These do not describe a physically converted Stik. The reusable loader supports additional OCV knots, while each new aircraft/pack still needs its own timestep and physical evidence.

From the repository root, run the visual demos with the pinned engine:

```sh
"$(app/get-godot.sh)" --path app -- --electric-demo=4s-battery
"$(app/get-godot.sh)" --path app -- --electric-demo=6s-battery
```

## State, events, and evidence

The coupled RK4 state carries propeller shaft speed, remaining charge (C), terminal energy (J), and pack heat (J), after any configured wash states. SOC and consumed charge derive from remaining charge. The exhaustion event is localized within a tick and composed with rotor-stop timing. At exactly zero charge this convention disconnects motor and auxiliary pack loads; the unpowered rotor continues to lose speed through bearing drag. This is a simulation boundary convention, not ESC low-voltage protection behavior.

Every stage evaluates `dQ/dt = −Ipack`, `dEterminal/dt = Vbus Ipack`, and `dHpack/dt = Rpack Ipack²`. Heat is accumulated loss energy, not temperature. There is no second simulation clock. The existing electric loader still refuses slipstream blocks; the shared continuous-state layout preserves the wash prefix for other propulsion paths.

`electric_battery_step.gd` wraps the existing rotor-stop solver. Active trial evaluations extend OCV at zero charge only to locate the boundary; no negative charge or RPM is committed. The accepted event uses a nonpositive charge residual bounded by 1e−10 C and a time bracket bounded by 1e−12 s, then sets charge to exactly zero and advances the remaining tick disconnected. Rotor events from rejected trials are discarded; coincident events have stable ordering. Positive charge derivatives, nonfinite evaluations and exhausted iteration bounds fail the whole tick. Focused fixtures cover battery-first, rotor-first and shared-time roots. This is a bounded monotone-depletion solver, not a detector for arbitrary hidden oscillatory events.

Launch retains the source stiffness guard and adds charge feedback: `dt [kt²/(Rm Jr delta) + max(dOCV/dSOC)/(Rm Capacity_C)] <= 0.25`, where `delta = 1 − Jr aᵀ Jlocked⁻¹ a`. This conservative source bound does not qualify aerodynamic/contact stiffness. Full-session refinement qualifies the two supplied fixtures at 240 Hz.

Dynamic-battery checkpoints use **`openrc-flight-checkpoint v6`** and CSV uses **`openrc-trace v8`**. Checkpoints include the coupled state and battery identity. Trace rows report SOC/charge, OCV, pack and auxiliary current, terminal power, pack loss, terminal energy, pack heat, and exhaustion state.

All electrical columns sample the accepted endpoint with the current tick's input; existing aerodynamic-load columns retain k1 timing. Reset restores initial charge and clears both energy integrals. Pause freezes state; faults roll back the full boundary; exact replay includes weather/RNG and battery state. Wrong law/configuration/version and invalid charge/energy are refused. The fixed-bus checkpoint v5/CSV v7 and combustion formats retain their old layouts. Full 480-tick fixed-bus checkpoint hashes match the prior EL1e results in [legacy-checkpoints.json](legacy-checkpoints.json); all six old aircraft files remain [byte-identical](unchanged-datasets.json).

Focused checks passed: supply kernel **95**, battery data **67** (including the fixed-voltage native-key regression), coupled event step **63**, and session/checkpoint/trace **103**. The independent numerical oracle and flight report are in [scalar.md](scalar.md) and [flights.json](flights.json). Flight verification covers eight 30 s traces (7,201 rows each) and 48 corrupted-trace controls. The 4S/6S level runs drifted −0.53/−0.74 m within the declared ±10 m software check; climbs gained 66.95/63.20 m; turns accumulated 355.8°/359.6°; throttle-chop runs retained auxiliary draw with zero motor current; all traces stayed above 10 m. The independent checks evaluate current/sag/power and the charge-based chemical-energy ledger. These are software tests on authored fixtures, not physical flight validation.

The scalar oracle uses independently derived principal-axis rotor/body and battery equations, analytic auxiliary-only exhaustion and pinned SciPy DOP853. Its source-off event timing error is below 6.1e−13 s across 120/240/480/960 Hz. The real-session 0.5 s transient compares those rates against 1920 Hz with separate body/RPM/charge/energy/heat budgets. Small high-rate charge/energy errors approach roundoff; the report records convergence diagnostics without claiming fourth order for the whole sampled flight system.

[Powered exhaustion](powered.md) adds eight real-session near-empty/full-duty cases across the same four rates. Exact chemical work closes within 4.48e−10 J; unmodified and instrumented sessions have byte-identical complete checkpoints. The experiment also exposes a tens-of-milliseconds exhaustion-tick cost, which is reported separately from ordinary warm batches.

Schema/runtime comparison passes **1,863 cases** (142 accepted controls, 20 runtime-only physical checks), plus the eight-aircraft structural preflight. [Schema log](schema.log). The [product proof](product-proof.json) passes **38** main-scene input checks across both battery routes, equal full-state hashes at 30/60/144 FPS, three invalid CLI controls, and both datasets in a Linux export run from empty working directories (49 v8 rows each). A [fresh clone](clean-checkout.json), without the original editor cache, passes import and all 67 data/103 session checks.

Reproduce from the repository root:

```sh
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_electric_battery_session.gd
python3 research/aircraft-data/schema/test_contract.py
python3 research/propulsion/el2/verify_battery.py --godot "$(app/get-godot.sh)" --app app --output /tmp/el2-scalar.json
python3 research/propulsion/el2/verify_flights.py --godot "$(app/get-godot.sh)" --directory /tmp/el2-flights
python3 research/propulsion/el2/powered/reproduce_and_compare.py --godot "$(app/get-godot.sh)"
python3 research/propulsion/el1/product_check.py --battery --out /tmp/el2-product
app/test.sh
```

The independent oracle uses the [pinned NumPy/SciPy environment](../../../../research/propulsion/el1a-r2/requirements.txt). Product export requires the already-installed pinned Linux export template; its runner does not download one.

## Limits and pending gates

The fixtures do not identify the Timber or any measured battery. The model has no per-cell imbalance or weakest-cell protection, measured ESC/LVC behavior, BEC/receiver model, RC polarization fit, or thermal fit. The constant auxiliary pack current is a declared fixture input; it does not establish receiver/servo consumption. No endurance or hardware-safety conclusion follows from these traces.

- Full app regression: **Pending — evidence to be added.**
- Electric tick-cost measurement: **Pending — evidence to be added.**
- Identified Timber pack/load data and physical acceptance: **Pending.**

See the [electric propulsion plan](../../../ELECTRIC-PROPULSION-PLAN.md#battery-and-esc-growth) for EL2a dependencies and later ESC, polarization, and thermal steps.
