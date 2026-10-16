# CR-35a · Bounded thermal-energy accounting foundation

2026-10-15 · **Status:** isolated generic arithmetic foundation only. It does not establish aircraft installation, ignition, damage, salvage, or physical-validation evidence. CR-35 remains open.

## Purpose and boundary

The [thermal budget module](../../../../app/economy/thermal_budget.gd) is a deterministic, bounded calculator for caller-supplied energy and resulting temperature/exposure in lumped components. It is disconnected from incident assessment, aircraft data, the physics solver, and rendering. It has no fire or visual-effects output and cannot initiate a source by itself.

The caller supplies every component and source value, provenance text, declared basis, accepted tick, and fixed step duration. The labels scenario_assumption and independently_validated are caller declarations. The module cannot verify a source, installation, measurement, threshold, or validation claim.

## Input contract

The strict openrc-thermal-budget v1 model has a bounded first_tick, fixed tick_duration_s, 1–64 components, and 0–64 sources. Unknown or missing keys are rejected.

Each component supplies:

- Positive finite heat capacity in J/K; nonnegative cooling coefficient in W/K; ambient and initial temperatures in kelvin. Initial temperature must be at or above ambient.
- parameter_basis and non-empty parameter_provenance.
- Either a positive damage_dose_threshold_k_s, threshold basis/provenance, and explicit damage_disposition of unrecoverable, or null for all threshold/disposition fields. A missing threshold is never inferred.

Each source supplies finite nonnegative joules and watts, a nullable ignition_tick, a component-aligned PackedFloat64Array of allocation_shares, basis, and provenance. Shares lie in [0,1] and sum to at most one. A null ignition tick keeps the source dormant; there is no implicit ignition event. The unallocated fraction remains explicit.

The implementation enforces finite bounds on all numeric values. Exact bounds and closed key sets are versioned implementation details, not recommended aircraft values.

## Tick and energy rules

advance accepts only the next tick with the configured fixed duration, or a duplicate of the last accepted tick. A duplicate returns a copied state with zero energy. Gaps and older ticks fail. A different duration fails even for a duplicate tick. Input model and state are not mutated; each state carries a SHA-256 fingerprint of the canonical model so it cannot be reused with changed inputs.

A source becomes active only when its non-null ignition tick is reached. During a tick it releases min(remaining joules, power watts × duration seconds), then depletes. Integration splits at source-depletion times so power stops at the correct instant. Released energy is divided using explicit allocation shares; unallocated energy is reported.

For each component and constant-power interval, the module solves this first-order lumped balance analytically:

    C dT/dt = P - h(T - Ta)

C is caller-supplied heat capacity, h is caller-supplied cooling, Ta is ambient temperature, and P is the sum of allocated source power. The output dose is the analytic interval integral of max(T - Ta, 0) in K·s. This is a bookkeeping exposure quantity, not a material damage law or ignition criterion.

Per accepted tick, the reported energy identity is:

    source_used = source_unallocated + component_storage_delta + component_cooling + balance_error

Cooling is positive heat leaving a component. During source-free cooling, stored-energy change is negative and cooling output is positive, so the same identity balances. A non-conserved result fails instead of returning a disposition.

The result reports temperature, cumulative dose, declared threshold crossing, and disposition. Missing thresholds and unqualified crossings remain inspect. unrecoverable is returned only when an explicit threshold is crossed and the component parameters, threshold, and every declared source capable of feeding that component carry the caller’s independently_validated label. The module checks labels only; that is not proof or independent validation.

## Verification

The [thermal budget tests](../../../../app/tests/test_economy_thermal_budget.gd) exercise 68 checks. References include the closed-form lumped heating solution and analytic dose integral, exponential source-free cooling, and agreement between one 1 s interval and ten 0.1 s intervals. Other cases cover absent/dormant sources, delayed activation, depletion, partial allocation, strict share bounds, energy conservation, remote components, null/scenario thresholds, rejected inputs and tick gaps, duplicate ticks, fixed duration, model fingerprints, and read-only inputs.

Focused command from the repository root:

    .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_economy_thermal_budget.gd

This verifies arithmetic and API behavior only. Test labels and numbers are not physical evidence.

## Evidence still required before integration

This foundation cannot decide whether or when an RC aircraft source ignites, how much energy reaches an installed component, or whether an item is damaged. No installation-specific source energy/power, ignition delay, heat capacity, cooling coefficient, ambient/initial condition, damage threshold, or accepted-source measurement is established here.

Before connecting a caller, CR-35 needs independently sourced inventory/location data, a defined accepted-event/source ledger with replay and duplicate semantics, bounded measurements for each supported energy release and component mapping, and independent qualification for any dose-to-disposition threshold. It also needs deterministic tests for source ordering, checkpoint/rollback, skipped aftermath ticks, and identical results across frame rate/LOD. Until those gates exist, callers must keep unknown quantities null or avoid constructing a model; scenario values must not produce repair charges, automatic ignition, salvage changes, or claims that a component is unrecoverable.

See the [crash-damage economics plan](../../../plans/crash-damage-economics.md#5-thermal-and-electrical-aftermath), the [CR-33 measurement contract](../CR-33a/README.md), and the [CR-31 repair/salvage contract](../CR-31c/README.md).
