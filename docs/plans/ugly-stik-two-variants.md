# Ugly Stik: two selectable variants, unchanged basic reference

2026-11-08 · Revision 2 · **Status: planning only. Double review removed a behavior-changing baseline replacement. No runtime, aircraft data or test migration implemented.**

Owner: fixed-wing physics/aircraft data with NITRO, EL/BAT, AS, AE, AFC, UI, US and native-backend owners. Steps: **EL1e-STIK-00…08**, under EL1e aircraft integration. [Ownership registry](../README.md#tracks-plans-and-step-ids).

## Decision: preserve the basic aircraft

Keep exactly two **player-selectable stock Ugly Stiks**. The electric aircraft remains experimental; selection does not establish physical validation:

| Configuration | Canonical ID | Powertrain and role |
| --- | --- | --- |
| **Existing Ugly Stick basic / MAX-61FX reference** | **Keep `jensen-das-ugly-stik-60`** | Existing MAX-61FX/APC 12x6 representation, prescribed fuel and existing RPM law. Keep the application default, common test reference and 15 m/s airborne start. |
| **Ugly Stick · Electric 6S** | Proposed `stik-electric-6s` | Scorpion SII-4020-540KV, APC 13x8E, 6S 4000 mAh LiPo. Finite `pack_ecm` is the normal mode; qualify electrical behavior separately. |

The basic aircraft already names an O.S. MAX-61FX in its inventory. **Do not replace it with `stik-glow-61fx-2t`.** That experimental aircraft has finite fuel, a coupled shaft and a 20 m/s start. Keeping the engine name would not preserve its physics, state or compatibility.

Hide `stik-glow-61fx-2t`, `stik-glow-55ax-2t` and `stik-glow-fs64v-4t` from ordinary stock aircraft selection. Preserve their technical definitions, generated data, explicit developer/compatibility CLI routes and specialized tests. Two stock player choices does not mean deleting laboratory specimens, shared engine implementations or user-created documents.

This revision supersedes the previous proposal to retire the basic ID, switch tests to finite 61FX, migrate basic saves or replace its golden format. **No base-data rename, physics upgrade, default change, blanket test-reference replacement or golden re-recording belongs in this task.** Future promotion of finite glow would be a separate intentional physics change.

## Two-pass source review

Inspected snapshot: `2465abc4b2def4cc9d6e3a175f4196a2b755236c`, with concurrent unrelated changes. Graph discovery was checked against current files because indexed ranges lag. This is static review, not an executed regression campaign.

Closing source-drift check: HEAD advanced to `2e05ed08c7c4ffb2e3c83440756fba594015dec6`. The reviewed aircraft data, catalog, golden, render, AFC and generator sources were unchanged between those commits; unrelated debug/RCV work and `app/test.sh` changed. Re-freeze the actual test harness and case inventory at implementation; this review does not qualify the evolving whole tree.

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

The electric aircraft gets independent installation data and per-instance presentation. Use its own binding/manifest if needed. Never mutate the basic geometry, shared materials or caches to hide glow equipment. Verify basic → electric → basic and concurrent instances.

### Technical registry versus player selection

Prefer an additive visibility boundary. Keep existing registry lookup and technical enumeration contracts (`entry`, `has`, `ids`, `can_fly` and fleet lists). Add explicit player-selectability metadata/helpers and visible navigation, using existing naming conventions. Technical validity does not imply a stock player choice.

Update every product choice route: Home lists, keyboard arrows, counters, backdrop/preloading, programmatic selection, Workshop's new-stock picker and scenario/random stock choices. Validate/migrate stored selection **before** the Home scene is constructed. Filtering a list alone is insufficient: existing `has(id)` still accepts hidden IDs and can restore them through preferences or `set_aircraft()`.

Keep validators, generators, native oracles and research tools on the full technical registry. Do not globally filter `airplane_flyable_ids()` and lose coverage.

For the inspected fleet, adding electric yields **12 registered configurations / 11 airplanes**; hiding three glow entries yields **9 stock player choices / 8 airplanes**, with exactly two visible Stiks. These counts assume no unrelated fleet additions. Tests should assert explicit expected sets/order against the implementation snapshot, not adopt permanent magic totals.

| Entry point | Required behavior |
| --- | --- |
| Fresh/default launch; existing basic preference | Same basic ID/data/default mode/start. No migration for basic users. |
| Saved stock selection for a hidden glow | Narrow versioned selection migration to basic with a concise explanation and recovery information. Never rewrite physical customizations. |
| Explicit known hidden-ID CLI | Preserve exact historical configuration for development/compatibility tests, labeled research-only in help/output. No basic alias and no promotion to a stock choice. |
| Unknown ID | Keep strict rejection. |
| Existing basic Workshop document/package | Continue loading unchanged under matching identities. |
| Existing hidden-glow Workshop document/package | Preserve loading, editing/export and validation through an explicit compatibility context; do not convert physics or offer it as a new stock base. User documents may remain in the library and are not extra stock configurations. |
| Old replay/checkpoint | Keep strict source/config/solver checks. Preserve original executable/source where necessary; unchanged JSON alone does not guarantee replay across builds. |
| Synthetic `--electric-demo` | Preserve existing fixture routing/tests; do not turn synthetic donor-mass fixtures into the sourced 6S aircraft. |

If that separation cannot preserve contracts, withhold the cutover and fix the boundary. Do not delete tests, loosen tolerances or redirect a finite-engine case to prescribed physics to get a green suite.

## Electric installation and battery modes

Initial candidate: **Scorpion SII-4020-540KV + APC 13x8E + ordinary 6S 4000 mAh LiPo**, with an airplane ESC rated for 6S and at least 80 A. Pin pack/ESC SKU, revision, mass, dimensions and BEC during authoring. [Manufacturer-source comparison and open inputs](../research/propulsion/ugly-stik-6s-selection-2026-11-08.md).

Generate a separate electric inventory from unchanged shared airframe inputs: motor, mount, adapter, ESC, battery, wires and restraints. Recompute mass, CG, inertia, rotor inertia and strike envelope. Remove glow engine/exhaust/tank from electric inventory and appearance. Reuse suitable licensed downloadable geometry/data; preserve stable `airplane`, `propeller`, `*_hinge` interfaces.

Follow the current battery contract: one electric ID with **ideal fixed-voltage `data`** and **finite `pack_ecm` `battery_data`**, generated consistently. Modes are not extra catalog aircraft. Fresh selection defaults to pack; an explicitly retained ideal preference stays visibly labeled ideal. Prove actual data routing for fresh profiles, inherited preferences, CLI, resets, checkpoints and HUD.

Workshop currently uses the principal data path. Before enabling electric test flight, carry the accepted mode through shared Workshop/admission contracts. If unsupported, refuse that electrical operation clearly; never advertise a finite LiPo flight and run an ideal bus silently. Preserve all basic capabilities and Turbo Lumber battery behavior.

Screening goals, not measured acceptance:

- Aim initially for 3.0–3.4 kg ready to fly; derive inventory, not artificial ballast. Target at least 350 W/kg electrical input and 1.2 static thrust/weight under the declared nominal bench condition.
- Assess current/voltage from fully charged 25.2 V through sag/depletion. Nominal 22.2 V is not constant, and nameplate ratings are not implemented motor/ESC protection.
- Verify minimum prop clearance in the declared normal taxi/takeoff/landing envelope, including suspension, pitch and terrain; check bay fit, retention and cooling.
- Use sourced in-flight `Ct/Cp` with correct provenance. Separate fitting, published-data checks and independent validation: one static point cannot satisfy all three.

Reuse the shared `VehicleModel`, float64 state, shaft and battery laws. Electrical coupled replay is additive; basic golden v1 remains untouched. Electric propwash, motor/ESC thermal dynamics and current limiting are outside the current power-stage contract; keep experimental limits explicit. [Electric guide](../ELECTRIC-PROPULSION-PLAN.md), [battery guide](battery-realism.md), [aircraft contract](../AIRCRAFT_CONTRACT.md).

## Execution steps and ownership

No shared-kernel refactor, donor cleanup or finite-glow promotion belongs in this change. UI/catalog owners handle visibility; NITRO retains fixtures; EL/BAT own new data; AS/US own presentation; AE/AFC retain saved/profile boundaries. Regenerate affected records through their source pipelines.

| ID | Work | Proof / status |
| --- | --- | --- |
| EL1e-STIK-00 | Select the electric candidate; review baseline-preservation policy. | Research and two-pass source review complete; no runtime qualification. |
| EL1e-STIK-01 | Freeze source/engine/dirty inputs, base data/goldens, dependency hashes, registry/case sets and known failures. | Pending: reproducible baseline, exact baseline log replay under matching identity, implicit-default and donor inventory. |
| EL1e-STIK-02 | Add technical-versus-visible selection with no initial visibility change. | Pending: old defaults, lists, navigation and behavior preserved; tests separate registry and product contracts. |
| EL1e-STIK-03 | Generate standalone electrical installation, pack and presentation. | Pending: valid production admission, source freshness, fit/current/inventory evidence, explicit ideal/pack paths; existing generated outputs unchanged. |
| EL1e-STIK-04 | Qualify electric lifecycle, visuals, Workshop, compatibility and identities before exposure. | Pending: coupled replay, pack events, complete flows and declared physical limits; inspect at 1080p first. Basic/other aircraft unchanged. |
| EL1e-STIK-05 | Offer electric and hide three experimental glow stock choices; migrate only affected saved selections. | Pending: exactly two visible Stiks, basic first/default; technical IDs/CLI/data retain original physics. |
| EL1e-STIK-06 | Update intentional selection/count expectations and add electrical/compatibility tests. | Pending: old physical assertions/tolerances retained; before/after case-set comparison proves no silent coverage loss. Verification accompanies each implementation step, not only this audit. |
| EL1e-STIK-07 | Verify stable integration, native receipts, performance and exports. | Pending: required CI, justified broad integration gate, fresh-checkout/package checks, actual-backend proof and unchanged-basic evidence. |
| EL1e-STIK-08 | Consolidate guides and support-versus-fixture distinctions. | Pending: no stale finite-61FX-default claim, no unwanted stock choices or deleted donors; preserve useful history and owner-held physical/pilot gates. |

Keep each step independently reviewable. Preparatory changes preserve existing behavior; do not ship the final transition before both visible aircraft and compatibility flows are admitted.

## Acceptance matrix and stop conditions

Use [existing tools](../tools/README.md), [physics/conformance checks](../tools/physics.md), [flight logging](../FLIGHT-LOGGING.md), [flight-test cards](../../research/flight-test/README.md), [BAT tools](../../research/battery/README.md) and [native qualification](../../research/native-kernel/README.md). Run focused checks while implementing, then required CI and broader coverage on the stable cross-cutting candidate. **No runtime suite was run for this document-only review.**

| Boundary | Required evidence |
| --- | --- |
| Basic physics | JSON bytes/hash, default/start/capabilities, golden bytes and tolerances unchanged. Existing golden, trim/aero/contact and log assertions pass; matched baseline comparison shows no unintended state/trajectory change. |
| Basic visuals/customization | Default Home/build, paints, hinges and Workshop saves/transformations work; switching and simultaneous instances show no cache/material leakage. |
| Shared generators | No unplanned changes to basic, Extra, P-51, Avanti, glow profiles or dependent records. New electric does not mutate donor. |
| Technical coverage | All old configuration/law cases remain, including finite 61FX, 55AX, FS64V and Extra. Compare enumerated IDs and admitted/skipped/refused/completed cases, not just pass totals. |
| Stock selection | Explicit visible set/wrap order; basic first/default; exactly two Stiks across every stock picker. Saved/programmatic selection cannot bypass visibility accidentally. |
| CLI/documents | Basic and explicit hidden-fixture paths retain identity/behavior; unknown IDs fail. Basic saves untouched; hidden documents preserve their distinct compatibility context. |
| Electric lifecycle | Actual ideal/pack file selection; fresh/partly discharged/weak pack, sag, cutoff/recovery, depleted start, reset/checkpoint/replay, shaft/ground events and prop strike. |
| Source/native identity | Catalog changes can invalidate receipts despite unchanged base data. Regenerate and qualify affected identities; record executed backend and retain original builds for old logs. Fallback is not native parity. |
| Other consumers | Preserve Turbo Lumber battery behavior, finite-fuel UI coverage, basic AFC, failure scenarios, unrelated aircraft and non-airplane activities. |
| Export/performance | Fresh package contains pinned resources for both visible aircraft and retained compatibility paths. Freeze hardware/build/backend/workload/metrics and current [Gate P policy](../../research/performance/README.md); compare basic cost and separately qualify electric at 1920×1080. Higher resolutions follow, 720p last. A screenshot does not prove performance. |

**Stop and investigate** unexplained base/golden changes, failed old physics assertions, missing cases, unexpected skips, hidden-ID substitution, lost basic Workshop capability, false battery-mode labels, stale native receipts or source drift. Keep original data and evidence intact; withhold cutover or revert only this task's isolated patch. Do not revert concurrent work or re-record expectations just to pass.

Zero regression is an acceptance requirement, not a guarantee from static inspection. Distinguish exact replay under matching identity, same-condition comparisons across builds, software qualification and still-open physical/pilot validation.
