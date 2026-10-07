# VAL-3 — Modal reference dashboard

**Status:** implemented; diagnostic comparisons, not aircraft acceptance. Evidence: [VAL-3](../../docs/research/validation/VAL-3/README.md).

From the repository root, with Python 3 and the pinned Godot:

```sh
python3 research/validation/test_dashboard.py
python3 research/validation/dashboard.py
python3 research/validation/dashboard.py --check
```

The collector uses the current Stik data and `FlightModes.analyze()` directly. It stays outside `app/`; it changes no flight code, data or settings. Generation writes [dashboard.md](dashboard.md) and [snapshot.json](snapshot.json). The snapshot carries full-precision samples and SHA-256 hashes of the analysis, data, references, tooling and inherited US120 derivation inputs. No third-party Python packages are required.

`--check` recomputes the report and fails on missing, tampered or stale output. Engine errors (including errors with exit code zero), timeouts, invalid references, a failed 15 m/s software regression, or inputs changing during collection fail before publication. Each output is replaced atomically; an interrupted two-file update is detected by `--check`. Red scientific comparisons are successful reports, not software failures. This is a manual research tool, not a new CI gate.

## Reference contract

`references/*.json` implement the modal profile of `openrc-reference v1`. Both `us120` and `us25e`, unique IDs and all five metrics are required. Missing/unknown fields, duplicate JSON keys, numeric booleans, nonfinite values, invalid units and invalid provenance are refused.

| Field | Meaning |
| --- | --- |
| `source` | Primary URL, locator, provenance status and limitations. `inherited_derivation` is weaker than `source_checked`. |
| `conditions` | Source speed, mass, span, chord and area in SI; nullable CG, throttle and wind, with an explanatory note. These are not Stik properties. |
| `comparison` | `legacy_scaled`: inherited US120 scalars at 13.8 m/s, guarded to the original 1.524 m target span. `same_cl_reduced`: 25e nominal CL, then each airframe's own length/speed normalization. |
| `rows` | Short-period/Dutch-roll natural angular frequencies (rad/s), damping ratios (1), positive stable roll decay rate (1/s); value, unit, evidence kind and source locator. |
| `uncertainty` | `null` in these imports: source uncertainty has not been established. Screening bands cannot substitute for it. |
| `band` | `null` for damping; otherwise relative half-width, `estimated` kind and reason. Bounds are inclusive. |
| `used_for_tuning` | `true`, `false` or `null` (unknown), plus `tuning_note`. Unknown history is never held-out evidence. |

The 25e transformation uses `CL = 2mg/(rho V² S)`, rho = 1.225 kg/m³ and g = 9.80665 m/s². Pitch frequency uses `wn*c/(2V)`; lateral frequency/rate uses `wn*b/(2V)` or `|lambda|*b/(2V)`. Damping remains unscaled. This is nominal lift matching, not full dynamic similarity.

## Mutation proof

The tests double Clp **in memory**, rerun the actual Godot analysis and require both roll discrepancies to increase. Both real reference rows are already red. A separate synthetic reference equal to the baseline tests the green-to-red transition; it is never saved as an independent reference or used for aircraft tuning. Tests also prove that model/source bytes remain unchanged.
