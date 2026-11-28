# ClearView implementation evidence — 2026-11-17

These eight packets record the tested worktree, its measurements, failures and proposals at the time. The [integrated corpus record](../clearview-2026-11-15.md#closeout-every-corpus-aircraft-flies-ac-cv-2026-11-20) gives the later results; the [ClearView contract](../../../plans/clearview-aircraft-import.md) defines the supported workflow.

## 6. Implementation status

### Packet 1 — independent repairs (2026-11-17)

```text
Existing step / phase: AC-CV-02/04 and AC-10/14 (Phase 1–2 independent repairs); AC-09/11 and AC-13/18 boundary fixes (Phases 3–4 prerequisites).
Baseline and integrated commit: main f0ed7dec + audit branch efc93d07; branch feat/aircraft-import-closeout-2026-11-17.
Owner and changed source/schema boundaries:
  clearview/package.gd, images.gd, converter.gd, motion.gd — cancellation is terminal at every poll, including the last
    model, PNG decode and final GLB admission; complete nested models are listed unavailable with a reason;
    targeted move/input servos report "unsupported_servo_movement"; v5 models state that motion is unmapped.
  authoring.gd + ui/aircraft_creator.gd — the document owns rejected inventory text ("inventory_raw" snapshot member,
    written only when non-empty; format unchanged). It dirties the document, is backed up/saved/reopened, and
    blocks Authoring.compile() and therefore capture, publication and new trials.
  compiled_publication.gd / source_resolver.gd — verify_derivation() recompiles and compares exact raw bytes before
    a bound v2 owner is sealed.
  trial.gd / main.gd — Trial.check_start selects the same explicit reference backend as Main (FLIGHT_BACKEND);
    servo-law aircraft fly with hard hull contacts, as checked.
  app_root.gd / main.gd — workshop trials detach the previous flight tentatively (its log stays open on failure,
    is finalized at commit) and assess/launch the previous flight's installed field and weather.
Player-visible outcome: cancel always cancels; no silently missing nested model or moving part; a typo in an
  inventory mass survives save/reopen and blocks flight until corrected; a failed trial start keeps the F10 log.
Source fixture and semantic assumptions: synthetic ZIP/AC3D/PNG fixtures in the existing tests; no corpus archive.
Positive and counterexample checks (Windows 11, Godot 4.8.beta2, headless, worktree candidate):
  test_creator_clearview_{readers 91, visual 51+, motion 224+, jpeg 363}; test_creator_trial; test_creator_compile_binding 91;
  test_creator_source_ref 240; test_creator_published_trial 62; test_creator_store 509; test_creator_clearview_ui 68;
  test_creator_persistence_ui 104; test_creator_ui 201; test_creator_publication_ui 28; test_creator_flow;
  test_workshop_integration (rollback keeps the same log for a later tick; commit finalizes it). All 0 failures.
Observed result and exact remaining limitation: no source-aware physical adoption, no qualified flight domain and
  no Home consumer. Cancel-to-idle latency is unmeasured. Property-level override ownership, wingspan/datum raw
  ownership and a full effective start request/receipt (lake, track, collision, SOC, timestep) remain open.
  The CLI field/weather fix aligns check and launch with the previous flight's installed context but has no
  dedicated direct-launch regression yet. Cross-platform byte determinism of compile_candidate is unproven.
Next packet, dependency and exit condition: Phase 0A candidate table for Extra 330 Red (needs the hash-pinned archives),
  then Phase 1 source adoption; Phase 3 start request/receipt with a direct --landscape/--wind regression.
```

### Packet 2 — ClearView models test fly (2026-11-17)

Owner request: make downloaded ClearView aircraft importable and flyable now. This is a deliberate policy change ([decision](../../../DECISIONS.md)): a labelled independent estimate may test fly before source-faithful adoption. It does not close Phase 1 (source adoption), Phase 3 (G05/G06 qualification) or Phase 4 (Home/publication).

```text
Existing step / phase: AC-CV-02..05, AC-09/10 (Phase 2 review; Phase 3 unsaved trial for the estimated configuration only).
Baseline and integrated commit: packet 1 on feat/aircraft-import-closeout-2026-11-17 (uncommitted).
Owner and changed source/schema boundaries:
  clearview/setup.gd (new) — documented ClearView render frame (metres, nose -X, up +Y) and a leading edge estimated
    by cutting triangle edges at 0.35/0.65 of the half-span (propeller, disk, wheel, gear, strut and smoke nodes
    excluded; sweep extrapolation capped). Elevon models are refused.
  authoring.gd apply_clearview_setup — one explicit, revision-guarded action. It fills only unresolved placement and
    empty fields (marked Estimated), proposes the inventory, keeps estimated tail volumes and aspect ratios inside the
    package domain, balances to static margin 0.15 (battery, then a visible "Nose balance weight (estimated)"),
    and records the existing independent-installation declaration.
  source_installation.gd / trial.gd / authoring issues — ClearView flight is refused only under the servo-interval
    law. freeze pins the declaration in the trial identity; verify refuses a ClearView trial without it.
  converter.gd — undecodable texture formats (GIF) are omitted with a note; invalid or oversized images still fail.
  UI — "Set up for flight automatically" with a confirmation; Save aircraft explains that publication is unavailable.
Player-visible outcome: Import ZIP -> Set up for flight automatically -> Test fly; Save draft; restart; Open -> Test fly.
Source fixture: CVplanesPk7 (16 local folders, zipped under tmp/, not redistributed). Not adopted: ClearView
  coefficients, modelMass (Yak 54 Lightning declares 10.8; estimate 3.6 kg), motors, gear.
Corpus result (headless, Windows): 12/16 convert visually (14/16 with the GIF fix). Flying: Yak 54 Lightning (airborne;
  hand launch honestly refused). Refused with reasons: span < 0.9 m (Yak 55 Electric, Y-Wing, VJ-101, Waterflyer),
  span > 2.2 m (V-22, U32 Pitts, Yak-55), elevons (Zagi x2, XF5U, Waterflyer), propeller offset (X-wing, X-35B),
  verNumber 0 params (XFV-1, VJ-101 VTOL), ambiguous marker (Votec 351, refusal kept deliberately).
Real app (Windows, 1920x1080, local session): imported Yak 54 Lightning, setup, test fly 120 fps, roll/pitch response,
  Save draft, process restart on the same profile, Open draft, test fly again (same aircraft id).
Checks: new test_creator_clearview_setup (21); updated source_installation (90), clearview_visual (54), language;
  creator trial/ui/persistence/flow/publication/compile_binding/source_ref/servo_document/clearview_ui/motion, 0 failures.
Remaining: Home listing and publication of ClearView aircraft (Phase 4); wider package domain or source adoption for
  small/large/elevon models; verNumber 0 dialect; render comparison against ClearView itself.
```

### Packet 3 — ClearView corpus robustness (2026-11-17)

```text
Existing step / phase: AC-CV-02..04 (conversion robustness), AC-09/10 (estimated setup), owner request "import all".
Source fixture: the owner's seven CVPlanesPk1..7 ZIPs (132 model roots; local only, hashes in the run log, not redistributed).
Changes:
  setup.gd — the wing span is measured from the wing (rotors and props excluded). Outside the 0.9-2.2 m domain the
    model is proposed at the nearest supported size, as an explicitly scaled configuration stated first in the dialog.
    A missing propeller is stated.
  authoring.gd — when setup chose the size, a too-heavy or overpowered small model is tried larger (<= 5 attempts, from
    the same state); a tail-heavy estimate whose battery is already at the nose gets the largest permitted estimated
    tailplane; the nose weight never exceeds the package mass range.
  converter.gd / ac3d.gd / motion.gd / params.gd — non-fatal with counted notes: missing textures, up to 32
    self-intersecting or untriangulable polygons, float32 slivers, subdivided surfaces (control mesh), ambiguous
    helper markers (hidden, part static). Float32 tolerance 0.1 % of a part. Flat v0-v4 parameters accepted.
    Hostile/limit guards (size, work, pixels, 1e8 offsets, >128 meshes) unchanged.
Corpus (headless Windows, conversion -> setup -> compile -> frozen trial -> airborne start check):
  before this packet 42/132 fly; after 105/132 fly; 131/132 convert visually.
  Refused with reasons: 15 jets (nose estimate > 1 m from the balance point), 8 elevon/flying wings, 3 unbalanceable
  estimates (A6-Zero, Fokker DR1, Stearman), 1 autogyro, 1 model over 128 meshes (Hindenburg).
Real app (1080p): PA-Cub (3.48 m) proposed at 2.16 m with the stated scale, test flight 98 fps.
Checks: 20 Creator/ClearView/Workshop suites, 0 failures.
Remaining: jet/ducted-fan and flying-wing packages (physics owner); Home/publication (Phase 4); source adoption (Phase 1).
```

### Packet 4 — park jets and balance (2026-11-17)

```text
Existing step / phase: AC-CV-05/06 estimate quality; Phase 0A evidence on source mass.
Changes:
  data/creator/power-electric-4s-800kv-apc12x6-pusher-estimated-v1.json (new) — same donor hardware, "layout": "pusher";
    the mirrored APC pusher shares the tractor CT/CP tables (as the stock single_pusher record does).
  packages.gd — registry entry; is_pusher/aft_sign; motor ahead of a pusher hub. compiler.gd — single_pusher capability,
    firewall and crash-hull spinner point ahead/behind by layout, nose-hub domain only for tractors.
  authoring.gd — the power package is a document choice (snapshot member written only for the pusher; unknown ids
    refuse the draft). The ClearView setup picks the pusher when no propeller node exists and places the hub 0.04 m
    behind the wing root at the fuselage centre line. A tail-heavy estimate that the mass range cannot ballast is
    tried at 90 % size (setup-chosen size only, labelled scaled).
Findings: v5 modelMass is unreliable (5.2 kg shared default; e.g. 1.48 m Twinstar II declares 3.0 kg), v6 plausible
  (EasyStar 0.70 kg, Sky Surfer 1.0 kg). Not adopted.
Corpus (7 packs, 132 roots): 105 -> 122 fly. Refused with reasons: 8 elevon flying wings (tailless estimator needed),
  Lockheed XFV-1 tail-sitter, Kellett autogyro, Hindenburg airship (>128 meshes).
Real app (1080p): F-104 set up as a pusher park jet (hub behind the wing), test flight at 30 m, 16.8 m/s.
Checks: test_creator_clearview_setup 34 (pusher compile, firewall/motor ahead of hub, offset aft of CG, draft
  round trip, unknown package refused) plus the regression batch below.
Next (physics owner): a tailless/elevon estimated airframe package; an EDF/turbine estimate; pusher wash and wake.
```

### Packet 5 — helicopters recognised; donor adapters designed (2026-11-17)

```text
Done: params.gd defaults modelName to the ClearView body.ac for old flat dialects (v0-v4, mostly helicopters), with a
  note; setup.gd reads the receipt modelType and refuses helicopters (0) instead of estimating them as aeroplanes.
  Helicopter corpus (CVHeliPak1/2 + four MC Exceed Roboheli, 41 roots): 0 -> 37 import visually; 4 refuse
  (material limit, unsafe member path, render precision). Plane corpus unchanged at 122/132.
Probe evidence (WorkshopCompiler on stock donors): moonrunner_x99 (Skywalker X8: tailless, elevon, single_pusher)
  and sebart_avanti_s_a200 (turbine jet) compile only at scale 1.0 — the Workshop refuses scaling for the
  electric_prop and turbine families. xcell_60_research and hx700_electric_3d_experimental are helicopter-format
  records, not openrc-aircraft v2.
Design for the next packets (each a labelled, different configuration, never the ClearView flight model):
  1. Donor airframe for aircraft: definition member `donor {id}` (new definition/snapshot version with a
     compatibility table), a Creator `compile_donor` that re-identifies the exact stock record (no edits), and a
     placement whose unit_scale fits the visual to the donor span. Flying wings -> X8 (elevon bindings from the
     ClearView LElevon/RElevon frames); jets -> Avanti S (turbine, fuel, flaps, retracts). Trial identity pins the
     donor id and record hash; publication stays closed.
  2. Rotorcraft: a Creator helicopter trial that installs the existing helicopter session with a donor by size
     class (HX700 electric 3D or XCell 60) and binds the ClearView main/tail rotor render groups
     (`mainrotor.*` renderGroupName) to the rotor visuals.
  3. Scaling donors (physics owner): propeller and turbine scaling laws for the Workshop compiler, so donors can
     match each model's size instead of resizing the visual.
  4. Landscapes: CVLandPk1/2 hold 22 ClearView sceneries (landscape-params.txt). They need a landscape importer
     owned by the landscape track, not the aircraft importer.
```

### Packet 6 — donor flights: helicopters and flying wings (2026-11-17)

```text
Owner request: make the remaining imported models useful and flyable; labelled donor configurations accepted.
Helicopters (implemented by a helper, reviewed and re-verified by the lead): clearview/heli_donor.gd,
  helicopter_main.gd `creator_visual`, Creator offer "Fly as a helicopter (X-Cell .60 donor)", AppRoot
  donor trial. The ClearView model sits on the donor CG and skid plane; it is scaled only when its rotor is more
  than 1.5x off the donor rotor; physics bit-identical to the stock X-Cell route. Rotor geometry is static
  (disc/blade parts switch by rotor speed). test_creator_clearview_heli 37/0; real Roboheli flight at 1080p.
Flying wings: clearview/donor.gd chooses the stock MoonRunner X99 (Skywalker X8: tailless, elevons, electric
  pusher, 6S) for elevon models; Main `donor_visual` builds the imported appearance fitted to the 2.1 m donor span
  on the exact stock physics; the automatic setup offers it instead of refusing elevons; AppRoot routes
  `creator_donor` through the shared donor-trial lifecycle (tentative detach, rollback, Return to Workshop).
  Zagi (real app, 1080p) climbs on the X8 6S power at 118 fps; XF5U, Predator, TwinJet and Waterflyer
  (headless, 480 ticks) fly without faults. test_creator_clearview_donor 6/0; Creator, UI, language, Workshop
  integration and Main startup suites 0 failures.
Plane corpus: 122 estimated + 8 flying-wing donors = 130 of 132 roots fly (remaining: Kellett autogyro,
  Hindenburg airship). Helicopter corpus: 37 of 41 import and fly on the X-Cell donor.
Limits: donors fly their own mass, inertia and power; the imported model only changes appearance (stated
  in every confirmation). Elevon visuals are static; publication and Home are not available for donor trials.
Next: helicopter donor by size class (HX-700 electric); moving elevons/rotors bound to the donor's surfaces;
  Avanti S turbine donor for jets as an alternative to the pusher park-jet estimate; landscape importer.
```

### Packet 7 — robustness and realism audit (2026-11-17)

```text
Method: Good Enemy source review of the whole candidate (helper, source-read-only); an RC-physics realism
  review (helper, with sources); a mutation fuzz (540 runs: Yak 54, Zagi and Roboheli packages with corrupted
  numbers, deleted/duplicated lines, truncation, byte flips and 1e6/1e-6/0/-1 geometry scales through package ->
  convert -> setup -> compile, flying-wing donor and helicopter donor build); a handling sweep of all 122
  estimated corpus aircraft and six stock references through the real session loop (trim, level-trim speed
  envelope, 10 s hands-off, 10 s power-off, 6 s full throttle, full aileron and elevator pulses).
Fuzz: 0 script errors, 0 hangs, no accepted non-finite or absurd scale.
Robustness defects fixed:
  - apply_clearview_setup: a size fit that had not converged by the fifth attempt restored the empty draft
    and still reported success; the last attempt now keeps its state. A refused declaration now rolls back
    placement, values, inventory and the power package; an invalid typed span is no longer overwritten.
  - Donor wing flights: the CG used the stock X8 model datum, shifting the imported appearance; the stock
    shadow proxy, stock smoke, scenario binding and Companions treated the flight as a stock X8 flight.
  - Helicopter donor: the visual scale was unbounded (a degenerate rotor gave ~1e9) and a rotor-less model was
    shown unscaled; rotor-less models are now sized by their length and scales beyond 20x are refused.
  - Untyped flight payloads: the source is type-checked before use (AppRoot and HeliDonor.is_helicopter).
  - Omitted textures share the 16-image limit; _fit_estimates and the model-type reader guard non-finite input.
Realism (handling sweep, before this packet):
  - Span <1.3 m: 21 of 22 diverge hands-off within 10 s (bank 72-180 deg, 36-166 m lost); mid 1.3-1.9 m: 2/38;
    >=1.9 m: 0/62. Stock Stik 6S: bank 14 deg. Cause: the single 4S/800 kV/12x6 installation (~1 kg) makes
    small estimates 2-3x too dense (WL 5.1-7.6 kg/m2, relative density ~4.8 vs ~1.3), the opposite of real
    models (wing loading rises with size). Fix: the automatic setup no longer chooses a span under 1.6 m
    (Authoring.SETUP_MIN_SPAN_M); smaller models fly as a labelled larger version, and a long model grows only
    until its body is 1.85 m from the datum (Setup.MAX_REACH_M). After: of 34 small models re-flown, divergent
    hands-off 17 -> 2 (A-10, Beginair, Cessna: bank 72-83 deg diving -> 25-27 deg climbing); WL 3.8-5.6 kg/m2.
  - Every estimate shares one AR-5 rectangular wing, 20/20/25 deg throws and the same package: same-size
    models fly almost identically (2.16 m: roll 80-101 deg/s, Vmax 23-25 m/s vs stock Extra 300S 391 deg/s).
  - Gliders get trainer drag (L/D ~8); jets fly as 12x6 pusher park jets (Vmax 23-33 m/s); biplanes and
    twins get one wing and one nose/aft propeller. Flipper and Harrier keep a pitch-sensitive divergence
    (q ~190 deg/s) after resizing.
  - Donors fly their own mass and size: a 0.48 m Waterflyer is a 2.1 m X8, a 450-size heli an X-Cell .60.
Next realism batch, by pilot-visible impact: measured planform (trailing edge, taper) instead of the AR-5
  rectangle; a small power package (3S, ~9 in) and a large one (6S) chosen by size, then lower the 1.6 m
  floor; a fast jet pusher; category throws (aerobatic, glider) where the source gives a signal; Froude-
  scaled donors (small wing, small electric heli).
```

### Packet 8 — realism batch: measured planform, size classes, EDF stand-ins (2026-11-17)

```text
Owner request: fix the packet 7 realism findings. Supersedes the 1.6 m setup floor.
Planform: Setup.planform() cuts the wing at 0.3/0.45/0.6/0.75 of the half-span (edges, not vertices), takes the
  contiguous section at the leading edge's height, fits root/tip chord by least squares (outlier stations
  dropped; more than one disagreeing station keeps the template) and dihedral from the outboard stations;
  taper 0.62-1 and AR 4.2-6.8 are kept inside the airframe domain. A second wing layer at three or more
  stations 0.25-1.6 chords apart is a biplane: one equivalent wing of 1.7x one wing's area. Examples:
  Cessna AR 5.6 taper 0.81 dihedral 3.7; Yak 54 AR 4.4 dihedral 0; F-86 1.4 deg; Stearman/DR1/Pitts biplanes.
Size classes (Authoring.setup_classes): 0.7-1.45 m conventional-parkflyer-estimated-v1 (foam densities, 9 g
  servos; calibrated on EasyStar II, FMS Ranger 1220, Apprentice 15e, FMS P-51D 1100) with 3S 1250 kV 9x6
  (SunnySky X2212-10 winding data) or its pusher; 1.45-2.2 m the trainer with 4S 800 kV 12x6. Jets: 4S
  1900 kV 6x4.5 pusher (16 N static, 70 mm EDF class) and from 1.9 m 6S 1200 kV 7x5 (27.5 N, 90 mm class),
  both tuned with the runtime electric solver; T/W 0.52-0.85 on the corpus jets. Drafts store
  `airframe_package` only for the park-flyer class. Good Enemy review: 8 findings; fixed the empty class list,
  the -1 class index, the pusher hub past the tail, the overpowered first jet package (27 N), the canard case
  and the dialog line; planform cost measured at <=153 ms on the largest corpus model (10.6k triangles).
Handling sweep, 122 corpus aircraft, before (packet 7 baseline) -> after:
  <1.3 m (22): mass 1.47-2.20 -> 0.79-1.38 kg; WL 5.1-7.6 -> 2.8-5.0 kg/m2; stall ~9.2-10.8 -> 6.8-8.7 m/s;
    flown at their own size; violent departures (>60 m lost in 10 s hands-off) 15 -> 2 (MiG-15, VJ-101).
  1.3-1.9 m (37): violent 1 -> 0; >=1.9 m (63): 0 -> 0. No NaN or failed flight; 0 script errors.
  Remaining: 18 small and 3 mid models still bank past 45 deg within 10 s hands-off. Traces show a slow spiral
  (about 5 deg/s; stock Stik recovers via sideslip and dihedral, light low-dihedral foamies do not), consistent
  with their measured 0-3.7 deg dihedral and low mass; not a solver fault. Full-throttle hands-off roll-off on
  A-10, Yak 55, Harrier, VJ-101 VTOL, X-wing (prop torque on light airframes).
Limits: one borrowed nondimensional aero set (UltraStick25e) for every class; new propellers reuse the APC
  Sport 11x6 tables; EDF stand-ins have no duct, inlet or exhaust model; throws stay 20/20/25 deg.
Next: per-category throws/rates where the source gives a signal; Froude-scaled donors (small flying wing,
  small electric heli); a measured-chord tailplane.
```
