# F4U-21: extra movements (canopy, tailhook, cowl flaps)

Built 2026-10-25 for the [F4U plan](../../../F4U-PLAN.md) at the owner's request: focus on the extra movements, "the engine flaps, the wings, the landing gear, the folding wings". Presentation only; the flight model is unchanged.

## Audit of g2.2's moving parts

[motion_audit.gd](../../../../research/f4u-corsair/F4U-21/motion_audit.gd) builds the catalog model through the production builder, stands it on its wheels and photographs close views through each motion at 1920×1080. [inventory_rig.py](../../../../research/f4u-corsair/F4U-21/inventory_rig.py) lists every R59 rig control and what it drives. Stills stay outside the repository in `D:\OpenRCsimulator-evidence\f4u-motion-20261025\`.

| Movement | R59 rig | g2.2 before F4U-21 | Result |
| --- | --- | --- | --- |
| Main and tail gear, doors, oleo | `tren_retraccion`, R22/R27/R28 | Sampled `GearRetract` (F4U-05) | Correct: legs fold aft with the 90° wheel twist, doors and tail doors follow, no clipping in transit |
| Flaps, ailerons, elevator, rudder | `flaps_deg`, `alerones_deg`, … | Hinges (F4U-05) | Correct over their ranges |
| Wing fold | R51 `plegado_*` | Fold groups (F4U-17) | Correct. R55 flush hinge covers and R53 struts and lock pins stay static; no visible fault at the joint |
| Canopy slide | `CABINA \| apertura` | `canopy_frame`, `canopy_glass` separate, static | **Added** (below) |
| Tailhook | `gancho_cola_deg`, `R27 \| pivote gancho` | `core_details` holds only the hook, static | **Added** (below) |
| Cowl flaps, 16 sectors | `cowl_flaps_deg`, `R14 \| bisagra sector 01…16` | Merged into `cowl` with the lip | Needs the author: [g2.3 request](../../../F4U-G2-3-REQUEST.md) C1 |
| Trim tabs, propeller pitch, stores | `compensador_deg`, R49, R45/R47 | Merged or not delivered | Out of scope |

## Source: R59's own rig

[extract_mechanisms.py](../../../../research/f4u-corsair/F4U-21/extract_mechanisms.py) reads R59 (SHA-256 `94edd59b…`) read-only, parses each driver, opens every mechanism in memory and compares Blender's evaluated world matrices with the analytic motion. Output: [mechanisms-r59.json](../../../../assets/aircraft/f4u-corsair-250/mechanisms-r59.json).

| Mechanism | R59 law | Blender check |
| --- | --- | --- |
| Canopy | Straight slide: location x = 0.70 · apertura, z = −0.0385 · apertura (aft and slightly down), no rotation | 6 × 10⁻⁸ |
| Tailhook | Turn about the pivot's local Y by `gancho_cola_deg`, 0–45° | 6 × 10⁻⁸ |
| Cowl flaps | Each sector turns about its hinge's local −Y by min(28, max(0, `cowl_flaps_deg`)) | 2.4 × 10⁻⁷ |

[compile_model.py](../../../../research/f4u-corsair/F4U-05/compile_model.py) maps the canopy and hook by D0 and the 1:4.5 scale. The canopy slides (0, −0.0086, 0.1556) m. The mapped R59 glass centre lands on g2.2's `canopy_glass` within 1 µm. The hook turns 45° about (0, 0.0978, 1.2895) m, axis +X. Its mapped centre lies 2.1 mm from `core_details`, because R59's hook parts are curves. The hook's tip, the aft low corner of its bounds, is its ground point. Cycle times are estimates: 2.5 s for the canopy and 1.5 s for the hook; R59 has no timing.

## Runtime

- **Model contract:** optional `construction.mechanisms`, at most one each of `canopy`, `tailhook` and `cowl_flaps` ([AIRCRAFT_CONTRACT](../../../AIRCRAFT_CONTRACT.md#model-and-package-contract)). A part slides by an offset or turns about a fixed axis in proportion to a 0–1 state. `imported_model.gd` moves members in place. It refuses a member that a hinge, fold or other mechanism already moves.
- **Flight scene:** **U** opens or closes the canopy and **Y** lowers or raises the tailhook, in the air or on the ground. The HUD shows each state, and restart closes and stows both. On the ground the lowered hook rests on the runway, as the real hook rides the deck. At full travel in the three-point attitude it would sink 0.13 m into the ground. Spanish strings, the controls reference and [FIRST-LAUNCH](../../../FIRST-LAUNCH.md) list the keys.

## Verification (2026-10-25, Windows, Godot 4.7.2)

| Check | Result | Evidence |
| --- | --- | --- |
| `verify_f4u.gd` | 40/40. New: both mechanisms bind their parts; canopy slide 0.1558 m without turning, half at 0.5; hook 45.0000° about R59's pivot; ground stop puts the tip on a test floor within 1 × 10⁻⁵ m and lowers fully over open or unknown ground; exact return to rest; an unknown key and a member already moved by a hinge are refused | [checks/verify_f4u.log](checks/verify_f4u.log) |
| [mechanism_check.gd](../../../../research/f4u-corsair/F4U-21/mechanism_check.gd), production flight scene, 1920×1080 | 8/8: U and Y open and lower in the air (2.5–3.0 s of wall time across runs, the canopy's 2.5 s cycle plus frame pacing), the HUD reports them, the solver keeps running without a throttle hold, U again reverses, restart stows both, on the runway the hook tip rests 0.0000 m above the ground | [checks/mechanism-check.json](checks/mechanism-check.json) |
| Generators, `--check` | `compile_model.py`, `build_models.py`, `build_descriptors.py`, `build_customization.py` current; `test_models.py` 17/17 | — |
| Parked-aircraft bakes | Rebaked for the importer and builder pins: Avanti, Extra, P-51 and Timber change only their source hashes; meshes are byte-identical | — |
| Related suites | See [checks/suites.txt](checks/suites.txt) | [checks/suites.txt](checks/suites.txt) |

Two findings outside F4U-21:

- `test_models.py`'s fresh-clone test failed since F4U-20: its fixture did not copy the livery GLBs that `build_models.py --check` hashes. The fixture now copies every manifest livery and its sidecar.
- The Ugly Stik's parked bakes (`stik_assembled`, `stik_service`) were already stale at HEAD: the O.S. 61 engine change altered `ugly_stik_model.gd`, its geometry and manifest. A rebake raises the Stik's distant LOD from 8,388 to 19,544 triangles. F4U-21 leaves both files as they were for the engine's owner.

## Limits

- Presentation only: the canopy and hook change neither drag nor mass. The hook catches nothing.
- The ground stop uses the rendered terrain height under the tip; it keeps the tip above it, not the whole hook.
- Cycle times are estimates.
- Cowl flaps wait for g2.3. The contract already accepts `cowl_flaps`; the integration will add the sixteen hinges from `mechanisms-r59.json` and a flight-scene law.
