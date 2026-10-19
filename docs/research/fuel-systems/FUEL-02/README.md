# FUEL-02 — Fuel-property registry (2026-10-19)

Evidence for step FUEL-02 of the [fuel, mass and balance plan](../../../plans/fuel-mass-balance.md). The registry is the single home for liquid-fuel densities (finding F04). No runtime behavior changed: nothing reads the registry yet except the tests, and every glow profile already derives the registry's glow density exactly.

## What exists

- **Data:** [`app/data/fuels/openrc-fuel-registry.json`](../../../../app/data/fuels/openrc-fuel-registry.json), format `openrc-fuel-registry v1`. It lists 7 components, each with a density at a reference temperature and, where sourced, a temperature slope, all as `{value, unit, kind, source}` quantities. It defines 3 blends, each with volume fractions, a reference temperature, a relative uncertainty and a use.
- **Runtime reader:** [`app/physics/fuel_properties.gd`](../../../../app/physics/fuel_properties.gd).
  - `load_file` returns the derived densities and a SHA-256 identity; `prepare` does the same for already-parsed data.
  - `blend_density(prepared, id, temperature_k)` returns a blend's density, by default at its reference temperature.
  - It refuses any shift to another temperature when a component has no slope.
- **Generator reader:** [`research/fuel-systems/fuel_registry.py`](../../../../research/fuel-systems/fuel_registry.py), with `blend_density` and `blend_source`. It follows the same rules for the Python generators that FUEL-05 will migrate.

| Blend | Density (kg/m³) | Reference | Uncertainty | Use |
| --- | ---: | --- | ---: | --- |
| `glow_10n_18castor` | 856.92 | 25 °C | ±2 % | O.S. MAX-55AX / 61FX / FS-64V profiles |
| `gasoline_premix_40_1` | 747.854 | 15 °C | ±4 % | Gasoline engines (DA-120) |
| `kerosene_5pct_turbine_oil` | 810.175 | 15 °C | ±4 % | JetCat P100-RX |

Sources and values are in [FUEL-00 §6.1](../FUEL-00/README.md#61-densities). The glow components keep the AIAA 2016-5011 values the profiles already use, so profile densities are unchanged. The standard-table values for the same components are recorded in their source strings.

## Proof

- **[`test_fuel_properties.gd`](test_fuel_properties.log):** 30 checks, 0 failed. It covers:
  - three blend densities against hand sums, within 1e-9;
  - each glow profile's own derived density equals the registry blend, within 1e-9;
  - a one-component change breaks that equality, so the check is not vacuous;
  - a component referenced at another temperature is shifted by its slope (synthetic registry);
  - a shift is refused without slopes;
  - 14 refusals: fraction sum, unknown component, negative density, empty source, unknown kind, wrong unit, extra keys, unknown family, positive slope, missing slope, format, zero fraction, uncertainty.
- **`test_fuel_registry.py`:** 3 tests. The same hand sums, plus refusals of a bad fraction sum and a missing slope.
- **Mutations** (on a disposable copy):

| Mutation | Result |
| --- | --- |
| Fraction-sum check disabled | 1 check fails |
| Temperature shift removed | 2 checks fail |

- Both scripts parsed outside `app/` before integration. Their `.uid` files come from an incremental `--import`; the uids are unique in `app/`.
- Both tests run in `app/test.sh`: the GDScript test is discovered by name, and the Python line sits next to the mass/balance check.

## Limits

- **Ideal volume mixing.** Measured glow blends are up to about 2 % denser.
- **Missing temperature slopes.** Nitromethane, castor, two-stroke oil and turbine oil have none, so blends containing them are defined at their reference temperature only.
- **Not yet consumed.** The aircraft data still writes prose densities: 0.8 g/ml (Stik), 0.82 (Extra) and 0.74 (P-51). Their generators move to the registry in FUEL-05.
