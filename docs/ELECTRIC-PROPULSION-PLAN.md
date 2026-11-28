# Reusable electric propulsion

This guide covers the fixed-wing electric motor, ESC power stage and their integration with the propeller and supply. The [battery guide](plans/battery-realism.md) owns pack laws, telemetry and cutoff. The [project roadmap](../ROADMAP.md) owns cross-project priority and acceptance gates.

## Current software contract

`openrc-aircraft v2` is the current aircraft-data boundary and carries the explicit `electric_prop` branch; v1 is a historical compatibility path. Motor, ESC and battery blocks must agree with `capabilities.energy`; the accepted fields and conditional modules are in [AIRCRAFT_CONTRACT](AIRCRAFT_CONTRACT.md) and the [schema/loader evidence](research/propulsion/EL1b/README.md).

The motor is a stateless, positive-rotation DC-equivalent source: `E = rpm/Kv`, `kt = 60/(2πKv)`, `Im = max((d·Vbus − E)/Rm, 0)`, and `Qsource = kt(Im − I0)` while rotating. The ESC law is ideal averaged motoring with identity command-to-duty mapping. The three accepted energy models have distinct scope:

- `fixed_voltage` is the EL1 prescribed bus, with no battery state.
- `ocv_resistance` is the EL2a synthetic pack with SOC, sag, charge/energy accounting, pack-side auxiliary current and exhaustion events. Its accumulated loss energy is not a thermal state.
- `pack_ecm` adds polarization, average/weakest-cell voltage, pack temperature and sampled ESC low-voltage cutoff; the [battery guide](plans/battery-realism.md) owns its behavior, authoring and limits.

MoonRunner X99 uses a [fixed-voltage installation](../app/data/aircraft/moonrunner_x99.json). Turbo Lumber Evolution and Ugly Stick · Electric 6S offer finite-pack and ideal-bus flight; use the [battery mode controls](plans/battery-realism.md#2-current-delivery). Both default to pack in ordinary flight. Workshop trials use their principal fixed-voltage data, explicitly labeled with no depletion, and refuse a finite-pack trial request. The Stik installation remains experimental; its [source dossier](../research/propulsion/stik-6s/README.md) records the conditional electrical fit, startup-current limitation and open physical gates.

When the finite-pack session owns the whole-tick policy, it also owns requested ground-contact subdivisions: compose the existing battery step over those pieces, merge bounded event results atomically, and sample the ESC supervisor once at the outer endpoint. The original one-piece route is retained; the kernel still rejects a foreign whole-tick policy with substeps. [Implementation and regression evidence](research/propulsion/ugly-stik-implementation-2026-11-08.md).

Motor winding and ESC thermal states, manufacturer current limiting, switching losses, controller dynamics, active braking, reverse rotation and regeneration are not implemented by the power-stage contract. Pack temperature and low-voltage cutoff apply only to `pack_ecm`; they do not model motor or ESC temperatures. An ESC rating or nameplate Kv is not a measured motor/pack law. Propeller loads continue to use the shared signed `Ct/Cp` data and stage-local inflow/density.

Electric flight requires `coupled-rk4` with valid rotor and carrier inertia; an explicit split integrator is refused. The session integrates body and rotor state together and localizes stopped-rotor and energy-exhaustion events. Developer routes `-- --electric-demo=4s|6s` use fixed voltage; `4s-battery` and `6s-battery` use synthetic OCV/resistance packs. These labeled Stik fixtures are not catalog aircraft and make no validated conversion claim. The shared shaft behavior is summarized in [PROPULSION-CORE-PLAN](PROPULSION-CORE-PLAN.md).

Electric propeller inflow is sampled at the hub (`v_air + omega × r`) for loads and shaft torque. The configuration hash identifies this law; old native snapshots are refused. Electric propwash is not supported by the current aircraft schema. [EL1d-R1 correction and verification](research/propulsion/EL1d/hub-inflow-2026-10-23/README.md).

## Physical reference and promotion

The reference is the E-flite Turbo Timber Evolution BNF Basic B, EFL105250B: 800 Kv motor, 70 A ESC, stock three-blade 11×7.3 propeller and 4S 3200 mAh pack class. The catalog's finite-pack variant is software integrated, but the exact installed pack and hardware revision, motor R/I0, rotor inertia, loadout and matched stock-prop map remain unidentified. Manufacturer labels do not supply those parameters. SAFE and AS3X state must be recorded separately; disabling SAFE alone is not an unaided-flight reference. The sourced configuration and limits are in [Turbo Lumber Evolution reference research](research/propulsion/EL1a/timber-reference.md).

EL5/EL6 require calibrated, matched, held-out physical measurements with hardware/firmware, temperature, environment, channel timing and uncertainty recorded. The ROADMAP targets remain ±10% for current/thrust and ±15% for endurance. The project's uncertainty rule passes when `abs(error)+Uerror <= limit`, fails when `max(0,abs(error)-Uerror) > limit`, and otherwise reports inconclusive; this is a project rule, not a manufacturer requirement. Preserve raw observations and the fit/validation split.

## Remaining qualification

| Work | Required evidence |
| --- | --- |
| EL1e-STIK / EL1f, catalog installations | For the experimental Stik 6S, qualify the remaining fleet, target performance and release routes against its [installation record](research/propulsion/ugly-stik-implementation-2026-11-08.md). For Turbo Lumber Evolution, identify the actual stock equipment and loadout against the [model handoff](research/propulsion/EL1f/README.md) and [aircraft integration plan](TIMBER-INTEGRATION-PLAN.md). Pilot acceptance remains separate. |
| EL3, controller behavior | Measure the controller's ramp, signal-loss and brake/freewheel modes. BAT-11 owns cell detection and low-voltage cutoff. |
| EL4, winding and ESC thermal behavior | Obtain thermal data and close the energy balance before adding thermal states or derating. BAT-07 owns pack temperature. |
| EL5 / EL6, powertrain and endurance | Apply the held-out measurement rule above. Use the [static validation tools](research/validation/VAL-7a/README.md), [RPM-step diagnostics](research/validation/VAL-7c/README.md) and [propeller coverage](research/propulsion/G1b1/README.md). BAT-28 owns endurance validation. |
| Electric tick budget | Measure whole-session ticks on the idle original target, recording selected backend, aircraft and regime. Report steady, contact and stop/exhaustion event distributions separately. |

The [motor/ESC investigation](research/propulsion/EL1a-R1/README.md), [numerical study](research/propulsion/EL1a-R2/README.md), [session and event fixtures](research/propulsion/EL1d/README.md) and [maneuver refinement](research/propulsion/EL2a-E1/README.md) document the model and its software checks. [EL2a-P1](research/propulsion/EL2a-P1/README.md) measured 558–562 µs battery medians on a Ryzen 9 5900X under WSL. [P2](research/propulsion/EL2a-P2/README.md) reduced event costs in its paired fixtures. [P3](research/propulsion/EL2a-P3/README.md) established result preservation under concurrent workloads. Target-host tail latency remains open.
