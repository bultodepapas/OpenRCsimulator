# Savox servo catalog and replacement plan

Updated: 2026-10-14. Status: product-representation permission confirmed; catalog selection and replacement are not implemented. Owner: physics/input track, using D6-SAV-00…08 under D6. Workshop integration belongs to AE; shared aircraft contracts and topology belong to AS, coordinated with EM. [Ownership map](../README.md#tracks-plans-and-step-ids).

## Outcome and support

Let a player replace supported aircraft servos with identified Savox catalog products and compare speed, mass, torque, voltage, dimensions and indicative cost. The selected hardware must affect the simulated installation through sourced parameters. Price is comparison information and never a physics multiplier.

Savox is credited as a **partner** for permission to represent its products. The 2026-10-14 reply also offers an engineering contact and social-media coverage once the servos are added. It does not establish financial sponsorship, donated hardware, supplied engineering measurements or validation of our simulation. [Permission record and dated catalog research](../research/servos/D6-SAV-00/README.md).

## Existing foundation

| Current source | Reuse / limitation |
| --- | --- |
| [Aircraft contract](../AIRCRAFT_CONTRACT.md#physical-modules-and-parameter-effects) and [actuator kernel](../../app/physics/control_actuators.gd) | Rate-limited normalized motion already exists. `servo_full_throw_time` means neutral-to-full travel, not the manufacturer's seconds per 60° of output-shaft rotation. |
| [Controls boundary](../AIRCRAFT_CONTRACT.md#shared-module-and-runtime-interfaces) and [EM-03a evidence](../research/failure-mode/EM-03a/README.md) | Current aircraft retain three logical servo states. Separate visual hinges do not establish independent installed servos. |
| [Workshop](../AIRCRAFT-WORKSHOP.md), [parameters](../../app/workshop/parameters.gd) and [compiler](../../app/workshop/compiler.gd) | Detached variants, validation, immutable saves and trials exist. The closed recipe currently has no hardware selection; changing control travel retains normalized servo timing. |
| [Stik inventory](../../app/data/aircraft/jensen_ugly_stik_60.json) | Estimated 135 g for three fuselage servos plus a 45 g aileron servo; the common 0.14 s timing is estimated. The grouped mass is not an actuator-to-surface map. |

## First deliverable

Start with the stock-size Stik, a declared 6.0 V servo supply, and a verified installation for each conventional control. Offer SA-1258TG+ and SA-1230SG+ only where mounting, travel and linkage checks pass. These provide a useful faster/lighter versus slower/heavier/high-torque comparison at the same voltage. Add the Extra through the same capability path as the second integration fixture.

Keep SH-0255MG+ as a micro-size catalog candidate and SB-2270SG+ as an HV candidate. Neither is a universal replacement. Their airframe fit, supply and load requirements need separate qualification. The [dated comparison](../research/servos/D6-SAV-00/README.md#catalog-candidates) owns the initial specifications and price evidence.

The first flight model uses catalog speed, installed mass and derived CG/inertia. Display torque as a published rating with **load-dependent motion not yet modeled**. Introduce load, current draw, deadband, backlash and centering behavior only through later evidenced model work. Helicopter cyclic/tail, truck steering, flaps, gear and throttle actuation remain subsequent capability integrations.

## Data and installation contract

Separate reusable product records from aircraft installations:

- **Product:** stable manufacturer/model/revision ID, exact `+`/`P` variant, official URL, source date, mass, case dimensions, supported voltages, voltage-specific speed and torque, motor/gears, spline and published signal/travel limits. Preserve missing values as unavailable; do not invent curves from endpoints.
- **Installation:** stable physical component and actuator IDs, driven surfaces, number of real servos, mounting position/orientation/envelope, horn and linkage geometry, direction, neutral/endpoints and actual servo-bus voltage. One central aileron servo can drive two surfaces; do not count two automatically.
- **Price:** amount, currency, market, seller/source, observation date and sale/list distinction. Show per-unit and installed-set totals only when known; exclude shipping/tax unless explicitly sourced. Missing or stale price never blocks a physically valid aircraft.
- **Provenance:** use the v2 `{value, unit, kind, source}` rules for physical quantities. Catalog specifications are `manual`, conversions are `derived`, and unmeasured installation assumptions remain `estimated`. Preserve original units alongside the import evidence.

Extend the closed contract, schema and capability registry before adding fields to aircraft files. Use the owning aircraft pipelines; regenerate descriptors and model bindings where affected. Proposed new homes are `research/servos/` for import/generation, `app/data/servos/` for generated catalogs and `docs/research/servos/` for evidence. These paths are planned, not current runtime interfaces.

For the Stik, resolve the grouped fuselage inventory into explicit installation bindings before substitution. Preserve untouched hardware, including any throttle servo. Replace old servo mass once, account for required horns/mounts, and derive mass, CG and the full inertia tensor from positions. Keep fixed datum geometry fixed when CG moves. Real hardware retains its physical size/mass during virtual airframe scaling; initially refuse unsupported scaling combinations.

## Motion and persistence

For an initial constant-ratio, unloaded linkage approximation:

`shaft_speed_deg_s = 60 / catalog_seconds_per_60_deg`

`neutral_to_full_seconds = required_shaft_travel_deg / shaft_speed_deg_s`

Thus a 0.08 s/60° specification and 30° of required shaft travel imply 0.04 s neutral-to-full, not 0.08 s. This is a derived model example, not a bench measurement. Solve or validate both travel directions; unequal/nonlinear linkage requires the corresponding mapping rather than one guessed common time. Surface travel edits must recompute required shaft motion without changing the actual servo's rated speed.

Use the shared float64 actuator path, with per-control rates and explicit installation identity. Physics and rendering consume the same accepted surface angles. Preserve the existing sampled update order and transactional rollback. Do not change transmitter rates/expo to imitate a faster servo.

Initially offer only published voltage points within all installed devices' limits. An HV propulsion battery does not establish an HV receiver/servo bus. Interpolation, voltage sag and current/thermal behavior require an explicit later law; never extrapolate catalog data silently. Stall torque is not continuous permissible torque, and speed plus stall torque does not determine a load-speed curve.

Freeze product revision, physical catalog bytes, installation, voltage, recipe and compiler identity with the trial and saved build. Save/load/restart/replay must reproduce the same selected hardware. Keep commercial price metadata outside physical identity so a price update cannot change a flight. Missing or mismatched physical dependencies must fail clearly while retaining the existing saved build and accepted session.

## Workshop experience

1. Open **Aircraft Workshop → Servos** and choose a supported control or hardware group.
2. Compare installed and candidate products; filter/sort by compatible fit, speed at the selected voltage, weight, torque and dated price. Lower seconds/60° means faster. Explain unavailable choices with the actual voltage, mounting, travel or unsupported-topology reason.
3. Preview per-servo and total cost, installed mass difference, CG/inertia change, actual surface travel time and evidence limits. Do not label a servo “better” just because it costs more.
4. Apply to the draft, undo/reset if needed, save a build and start a new test flight through the existing transactional path. No mid-flight hardware replacement. Keep the original aircraft available.

Use the common AE parameter registry and EN/ES labels. Begin with text/specification cards. For visual representations, inspect the manufacturer's free PDF/3D downloads first and reuse suitable authorized assets with attribution and recorded terms. Do not rebuild available geometry or treat third-party assets as MIT code. Stable aircraft hinge names remain unchanged.

## Steps and acceptance

| ID | Work | Proof / status |
| --- | --- | --- |
| D6-SAV-00 | Verify permission, credit partner, identify initial catalog and current code boundary | Complete for documentation: [dated evidence](../research/servos/D6-SAV-00/README.md). No servo integration claimed. |
| D6-SAV-01 | Import the small catalog with exact revisions and voltage rows; resolve conflicting specifications and obtain fresh price observations | Pending: reproducible source manifest/hash, unit conversions, missing/conflicting-data rejection and manufacturer/seller separation. |
| D6-SAV-02 | Define the shared product/installation capability with AS, AE-12 component work and EM topology owners | Pending: closed-schema checks, real servo counts, mapping/fit/supply validation and legacy no-op parity. Do not create a parallel EM actuator schema. |
| D6-SAV-03 | Compile substitutions and mass/CG/inertia changes through source pipelines and generated bindings | Pending: independent mass/first-moment/tensor checks, no double counting, fixed-datum checks, descriptor freshness and invalid-draft rollback. |
| D6-SAV-04 | Add per-control catalog-derived motion through the shared kernel and versioned session identity | Pending: analytic timing, direction/endpoints, travel-change conversion, physics/render parity, pause/reset/restore/replay and unchanged stock flights. |
| D6-SAV-05 | Add the common Workshop selector, comparison and saved-build flow with AE-18 | Pending: Stik and Extra through the same code path; EN/ES at 720p/1080p, keyboard navigation, undo/reset, save/load, failed launch and return-to-draft captures. This closes the bounded speed/mass MVP. |
| D6-SAV-06 | Obtain engineering/bench evidence and extend torque/load, deadband, current and bus behavior where supported; detailed in the [servo load plan](servo-dynamics.md) (D6-SRV) | Pending: voltage/load/temperature-tagged measurements, tolerances fixed before fitting, held-out comparisons and independent physical validation. The offered contact is not delivered data. |
| D6-SAV-07 | Qualify further installations, HV/micro products and optional manufacturer visuals | Pending: per-aircraft fit/supply/load proof, generated asset provenance and topology/state tests before additional aircraft or servo roles are enabled. |
| D6-SAV-08 | Package the delivered scope and consolidate operating instructions | Pending: tests, package smoke checks, frozen evidence and accurate release notes. Prepare release material for Savox; sending it remains a separate maintainer action. |

Use [TOOLS](../TOOLS.md) for native focused checks, `app/test.sh` and `research/test-tools.sh` as affected. Relevant existing checks include `test_servo.gd`, `test_control_actuators.gd`, `test_control_surface_observation.gd`, Workshop tests and checkpoint tests. Run independent timing/mass oracles and 240/480/960 Hz comparison for new motion laws; preserve stock golden flights unless physics deliberately changes.

Minimum demonstration: at fixed voltage/linkage/throw, a faster catalog servo reaches the same target sooner; a heavier installed servo changes mass and its position-dependent CG/inertia; a price-only edit leaves the trajectory identical. An incompatible installation is refused without disturbing the accepted flight. Software evidence closes implementation gates, while hardware measurements and pilot comparison close physical-validation claims separately.
