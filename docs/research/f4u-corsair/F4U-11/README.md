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
- Each of the 14 hull probes, three gear contacts and the propeller strike maps to the components it inspects (a cowl-bottom hit inspects cowl and engine).
- Priced: ten flight-control servo positions with the SA-1230SG+ proxy and two throttle/choke servos with the HS-311 proxy (subtotal $1,067.88), the same observations the P-51 uses.
- Unpriced and listed as missing: the CARF kit, spares and retracts, propeller, airframe parts, radio, fuel system and labor. The Moki S250 lists at 4,610.00 USD (CARF, observed 2026-10-22). It is recorded in the notes, not as a price observation, because the shared price catalog carries one observation date for every aircraft and a new date would restamp them all.

The dossier is therefore incomplete, as the P-51's and the Ventage Jet's are.
