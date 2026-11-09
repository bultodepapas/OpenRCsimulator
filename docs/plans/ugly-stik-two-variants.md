# Ugly Stik: two selectable variants, unchanged basic reference

2026-11-08 · Revision 6 · **Status: software implementation complete with bounded verification. Two stock variants, compatibility/persistence, sourced estimated installation, model/Workshop/exported resources, final maneuver cards and scoped Linux native equivalence are implemented and checked. Required CI, broader native/performance, physical/pilot acceptance and the unrelated combined recorder draft retain their own gates.**

Owner: fixed-wing physics/aircraft data with NITRO, EL/BAT, AS, AE, AFC, UI, US and native-backend owners. Steps: **EL1e-STIK-00…08**, under EL1e aircraft integration. [Ownership registry](../README.md#tracks-plans-and-step-ids).

## Decision: preserve the basic aircraft

Keep exactly two **player-selectable stock Ugly Stiks**. The electric aircraft remains experimental; selection does not establish physical validation:

| Configuration | Canonical ID | Powertrain and role |
| --- | --- | --- |
| **Existing Ugly Stick basic / MAX-61FX reference** | **Keep `jensen-das-ugly-stik-60`** | Existing MAX-61FX/APC 12x6 representation, prescribed fuel and existing RPM law. Keep the application default, common test reference and 15 m/s airborne start. |
| **Ugly Stick · Electric 6S** | `stik-electric-6s` | Scorpion SII-4020-540KV, APC 12x8E, 6S 4000 mAh LiPo. Finite `pack_ecm` is the normal mode; qualify electrical behavior separately. |

The basic aircraft already names an O.S. MAX-61FX in its inventory. **Do not replace it with `stik-glow-61fx-2t`.** That experimental aircraft has finite fuel, a coupled shaft and a 20 m/s start. Keeping the engine name would not preserve its physics, state or compatibility.

Hide `stik-glow-61fx-2t`, `stik-glow-55ax-2t` and `stik-glow-fs64v-4t` from ordinary stock aircraft selection. Preserve their technical definitions, generated data, explicit developer/compatibility CLI routes and specialized tests. Two stock player choices does not mean deleting laboratory specimens, shared engine implementations or user-created documents.

This revision supersedes the previous proposal to retire the basic ID, switch tests to finite 61FX, migrate basic saves or replace its golden format. **No base-data rename, physics upgrade, default change, blanket test-reference replacement or golden re-recording belongs in this task.** Future promotion of finite glow would be a separate intentional physics change.

## Two-pass source review

Final implementation-planning inspection: `36d08d0e3a48f8867c65843b89a5632e2964d477`, initially clean. At final documentation checks, HEAD was `75299d6869f0b80f955574ddda8ba95f4b4915f4`; the intervening commit changed unrelated aero evidence, and concurrent performance edits remained unqualified. Earlier baseline review used `2465abc4b2def4cc9d6e3a175f4196a2b755236c`. Graph discovery was checked against current files because indexed ranges lag. This is static review, not an executed regression campaign; re-freeze actual sources and the test harness before implementation.

**Pass 1 — identity and dependencies:** 173 files under `app/tests` directly reference the basic ID/JSON path; 58 reference experimental glow IDs/paths. These are literal-match file counts, not executed tests or complete transitive coverage. Implicit default `FlightSession.setup()` calls add dependencies.

**Pass 2 — indirect regressions:** checked catalog enumeration/order, generated donors, golden admission, saved identities, Workshop, AFC, native receipts and battery-mode routing. Independent Good Enemy review challenged both the original proposal and the corrected policy.

| Observed dependency | Concrete risk | Required treatment |
| --- | --- | --- |
| [Catalog](../../app/app_state/aircraft_catalog.gd), [basic data](../../app/data/aircraft/jensen_ugly_stik_60.json) | Prescribed versus finite fuel, different startup speed and solver state. | Keep default, ID, path, physical bytes, capabilities, start and laws. |
| [Golden test](../../app/tests/test_golden.gd), [helper](../../app/tests/golden_flights.gd) | Default setup; golden v1 rejects coupled-shaft sessions. | Keep old goldens and tolerances; add separate electrical coupled coverage. |
| [Catalog test](../../app/tests/test_aircraft_catalog.gd) | Asserts 11 registered entries, 10 airplanes and ordered glow IDs. | Update only intentional membership/count expectations; preserve uniqueness, ordering, invalid-ID and physical assertions. |
| [UI test](../../app/tests/test_ui_aircraft.gd), [preserved choices](../../app/tests/test_ui_preserved_choices.gd) | Old navigation order; finite 61FX exercises fuel UI. | Verify visible navigation separately; retain finite-fuel UI coverage using supported Extra or an explicit fixture context. |
| [Spatial weather](../../app/tests/test_spatial_weather_session.gd) | Uses `airplane_flyable_ids()[0]`. | Keep basic first in both technical and visible lists; inspect other positional assumptions. |
| [Render adapter](../../app/render/airplane.gd) | Default `build()` and visual family use the basic ID. | Preserve default rendering/family; isolate electric equipment per instance. |
| [Glow generator](../../research/glow-engines/build_installations.py), [Extra](../../research/extra-300/ex05/derive_physics.py), [P-51](../../research/p51/p51-05/derive_physics.py), [Avanti](../../research/avanti-s/av06/derive_physics.py) | All read the basic JSON as a donor. | Do not move, edit or delete it; preserve existing generated outputs. |
| [Workshop](../AIRCRAFT-WORKSHOP.md), [store tests](../../app/tests/test_workshop_store.gd) | Different capability/pinning rules for base versus finite fuel. | Preserve basic transformations, controls and existing saves; no disabling them to accommodate electric. |
| [AFC loader](../../app/ai/companions/profile_loader.gd) | Pins basic ID, data hash and broader source fingerprint. | Keep basic profile; audit shared-code fingerprint changes separately. |
| [Atmosphere CLI](../../app/tests/test_atmosphere_column_cli.py), [glow trials](../../app/tests/test_glow_connected_trial.gd) | Explicit hidden IDs/data exercise different engine laws. | Keep exact fixture routing; never substitute basic physics. |
| [Native build](../../research/native-kernel/build.py), [fleet](../../research/native-kernel/fleet.gd), [native replay](../../app/tests/test_native_replay.gd), [contact tests](../../app/tests/test_contact_policy.gd) | Smaller enumerations silently lose cases; catalog source contributes to native identity. | Retain old technical case sets; add electric and requalify affected receipts. |
| [Battery selection](../../app/app_state/aircraft_catalog.gd), [BAT contract](battery-realism.md) | `data` means ideal and `battery_data` means pack; Workshop uses principal data. | Explicit mode routing and truthful labels; no finite-battery claim on an ideal test. |

Basic JSON SHA-256 at review: `5635e7f7b2a44bdfc7db5ad2646c74654af42944133bc39a91a0908bac887b66`. Capture a fresh implementation baseline including relevant dirty inputs. If another authorized track changes it, reconcile the change rather than reverting unrelated work or treating this snapshot as permanently authoritative.

## Preservation and visibility contracts

### Immutable baseline for this task

Preserve the basic ID/path/data bytes, `Catalog.DEFAULT_ID`, first-list position, state layout, integrator, fuel/RPM semantics, trim, start, controls, aerodynamics and contacts. Existing common tests continue to use the basic aircraft; a new shared test-fixture abstraction is unnecessary.

Preserve golden files/tolerances, basic Workshop features, AFC data pins, geometry, appearance, hinge names and paint compatibility. Check generated manifest dependency closures as well as physical JSON. If shared adapter edits necessarily change a source pin, regenerate it honestly and verify compatibility; do not retain a false hash.

The electric aircraft gets independent installation data and a separate `stik-electric-6s` visual family, reusing unchanged airframe geometry. Never mutate the basic geometry, shared materials or caches to hide glow equipment. Verify basic → electric → basic and concurrent instances. The registration strategy below prevents an unplanned rewrite of every legacy family manifest.

### Technical registry versus player selection

Use an additive visibility boundary. Keep `ENTRIES` as the literal technical registry and preserve lookup/enumeration semantics (`entry`, `has`, `ids`, `can_fly`, `step` and fleet lists). Do not convert entries to computed factories: the Workshop and economy generators parse the literal IDs and data paths. Technical validity does not imply a stock player choice.

Implemented catalog API:

| API / metadata | Contract |
| --- | --- |
| Optional `player_selectable = false` | Boolean field on the three hidden glow entries; omitted means true. Keep every technical entry and its physics/status. Electric starts false during integration. |
| `is_player_selectable(id)` | Resolve `canonical_id(id)`, reject unknown IDs, then read the explicit flag. Visibility is independent of PREVIEW/EXPERIMENTAL/FLYABLE status. |
| `player_entries()` / `player_ids()` | Stable filtering of technical order, returning canonical IDs; retain currently eligible previews and rotorcraft. No duplicate historical aliases. |
| `player_step(id, delta)` | Wrap within the visible list, preserving ordinary integer-step behavior. Canonicalize supported aliases; return an explicit invalid/empty result for hidden or unknown origins, not a silent substitute. |
| Workshop new-stock list | Filter player entries by the existing flyable-airplane capability; do not apply the filter to saved documents or descriptor generation. |

Append the electric technical entry after the three existing glow entries so their prior relative order stays intact. After hiding those three, the visible order begins basic → electric → Extra. Preserve the existing `skywalker-x8` → `moonrunner-x99` compatibility mapping; use canonical IDs for UI membership without changing historical document resolution.

Update Home lists (including direct `ENTRIES` iteration), keyboard arrows, counters, backdrop/preloading, programmatic selection and Workshop's new-stock picker. Validate the effective stored selection **before** the Home scene is constructed. Filtering a list alone is insufficient: existing `has(id)` still accepts hidden IDs and can restore them through preferences or `set_aircraft()`.

Preserve Natural Random v1's fixed five-aircraft list, seed-to-aircraft/conditions mapping, format and rejection rules; it already excludes the hidden glow entries. Do not auto-add the electric aircraft to seeded scenario pools. Its serialized build identity can change across commits; require exact reproduction under matching identity, not an identical scenario digest across builds. Likewise retain AFC's existing aircraft support; the electric entry has no companion support until independently qualified. These are outside this cutover, not implicit missing tests.

Keep validators, generators, native oracles and research tools on the full technical registry. Do not globally filter `airplane_flyable_ids()` and lose coverage.

For the inspected fleet, adding electric yields **12 registered configurations / 11 airplanes**; hiding three glow entries yields **9 stock player choices / 8 airplanes**, with exactly two visible Stiks. These counts assume no unrelated fleet additions. Tests should assert explicit expected sets/order against the implementation snapshot, not adopt permanent magic totals.

| Entry point | Required behavior |
| --- | --- |
| Fresh/default launch; existing basic preference | Same basic ID/data/default mode/start. No migration for basic users. |
| Saved stock selection for a hidden glow | Resolve to basic for the current Home session with a visible explanation; preserve the original stored ID until an explicit player selection/use is successfully saved. Never rewrite physical customizations. |
| Explicit known hidden-ID CLI | Preserve exact historical configuration for development/compatibility tests, labeled research-only in help/output. No basic alias and no promotion to a stock choice. |
| Unknown ID | Keep strict rejection. |
| Existing basic Workshop document/package | Continue loading unchanged under matching identities. |
| Existing hidden-glow Workshop document/package | Preserve loading, editing/export and validation through an explicit compatibility context; do not convert physics or offer it as a new stock base. User documents may remain in the library and are not extra stock configurations. |
| Old replay/checkpoint | Keep strict source/config/solver checks. Preserve original executable/source where necessary; unchanged JSON alone does not guarantee replay across builds. |
| Synthetic `--electric-demo` | Preserve existing fixture routing/tests; do not turn synthetic donor-mass fixtures into the sourced 6S aircraft. |

If that separation cannot preserve contracts, withhold the cutover and fix the boundary. Do not delete tests, loosen tolerances or redirect a finite-engine case to prescribed physics to get a green suite.

### Saved selection, automation and rollback

Keep preferences schema 6; no schema bump or new persistent migration format is needed. Store the original aircraft selection and effective Home selection separately in one session-owned resolution result. Loading must not write settings. Until the player explicitly selects a visible stock aircraft or presses Fly on the explained fallback, every unrelated save (language, weather, HUD, etc.) preserves the original aircraft value. Initialization/programmatic binding is not explicit selection. Put this rule at the common preference-save boundary, not in individual button handlers.

Show a localized, nonmodal notice naming the hidden configuration and explaining that existing builds and explicit technical launch still work. A log-only `preferences.note` is insufficient. Keep schema-future/read-only settings protected; on save failure retain original bytes and report failure while keeping a valid session selection. Restart is idempotent: no repeated destructive rewrite or accumulating backup files. Explicit selection commits only after successful persistence.

The current `Preferences.save_to()` ends in a direct `ConfigFile.save(path)`, which does not establish that failure guarantee. Before cutover, implement a bounded write transaction at that boundary: serialize to a unique sibling temporary file, close/reload and validate it, then publish through a replacement operation verified on supported platforms. Never truncate/remove the accepted file before replacement. If the platform requires a recoverable backup, retain at most one validated previous version, define startup recovery and remove it only after successful validation of the published file. Do not claim power-loss durability without evidence. Test write/validation/replacement failures and interrupted recovery in disposable profiles; persistence failure must not commit the session's original-ID marker. Keep this scoped to the existing preferences format, without a new general storage framework.

`AppRoot.set_aircraft()` and Home-driven start requests must reject hidden/unknown stock IDs before changing state. The [debug bridge](../../app/debug/debug_bridge.gd) must distinguish Home-selectable IDs from technical registry IDs in its catalog response. Prevalidate composed `setup`/`fly` arguments, check setter results, and return a faithful failure without starting the previous aircraft after rejection. Keep headless/direct CLI fixture routes separate and unchanged. Test rejection with all prior settings and active aircraft retained.

Rollback before explicit user choice leaves the original saved selection intact. Rollback after a successful choice preserves that deliberate choice; old builds may apply their existing unknown-ID behavior to electric, but must not erase the original user document. Disable/revert only this feature's visibility change if admission fails; keep generated historical fixtures and original evidence.

## Electric installation and battery modes

Implemented experimental candidate: **Scorpion SII-4020-540KV + APC 12x8E + Gens ace G-tech GEA406S60X9GT 6S 4000 mAh + Scorpion Tribunus III 06-80A**. The 13x8E/13x6.5E preliminary choices were revised after full-charge current/RPM screening. The [installation dossier](../../research/propulsion/stik-6s/README.md) owns the source points, conditional DC-equivalent fit, residual errors and operating limits; the [manufacturer-source record](../research/propulsion/ugly-stik-6s-selection-2026-11-08.md#pack-and-esc-reference-selected-during-final-planning-review) pins pack/ESC references. Fit, wiring, cooling, BEC setpoint, actual firmware behavior and electrical characterization remain physical acceptance inputs.

Generate a separate electric inventory from unchanged shared airframe inputs: motor, mount, adapter, ESC, battery, wires and restraints. Recompute mass, CG, inertia, rotor inertia and strike envelope. Remove glow engine/exhaust/tank from electric inventory and appearance. Reuse suitable licensed downloadable geometry/data; preserve stable `airplane`, `propeller`, `*_hinge` interfaces.

Follow the current battery contract: one electric ID with **ideal fixed-voltage `data`** and **finite `pack_ecm` `battery_data`**, generated consistently. Modes are not extra catalog aircraft. Fresh selection defaults to pack; an explicitly retained ideal preference stays visibly labeled ideal. Prove actual data routing for fresh profiles, inherited preferences, CLI, resets, checkpoints and HUD.

**Bounded first delivery: Workshop remains ideal-mode only for this electric aircraft**, following its existing main-data contract. Label the descriptor/editor/test-flight result as fixed-voltage with no depletion; Home/normal flight uses pack by default. Do not add a general Workshop battery selector or rewrite the bundle/recipe format in this task. Refuse any request that claims a finite-pack Workshop trial instead of silently downgrading it. Preserve all basic capabilities and Turbo Lumber behavior. Pack-mode Workshop editing is a separate AE/BAT feature, not a prerequisite for this stock aircraft.

Screening goals, not measured acceptance:

- Derive inventory, not artificial ballast. The original 3.0–3.4 kg screening aim is superseded by the estimated 2.600082 kg inventory after removing glow hardware, receiver pack, unused throttle servo and the donor's virtual balance fixture. Target at least 350 W/kg electrical input and 1.2 static thrust/weight under the declared nominal bench condition; source-point calculations and runtime predictions remain distinct.
- Assess current/voltage from fully charged 25.2 V through sag/depletion. Nominal 22.2 V is not constant, and nameplate ratings are not implemented motor/ESC protection.
- Verify minimum prop clearance in the declared normal taxi/takeoff/landing envelope, including suspension, pitch and terrain; check bay fit, retention and cooling.
- Use sourced in-flight `Ct/Cp` with correct provenance. Separate fitting, published-data checks and independent validation: one static point cannot satisfy all three.

Record a decision before stock exposure: the sourced/estimated installation must support the power and thrust targets and a declared electrical operating envelope. If 13x8E exceeds that envelope at full charge, assess the sourced 13x6.5E fallback with the same gates and regenerate the single electric installation. If neither passes, keep electric hidden and revise the installation; do not hide the failure with an unsupported throttle cap, invented ESC protection or nominal-voltage-only evidence. Hardware measurements remain a separate physical-validation gate, not a claim made by software admission.

Implementation decision: use sourced APC 12x8E instead. Its conditional numerical steady screen passes at 25.2 V and sampled axial speeds 0–30 m/s; it does **not** pass a hardware startup-current qualification. The estimated pack/ideal ESC produces an unprotected severe zero-speed/full-duty transient, and higher-speed propeller RPM, actual fit and thermal/firmware response remain unqualified. Preserve these limits in the dossier and experimental status; a steady-current check cannot close them.

Reuse the shared `VehicleModel`, float64 state, shaft and battery laws. Electrical coupled replay is additive; basic golden v1 remains untouched. The electric aircraft shares the exact donor wheel-profile key through a closed default-registry alias. The global wheel file and old basic Workshop dependency hashes remain byte-identical; explicit profile selections/custom registry paths retain their behavior and a missing aliased donor is refused. Electric propwash, motor/ESC thermal dynamics and current limiting are outside the current power-stage contract; keep experimental limits explicit. [Electric guide](../ELECTRIC-PROPULSION-PLAN.md), [battery guide](battery-realism.md), [aircraft contract](../AIRCRAFT_CONTRACT.md).

Implementation refinement: the lighter inventory requires two contact substeps at 240 Hz. The existing dynamic-battery whole-tick policy now owns that subdivision internally, retains the original one-piece route and samples the ESC supervisor once at the outer endpoint. `Simulation` and its policy/substep rejection remain unchanged. Do not lower gear stiffness or add fictitious mass. Check the installed callback identity before suppressing the kernel's substep request; cover piece boundaries, failure atomicity, ground replay and unchanged existing battery cases. Requalify the basic AFC source pin after this shared session-source change.

### Authoring outputs and identity boundary

The paths below are implemented additions. Keep one installation source and generate both energy modes from it; do not clone and independently tune two aircraft JSON files.

| Source / output | Required contract |
| --- | --- |
| `research/propulsion/stik-6s/installation.json` and `build_aircraft.py` | Source matrix for exact hardware, estimates, units and URLs/hashes; read the unchanged basic donor, replace installation inventory, recompute mass properties and reference offsets through existing helpers. Support deterministic regeneration and `--check`. |
| `app/data/aircraft/stik_electric_6s.json` and `app/data/aircraft/battery/stik_electric_6s_pack.json` | Both identify `stik-electric-6s`; same airframe, inventory, controls, start and propeller. Only declared energy/supervisor fields differ. Preserve stable inventory IDs, explicit modules and fail-closed v2 admission. |
| New BAT record, ID `lipo-6s1p-4000-gea406s60x9gt-est-v1` | Reuse the existing fitted cell template; add sourced mass/box and estimated electrical law with honest provenance. Exact pack hash and inventory mount mass must agree. Do not refit all cells or modify existing packs. |
| `assets/aircraft/stik-electric-6s/` authoring inputs and new electrical builder | Reuse unchanged common geometry; independently register equipment, physical rotor diameter, crash sections, paint and allowed smoke/audio behavior. No combustion source outlet or decorative throttle linkage on electric. |
| New model/customization overlay and Workshop descriptor | Dedicated visual family `stik-electric-6s`; no alias to the basic manifest. Physical and presentation proofs remain distinct; ideal-mode Workshop descriptor pins the actual ideal source. |
| Economy dossier through `research/crash-economics/aircraft-costing.json` / `build_runtime.py` | Include every technical ID, including the three hidden glow specimens and electric. Reuse established missing-price semantics; no fabricated quotes or inventory copied from glow. |

Do not label the BAT class curve or ideal ESC law as measured behavior of the selected brands. Copying the Turbo Lumber generator's wiring, cooling, LVC or Avian settings would carry incompatible assumptions: source or explicitly estimate each electrical installation field. Identify nominal motor specifications separately from sample-fit Kv/resistance, retain rotor inertia uncertainty and keep fit/held-out data separate.

### Model registration: resolve before catalog insertion

Adding a family to global `assets/aircraft/model-bindings.json` changes its source hash inside **every** legacy physical manifest. Avoid that path. Extend the existing separately registered [model overlay mechanism](../../app/aircraft/model_overlay_registry.gd) with an explicit closed mapping for MoonRunner and the new electric family. Its current one-file/one-family assumptions must be replaced by exact registered-set validation in runtime, generators, customization and export proof consumers. Do not enable arbitrary directory scanning, fallback to unverified models or relax hash validation.

Keep the basic global binding, builder, geometry, physical manifest and physical Workshop descriptor bytes unchanged. Build the new electrical presentation independently. The [overlay source proof](../../research/aircraft-standardization/build_overlay_proof.py) pins shared registry scripts, so a registry change can legitimately regenerate MoonRunner's proof/manifest/customization/descriptor chain. List that exact proof-only diff as an allowed exception, test MoonRunner's model and saved-record behavior, and reject any physical-data change. A source-proof refresh is not permission to silently rebase a user bundle: unchanged content must use an explicit verified compatibility rule, otherwise preserve original-source handling and disclose the boundary. If the existing saved-basic contract cannot be retained, withhold catalog insertion and revise the presentation seam.

Registration is atomic at the technical boundary: adding a hidden electric `ENTRIES` record must arrive with valid ideal/pack files, model/customization/descriptor proofs, audio/smoke capability handling and economy records. The economy loader compares its dossier IDs against all `Catalog.ids()`; an incomplete entry can break crash-cost lookup for the basic aircraft too. Keep stock visibility false until the full package is admitted.

Generation dependency order: selected pack → ideal/pack aircraft → overlay source proof → model manifests/package proofs → customization/presentation proofs → Workshop descriptors → economy/repair records → native source identity/receipts. Preserve existing LF/raw/CRLF rules and review generated diffs after each owner. Existing tools: `research/aircraft-standardization/build_overlay_proof.py`, `build_models.py`, `build_customization.py`, `research/aircraft-editor/build_descriptors.py`, `research/crash-economics/build_runtime.py`; use each supported `--check` and [authoritative generation workflow](../TOOLS.md#aircraft-workshop). Run the actual loader after freshness checks; generated bytes alone do not establish admission.

## Execution steps and ownership

No shared-kernel refactor, donor cleanup or finite-glow promotion belongs in this change. UI/catalog owners handle visibility; NITRO retains fixtures; EL/BAT own new data; AS/US own presentation; AE/AFC retain saved/profile boundaries. Regenerate affected records through their source pipelines.

| ID | Work | Proof / status |
| --- | --- | --- |
| EL1e-STIK-00 | Select the sourced motor/prop/pack/ESC candidate; review preservation and dependency policy. | Implemented selection: 12x8E replaced preliminary 13-inch candidates after full-charge screening. Conditional DC-equivalent fit and severe startup transient are disclosed in the installation dossier. |
| EL1e-STIK-01 | Freeze source/engine/dirty inputs, base data/goldens, dependency hashes, registry/case sets and known failures. | Basic data/model/descriptor hashes and golden bytes preserved. Four basic goldens pass before/after; nine retained companion tapes compare identically across accepted solver revisions. A separate current-build 6,428-sample log replays exactly; it is not a pre-change recording. |
| EL1e-STIK-02 | Add player APIs and route stock consumers through them, initially with all existing entries visible. Implement saved-selection resolution, safe persistence and atomic debug rejection. | Implemented additive player APIs, retained selection marker, bounded validated preference replacement/recovery, localized notice and all-or-nothing debug prevalidation. Schema 1/6/99 and three hidden IDs exercised without changing technical enumeration. |
| EL1e-STIK-03a | Add the 4000 mAh BAT record and deterministic ideal/pack installation generator. Keep drafts outside `app/` until valid. | Implemented deterministic 2.600082 kg ideal/pack inventory and sourced-mass BAT record. Thirty-two installation checks, low-SOC cutoff and bounded full-charge current/RPM screen pass. Actual fit, startup current and physical errors remain open; existing packs and donor stay unchanged. |
| EL1e-STIK-03b | Extend the closed overlay registry/generators and add independent electric presentation. | Implemented closed two-family overlay registration and independent electric equipment. Basic global manifest/descriptor bytes unchanged; audited MoonRunner proof chain regenerated. Saved stale MoonRunner documents remain readable and fail strict trial admission instead of rebasing. LF/CRLF fresh clones pass. |
| EL1e-STIK-03c | Atomically register the hidden electric package with its descriptor, source proofs, audio/smoke handling and economy dossier. | Implemented all twelve technical routes, electric descriptor/customization/source proofs and unpriced electric economy entry. Catalog, package, descriptor and economy admission checks pass. |
| EL1e-STIK-04 | Qualify lifecycle, visuals, ideal-only Workshop, compatibility and identities before exposure. | Implemented ideal/pack replay, low-SOC cutoff/reset, depleted-start refusal, applied donor-wheel alias, contact refinement/strike/reset and ideal-only Workshop refusal of pack claims. Six requested maneuver-card cases pass in each mode. Windows 1080p Home, flight and Workshop inspected. Bounded ground cases pass; physical/pilot qualification remains open. |
| EL1e-STIK-05 | In one cutover, show electric and hide the three glow stock choices; activate explained session fallback for affected saved selections. | Implemented atomic visibility cutover: basic → electric → Extra; exactly two stock Stiks, nine stock choices. All three glow IDs/data/CLI/saved compatibility contexts retained. Persistence failure keeps the original-ID marker. |
| EL1e-STIK-06 | Audit the checks already added with each slice; reconcile intentional set/order expectations. | Existing technical fleet, finite-fuel UI fixture coverage, Natural Random pool and AFC support retained; targeted catalog/UI/Workshop/debug/battery/log regressions pass. Broad runner includes new test files automatically. Final contact contract passes 1,563 checks; alias compatibility passes 15 and the two-mode missing-donor mutation fails closed. Final focused regressions are recorded in linked evidence; a whole-tree/CI pass is not claimed. |
| EL1e-STIK-07 | Verify stable integration, native receipts, performance and exports. | Actual exported PCK smoke passes 64 checks from an empty project with compiled overlay scripts and applied wheels. LF/CRLF clone regeneration passes. All 19 native oracle gates and nine scoped Linux native/reference start rows pass; the qualified library is installed through the unchanged guard. Four unchanged basic goldens and 4,387 log checks pass on the final alias. Required CI, broader fleet/weather, performance and physical gates remain separate. |
| EL1e-STIK-08 | Reconcile `GLOW-ENGINES.md`, `AIRCRAFT_CONTRACT.md`, Workshop/electric guides and debug/CLI help with implemented support. | Canonical Stik, electric, Workshop, aircraft, first-launch, tools and glow guides updated; technical fixture history retained. This plan remains active for the remaining qualification gates, linked to dated implementation evidence. |

Keep each step independently reviewable. Preparatory changes preserve existing behavior; do not ship the final transition before both visible aircraft and compatibility flows are admitted.

The critical path is **01 → 02 → 03a/03b → 03c → 04 → 05 → 06/07 → 08**. A branch may hold generated additions before registration, but every integrated commit must load the old fleet successfully. Keep the existing stock selection policy until the complete electric package passes admission. At cutover, flip all four visibility flags together; do not temporarily ship one or five visible Stiks. Maintain one writer per shared registry/generator file and isolate test profiles from the user's settings.

## Acceptance matrix and stop conditions

Use [existing tools](../tools/README.md), [physics/conformance checks](../tools/physics.md), [flight logging](../FLIGHT-LOGGING.md), [flight-test cards](../../research/flight-test/README.md), [BAT tools](../../research/battery/README.md) and [native qualification](../../research/native-kernel/README.md). Run focused checks while implementing, then required CI and broader coverage on the stable cross-cutting candidate. The [implementation evidence](../research/propulsion/ugly-stik-implementation-2026-11-08.md) records executed checks, exact identities and open gates; the earlier source review above remains historical.

Start from these existing checks, extending them where the failure mode is missing. Test files are under `app/tests/` unless a path is given. Run GDScript through the [checked runner](../tools/shared.md#one-godot-script); a zero engine exit alone is insufficient. This is a dependency map, not a command to rerun every group after every edit.

| Implementation slice | Focused verification |
| --- | --- |
| Visibility, preferences and automation | `test_aircraft_catalog.gd`, `test_ui_aircraft.gd`, `test_ui_preserved_choices.gd`, `test_ui_language.gd`, `test_ui_battery_mode.gd`, `test_debug_bridge.gd`, `test_debug_bridge_contracts.gd`; `tools/debug/test_debugctl.py` if its response contract changes. |
| Pack and electrical installation | BAT generator freshness; `test_battery_data.gd`, `test_battery_pack_ecm.gd`, `test_battery_session.gd`, `test_battery_esc_supervisor.gd`, `test_electric_session.gd`, `test_aircraft_ground_battery.gd`. Add new-ID cases, keeping existing Turbo Lumber cases. |
| Models and complete registration | Overlay/model/customization/descriptor/economy generator freshness; `test_aircraft_model_manifest.gd`, `test_aircraft_package_proofs.gd`, `test_moonrunner_overlay.gd`, `test_presentation_sources.gd`, `test_economy_catalog.gd`. |
| Workshop and saved content | `test_workshop_descriptor.gd`, `test_workshop_compiler.gd`, `test_workshop_store.gd`, `test_workshop_bundle.gd`, `test_workshop_trial.gd`, `test_workshop_presentation.gd`; basic, hidden glow and historical MoonRunner/Skywalker documents. |
| Physics, preserved fixtures and backend | Existing basic golden/trim/contact/log coverage; `test_glow_connected_trial.gd`, `test_atmosphere_column_cli.py`, `test_contact_policy.gd`, `test_native_replay.gd`, actual native fleet qualification. Retain baseline case identities. |

Required regression scenarios beyond list/count assertions:

- Cross old/current/future preferences schemas (including 1, 6 and unsupported 99) with basic, each hidden ID, electric, historical alias and unknown ID. Check accepted settings, localization, read-only files, unrelated saves, explicit selection/Fly, failures and restart; rejected requests retain all prior settings and the active aircraft.
- Check first/last wrap, negative/multiple steps, preview and rotorcraft entries, no duplicate aliases, and new-stock versus saved-library membership. Headless debug `setup`/`fly` must not partially apply valid fields before rejecting an invalid aircraft.
- In disposable copies, deliberately omit/corrupt electric pack data, descriptor/source proof or economy entry. Admission must fail visibly without substituting the basic model; a partially registered package must fail the integration gate. Do not weaken validation to make a hidden malformed entry harmless.
- Verify ideal/pack geometry, controls, inventory and mass properties agree; only the declared electrical mode differs. A Workshop ideal flight must never report pack depletion. Electric → basic → electric and concurrent instances must preserve equipment, paints, smoke/audio and scale.
- Freeze actual case rosters and generated diffs. Retain independent generator checks for existing donors, Natural Random v1 seed mapping and AFC basic pins; document legitimate build-identity changes separately from behavioral changes.

| Boundary | Required evidence |
| --- | --- |
| Basic physics | JSON bytes/hash, default/start/capabilities, golden bytes and tolerances unchanged. Existing golden, trim/aero/contact and log assertions pass; matched baseline comparison shows no unintended state/trajectory change. |
| Basic visuals/customization | Default Home/build, paints, hinges and Workshop saves/transformations work; switching and simultaneous instances show no cache/material leakage. |
| Shared generators | No unplanned changes to basic, Extra, P-51, Avanti, glow profiles or dependent records. New electric does not mutate donor. |
| Technical coverage | All old configuration/law cases remain, including finite 61FX, 55AX, FS64V and Extra. Compare enumerated IDs and admitted/skipped/refused/completed cases, not just pass totals. |
| Stock selection | Explicit visible set/wrap order; basic first/default; exactly two Stiks across every stock picker. Saved/programmatic selection cannot bypass visibility accidentally. |
| Persistence and automation | No write on preference load; unrelated saves retain hidden stored IDs. Transaction failures preserve accepted data or recover the validated prior file; no false success, partial debug setup or launch of a previous aircraft. |
| CLI/documents | Basic and explicit hidden-fixture paths retain identity/behavior; unknown IDs fail. Basic saves untouched; hidden documents preserve their distinct compatibility context. |
| Registration and proofs | Exact technical catalog/economy sets; old global physical manifest/descriptor bytes retained. Only declared overlay proof refreshes occur, with compatibility tests and actual exported-resource verification. |
| Electric lifecycle | Actual ideal/pack file selection; fresh/partly discharged/weak pack, sag, cutoff/recovery, depleted start, reset/checkpoint/replay, shaft/ground events and prop strike. |
| Source/native identity | Catalog changes can invalidate receipts despite unchanged base data. Regenerate and qualify affected identities; record executed backend and retain original builds for old logs. Fallback is not native parity. |
| Other consumers | Preserve Turbo Lumber battery behavior, finite-fuel UI coverage, basic AFC, failure scenarios, unrelated aircraft and non-airplane activities. |
| Export/performance | Fresh package contains pinned resources for both visible aircraft and retained compatibility paths. Freeze hardware/build/backend/workload/metrics and current [Gate P policy](../../research/performance/README.md); compare basic cost and separately qualify electric at 1920×1080. Higher resolutions follow, 720p last. A screenshot does not prove performance. |

**Stop and investigate** unexplained base/golden changes, failed old physics assertions, missing cases, unexpected skips, hidden-ID substitution, lost basic Workshop capability, false battery-mode labels, stale native receipts or source drift. Keep original data and evidence intact; withhold cutover or revert only this task's isolated patch. Do not revert concurrent work or re-record expectations just to pass.

Zero regression is an acceptance requirement, not a guarantee from static inspection. Distinguish exact replay under matching identity, same-condition comparisons across builds, software qualification and still-open physical/pilot validation.
