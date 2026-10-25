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

- Every inventory row is bound to one of 33 lines; the virtual balancing mass is excluded automatically.
- Each of the 23 hull probes, three gear contacts and the propeller strike maps to the components it inspects (a cowl-bottom hit inspects cowl and engine).
- Parts-only references: ten flight-control servo positions with the SA-1230SG+ proxy, two throttle/choke servos with the HS-311 proxy ($1,067.88 together), a single-color cowl ($262), horizontal surfaces ($454) and vertical surfaces ($241), plus whole-engine ($4,610) and air-system ($479) proxies. The $7,113.88 reference subtotal is not the aircraft value or an accident bill.
- F4U-11-R3 retains 30 dated CARF USD observations and two newly dated servo rechecks. The $5,170 exact kit, wing, fuselage and gear offers remain unattached where scope overlaps or installed coverage is unresolved. Engine/air package references require explicit replacement decisions. Historical servo dates and other aircraft bindings are preserved.

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

## F4U-11-R2: cost and damage matrices (2026-10-25)

This section records the R2 acceptance state; R3 below supersedes its engine package and price-research gaps. Contact and inspection behavior is unchanged.

Two research agents independently investigated [current purchase prices and package boundaries](cost-research-2026-10-25.md) and [inspection/disposition evidence](damage-research-2026-10-25.md). Primary CARF and MOKI pages establish product identities; manufacturer/model-association guidance informs inspection prompts. Full-scale composite guidance is an analogy only. No source established calibrated Corsair fracture thresholds, crash survival probabilities or post-impact labor costs.

The generator now separates the ten flight-control servos into seven installation groups: left/right aileron (one each), left/right flap (two each), elevator (two), rudder (one), and tail steering (one). The two throttle/choke servos remain separate. Physical inventory identities and aircraft dynamics are unchanged. Contact mappings cover all 23 hull probes, three gear supports and the propeller strike.

| Accepted contact | Economic components opened for inspection | Automatic cost consequence |
| --- | --- | --- |
| Left/right outer wing | That wing, its aileron and flap servos, joiner | None; opposite-side controls stay untouched |
| Left/right gull underside | That wing, joiner, same-side flap servos and main gear, shared air system | None |
| Main gear | Struck leg, its wing attachment, joiner and air system | None; a set price is not assigned to one leg |
| Tail gear | Tail gear, rear fuselage, steering servo and air system | None |
| Stabilizer | Horizontal surfaces, elevator servos, rear fuselage | None |
| Fin/rudder | Vertical surfaces, rudder servo, rear fuselage | None |
| Tailcone/rear underside | Rear fuselage, horizontal tail, elevator servos, tail gear and steering | None |
| Cowl/spinner | Local nose structure, engine/mount and nearby ignition/control installation | None; engine purchase remains unconfirmed |
| Confirmed simulation propeller strike | Powertrain/mount/cowl/ignition controls inspected; one propeller marked for replacement | Existing conservative simulation rule; exact prop price remains unknown |

These mappings are authored inspection scopes based on installation and load paths, not predictions of fracture or propagation. `inspect` does not mean `replace`. A later explicit inspection/scenario receipt determines the affected quantity and disposition. Visual C0-C4 severity, detached meshes and fire particles cannot create a bill or prove salvage.

| Price reference | Runtime treatment |
| --- | --- |
| Cowl, CARF 791102, $262 | Single-color price proxy; scheme-specific paint quote/hardware/labor remain unknown |
| Horizontal tail, 791301–791304, $454 | Parts-only composite: $111 + $111 + $111 + $121; only explicit replacement of the grouped inventory row selects it |
| Vertical tail, 791305–791306, $241 | Parts-only composite: fin $130 + rudder $111; no automatic two-part loss from a contact |
| Moki S250, 953250, $4,610 | Unattached candidate: ignition is included, cast mount coverage unresolved; never add a second ignition charge |
| Main retract set $1,330; wheel pair $346 | Unattached set/pair references; no unsupported per-side division |
| Tail gear $608 and one listed door $93 | Unattached; door contents/quantity and steering linkage do not establish a complete tail-gear basket |
| Folding wings $754 each; fuselage $1,770 | Unattached until finish, control-surface/hardware inclusion and assembly overlap are reconciled |
| 32-inch carbon propeller set $692 | Unattached: different from the authored SEP-class 30x18 wood propeller |

Amounts exclude unresolved finish, hardware, labor, tax and freight. Missing prices remain null; a partial subtotal cannot become a complete repair total. EUR kit/engine quotes stay research evidence without an invented exchange rate. Offer observations retain their dates, package quantities, URLs and availability caveats; runtime performs no shopping or internet calls.

**Corrected defect:** the old Corsair `propeller_inspection_ids` included `propeller`, so `_mark_propeller()` changed `replace` back to `inspect`. The generator excludes that self-reference; observation and checkpoint reconstruction also guard against it. A disposable copy with the old observation loop fails the two new self-reference/recovery checks; the corrected code passes. Duplicate accepted events still cannot charge twice.

**Evidence:** [retained checks and source identities](checks/cost-r2/identities.json) record 64 Python tests and 431 Godot checks: inspection 79, checkpoint 65, catalog 90, report 119, production integration 78. All three economics generators pass `--check`. The production regression confirms identical healthy float64 state with economics enabled/disabled and frame-cadence-independent reports. This is headless software evidence, not physical damage validation, a rendered 1080p qualification or a full repository-suite run. No physics data or solver law changed.

## F4U-11-R3: double price pass (2026-10-25)

The [price research](cost-research-2026-10-25.md#double-pass-findings-f4u-11-r3) records two specialist passes and independent review of exact variants, package coverage, currencies and dated availability. All 29 previous CARF amounts matched. New observations add the exact Navy Blue folding ARF at $5,170 and refresh the unchanged Savox/Hitec proxy prices, preserving historical observations.

The MOKI manual resolves standard cast-mount inclusion; engine, ring muffler and ignition are covered by one $4,610 purchase proxy. Applying manufacturer package contents to CARF remains an explicit same-model inference. The separate module/switch row stays unpriced: no duplicate included-ignition charge and no invented switch or module-only repair price. The $479 pneumatic completion set explicitly includes the tank and now prices whole-system replacement only. Known parts references total **$7,113.88**, excluding the kit; the dossier remains incomplete.

The SEP 30×18 size option costs **€172.94 undrilled / €187.94 bored** before delivery/import charges. The €157.35 base belongs to 29×18. This EUR evidence is retained in research; USD runtime pricing remains null. Neither Aeroscale's $112 family listing without a 30×18 variant nor CARF's $692 carbon alternative substitutes for it.

**Verification:** [retained identities and checks](checks/cost-r3/identities.json): 66 Python tests, 83 Godot inspection checks and 90 catalog checks pass; all three generators pass `--check`. New scenarios exercise explicit engine/air replacement at $5,089, no second ignition charge, unknown remaining totals and duplicate-receipt idempotence. Contact/propeller-strike scenarios retain zero known charges before inspection. [The audit comparison](checks/cost-r3/comparison.md) records three added offers, three source-URL changes and three allocation changes; 121 offers are unchanged. No physics source, simulation law or economic runtime logic changed. These focused headless checks do not constitute a full repository-suite run or physical validation.
