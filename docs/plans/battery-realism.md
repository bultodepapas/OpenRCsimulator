# Battery and energy-storage realism plan

**Date:** 2026-10-19. **Revision:** 2. **Status:** the minimum playable slice is software verified ([BAT-10 record](../research/battery/BAT-10/README.md)): `pack_ecm`, ESC low-voltage cutoff, Timber battery mode `pack`, O9 Battery overlay. D1–D14 were adopted as recommended (owner: "procede", [DECISIONS](../DECISIONS.md)). Physical validation, Gate P and BAT-08, 12, 16–29 remain open. **Owner:** coupled shaft / electric propulsion track (EL), physics main line. **Parent:** [electric propulsion plan](../ELECTRIC-PROPULSION-PLAN.md). **Steps:** BAT-00…29. **Dated evidence:** [BAT-00 source review](../research/battery/BAT-00/README.md).

**Owns (after BAT-00):**
- the shared battery law and the ESC battery supervisor (`app/physics/battery/`)
- `openrc-battery v1` data and generators (`app/data/batteries/`, `research/battery/`)
- battery tests (`app/tests/test_battery_*.gd`)
- evidence under `docs/research/battery/`

It takes over EL2b, the battery-facing part of EL3 (cell detection, LVC, BEC), the pack part of EL4 and EL6. EL keeps the motor, the ESC power stage (ramp, brake, freewheel, signal loss), winding/ESC thermal and EL5.

**Shared boundaries:**
- aircraft contract, schema and loader (AS)
- `flight_session.gd`, trace, checkpoint and flight log (physics main line)
- HUD overlays (HUD), audio (AUD), menus and preferences (UI)
- Workshop (AE), failures (EM), crash/economy (CR)
- Timber data (TT); multirotor (DR), ground vehicle (RCV) and helicopter (HELI) sessions

Inspect `git status` and coordinate each seam before editing it. Each of those tracks keeps ownership of its files.

## 1. Objective and definition of realism

Give every electric RC vehicle a battery that behaves like the real one: finite charge, voltage sag that grows near empty and in the cold, recovery after a load, heating, an ESC that protects the pack, telemetry a pilot would actually see, packs to choose between, and lasting consequences of abuse. The aircraft come first: the Timber, then the synthetic Stik conversions. Other vehicles enter through the shared kernel and keep their own gates.

Realism here means emergent behaviour from a small identified model, not tuning curves:
- Shorter flights at high current, colder packs that sag more, and a weak cell that trips LVC early must all **emerge** from OCV, resistance, the RC state, temperature and the cutoff.
- No Peukert exponent is applied to lithium cells. No C-rating is converted into a resistance.

| Level | Meaning | Required evidence |
| --- | --- | --- |
| Software verified | Equations, units, events, lifecycle and replay are implemented correctly | Analytic and independent oracles, energy closure, refinement order, replay, mutations, paired cost |
| Evidence constrained, experimental | Templates come from cited free data or datasheets; unsupported values are labeled `estimated` | Source register, fit report with held-out error, sensitivity, declared domain |
| Physically validated for a stated pack | Independent measurements of the flown pack and installation agree | Owner bench and flight telemetry, held-out cases, project uncertainty rule (`abs(e)+U ≤ L` pass) |

A plausible discharge curve, a familiar-looking widget or a passing replay does not confer physical validation.

## 2. Baseline and gaps

### 2.1 What exists

The rest of this plan builds on these pieces:

| Area | Current behaviour | Where |
| --- | --- | --- |
| Motor/ESC | DC-equivalent motor `Im = max((d·Vbus − E)/Rm, 0)` with an ideal motoring ESC: one quadrant, no ramp, no limit | `app/physics/electric_motor.gd` |
| Pack law | EL2a: balanced pack with `OCV(SOC)` and one resistance. Closed-form solve `Im = max((d·(OCV − R·Iaux) − E)/(Rm + d²R), 0)` | `app/physics/electric_supply.gd` |
| State | Remaining charge (C), terminal energy (J) and pack heat (J) are RK4-coupled with shaft rpm (`BATTERY_LAYOUT`) | `app/sim/flight_session.gd:67`, `:2741-2907` |
| Events | `battery_exhausted` is localised to 1e-12 s. At Q = 0 every load disconnects. **No app code consumes `events_located`.** | `app/physics/electric_battery_step.gd`, `app/sim/simulation.gd:344-349` |
| Data | `fixed_voltage` (Timber, 14.8 V) and `ocv_resistance` (synthetic 4S/6S Stik, linear OCV). Neither has a cell count or chemistry. `capabilities.energy` must equal `battery.kind`. | `app/physics/aircraft_data.gd:1129-1215`, `aircraft-contract-v2.json`, `aircraft-modules-v1.json` |
| Mass | The pack is an ordinary inventory item, unlinked to `propulsion.battery`. Timber `battery_main` is 0.33 kg, `energy_source: "lipo"`. | Timber JSON, `docs/AIRCRAFT_CONTRACT.md:96,145` |
| Trace/log | Trace v8 `BATTERY_COLUMNS`; `.orfl` stores the raw continuous block; checkpoint v6 | `app/sim/trace.gd:40-48`, `app/sim/flight_log.gd` |
| HUD | Only a "BATTERY LOW" chip, from **true SOC** < 0.2 or exhaustion. Volts and amps appear only in the legacy `--electric-demo` text line. | `app/render/overlays/telemetry.gd:20,101`, `app/main.gd:1005-1008` |
| Audio | Electric pitch follows rpm and gain follows rpm/load/throttle, so sag is audible only through rpm. | `app/audio/soundscape_model.gd:122-140` |
| Failures | `electric_drive_loss` exists. `battery.lvc`, `receiver.brownout`, `esc.thermal_derate` and EM-15/16/18/25 are planned. | `app/failures/catalog.gd:29`, [failure plan](failure-mode.md) |
| Crash/economy | Delayed LiPo venting (CR-22b), the `lipo_damage` replace-only flag, and a priced 4S 3200 pack | `app/render/crash/effects.gd`, `app/economy/inspection.gd:8`, `app/data/economy/catalog.json` |
| Workshop | No battery choice. AE-12/15/18 plan component keys, electric modules and a battery trade-off recipe. | [aircraft editor plan](aircraft-editor.md) |
| Other vehicles | Multirotor uses a first-order motor with no pack; DR-05 plans the shared-bus solve. MT8 is a fixed torque–speed line. The electric HX-700 heli is laboratory-only. | `app/physics/multirotor/powertrain.gd`, [drone plan](drone-racing.md) §4.4, [RCV plan](rc-monster-truck.md), [heli plan](helicopter.md) |
| Environment | `SimEnvironment.air(down_m).temperature_k`; the ground session always gets ISA 288.15 K | `app/sim/environment.gd:42`, `app/physics/atmosphere.gd` |
| Precedent | Glow head thermal `evaluate(source, T, T_amb, cooling_airspeed, params)`. Nitro truck fuel mass and refuel service actions. | `app/physics/glow/thermal.gd`, `app/sim/ground_vehicle/session.gd:580-629` |
| Cost | Battery route 558–562 µs/tick after EL2a-P1, against the 500 µs Gate P | [EL2a-P1](../research/propulsion/EL2a-P1/README.md) |

### 2.2 Gaps by priority

| Priority | Gap | Consequence | Correction (step) |
| --- | --- | --- | --- |
| P0 | No catalog aircraft flies a finite pack | Endless flight; no sag or end-of-flight decision | Timber pack variant (BAT-13) |
| P0 | No cell count, chemistry or per-cell limits | Cannot express LiPo vs Li-ion, cutoffs or alarms | `openrc-battery v1` and templates (BAT-04/05) |
| P0 | No ESC supervisor | The pack drains to 0 C instead of LVC: unrealistic dead-stick timing and no soft-cut warning | BAT-11 |
| P0 | The HUD warns on true SOC | Pilots see information no real radio provides | Observable telemetry and alarms (BAT-14/15) |
| P1 | No polarisation state | No sag-then-recovery after a punch-out; voltage alarms behave wrongly | 1-RC ECM (BAT-06) |
| P1 | No temperature | Cold/hot days and heating under load do not change sag | Lumped thermal and R0(T) (BAT-07) |
| P1 | Pack mass/CG not linked to the pack | Changing packs cannot move CG or change AUW | Contract link (BAT-09) |
| P1 | No weakest cell | Min-cell telemetry, early LVC and per-cell damage are impossible | Average + weakest cell (BAT-06) |
| P2 | No health, persistence or damage | Abuse has no consequence; every flight starts with a new pack | BAT-20/21 |
| P2 | No bidirectional current | Drone braking and car regen cannot be expressed | BAT-08, BAT-24/25 |
| P2 | No BEC/receiver rail | Brownout cascades cannot be modelled | BAT-12 with EM-18 |

## 3. Design principles

1. **Truth and observation are separate.**
   - The physics state holds true charge, polarisation and temperature.
   - Everything the pilot sees passes through a declared sensor or estimator: pack voltage, current, consumed mAh, cell voltage and an estimated remaining %.
   - True SOC appears only in the developer overlay and in traces.
2. **One source of truth for numbers.** Pre-flight endurance, thrust and AUW estimates call the same laws and the existing equilibrium/trim tools (EL1c). They never use a separate formula.
3. **Effects emerge.**
   - Rate-dependent usable capacity comes from R0 + RC + cutoff.
   - Cold loss comes from R0(T). Coulombic capacity is independent of temperature unless a fit residual proves otherwise (BAT-00 F10).
   - Weak-cell behaviour comes from that cell's own capacity and resistance factors.
4. **Data tiers, never hand-authored curves** (AGENTS: do not create what can be freely downloaded):

   | Tier | Source | Example |
   | --- | --- | --- |
   | A, measured | Fit of a free dataset, or of the owner's pack | Galeotti LiPo; Kollmeyer HG2 |
   | B, datasheet | Tremblay three-point fit, or a manufacturer discharge curve | Molicel P42A |
   | C, class template | A tier A/B cell scaled to a pack class, labeled `estimated` | "4S 3200 30C class" |

   Generators emit every curve with input hashes. Generated JSON is never edited.
5. **Existing behaviour is preserved.**
   - Non-electric aircraft stay byte-identical.
   - `fixed_voltage` and `ocv_resistance` keep their laws, formats and replay identity.
   - The new behaviour is a new battery kind, `pack_ecm`.
6. **The kernel stays generic.** Battery state lives in the session's continuous block, and discrete supervisor state lives in session-owned modes. No vehicle branches are added to `simulation.gd` (AGENTS).
7. **Every new state follows the full lifecycle:** layout, reset, checkpoint, restore, replay, rollback, trace and flight log, in one change (`docs/AIRCRAFT_CONTRACT.md:151`).
8. **Measured cost.** Each runtime step reports paired per-tick cost against the frozen BAT-02 baseline (Gate P).

## 4. Physical model

### 4.1 Cell and pack equivalent circuit (Thevenin, 0–2 RC branches)

These equations describe the pack, its cells and its losses:

```text
z        = cell state of charge, from coulomb counting of total pack current
i_c      = I_pack / m_P                       (equal sharing in each parallel group)
v_k'     = i_c / C_k − v_k / (R_k·C_k)        k = 1..n_RC   (n_RC ∈ {0,1,2}; default 1)
v_cell   = OCV(z, T) − Σ v_k − R0(z, T)·i_c
V_pack   = Σ_series v_cell − R_w·I_pack       (R_w: wires, connector, measured or estimated)
Q_rem'   = −I_pack                            (one charge state per series string)
E_term'  = V_pack·I_pack ;  H'  = I_pack²·(R0_pack + R_w) + Σ_cells Σ_k v_k²/R_k
```

- **Energy closure test:** `OCV·I = V·I + I²R0 + Σ v_k²/R_k + d/dt(Σ ½·C_k·v_k²)` per cell, and summed over the pack.
- **Closed form preserved.** `v_k` and `T` are states, so the stage solve keeps EL2a's form. Replace `OCV` with `OCV_pack − Σ_series Σ_k v_k` and `R` with `R0_pack + R_w`. There is no algebraic loop and no iteration.
- **Tables.** OCV, R0, R_k and τ_k are bilinear in (z, T) on generated knots. Use linear lookup by default; PCHIP is allowed only inside monotone segments (EL1a-R2 #09). Reject non-positive V or R.
- **Domain.** The OCV table runs from the template's data floor (z = 0) to full charge. Rated capacity is defined at the manufacturer cutoff, so z at rated-empty is > 0 and declared. Below the data floor nothing is extrapolated: the existing exhaustion event fires, the pack is disconnected, and the stress record marks the domain exit (§4.6).
- **Hysteresis.** OCV charge/discharge hysteresis stays off. Suti 2022 found about 5 mV. Admit it only if a held-out residual requires it.

### 4.2 Pack topology and the weakest cell (decision D3)

The pack is modelled as `n_S − 1` average cells plus one weakest cell. Both carry the same series current, so one charge state serves both:

```text
z_avg = z0 − Q_used/(3600·Q_cell)          z_weak = z0 − Δz0 − Q_used/(3600·f_Q·Q_cell)
R0_weak = f_R·R0 ;  RC branches duplicated for the weak cell ;  shared pack temperature T
```

- **Exhaustion event:** locate it on the **weak cell's** remaining charge. It reaches zero first, and the existing single-index event protocol is unchanged.
- **Cost:** `n_RC` extra states for the weak cell, instead of `n_S·(1 + n_RC)` for a full per-cell model.
- **What it gives:** realistic min-cell telemetry (EdgeTX "Lowest"), early LVC on aged packs, and per-cell over-discharge damage.
- **Defaults:** a balanced pack is `f_Q = f_R = 1, Δz0 = 0`. Spread comes from the hangar's health record (§7) or a failure scenario (EM).
- **Parallel groups:** `m_P` is lumped and balanced. Per-parallel-string current sharing is out of scope.

### 4.3 Temperature (lumped)

```text
m_p·c_p·T' = H' − hA(v_cool)·(T − T_amb) ;   T_amb = SimEnvironment.air(down).temperature_k
R(T) = table(T) from data; fallback R_ref·exp(Ea/R_g·(1/T − 1/T_ref)), Ea labeled `estimated`
hA(v) = hA0 + hA1·sqrt(max(v_cool, 0))  (installation-specific: bay airflow, `estimated` until measured)
```

- Initial `T` is a session input: ambient, "warmed", "left in the sun" or a measured value.
- The entropic heat term is omitted and declared.
- The glow `thermal.gd` signature is the interface precedent.
- ESC and winding thermal remain EL4.
- The thermal time constant is minutes, so the state is non-stiff at 240 Hz.

### 4.4 Bus solve

| Case | Solve | Step |
| --- | --- | --- |
| One motor, motoring | EL2a closed form with ECM substitutions | BAT-06 |
| N motors on one pack (multirotor) | Active-set closed form `V·(1 + R·Σd_i²/R_m) = E_oc − R·I_aux + R·Σd_i·E_i/R_m`, ≤ N passes ([drone plan](drone-racing.md) §4.4) | BAT-08, with DR-05 |
| Bidirectional (synchronous ESC, braking, regen) | Same linear branch without the `max(·,0)` clamp. Negative pack current is allowed up to a charge-acceptance limit. A full-charge boundary event replaces "charge never increases" in the step policy. | BAT-08 |

`electric_battery_step.gd` currently refuses a positive charge derivative. BAT-08 generalises it under SF-04b rules: nest the stop locator, use the shared bracket proposer, never split a policy tick. Aircraft ESCs stay one-quadrant unless an identified ESC proves regeneration (EL1a-R1 01: call a mode regenerative only when measured pack power is negative).

### 4.5 ESC battery supervisor (sampled, deterministic)

Real ESCs and flight controllers make battery decisions as sampled controllers. Model them that way:
- Evaluate at accepted tick boundaries from committed state.
- Keep the state in session-owned modes, included in checkpoint identity.
- Do not localise inside RK. The sampling phase is part of the model (EL1a-R1 04).

| Function | Behaviour | Data (per ESC profile, with provenance) |
| --- | --- | --- |
| Cell detection | At connection, `n = rule(V_pack)`. The rule is per profile: ceiling of `V/v_detect`, or fixed. Misdetection (for example a deeply discharged pack) is a real outcome, not a bug. | Avian: auto/fixed. Betaflight: 4.30 V max-cell rule. Hobbywing: "3.7 V/cell" rule. |
| Voltage sense | `v_s` = sampled `V_pack`, with an optional first-order filter | Filter τ is `estimated` until benched |
| LVC | Threshold `n·v_cut`. **Soft:** the output limit ramps to `L_soft` over `T_soft` after a debounce. **Hard:** limit 0. **Off:** none. Effective duty = `min(duty, limit)`. | Avian 2.8–3.8 V/cell, soft 50 % over 3 s (60 % in troubleshooting). Hobbywing off/2.8/3.0/3.4, 60 % in 3 s. |
| Recovery | Per profile: latch until the throttle returns to idle, voltage hysteresis, or none | Unknown for Avian; D8 default is labeled `estimated` |
| Alarm vs cutoff | The transmitter alarm (Timber manual: 3.4 V/cell) is presentation (BAT-14), never the ESC threshold | EL1a-R1 06 |
| BEC rail | `I_aux = I_rx + Σ I_servo(activity)` referred to the pack side. BEC dropout produces a `rail_low` signal, consumed by EM-18 brownout. | Receiver minimum, e.g. AR410 3.5 V (EM-00 R02); servo currents from the Savox catalog where sourced |

Startup ramp, brake, freewheel and signal-loss cut stay with EL3. The supervisor only bounds duty.

### 4.6 Health, stress and damage (decisions D5, D6)

During flight the session accumulates deterministic **stress integrals** at accepted ticks. They are checkpointed and derived from the state trajectory, so replay reproduces them:

| Stress | Measure | Effect on the pack record (applied at session end) | Evidence basis |
| --- | --- | --- | --- |
| Mild over-discharge | Time and depth of the weak cell's rested-equivalent OCV below the chemistry's recommended minimum | Small capacity loss and R0 growth | `estimated` magnitudes; labeled |
| Severe over-discharge | Weak cell past the template data floor, or LVC off and the cell driven below the damage floor | Large loss. The pack is flagged **unsafe: do not charge, retire.** Fire risk is shown only as safety text. | Mechanism-anchored threshold (Guo 2016, Cu dissolution beyond about −12 % SOC); cell format differs |
| Over-temperature | ∫ of `T` above the SKU limit | Accelerated fade and a "swelling" flag above the hard limit | `estimated`; the SKU limit is cited |
| High current | No direct damage law | Acts through heating only. The C label never limits or damages directly. | EL1a-R1 05 rule |
| Cycling | Equivalent full cycles = Ah throughput / capacity | Optional slow fade and R growth curve (D6) | `estimated`; a fitted aging law needs data |
| Crash puncture | CR severity on the pack's inventory item | `lipo_damage` → replace-only (existing), plus venting presentation (CR-22b) | Existing CR decision |

- Damage changes the **next** session's pack parameters: capacity factor, R factor, weak-cell factors and the unsafe flag. Within a flight, physics follows only the continuous state. This keeps a session self-contained and replayable.
- Every damage function is opt-in and labeled `estimated`. The plan claims consequence, not calibrated aging.
- The UI carries real safety guidance: storage charge, never below cutoff, retire swollen packs.

### 4.7 Out of scope

These are excluded until the evidence named here exists:
- electrochemical (P2D/SPM) runtime models (PyBaMM stays offline)
- per-parallel-string sharing
- charger electronics
- self-heating runaway physics
- gas swelling geometry
- calendar aging without data
- ESC MOSFET losses (EL)
- any use of manufacturer C-rating as resistance
- copying a paper's fitted coefficients as a specific pack's data (EL1a-R1)

## 5. Chemistry and data

### 5.1 Chemistry register (per cell)

These are class conventions. BAT-01 replaces each with cited per-SKU values before any template uses it. Unsourced cells are marked †.

| Chemistry | Full (V) | Nominal (V) | Typical cutoff (V, loaded) | Character | Main RC use |
| --- | --- | --- | --- | --- | --- |
| LiPo (pouch) | 4.20 | 3.7 | 3.0–3.5 (ESC options 2.8–3.8) | High rate, low R, moderate Wh/kg | Planes, quads, cars |
| LiHV | 4.35 (MultiGP cap) | 3.8† | as LiPo | Higher energy; can be misdetected or overcharged on LiPo settings | Racing quads, sport planes |
| Li-ion 18650/21700 (NMC/NCA) | 4.20 | 3.6 | 2.5–3.0 (P42A: 2.5) | High Wh/kg, higher R and sag, lower burst | Long-range planes and quads, gliders |
| LiFePO4 ("LiFe") | 3.6†–3.65† | 3.2†–3.3† | 2.5†–2.8† | Very flat OCV, so voltage-based % is unreliable | Receiver/ignition packs |
| NiMH | ~1.4† charged | 1.2 | 0.9†–1.0† | Flat curve; Tremblay template exists | Receiver packs, older cars |

The flat LiFePO4/NiMH curves are why the radio-side % estimator (BAT-14) must be mAh-based for those chemistries. That is a real-world lesson the HUD should reproduce.

### 5.2 `openrc-battery v1` (sketch; field names fixed in BAT-04)

```json
{
  "format": "openrc-battery v1",
  "id": "lipo-4s1p-3200-c30-class",
  "display_name": "4S 3200 mAh LiPo (30C class)",
  "chemistry": "lipo",
  "topology": {"series": 4, "parallel": 1},
  "cell_template": {"id": "lipo-pouch-class-v1", "sha256": "…"},
  "rated_capacity_ah": {"value": 3.2, "unit": "Ah", "kind": "manual", "source": "…"},
  "mass_kg": {"value": 0.33, "unit": "kg", "kind": "derived", "source": "Timber manual 2.190 − 1.860 kg"},
  "dimensions_m": {"…": "box for inertia and bay fit"},
  "c_rating_label": {"continuous": 30, "kind": "manual", "source": "label only; never a resistance or limit"},
  "interconnect_resistance_ohm": {"value": 0.002, "unit": "ohm", "kind": "estimated", "source": "…"},
  "limits_per_cell": {"v_max": "…", "v_min_recommended": "…", "v_damage_floor": "…", "t_max_k": "…"},
  "measured_ir_ohm": null
}
```

- A cell template (`openrc-cell-template v1`) carries the knots, the OCV/R0/RC tables, thermal mass, data domain, generator path and input hashes.
- Template resistance is normalised to a reference capacity. Scaling to a pack's capacity (`R ∝ 1/Q` within one cell family) is `derived`, and a measured pack IR replaces it.
- Every quantity uses `{value, unit, kind, source}`, and invalid data cannot fly (AGENTS).

### 5.3 Aircraft contract extension (BAT-09)

The new battery kind `pack_ecm`, with `capabilities.energy: "pack_ecm"`:

```json
"battery": {
  "kind": "pack_ecm",
  "default_pack": "lipo-4s1p-3200-c30-class",
  "compatible": {"series": [3, 4], "max_mass_kg": {"…": "…"}, "bay_m": {"…": "…"}},
  "mount": {"inventory_key": "battery_main", "position_m": {"…": "…"}},
  "esc_supervisor": "avian-70a-class-v1",
  "auxiliary": {"receiver_a": {"…": "…"}, "servo_model": "…"}
}
```

- Pack mass and box inertia **replace** the mounted inventory item's mass when a pack is selected, which changes CG and AUW. Pack mass is constant during discharge, which is physically correct for lithium; no mass state is needed.
- Initial SOC, temperature and health are **session inputs** (pack definitions stay immutable, EL1a-R2 #05). The aircraft file has none.
- Admission follows `docs/AIRCRAFT_CONTRACT.md:109`: a conditional module, a consumer, provenance, complete lifecycle state, a versioned schema and an analytic test. Battery temperature and BEC move from "rejected" to "admitted under `pack_ecm`".
- Files to change (from the integration map):
  - `aircraft_data.gd` `_electric_battery`
  - `aircraft-contract-v2.json` and `aircraft-modules-v1.json`
  - `research/aircraft-standardization/build_schema.py:382`, then regenerate the v2 schema
  - `propulsion.gd:92-112`, `failures/catalog.gd:199`, `trace.gd:658`
  - contract/module tests and the Python schema checks

## 6. Telemetry, HUD and pilot information

### 6.1 Telemetry snapshot and sensor emulation (BAT-14)

The session publishes a read-only, committed-tick `battery_telemetry()`:
- true values: V, I, P, Q_used, z_avg, z_weak, T, LVC state, detected cells, rail voltage
- the event list, consuming `events_located`

A pure sensor layer then turns it into what a radio would show:

| Displayed | EdgeTX analogue | Emulation |
| --- | --- | --- |
| Pack voltage | VFAS / RxBt-style | Sample rate, resolution and latency per telemetry profile |
| Current | Curr | Same, plus optional calibration error (default 0) |
| Used mAh | Fuel (consumption) | The sensor integrates its own current samples, so it is not the true Q |
| Cell average / lowest | Cels → calculated `Cell`, index Lowest | Lowest needs a cell sensor (Smart/FLVSS-like); otherwise only the average |
| Remaining % | Radio-side estimate | mAh-based by default; voltage-based with R compensation (PX4-style) as an option. **Never true SOC.** |
| Pack temperature | Tmp1 | Only if the profile declares a sensor |

Emulated values are logged next to the truth in trace and `.orfl`. Simulated flights and the owner's EdgeTX logs can then be compared column by column (BAT-28).

### 6.2 Battery overlay (BAT-15, HUD-owned implementation)

This is a new overlay, **O9 "Battery"**, because O1–O8 are taken. The drone plan's OSD also claims O8, so the HUD owner must renumber one of the two (D12). There are two layouts. Compact goes in the Pilot preset; detailed goes in Full.

```text
┌ BATTERY · 4S 3200 LiPo ───────── LVC ┐   compact (Pilot)
│ 14.62 V   3.66 V/c   min 3.61        │   14.6 V · 38 A · 1874 mAh · 41 %
│ 38.4 A    561 W      31 °C           │
│ 1874 / 3200 mAh  ███████░░░░  41 %   │
│ V ╲__╱‾╲_  A _╱‾╲__   last 60 s      │
└──────────────────────────────────────┘
```

- The sparkline uses Godot's `CanvasItem.draw_polyline`; no chart add-on is needed.
- Refresh at 10 Hz, matching the existing overlays. Spanish strings go in `es.po`.
- The current true-SOC "BATTERY LOW" chip is replaced by observable alarms. True SOC moves to the Developer overlay.
- The existing pre-flight Transmitter overlay can show a telemetry page; coordinate with HUD.

### 6.3 Alarms (BAT-14 logic, BAT-15/16 presentation)

These are configurable like a transmitter, with defaults from the aircraft's telemetry profile:
- per-cell warning and critical thresholds on the **loaded** sensor voltage, with debounce. A sag-induced alarm during a punch-out is realistic and intended.
- used-mAh percentage (for example 80 %)
- pack temperature
- LVC active
- detected-cell mismatch at connection
- "pack damaged/unsafe" before flight

The audio cues (AUD) are:
- ESC cell-count beeps at connection (the pilot's real cue for misdetection)
- a low/critical voice-style callout
- the soft cut, audible through rpm

### 6.4 Post-flight report and logs (BAT-17)

The debrief and the accident report get a battery section:
- used mAh and Wh, min/avg loaded and rested voltage, peak current and power, peak temperature
- LVC events with times, alarms raised
- stress incurred, and the health change applied to the pack record

CSV export and plots use the existing flight-log tools and free plotters; no new plotting tool is written. `accident_report.gd` gains a `battery_main` label.

## 7. Battery options, persistence and economy

- **Catalog (BAT-18).** `app/data/batteries/` is generated from templates. It covers 3S/4S/6S LiPo in several capacities and C classes, LiHV, Li-ion 4S1P/4S2P 21700, and LiFe/NiMH receiver packs. Names are brand-neutral class packs (D10). A real SKU enters only with sourced data and an economy price row; the existing `spektrum_spmx324s50` product row is the first candidate.
- **Compatibility.** The aircraft declares the series range (from the ESC: Avian 3S–6S; Timber manual 3S/4S, 2200–5000 mAh), the bay box and the maximum mass. Incompatible packs are refused with a reason.
- **Battery mode (BAT-13, delivered).** The finite pack is the default (owner decision 2026-10-19). Home shows "Battery: finite pack / ideal" inside the flight details for catalog aircraft with `battery_data`; direct routes accept `--battery=ideal|pack`. The collapsed flight card has no spare height (`test_ui_home`).
- **Pre-flight selection (BAT-19, UI-owned screen).** The pilot picks a pack, a charge state (full, storage, a custom %, or "as left"), a temperature and, with wear enabled, a pack from the hangar. The screen shows:
  - AUW, wing loading and CG shift
  - static thrust at full and at storage charge
  - estimated flight time for a declared mixed profile

  All estimates come from the shared laws and are labeled as estimates. Discharge curves for the chosen pack at 1C/5C/15C and at two temperatures are **generated from the model**, never drawn by hand.
- **Hangar (BAT-20).** An optional persistent per-pack record: identifier, template, cycles, capacity and R factors, weak-cell factors, last charge state and time, flags and history. The session copies an immutable snapshot at start, so replay never depends on later hangar edits. Service actions (charge to full/storage, swap pack) follow the nitro refuel precedent.
- **Economy and crash (BAT-23).** Retiring a pack costs its catalog price. A puncture uses the existing `lipo_damage` and venting. The inspection report lists pack health.

## 8. Other vehicles (after aircraft acceptance)

| Vehicle | Integration | Owner coordination |
| --- | --- | --- |
| Multirotor (BAT-24) | One pack, four ESCs, active-set bus solve. `synchronous` ESC with negative pack current. Betaflight-style cell detection, `vbat_sag_compensation` as an FC input (DR). OSD fields from §6.1. | DR-05/12/31/40; DR keeps the plant and FC |
| RC ground vehicle (BAT-25) | Replaces MT8's estimated torque line under RCV-08: forward/brake/reverse ESC modes, optional regen within charge acceptance, 2S–6S packs. The ground session needs real ambient temperature. | RCV-08; MT8 data via `build_vehicle_data.py` |
| Electric helicopter (BAT-26) | 12S pack, `governor` ESC kind, BEC kept separate from the motor bus (HELI rule) | HELI-36a/35; HX-700 stays laboratory-only until its gates |
| Receiver packs for glow/gas aircraft (BAT-12b) | Small LiFe/NiMH pack on the BEC/rail model; depletion leads to EM-18 brownout | EM, NITRO, aircraft owners; opt-in (D14) |

## 9. Numerics, state, events and performance

- **Continuous block** for `pack_ecm`: `rpm, Q_rem_weak, E_term, H, v_1..n (avg), v_1..n (weak), T`. For `n_RC = 1` that is three states beyond EL2a. Update every hard-coded size: `_battery_values_valid`, `_coupled_rpm`, `wheel_state_layout`, `trace.gd:639-643`, and the layout string and configuration hash.
- **Discrete block** (modes, tick-boundary): detected cells, LVC phase, timer and limit, filtered voltage, and the stress accumulators. Extend the modes size check at `flight_session.gd:3424`.
- **Stiffness:** τ_RC ≥ ~1 s and τ_thermal ~ minutes, so `|λ·dt| ≤ 0.005` at 240 Hz. Extend the launch guard `_electric_step_supported` with the RC term and reject templates whose smallest τ breaks it.
- **Events:** keep one located charge boundary, now on the weak cell. Add the full-charge boundary only for bidirectional ESCs (BAT-08). LVC is sampled, never located. Simultaneous-root priority follows the physics audit (rotor stop first).
- **Formats:** checkpoint `openrc-flight-checkpoint v6` with `electric_law` `electric-pack-ecm-coupled-events-v1` (v7 already names the collision-world boundary) and `openrc-trace v13`; existing readers unchanged. The model hash covers the pack and template tables and their SHA-256 pins.
- **Cost:**
  - Use the compact stage path with no Dictionary allocation per stage.
  - Cache the table segment per tick; SOC moves by less than 1e-4 per tick.
  - Budget: the median per-tick increase is ≤ 5 % over the BAT-02 frozen `ocv_resistance` route, measured paired on the same host. The battery-exhaustion spike must not regress (EL2a-P2).

## 10. Verification and validation

**Software:**
- **Known answers.**
  - Constant-current 1-RC: `v_1(t) = I·R_1·(1 − e^{−t/τ})`.
  - Linear-OCV discharge: closed form.
  - Thermal steady state: `T = T_amb + P/hA`.
  - Arrhenius ratio.
  - LVC soft ramp reaches `L_soft` ± 1 % at `T_soft`.
  - Cell detection over a voltage sweep.
- **Independent oracles.**
  - A Python ECM integrated with SciPy DOP853/Radau, with NumPy 1.26.4 / SciPy 1.11.4 pinned as in EL1a-R2.
  - A second cross-check with PyBaMM's Thevenin model (BSD-3, exact version pinned in BAT-03) on identical parameters.
- **Parity.** `pack_ecm` with `n_RC = 0`, isothermal, balanced and a 1S-equivalent mapping reproduces the `ocv_resistance` trajectory and events within 1e-12 relative. Existing fixtures and the non-electric fleet stay byte-identical.
- **Properties.** A new battery property set for the law harness (`app/tests/law_properties.gd` signature does not fit):
  - energy closure
  - passivity (no energy creation)
  - voltage monotone in current and in SOC
  - SOC monotone under discharge
  - table continuity
  - refinement ratio approaching 16
- **Lifecycle.** Exact replay, checkpoint/restore across LVC and ramp states, rollback, two-session isolation (EL1a-R2 #05), and mutations on disposable copies (AGENTS).
- **Product.** Real-keyboard UI tests for selection and alarms, plus Xvfb captures at 640 px and 1080p (HUD pitfalls).

**Physical (owner field kit, extends ROADMAP §Owner's field kit):**
1. A pack card (BAT-27): weigh and measure the pack. Charger discharge logs at about 1C and the highest safe rate, to the cutoff. A rested OCV ladder (10 % steps with 30 min rests, after Galeotti/Suti). Charger IR readings per cell. Ambient and pack temperature. Reducer: `research/battery/bat-27/reduce_pack.py`.
2. Flight telemetry (BAT-28): EdgeTX SD logs of VFAS/Curr/Fuel/Cels/RPM on an electric aircraft, with the throttle tape replayed through the flight-logging workflow.
3. Acceptance uses the project uncertainty rule:
   - loaded-voltage error over held-out flights, with a target to fix in BAT-27 (proposed 3 % above 20 % SOC)
   - endurance to LVC ±15 % (ROADMAP EL6)
   - LVC trip time
   - current ±10 % (EL5)

Synthetic or template packs never count as measurements.

## 11. Step register

Each row is one small, reviewable change with its proof. Steps marked **Delivered** are software verified on 2026-10-19 ([BAT-10 record](../research/battery/BAT-10/README.md)); all others are planned.

| ID | Work | Proof | Coordination |
| --- | --- | --- | --- |
| **Phase A: foundation (no runtime change)** | | | |
| BAT-00 | Owner decisions D1–D14. Registry row and prefix in `docs/README.md`. EL plan rows EL2b/3/4/6 point to BAT. DECISIONS entry. Source review ([BAT-00](../research/battery/BAT-00/README.md), done 2026-10-19). | **Delivered**: decisions in DECISIONS, registry row, EL rows point here | EL, docs owners |
| BAT-01 | Source/dataset record: download the Galeotti and Kollmeyer data and the official Molicel/LiFe/NiMH datasheets; record licences; cite every chemistry-table value; list dead ends | Partly delivered: Galeotti (109 files) and HG2 (44 files) downloaded and hash-checked ([BAT-05](../research/battery/BAT-05/README.md)); official datasheets and the §5.1 citations open | research-sources rule |
| BAT-02 | Freeze the baseline: copy the EL2a supply/step for parity, baseline `.orfl` of the 4S/6S battery routes and Timber, paired cost baseline | Exact replay, hashes, p50/p95 µs | FL, Gate P |
| BAT-03 | Offline reference: Python ECM/thermal oracle and PyBaMM cross-check, pinned | **Delivered**: `research/battery/ecm_reference.py`, 19 tests, 5 mutations caught; runtime agreement 2.7e-15 (BAT-06 probe) | — |
| **Phase B: pure laws** | | | |
| BAT-04 | `openrc-battery v1` and `openrc-cell-template v1` schemas plus a strict loader | **Delivered**: [spec](../research/battery/BAT-04/specification.md), `battery_data.gd`, `test_battery_data.gd` 52/0 | AS review |
| BAT-05 | Generators `research/battery/bat-05/`: dataset/datasheet → templates (LiPo tier A, Li-ion tier A, Tremblay tier B; LiFe/NiMH optional), 0/1/2-RC comparison | **Delivered**: LiPo K1 and HG2 K2 by held-out residual, 2 templates, 8 packs ([BAT-05](../research/battery/BAT-05/README.md)) | — |
| BAT-06 | ECM cell/pack law, weakest cell, closed-form single-motor solve | **Delivered**: `test_battery_pack_ecm.gd` 84/0, EL2a parity 1e-12, oracle 1 200 cases | EL |
| BAT-07 | Lumped thermal, R0(T), ambient input, cooling term | **Delivered**: lumped T, (SOC, T) tables, √v forced convection; steady-state test | ATM |
| BAT-08 | N-load active-set solve, bidirectional branch, full-charge event in the step policy | Brute-force root to 1e-12; N = 1 byte-identical; event tests | DR-05, SF |
| **Phase C: aircraft integration** | | | |
| BAT-09 | Contract kind `pack_ecm`: modules, schema regeneration, pack mass/inertia → inventory and CG | **Delivered**: contract, modules, schema, register, mount check; pack mass equals the mounted item | AS, AE-12 |
| BAT-10 | Session integration: continuous block, step policy, checkpoint v6 with the `pack_ecm` law, trace v13, flight log, consumed events, launch guard | **Delivered** (cost under shared load only): `test_battery_session.gd` 43/0, existing electric suites unchanged; Gate P open | Physics main line, FL |
| BAT-11 | ESC supervisor: detection, LVC off/soft/hard, recovery, profiles (Avian-class, Hobbywing-class) | **Delivered**: `test_battery_esc_supervisor.gd` 36/0; soft cut in flight | EL3 |
| BAT-12 | Auxiliary/BEC rail and `rail_low` signal. BAT-12b: receiver packs for glow aircraft (opt-in) | Current-plane tests (pack-side reference); EM hook test | EM-18, SAV |
| BAT-13 | Timber `pack_ecm` variant via the TT pipeline (fixed-voltage variant kept). FT card battery/endurance scenario. | **Delivered** without FT/`.orfl` evidence: TT-07 variant, catalog `battery_data`, Home/CLI mode; FT battery card open | TT, FT |
| **Phase D: pilot information** | | | |
| BAT-14 | Telemetry snapshot, sensor emulation, radio-side estimator, alarm logic (pure) | **Delivered** without logging ([BAT-15](../research/battery/BAT-15/README.md)): sensors, radio-side %, alarms | HUD |
| BAT-15 | O9 Battery overlay (compact/detailed), alarm chips, Developer true-SOC, i18n | **Delivered** without captures: O9 overlay, 133 checks, live `pack_ecm` flight | HUD, UI |
| BAT-16 | Audio cues: cell-count beeps, low/critical callouts | Bench scenario; mute/limiter rules respected | AUD |
| BAT-17 | Post-flight battery report, accident-report label, CSV columns | UI tests; capture | UI, CR |
| **Phase E: choice, persistence, health** | | | |
| BAT-18 | Generated pack catalog and compatibility rules | Generator `--check`; refusal reasons tested | Economy |
| BAT-19 | Pre-flight battery screen with model-derived estimates and curves | Real-keyboard UI tests; estimate equals solver output | UI, AE-15 |
| BAT-20 | Pack hangar persistence, session snapshot, service actions | Persistence and replay-independence tests | UI app_state |
| BAT-21 | Stress integrals and health update at session end; unsafe flag | Scenario tests per band; labels present | CR |
| BAT-22 | Charging/storage between flights (decision D11) | Time-skip tests | UI |
| BAT-23 | Economy, crash and failure links: weak cell, connector resistance, LVC misconfiguration | Economy/failure tests | CR, EM-15/16/25 |
| **Phase F: other vehicles** | | | |
| BAT-24 | Multirotor pack with synchronous ESCs, FC battery inputs, OSD feed | DR-05 proofs; energy closure with braking | DR |
| BAT-25 | Ground-vehicle electric powertrain under RCV-08 | RCV gates; regen limits | RCV |
| BAT-26 | Electric helicopter pack and governor ESC | HELI-36a gates | HELI |
| **Phase G: validation and promotion** | | | |
| BAT-27 | Pack characterisation card and reducer | Reducer tests (synthetic, then owner data) | VAL |
| BAT-28 | EdgeTX log reducer and flight comparison; EL6 endurance closure | Uncertainty-rule verdicts | VAL, FL |
| BAT-29 | Gate P qualification; promote `pack_ecm` to the default for catalog electric aircraft | p50/p95 on the target host; owner flight | Gate P, ROADMAP |

**Minimum playable slice:** BAT-00…06, then BAT-09, 10, 11, 13, 14 and 15. Result: the Timber flies a 4S LiPo class pack with sag and recovery, soft LVC, a battery widget, mAh and min-cell telemetry, and a post-flight summary. Wear stays off. Thermal (BAT-07), choice (BAT-18/19) and health (BAT-20/21) follow.

## 12. Owner decisions

| ID | Question | Recommendation |
| --- | --- | --- |
| D1 | Make BAT a subplan of EL that takes over EL2b, the battery side of EL3, the pack side of EL4, and EL6? | Yes; EL keeps motor, power stage and EL5 |
| D2 | Default model order | 1 RC. Allow 2 per template only if the held-out residual justifies it; 0 for parity. |
| D3 | Cell representation | Average + weakest cell. Per-cell only if a measured imbalance case needs it. |
| D4 | Realism exposure | Decided by the owner 2026-10-19: the finite pack is the default wherever an aircraft has `battery_data`; ideal stays selectable (Home flight details, `--battery=ideal`). Wear remains opt-in when BAT-20/21 land. |
| D5 | Persistent pack health | Yes, opt-in with wear; immutable session snapshot |
| D6 | Accept labeled `estimated` damage magnitudes? | Yes, opt-in. Only the severe band claims a mechanism source. |
| D7 | LVC defaults | Aircraft ESC-profile defaults, editable within the profile's documented options |
| D8 | Recovery when undocumented | Latch until throttle idle, labeled `estimated`, until benched |
| D9 | Telemetry naming | Plain labels in the HUD; EdgeTX names in log columns and tooltips |
| D10 | Pack names | Brand-neutral classes; real SKUs only with sourced data and a price row |
| D11 | Charging between flights | Service actions only (full/storage), no charger model |
| D12 | Overlay ID | O9 Battery; HUD owner resolves the DR "O8 OSD" collision |
| D13 | Vehicle order after aircraft | DR → RCV → HELI |
| D14 | Receiver packs on glow aircraft | After BAT-12, opt-in, with EM-18 |

## 13. Risks

| Risk | Mitigation |
| --- | --- |
| Gate P: the battery route is already above 500 µs | Compact path, segment caching, per-step paired budget; promotion only at BAT-29 |
| Identifiability: R vs rotor inertia vs RC from speed-only data (EL1a-R2 #12) | Independent IR and pulse/recovery data in BAT-27; parameter intervals reported |
| Template realism mistaken for a specific pack | Tier labels in data, UI and reports; "class" in every name |
| Damage model teaching wrong practice | Conservative bands, explicit safety text, opt-in wear |
| Replay depending on persistent state | Session snapshot; hangar never read mid-session |
| Hot shared files (`flight_session.gd`, `trace.gd`, `main.gd`) edited by parallel tracks | Small steps, `git status` first, stage only own hunks |
| Licence or trademark exposure | Brand-neutral names; datasets kept local unless CC BY; GPL code never copied |
| HUD clutter | Compact layout in Pilot, detailed in Full; owner reading (HUD-12-style) |

## 14. Sources

- [BAT-00 source review](../research/battery/BAT-00/README.md) and [manifest](../research/battery/BAT-00/sources.json): Tremblay & Dessaint 2009, Guo 2016, Saha 2011, Nyangweso & Bole 2014, Galeotti 2023, PX4/Betaflight/EdgeTX behaviour references, Molicel P42A, UAF cold-temperature thesis.
- [EL1a-R1 battery and ESC investigations](../research/propulsion/EL1a-R1/02-battery.md) (Suti 2022, Di Nisio 2023, Avian/Timber LVC) and [motor/ESC](../research/propulsion/EL1a-R1/01-motor-esc.md).
- [EL1a-R2 numerics and identifiability](../research/propulsion/EL1a-R2/README.md); [EL2a delivery and performance](../research/propulsion/EL2a/README.md).
- [Roadmap investigation 05](../research/roadmap-investigations/05-propulsion-engines-motors.md) (battery ladder B0–B3, Hobbywing LVC, CRRCSim/PyBaMM notes).
- [DR-01 battery notes](../research/drone-racing/DR-01/README.md) (Bauersfeld & Scaramuzza, racing pack resistance, class limits).
- [Timber reference](../research/propulsion/EL1a/timber-reference.md) (4S 3200 class, 330/340 g).
