# Fuel, mass and balance plan

**Date:** 2026-10-19. **Status:** active. FUEL-00, FUEL-01, FUEL-02 and FUEL-04 delivered; D1–D8 adopted as recommended on 2026-10-19 (owner: "procede con la implementación"; [DECISIONS](../../DECISIONS.md)). **Owner:** physics track, subtrack with prefix `FUEL-` (D1), registered in the [documentation map](../README.md#tracks-plans-and-step-ids). **Steps:** FUEL-00…FUEL-14. **Evidence:** [FUEL-00 audit and sources](../research/fuel-systems/FUEL-00/README.md); reproducible scripts in [`research/fuel-systems/FUEL-00/`](../../research/fuel-systems/FUEL-00/).

**Owns (proposed):** this plan, `docs/research/fuel-systems/`, `research/fuel-systems/`, the shared fuel-property registry and energy-store loader with their tests, and the mass/balance report tool.

**Does not own:** `app/physics/glow/` (NITRO), `app/physics/turbine.gd` and AV-10 (Ventage Jet), contract/schema files (AS; co-edited per step), Workshop (AE), failures (EM), crash/economy (CR), HUD/AUD/menus, kernel files `simulation.gd`, `vehicle_model.gd` and `mass_inventory.gd` (physics/SF), and each aircraft's generator (its aircraft owner). Every step below names its co-owner. Generated aircraft data changes only through its generator.

## 1. Goal

Make fuel weight, tank position and fuel burn behave like a real RC airplane for glow and gasoline engines, and give kerosene turbines, smoke oil and later ground/rotor vehicles the same contract. Concretely:

1. Fuel mass is volume × density of the actual blend at a stated temperature, from one registry.
2. Each tank has a declared position, size, capacity, unusable residue and empty shell; liquid and shell are separate items.
3. Burn changes mass, CG and full inertia continuously; every consumer (dynamics, contacts, HUD, crash, economy, logs) reads the same live sample.
4. Balance is defined like a real manual: the plan CG at a declared fuel state, an optional CG range at that state, and a positive static margin at every fill from full to empty.
5. Engines drain what they deliver. Feed depends on the specific force at the tank and carburetor, including rotation. The tank stops feeding at its unusable residue, not at the last gram.
6. One law for every family; family-specific parts stay with their owners.

Acceptance has the same three levels as the [turbine plan](turbine-realism.md#1-objective-and-definition-of-realism): **software verified** (equations, units, events, replay), **evidence constrained** (sourced densities, capacities, consumption and placement, with uncertainty), **physically validated** (weighed full/empty airplane, measured burn per flight). Software checks never close the physical level.

Out of scope: slosh dynamics, fuel temperature dynamics, fire (CR-35), engine tuning (NITRO/AV) and new aircraft.

## 2. What exists on 2026-10-19

| Mechanism | State | Where |
| --- | --- | --- |
| Variable mass, CG, inertia | Glow Stiks only. One fixed-shape tank, uniform density scaling, co-moving efflux, body datum at the initial wet CG. Independently verified: momentum is conserved to 1.8e-5 kg·m/s at 240 Hz, versus 8.5e-2 without the datum correction | `app/physics/glow/fuel_mass.gd`, `flight.gd:226` |
| General resource kernel | `MassInventory`: dry parts plus resources with capacity, stable IDs and tensor checks. Runtime never calls `prepare`/`evaluate`; it agrees with `FuelMass` to 1e-16 | `app/physics/mass_inventory.gd` |
| Kernel hook | Open-system stage derivative in `VehicleModel` | `app/sim/simulation.gd:236`, `app/sim/vehicle_model.gd:27` |
| Consumption | Glow: per-cycle air law (2T/4T). Turbine: `fuel_flow` table, telemetry only. Gasoline: none | `two_stroke.gd`, `four_stroke.gd`, `turbine.gd:188` |
| Feed | Glow: hydrostatic head along the specific force plus estimated drive pressure. No rotation, pickup or unusable fuel | `app/physics/glow/fuel_feed.gd` |
| Exhaustion | Glow: bracketed to 1e-12 s; the engine stops on the last gram | `lifecycle.gd:491-495` |
| Contract | Fuel is a generic inventory item with an `energy_source` tag. Energies are `prescribed_fuel` or `finite_glow_fuel`. The glow tank is bound by item name | `aircraft-contract-v2.json:180-194`, `installation.gd:250` |
| Balance | Loader requires `plan_cg` to match the inventory CG at the declared state. No range; the fuel state is free text, explicit only for the Extra | `aircraft_data.gd:338-414` |
| Start and reset | Always the declared fill (half tank); reset refuels | `flight_session.gd:2710-2714` |
| Measurement | VAL-5a weighing and VAL-6a swing reducers already record fuel state | [weighing](../../research/validation/weighing/README.md), [inertia](../../research/validation/inertia/README.md) |

Fleet, from [`static_margin.out.txt`](../../research/fuel-systems/FUEL-00/static_margin.out.txt). Full tank = twice the declared fill; neutral points are the repository's own estimates.

| Aircraft | Fuel, burn | Declared fill | Tank ahead of CG | CG shift full→empty | Static margin full / declared / empty (% MAC) |
| --- | --- | --- | ---: | ---: | --- |
| Stik glow 55AX / 61FX / FS-64V | Glow, finite | 0.12 kg = "half tank" | 221 mm | +18 to +21 mm | 7.0 / 3.8 / **0.3–0.7** |
| Base Stik `jensen_ugly_stik_60` | Glow, fixed | 0.12 kg | 221 mm | +18 mm | 6.7 / 3.8 / 0.7 |
| Extra 300S .60 | Glow 61FX, fixed | 0.146 kg (355 ml tank) | 138 mm | +12 mm | 16.4 / 14.5 / 12.5 |
| P-51D 1/4 | Gasoline DA-120, fixed | 0.37 kg (1 l tank) | 327 mm | +11 mm | 8.3 / 7.2 / 6.1 |
| Ventage Jet | Kerosene, fixed | 1.28 kg (3.2 l tank) | 190 mm | +42 mm | 13.7 / 8.5 / **2.1** |
| Synthetic electric Stiks | None | Carry glow "fuel (half tank)" donor items | — | — | — |
| Timber | LiPo | Well-formed inventory reference | — | 0 | — |

## 3. Audit findings

Full evidence, file references and reproduction commands are in [FUEL-00](../research/fuel-systems/FUEL-00/README.md#5-findings).

| ID | Priority | Finding | Fixed by |
| --- | --- | --- | --- |
| F01 | P0 | Stik glow balance is defined with a half tank. The empty-tank static margin falls to 0.3–0.7 % against the 43.5 % c neutral-point estimate, so every glow flight ends nearly neutral. The Great Planes and Top Flite manuals balance with an empty tank | D3, FUEL-05 |
| F02 | P0 | Ventage Jet: SebArt's 240 mm is applied at half tank, and the empty tank moves the CG to 263 mm, aft of the manual's 260 mm aft limit (margin 8.5 → 2.1 %). The Krill 2.1 m manual (same tank bay) gives 240 mm full and 260 mm with landing fuel, which implies a tank about 70–90 mm ahead of the CG, not the modelled 190 mm | D3, AV-10c with FUEL-05 |
| F03 | P0 | Fuel quantity is inconsistent: 0.12 kg vs "150 ml" vs a 225 ml fuel box vs an "8–10 oz" tank vs the 350 cc the manuals recommend. "Usable premix" is the half-tank mass; a full tank cannot be represented | FUEL-03, FUEL-05 |
| F04 | P0 | Glow density has four values: 0.80, 0.82, about 0.857 (profile) and a hard-coded 0.8 in the HUD, which overstates volume by 7 % | FUEL-01, FUEL-02 |
| F05 | P0 | Wet mass after burn is still used by the HUD load factor, crash severity/effective mass/wreck mass, crash fuel stain and economy; the trace has no live mass or CG | FUEL-06 |
| F06 | P1 | NITRO-61FX README flows are ×0.76 low (the calibration mirror includes 2T trapping; runtime does not), so its endurance is about 30 % optimistic | FUEL-01 (NITRO) |
| F07 | P1 | Two mass kernels for one law (`FuelMass`, `MassInventory`) | FUEL-04 |
| F08 | P1 | Two datum conventions: glow uses the initial wet CG; AV-10b proposes a dry datum | D2, FUEL-04 |
| F09 | P1 | Contract gaps: no tank object; tank bound by name; generator selects the fuel item by array index `inv[6]`; template fuel item lacks `energy_source`; 5 kg per-item cap | FUEL-01, FUEL-03 |
| F10 | P1 | No finite fuel for gasoline or kerosene; the glow profile contract cannot express gasoline | FUEL-08, AV-10 |
| F11 | P1 | No CG range; the fuel state of `plan_cg` is implicit except for the Extra | FUEL-03 |
| F12 | P1 | Tanks and liquid are point masses (`size [0,0,0]`) on every aircraft except the glow liquid and the jet | FUEL-05 |
| F13 | P1 | Synthetic electric Stiks carry a glow engine, tank and fuel as donor mass, without IDs or a battery | FUEL-05 (D7) |
| F14 | P1 | Feed: fill is measured against initial fuel, not capacity; the fuel centroid is fixed while the feed law lowers a free surface; no rotational acceleration (20 % g at the tank at q = 3 rad/s); no pickup, unusable fuel or line run-on | FUEL-09 |
| F15 | P1 | Fill cannot be chosen at start; reset always refuels to the declared fill | FUEL-07 |
| F16 | P2 | Workshop `weight_multiplier` also scales the fuel; Workshop transforms are disabled for finite glow | FUEL-11 (AE) |
| F17 | P2 | Ventage Jet's 1.3 l smoke tank is not in the inventory; full it would move the CG 16 mm forward | FUEL-05 (AV, SM) |
| F18 | P2 | Economy prices fuel on the Stiks only | FUEL-10 (CR) |
| F19 | P2 | No fuel gauge, low-fuel warning, lean-out cue or fuel-system failure; only `glow_fuel_cut` exists | FUEL-10, EM-15/16 |
| F20 | P2 | Nitro truck keeps body mass fixed while its fuel state falls; the X-Cell .60 helicopter has no fuel | FUEL-14 (RCV, HELI) |
| F21 | P1 | FS-64V flow looks low: 13–17 ml/min at full throttle, against 16–18 ml/min mixed from its manual and 20 cc/min at full throttle for the similar Saito FA-62B | FUEL-08 (NITRO) |
| F22 | P1 | Stik tank "8–10 oz" is below the 350 cc the 55AX/61FX manuals recommend (220 cc for the FS-64V) | FUEL-05 |

What already works and must be preserved: the glow datum law and moment transfer, live-CG contacts, exhaustion localization, reset refuel, the trace's fuel-never-increases check, the Extra generator's dry-then-fuel balance, and Timber's inventory pattern.

## 4. Target physical model

### 4.1 Fuel properties

One registry of fuel blends. Each entry lists its components with volume fractions and per-component density at a reference temperature, each with a source, plus an optional measured-density override. The temperature slopes are about −0.94 kg/m³/K for methanol-based glow, −0.92 for gasoline and −0.74 for kerosene.

Glow blend density is computed from components, as `profile.gd` already does: 72/10/18 methanol/nitro/castor gives 856.9 kg/m³. Fuels with 15 % or 30 % nitro, or synthetic oil, reach 874–937 kg/m³. Each blend carries ±2 % uncertainty (Menon's measured blend is 1.6 % above ideal mixing). Gasoline premix (747–751 kg/m³ at 745 kg/m³ gasoline; batch spread 715–775) and kerosene with 5 % oil (810 kg/m³) are registry entries.

Fuel mass is always `volume × density`; no file writes a density in prose. Values and sources are in [FUEL-00 §6](../research/fuel-systems/FUEL-00/README.md#6-external-sources).

### 4.2 Tank and energy store

An energy store binds by ID to its shell inventory item and owns:

- fuel blend ID;
- capacity volume and unusable volume;
- liquid geometry: box size and centroid (cylinder later if a tank needs it);
- pickup point (JSBSim's `drain_location`);
- pickup type (`clunk`, `felt_clunk`, `fixed`, `hopper`) and feed type (`suction_muffler` for glow, `pumped_diaphragm` for gasoline, `ecu_pump` for turbines);
- start fill fraction, overridable per session;
- optionally, a feed `priority` for multi-tank and hopper layouts.

Field meanings follow [JSBSim's `FGTank`](https://github.com/JSBSim-Team/jsbsim/blob/master/src/models/propulsion/FGTank.cpp) where one exists (capacity, unusable volume, drain location, priority). We use its ideas, not its LGPL code, which does not run in GDScript.

**Glow tank height.** The tank height relative to the carburetor follows the selected engine's manual, and the three O.S. rules differ:

| Engine | Rule |
| --- | --- |
| FX | Tank top 5–10 mm above the needle |
| 55AX | Tank center level with the carburetor |
| FS-64V | Tank center 10 mm below the needle |

**Liquid shape.** The liquid stays a fixed-shape, uniform-density distribution (`fixed_geometry_uniform_density_v1`). Against a settling free surface it is off by about 0.3 mm of CG in level flight on the Stik, and by at most 4.9 mm under acceleration. A quasi-static centroid (JSBSim-style drain interpolation, or free-surface tilt under load) is evaluated only in FUEL-09 (D6).

### 4.3 Mass properties and datum

All finite resources go through `MassInventory`: dry parts plus resources, about one fixed datum. The open-system derivative (`FuelMass.datum_derivative`, verified) moves to a shared helper keyed by law ID. Co-moving efflux needs no dm/dt or dI/dt terms; adding `-İω` would create spin-up. The fuel's own momentum flux is about 0.04 N against 30 N of thrust and stays out.

The datum must not move with the fuel fill. Recommendation for D2: the datum is the declared `plan_cg` point, a fixed geometric point. For existing glow Stiks this equals today's initial wet CG, so their law output is unchanged. With `plan_cg` at the empty tank it is also the dry CG that AV-10b proposes.

Each accepted tick publishes one mass-properties sample (mass, CG, inertia, fuel per store, law ID). Consumers read it and never recompute it.

### 4.4 Consumption

The tank drains the delivered flow, not the commanded flow.

- **Glow:** existing per-cycle law (NITRO). Measured glow BSFC is about 1.39 kg/kWh at peak power, 2.4–3× that of small gasoline two-strokes. The 4T flow needs review (F21).
- **Gasoline:** first a minimal law on the existing propulsion: delivered flow = brake-specific consumption × shaft power, with an idle floor and gasoline premix chemistry.
  - The measured BSFC band is 406–580 g/kWh.
  - For the P-51's installed 6.9 kW this gives 63–90 ml/min at full throttle, or 11–16 min per litre. Desert Aircraft quotes 71 g/min for the DA-100 at 6,000 rpm.
  - A full gasoline engine family like glow is a separate owner decision (D5).
- **Turbine:** AV-10a.

Consumption evidence carries its kind: `wot_flow`, `idle_flow`, `bsfc_map` or `mixed_endurance`. A mixed-flight endurance figure is never converted into a full-throttle flow. Every model output is labelled as model output and compared with manufacturer figures in the evidence. No idle flow has been published for glow or gasoline engines, so idle flow stays estimated.

### 4.5 Feed, pickup and unusable fuel

The specific force at a point is `f = -F_nongrav/m + ω̇×r + ω×(ω×r)` for the tank and the carburetor.

- **Glow (suction):** keep the hydrostatic head law, add the rotational terms, measure fill against capacity, and share the tank geometry with 4.2.
- **Clunk pickup:** follows `f`. It feeds while the liquid covers it along `f` and the store is above its unusable volume. Otherwise the line volume runs out, then the engine leans and stops through the existing lifecycle.
- **Pumped gasoline:** head-insensitive inside a declared pressure band. The DA-120 manual says "the tank can be mounted almost anywhere".
- **Hopper/UAT:** the engine starves only when the hopper is empty. Main-tank depletion alone is not a fuel cut.

All starvation is deterministic: no probability, no bank-angle rule. Inverted flight with a working clunk keeps running. The manuals' vibration-induced foaming stays out until there is data to drive it.

### 4.6 Balance, CG range and stability

- `plan_cg` declares its fuel state. The default is `empty`, as the Great Planes Extra 300S and Top Flite Giant P-51D manuals state ("ready to fly and an empty fuel tank"). Jets use a full hopper and an empty main tank. D3 decides per aircraft.
- An optional `cg_range` (forward and aft limits with sources) applies at that declared state only. Manual ranges are written for the balance state: the Extra's ±9.5 mm range would put its full tank 2.3 mm ahead of the forward limit, which is normal.
- The mass/balance report prints CG and static margin at full, start and empty for every aircraft. It gates on two things: the declared-state range, and a positive static margin at every fill against the aircraft's neutral-point estimate.
- A generator never rebalances hardware per fill state.

### 4.7 Left out, with reasons

Dynamic slosh is left out. A half-full 16 oz tank sloshes at about 1.7–3.2 Hz (Dodge 2000), close to RC short-period frequencies, so the case is not frequency separation. It is mass: the CG excursion is bounded at about 4.9 mm in a 3 kg airplane, and no small-aircraft slosh flight data exist. The quasi-static centroid of 4.2 is the most this plan considers; slosh reopens only if a measured flight disagrees. Fuel temperature, vapor, foaming and fire (CR-35) are also left out.

## 5. Data standard (contract extension, opt-in)

A sketch for AS review; the final names follow the AS-16 energy-store decision. Missing blocks mean today's behavior, so existing aircraft load unchanged until migrated.

```json
"fuels": [{"id": "glow_10n_18o", "ref": "registry:glow_10n_18o"}],
"energy_stores": [{
  "id": "main_tank", "kind": "liquid_fuel", "fuel": "glow_10n_18o",
  "shell_inventory_id": "item_fuel_tank",
  "capacity": {"value": 0.355, "unit": "l", "kind": "manual", "source": "..."},
  "unusable": {"value": 0.010, "unit": "l", "kind": "estimated", "source": "..."},
  "liquid_box": {"center": {"value": [-0.1, 0, 0], "unit": "m"}, "size": {"value": [0.12, 0.07, 0.05], "unit": "m"}},
  "pickup": "clunk", "feed": "suction_muffler",
  "start_fill": {"value": 1.0, "unit": "1", "kind": "authored", "source": "..."}
}],
"balance": {"plan_cg": {...}, "plan_cg_fuel_state": "empty",
            "cg_range": {"forward": {...}, "aft": {...}}}
```

Rules:

1. A liquid inventory item is derived from its store, never authored twice.
2. Every reference uses an ID: store → shell item, installation → store.
3. Density comes from the registry only.
4. The liquid box volume is at least the capacity.
5. A shell has a size: zero-size tanks are refused once migrated.
6. The CG at the declared balance state must lie in `cg_range` when one is declared; full and empty fills are reported against static margin, not the range.
7. Electric aircraft declare no fuel store.
8. The template carries one complete example.

## 6. Steps

| ID | Work | Co-owner | Proof / status |
| --- | --- | --- | --- |
| FUEL-00 | Audit of code, data, contract and plans; external sources; reproducible scripts | — | **Delivered 2026-10-19**: [FUEL-00](../research/fuel-systems/FUEL-00/README.md) |
| FUEL-01 | Byte-identical repairs and baseline. (a) Generator selects inventory records by id, not position. (b) HUD reads the profile density. (c) Calibration mirror's 2T flow drops trapping; NITRO-61FX README corrected. (d) Template fuel item gets `energy_source`. (e) Mass/balance report, neutral-point register and stored baseline, checked in `app/test.sh` | NITRO, AS, HUD | **Delivered 2026-10-19**: [FUEL-01](../research/fuel-systems/FUEL-01/README.md). 20 fingerprints identical; generated JSON byte-identical; HUD shows 140 mL for 0.12 kg; 61FX flows 38.8/46.0/58.1 ml/min; four mutations detected |
| FUEL-02 | Fuel-property registry and loader; glow profiles validated against it; no prose densities | NITRO | **Delivered 2026-10-19**: [FUEL-02](../research/fuel-systems/FUEL-02/README.md). `openrc-fuel-registry v1` (7 components, 3 blends), GDScript and Python readers; 30 + 3 checks; glow profiles equal the registry blend (856.92 kg/m³); two loader mutations detected. Prose densities leave the aircraft data in FUEL-05 |
| FUEL-03 | Contract: `energy_stores`, `plan_cg_fuel_state`, `cg_range`, ID binding; schema, loader, template and [AIRCRAFT_CONTRACT](../../AIRCRAFT_CONTRACT.md) text | AS | Invalid-data refusal tests (rules 1–8); fleet fingerprints identical with blocks absent |
| FUEL-04 | One mass kernel: prepared fast path in `MassInventory`, shared open-system helper, glow migrated, datum per D2 | Physics/SF, NITRO | **Delivered 2026-10-19**: [FUEL-04](../research/fuel-systems/FUEL-04/README.md). `MassInventory.prepare_reference/evaluate_reference` + `FixedDatumBody`; bit-identical to `FuelMass` (0 mismatches, 20 fingerprints identical); momentum fixture 4th-order (ratio 16.0001), law error 0.0626 without the correction; cost no worse (min 17.1 vs 18.6 µs) |
| FUEL-05 | Fleet data through generators: capacities from engine/kit manuals (F22) and start fill, registry densities, tank boxes and heights, IDs, balance state per D3, Ventage tank position re-estimated (F02), electric donor items per D7, Ventage smoke store | Stik, EX, P51, AV, SM owners | Mass/balance report before/after; every aircraft inside its range at the balance state with positive margin at full and empty; golden and FT baselines re-recorded with a written reason |
| FUEL-06 | Publish the live mass-properties sample; HUD load factor, crash director/effective mass/wreck/fuel stain, economy and `.orfl`/trace columns read it (closes the R05-B handoff) | HUD, CR, FL | Empty-tank tests: HUD n uses live mass; crash `fuel_kg` equals the remaining fuel; log shows mass and CG every tick; replay exact |
| FUEL-07 | Start fill per session or scenario (default per D4); reset to the selection; fill in checkpoint and replay identity; menu control | UI | Session tests at 0.1/0.5/1.0; restore after reset; old checkpoints refused with a message |
| FUEL-08 | Finite fuel for the remaining fleet: gasoline consumption law for the P-51 (D5); Extra through the NITRO installation path; Ventage Jet through AV-10a/c; NITRO review of the 4T flow (F21). Opt-in variants first | NITRO, P51, AV | Exhaustion localized; P-51 within 406–580 g/kWh at its shaft power; glow within the manuals' mixed-flight endurance when flown on a mixed tape; figures labelled by kind |
| FUEL-09 | Feed v2: rotational point acceleration, fill vs capacity, clunk pickup, unusable residue, line volume run-on, pumped gasoline feed | NITRO, EM | Fixtures: inverted cruise keeps running; sustained negative g near empty starves after the line volume; continuity of the feed factor; no starvation at 90° bank |
| FUEL-10 | Presentation: fuel gauge in ml and %, low-fuel warning at an authored reserve, lean-out cue, consistent fuel pricing | HUD, AUD, CR | Overlay and audio tests; pricing rule applied fleet-wide |
| FUEL-11 | Workshop: move/resize tank, choose fill, dry-only weight multiplier, target CG and ballast (AE-12) | AE | AE oracles; CG recomputed; fuel never scaled |
| FUEL-12 | Flight-feel evidence: same tick/input tape at full vs empty per the [flight logging workflow](../FLIGHT-LOGGING.md); FT card at two fills | FT, FL | Trim elevator, stall speed (∝ √m), pitch response and glide differences match the hand calculation; `solver_changed`/`complete` checked |
| FUEL-13 | Physical validation: weigh an airplane empty and full (VAL-5a) to get the tank centroid; timed burn per flight; owner's Stik if available | VAL | Raw inputs, uncertainty, configuration; model vs measurement |
| FUEL-14 | Other vehicles on the same kernel: nitro truck mass, helicopter nitro tank | RCV, HELI | Each track's own gates; only when that track schedules it |

## 7. Order and first slice

```text
FUEL-00 → FUEL-01 → FUEL-02 → FUEL-04 → FUEL-03 → FUEL-05 → FUEL-06 → FUEL-07
                                              ↘ FUEL-08 ∥ FUEL-09 → FUEL-10/11 → FUEL-12 → FUEL-13
```

FUEL-04 runs before FUEL-03. The kernel works with today's glow tank data, while the battery track (BAT-09) is changing the same schema, loader and contract files on 2026-10-19. FUEL-03 starts once that work lands and reuses its inventory-binding pattern for packs. FUEL-05 is the step that changes flight behavior (D3/D4/D7). AV-10a/b/c keeps its own IDs and status; FUEL-03/04 supply the shared contract and kernel it consumes.

## 8. Owner decisions

All eight recommendations were adopted on 2026-10-19 ([DECISIONS](../../DECISIONS.md)). Each stays revisable; D3 and D4 change flight behavior only in FUEL-05.

| ID | Question | Recommendation (adopted) |
| --- | --- | --- |
| D1 | New `FUEL-` subtrack, or fold into NITRO | New subtrack under physics; it spans glow, gasoline, turbine, Workshop and presentation |
| D2 | Fixed datum | `plan_cg` point. Unchanged for glow today; equals AV-10b's dry datum when the plan CG is at an empty tank |
| D3 | Fuel state of the plan CG | `empty` for propeller aircraft, as the Extra and Top Flite P-51 manuals state; jets use a full hopper with an empty main tank. For the Ventage Jet, choose between SebArt's unqualified 240 mm and Krill's "240 mm full". For the Stik this restores about 4 % margin at empty and about 10 % at full |
| D4 | Default start fill | Full tank for finite-fuel aircraft, with a session choice |
| D5 | Gasoline scope | Minimal BSFC law first; a gasoline engine family only with matched data |
| D6 | Fuel centroid | Keep the fixed shape in FUEL-04 (0.3 mm level, ≤ 4.9 mm under load). Test a quasi-static centroid in FUEL-09 and adopt it only if it changes a fixture by more than 1 mm. No dynamic slosh |
| D7 | Synthetic electric Stiks | Keep the donor mass but rename it as neutral ballast with IDs, or give them a real battery/motor inventory |
| D8 | Display units | ml and % by default; oz as an option (UI) |

## 9. Verification and evidence layout

- **Software checks per step:** analytic oracles (mass, first moment, tensor), the FUEL-00 momentum fixture, refusal tests for every contract rule, actual-session tests, replay identity, and one deliberate mutation per new rule. Run them on a disposable copy, as [AGENTS](../../AGENTS.md) requires.
- **Fleet proofs:** fingerprints from `app/tests/fingerprint_vehicles.gd` against the exact pre-step commit. Golden flights are re-recorded only in FUEL-05/08, with the reason written down.
- **Evidence:** `docs/research/fuel-systems/FUEL-NN/` holds the README with commands and results; scripts and data live in `research/fuel-systems/FUEL-NN/`.
- **Report tool:** the mass/balance report, which FUEL-01 generalizes from `cg_shift.py`, runs in the suite as a non-gating report until FUEL-05 makes the range a gate.

## 10. Risks

- Golden flights, FT baselines, NITRO refinement/endurance records, R05-B contact evidence, glow identity hashes and `MASS_CONTACT_LAW` checkpoints all change in FUEL-04/05. Batch the re-records and explain each one.
- `MassInventory.evaluate` validates on every call and runs on every RK stage; FUEL-04 must add a prepared path and bench it.
- Several tracks edit the shared contract, session and crash files. Coordinate per step and stage only your own paths.
- Estimated tank positions and blends must not become "measured" through reuse; FUEL-13 is the only physical step.

## 11. Coordination

| Other step | Owner | Relation |
| --- | --- | --- |
| AV-10a/b/c, AV-05b/23/25/27/28 | Ventage Jet | Consumes FUEL-03/04; AV keeps turbine depletion, ECU, hopper and pump |
| VAL-AUD-R05, R07 | Physics, AV | FUEL-04 is the proposed home of the shared datum and finite-resource rule |
| R05-B handoff | Physics, CR | Closed by FUEL-06 |
| AS-12, AS-16 | AS | FUEL-03 aligns the energy-store naming with AS-16 |
| AE-12, AE-13, AE-16, AE-17 | AE | FUEL-11; wet-to-dry mass handled by FUEL-03/04 |
| EM-15, EM-16, EM-21 | EM | FUEL-09 provides deterministic starvation; EM-21 detachment uses the same kernel |
| CR-35, CR-37 | CR | FUEL-06 supplies remaining fuel and live mass |
| NITRO-04, NITRO-2T/4T-04 | NITRO | FUEL-08/13 supply measured burn per flight |
| G4a, G4b, X-DATA-11 | Proposals | Superseded by FUEL-04/05/07 (G4b's per-tick state shift is replaced by the per-stage fixed datum) |
| VAL-5, VAL-6 | VAL | FUEL-13 reuses both reducers |
| RCV-36 follow-up, HELI fuel | RCV, HELI | FUEL-14 |
