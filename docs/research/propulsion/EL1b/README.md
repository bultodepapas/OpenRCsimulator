# EL1b — Electric aircraft data

2026-10-10 · **Status: loader/schema, synthetic-data checks and full app regression pass. Step prefix: EL.**

EL1b adds an explicit `electric_prop` branch to the v1 aircraft loader and schema, plus two synthetic Stik-based electric demo datasets. The implementation is in [aircraft_data.gd](../../../../app/physics/aircraft_data.gd), [the v1 schema](../../../../app/data/schema/openrc-aircraft-v1.schema.json), [focused checks](../../../../app/tests/test_electric_data.gd), and the [800 Kv/4S](../../../../app/data/aircraft/synthetic_stik_electric_4s.json) and [400 Kv/6S](../../../../app/data/aircraft/synthetic_stik_electric_6s.json) datasets. The owning [Electric Propulsion Plan](../../../ELECTRIC-PROPULSION-PLAN.md) tracks the remaining integration and physical-validation steps.

## Data contract

The raw `propulsion` object selects `kind: "electric_prop"` and contains only `motor`, `battery`, `esc`, and `propeller`; combustion `engine` data is rejected. The motor requires provenance-bearing quantities `kv_rpm_per_volt` (`rpm/V`), `resistance_ohm` (`ohm`), `no_load_current_a` (`A`), and a no-load test context with voltage (`V`), speed (`rpm`), and temperature (`°C`). Resistance is explicitly `motor_winding_equivalent`; ESC and wiring losses are excluded. The battery is `fixed_voltage` with a prescribed terminal voltage. The ESC is `ideal_motoring` with `identity` command mapping. The existing propeller fields keep their v1 raw names and evidence format: diameter, thrust-line offset, rotating inertia, Ct/Cp tables, and optional thrust angles. Each numeric entry keeps `{value, unit, kind, source}`.

The normalized propulsion dictionary reuses the shared flat propeller fields and adds the electric source blocks:

```text
{
  kind: "electric_prop",
  motor: {kv_rpm_per_volt, resistance_ohm, no_load_current_a},
  battery: {kind: "fixed_voltage", voltage_v},
  esc: {kind: "ideal_motoring", command_mapping: "identity"},
  max_rpm: kv_rpm_per_volt × battery.voltage_v,  # descriptive no-load reference
  diameter, offset, rotor_inertia, ct, cp, axis,
  cp_min: optional signed lower Cp bound
}
```

`max_rpm` is not a shaft-speed limit or governor. The loader accepts only positive, direct-drive rotation about the declared propeller axis; gearing and reverse sense are unsupported. It rejects unknown or mixed combustion fields, unknown evidence keys, unsupported modes/units, malformed or nonfinite quantities, and cross-field violations. It also requires positive loaded rotor inertia and verifies that removing its axial spin inertia leaves a positive-definite carrier from the complete aircraft inertia tensor. Signed Cp is retained for windmilling, while static Ct and Cp must be positive.

Missing-kind glow data retains the legacy glow path, and explicit turbine data retains its turbine path. The isolated compatibility sweep includes all four pre-existing aircraft files; the original files are unchanged. The focused checks also load the legacy Ugly Stik glow data and Avanti turbine data.

## Synthetic demo data

`synthetic_stik_electric_4s.json` uses a synthetic 800 Kv motor and prescribed 14.8 V bus. `synthetic_stik_electric_6s.json` uses a synthetic 400 Kv motor and prescribed 22.2 V bus. Both inherit the Ugly Stik geometry, aero data, and existing Stik propeller tables, and retain the original inventory. The focused loader checks verify identical aircraft mass, CG, and complete locked inertia to the existing Stik. Motor constants, bus settings, and loaded rotor inertias are explicitly labeled synthetic in their evidence sources. These files are integration demos only: they are not real conversions, validated electric aircraft, matched motor/propeller datasets, or Timber data.

## Software evidence

The EL1b files are installed in the live app. The pre-change `app/test.sh` baseline passed before installation; the focused checks below ran afterward. The parity harness found no schema/loader mismatches. From the repository root, the commands are:

```sh
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_electric_data.gd
python3 research/aircraft-data/schema/test_contract.py
python3 research/aircraft-data/schema/check.py
```

The focused GDScript test passed **43 checks**. The [schema/loader harness](../../../../research/aircraft-data/schema/test_contract.py) passed **1,779 cases**, including **139 valid controls** and **13 schema-valid/runtime-only cross-field controls**; all four schema-contract tests passed. The [structural preflight](../../../../research/aircraft-data/schema/check.py) passed all **six aircraft files** (four existing aircraft and the two synthetic demos). The deliberate serialized `1e999` negative control causes Godot to print `WARNING: Exponent too high`; the loader rejects it, the test passes, and the run has no `SCRIPT ERROR`. The post-install full `app/test.sh` also passed; [EL1d preserves its log and source hashes](../EL1d/README.md).

These results establish software parsing, schema/loader agreement, normalization, and preservation of the inherited airframe identity. They do not establish motor R/I0, rotor inertia, bus behavior, propeller performance, flight handling, endurance, or physical accuracy. EL1c–f and EL5/6 remain responsible for operating-point behavior, session integration, measured Timber data, and physical acceptance.
