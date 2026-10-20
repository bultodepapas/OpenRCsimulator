# FUEL-00 — Fuel, mass and balance audit (2026-10-19)

Dated evidence for the [fuel, mass and balance plan](../../../plans/fuel-mass-balance.md). This is a read-only audit of the working tree on 2026-10-19 (HEAD `272e2e51`); no runtime, data or test file changed. Uncommitted GP-06c gear-travel edits by another track were present in the same tree; they change no fuel, tank, inventory-mass, `plan_cg` or `energy_source` field, so the numbers below are unaffected. Every number below was reproduced with the scripts in [`research/fuel-systems/FUEL-00/`](../../../../research/fuel-systems/FUEL-00/) (§7). Line numbers are those of that tree.

## 1. Scope and method

- **Code:** `app/physics/glow/*`, `mass_inventory.gd`, `effective_mass.gd`, `turbine.gd`, `aircraft_data.gd`, `aircraft_contract.gd`, `app/sim/flight_session.gd`, `simulation.gd`, `vehicle_model.gd`, crash, HUD, Workshop, failures, economy, ground-vehicle and rotorcraft fuel paths.
- **Data:** every `app/data/aircraft/*.json`, glow profiles and installations, schemas, the authoring template and their generators.
- **Plans:** ROADMAP, every active plan, the phase knowledge base and the 2026-10-14 physics audit.
- **Method:** three parallel read-only reviews (glow chain; fleet and contract; external sources), then spot checks of the key claims against source. Python mirrors of the GDScript arithmetic; no Godot run on the shared tree.

## 2. Glow variable-mass law

`fuel_mass.gd:11-40` models one tank as a rigid, uniform-density box of fixed size and center. Mass is scaled down from the initial wet load: `m = m_wet − Δ`, `c = −Δ·r_tank/m`, `I_O = I_wet − Δ·T_box,O`, `I_cm = I_O − m·par(c)`. The body datum O is the initial wet CG. There is no free surface, line or carburetor inventory, and no slosh.

**The datum derivative is correct.** `datum_derivative` (`fuel_mass.gd:44-52`) takes `RB.derivative` (CM acceleration, Euler equation with live `I_cm`) and subtracts `α×c + ω×(ω×c)` from the datum velocity rate. For rigid remaining particles, `Σmᵢaᵢ = F` gives `a_O = F/m − α×c − ω×(ω×c)` and `M_cm = I_cm·α + ω×I_cm·ω`, with no `İω`, `ṁ` or `ċ` term. Co-moving efflux means no thrust-like reaction and no jet damping.

**Independent check:** `datum_momentum.py`. Zero wrench and gravity, a non-principal 3.7 rad/s spin and a 280 s burn of 0.12 kg:

| Case | dt | Remaining-body plus ejected momentum error (kg·m/s, P0 = 13) |
| --- | --- | ---: |
| With datum correction | 1/120 s | 1.3e-4 |
| With datum correction | 1/240 s | 1.8e-5 |
| Without correction | 1/120 s | 8.5e-2 |
| Without correction | 1/240 s | 8.5e-2 |

**Neglected terms.** Fuel momentum flux through the engine is about 0.0004 kg/s × 100 m/s ≈ 0.04 N, against about 30 N of thrust. The line Coriolis term is about 1e-5 N·m.

**Consumers on the live CG:**
- Aero, propeller and ground moments are transferred to the live CG at `flight.gd:226`.
- Rotor coupling and friction use live inertia (`flight.gd:236,246`), as do the starter impulse (`flight_session.gd:171-178`) and the rotor-stop projection (`flight.gd:267-279`).
- Hull, terminal-hull, scenery and lake contacts use the live sampler (`flight_session.gd:1712-1725`, `2653`).
- The renderer poses the airplane at O, so geometry never jumps.

**Consumers still on wet values after burn:**
- `sim.mass`/`sim.inertia` (`flight_session.gd:1080-1081`) feed the HUD load factor (`overlay_manager.gd:233`), which reads up to 4.6 % low at empty.
- The crash director uses wet values for severity, effective mass, wreck mass and `_cg_model` (`render/crash/director.gd:173-178`; `main.gd:797-801`), and the legacy `EffectiveMass.at_point` treats the datum arm as the CG arm.
- Crash `fuel_kg` is the declared inventory (`director.gd:84-95, 207-208`), and the economy impact budget reads it.
- The trace logs wet `mass_kg` and inertia, labelled as such (`flight_session.gd:3262-3271`). Its moments are about O, which is not stated.
- Trim and start solvers use wet values. That is consistent today only because every reset refuels to the declared load.

**Two kernels.** `MassInventory.prepare/evaluate` (`mass_inventory.gd:51-169`) has callers only in tests; runtime uses only its `rectangular_box_per_kg` and `is_physical_tensor`. On the three glow Stiks at 0.12/0.06/0 kg the two kernels agree to |Δm| ≤ 4.4e-16, |Δc| ≤ 5.6e-17 m and |ΔI| ≤ 5.6e-17 kg·m² (`mass_kernel_compare.py`). That is agreement to rounding, not bit identity. Dry vs wet inertia: Ixx −0.04 %, Iyy −1.6 to −2.0 %, Izz −1.3 to −1.5 %.

## 3. Fleet mass and balance

From `cg_shift.py` and `static_margin.py`. Capacity and density come from each item's own provenance text, and a full tank is assumed to be twice the declared half tank. MAC uses the taper formula; `reference.mean_chord` is S/b, not MAC. Neutral points are repository estimates:
- Stik: 43.5 % c ([climb-trim](../../flight-dynamics/climb-trim/README.md)).
- Extra: 42.5 % MAC (`research/extra-300/ex05/derivation.md`).
- P-51: 34.2 % MAC.
- Ventage Jet: the manual's 260 mm aft CG taken as 3 % stable (`research/avanti-s/av06/inputs.json`).

| Aircraft | Mass decl. (kg) | Fuel decl. (kg) | Tank ahead of CG | CG full / decl. / empty | Static margin full / decl. / empty |
| --- | ---: | ---: | ---: | --- | --- |
| Stik glow 61FX | 2.885 | 0.12 | 221 mm | 36.8 / 39.7 / 42.8 % c | 6.7 / 3.8 / 0.7 % |
| Stik glow 55AX | 2.623 | 0.12 | 221 mm | 36.5 / 39.7 / 43.1 % c | 7.0 / 3.8 / 0.4 % |
| Stik glow FS-64V | 2.593 | 0.12 | 221 mm | 36.5 / 39.7 / 43.2 % c | 7.0 / 3.8 / 0.3 % |
| Base Stik | 2.885 | 0.12 | 221 mm | 36.8 / 39.7 / 42.8 % c | 6.7 / 3.8 / 0.7 % |
| Extra 300S | 3.420 | 0.146 | 138 mm | 26.1 / 28.0 / 30.0 % MAC | 16.4 / 14.5 / 12.5 % |
| P-51D | 21.5 | 0.37 | 327 mm | 25.9 / 27.0 / 28.1 % MAC | 8.3 / 7.2 / 6.1 % |
| Ventage Jet | 11.705 | 1.28 | 190 mm | 221 / 240 / 263 mm from root LE | 13.7 / 8.5 / 2.1 % |

Cross-check: the Extra's empty-tank CG of 30.0 % MAC matches its generator's dry reference of 29.99 % MAC.

**Ventage smoke oil.** A full 1.3 l Ventage smoke tank (an assumed 0.85 kg/l at the fuel-tank position) would move the CG 16.4 mm forward. Every fuelled aircraft declares exactly 50 % fill; only the glow Stiks deplete it.

## 4. Glow consumption and feed

**Flow law** (`two_stroke.gd:165-206`; the 4T uses VE and rpm/120). It is not BSFC:

`ṁ = ρ_air·V_d·adm·DR(rpm)·φ/AFR/(1−oil)·rpm/60`

- The tank drains the lagged transport state (`lifecycle.gd:286, 319-324`), which includes short-circuited 2T fuel.
- The 72/10/18 blend gives ρ = 856.9 kg/m³, AFR 5.641 and oil mass fraction 0.2019.
- Flows below are from `glow_flow.py` at φ = 1.15, ρ_air = 1.225 kg/m³ and feed factor 1.

| Engine | Full throttle (ml/min) | Idle (ml/min) | 0.12 kg lasts at static WOT |
| --- | --- | ---: | ---: |
| MAX-55AX | 28.1 at 9,380 rpm (static); 52.2 at 16,000 | 1.5 | 5.0 min |
| MAX-61FX | 38.8 at 10,976; 46.0 at 12,550; 58.1 at 16,000 | 1.7 | 3.6 min |
| FS-64V | 13.0 at 7,823 (static); 17.9 at 11,000 | 1.0 | 10.7 min |

The endurance stand agrees: 0.410 g/s (55AX) and 0.186 g/s (FS-64V). The context figures already in the repository bracket these values:
- the 55AX manual's 350 cc for 10–12 min at mixed throttle;
- the AIAA 2016-5011 2T fit of about 27 g/min at 900 W;
- the AIAA 4T fit of about 14 g/min at 600 W;
- Saito FA-82B at 35 cc/min, scaled by displacement to 27 cc/min, which is 37 % above the FS-64V model at 10,000 rpm.

**Calibration mirror error.** `research/glow-engines/calibration_report.py:160-162` multiplies the 2T air charge by trapping; runtime's delivered premix does not (`two_stroke.gd:167-206`). The NITRO-61FX README therefore quotes 29.5/35.0/43.0 ml/min where runtime gives 38.8/46.0/58.1, and its 11.9/10.0/8.1 min per 350 cm³ are about 30 % optimistic.

**Feed law** (`fuel_feed.gd`):
- It models the hydrostatic head from the box free surface, perpendicular to `g_eff = −F_nongrav/m` at the CG, up to the spray bar (81-90 and 122).
- Drive pressure scales as `(admission·rpm/rated)²` between idle and full throttle (94-98).
- The feed factor is `k = √((p+Δh)/(p+Δh_needled))`, clamped to [0, 2] and needled at level 1 g with a full box (102-113).
- Fill is measured as fuel / initial fuel (`flight.gd:167`), so the half tank counts as a full box.
- Drive pressures and carburetor positions are estimates (`build_installations.py:74-89`); no pressure measurement exists.

Feed factors from `glow_feed.py`:

| Case | k at idle | k at full throttle |
| --- | ---: | ---: |
| 2T, level, empty box | 0.853 | 0.965 |
| 2T, vertical up-line, 10 % | 0.117 | 0.865 |
| 4T, level, empty box | 0.704 | 0.944 |
| 4T, 3 g pull, 10 % | 0 (starves) | 0.785 |

The rotational term at the tank (0.221 m from the CG) is not modelled. It reaches 9 % g at q = 2 rad/s, 20 % g at 3 rad/s and 56 % g at 5 rad/s.

**Lifecycle.**
- **Priming:** removes `starter_prime_kg` (1e-5 kg) instantly (`flight_session.gd:158-185`).
- **Exhaustion:** bracketed to 1e-12 s with a residual of at most 1e-10 kg, then latched in the lifecycle (`lifecycle.gd:491-495`). The event keeps the key `charge_residual_c` (`flight.gd:313`).
- **Refuel:** only through reset (`test_glow_session.gd:65-66`).
- **Failures:** `glow_fuel_cut` freezes fuel mass (`failures/catalog.gd:86`, `runtime.gd:599`); no fuel-system failure exists.

## 5. Findings

The [current fuel work packages](../../../plans/fuel-mass-balance.md#4-work-packages-and-execution-order) own remaining work; these findings retain their original audit scope.

| ID | Kind | Evidence | Suggested fix |
| --- | --- | --- | --- |
| F01 | Realism | Glow generator balances with fuel included (`research/glow-engines/build_installations.py:131-138`); only the wet CG is checked (`app/physics/aircraft_data.gd:412-414`); empty-tank margin 0.3–0.7 % | Declare the plan-CG fuel state; check full and empty against a range |
| F02 | Realism | SebArt's 240 mm CG has no fuel state and is applied at half tank (`research/avanti-s/av06/inputs.json` `cg_aft_of_root_le`). In the model the empty tank puts the CG at 263 mm, aft of the 260 mm aft limit. The Krill 2.1 m manual (same tank bay) gives 240 mm full and 260 mm with landing fuel ([AV-06](../../avanti-s-av06-airframe-data.md)). That shift of about 20 mm for about 2.6 kg implies a tank centroid about 70–90 mm ahead of the CG; the model has 190 mm (estimated) | Decide the fuel state (full, or full hopper with empty main) and re-estimate the tank position before AV-10c; record in DECISIONS |
| F03 | Inconsistency | Stik fuel item: "150 ml at ~0.8 g/ml; half tank" = 0.12 kg; tank "8–10 oz" (237–296 ml); fuel box 0.09×0.05×0.05 m = 225 ml; 0.12 kg at the profile density is 140 ml; 55AX/61FX manuals recommend about 350 cc. The fuel item was renamed "usable glow premix" (`build_installations.py:127-129`) but is still the half tank; full tank refused (`fuel_mass.gd:17`, `flight.gd:47`) | Capacity and start fill as separate fields; mass from volume × density |
| F04 | Inconsistency | Glow density 0.80 (Stik text), 0.82 (Extra text), 856.9 kg/m³ (`app/physics/glow/profile.gd:48-55`), 0.8 hard-coded in the HUD (`app/main.gd:934-935`) | One registry; HUD reads the profile |
| F05 | Gap | Wet values in HUD, crash, economy and trace (§2) | Publish one live mass-properties sample |
| F06 | Inconsistency | Calibration mirror includes 2T trapping (`calibration_report.py:160-162`); NITRO-61FX README flows ×0.76 | Remove `trap` from the mirror's flow; regenerate; correct the README |
| F07 | Duplication | `FuelMass` and `MassInventory` implement the same law | Route through `MassInventory` with a prepared fast path |
| F08 | Inconsistency | Wet-CG datum (DECISIONS 2026-10-13 NITRO-02) vs the dry datum AV-10b proposes (`docs/plans/turbine-realism.md:164`) | One fill-independent datum rule |
| F09 | Contract | No tank object (`app/data/schema/aircraft-contract-v2.json:180-194`). Glow tank bound by name (`glow-installation-v1.schema.json:31`, `installation.gd:250`). Generator selects `inv[6]` by index (`build_installations.py:127`). Template fuel item has no `energy_source` (`research/aircraft-standardization/template/openrc-aircraft-v2.template.json`). 5 kg per-item cap (`aircraft_data.gd:352`) | Energy-store block with ID binding |
| F10 | Gap | Turbines forced to `prescribed_fuel` (`aircraft_contract.gd:162-163`); glow profile contract requires methanol (`profile.gd:48-50`) | Family-neutral finite fuel; gasoline chemistry entry |
| F11 | Gap | No CG range; fuel state explicit only in the Extra's `balance.configuration` (`gp_extra_300s_60.json:82`) | `plan_cg_fuel_state` and `cg_range` |
| F12 | Gap | Point-mass tank shells and liquids on the Stik base, Extra, P-51 and Ventage shell | Sized boxes from tank dimensions |
| F13 | Inconsistency | Synthetic electric Stiks keep the glow donor engine, muffler, tank and "fuel (half tank)" without IDs and with no battery (`synthetic_stik_electric_4s.json:216,245`); described as "original inventory mass distribution" | Neutral donor names with IDs, or a real electric inventory |
| F14 | Gap | Feed fill vs initial fuel (`flight.gd:167`). Fixed fuel centroid vs a falling free surface: about 0.3 mm CG in level flight, at most 4.9 mm under acceleration (§6.4). No rotational term, pickup, unusable fuel or line run-on (`fuel_feed.gd:66-67`) | Feed v2 |
| F15 | Gap | Reset always refuels to the declared fill (`flight_session.gd:2710-2714`) | Start-fill selection |
| F16 | Inconsistency | Workshop `weight_multiplier` scales fuel too (`app/workshop/compiler.gd:156`); transforms disabled for finite glow (`aircraft-modules-v1.json:247-263`) | Dry-only scaling; fill as its own parameter |
| F17 | Gap | Ventage 1.3 l smoke tank absent from the inventory | Separate consumable store, empty by default |
| F18 | Inconsistency | Economy prices fuel on the Stiks ($3) and leaves it null elsewhere (`app/data/economy/catalog.json:2144-2154, 3762-3772`) | One pricing rule |
| F19 | Gap | No fuel gauge, low-fuel warning, lean-out cue or fuel-system failure; only `glow_fuel_cut` | Presentation and EM steps |
| F20 | Gap | Nitro truck fuel falls while body mass stays fixed (`app/physics/ground_vehicle/nitro_dynamics.gd:13,124`); helicopters have no fuel fields; HELI excludes fuel burn (`docs/plans/helicopter.md:347`) | Same kernel when those tracks schedule it |
| F21 | Realism | FS-64V flow looks low: 13.0 ml/min at static full throttle and 17.0 at 10,000 rpm, against 16–18 ml/min mixed from its manual and 20 cc/min at full throttle for the similar Saito FA-62B (§6.2) | NITRO review of the 4T charge/VE estimate |
| F22 | Realism | Stik tank "8–10 oz" (`jensen_ugly_stik_60.json` tank item) is below the 350 cc the 55AX/61FX manuals recommend; the FS-64V manual uses 220 cc | Capacity per installation from the engine manual unless the Stik plan states one |

**Plan overlaps found.** The shared variable-mass rule has four candidate homes: VAL-AUD-R05, AV-10b, AS-12 and G4b. A tank or registry schema is proposed in three places: G4a (05-propulsion knowledge base), AS-16 and turbine-realism §7. EM-21 and CR-37 both promise mass conservation on detachment. G4b's per-tick state shift is superseded by the per-stage fixed-datum law. The plan names one home for each.

**Preserve:**
- the glow datum law and moment transfer;
- live-CG contacts;
- exhaustion localization;
- reset refuel;
- the trace's fuel-never-increases check (`app/sim/trace.gd:936-945`);
- the Extra generator's dry-then-fuel balance (`research/extra-300/ex05/derive_physics.py:122, 275-283`);
- Timber's inventory pattern (IDs, boxes, `energy_source: lipo`, provenance).

## 6. External sources

Source review of 2026-10-19:
- 21 new downloads live in the gitignored `references/rc-fuel-systems/` (about 86 MB).
- 8 manuals were re-read from existing `references/` folders.
- 15 web pages are recorded with access date and extracted values.
- [`sources.json`](sources.json) (openrc-reference-manifest v1) has the URL, size, SHA-256, licence and use of each. All 29 local hashes were re-verified.

Evidence kinds: **M** manufacturer-stated, **X** measured, **S** standard or specification table, **D** derived here, **R** hobby practice. Sources already in the repository are not repeated:
- NITRO-00/2T: 55AX 350 cc for 10–12 min; Saito FA-82B; AIAA 2016-5011.
- AV-18: JetCat flows.
- 05-propulsion: DA-100.
- AV-06: Krill CG.

### 6.1 Densities

| Fluid | Value | Temperature slope | Kind, source |
| --- | --- | --- | --- |
| Methanol | 796.1 (15 °C), 791.4 (20 °C) kg/m³ | −0.94 kg/m³/K | S, ISED-MEOH |
| Nitromethane | 1137.1 kg/m³ (20 °C) | not found | S, PubChem/CRC |
| Castor oil | SG 0.952–0.966; 0.957–0.961 at 25 °C | — | S, JECFA, USP |
| Synthetic glow oil | SG 0.997–1.006 (polyalkylene-glycol proxy; no glow-oil sheet found) | — | M, proxy |
| Gasoline E0–E15 | 715–775 kg/m³ (15 °C) | −0.92 kg/m³/K | S, WWFC-2019, ISED-GAS |
| Two-stroke oil | 0.862 kg/l (15 °C); 0.911–0.926 (20 °C) | — | M, Valvoline; Motul retailer copy |
| Jet A / kerosene | 775–840 kg/m³ (15 °C) | −0.74 kg/m³/K | S, ISED-JETA |
| Turbine oil | 1.0035 kg/l (15 °C) | — | M, Mobil Jet Oil II |

Blend densities (D), assuming ideal volume mixing at 20 °C. Nitro and oil are by volume:

| Blend | kg/m³ |
| --- | --- |
| 10/18 castor | 857 (equals the profile's 856.9) |
| 15/18 castor | 874 |
| 15/20 castor | 877 |
| 30/18 castor | 926 |
| 30/20 synthetic | 937 |
| Gasoline 745 kg/m³ + oil, 32:1–50:1 | 747–751 (oil moves it < 0.5 %; the gasoline batch spread dominates) |
| Kerosene + 5 % turbine oil | 810, range 786–848 (JetCat's kg/ml columns imply 800) |

Menon 2010's heating values for a 70/10/20 blend imply 874 kg/m³, against 860 from ideal mixing. Carry ±2 % for glow blends.

**What this means for the fleet:**
- The 0.80 and 0.82 g/ml glow values in the aircraft data are 4–7 % low.
- The P-51's 0.74 is at the low end of gasoline.
- The Ventage Jet's 0.80 is consistent.

### 6.2 Consumption

| Engine | Figure | Kind |
| --- | --- | --- |
| O.S. 40/46FX, 61FX, 91FX | 300 / 350 / 450 cc tanks "allow 12–13 minute flights", implying 24 / 28 / 36 ml/min mixed | M implied (OS-FX) |
| O.S. 55AX | 350 cc for 10–12 min, implying 29–35 ml/min mixed | M implied (in repo) |
| O.S. FS-64V | 220 cc for 12–14 min (the manual is inconsistent), implying 16–18 ml/min mixed | M implied (OS-FS64V) |
| Saito FA-62B (10.2 cc 4T) | about 20 cc/min at full throttle, 10,200 rpm | M (SAITO-62B) |
| O.S. 40FX / 46FX dyno | BSFC 1.39 kg/kWh at peak power (677 / 681 W), efficiency 11.8 % | X (MENON-2010) |
| 3W-100i gasoline | 485 g/kWh at peak; best 406 g/kWh | X (MOULTON-2007) |
| 28 / 55 / 85 cc gasoline | 14.9 / 15.4 / 18.3 % efficiency, about 560 / 540 / 455 g/kWh | X / D (Horn, AFIT 2015) |
| DA-100 / DA-150 | 71 / 93.5 g/min at 6,000 rpm | M (Barnard compilation) |
| JetCat P20-SX … P200 | idle/max 12/90 … 129/730 ml/min | M |

Glow burns about 2.4–3× more fuel per kWh than small gasoline two-strokes (both measured). No idle flow was found for glow or gasoline engines.

**Checks against the model:**
- **61FX:** the model gives 38.8–58.1 ml/min at full throttle, against 28 ml/min mixed and 35 ml/min at 1.3 kW × 1.39 kg/kWh. Plausible.
- **FS-64V:** the model gives 13.0 ml/min at static full throttle and 17.0 ml/min at 10,000 rpm. That is below the 16–18 ml/min mixed figure, and 15 % below the similar-size FA-62B's 20 cc/min at full throttle. The 4T flow looks low (F21).
- **P-51 DA-120 at the installed 6.9 kW:** 406–580 g/kWh gives 47–67 g/min, about 63–90 ml/min, or 11–16 min per litre at full throttle.

### 6.3 Tank sizing, placement and balance

- **Sizes (M):**
  - O.S.: 300–450 cc for .40–.91 glow two-strokes; 220 cc for the FS-64V.
  - Great Planes Extra 300S: 12 oz.
  - Top Flite Giant P-51 (30–60 cc gas): 16–24 oz.
  - DA-120: 32 oz or more.
  - Sullivan 16 oz tank: 146×68×59 mm (retailer).
  - The Stik's "8–10 oz" is below the 350 cc that the 55AX and 61FX manuals recommend (F22).
- **Glow tank height (M):** the three O.S. rules differ.
  - FX: tank top 5–10 mm above the needle.
  - 55AX: tank center level with the carburetor.
  - FS-64V: tank center about 10 mm below the needle, close to the engine "to minimize fuel level head pressure variation".
  - All three use muffler pressure, and a different silencer changes the needle setting. No pressure values are published.
  - (D) 10 mm of fuel at 1 g is 84 Pa; a 146 mm tank under 3 g is 3.7 kPa.
- **Gasoline (M):** DA-120: the carburetor "has a strong pump, so the tank can be mounted almost anywhere". DLE-120: vented, unpressurized tank.
- **Turbine (M):** Xicoy: tank center "as close to the CofG as possible … to minimize the effects of the CofG shifting", with a felt clunk. JetCat: short suction line, because cavitation causes flameout. Hopper/UAT starvation happens only when the hopper is empty.
- **Clunk and foam (M):**
  - The clunk must fall freely to the top when inverted (Hangar 9).
  - The O.S. non-bubble weight stops the pickup sticking to the wall.
  - Great Planes and Top Flite: vibration "may cause your fuel to foam, which will … cause your engine to run lean or quit".
- **Balance condition:**
  - Empty tank, stated explicitly: Great Planes Extra 300S 60 (p.43, "ready to fly and an empty fuel tank") and Top Flite Giant P-51D (M).
  - No fuel state given: Hangar 9 AT-6 and P-51 manuals.
  - Jets: full hopper, empty main tank (R; A200 owners in AV-06).
  - Krill Avanti 2.1 m: 240 mm with a full tank, 260 mm with landing fuel, "will fall back on its tail" when empty (M; same tank bay, different airframe).
- **Pilot effect (M):** Extra manual: aft CG is "agile/snappy", forward CG "smoother/stabler" and needs more speed. Its range is ±3/8 in (±9.5 mm) about the empty-tank point.
- **Unusable fuel volume:** no primary number found.

### 6.4 Simulator references and slosh

- **JSBSim** (`FGTank`, `FGPropulsion`, `FGMassBalance`, LGPL, master `17f165c`). Its ideas are used, not its code:
  - Tank fields: `location`, `drain_location`, `radius`, `inertia_factor`, `capacity`, `contents`, `unusable-volume`, `standpipe`, `priority`, `density` or fuel `type`, `temperature`.
  - The fuel centroid slides linearly from `location` to `drain_location` as the tank empties. Drain stops at the unusable amount.
  - Inertia is a "shrinking snowball" sphere plus the parallel-axis term.
  - Tanks feed by priority. There is no burn during trim.
  - Mass, CG and inertia are recomputed every frame, with no variable-mass terms in the equations of motion.
  - The fuel table has no methanol, nitromethane or premix entries.
- **YASim:** point-mass tanks at 6.0 lb/gal (6.72 with `jet`).
- **Slosh (D, Dodge 2000 eq. 1.19):**
  - A half-full 146 mm tank sloshes at 1.7 Hz lengthwise and 3.2 Hz sideways, close to RC short-period frequencies.
  - Its mass effect is bounded: 0.2 kg moving half the tank length in a 3 kg airplane shifts the CG by at most 4.9 mm.
  - No small-UAV slosh flight data and no RC-simulator fuel documentation were found.

### 6.5 Dead ends

- **Blocked or paid:** CRC Report 635 (DTIC blocked) and 663 (paid).
- **Not obtainable as files:** the Motul 800 data sheet (served as HTML); Red Line, Klotz, Cool Power and SIG fuel safety sheets; Dow UCON LB-165.
- **No data found:** consumption for DA-50, DA-120, DLE and 3W-55; idle flows; unusable volumes; muffler pressures; jet full/empty CG tables.
- **Not downloaded:** the Horn AFIT thesis (109 MB; abstract values used).
- **Broken links:** most Horizon manual URLs return 404.

## 7. Reproduction

```sh
cd research/fuel-systems/FUEL-00
python3 -I cg_shift.py ../../.. > cg_shift.out.json
python3 -I static_margin.py ../../.. > static_margin.out.txt
python3 -I glow_flow.py ../../.. > glow_flow.out.txt
python3 -I glow_feed.py > glow_feed.out.txt
for a in stik_glow_61fx_2t stik_glow_55ax_2t stik_glow_fs64v_4t; do
  python3 -I mass_kernel_compare.py ../../../app/data/aircraft/$a.json; done > mass_kernel_compare.out.txt
python3 -I datum_momentum.py > datum_momentum.out.txt   # about 25 s
```

These scripts are Python mirrors of the GDScript arithmetic, not runtime calls. Agreement shows the arithmetic, not physical validity.
