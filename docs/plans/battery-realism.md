# Battery and energy storage

2026-10-19 · Step prefix: **BAT-00…29** · Owner: electric propulsion (EL).

Current behavior comes from runtime code, configuration and generated data. This guide owns battery integration and remaining BAT work. Software verification does not establish physical validation; the shipped packs are class estimates.

## 1. Ownership and documentation homes

BAT owns `app/physics/battery/`, generated `app/data/batteries/`, `research/battery/`, battery tests and battery evidence. It continues EL2b, the battery supervisor/BEC part of EL3, pack temperature from EL4 and endurance from EL6. EL retains the motor, ESC power stage, winding/ESC thermal and powertrain validation.

| Topic | Home |
| --- | --- |
| Motor, supply choices and remaining EL work | [Electric propulsion](../ELECTRIC-PROPULSION-PLAN.md) |
| Accepted battery fields, normalization, equations and state layout | [BAT-04 specification](../research/battery/BAT-04/specification.md), checked against the loaders and laws linked there |
| Fitting, generation and reference commands | [Battery tools](../../research/battery/README.md) |
| Player controls | [First launch](../FIRST-LAUNCH.md#4-settings-and-flight-options) |
| Decisions and original rationale | [DECISIONS](../DECISIONS.md), including BAT-13's default-mode override |
| Dated sources and delivery proof | [BAT-00](../research/battery/BAT-00/README.md), [BAT-05](../research/battery/BAT-05/README.md), [BAT-10](../research/battery/BAT-10/README.md), [BAT-15](../research/battery/BAT-15/README.md) |

Contract/schema, aircraft generators, session/logging, HUD, UI, audio, Workshop, failures and crash/economy retain their [registered owners](../README.md#tracks-plans-and-step-ids). Other vehicles use the shared kernel and keep their own acceptance gates.

## 2. Current delivery

Turbo Lumber Evolution is the only catalog aircraft with `battery_data`. Its finite `pack_ecm` variant is the default; Home's **More flight details → Battery** or `--battery=ideal|pack` selects the mode. `pack` is refused without pack data. The ideal Timber variant uses fixed voltage. Selection and default rules live in [AircraftCatalog](../../app/app_state/aircraft_catalog.gd).

The [pack law](../../app/physics/battery/pack_ecm.gd) implements 0–2 Thevenin RC branches, an average cell plus one weakest cell, charge/energy/loss accounting, a lumped pack temperature and a closed-form single-motor bus solve. SOC/temperature table lookups are bilinear and clamped. Capacity is temperature-independent; resistance and cutoff produce reduced usable charge under load. Interconnect loss contributes to electrical loss, but not pack heating.

The [ESC battery supervisor](../../app/physics/battery/esc_supervisor.gd) detects cells at connection and supports off/soft/hard LVC, debounce and throttle-reset or latched recovery. It samples accepted tick endpoints and holds its limit for the next tick. LVC bounds duty; it is separate from the pilot's voltage alarm.

The older `fixed_voltage` and `ocv_resistance` routes retain their separate laws. Motor/ESC temperature, current limiting, braking, reverse and regeneration are outside the current power-stage implementation.

## 3. Data and authoring

The [strict pack loader](../../app/physics/battery/battery_data.gd) accepts `openrc-battery v1` packs pinned to `openrc-cell-template v1` bytes. The [aircraft loader](../../app/physics/aircraft_data.gd) requires `openrc-aircraft v2`, matching capabilities, a pinned pack, an inventory mount with exactly the pack mass, and a `low_voltage_cutoff` block. Aircraft admission currently permits LiPo/LiHV mounts with `energy_source: "lipo"`; other chemistries need crash-vocabulary integration first.

The generated catalog contains two fitted templates (LiPo K1 and HG2 Li-ion K2) and eight class packs. A generated pack is not automatically selectable or flyable. There is no general pack chooser or aircraft compatibility/bay-fit evaluator yet.

Regenerate through the [battery tools](../../research/battery/README.md) and the owning aircraft pipeline; never edit generated JSON. Preserve input hashes, quantity provenance and the dataset-fit/class-scaling distinction. C-rating labels do not define resistance or a runtime current limit. `initial_soc`, auxiliary current, cooling and weak-cell factors currently come from aircraft data; reset starts a rested pack at ambient temperature. Arbitrary charge/temperature selection and persistent health remain planned.

## 4. State, events and replay

[FlightSession](../../app/sim/flight_session.gd) couples pack and shaft/body state through RK4. After shaft rpm, the battery block has `9 + 2K` float64 slots, including RC voltages, temperature and zero-derivative sampled ESC slots; [BAT-04 §5](../research/battery/BAT-04/specification.md#5-session-continuous-block) owns the exact order.

Weak-cell charge is the located exhaustion boundary. Exhaustion disconnects motor and auxiliary load; LVC is sampled rather than root-located. The current step policy refuses charging, so regenerative/full-charge events are still BAT-08 work. Launch guards include the electrical/RC/filter timestep constraints.

Checkpoint, restore, rollback, trace identity and flight logs include the pack state and configuration pins. Current format selection belongs to the session and [trace writer](../../app/sim/trace.gd); delivery-time version numbers in BAT-10 are historical. Use the [flight logging workflow](../FLIGHT-LOGGING.md) for exact baseline/candidate comparisons.

## 5. Evidence and acceptance

The [BAT-10 record](../research/battery/BAT-10/README.md) holds software results, mutation evidence and measured cost limits. The independent [Python reference](../../research/battery/ecm_reference.py) uses the standard library; native comparisons cover stage results, rates and supervisor behavior. A SciPy/PyBaMM cross-check was proposed but is not delivered. The tool guide owns runnable commands; focused native checks are `test_battery_data`, `test_battery_pack_ecm`, `test_battery_esc_supervisor`, `test_battery_session`, `test_ui_battery_mode`, `test_overlay_battery` and `test_overlay_battery_flight` under `app/tests/`.

The finite default is an owner decision, not Gate P acceptance. The 500 µs whole-session target and original-target measurements remain open. BAT-02 must retain a replayable baseline and paired cost evidence; BAT-29 must qualify median/tail cost and exhaustion spikes on the target host. Shared-host measurements do not close those gates.

BAT-27/28 require identified pack/installations, calibrated bench and flight observations, temperature/environment, raw telemetry, timing, uncertainty and a held-out fit/validation split. Current/endurance targets come from [ROADMAP](../../ROADMAP.md#owners-field-kit). Loaded-voltage and LVC-time acceptance limits must be fixed before testing; the former 3% voltage suggestion is not an accepted gate. Apply `abs(error) + Uerror <= limit`; synthetic/template runs cannot close physical validation.

### 5.1 Chemistry evidence

[BAT-05](../research/battery/BAT-05/README.md) records the downloaded LiPo/HG2 sources, fits and limits. [BAT-00 and its source manifest](../research/battery/BAT-00/README.md) retain the primary references and open source checks, including datasheets needed before adding LiFePO4/NiMH templates. Use cited per-template voltage limits. Runtime temperature behavior comes from interpolated tables.

## 6. Telemetry, HUD and pilot information

### 6.1 Sensor readings

The session exposes electrical truth through `electrical_state()`. The [presentation sampler](../../app/render/overlays/battery_sensors.gd) quantizes held readings and integrates sampled current for used mAh and estimated remaining percentage; it does not read true SOC. It runs at the overlay's approximately 10 Hz refresh, even with O9 closed. A rollback restarts the presentation count.

Radio readings are not tick-synchronous, checkpointed sensor state or replay-identical log columns. Traces contain physics truth; deterministic sensor logging remains BAT-14 work. Sample rates, thresholds and resolutions are code constants, not configurable transmitter/aircraft profiles.

### 6.2 Overlay

O9 **Battery** is compact in Pilot and detailed with Telemetry visible (Full/Developer). It shows the available voltage, cell, current, power, temperature, mAh, estimated percentage and LVC readings. True SOC is in Developer Diagnostics. Legacy OCV/resistance fixtures expose fewer readings and retain their old SOC warning rule. [BAT-15](../research/battery/BAT-15/README.md) records layout checks, presentation defaults and limitations; rendered captures and pilot readability acceptance remain open.

### 6.3 Alarms

`pack_ecm` chips follow sampled loaded-cell voltage, used capacity, temperature, exhaustion and LVC. Presentation thresholds are estimates, independent of the ESC cutoff. There is no cell-mismatch/unsafe-pack alarm, connection beep or battery callout yet. A dedicated post-flight battery report is also pending; the playable slice does not include BAT-17.

## 7. BAT step register

Each BAT status lives here; numerical results stay in the dated evidence linked above. “Implemented” describes software scope only. Keep changes small and coordinate shared files with their owners.

| ID | Work | Proof/status |
| --- | --- | --- |
| BAT-00 | Ownership and decisions D1–D14 | Adopted; BAT-13 supersedes the original default-mode timing. |
| BAT-01 | Dataset licences, official datasheets and chemistry limits | Partial: LiPo/HG2 inputs and fits recorded in BAT-05; remaining chemistry/SKU source checks open. |
| BAT-02 | Frozen EL2a/Timber baseline tapes and paired cost | Open: retain exact-replay `.orfl` identities and target-host p50/p95. |
| BAT-03 | Independent ECM/thermal reference | Standard-library reference and native comparisons implemented; proposed SciPy/PyBaMM cross-check open. |
| BAT-04 | Strict formats and loader | Implemented; template metadata and branch-order rejection gaps are listed in BAT-04. |
| BAT-05 | Source-derived templates and class packs | Implemented for LiPo/HG2; model order selected by held-out residual. Additional chemistries need evidence. |
| BAT-06 | Single-motor ECM and weakest cell | Implemented; law/oracle, energy, refinement and parity evidence in BAT-10. |
| BAT-07 | Lumped thermal, temperature tables and cooling | Implemented; installation cooling and class scaling remain estimated. |
| BAT-08 | Shared N-load bus, bidirectional current and full-charge event | Planned with DR-05; require independent root/energy checks, N=1 parity and event evidence. |
| BAT-09 | Aircraft capability, pack pins and mass/inventory link | Implemented mass equality and mount checks; selection must regenerate consistent mass/CG/inertia. |
| BAT-10 | Session state, events, checkpoint, trace and log integration | Implemented; replay/lifecycle evidence in BAT-10; performance qualification open. |
| BAT-11 | Sampled ESC cell detection and LVC | Implemented modes/recovery; identified controller profiles and physical timing remain unvalidated. |
| BAT-12 | BEC/receiver rail; BAT-12b receiver packs for glow aircraft | Planned with EM-18; preserve the pack-side auxiliary-current reference and prove brownout hooks. |
| BAT-13 | Timber finite-pack variant and product mode | Implemented default/selector; FT battery scenario and retained baseline `.orfl` evidence open. |
| BAT-14 | Radio sensor/estimator/alarms | Presentation sampler implemented; tick-synchronous logging, profiles and extra alarms open. |
| BAT-15 | O9 widget, warning chips and Developer truth | Implemented; rendered captures and pilot reading open. |
| BAT-16 | Cell-count beeps and low/critical callouts | Planned with AUD; verify scenarios, mute and limiter behavior. |
| BAT-17 | Post-flight report, accident label and sensor CSV | Planned with UI/CR; include energy, peaks, LVC/alarms and later health changes; verify UI/export. |
| BAT-18 | Pack compatibility and catalog integration | Eight generated packs exist; series/bay/mass rules, refusal reasons and economy links remain planned. |
| BAT-19 | Pre-flight pack, charge and temperature selection | Planned with UI/AE; derive AUW/CG, thrust/endurance and curves from shared solvers, label estimates and test selection. |
| BAT-20 | Optional pack hangar and wear persistence | Planned; immutable session snapshot, no mid-flight hangar reads; prove replay independence. |
| BAT-21 | Stress integrals and next-session health changes | Planned, opt-in and labeled estimated: over-discharge, temperature, throughput, capacity/R/weak-cell factors. No direct C-label damage law or calibrated-aging claim. |
| BAT-22 | Full/storage-charge service actions | Planned; service/time-skip checks, no charger-electronics model. |
| BAT-23 | Economy, crash and failure links | Planned with CR/EM; reuse replace-only `lipo_damage`, price rows and venting; verify weak-cell/connector/LVC failure scenarios. |
| BAT-24 | Multirotor shared pack and FC/OSD inputs | Planned with DR, after aircraft acceptance and BAT-08; prove shared-bus energy under braking. |
| BAT-25 | Ground-vehicle pack and forward/brake/reverse ESC | Planned with RCV-08; include ambient temperature and charge-acceptance limits. |
| BAT-26 | Helicopter pack, governor and separate receiver supply | Planned with HELI; laboratory HX-700 keeps its own gates. |
| BAT-27 | Identified pack characterization card and reducer | Planned; synthetic reducer tests, then owner measurements and fixed validation limits. |
| BAT-28 | EdgeTX log reduction and endurance comparison (EL6) | Planned with VAL/FL; matched input tape, held-out measurements and uncertainty verdicts. |
| BAT-29 | Performance and physical qualification of the existing finite default | Open; target-host Gate P and owner flight acceptance. Default selection is already implemented. |

Full per-cell/parallel-string sharing, electrochemical runtime models, charger electronics, runaway physics and calendar aging stay out of scope. Any future health/damage model must preserve deterministic accepted-tick stress records and apply parameter changes between sessions. The mechanism evidence and its cell-format limits remain in BAT-00; estimated damage magnitudes do not establish calibrated aging.
