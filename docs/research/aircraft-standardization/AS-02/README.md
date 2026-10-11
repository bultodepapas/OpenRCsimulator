# AS-02: Versioned aircraft-data migration

**Status:** v2 migration integrated into the live fleet; all eight JSONs are v2 and match the staged candidates.  
**Scope:** structural migration for the eight existing configurations, generator wiring for Extra/P-51/Avanti, and a synthetic authoring template. No runtime loader or physics equations change here.

## Contract

The root format is `openrc-aircraft v2` with `convention_id: openrc-le-frd-v1`. Each file declares `reference.planform`, `propulsion.kind`, an explicit `start.level_speed`, and `capabilities` for conventional controls, the simulated gear state, propulsion layout, energy source, terminal-hull damage and unsimulated flaps. These fields describe what the current simulation runs; they do not claim that physical gear, engine or flap dynamics are implemented.

The migration is allowlisted by the current eight aircraft IDs. It rejects unknown IDs, conflicting capabilities, versions, propeller directions and electric battery shapes. Glow props use the fixed v2 value `clockwise_from_rear`; electric propeller direction is fixed by the convention; turbines keep their signed `rotor_sense` data. The migration does not infer an EDF, pusher, multiple engines or retract operation from nearby fields.

For a v1 input, the helper preserves every original numeric leaf exactly, moving only the inert `aero.coefficients.CLadot` quantity and its evidence to `aero.reference_coefficients.CLadot`. It makes the v1 loader's omitted defaults explicit: start speed 15 m/s only for the Stik-derived configurations that relied on that default, zero-size point masses, and zero steering where the contact omitted the field. It adds explicit engine kind, convention and capability metadata. The complete per-file numeric path/value comparison is in [numeric-parity.json](numeric-parity.json). AV-06 coefficient derivation continues to use the unrounded geometric `S/b`; a source pin preserves only the checked-in serialized `reference.mean_chord` value. This preserves the existing output without changing the coefficient calculation.

Across the eight files, all 2,815 original numeric leaves are identical, eight CLadot leaves move to their reference-only path, 286 compatibility-default numeric leaves are made explicit, and the comparison finds zero differences.

The full-suite freshness check also identified three generated D8b-R2 research polar candidates whose donor is the Stik file. Regenerating them through their existing `make_candidates.gd` pipeline carries the donor's v2 contract into these artifacts without editing their synthetic polar curves. [Candidate parity](polar-candidate-parity.json) preserves all 1,023 original numeric leaves (341 per candidate) exactly, with 108 explicit default leaves added. They remain research-only, with no production polar selection or physical calibration claim. The retained historical D8b-R2 reports describe their original inputs; new candidate hashes and rerun evidence are recorded under AS-04.

`balance.firewall`, glow `peak_power` and `peak_power_rpm`, and turbine `fuel_flow` remain at their existing paths with their provenance. They are reference or telemetry values, not active forces or aircraft-mass changes in the current model. Existing `fuel_flow` does not decrement mass. See the [AS-00 physics audit](../AS-00/physics-audit.md) for behavior and source scope.

## Existing capability boundary

| Configuration | Current support | Unimplemented or unvalidated |
| --- | --- | --- |
| Single glow piston with tractor prop | Supported by Stik and Extra; RPM/throttle and prop tables; session on/off state | Fuel burn and engine-specific start/ignition lifecycle |
| Single gasoline piston with tractor prop | P-51 runs through the generic glow_prop branch | Separate gasoline ignition/fuel model; experimental P-51 parameterization |
| Single turbine / centerline jet | Avanti only; ECU spool/thrust branch and session run/off state | Engine-specific start/restart sequence, modeled spool-down and flameout; fuel mass change |
| Single electric motor with direct-drive tractor prop | Loader branch supports fixed_voltage and ocv_resistance; synthetic fixtures only | Production aircraft acceptance; EDF/fan behavior |
| EDF | Unsupported | Ducted-fan map and installation effects |
| Tractor propeller | Existing configuration supported | Direction remains a fixed convention; reverse rotation is not supported |
| Pusher propeller | Unsupported as a declared/validated layout | Installation, orientation and wake effects need a validated model |
| Multiple engines | Unsupported | Per-engine placement/state, asymmetric thrust and failure aggregation |
| Fixed tricycle/taildragger gear | Supported as static spring/damper contacts | Gear movement, brakes and doors |
| Retractable gear | Frozen configurations only: P-51 down, Avanti up | Deployment/retraction, actuation, drag and changing contacts |
| Flaps | Not simulated | Control, deployment state and aerodynamic change |

This matrix describes the migration baseline. The concurrently integrated GP wheel-profile interface adds explicit rotating-wheel and optional brake equipment parameters outside aircraft JSON; all current aircraft profiles remain unbraked. Its validation, consumers and separate ownership are recorded in the [current module supplement](../AS-01/module-semantics.md#concurrent-ground-profile-interface).

## Files and authoring

`research/aircraft-standardization/migrate.py` exposes `upgrade(raw)` and `legacy_input(raw)`. `upgrade` returns a deep-copied v2 object and is idempotent for valid v2 data. `legacy_input` provides the historical v1 layout for derivation and mutation tools, including reversing the CLadot path and fixed rotation string without dropping numeric values.

Extra, P-51 and Avanti continue to derive their own physics; each now converts any copied Stik source to a legacy view and upgrades the completed result before writing. The Ugly Stik physics file is authored rather than generated. The electric configurations are authored synthetic fixtures, so the migration stages them directly; there is no separate electric generator.

Generated report paths use POSIX separators explicitly, so Windows generation and Linux freshness checks agree. The final portability correction changed report headers only; all eight aircraft JSON byte hashes stayed unchanged ([evidence](../AS-04/full-suite/generator-portability.log)).

For an authoring starting point, use [openrc-aircraft-v2.template.json](../../../../research/aircraft-standardization/template/openrc-aircraft-v2.template.json) as a shape example only. It is a structural copy of the experimental Stik; every quantity is classified as borrowed and its source note identifies the donor evidence kind and provenance. Replace its ID, values, sources, frame notes and capability choices with evidence and behavior for the new configuration; it is not a validated model and is intentionally absent from the migration allowlist.

## Staged verification and regeneration

The staged candidates live in `.tools/as-integration/app/data/aircraft`; all eight live app JSONs currently match them. Use a stage first when preparing a new migration candidate:

```powershell
python research/aircraft-standardization/migrate.py --write-known --output-dir .tools/as-integration/app/data/aircraft
$env:OPENRC_AIRCRAFT_OUTPUT_DIR = '.tools/as-integration/app/data/aircraft'
$env:OPENRC_AIRCRAFT_REPORT_DIR = '.tools/as-integration/reports/extra'
python research/extra-300/ex05/derive_physics.py
$env:OPENRC_AIRCRAFT_REPORT_DIR = '.tools/as-integration/reports/p51'
python research/p51/p51-05/derive_physics.py
$env:OPENRC_AIRCRAFT_REPORT_DIR = '.tools/as-integration/reports/avanti'
python research/avanti-s/av06/derive_physics.py
python research/aircraft-standardization/migrate.py --check-known --input-dir .tools/as-integration/app/data/aircraft
python research/aircraft-standardization/test_migrate.py
```

Each derived generator checks numeric parity for its assembled legacy object before and after migration. `--check-known` is a strict v2 check: it rejects v1 input rather than upgrading it in memory. After reviewing staged results, the installed loader accepts the v2 fleet; `--write-known` without `--output-dir` targets the live JSONs, and the three derived generators can write there by setting `OPENRC_AIRCRAFT_OUTPUT_DIR=app/data/aircraft`. Keep derivation reports under a staging `OPENRC_AIRCRAFT_REPORT_DIR` unless intentionally updating their owning research evidence.
