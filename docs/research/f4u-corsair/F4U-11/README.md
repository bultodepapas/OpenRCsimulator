# F4U-11: crash sections and repair economics of the F4U Corsair

Built 2026-10-22 for the [F4U plan](../../../F4U-PLAN.md). Presentation and cost estimates; no structural failure physics.

## Crash release

The g1.3 GLB tags every mesh and pivot with `openrc_section`, and the shared wreck collector builds ten fragment groups: `core`, `wing_left`, `wing_right`, `wing_center`, `engine`, `propeller`, `horizontal_tail`, `vertical_tail`, `gear`, `canopy`. Each outer wing panel carries its aileron and outer flap (same section); the inner gull panels with flaps 1–2 form `wing_center`.

| Check ([verify_f4u.gd](../../../../app/aircraft/verify_f4u.gd)) | Result |
| --- | --- |
| Wreck twin prepares and exposes all ten sections | pass |
| C3 hit naming the left wing | releases exactly `wing_left` |
| C3 hit naming the right wing | releases exactly `wing_right` |
| C3 spinner hit | releases exactly `propeller`, `engine`, `canopy` |

The catalog crash suites (`test_crash_wreck`, `test_crash_integration`, `test_crash_pose`, `test_crash_hull_labels`, `test_crash_energy`) pass with the Corsair: twin, C2 and C4 behavior, the accepted crossing tick, hull labels and the `gasoline` energy tag.

## Repair economics

[costing_entry.py](../../../../research/f4u-corsair/F4U-11/costing_entry.py) writes an independent dossier into `research/crash-economics/aircraft-costing.json`, pinned to the physics file's SHA-256; `build_runtime.py` turns it into `app/data/economy/catalog.json`.

- Every inventory row is bound to one of 27 lines; the virtual balancing mass is excluded automatically.
- Each of the 23 hull probes, three gear contacts and the propeller strike maps to the components it inspects (a cowl-bottom hit inspects cowl and engine).
- Priced: ten flight-control servo positions with the SA-1230SG+ proxy and two throttle/choke servos with the HS-311 proxy (subtotal $1,067.88), the same observations the P-51 uses.
- Unpriced and listed as missing: the CARF kit, spares and retracts, propeller, airframe parts, radio, fuel system and labor. The Moki S250 lists at 4,610.00 USD (CARF, observed 2026-10-22). It is recorded in the notes, not as a price observation, because the shared price catalog carries one observation date for every aircraft and a new date would restamp them all.

The dossier is therefore incomplete, as the P-51's and the Ventage Jet's are.

## F4U-11-R1: structural crash contacts (2026-10-25)

The R59 hull omitted the outermost wing vertices, the underside of the gull-wing roots and the tailcone of the delivered g2.2 mesh. The hull now retains the original 14 probes in order and appends nine measured supports: two wing tips, two gull-wing undersides, tailcone, rear fuselage underside, two aft stabilizer corners and the upper aft fin. [The extractor](../../../../research/f4u-corsair/F4U-11/extract_crash_geometry.py) checks the frozen GLB identity and records each source mesh, direction and vertex in [crash-geometry.json](../../../../assets/aircraft/f4u-corsair-250/crash-geometry.json). Physics, Workshop hashes and repair mappings are regenerated through their normal pipelines. CI checks the extractor output before physics derivation.

| Previously missing support | Distance |
| --- | ---: |
| Each wing tip, lateral direction | 53.440 mm |
| Gull-wing underside, structural hull excluding propeller probes | 66.369 mm |
| Tailcone, tail-first direction | 145.752 mm |

The two root contacts use `left_wing_root` / `right_wing_root`, classified in the existing `wing` severity group. A C3 root impact releases the central section and the struck outer wing; a C3 tip impact still releases only that outer wing. Root repair mappings include the corresponding wing and joiner. These are presentation and repair estimates, not calibrated structural failure mechanics.

Verification on Godot 4.8-beta1:

- [Model contract](checks/model-contract.log): 113 checks pass. All nine points lie on the independently imported mesh within 2 micrometres, meet their support planes, stay clear 1 mm above ground and detect a hard crossing 1 mm below it. Contact IDs survive event serialization. Whole-hull left-tip, right-tip and tail-first impacts select the intended new points.
- [Negative control](checks/old-hull-negative.log): a disposable copy of the same verifier using the retained original aircraft input fails the nine missing-ID checks and all three whole-hull crossing checks. The old hull returns index `-1` in each crossing, confirming missed detection rather than merely renamed contacts.
- [Hull labels](checks/hull-labels.log): 259 checks pass, including schema vocabulary, side labels, severity grouping and wreck mapping. [Production crash integration](checks/crash-integration.log): 202 checks pass across the fleet; headless audio playback is explicitly skipped.
- All seven relevant generator checks pass; crash-economics Python suite: 62 tests pass. No frame-rate qualification is claimed: runtime uses 23 bounded points and performs no mesh scanning.

Flight evidence retains the [original recording](checks/baseline.orfl) and its [exact replay](checks/exact-before.json). Accepting the two new component labels changes the loader's solver fingerprint, so the [original aircraft input](checks/baseline-aircraft.json) was also recorded with the updated loader as [isolated-baseline.orfl](checks/isolated-baseline.orfl). Its [exact replay](checks/isolated-exact.json) and the [candidate replay](checks/candidate.json) both report `complete: true`, `solver_changed: false`, 2,401 rows and tick 2,400. The [same-tape comparison](checks/comparison.json) has no divergence. All three CSV outputs are byte-identical to the retained [F4U-12 CSV](../F4U-12/baseline.csv); hashes and source identities are in [identities.json](checks/identities.json). The candidate remains a candidate replay, not an exact replay claim.

Limits: these are sampled supports in neutral control pose with wings spread, not triangle collision for every attitude. The lowered tailhook and folded wings do not acquire dynamic crash geometry. The gull-wing support measurement excludes the propeller; it does not claim the root must strike first in a level impact. The airborne replay protects flight behavior on this tape; it neither validates crash realism nor replaces the measured crossing tests.
