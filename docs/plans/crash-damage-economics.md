# Component damage, accident assessment and repair economics

2026-10-15 · **Owner:** crash track, **CR-28…38**, under [Crash and damage](../CRASH-DAMAGE-PLAN.md). **Status:** first playable economics slice implemented: generated USD sidecar, accepted-contact observer, integer-cent calculator and persistent accident report. Structural/thermal assessment, complete fleet valuation and physical qualification remain pending. See [CR-29…32 evidence](../research/crash-damage-investigations/CR-29-32/README.md).

## 1. Product outcome and boundaries

After an accident, show a prominent **estimated repair cost or total loss in USD**, explain what broke, and deduct only recoverable value supported by the assessment. A broken Stik propeller, a covering scrape and a destroyed turbine jet must produce different bills. A repairable airplane can still be an economic write-off; a destroyed airframe can still contain reusable equipment.

Start with the Jensen Das Ugly Stik 60. Deliver a small complete loop first: prop strike → one damaged propeller → sourced replacement cost → readable report. Extend the same component and event contracts to landing gear, structure, electronics, powerplants and thermal damage. Do not reduce this to speed multiplied by aircraft price, or price multiplied by the current C0–C4 visual class.

The [dated research](../research/crash-damage-investigations/CR-28/README.md) owns sources, prices and worked examples. The [JSON catalog](../../research/crash-economics/catalog.json) owns reusable offers; the [baseline and fleet data](../../research/crash-economics/aircraft-costing.json) owns valuation assumptions and missing coverage. The runtime sidecar is generated from these offline sources. No shopping, live pricing request or payment occurs during play. Reuse manufacturer manuals, parts diagrams, free plotting tools and existing crash assets before creating replacements.

**Ownership:** CR owns assessment, research and `app/economy/`; `app/damage/` remains proposed. SF/physics owns accepted contact/state integration; AS owns contract/schema and identities; D6-SAV owns servo products/specifications; AE owns installed Workshop configurations; GP/aircraft owners own gear and generated data; EM owns initiating failures; UI/HUD owns report presentation; CAM/AUD/model tracks consume the accepted result. CR-11–15 still owns damaged flight. This plan does not independently close those steps or Gate CR.

## 2. Existing behavior to preserve and improve

| Foundation | Reuse | Gap this plan must close |
| --- | --- | --- |
| [Contact observations](../../AIRCRAFT_CONTRACT.md#contact-observations-and-checkpoints) | Accepted tick, stable probe/support IDs, lifecycle, strike latch, swept scenery fraction | Gear impulses/kinematics can be unknown; buffer is bounded, not an accident history. Rejected steps must never create damage or a bill. |
| `app/render/crash/severity.gd`, CR-08b | Effective mass, normal/slapdown/abrasion channels, estimated surface response | C0–C4 is presentation, not strength or monetary loss. Slapdown is a bound, not an additional measured impact. |
| CR-01d/e and E3d2 | Named contacts, causal telemetry, a prop strike can stop the engine while flight continues | Accumulate nonterminal damage until landing/reset; do not require a terminal crash to report a propeller. |
| CR-09 wreck and CR-22 fire | Sections, mass-aware presentation, bounded aftermath | Visual debris/particle contacts and rendering frame rate cannot decide recoverability or change a bill. |
| [Physical identities](../../AIRCRAFT_CONTRACT.md#stable-physical-identities) | Inventory, contact, propulsion and control IDs | A probe, mesh section, economic part and physical mass item are different entities; declare their mappings. |
| [Savox plan](savox-servos.md) | Product identity, voltage/fit checks, physical versus price identity | Three logical servo states are not a count of physical servos. The Stik inventory has four physical units. |

The source reviewed on 2026-10-15 has eight airplane catalog configurations in five visual families, plus the experimental X-Cell/HX-700 helicopter route. Generated synthetic electric Stiks are test specimens, not another retail airplane. The catalog count and every route must be discovered at validation time rather than hardcoded.

## 3. Data contracts

### 3.1 Reusable parts and offers

Keep three identities separate: **product/specification revision**, **aircraft installation**, and **dated price observation**. A price refresh must not alter mass, strength, servo speed, replay physics identity or a saved accident report.

Each product needs a stable ID, manufacturer, exact model/SKU/revision, category, package contents and unit of sale. Each offer needs seller, market, original currency, integer minor-unit amount, observation date, direct URL, evidence quality, stock/condition, regular/sale/list distinction, tax/shipping treatment and pack quantity. Preserve list and sale offers separately. Do not turn an out-of-stock listing into an available purchase or a search snippet into a confirmed checkout price. If converted, retain original amount, FX source/date and rate; the initial catalog uses USD directly.

Select offers deterministically: exact product and condition, qualified seller/market, available regular offer preferred; otherwise mark a fallback, historical offer or cost proxy explicitly. No price is `0` merely because it is unavailable. Use `null` and expose incomplete coverage. Freeze the selected offer IDs and catalog hash when the session/build valuation starts. Proposed refresh policy: review prices after 90 days and flag older than 180 days, configurable and labeled a product policy. Expired sale prices need immediate rechecking. Existing reports keep their snapshot.

SAVOX is the established product-representation partner under [D6-SAV-00](../research/servos/D6-SAV-00/README.md). Other brands enter the catalog as unpartnered products or prospective contacts, with no implied endorsement. Partner status never changes damage resistance or salvage. Do not duplicate the servo specification database inside the economic catalog; reference its product revision when it exists.

### 3.2 Aircraft economics manifest

New aircraft submissions must include the cost dossier specified in the [aircraft contract](../../AIRCRAFT_CONTRACT.md#damage-and-cost-authoring-dossier). Proposed runtime format: a separately versioned `openrc-aircraft-economics v1` sidecar, not unrecognized fields inserted into the closed physical v2 JSON. Introduce loader/schema/module support before runtime integration.

Required content:

- Configuration ID and source hash, installation revision, assembly basis (`kit`, `ARF`, `PNP`, `BNF`, complete built aircraft), owned equipment and exclusions. Transmitter, charger and field tools are excluded from crash loss unless actually onboard.
- A bill of materials (BOM) of economic component instances with stable IDs, physical inventory bindings, quantities, product/offer references or explicit estimates, included-in-package relationships, and replacement alternatives. Every physical inventory item maps to one priced coverage group or an explicit nonpurchasable exclusion. Virtual balancing mass has no retail value.
- Binding from hull probes, gear contacts, joints and render sections to affected economic instances. One wing may contain a skin, spars, hinges and a servo; one airframe SKU may replace many damaged structures. Preserve those different granularities.
- Damage zones/materials/joints, installed electronics positions, energy-source location, fuel/pack capacity and supported state, inspection and repair recipes, salvage restrictions and applicable evidence intervals.
- Labor basis, materials consumption versus checkout purchase, incomplete coverage, uncertainty and asset provenance. Distinguish purchased kit price, completed airframe construction value and total assembled flyable aircraft value.

For the Stik, `item_fuselage_servos` covers three units and `item_aileron_servo` one central unit. Initially record group-to-economic-unit mappings and uncertain individual positions; do not pretend physical per-servo dynamics exist. Split inventory through its authoring owner before individual hardware failures/loads are simulated. A 6 V/HV catalog servo is not automatically a compatible replacement for the baseline 4.8 V installation. A price proxy does not replace hardware in the solver.

### 3.3 Damage state and assessment result

Keep physical condition separate from disposition. Suggested component channels: skin abrasion/tear, joint looseness, bending/crush, fracture/detachment, contamination/water, electrical damage and thermal dose. Track functional availability separately. Disposition is `reuse`, `repair`, `replace`, `inspect`, `unrecoverable` or `unknown`.

An `AccidentAssessment` contains incident ID, event range/ticks, input/source/solver identities, configuration and price hashes, evidence/model versions, component states, repair actions, salvage decisions and estimates. Also record causal labels with confidence, unresolved items, completeness, and `provisional`/`final` status. A likely stall is explanatory context; it cannot itself add a repair charge.

## 4. Contact-to-damage calculation

### 4.1 Accepted event pipeline

1. At accepted ticks, collect contact observations and physical failure events in stable order. Key them by session, tick, source, contact ID and event sequence. A strike and hull onset describing one impact are linked, not billed twice.
2. Build a contact manifold/episode: new impact, sustained rubbing, rolling support, separation, subsequent impact. Integrate persistent-contact work once per accepted interval. Paused frames, rejected RK candidates and duplicate notifications contribute nothing.
3. Resolve damage locally, then propagate loads through declared joints. Record damage monotonicity during the incident; repairs are separate transactions. Order-independent simultaneous-contact handling is required.
4. Queue each accepted change and recompute available repair choices at the frame boundary, coalescing pending changes. Cost computation, UI publication and file access stay outside accepted-tick callbacks and the 240 Hz force evaluator. Evidence revisions/ticks are assigned during ingestion, so publication cadence cannot change the result. Runtime uses preloaded products, bounded arrays and integer cents.
5. Freeze an incident report after settling and the modeled thermal horizon. When the player skips the aftermath, finish the same bounded deterministic assessment, or retain a clearly provisional report; skipping must not improve salvage. Restart archives the report before clearing flight-local state.

The session/vehicle adapter installs evaluators through `VehicleModel`; no aircraft-specific branch enters `Simulation`. Pure presentation observers can ship first without influencing motion. When damage affects flight, it enters the vehicle-owned state layout, derivatives, reset, checkpoint and rollback contracts; debris masses and inertia are conserved at the accepted handoff.

### 4.2 Local impact kinematics and energy accounting

All physics uses float64 scalars/packed arrays. For contact arm `r` relative to CG and outward unit normal `n`, in a common frame:

```text
v_rel = v_CG + omega × r - v_obstacle_at_contact
v_n   = max(0, -dot(v_rel, n))
v_t   = v_rel - dot(v_rel, n) n
1/m_eff = 1/m + (r × n)^T I^-1 (r × n)       # immovable obstacle
E_n   = 0.5 m_eff v_n^2
J_n   = (1 + e) m_eff v_n                    # isolated rigid impulse estimate
E_diss = 0.5 m_eff (1 - e^2) v_n^2
W_slide = integral max(0, -F_t · v_t) dt
K_body = 0.5 m |v_CG|^2 + 0.5 omega^T I omega
K_rotor = 0.5 I_shaft Omega^2
```

For a movable obstacle, add its inverse-mass and rotational terms. Tree trunk, branch, foliage, soil, asphalt, water and a vehicle have different compliance and contact geometry. A central trunk strike cannot be treated as a soft canopy brush. Sweeps/continuous event location must prevent tunneling at 41.67 m/s: a 240 Hz tick covers about 0.174 m.

Use actual accepted impulses and dissipated work when available. The formulas are isolated-impact estimates when the solver cannot supply them; mark that distinction. Do not multiply `E_diss` by another untracked transfer factor and call it measured absorbed energy. Partition dissipated work into aircraft deformation, obstacle deformation, friction/heat and other losses with nonnegative shares totaling at most one. Joint redistribution moves that allocation; it does not create energy.

For simultaneous contacts use the coupled contact solution, or a documented conservative episode budget, instead of independently spending the full body energy at every probe. Later impacts receive the remaining kinetic energy plus actual work from gravity/propulsion. Rebound energy remains in motion. Do not charge CR-08b's speculative slapdown bound and then charge the same actual belly impact again. Price calculation never consumes particle energy or presentation scatter energy.

`F_average ≈ J/dt_contact` or `E_absorbed/stopping_distance` can illustrate load only when duration/distance is known or explicitly assumed. Tick length is not contact duration; speed alone does not give a credible peak force. Propeller contact adds shaft-energy/work and shaft/mount load paths; a cheap propeller strike may require engine/motor inspection without automatically destroying the powerplant.

### 4.3 Component failure laws

Begin with declared failure envelopes per component family, confidence and low/nominal/high bounds, not arbitrary universal joule cuts. Example criteria where supported:

```text
sigma_bending = M*c/I_section
utilization = max(|sigma|/sigma_allow, |tau|/tau_allow,
                  strain/strain_allow, joint_force/joint_limit)
fracture_damage_increment = absorbed_fracture_work / fracture_capacity
abrasion_increment = sliding_work / calibrated_wear_capacity
```

Keep elastic load exceedance, plastic deformation and irreversible fracture distinct. Do not add all utilization channels as though each were independent measured fracture energy. Joint strength and grain/laminate orientation can dominate the material coupon rating. These are proposed reduced models; numeric capacities await CR-07 measurements or explicitly bounded gameplay estimates. Accumulated fatigue belongs to a later persistent-maintenance extension, with its own evidence.

| Component/event | Required signals and consequence | Cost treatment |
| --- | --- | --- |
| Film scrape | Contact area/path, abrasion work; inspect skin and underlying rib/spar | Clean/scuff can cost zero; covering-only puncture uses a patch recipe. Structural damage prohibits the cheap patch outcome. |
| Wing/root/tail | Root bending/torsion, joint path, crush and actual secondary impact | Repair skin/ribs if feasible; spar/root separation can require wing or whole airframe replacement. No bill per visual splinter. |
| Propeller/spinner | Blade/disk intersection, RPM, rotor work, shaft impulse | Replace damaged prop; assess spinner separately; inspect crankshaft/bearings/motor mount. Broken blades are never patched for salvage. |
| Fixed gear | Compression, stroke, side load, mount moment, ground snag | Leg, axle, wheel and mount are distinct repair options. Stik has fixed gear, not retracts. |
| Retracts | Deployment/lock state, actuator/trunnion/strut loads, mount failure, controller | Single leg/trunnion repair, complete retract unit or set depending on sold parts; charge included controller/brakes once. |
| Servo/linkage | Local shock, case/mount/gear/spline condition, commanded versus achieved motion, heat/water | Reuse after simulated inspection; gear-set repair only for a compatible sold kit and otherwise viable servo; replace failed electronics. |
| Receiver/power wiring | Local shock, antenna/connectors, supply fault, heat/contamination | An intact outer case does not prove reuse; inspection or replacement. Receiver protocol/voltage must match. |
| Glow/gas/turbine | Mount/firewall load, shaft damage, ingestion, fuel/oil path, thermal state | Distinguish replaceable muffler/carburetor, repair/inspection and destroyed engine. Turbine inspection quote can remain unknown. |
| Electric system | Prop/motor mount, motor shaft, ESC short/heat, pack crush/puncture/SOC | Pack, ESC, BEC and motor are independent; damaged pack has no serviceable salvage credit. |
| Water/lost aircraft | Impact first, then immersion duration/salinity/energized state; physical retrieval | Unknown recovery remains provisional; unretrieved components get no realized salvage. Water contact need not shatter the airframe. |

Cover stalls/spins, overspeed/flutter or in-flight separation, hard/asymmetric/gear-up landings, ground loops/cartwheels, tree/fence/building strikes, prop strikes, water and flyaway. EM can initiate a failure, but the same downstream contact/thermal/economic logic handles the resulting accident. Current aerodynamic models do not automatically establish flutter or structural overspeed; unsupported initiators remain unavailable.

## 5. Thermal and electrical aftermath

Mechanical damage can rupture a tank, puncture a pack or cut wiring. Fire additionally requires a compatible energy source, ignition mechanism and exposure; severity class alone is insufficient. A stopped engine may still be hot. Multiple sources can coexist, including a turbine's receiver LiPo. Use installed positions and shielding, not the label “central hit.”

For a future reduced thermal network, per component:

```text
m_i c_i dT_i/dt = Q_in,i - h_i A_i(T_i-T_air) - Q_out,i
thermal_dose_i = integral max(T_i - T_damage,i, 0) dt
fuel_remaining_next = max(0, fuel_remaining - burn_rate*dt)
E_electrical_nominal_J = 3600 * nominal_voltage_V * capacity_Ah * SOC
```

Use heat capacities/transfer/critical doses only with provenance and validity bounds. Electrical stored energy is not the total fire heat of a LiPo; electrolyte and surrounding combustibles add chemical energy. Fuel depletion and any battery internal-reaction model require their own mass/energy budget. Do not claim a quantitative fire model from particle lifetime.

| Source | Planned state progression | Economic effect |
| --- | --- | --- |
| Glow/methanol blend | Leak, optional ignition near a hot source, low-visibility flame, charring/extinction | Correct the existing stain-only presentation assumption for damage purposes. Nearby fuel-soaked wood/electronics can be lost despite faint flames. |
| Gasoline | Leak/vapor/ignition, local fire and spread, source exhaustion | Value surviving remote parts independently. No automatic whole-aircraft fire. |
| Kerosene turbine | Tank/line rupture plus hot section/ignition; leak, sustained burn, propagation | Airframe, turbine, ECU, pump, retract controller and radio have separate locations and coverage. |
| LiPo/electric | Crush/puncture/short → quarantine; possible delayed heating, venting and runaway | Damaged pack replaced even without flame; thermal exposure can later revoke provisional servo/receiver salvage. Not every impact burns. |
| No relevant energy source | Mechanical/abrasion/immersion only | No fire surcharge. NiMH is not silently classified as LiPo. |

Manufacturer guidance supports delayed LiPo hazards and rejection of damaged packs, but not a universal ignition probability or 5–30 s delay. First release uses deterministic, labeled scenario rules and sensitivity ranges; if stochastic variability is later used, seed once per incident/component, persist the draw, and keep correlated damage through shared zone exposure. Do not reroll salvage on reopening a report or refreshing prices.

## 6. Repair, replacement and salvage accounting

### 6.1 Choose feasible repair packages

Build a small graph of economic coverage. A replacement wing covers its skin/ribs/spar and any explicitly included hardware; a BNF package may include receiver/servos/motor/ESC; an ARF generally does not. Every required repair action must be covered once. Choose the cheapest feasible set of sold packages and supported repair recipes, respecting availability, compatibility and repairability. Bounded enumeration or dynamic programming is sufficient for the first BOM; do not build a general purchasing service.

```text
C_repair = parts_and_consumables + labor + inspection + required_disposal
C_replace = equivalent_complete_build + commissioning + required_disposal
            - realizable_salvage_credit
C_incident = min(C_repair, C_replace) among feasible, sufficiently priced options
```

Here `equivalent_complete_build` excludes any commissioning charged on the next term. If the selected assembled-build valuation already includes final assembly/commissioning (as in the CR-28 example), that next term is zero additional cost. Labor cannot appear in both places.

An unavailable structural repair is infeasible, not free. “Structural total loss” and “economic total loss” are separate report labels. The economic crossover is `C_repair >= C_replace`; a configurable 80% repair-to-replacement warning can be a game policy, not an insurance/engineering fact. Unknown essential prices produce a range/partial report and prevent claiming an exact total.

Use integer cents and explicit rounding (half-up at billed line boundaries); retain full precision for area/work calculations. Taxes, shipping, recovery and disposal are separately optional. Initial game bills exclude tax/shipping and show that exclusion. Do not silently add an hourly rate: DIY and paid-labor profiles have separate values and ranges, labeled assumptions when not quoted.

### 6.2 Salvage is a disposition, not a discount slider

Reuse requires recovered hardware, component-specific eligibility and the chosen inspection outcome. Inspect servos for gears, spline, case, leads, operation under load and centering; receivers for supply/connectors/antennas and radio operation. These are simulated assessment criteria, not a certification of a real wreck. Burned, flooded-with-uncertain-condition and unresolved critical electronics remain quarantined/unknown until the assessment resolves them. No automatic “all servos survive C3” rule.

Choose **one** credit basis for each part:

- **Reuse in a component-built replacement:** avoided purchase cost of that exact required item, capped by the replacement BOM line. Also retain required inspection/refit labor. Never subtract it again after omitting that purchase.
- **Sell after buying a complete package:** estimated used/residual sale value, with explicit condition/factor/source. Do not subtract new retail value merely because a spare servo exists.
- **Unknown pending inspection:** provisional credit interval `[0, eligible maximum]`; the final discrete game outcome records its inspection result. An expected probability-weighted salvage figure may be a forecast, not a realized refund.

Salvage cannot include an item already counted as repaired/reused in the chosen repair option, nor exceed covered replacement value. An engine sold with a muffler does not generate two full engine credits. Debris fragments have no independent product value. Persistent inventory, if added later, must transfer each serial/instance once to prevent reset/salvage farming.

The research Stik uses generic hardware and commercial price proxies. Its numeric servo-credit examples exercise the same hypothetical valuation basis on both sides of the ledger; they do not establish that SAVOX servos are installed or recoverable. Runtime reporting must retain an unknown/proxy label until installation identity and disposition are known.

### 6.3 Covering and labor example rules

For a repairable film-only hole, use `patch_area = (tear_length + 2*overlap)*(tear_width + 2*overlap)`, then layout/waste and color constraints. Consumption cost is `roll_price * used_area / usable_roll_area`; a $25 roll need not mean $25 consumed by a tiny scratch. Checkout cost rounds purchases to whole rolls when workshop stock is empty. Show material usage and cash purchase separately, carrying leftover stock only if the inventory mode exists. Add compatible adhesive and labor once. A foam Timber repair uses a material-compatible foam/adhesive recipe, not hot film by default.

## 7. Fleet rollout and configuration accounting

| Configuration/family | Required cost and damage model | Initial research/qualification action |
| --- | --- | --- |
| `jensen-das-ugly-stik-60` | Built-up balsa/ply, film, fixed tricycle gear, MAX-61FX, APC 12×6, four servos, receiver and NiMH pack | Complete proxy-valued BOM first; historical Jensen exact assembled quote unresolved. Exclude virtual balancing mass from price, retain it in physical mass. |
| `stik-glow-61fx-2t` | Same actual parts, different engine simulation law | Inherit BOM once; model law change alone does not change price. Separate physical identity. |
| `stik-glow-55ax-2t` | Replace engine/prop/installation rows as authored | CR-36a implements reconciled economic coverage: 55AX/silencer package plus APC LP12070; stock-silencer revision remains a price proxy. Physical mount/performance qualification remains open. |
| `stik-glow-fs64v-4t` | FS-64V installation, valve/pushrod/muffler risks | CR-36a implements reconciled economic coverage: FS-64V/F-4051 package plus K Series 14×6. Four-stroke service recipes and independent mass/load validation remain open. |
| `gp-extra-300s-60` | Low-wing balsa .60 glow; its own gear/mounts/servo topology | Historical airframe replacement/proxy dossier; engine price reuse only if exact installed model matches. |
| `p51d-mustang-120` | 2.82 m warbird, DA-120 gasoline, retracts, doors, multiple control servos, ignition/power | Giant-scale parts and pair/set quantities; cannot use .60 gear pricing or a small foam P-51 retail value. Coordinate active P51 generator work. |
| `sebart-avanti-s-a200-p100rx` | 2 m Ventage Jet, JetCat P100-RX, turbine accessories, fuel, retracts/brakes | Price a matched 100 N installation. A 200 N turbine or generic gear set is a comparison only. Retract landing outcomes wait for deployed-gear physics support. |
| `turbo-lumber-evolution` | Foam electric STOL, fixed gear, motor/ESC, 4S pack, installed electronics | E-flite reference products are cost proxies for the fictional aircraft. PNP/BNF includes differ; pack usually separate. Whole-wing replacement and foam repair compete. |
| `xcell-60-research` / HX-700 visuals | Experimental rotorcraft, main/tail blades, shafts, gears, frame, engine and cyclic/tail electronics | Separate physical X-Cell BOM; never price its HX-700 visual surrogate as the installed helicopter. Extend rotorcraft contract and local rotor-energy accounting before coverage. |
| Electric Stik fixtures, alternate prop specimens, future EDF/drone/jet | Actual configuration, pack count and propulsion-specific parts | Test fixtures explicitly `not_market_valued`; future products require their own dossier. EDF fan/duct is not a combustion turbine. |

Each priced aircraft must report both known-value coverage and uncovered required items. Do not publish a fleet total obtained by assigning Stik percentages to every aircraft. Catalog products can be reused; installations and fracture evidence cannot be inherited merely from visual resemblance.

## 8. Player-facing accident report

The final crash card must make the money result its dominant element. Proposed 1280×720 layout: centered or lower-center panel with **48–64 px** cost text, at least 32 px at the smallest supported scaled viewport, no clipping at supported UI scales. UI owners validate actual readability. Example copy: **“ESTIMATED LOSS · US$…”**, **“REPAIR · US$…”**, or **“ASSESSING DAMAGE…”**. A total-loss subtitle explains whether structure or economics decided it.

Immediately show a provisional amount/range after the initial assessment. Replace it with a final amount after aftermath evaluation; visibly identify pending fire/inspection effects and announce material revisions. Never call a partial subtotal the total. The player can expand parts, labor, salvaged equipment, assumptions, source date and estimate range. Show large headline amounts rounded to whole dollars and retain cents below US$100; always show cents in the breakdown. USD is explicit in English and Spanish.

Buttons: inspect wreck, damage breakdown, replay incident, restart. Preserve the result until an intentional action; do not hide it behind the old automatic crash restart. Do not obscure the aircraft during a continuing nonterminal prop strike or wing brush: show a compact damage notification, then a large report on landing/session end. Respect pause, input focus, controller navigation, screen scaling, reduced motion and color-independent statuses. Reopening/replaying the report never rebills it. Initial mode is educational estimated loss; campaign wallets/insurance/rewards are separate future product decisions.

## 9. Delivery steps and acceptance

| ID | Work | Proof/status |
| --- | --- | --- |
| CR-28 | Source audit, USD catalog seed, Stik BOM, worked examples and fleet gaps | This planning delivery; observed prices are not checkout guarantees. Validator checks IDs, citations, dates and arithmetic. |
| CR-29 | AS/AE/SAV economic sidecar, coverage schema, versioning and compatibility rules | Implemented first schema/loader: all nine routes represented, exact physical source binding, duplicate/orphan/unknown-price checks. Full compatible BOMs remain CR-36. |
| CR-30 | Read-only incident accumulator and prop-only first release | Implemented accepted prop strike, bounded deduplicated history with overflow-safe confirmed facts, frame-boundary valuation, reset/checkpoint, healthy-state parity and supported-rest promotion. Full damage replay remains pending. See CR-30/32-R1 in the evidence. |
| CR-31 | Stik repair and salvage calculator | Implemented integer-cent repair/replacement comparison, conditional salvage and incomplete estimates. Full package optimizer, labor-mode selection and physically qualified salvage assessments remain pending. |
| CR-32 | Large report UI and persistent incident record | Implemented large English/Spanish terminal and nonterminal settled reports, breakdown, inspect/restart for terminal incidents, controller hooks and bounded latest-report archive. Settled cards collapse on renewed movement. See evidence for tested viewports; owner readability and target-host qualification remain open. |
| CR-33 | CR-07 structural evidence and component resolver | Pending. Joint/material data, explicit uncertainty, isolated impact/abrasion/rotor cases, energy accounting and threshold sensitivity. No acceptance from self-fit fixtures alone. |
| CR-34 | Fixed/retract gear, secondary impacts, scenery and water | Pending. GP/LU/SF integration; asymmetric/locked/retracted gear, mount failure, swept 150 km/h obstacle contacts, cartwheel and retrieval cases. |
| CR-35 | Fuel/electric thermal damage and post-fire salvage | Pending. Source-budget bounds, no-source/no-ignition cases, delayed/absent LiPo ignition, remote component survival, skip/LOD/frame-rate independence. |
| CR-36 | All eight airplane configuration dossiers and dedicated rotorcraft extension | Partial: [CR-36a](../research/crash-damage-investigations/CR-36a/README.md) adds guarded engine/prop substitutions for 55AX and FS-64V. Four Stik routes have complete modeled inventory cost coverage with estimates; the other five routes remain incomplete. Physical compatibility, full fleet BOMs and independently reviewed crash/repair cases remain pending. |
| CR-37 | Damaged-flight integration through CR-11–15 and EM | Pending. Conserved mass/CG/inertia on detachment, actuator/electrical dependency failures, checkpoints and rollback, aircraft-specific validation. |
| CR-38 | Release, calibration review and catalog upkeep | Pending. Complete matrix, pinned catalog, offline packaged assets, physical/pilot acceptance and target-host timing. Gate CR remains independent. |

CR-30→31→32 is the first playable slice and can precede structural/thermal simulation. CR-33 needs CR-07; CR-34 needs relevant contact support; CR-35 needs component energy/thermal state; CR-37 cannot ship before its existing physics prerequisites. No full finite-element solver is required for that first slice.

## 10. Required regression and validation matrix

| Case | Required result |
| --- | --- |
| Light brush, intact film | Zero material repair allowed, inspection status explicit; no wing replacement. |
| Covering-only tear | Patch consumption versus purchase distinguished; spar damage switches to another recipe. |
| Powered prop strike, otherwise intact Stik | One prop replacement plus any evidenced inspection; no automatic whole engine or aircraft write-off. |
| Direct Stik trunk collision at 150 km/h | Near-total airframe loss benchmark; mechanical assumptions visible, no speed-only universal rule; conditional servo salvage deducted once. |
| Same speed, glancing foliage | Local normal velocity/compliance governs; not forced to match direct trunk outcome. |
| Hard landing on fixed gear / retract jet | Strut, mount and retract package coverage differ; no generic cost multiplier by aircraft price. |
| Destroyed airframe, two/four reusable servos | Separate exact cent-credit cases; pending inspection gives a range; heat can invalidate provisional credit. |
| Electric impact without runaway / with delayed runaway | Pack replacement in both if damaged, additional thermal losses only in the latter. |
| Glow fire / cold leaked turbine fuel / hot leaked turbine fuel | Low-visibility burn can damage; no fire without modeled ignition; no fixed C4-only ignition rule. |
| Same incident at 30/60/144 render FPS, effects disabled, camera far away | Identical physical damage and monetary report on the qualified platform. |
| Restore, restart, duplicate events, rejected tick, price refresh | No reroll/double charge; old report immutable; rollback leaves no damage. |
| Missing price, discontinued kit, package containing electronics | Explicit incomplete/proxy status; no $0 missing item or kit-plus-parts double count. |

Use current [test commands](../TOOLS.md) and [flight logging workflow](../FLIGHT-LOGGING.md). Before a physics-affecting slice preserve a baseline `.orfl`, verify exact replay, then compare the explicit candidate with the same input tape and source/config identities. Record `solver_changed`, `complete`, markers, CSV and reports. Do not re-record goldens for pricing/UI work. Recovered prefixes and deterministic software tests do not validate crash realism.

Validate analytic central/off-center effective mass, units, zero contact, energy partitions, translation/rotation, multiple contacts and timestep refinement before tuning aircraft behavior. Use repair invoices, teardown reports, manufacturer replacement policies and non-destructive material/joint measurements where available; do not manufacture physical validation by tuning to the examples in this plan. Keep held-out incidents and expert review separate from fitting. Avoid deliberate dangerous full-aircraft crashes as a data-acquisition prerequisite.

Measure bounded accumulator overhead inside the existing 500 µs physics budget; price lookup must not add network/I/O to ticks. Proposed report budget is under 10 ms for a 100-part BOM on the accepted host, with timing reported rather than assumed. Test dense scenery, repeated scraping and thermal aftermath; cap event storage with explicit overflow/incomplete reporting, never silently discard costly damage. Reuse downloaded specifications/assets under their licenses and existing analysis tools.
