# Pure afterburner core: integration starter

**Status:** original standalone GDScript prototype, not installed into OpenRC Simulator. The example values are invented tuning for a virtual installation. They are not measured JetCat P100-RX performance, an ECU model, or evidence of a real afterburner on the stock aircraft.

The reviewed production source is `bultodepapas/OpenRCsimulator` at `f41d0fd2eb5483c609bcd858bcf22776eb311e14`. Its application uses a custom float64 240 Hz RK4 kernel, body FRD coordinates and world NED. This prototype has no tick owner, scene nodes, input polling, audio dispatch, fuel inventory or Godot rigid-body calls. The production source remains unchanged.

## What is implemented

- A pure scalar intensity derivative with separate rise and fall time constants.
- Independent request, dry-throttle and RPM gates; engage/release hysteresis.
- Engine/source/arming/input interlocks and release-to-rearm after hard inhibition.
- A read-only sampled-command envelope, frozen across RK stages and retries.
- Pure accepted-boundary state/event proposals; ignition timers never advance in a stage evaluator.
- Additional gross nozzle force and its analytical moment, returned as `PackedFloat64Array([Fx,Fy,Fz,Mx,My,Mz])`.
- Additional fuel flow in kg/s, returned to the caller without decrementing inventory.
- Bit-exact positive-zero added force, moment, gross-thrust and fuel outputs in disabled/cosmetic modes.
- Independent state envelopes for separate engines; no static mutable runtime state.
- Explicit invalid/nonfinite input refusal and a conservative scalar step-size check.

All physics values use GDScript `float` or `PackedFloat64Array`. Discrete enums/sequences are integers. The core uses no `Vector3`, `Basis`, `Quaternion`, `Transform3D`, RNG, frame clock or render-time value.

## API and ownership

| Function | Owner / contract |
| --- | --- |
| `example_config(mode)` | Returns provisional scalar tuning. Use a configuration frozen for the run. Changing it mid-interval is unsupported. |
| `validate_config(config)` | Checks numeric constraints, gates, finiteness and array shapes in this standalone configuration. Field names declare intended SI units; this function does not parse or validate production unit/provenance wrappers or establish physical realism. |
| `initial_state(config)` / `valid_state(state, config)` | Detached accepted state; the production adapter must map it into explicitly versioned continuous, sampled and discrete blocks. |
| `freeze_sample(state, command, permits, config)` | Pure once-per-interval proposal from the accepted state and accepted controls. Returns a read-only dictionary containing scalars only. |
| `evaluate(intensity, sample, stage_combustion_available, config)` | Pure stage function. Returns intensity derivative, flame intensity, additive gross loads and additive fuel demand. |
| `finish_interval(previous, sample, candidate_intensity, dt, endpoint_combustion_available, config)` | Pure proposal of the accepted endpoint and transition records. The transaction owner commits it once. |
| `step_supported(config, dt)` | Checks the scalar explicit-stage interval; not a general whole-aircraft stiffness proof. |

`command` contains `request` and `throttle`, each finite in `[0,1]`. Request is independent of throttle, so the existing dry-throttle range can be preserved. `permits` contains booleans `armed`, `input_valid`, `engine_running`, `source_available`, plus a finite nonnegative `rpm_ratio`. Thresholds are invented fractions of a future installation-specific RPM reference.

The returned sample is immutable, but the caller must also preserve its configuration for the interval. Validation does not substitute for configuration hashes or model identity. The stage's `stage_combustion_available` is a separate current-stage input: a located fuel-exhaustion event must override a sample that permitted burn at interval start. This is deliberately not cached in the request latch.

The accepted state contains `intensity`, `phase`, `ignition_elapsed_s`, `latched`, `rearm_required` and `transition_sequence`. Save/restore all of them. Event records contain a sequence number, previous/new phase, interval-relative time and reason. They are returned data; the core emits no signals or sounds. Repeating an uncommitted proposal returns the same records. The real transaction owner must commit only once and presentation must deduplicate committed transition IDs. A cold ignition event is `IGNITING -> LIT`; `EXTINGUISHING -> LIT` with reason `resume_existing_burn` resumes an existing flame and must not replay a cold-ignition one-shot.

These local event proposals are **not** already valid `VehicleModel` event records. The production adapter must give them an event `type` and engine identity, convert `time_offset_s` to the kernel's absolute `time_s`, and place them in the owning accepted transaction. Do not pass this local array directly to the kernel event contract.

## Model equations and limits

For target intensity `u`, integrated intensity `a` and selected response time `tau`:

```text
da/dt = (u - a) / tau
additional gross thrust = a * configured full-AB gross-thrust increment
additional fuel flow = a * configured full-AB fuel-flow increment
additional force = nozzle_axis_FRD * additional gross thrust
additional moment = nozzle_arm_FRD cross additional force
```

Force and fuel use the same accepted physical burn intensity. A normal release has a short modeled tail with corresponding fuel demand. A hard combustion/source cutoff immediately suppresses the stage's AB force/fuel outputs; the accepted endpoint clears intensity and requires a fresh request release. Any longer residual visual heat/flame envelope belongs to presentation and cannot keep supplying thrust.

Reengagement while the soft tail is still physically burning resumes directly from its current intensity. It does not mute force/fuel during a new ignition wait, then resurrect the residual intensity. After the tail has reached `READY` at zero intensity, a new request performs the normal ignition delay. This is an explicit provisional transition policy, not a manufacturer ECU claim.

Ignition is deliberately **quantized to accepted interval boundaries**, with at most one interval of completion delay. `finish_interval` increments the timer once. No stage consumes time or changes modes. This starter does not claim exact within-tick ignition-event timing; adding that requires composition with the existing fuel event policy, not a second independent integrator.

The `tail_epsilon` endpoint projection ends an asymptotic tail. Its small discarded remainder is a declared numerical approximation, not an exactly energy-conserving shutoff model. The fixture validates the smooth tail before this projection separately.

The prototype's force/fuel coefficients describe only one nominal condition. It has no density, Mach, pressure ratio, nozzle-area, compressor-rematching or thermal map. A production profile needs bounded evidence-based or explicitly estimated maps; do not treat these constants as a full flight-envelope law. It does not change core RPM or rotor momentum when AB starts.

## Production integration seams

1. Extend the existing `VehicleModel` callbacks and state layout; do not add vehicle-specific code to `Simulation`. Its framed sampled protocol can freeze accepted request/latch state across every RK stage. Keep legacy and framed callbacks consistent with the selected protocol. For disabled/cosmetic operation, **bypass physical force/fuel addition entirely** in the production adapter: even adding numeric zero can change a signed-zero bit pattern or arithmetic order. The starter's canonical zero outputs alone cannot establish bitwise preservation of the stock integration path.
2. Add the returned gross-nozzle force and moment to the turbine result **before** the existing fixed-datum/live-CG transformation. The core arm is already FRD relative to the same declared datum. Do not convert an authored `[aft,right,up]` arm twice or perform the live-CG shift twice.
3. Preserve the existing captured-air momentum/ram-drag contribution and rotor angular momentum. Multiplying the whole turbine load vector would incorrectly multiply inlet side forces and moments.
4. Add `additional_fuel_flow_kg_s` to the existing dry fuel rate inside the same stage derivative. Reuse its fuel exhaustion locator, source latch, residue and stage mass/CG/inertia. Do not create another tank or a render-tick inventory writer.
5. `liquid_fuel_flight.gd` currently validates `values.size() == _liquid_index() + 2`. Appending a scalar without updating every index/layout/restore path is invalid. Version the complete state layout and identity, then qualify checkpoint, exact replay and native snapshot serialization/admission.
6. Refuse the new physical capability on the native backend until the matching native state, stage/fuel laws, events and snapshots are implemented and qualified. Do not silently run dry native physics under wet presentation. A deliberate, visibly identified reference-backend selection is a separate integration decision.
7. Route keyboard/gamepad/radio controls through accepted simulator input. Preserve existing arming, pause/disconnect, help, remapping and saved-profile ownership. Old profiles default to zero request.
8. Bind render/audio emitters by stable `engine_id`. Two nozzles from one engine do not duplicate thrust or fuel. Multi-engine propulsion itself remains a production extension unless the installed model already supports it.
9. Update the aircraft generator, strict capability schema and Workshop pipeline. Do not hand-edit generated P100 aircraft JSON or claim these invented increments as manufacturer data.

These are integration instructions, not completed changes. The current stock jet's default dynamics remain unchanged because this package is detached.

## Run the focused fixture

Use the source-pinned official Godot 4.8-beta2 executable. From the prototype directory:

```sh
"/absolute/path/to/Godot_v4.8-beta2_linux.x86_64" \
  --headless --path . --audio-driver Dummy \
  --script res://tests/test_afterburner_core.gd
```

Inspect both the final marker `AFTERBURNER_CORE: ... checks, 0 failed` and Godot diagnostics. A zero process status alone is insufficient. With the OpenRC checkout available, use its existing checked runner:

```sh
python3 /absolute/path/to/OpenRCsimulator/tools/godot/run_checked.py \
  --label afterburner-core --timeout 30 \
  --out-dir /absolute/path/to/fresh-evidence-parent \
  --require-text 'AFTERBURNER_CORE:' -- \
  /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --headless --path /absolute/path/to/prototype --audio-driver Dummy \
  --script res://tests/test_afterburner_core.gd
```

The fixture uses a test-only scalar RK4 quadrature and compares against independent closed-form exponential response and fuel integrals. It checks input/state rejection, immutable sampling, repeated-stage and endpoint purity, ignition timing, threshold chatter, reconnect rearming, source cutoff at high RPM, soft-tail fuel consistency, analytical off-axis moments, canonical zero physical outputs, checkpoint repeatability and independent engine state. It does not run production `Simulation`, prove native parity, validate full fuel exhaustion/remainder behavior, or qualify flight realism, renderer cost or hardware controllers.

## Primary references

- [OpenRC VehicleModel contract at the reviewed commit](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/sim/vehicle_model.gd).
- [Existing turbine force law](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/physics/turbine.gd).
- [Existing finite-liquid stage adapter](https://github.com/bultodepapas/OpenRCsimulator/blob/f41d0fd2eb5483c609bcd858bcf22776eb311e14/app/sim/liquid_fuel_flight.gd).
- [NASA afterburning jet thrust](https://www.grc.nasa.gov/www/k-12/airplane/turbab.html).
- [NASA general thrust equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/).
- [NASA thrust-specific fuel consumption](https://www.grc.nasa.gov/www/k-12/airplane/sfc.html).
- [JetCat LED afterburner rings: appearance simulation](https://www.jetcat.de/en/productdetails/produkte/jetcat/produkte/zubehoer/Elektronik/Nachbrennerring%20D-80mm).
