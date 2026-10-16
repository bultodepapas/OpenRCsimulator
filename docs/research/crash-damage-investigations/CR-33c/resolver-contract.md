# CR-33c — Bounded component damage resolver contract

2026-10-16 · **Implemented isolated helper; no aircraft calibration or incident integration.** This contract separates labeled gameplay estimates from physical qualification. It defines no aircraft threshold and does not authorize a production surcharge, salvage credit, or automatic failure decision.

## What current signals establish

`FlightSession.contact_events_changed` publishes a detached `contact_events()` snapshot after an accepted step. The snapshot carries `tick`, `active_hull_ids`, that tick's `events`, and the propeller-strike latch. Versioned events carry `event_id`, `tick`, `source`, `contact_id`, `lifecycle`, `policy`, and `response`; optional fields include a probe binding, point/normal/velocity, and measures. The current event sources/types are hull contact, hull/gear/scenery/lake impact, and propeller strike. Only a validated `new` event is a new cause; persistent and ended hull contacts cannot be charged again.

These are software observations, not structural outcomes. A probe/support-point ID is not a failed component or joint. Optional speed, compression, `impact_energy_j`, and `dissipated_energy_j` remain source-specific estimates; gear compression is not mount load. The event stream does not supply a general accepted impulse/force history, balsa/ply/film joint capacity, component survival, ignition, or heat transfer. See [CR-33a](../CR-33a/README.md) and [report 03](../03-rc-construction-material-joint-evidence.md).

`ImpactBudget` may estimate isolated normal restitution loss from a separately assembled accepted-tick rigid-body sample. Its `isolated_estimate` is not observed solver work or a failure metric; episode apportionment is bounded by a caller-supplied budget and candidate estimates. `ThermalBudget` advances only caller-supplied energy, power, ignition tick, allocation shares, thermal parameters, and optional threshold. Its basis/provenance labels are caller declarations. Neither helper is connected to `Incident`.

Today, an accepted non-prop contact can add an unresolved inspection reason. The existing prop-strike policy records one prop replacement and powertrain inspection, but a strike does not physically prove the propeller failed. `Incident.apply_inspection` already accepts an explicit `scenario_assumption` receipt and can price its declared choices; it does not predict them. `assessment_changed(report, terminal)` is the report publication signal, not a damage-measurement signal. These are the available bounded gameplay paths without new physical measurements.

## Smallest resolver contract

The isolated pure helper is [`ComponentResolver.resolve(input: Dictionary) -> Dictionary`](../../../../app/economy/component_resolver.gd). It does not read the solver, mutate an incident, emit a signal, select a price, or change inventory. The caller must validate every `accepted_event` ID and tick against the accepted snapshot, `AircraftContactEvents.validate_events`, and current aircraft bindings before constructing this input; the resolver accepts caller references and does **not** validate event payloads, bindings, lifecycle, or tick membership. The closed input keys are `format`, `incident_id`, `aircraft_id`, `source_sha256`, and `components`; the source hash is 64 lowercase hexadecimal characters. Each component has exactly `component_id` and `causes`. Each cause has exactly `cause_kind`, `cause_id`, `tick`, and `channels`. A channel has exactly `channel`, `unit`, `quantity_low`, `quantity_high`, `quantity_class`, `quantity_provenance`, `capacity_low`, `capacity_high`, `capacity_class`, `capacity_provenance`, `over_capacity_candidate`, and `qualification_ref`:

```json
{
  "format": "openrc-component-evidence v1",
  "incident_id": "incident-1",
  "aircraft_id": "example-aircraft",
  "source_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "components": [{
    "component_id": "wing-left",
    "causes": [{
      "cause_kind": "authored_scenario",
      "cause_id": "scenario-impact-1",
      "tick": 42,
      "channels": [{
        "channel": "impact_allocated_j",
        "unit": "J",
        "quantity_low": 8.0,
        "quantity_high": 11.0,
        "quantity_class": "isolated_estimate",
        "quantity_provenance": "synthetic normal-loss interval",
        "capacity_low": 6.0,
        "capacity_high": 9.0,
        "capacity_class": "scenario_assumption",
        "capacity_provenance": "explicit scenario file and revision",
        "over_capacity_candidate": "repair_candidate",
        "qualification_ref": ""
      }]
    }]
  }]
}
```

The resolver accepts 1–64 affected component rows and at most 128 cause/component rows. A cause uses `accepted_event` with the exact validated event ID, or `authored_scenario` with an explicit configuration ID; both require a nonnegative accepted tick. `quantity_class` is `accepted_observation`, `measured`, `isolated_estimate`, `scenario_assumption`, or `independently_validated`; `capacity_class` is `scenario_assumption` or `independently_validated`. `qualification_ref` is empty unless either class claims independent validation, in which case it must be nonempty. Input labels and references are not verified by this pure helper.

Use only these channels, with at most three per cause:

| Channel | Quantity and capacity unit |
| --- | --- |
| `impact_allocated_j` | J |
| `abrasion_j` | J |
| `thermal_dose_k_s` | K·s |

Each channel row contains a quantity interval `[quantity_low, quantity_high]`, a declared capacity interval `[capacity_low, capacity_high]`, `over_capacity_candidate` (`repair_candidate` or `replace_candidate`), separate nonempty provenance and evidence class for quantity and capacity, plus a qualification reference when either class claims `independently_validated`. Reject duplicate `(cause_kind, cause_id, component_id)` rows, duplicate channels, unknown channels, unknown keys, mismatched units, invalid ticks, reversed/negative/nonfinite values, and sums above `10^12` in the channel's declared unit. Sort IDs before summing so input ordering cannot change the result. Require capacity intervals and candidate action for repeated rows of the same component/channel to match exactly; sum quantity intervals across unique causes with overflow checks. No missing capacity is filled from material tables, generic strength, scenery cutoffs, or defaults. A cause with no supported channel remains `inspect`.

For total quantity interval `[qL,qH]` and capacity interval `[cL,cH]`, the resolver uses a deterministic numerical comparison tolerance `tol = 1e-12 * max(1, qH, cH)` in the channel's declared numeric unit. Each channel result returns this value as `comparison_tolerance`. The band accounts only for floating-point roundoff during summation and comparison; it is not physical uncertainty, a material factor, or a change to the declared capacity. Any result within the band remains `inspect`.

| Test | Resolver result |
| --- | --- |
| `cL - qH > tol` | `below_declared_capacity` (mandatory inspection remains required; this does not establish serviceability) |
| `qL - cH > tol` | The authored `repair_candidate` or `replace_candidate` |
| Otherwise, including equality and differences within `tol` | `inspect` |

Candidate severity is monotone: `replace_candidate` outranks `repair_candidate`, which outranks `inspect`; no result can grant `reuse`. Every successful component result keeps `inspection_required: true`, including a below-capacity comparison; an empty channel, missing capacity, or overlapping/equal interval also stays inspect. A declared scenario capacity may produce a gameplay candidate even when the quantity is only measured or estimated; the result remains labeled as a scenario assumption, not a physical finding. A below-capacity result means only that the declared interval was not crossed. Successful results use `format: openrc-component-resolution v1`, sorted component rows, each channel's summed intervals/comparison/candidate, source cause IDs, provenance, and evidence classes; invalid input returns `ok: false` and errors. Any channel with a scenario assumption is labeled `scenario_assumption`; heterogeneous non-scenario classes are `mixed`; a uniform nonqualified class is `unqualified`; only entirely independent quantity and capacity classes are labeled `independently_validated_claim`. Successful results always return `qualification_verified: false` and `production_billing_enabled: false`; any input class claiming independent validation sets `qualification_claim_unverified: true`. The helper never returns a physical disposition or price. A future integration must verify the exact aircraft-source hash, installed component, channel, conditions, capacity, outcome model, and held-out validation in a reviewed qualification registry before treating a claim as physical evidence. The current inspection receipt schema does not accept such a qualified basis.

An explicitly authored scenario may therefore produce a deterministic *gameplay estimate* and a later `scenario_assumption` cost receipt. Until someone authors scenario capacities and component mappings, current impact/fire contacts remain inspect-only. Do not turn report 03 coupon values, the isolated impact estimate, or generic thermal arithmetic into a production default.

## Verification and gates

[`test_economy_component_resolver.gd`](../../../../app/tests/test_economy_component_resolver.gd) passes 35 checks. It covers strict-below, strict-above, equality and overlap; decimal-sum equality, one-ULP exceedance and an exceedance beyond the numerical band; repair/replacement candidate actions; channel priority; deterministic sorting and interval summation; independent components; caller input immutability; missing/unpriced capacity; duplicate cause/component and duplicate-channel rejection; unknown fields/channels/units; reversed, negative, nonfinite and overflow values; capacity disagreement; and qualification claims remaining unverified. Held-out synthetic mechanical and thermal fixtures are explicitly labeled **software-only scenarios**. They test interval behavior and do not calibrate thresholds. The existing impact and thermal budget tests still pass their 36 and 68 software checks.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --check-only --script res://economy/component_resolver.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --check-only --script res://tests/test_economy_component_resolver.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_economy_component_resolver.gd
```

Automatic production impact/fire cost remains gated on the [CR-33a measurement contract](../CR-33a/README.md#billing-gate), applicable installed-aircraft evidence, component/joint mapping, uncertainty, and independent held-out validation. No new measurement or source cited here closes CR-07 or CR-33. Reviewed with the existing [CR-33b](../CR-33b/README.md), [CR-35a](../CR-35a/README.md), and [CR-07 report 03](../03-rc-construction-material-joint-evidence.md).
