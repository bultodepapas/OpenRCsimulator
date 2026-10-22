# FUEL-04 — One fixed-datum resource kernel (2026-10-19)

**Later clarification 2026-10-19:** this evidence describes the original FUEL-04 snapshot. The prediction below that empty-tank balancing would make the solver datum dry was not implemented. The datum remains the authored reference inventory CG; `plan_cg` is a separate balance target. See the [unified standard](../../../plans/fuel-mass-balance.md) and [FUEL-00-R1 review](../FUEL-00-R1/README.md).

Evidence for step FUEL-04 of the [fuel, mass and balance plan](../../../plans/fuel-mass-balance.md). This closes F07 (two mass kernels for one law) and sets the datum rule of D2. Every existing trajectory is bit-identical.

## Change

| File | Change |
| --- | --- |
| `app/physics/mass_inventory.gd` | New `REFERENCE_LAW` `fixed-datum-reference-state-resources-v1`, `prepare_reference(reference_mass, reference_inertia, resources)` and `evaluate_reference(prepared, amounts)` |
| `app/physics/fixed_datum_body.gd` (new) | Open-system derivative `derivative(s, properties, force, moment_cm, gravity, rotor)`, law `fixed-datum-co-moving-efflux-v1`, moved verbatim from the glow `FuelMass` |
| `app/physics/glow/fuel_mass.gd` | Thin adapter: `prepare`, `evaluate` and `datum_derivative` call the shared kernels |
| `app/physics/glow/installation.gd` | Prepares `install.mass_reference` once and refuses an invalid one |
| `app/physics/glow/flight.gd` | Each stage evaluates the prepared reference and uses `FixedDatumBody`. It re-prepares only if the model's wet mass or inertia was replaced after installation |
| `app/tests/test_fuel_mass_reference.gd` (new) | 26 checks, described under Proof |

**How the reference form works:**

- **Datum (D2):** the CG of the authored aircraft state. It is a fixed geometric point that does not move with the fill.
- **Resource:** each one is a uniform box of fixed centre and size, with reference amount ≤ capacity.
- **Evaluation:** each resource subtracts `(reference − amount)` from the reference state.
- **Order of operations:** with one resource this is the historical glow arithmetic, operation for operation.
- **Fill range:** amounts may run from 0 to capacity. A start fill above the authored one (FUEL-07) and several tanks (hopper, smoke) are therefore representable. Glow capacity stays equal to the authored load until FUEL-03 declares capacities, so behaviour is unchanged.

## Proof

**Bit identity:**
- The installed MAX-55AX, MAX-61FX and FS-64V Stiks were evaluated at six fuel levels, from full down to 1e-30 kg and 0.
- Both the cached reference and the `FuelMass` adapter equal a verbatim copy of the pre-FUEL-04 `FuelMass.evaluate` with `==` on mass, CG, inertia, inverse and datum inertia. There were 0 mismatches.

**Fleet fingerprints:** [`fingerprints.json`](fingerprints.json). The candidate tree with FUEL-01, FUEL-02 and FUEL-04 gives the same SHA-256 as the pre-FUEL-01 baseline copy of the same tree, for all 20 trajectories (airplanes with cut variants, helicopter, ground vehicle). This held both before and after the cost optimization.

**Two resources:**
- A main tank and a smoke tank in the reference form agree exactly (worst difference 0.0) with the dry-up `MassInventory.evaluate` form. Tested at six fill pairs, including both tanks above their authored amounts.
- A fill above the authored amount adds exactly that mass and moves the CG toward the tank.

**Refusals:**
- At evaluation: amounts above capacity, negative, NaN, or a wrong count.
- At preparation: resources heavier than the aircraft, no resources, a 5-entry tensor, duplicate ids, reference above capacity, negative size, non-finite centre and empty id.

**Momentum** (the FUEL-00 fixture ported to the runtime kernels):

- **Setup:** zero wrench and gravity, a non-principal spin of 2/3/1 rad/s, and a 30 s burn of 0.09 kg from the 61FX tank. RK4 integrates the 13-value body, the fuel and the ejected-fuel momentum together.

| Case | \|ΔP\| at 240 Hz (kg·m/s) | At 480 Hz | Reading |
| --- | ---: | ---: | --- |
| With the datum correction | 9.0e-7 (P ≈ 14) | 16.0001× smaller | 4th-order integration error |
| Without the correction | 0.0626 | Unchanged (0.06258) | Law error |

**Cost** ([`cost-bench.txt`](cost-bench.txt), probe [`cost_bench_probe.gd.txt`](cost_bench_probe.gd.txt)):
- Per-stage mass evaluation over 30 interleaved rounds of 20,000 calls on the shared VM:

| Path | Minimum (µs) | Median (µs) |
| --- | ---: | ---: |
| Historical | 18.6 | 26.3 |
| Shared, including the cache guard | 17.1 | 26.0 |

- The prepared form stores parallel typed arrays, so no dictionary lookup happens per resource.

**Regression suite:**
- 24 focused programs pass on the candidate copy.
- 20 of 21 pass after integration, on a fresh copy of the main tree that includes other tracks' uncommitted work ([`post-integration-checks.txt`](post-integration-checks.txt)). That covers glow physics, installation, session, feed, trace, lifecycle, stage reuse, prepared evaluator, coupling, hub inflow, mass inventory, R05-B dynamic contacts, SF-06 law properties, SF-04b event refinement, catalog, failures and pilot trim.
- The one failure is `test_crash_energy`: "aircraft data file has an explicit energy-test classification: `turbo_lumber_evolution_4s_pack.json`". That is a new battery-track (BAT-13) aircraft file missing from that test's table, unrelated to FUEL-04.
- All drafts parsed outside `app/` before integration. The new `.uid` files come from an incremental import and are unique.

## Reproduce

```sh
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_fuel_mass_reference.gd
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/fingerprint_vehicles.gd -- --output=/tmp/fp.json
```

## Limits

- Fuel is a uniform box of fixed shape: no free surface and no slosh (D6).
- The datum is the CG of the authored state. When FUEL-05 moves the authored balance to an empty tank, the datum becomes the dry CG, which matches AV-10b's recommendation.
- Contacts, crash and HUD consumers of wet values are FUEL-06.
