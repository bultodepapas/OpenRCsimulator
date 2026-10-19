# BAT-04 — Battery data formats and `pack_ecm` law specification

2026-10-19 · **Status:** normative specification for BAT-04…11. The GDScript runtime (`app/physics/battery/`) and the independent Python reference (`research/battery/ecm_reference.py`) implement this text separately; BAT-03/06 compare them. Plan: [battery realism](../../../plans/battery-realism.md).

Every physical quantity uses the repository quantity form `{value, unit, kind, source}` with `kind` in `manual | measured | borrowed | estimated | derived`. Integers that are counts (cells) and enumerations are plain JSON values.

## 1. Cell template — `openrc-cell-template v1`

Generated into `app/data/batteries/cells/<id>.json` by `research/battery/bat-05/build_batteries.py`. Never edited by hand.

| Field | Form | Rule |
| --- | --- | --- |
| `format` | string | `openrc-cell-template v1` |
| `id`, `display_name` | string | id matches the file name |
| `chemistry` | enum | `lipo`, `lihv`, `liion`, `lifepo4`, `nimh` |
| `tier` | enum | `A` dataset fit, `B` datasheet fit, `C` class estimate |
| `generator` | string | repository path of the generator |
| `provenance` | object | `fit_report` path and `inputs` list of `{dataset, file, sha256, license}` |
| `reference_capacity_ah` | Q `Ah` | capacity between SOC knots 0 and 1 at the reference low rate |
| `soc_knots` | Q `1`, vector | strictly increasing, first 0, last 1, at least 2 |
| `temperature_knots_k` | Q `K`, vector | strictly increasing, at least 1 |
| `ocv_v` | Q `V`, matrix `[nT][nSOC]` | positive, nondecreasing in SOC on every row |
| `r0_ohm` | Q `ohm`, matrix | positive |
| `rc_branches` | array of 0…2 `{r_ohm, tau_s}` | each a positive matrix `[nT][nSOC]`; branches ordered by increasing median τ |
| `specific_heat_j_per_kg_k` | Q `J/(kg·K)` | positive |
| `limits` | object of Q | `v_max`, `v_cutoff`, `v_damage_floor` (`V`, per cell, `v_damage_floor < v_cutoff < v_max`), `t_min_k`, `t_max_k` (`K`). `v_cutoff` is the template's data floor (the loaded voltage that defines SOC 0), which can sit above a datasheet's minimum; `v_damage_floor` carries the chemistry limit |

SOC 0 is the template data floor: discharge to `v_cutoff` at the reference rate. SOC 1 is full charge. Values outside the knots are clamped, never extrapolated. A template has one reference capacity; multi-temperature data are normalized to each test's own capacity before fitting, and coulombic capacity does not vary with temperature at runtime.

## 2. Pack — `openrc-battery v1`

Generated into `app/data/batteries/packs/<id>.json` by the same generator.

| Field | Form | Rule |
| --- | --- | --- |
| `format` | string | `openrc-battery v1` |
| `id`, `display_name`, `class_note` | string | `class_note` states whether this is a class estimate or an identified product |
| `chemistry` | enum | equals the template chemistry |
| `cell_template` | `{id, sha256}` | sha256 of the exact template file bytes |
| `series`, `parallel` | integer | `1…24`, `1…8`; the model treats each parallel group as one equivalent cell |
| `rated_capacity_ah` | Q `Ah` | capacity of one parallel group |
| `resistance_scale` | Q `1` | multiplies template resistances after capacity normalization |
| `interconnect_resistance_ohm` | Q `ohm` | wires, balance taps, connector; ≥ 0 |
| `mass_kg` | Q `kg` | whole pack |
| `dimensions_m` | Q `m`, vector 3 | length, width, height |
| `heat_transfer` | object of Q | `still_air_w_per_k` (`W/K`), `forced_w_per_k_per_sqrt_mps` (`W/(K·(m/s)^0.5)`) |
| `label` | object | `{c_rating_continuous, c_rating_burst, source}`, informative only (`null` when not rated); physics never reads it |

Normalization (runtime and reference):

```text
Q_g   = 3600 · rated_capacity_ah                               [C] per series group
s_R   = (reference_capacity_ah / rated_capacity_ah) · resistance_scale
R0(z,T), R_k(z,T) → s_R · template value ;  τ_k(z,T) unchanged
C_th  = mass_kg · specific_heat_j_per_kg_k                     [J/K]
hA(v) = still_air_w_per_k + forced_w_per_k_per_sqrt_mps · sqrt(max(v_cool, 0))
```

## 3. Aircraft `propulsion.battery` with `kind: "pack_ecm"`

```json
"battery": {
  "kind": "pack_ecm",
  "pack": {"id": "lipo-4s1p-3200-30c-class", "sha256": "<bytes of the pack file>"},
  "mount_inventory_id": "battery_main",
  "initial_soc": Q "1" in (0, 1],
  "auxiliary_current_a": Q "A" ≥ 0,
  "cooling_airflow_fraction": Q "1" in [0, 1],
  "weak_cell": {"capacity_factor": Q "1" in (0, 1], "resistance_factor": Q "1" in [1, 10], "soc_offset": Q "1" in [0, 0.5)}
}
```

- The inventory item `mount_inventory_id` must exist, carry `energy_source: "lipo"` for `lipo`/`lihv` packs, and have exactly the pack mass. Other chemistries are refused until the crash energy-source vocabulary covers them.
- `initial_soc − soc_offset > 0`.
- `capabilities.energy` is `pack_ecm`.

`propulsion.esc` keeps `kind: "ideal_motoring"` and `command_mapping: "identity"`, and **requires** `low_voltage_cutoff` when the battery is `pack_ecm` (forbidden otherwise):

```json
"low_voltage_cutoff": {
  "mode": "soft" | "hard" | "off",
  "cell_detection": "auto" | "fixed",
  "fixed_cells": Q "1", integer value (only with "fixed"),
  "detection_max_cell_v": Q "V" (only with "auto"),
  "cutoff_per_cell_v": Q "V",
  "soft_limit": Q "1" in [0, 1),
  "soft_ramp_s": Q "s" > 0,
  "debounce_s": Q "s" ≥ 0,
  "recovery": "throttle_reset" | "latched",
  "reset_throttle_max": Q "1" in [0, 0.2],
  "voltage_filter_s": Q "s" ≥ 0.02
}
```

## 4. Law (one stage evaluation)

Inputs: `rpm ≥ 0`, commanded duty `u ∈ [0,1]`, `enabled`, ESC `limit ∈ [0,1]`, the state below, ambient `T_amb` [K] and cooling speed `v_cool = cooling_airflow_fraction · |V_air|` [m/s].

```text
n   = series ;  Q_w = capacity_factor · Q_g ;  z0 = initial_soc ;  Δz = soc_offset ;  f_R = resistance_factor
q_w0 = (z0 − Δz) · Q_w                       weak-cell initial remaining charge [C]
state: q_w, v_a[k], v_w[k], T, v_s           (k = 1..K, K = number of RC branches)
q_used = q_w0 − q_w
z_w = q_w / Q_w ;  z_a = z0 − q_used / Q_g    (table lookups clamp z to [0, 1])
OCV_a = OCV(z_a, T) ; OCV_w = OCV(z_w, T)
R0_a = s_R·R0(z_a,T) ; R0_w = f_R·s_R·R0(z_w,T) ; R_ak = s_R·R_k(z_a,T) ; R_wk = f_R·s_R·R_k(z_w,T) ; τ_ak = τ_k(z_a,T) ; τ_wk = τ_k(z_w,T)
E_oc = (n−1)·(OCV_a − Σ_k v_ak) + (OCV_w − Σ_k v_wk)
R_p  = (n−1)·R0_a + R0_w + R_w
d    = min(u, limit) if enabled else 0
```

- **Exhausted** (`q_w == 0` at or after the located exhaustion event; trial stages before the event use the connected left limit): `I = 0`; the motor sees bus 0 and is disabled; `V = E_oc`.
- **Connected**: `V0 = E_oc − R_p·I_aux > 0`; `E_m = rpm/Kv`; `Im = max((d·V0 − E_m)/(Rm + d²·R_p), 0)` when `d > 0`, else 0; `I = d·Im + I_aux`; `V = E_oc − R_p·I > 0`. The motor law is EL1a evaluated at bus `V` and duty `d`.

Bilinear interpolation: find the T segment (clamped) and the z segment, interpolate linearly in z on both bounding T rows, then linearly in T. With one T knot, T is ignored.

Rates (state order of §5):

```text
dq_w/dt  = −I
dE/dt    = V·I
dH/dt    = I²·R_p + (n−1)·Σ_k v_ak²/R_ak + Σ_k v_wk²/R_wk
dv_ak/dt = (R_ak·I − v_ak)/τ_ak ;  dv_wk/dt = (R_wk·I − v_wk)/τ_wk
dT/dt    = (I²·((n−1)·R0_a + R0_w) + (n−1)·Σ v_ak²/R_ak + Σ v_wk²/R_wk − hA(v_cool)·(T − T_amb)) / C_th
dv_s/dt  = (V − v_s)/voltage_filter_s
```

Energy closure per stage: `((n−1)·OCV_a + OCV_w)·I = V·I + dH/dt + d/dt[(n−1)·Σ ½·C_ak·v_ak² + Σ ½·C_wk·v_wk²]` with `C = τ/R`, exact when the tables are locally constant.

## 5. Session continuous block

After the shaft rpm slot `s`:

| Offset | Quantity | Derivative |
| --- | --- | --- |
| s+1 | weak-cell remaining charge `q_w` [C] (located exhaustion event) | −I |
| s+2 | terminal energy [J] | V·I |
| s+3 | pack electrical loss [J] | dH/dt |
| s+4 … s+3+K | average-cell RC voltages [V] | law |
| s+4+K … s+3+2K | weak-cell RC voltages [V] | law |
| s+4+2K | pack temperature [K] | law |
| s+5+2K | ESC sensed pack voltage [V] | law |
| s+6+2K | ESC output limit [1] | 0 (sampled) |
| s+7+2K | ESC LVC phase code: 0 normal, 1 debounce, 2 soft cut, 3 hard cut | 0 (sampled) |
| s+8+2K | ESC phase timer [s] | 0 (sampled) |
| s+9+2K | ESC detected cells | 0 (sampled) |

At reset: `q_w = q_w0`, energy and loss 0, RC voltages 0 (rested pack), `T = T_amb` at the start position, `v_s = E_oc − R_p·I_aux`, limit 1, phase 0, timer 0, cells from §6.

## 6. ESC supervisor (sampled at each accepted endpoint)

After a tick is integrated, with `v = v_s` at the endpoint, the tick's commanded throttle `u`, and `dt`:

```text
threshold = cells · cutoff_per_cell_v
mode off      → phase 0, limit 1, timer 0
phase 0       → if v < threshold: phase 1, timer = dt ; else timer 0
phase 1       → if v ≥ threshold: phase 0, timer 0 ; else timer += dt
                if phase 1 and timer ≥ debounce_s: soft → phase 2, timer 0 ; hard → phase 3, timer 0
phase 2       → timer += dt ; limit = max(soft_limit, 1 − (1 − soft_limit)·min(timer/soft_ramp_s, 1))
phase 3       → limit = 0
recovery      → throttle_reset: in phase 2 or 3, if u ≤ reset_throttle_max and v ≥ threshold → phase 0, limit 1, timer 0
                latched: never leaves phase 2 or 3 in this session
phase 0 or 1  → limit 1
```

Order within one sample: recovery is tested first in phases 2 and 3 (before the phase-2 timer advances); the debounce test runs in the same sample as the 0 → 1 transition. Timer comparisons use a 1 ns tolerance (`timer ≥ debounce_s − 1e-9`, and the ramp fraction is exactly 1 once `timer ≥ soft_ramp_s − 1e-9`) so accumulated `dt` rounding does not delay a decision by one sample. The phase-3 timer is not advanced. The new limit applies to the next tick (zero-order hold). Cell detection happens once, at reset ("connection"): `fixed` → `fixed_cells`; `auto` → `max(1, ceil(V_rest/detection_max_cell_v − 1e-9))` with `V_rest = E_oc − R_p·I_aux`. A deeply discharged pack can therefore be misdetected; that is modeled behaviour, not an error.
