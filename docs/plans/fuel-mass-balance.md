# Fuel, mass and balance

Code and aircraft data define implemented behavior. This is the single guide and remaining-work list for `FUEL-00`…`FUEL-14`, owned by physics with the aircraft, NITRO, AV, AS, AE and presentation owners. Checked 2026-10-19. The [aircraft contract](../AIRCRAFT_CONTRACT.md) owns field syntax and frames; this page owns shared fuel behavior and completion scope.

## 1 Conclusion and scope

Fixed-wing sessions implement finite glow fuel, gasoline BSFC and turbine-map consumption, live mass properties, start-fill/reset policy and fuel-aware diagnostics. A tank declaration alone does not enable consumption: the accepted aircraft data must select a supported energy/propulsion adapter. Prescribed-fuel references keep fixed mass. Battery energy belongs to BAT and does not consume pack mass.

Software implementation does not establish physical validation. Pickup coverage, line/hopper transfer, smoke-fluid depletion, broader vehicle adoption and measured qualification remain separate work below. Original audit findings, numbers and proposed repairs live in [FUEL-00-R1 evidence](../research/fuel-systems/FUEL-00-R1/README.md#findings-at-the-audited-baseline); its Word export is historical.

## 2 Audit of the current tree

Use these source boundaries to resolve discrepancies. Dated audit results do not override newer code.

### 2.1 What is implemented

| Boundary | Implemented behavior and source |
| --- | --- |
| Registry and tanks | [Fuel registry](../../app/data/fuels/openrc-fuel-registry.json) and [loader](../../app/physics/aircraft_data.gd) resolve stable tank/liquid/shell IDs, blend density, capacity, unusable mass, reserve and declared balance state. Glow installation checks registry identity and blend compatibility. |
| Resource laws | [Glow installation/flight](../../app/physics/glow/flight.gd) consumes its explicit installation. [LiquidFuel](../../app/physics/liquid_fuel.gd) implements `gasoline_bsfc_v1` and `turbine_map_v1`; [LiquidFuelFlight](../../app/sim/liquid_fuel_flight.gd) integrates one active store, preserves residue and locates usable-fuel exhaustion. |
| Mass and dynamics | [MassInventory](../../app/physics/mass_inventory.gd) derives mass/CG/tensors; [FixedDatumBody](../../app/physics/fixed_datum_body.gd) keeps the body reference fixed while resources change. |
| Accepted samples | [FlightSession](../../app/sim/flight_session.gd) and [FuelSample](../../app/sim/fuel_sample.gd) expose tick/time, mass, CG, inertia, typed stores, volume, fill and reserve. Queries are detached and read-only. |
| Consumers | HUD and crash consumers use live samples. Crash `fuel_by_kind_kg` is typed; legacy `fuel_kg` remains explicitly kerosene-only. Contact samples label their time or accepted-endpoint approximation. |
| Recording and restore | `.orfl` and CSV record mass/CG. Checkpoints retain actual resource state and a separate launch-fill selection; legacy reads mark missing selection provenance unknown. [Logging workflow](../FLIGHT-LOGGING.md). |
| Workshop | Dry-weight, geometry and tank-capacity transforms are separate. The [Workshop guide](../AIRCRAFT-WORKSHOP.md#scale-policy) owns bounds, formulas and current module/descriptor support. |
| Fleet report | [Mass/balance report](../../research/fuel-systems/mass_balance_report.py) scans recursively, includes catalog battery modes and supported data variants, and checks catalog coverage. `--fail-on-drift` makes stored-report drift fatal; `--qualify` also requires neutral-point estimates. |

### 2.2 Open findings and disposition

The [original A1…A10 findings](../research/fuel-systems/FUEL-00-R1/README.md#findings-at-the-audited-baseline) describe an earlier source snapshot. Several mechanisms they requested now exist: typed crash fuel, checkpoint fill provenance, ID/capacity/blend binding, rotational glow feed, mass traces, recursive reporting and fuel event units. Their presence does not close every production-path, fleet, performance or physical gate. Use section 4 for remaining work and section 5 for verification.

## 3 Common standard

### 3.1 Data and ownership

Use the [v2 contract](../AIRCRAFT_CONTRACT.md#capabilities-and-conditional-modules) and source generators. Quantities retain units, evidence kind and provenance. Registry density and tank geometry determine liquid mass; names and inventory ordering do not select a store. Inventory hardware does not activate its dynamics.

NITRO owns glow laws/feed/lifecycle; aircraft owners own gasoline/turbine installation data; AS owns schema/modules; physics owns shared state/mass contracts. UI/HUD/CR/AUD/EM/AE consume accepted data. No aircraft-specific branch belongs in `Simulation`.

### 3.2 Frames mass and balance

The solver datum O is the authored reference-inventory CG and stays fixed across burn, selected fill and reset. `balance.plan_cg` validates the declared balance state and does not move O. Live samples give CG relative to O and inertia about that live CG. The [coordinate contract](../AIRCRAFT_CONTRACT.md#coordinates-signs-and-units) owns conversions and force-arm signs.

The existing fixed-datum law assumes co-moving efflux. It does not add exhaust thrust, jet damping or mass-derivative spin-up terms. Tanks retain fixed geometry/centroids; slosh and general internal transfer are not admitted by this law alone.

The loader checks a CG range at the declared balance state. Full/empty reports and estimated static margins are additional diagnostics, not physical handling validation or automatic range enforcement at every fill. Separate main/hopper balance states require explicit schema and runtime support.

### 3.3 Flow feed and exhaustion

Consumption is kg/s. Glow retains its cycle/thermal model. Gasoline uses the authored idle flow plus BSFC applied above its idle-power reference; stopped flow is zero. Turbines use their authored RPM/flow map. These are supported model laws, not identified installed hardware.

Unusable liquid remains onboard after usable-fuel exhaustion. Glow feed uses total fill and same-stage translational/angular apparent acceleration with a bounded pressure/flow solve. Its box free surface is an estimate; it does not simulate clunk coverage, fuel-line inventory or hopper transfer. A declared pickup/feed label does not implement those mechanisms.

RK-stage queries remain pure. The model supplies state layout, event projections and lifecycle through the shared kernel. Exhaustion commits nonnegative usable fuel and source cutoff; glow event residuals use `fuel_residual_kg`. Cutoff/coast-down does not establish a qualified turbine ECU, freewheel or restart envelope.

### 3.4 Samples checkpoints and consumers

Use `FlightSession.mass_properties()` for accepted endpoint state. Contact samplers can interpolate inventory at a swept contact; consumers must retain the declared sample time/basis. Do not substitute starting wet mass for live mass, infer a reset fill from remaining fuel, or sum the legacy kerosene scalar as total fuel.

Home offers full/75/50/25 percent for finite-fuel selections. Direct flights accept `--fuel=<fraction>` with `0 < fraction <= 1`; the default is full. Initial usable mass, model and trim checks still apply. Reset uses the selected launch fill. Current checkpoints preserve that selection; a legacy checkpoint without it retains the destination reset setting and marks provenance unknown.

Keep recordings bounded and read-only. Use the [flight logging workflow](../FLIGHT-LOGGING.md) for exact replay and one-candidate comparisons. Candidate/recovered outputs never establish exact equivalence or physical realism.

### 3.5 Admission of future aircraft

A new finite-fuel configuration needs an owning generator, registered blend, stable tank bindings, supported propulsion/energy law, compatible module/descriptor data, balance declarations and lifecycle tests. A structurally valid tank or catalog entry is insufficient. Label estimated capacity, geometry, reserve and consumption; include source identity and uncertainty with physical measurements.

## 4 Work packages and execution order

This table owns remaining FUEL work. Implemented code is summarized above; historical proof stays with its source snapshot. A code slice does not automatically close its wider step.

| IDs | Present in code | Remaining work / acceptance |
| --- | --- | --- |
| FUEL-00…04 | Registry, tank normalization, shared fixed-datum mass law | Retain [original evidence](../research/fuel-systems/FUEL-00/README.md) and momentum/refinement records; physical calibration is separate. |
| FUEL-05-R1 | ID/capacity/blend binding; recursive report and explicit drift mode | Complete fleet generator/module/descriptor conformance and reproducible report/replay evidence; resolve missing ranges/neutral points explicitly. |
| FUEL-06-R1 | Accepted mass/store samples, typed crash fuel, CSV/`.orfl` channels and contact sampling | Qualify all production consumers and contact/event boundaries; retain R05-B/free-rotor handoff limits. |
| FUEL-07-R1 | Selected start fill, reset and checkpoint provenance policy | Complete per-aircraft full/low-fill, legacy restore, JSON and exact-replay coverage. |
| FUEL-08 | Finite glow, gasoline and turbine adapters; typed fuel residuals | Finish fleet installation, flow/stop/restart and exhaustion-domain qualification. |
| FUEL-09 | Glow pressure/head and rotational apparent-acceleration feed | Pickup coverage, line/hopper inventory and transfer, conservation and deterministic starvation/recovery. |
| FUEL-10 | Accepted ml/fill/reserve samples and low-fuel warning inputs | Complete presentation/audio/economy integration and readability acceptance; smoke liquid remains separate. |
| FUEL-11 | Dry-only weight and separate tank-capacity transforms | Target-CG/ballast editing, complete family eligibility and identity/replay qualification; [Workshop](../AIRCRAFT-WORKSHOP.md) owns its UI. |
| FUEL-12 | Existing log/replay and flight-test tools | Retain exact baseline plus one candidate with matching tape, source identities, markers, CSV and completion reports for each promoted configuration. |
| FUEL-13 | Measurement reducers exist | Identified empty/full weighing, CG and burn measurements with calibration and uncertainty; physical gate remains open. |
| FUEL-14 | Shared contracts available | Separate HELI/RCV adoption and native/backend/vehicle qualification; no implied fleet-wide integration. |

Prioritize conformance and production-consumer gaps before new feed mechanisms. AV, NITRO, AS, AE, EM and CR retain their [track boundaries](../README.md#tracks-plans-and-step-ids). This list supersedes old G4a/G4b and X-DATA-11 proposals. Battery energy stays with BAT; dynamic slosh, foaming, fuel-temperature dynamics and fire simulation remain outside scope.

## 5 Acceptance gates and evidence

### 5.1 Software completion

1. Run the relevant schema, generator, module/descriptor and session checks in [TOOLS](../TOOLS.md); inspect exit status and engine errors. Invalid bindings or unsupported laws must refuse flight.
2. Cover full/low/reserve/exhausted mass and tensor oracles, located events, rollback, reset and checkpoint identity. Include production crash/HUD/trace consumers, not only helpers.
3. Check the independent fleet report without changing data:

```sh
python3 research/fuel-systems/test_mass_balance_report.py
python3 research/fuel-systems/mass_balance_report.py --check research/fuel-systems/mass_balance_current.json --fail-on-drift
```

`--qualify` adds the missing-neutral-point policy. A stored report is a snapshot: regenerate it only through its tool after reviewing intentional source changes. Passing focused tests is not a complete suite or target-host performance result.

### 5.2 Aircraft and physical qualification

Retain source/configuration identity, full/start/reserve/empty mass reports and declared-state range checks. Re-record goldens only for explained physics changes. Use exact baseline replay before candidate/flight-test comparisons; keep `solver_changed` and `complete` visible.

Close physical validation only with actual weighing, CG and burn observations, uncertainty and held-out comparisons under VAL. Software acceptance can remain separate from pilot, GPU and measured performance gates.

## 6 Sources and maintenance

[FUEL-00-R1](../research/fuel-systems/FUEL-00-R1/README.md) owns its original audit/probes and Word snapshot. The [FUEL-00 manifest](../research/fuel-systems/FUEL-00/sources.json) retains primary references and access/licence records. Historical numbers are not current calibration.

Keep shared behavior and remaining work here, field definitions in AIRCRAFT_CONTRACT, glow-specific operation in GLOW-ENGINES, Workshop transforms in AIRCRAFT-WORKSHOP and replay instructions in FLIGHT-LOGGING. Link these homes instead of copying their rules. Evidence records what was checked; code determines what exists.
