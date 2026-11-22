# OpenRC Simulator — vehicle and repository system unification audit

| Review identity | Value |
| --- | --- |
| Date | 2026-11-22 (America/Bogota) |
| Repository | `bultodepapas/OpenRCsimulator` |
| Audited main | `7940a4081e10994f34c858c4acac3d7a1a271464` (v0.3.3 preparation) |
| Application tree | `fe6fdf080899707fab1a1dd4118a32481bca5e4c` |
| Scope | Source audit and implementation recommendations for all vehicle families, followed by repository-wide runtime/UI, tools/CI, generation and legacy-boundary review. No production implementation, new runtime qualification or performance measurement. |

## 1. Executive decision

**Continuation:** [section 8](#8-repository-wide-continuation-findings-beyond-vehicle-coordination) adds twelve repository-wide findings; [section 9](#9-what-to-retain-what-can-retire-and-how-to-organize-it) classifies retirement/retention; [section 10](#10-recommended-next-implementation-sequence) orders the proposed changes. Sections 1–7 preserve the first vehicle-focused pass.

**Unify mechanisms with the same contract; keep vehicle laws and operational policies with their current owners.** OpenRC already has the important shared foundation: every family installs a `VehicleModel` into `Simulation`. The next investment should remove repeated coordination around that foundation, especially route selection, controller ownership, launch handoff, environment preparation, recording transport and presentation-resource lifetime. A universal vehicle superclass would turn existing differences into a growing collection of conditional branches. The current model boundary is a better foundation. [Shared architecture][architecture] [Model contract][vehicle-model]

This audit finds concrete duplication, rather than inferring it from similar method names. It also finds two control-flow problems that illustrate the maintenance cost of parallel ownership: an airship CLI request with another argument can fall through to the aircraft route; the ground activity's local controller registry does not inherit the separately selected Home menu role. Both are source-derived findings, not observations from a rendered session or physical controller. The latter also has a test that injects the missing local role, so that test does not establish the real Home-to-car handoff. Sections 4.1 and 4.2 trace the complete paths.

Recommended structural priorities are:

1. Give route recognition and each controller role one authority, repairing incorrect behavior in separate changes.
2. Extract the duplicated ORFL packet writer and the pure lake/collision checks, with two real consumers each.
3. Factor the common Home activity handoff for ground, blimp and quad after characterizing cancellation and rollback.
4. Consolidate controller candidate selection inside the existing service, retaining family recovery rules.
5. Extract repeated lens-resource lifetime mechanics when that removes a demonstrated maintenance burden.

Do not start with wholesale directory moves, a new simulation engine, a universal session, a universal checkpoint, or a universal battery/powertrain law. This review does not promise an FPS increase. Its immediate objective is fewer independent implementations of the same responsibility and fewer places to repair the same defect.

## 2. Relationship to existing work and evidence

The [existing VRC plan][prior-plan] and [migration matrix][prior-matrix] are already published on `audit/game-controls-2026-11-21`, pinned here at `3095afd95220232e8e659d53635acab5104ee94c`. Their runtime baseline is `57abea025f62b20233ca281d58d2acbee4ab8b8e`; they describe proposed work, not an implemented common API. This report refines that work against the newer main snapshot. It does not create a second master plan or mark VRC-00 through VRC-11 complete.

The controls plan's fixed-wing PauseMenu characterization remains its first controls slice. The packet and pure-environment extractions below are independent candidates under the existing VRC boundaries, not a reason to delay controls repairs. The prior five GCA findings and 40 acceptance cases are not rerun or closed here. Before moving their affected seams, reconcile their status and execute the appropriate existing witnesses. The [pending external audit ledger][audit-ledger] and completed ledger were reviewed to avoid treating old repaired findings as new defects.

Three bounded research helpers examined simulation/session boundaries, activity/presentation coordination, and input/catalog ownership. The lead checked the material source paths and integrated the recommendations; a separate adversarial review checked the integrated design and consequential findings. No engine, device, rendered, native-parity, package or full-CI campaign was run for this audit.

The initial readable checkout was the one-commit documentation-only child `8245859b3392eb08eea0d56dc07de0d834a12b5b`. Its `app` tree was verified identical to audited main. A fresh isolated checkout of `7940a408` was then used for inventory and final source checks. All source links below are pinned to audited main, not a moving branch.

### Measured source inventory

These are UTF-8 `splitlines()` counts, not complexity scores, removable-line estimates or performance measurements. The [machine-readable inventory](vehicle-system-unification-2026-11-22-source-inventory.json) includes all 16 inspected coordinator/recorder files, blob identities and the duplicate-scan method.

| Current owner | Lines | Top-level functions | Interpretation |
| --- | ---: | ---: | --- |
| `app/sim/flight_session.gd` | 6,697 | 339 | Broad fixed-wing coordination; isolate responsibilities incrementally |
| `app/app_root.gd` | 5,372 | 242 | Shell, routes, controller integration and transitions |
| `app/main.gd` | 4,303 | 151 | Fixed-wing presentation and activity coordination |
| `app/sim/ground_vehicle/session.gd` | 2,261 | 127 | Ground-specific run, recording, recovery and checkpoint ownership |
| `app/vehicles/multirotor/multirotor_scene.gd` | 1,663 | 94 | Quad activity, input recovery, presentation and race integration |
| `app/sim/helicopter_flight_session.gd` | 1,444 | 80 | Rotorcraft session and native/control admission |
| `app/vehicles/ground/ground_scene.gd` | 1,317 | 63 | Garage, driving, presentation and departure decisions |
| `app/sim/multirotor/session.gd` | 1,213 | 56 | Closed-loop plant, controller/race frame and accepted events |
| `app/vehicles/airship/airship_scene.gd` | 923 | 47 | Airship activity, controls, presentation and recording |

A bounded scan of those 16 files compared top-level functions after removing blank/comment-only lines, expanding tabs and trimming trailing whitespace. It did not rename identifiers or infer semantic equivalence. Four groups of at least eight retained lines were identical between airship and quad:

| Function | Airship | Multirotor | Retained lines per copy |
| --- | --- | --- | ---: |
| `_write_packet` | `sim/airship/flight_log.gd:187` | `sim/multirotor/flight_log.gd:212` | 18 |
| `_install_lake` | `sim/airship/session.gd:322` | `sim/multirotor/session.gd:366` | 15 |
| `_clearance` | `sim/airship/session.gd:502` | `sim/multirotor/session.gd:994` | 14 |
| `_failed` | `sim/airship/flight_log.gd:214` | `sim/multirotor/flight_log.gd:240` | 11 |

These exact matches establish specific extraction candidates. They are not the project's total duplication count. The larger launch and presentation routines contain common sequences mixed with real differences, so their full line counts must not be presented as duplicated or removable code.

## 3. What to share and what to preserve

| System | Shared responsibility | Responsibility that remains specific |
| --- | --- | --- |
| Simulation | Existing accepted-tick transaction, clock, state publication, model protocol and rollback | Each model's forces, state layout, events, sampling and integration policy |
| Controls | Device identity, profile storage, candidate ranking and shared input transport through existing owners | Throttle/collective/steering meaning, shaping, arm/hold/rearm and recovery |
| Launch | Route-family recognition and, where equivalent, Home handoff/rollback mechanics | Family argument validation, start configuration, prepared session and flight admission |
| Environment | Pure normalized-data checks and equivalent weather/surface construction | Weather domains, query timing, contact response, water behavior and native eligibility |
| Collision | Same-arithmetic proxy distance and shared world validation | Broad phase, candidate order, hull/rotor witnesses, contact timing and damage |
| Recording | Packet framing, digest chain, bounds, file-error handling and storage primitives | Record layout, checkpoint, accepted-event timing, replay and departure policy |
| Presentation | Resource construction/retirement and detached common observations | Cameras, HUD layout, rotor/propeller animation, audio meaning and effect events |
| Energy | Existing qualified primitives where their mathematical domain matches | Airship power demand, quad coupled bus, fixed-wing supply, nitro/glow and fuel laws |
| Data/catalog | Existing `VehicleRoster` projection backed by family catalogs | Family schemas, authored provenance, validation and admission |
| Tests | Common contract cases for the exact extracted mechanism | Family numerical, replay, recovery, device and physical qualification |

The existing [environment][environment], [controller service][controller-service], [recording transport][fixed-log-writer], [lens stack][lens-stack] and [model interface][vehicle-model] are the starting owners. Create a helper only when an existing owner cannot absorb the responsibility cleanly. A common name such as `resume`, `reset` or `checkpoint` is insufficient evidence of an interchangeable contract.

## 4. Findings and bounded remedies

The U identifiers below belong to this report. They are not a replacement implementation track. “High” means prioritize correctness or remove a consequential migration ambiguity; “medium” means a useful structural improvement. It is not a security severity scale.

### U01 — High: recognize requested vehicle routes before generic flight fallback

**Evidence.** `AppRoot._ready` recognizes the airship route only when the entire argument array has exactly one element. With `--airship=historico --quick-flight`, that branch is skipped, the quad recognizer reports no quad request, the unknown-ground-vehicle check does not match, and `wants_direct_flight` accepts any nonempty arguments. The call reaches `start_flight`; the aircraft parser stores arbitrary argument keys rather than rejecting the airship selector. By contrast, the quad recognizer explicitly rejects an additional argument. [AppRoot dispatch][route-dispatch] [Generic direct route][direct-route] [Aircraft parser][aircraft-args] [Quad route checks][quad-route-test]

**Consequence.** Source control flow permits a requested airship invocation to take the fixed-wing route. This is not a rendered reproduction, and no claim is made about the resulting visible flight on a particular installation.

**Remedy.** Add one route-recognition/refusal boundary in AppRoot or a small app-state helper. Recognize an explicit family selector independently of whether its arguments are valid; then delegate validation to that family's existing parser/catalog. Conflicting family selectors or an unsupported combination must produce a family-specific refusal before generic aircraft fallback. Keep direct-launch and Home preference semantics unchanged. Do not invent one global argument schema or automatically add options a family does not support.

**Acceptance.** Exercise a valid airship invocation, airship plus another option, malformed/unknown family IDs, duplicate selectors, conflicting families, both argument orders, valid aircraft technical arguments, no-argument Home and diagnostic routes. Preserve the higher-precedence input-report route and characterize the current `--airship=` empty-value fallback before changing it. Not every extra flag reaches fixed-wing: diagnostics and other recognized family selectors have earlier paths, and an explicit rotorcraft aircraft selector can choose helicopter. Include the production startup dispatch, not only a helper's returned dictionary. Extend `test_airship_activity.gd` or the appropriate startup check; retain `test_mr_activity.gd` direct-route cases.

### U02 — High: the ground activity duplicates menu-role authority and drops the selected Home menu pad

**Evidence.** Ground activity saves the supplied registry as `_source_controller_registry`, creates a new local registry, copies device observations, and selects only its local `flight` role. Its button acceptance checks local `ui` or `flight`, while GUI navigation is assigned to the local driving pad. AppRoot's UI-role callback calls the activity's refresh without forwarding the selected ID, and its ordinary controller event route exits while this activity slot is occupied. These paths do not supply the missing menu-role handoff. [Local registry and navigation][ground-registry] [Button acceptance][ground-button] [Shell UI callback][shell-ui-role] [Shell dispatch exclusion][shell-controller-exclusion]

`test_controller_car.gd` selects a menu pad in the source registry, launches the activity, and then manually selects that pad again in the activity's local registry before asserting that it can resume. The injected local assignment bypasses the production handoff being evaluated. The test also explicitly expects the driving pad to own garage navigation; preserve that distinction until an intentional product-policy change is specified. [Existing test][ground-role-test]

**Remedy.** Keep the garage's local driving selection and its neutral/reselection safety. Give the Home-selected menu role one authority: read it from the source registry or forward a detached role identity and its connection generation through the existing callback. Preserve the intended menu Start/Menu behavior separately from driving shortcuts. Decide explicitly whether separate-pad GUI navigation is supported; do not silently change the tested driving-pad navigation policy while repairing role propagation. Do not make the garage mutate the global aircraft flight role.

**Acceptance.** Launch through Home with distinct driving and menu pads, with no post-launch test injection. Check both pads' permitted Start/Menu actions, driving-only shortcut exclusion, UI-role changes, eligibility/revocation, disconnect/reconnect generation, loss of the driving pad, held buttons through garage transitions and Home restoration. The documented separate-pad Back action needs its own witness: copying a `ui` ID alone will not make `event.is_action_pressed("ui_cancel")` true while native GUI mapping still belongs to the driving pad. Route that action under an explicitly admitted owner; a connected raw device is insufficient evidence of menu eligibility. Use `test_controller_car.gd` and `test_controller_ground.gd` as starting points; synthetic success does not qualify physical devices. [Ground control guide][ground-controls]

### U03 — Medium: controller fallback ranking is copied and has a weaker consistency boundary

**Evidence.** `ControllerService` ranks saved-profile match, radio, known gamepad and other device under an outer store lease. Quad `_adopt_fallback_device` independently reproduces that priority and the ambiguous-Jeti rule, calling `match_profile` per device without a coherent outer lease. A failed store read is represented as no matches by the current store API. Selection can therefore be made from incomplete or separately read evidence. The subsequent managed profile resolution still fails closed: an empty profile does not grant a ready built-in pad mapping. This finding is about ownership and consistency, not evidence of unsafe flight. [Service selection][selection-service] [Quad copy][quad-fallback] [Store read and matching][store-matching] [Fail-closed connection][quad-profile-refusal]

**Remedy.** Put candidate ranking in the existing service, with one coherent observed-device/profile snapshot and an explicit busy/unknown result. Let the quad retain its lost-device exclusion, explicit keyboard choice, held state, confirmation and rearm decisions. Support its direct/standalone route deliberately; do not create a mandatory global singleton or duplicate persistent cache. Individual candidate reads already acquire leases; the missing boundary is one consistent ranking operation. Decide busy/corrupt-store behavior as an intentional owning-policy repair, separately from a behavior-preserving extraction.

**Acceptance.** Retain priority and ambiguity checks in `test_controller_auto_defaults.gd`, and activity fallback/keyboard checks in `test_mr_activity.gd`. Add store-busy/interleaved-profile-change, equal-priority, selected-device generation and reconnect cases. A helper selecting a device must not independently arm, resume or write profiles.

### U04 — Medium: three Home activity launches repeat one handoff transaction

**Evidence.** `start_ground_vehicle`, `start_airship` and `start_multirotor` repeat the Home preparation drain, post-await guard, activity exclusivity check, Home detach, candidate construction, startup check, successful publication, and failure restoration. Family configuration and controller injection differ. The three ranges contain 188 source lines in total; that includes distinct logic and is not a removable-line estimate. All three also occupy a variable named `ground_vehicle`, although two are airborne activities. [Launch sequences][activity-launches]

**Remedy.** First isolate the common handoff inside AppRoot, with family candidate construction/configuration and success hooks kept at the existing callers. A small private helper may be enough. If a separate class proves useful, it should own only this shell transaction. Preserve the current order: await Home preparation, revalidate the live origin, then capture the departing Home and construct the candidate. Retain those exact objects through commit/rollback and retire the failed candidate completely. Do not move candidate creation before the existing await or fold the more elaborate staged fixed-wing/helicopter loader into this initial change. Rename the misleading slot only in a later mechanical change after auditing callers; naming alone is not the structural fix.

**Acceptance.** Successful launches and failed construction/startup for each of the three activities; Home camera/focus restoration; duplicate launch while preparation drains; quit or screen change during the await; no orphan scene, signal or worker; direct-launch error behavior; returning Home after the activity. Use `test_airship_activity.gd`, `test_mr_activity.gd`, ground activity tests and existing Home-preparation tests.

### U05 — Medium: share lake and collision validation without sharing collision response

**Evidence.** Airship and quad `_install_lake` functions are identical after the bounded normalization described above. They check normalized geometry and its recomputed identity, detach the accepted lake, and remove an empty option. Related substantive checks appear in the fixed-wing and helicopter owners. The airship and quad capsule/oriented-box `_clearance` functions are also identical. Several sessions call the same private collision-world header/proxy validators in their own loops. [Airship lake and world checks][airship-lake] [Quad lake checks][quad-lake] [Airship clearance][airship-clearance] [Quad clearance][quad-clearance]

**Remedy.** Extend the existing lake/collision owners with pure normalized validation and same-arithmetic geometry queries. Return a detached checked candidate; each session decides when to install it and whether installation closes observers or invalidates readiness/native preparation. In particular, `_install_lake` currently mutates `env` and removes a key from `opts`; it must not be advertised as a pure function merely because its text matches. Preserve validation order, alias/deep-copy behavior and that canonicalization effect explicitly at the caller boundary. The existing collision header/proxy checks are structural; they do not recompute the whole world identity or prove spatial-bin coherence. Stricter integrity admission would be separate behavior work. [Existing collision checks][collision-validation]

Keep family broad phases, candidate order, witness geometry, water response and event timing. Airship records a boundary on a changed world after tick zero; quad also rebuilds its plant collision callbacks; helicopter has its own readiness/native effects. Empty-world handling and fixed-wing damage behavior are not automatically equivalent. [Airship world installation][airship-lake] [Quad world installation][quad-world]

**Acceptance.** Dry/empty data, malformed geometry, forged identity, detached-copy mutation, accepted/refused in-flight installation, boundary points and rotated boxes/capsules. Preserve float64 operation order, signed zero, proxy order and tie behavior. Retain `test_airship_collision_recording.gd`, `test_mr_fast_paths.gd`, `test_helicopter_lake_context.gd` and affected session checks. A new function call inside a collision hot path has unmeasured cost; measure it before claiming an optimization.

### U06 — Medium: share only the overlapping environment-preparation domain

**Evidence.** Airship and quad independently build the same default steady-wind configuration, construct a wind law, load/build the surface table and validate it before assembling `SimEnvironment`. The existing environment abstraction already supplies common providers and an adapter for ground courses. Airship admits up to 4 m/s; quad admits up to 8 m/s and has additional option/course handling. Fixed-wing supports broader weather and transactional pending selection; helicopter and ground have different admitted domains. [Airship preparation][airship-prepare] [Quad preparation][quad-prepare] [Existing environment][environment]

The scene layer also repeats field/lake/sky/night setup. Here failure policy already differs: ground rejects a lake-resolution error but tolerates an obstacle warning; airship/quad can warn and use no lake but reject obstacle setup. That is policy to characterize, not erase by selecting whichever implementation looks shorter. [Ground field preparation][ground-field] [Airship field preparation][airship-field] [Quad field preparation][quad-field]

**Remedy.** Prefer two small boundaries: pure simulation preparation for the actual common weather/surface subset, and a detached presentation configuration builder if it removes repeat work. Callers retain admissible bounds, error policy, course overlays, start and native gates. Do not introduce one policy-heavy `VehicleEnvironmentManager`, substitute steady wind for richer laws, or impose the quad's specialized terrain fast path on other vehicles.

**Acceptance.** Exact dry/calm baseline, different wind limits, invalid surfaces, lake/course overlays, deterministic environment identity and refused changes. Exercise `test_sf_environment.gd`, `test_airship_session.gd`, `test_mr_session.gd`, `test_heli_weather_admission.gd` and affected field/activity tests. Keep visual lighting independent of physical weather.

### U07 — Medium, strong first extraction: one ORFL packet transport, separate family recordings

**Evidence.** Fixed-wing, airship and quad write the same packet structure: serialized payload, bounded size, digest, file writes/flush, error checks and chained digest. Airship/quad `_write_packet` and `_failed` are exact matches under the scan; both already import the fixed-wing `flight_log.gd` for magic, hashing and packet reads. The common container exists, but writer ownership remains copied and the dependency points at a family-named recorder. [Fixed-wing writer and reader][fixed-log-writer] [Airship writer][airship-log-writer] [Quad writer][quad-log-writer]

**Remedy.** Extract a small packet I/O owner beside the existing logging code, preserving its framing, size/error contract and hash chain. Start with the two identical writers. Retain existing public recorder facades; migrate fixed-wing after checking its caller contract. Do not centralize session subscriptions or invent a common record row as part of this change. Shared transport may provide a bounded error result; each recorder still owns how to close its subscriptions and report incomplete capture.

Airship records clean sticks and body/continuous state. Quad carries a full controller/plant checkpoint, pilot frames, auxiliary/mode arrays, kernel events and race variants; replay reruns its controller. Fixed-wing has its own backend, intervention and closing-context logic. The helicopter's manual trace and car's CSV/JSON export are separate recording products. They already reuse some storage primitives and should not be converted merely to make the directory uniform. [Airship header][airship-log-header] [Quad header][quad-log-header] [Manual trace save][manual-save] [Ground export][ground-export]

**Acceptance.** Preserve byte framing and reader compatibility with existing fixtures. Exercise corrupted/truncated packets, bad digest, missing/inconsistent footer, row/event-only streams, packet/file limits, write/flush failures and stop reentry. Then run the real family recorder/replay consumers: `test_flight_log.gd`, `test_airship_flight_log.gd`, `test_mr_flight_log.gd`, relevant input and collision-recording cases. Existing fixtures and matching-source exact replay remain the baseline; changed source identity needs the documented comparison route.

### U08 — High migration constraint: reset, finalization and replay verdicts differ

**Evidence.** Fixed-wing uses explicit prepared-reset and commit receipts, with rejected preparation distinguished from a committed observer fault. Airship `prepare` assigns candidate session/model/environment state and then calls `reset`; `resetting` can be emitted before the kernel rejects reset. A nonfinite `heading_deg` is an unexecuted counterexample candidate: preparation does not validate it before quaternion construction. This needs a focused regression; it is not a claim of observed player data loss. Quad and ground have additional checkpoint, race/outbox, run-validity and recovery contracts. [Airship preparation/reset][airship-prepare] [Kernel prepared reset][prepared-reset] [Fixed-wing transaction][fixed-reset]

There is also a finalization question: airship/quad `_stop_recording` discard the `Error` from `flight_log.stop`, and their Home action can continue. The log reports incomplete writes, while the shell's guarded manual-recorder departure protocol is not automatically supplied for these logs. A fault-injected footer/flush test is needed to establish the user-visible outcome and decide the appropriate recovery. Do not assume that the ground trace's retry/discard policy applies to an already failed ORFL stream. [Airship stop wrapper][airship-stop] [Quad stop wrapper][quad-stop] [Shell departure][departure]

**Confirmed source-level replay divergence.** Airship `verify` computes `solver_changed` but can subsequently set both `exact` and `ok` true after all state/outcome comparisons, without refusing that flag. Quad explicitly refuses a changed solver in exact mode. The airship CLI uses `report.ok` for successful exit, and its guide tells the consumer to inspect `solver_changed`; changed-law candidate comparison is not implemented for the blimp. A common verifier that treats `ok` or `exact` alone as a matching-identity replay would therefore misread current results. This is a statically verified acceptance-contract difference, not a replay executed during this audit. [Airship verdict][airship-replay] [Airship CLI][airship-replay-cli] [Quad verdict][quad-replay] [Blimp logging guide][blimp-logging]

**Remedy.** Before moving a transition, record its full prepare/refuse/commit/fault/cancel behavior and observer timing. Repair an incorrect owning contract in a separate change. Reuse the kernel's existing prepared-reset capability where appropriate; retain family envelopes. Share mechanical subscription retirement only after proving the owner is finally retired. A temporarily detached Home/flight or a failed save is not permission for unconditional cleanup.

**Acceptance.** Failed prepare/reset/restore during recording; unchanged or deliberately changed model/environment/frame/tape identities; exactly ordered observer signals; postcommit faults; repeated close/stop; save failure; pending race results; accepted restore with correct credit policy. Add an airship negative control in which the source fingerprint changes while the recorded numerical trajectory still matches; the acceptance consumer must not call that matching-identity exact replay. Repair any desired CLI/verifier semantic change separately from packet extraction. Start with `test_flight_reset_transaction.gd`, `test_airship_flight_log.gd`, `test_mr_session.gd`, `test_race_session_replay.gd` and ground recovery/recording checks. These scenarios are proposed, not newly executed evidence.

### U09 — Medium: factor lens-resource lifetime, preserve presentation policy

**Evidence.** Five activities repeat removal/free of an old lens stack, settings resolution, construction/addition, configuration and failure cleanup. `LensStack` and `LensSettings` are already shared. The repeated construction is the remaining candidate, while contacts, reset subscriptions and event attribution differ. [Fixed-wing lens][plane-lens] [Helicopter lens][heli-lens] [Airship lens][airship-lens] [Ground lens][ground-lens] [Quad lens][quad-lens]

**Remedy.** Use a small owner for constructing/replacing/retiring a configured stack, or extend an existing presentation owner. Family scenes retain the events and context they supply. Do not combine all cameras, HUDs and effects into a universal presentation controller. Fixed-wing/heli use actual wind and simulation time in their world updates; the newer activities currently use a 37-second visual offset and zero render wind. Workshop also saves/restores shared world context. Those existing choices must stay explicit until separately changed. [World context][world-context] [Workshop restoration][workshop-world]

**Acceptance.** Repeated settings changes, reset, scene departure, unsupported settings and Workshop return; no duplicate callbacks or leaked stacks; expected camera/HUD and world clock behavior at the required display target. Use `test_lens_effects.gd`, `test_world_environment_lifetime.gd` and affected activity/presentation tests. Sharing a constructor does not qualify a rendered result.

### U10 — Medium/low: strengthen the existing roster; defer low-payoff helpers

**Catalogs.** `VehicleRoster` already provides the Home projection over aircraft and specialized family catalogs; extend that existing owner instead of creating another registry or descriptor system. Its activity table repeats installed IDs as literals. Its validator checks collision with aircraft IDs and listed-entry installation, but does not detect duplicate activity IDs; reverse coverage currently checks ground IDs only. No current duplicate entry was found. Use authoritative family constants where available, retain deliberate Home order/copy, and add negative duplicate/unknown-family/missing-player-entry cases to `test_home_vehicle_roster.gd`. If a ground ID lacks a named constant, add one at its owner or retain the validated literal; do not depend on a numeric position in `GroundCatalog.IDS`. Do not automatically expose every technical model in Home, repeat capability admission in the roster, or force all physical data into the aircraft v2 schema. [Existing roster][vehicle-roster] [Roster tests][roster-tests] [Prior ownership decisions][prior-matrix]

**Quantity readers.** Several family loaders repeat finite-number and `{value, unit, kind, source}` envelope checks, but allowed kinds, source rules, closed/open fields and legacy compatibility differ. A common primitive is optional after explicit accepted/refused-domain comparisons; a single vehicle schema is not recommended. Existing loaders retain unit interpretation, physical ranges, cross-field rules and derived quantities. This is a lower-priority opportunity than the actual routing and ownership gaps. [Airship quantities][airship-quantities] [Quad quantities][quad-quantities]

**Audio.** Airship and quad both duplicate a WAV resource before enabling looping and building positional players. A tiny asset/player helper could centralize that resource-safety pattern. Their motor count, spatial placement, accepted-tick mechanics and damaged-prop sounds remain separate. This is lower priority than route, role and recording ownership. [Airship audio][airship-audio] [Quad audio][quad-audio]

**OCV interpolation.** Airship, quad and fixed-wing supply contain similar piecewise SOC/voltage lookup, but the tables have different voltage units and endpoint policies. The quad's prepared-data domain does not impose every endpoint requirement of its file loader. Even returning an exact endpoint rather than recomputing it can change float64 bits. Defer consolidation unless independent boundary/parity and hot-path evidence justify it. Keep each coupled supply law. [Airship lookup][airship-ocv] [Quad lookup][quad-ocv] [Fixed-wing lookup][plane-ocv]

## 5. Architecture and code organization

The target is a set of narrow owners around the existing model boundary. These boxes are responsibilities, not a request to create one class for every box.

```mermaid
flowchart TD
    Shell["AppRoot and UI"] --> Routes["Route recognition and launch handoff"]
    Routes --> Activities["Family activities"]
    Input["Existing controller authorities"] --> Activities
    Activities --> Sessions["Family sessions"]
    Sessions --> Kernel["VehicleModel and Simulation"]
    Sessions --> Preparation["Shared pure preparation and geometry"]
    Activities --> Presentation["Shared presentation resource owners"]
    Sessions --> Records["Family recording adapters"]
    Records --> Packets["Shared packet and storage mechanisms"]
```

| Location | Responsibility after a justified extraction | Excluded responsibility |
| --- | --- | --- |
| `app/app_root.gd`, optionally a small `app/app_state/` helper | Shell transition and requested route recognition | Vehicle dynamics, cached readiness or universal session reset |
| Existing `app/input/controller_service.gd` and store/registry/profile owners | Coherent device/profile selection, persistence and role facts | Family arm/hold/recovery policy |
| Existing lake/environment/collision modules | Detached validation, common-subset preparation, pure geometry | Mutable session lifecycle or collision aftermath |
| Small helper beside existing logging code | Bounded ORFL packet I/O | Universal row schema, replay or departure decisions |
| Existing render/lens owners | Stack resource lifetime | One camera/HUD for every vehicle or authority over physics |
| Family session/activity modules | Explicit adapters, starts, controls, recovery and specialized presentation | Reimplementing a shared mechanism without a documented difference |

Keep the first extraction close to its current owner. Preserve existing public functions, resource paths and UIDs where practical. Establish two real consumers and remove the replaced implementation in the same bounded change. Do not keep a permanent old/new pair or publish a generic API with no actual second use.

Splitting `FlightSession` or `AppRoot` should follow an identified responsibility, such as packet transport or launch handoff. Moving 6,697 lines into several files without reducing ownership or dependency complexity would not meet this audit's objective. No wholesale relocation into new `core`, `managers` or `systems` directories is proposed.

### Physics and native boundaries that must survive

The fixed 240 Hz outer clock, float64 state and atomic accepted-tick protocol remain shared. This does **not** mean every family's complete state uses an identical RK4 procedure: ground nitro's existing whole-tick policy uses a midpoint engine/fuel update and the ground vehicle RK4 body step. Quad samples its controller once per tick and carries controller memory in the accepted checkpointed frame. Preserve these policies and their identities. [Ground integration callback][ground-tick] [Nitro composite step][nitro-step] [Quad sampled controller][quad-controller]

Qualified C++ evaluators and the selectable GDScript reference are deliberate implementations with distinct verification roles. Native acceleration replaces declared model evaluation callbacks while Simulation retains the transaction. Keep that architecture. A source-only consolidation audit supplies no reason to rewrite UI, orchestration or file I/O in C++, and no reason to delete reference laws or collapse independent test oracles. [Native policy][native-policy]

## 6. Reviewable work sequence and acceptance

Relative effort below is a planning assessment: small means a bounded owner or helper; medium means several lifecycle consumers. It is not a schedule or a measured cost estimate. Every proposed row remains unimplemented and its new acceptance cases unrun.

| Slice | Deliverable | Existing VRC/owner alignment | Proof before adoption |
| --- | --- | --- | --- |
| A: correctness | Repair U01 route refusal and U02 menu-role handoff in separate changes | UI/BL/RCV/D6; VRC-00 characterization and affected VRC-03/05 seams | Production-path regressions; no mixed structural migration |
| B: small | Shared ORFL packet writer with airship and quad first | FL; VRC-07 mechanical storage/observer boundary | Packet fixture/error tests and real recorder consumers; preserve family lifetime |
| C: small | Shared normalized lake checks, then same-arithmetic proxy primitive | LU/SC/GP/SF; VRC-06 | Equivalent accepted/refused inputs and numerical/collision boundaries |
| D: medium | Common-subset weather/surface preparation | M5/GP/SF and family owners; VRC-06 | Preserve caller bounds, identity, overlays and failure behavior |
| E: medium | Private shell handoff helper for the three newer activities | UI/RCV/BL/DR; VRC-01/05/07 as scoped | Await cancellation, success/failure restoration and retirement witnesses |
| F: medium | Coherent controller candidate selection in existing service | D6/DR/UI; VRC-03 and prior controls defect dependencies | Busy/unknown results, role/generation and first accepted command |
| G: small/medium | Lens resource-lifetime simplification | UI/render; VRC-08 | Subscription/resource checks plus actual rendered acceptance |
| H: conditional | Rename the activity slot, refine module boundaries and update owning docs | VRC-10 | References, scene resources, UIDs, package/import and dependency checks |

The existing controls plan remains the authority for its fixed-wing-first migration. Independent pure helpers may proceed when their own contracts are known; they do not require completing all optional work. Conversely, a repaired routing defect does not prove that reset, recording or native seams are safe to migrate.

For each structural slice, separate the behavior-preserving extraction from bug fixes, tuning, caching and format changes. Characterize the actual caller first, execute the extracted mechanism and its real consumers, and broaden validation only for the affected contracts or required CI. A test that constructs a corrected internal state after launch, as in U02, is insufficient evidence of production wiring.

### Identity, regression and performance rules

The source replay fingerprint traverses GDScript files under `physics`, `sim` and `failures`, plus selected additional sources. Moving or adding a helper in those directories can change the fingerprint even when accepted numerical behavior should remain the same. Do not suppress or falsify that identity change. Keep a matching-source/backend/engine baseline and preserve existing identity refusals where enforced. Use the supported fixed-wing/quad candidate workflows with their declared limits and applicable native parity/selection and package checks. For airship exact acceptance, require `complete && identity_match && exact && !solver_changed` as well as matching execution identity; `ok` or CLI exit zero alone is insufficient. A changed-source blimp comparison needs a separately defined family tape experiment: its public changed-law candidate mode is not implemented. The stricter acceptance requirement is not a claim that every current verifier already enforces it. [Fingerprint implementation][source-identity] [Flight logging workflow][flight-logging] [Airship divergence][airship-replay]

Meaningful contract cases include:

- The same accepted commands, state bytes, event order, tick and random-state behavior where the existing contract requires exactness.
- Refusal preserves precisely what the owning contract promises; a committed observer fault is reported as committed, not rollback.
- Exactly one owner for active device roles and subscriptions; stale activity/device generations cannot authorize actions.
- Storage failures remain visible and incomplete recordings never become complete/exact claims.
- World/Workshop clocks and detached rendering values do not feed back into physics.
- The extracted mechanism is actually used by both intended consumers, and the old duplicated code is removed.

For hot collision or physics helpers, measure the complete affected production workload on the target host before claiming a performance improvement. Fewer lines, fewer methods or an added cache do not establish lower CPU time, less memory, lower latency or higher FPS. A cold preparation helper and a per-stage callback have different cost profiles.

## 7. Completion criteria and audit limits

The future consolidation is successful when a fix to one shared mechanism reaches all adopted families through one implementation, while family-specific controls, trajectories, checkpoints and user recovery remain correct. A new vehicle should compose the existing kernel, transport and presentation facilities, then supply its own model, admitted data, controls and specialized behavior. It should not need another copy of route detection, packet writing or device ranking.

This audit completed source inspection, prior-plan reconciliation, a bounded reproducible inventory/duplicate scan, lead verification and adversarial review. It does not certify all source files or every path in this large repository. Findings about the route and role wiring are statically traced; the airship failed-prepare and finalization-error scenarios require execution before being described as reproduced incidents. The attached inventory is source evidence, not a test pass report.

No runtime repair, physics tuning, engine change, schema migration, golden regeneration or benchmark is delivered with this report. Proposed test names are starting points and do not mean their full new scenario coverage exists. Hardware, pilot, physical accuracy, package and full-CI qualification remain separate. The report and inventory are the only substantive deliverables; the audit ledger receives a discovery link without rewriting historical statuses.

## 8. Repository-wide continuation: findings beyond vehicle coordination

This continuation answers the request to scrutinize the whole repository. It retains the same main revision and extends the investigation to settings and startup, Creator and Workshop, UI diagnostics, developer tools, native qualification, source generation and legacy dependencies. Three additional research helpers inspected runtime consolidation, tools/CI, and retirement boundaries; the lead checked consequential source paths and requested an independent challenge. R identifiers below are local findings, not a new implementation track or a count of reproduced bugs.

### Coverage and what the measurements mean

The Git tree inventory covers **52,543 tracked entries on audited main**. The application scan inspected **839 tracked GDScript files outside app/tests and app/assets**, containing **369,946 splitlines() lines and 14,122 top-level function declarations**. It found **27 exact normalized-function groups**, including the four groups already reported in section 2. Signatures are retained; only blank/comment-only lines, trailing whitespace and tab expansion are normalized; the minimum is eight retained lines. The extended [source inventory](vehicle-system-unification-2026-11-22-source-inventory.json) records scope, identities and matches.

This is a whole-tree inventory and a broad application scan, followed by targeted source tracing. It is not a manual review of all 52,543 files, a full Python/C++/JavaScript clone scan, a call graph, or a removable-line estimate. The largest GDScript files include generated geometry: f4u_corsair_geometry.gd has 27,152 lines and avanti_s_blender_geometry.gd has 16,927, both with zero top-level function declarations under this scan. Their size does not establish a coordinator design problem. Exact wrappers can also call different implementations; matching text alone does not justify extraction. [Corsair geometry][r-corsair-geometry] [Vantage geometry][r-avanti-geometry]

### R01 — High: make successful settings publication mean verified publication

**Evidence.** DisplayPreferences.save_to builds a ConfigFile and directly returns its save result. DisplayPreferences.save then updates its accepted in-memory configuration on OK, and SettingsScreen.keep_changes publishes presentation_committed on the same result. RendererGuard.save_state already performs a complete readback comparison for the short-write failure described in its source comment. PreferencesFile has a more extensive leased, verified temporary/previous/current transaction. These owners currently provide different guarantees for an operation the UI treats as committed. [Display file write][r-display-file-write] [Display publication][r-display-write] [Settings acceptance][r-settings-keep] [Guard verification][r-guard-write] [Preferences transaction][r-preferences-file]

**Consequence and limit.** A false-OK or incomplete publication is a concrete fault-injection target at the display boundary. No full-disk or interrupted-write incident was reproduced here, and no claim is made that existing normal saves fail.

**Consolidation.** First characterize and repair verified publication within DisplayPreferences. Extract a shared write/readback primitive only after two real owners demonstrate the same transport contract; ConfigFile semantics and Workshop's byte-oriented records are not automatically equivalent. A helper can validate temporary bytes or decoded contents and report publication failure; it must not silently become a universal settings store. Display keeps its schema, future-version refusal, GPU-default ownership and trial Keep/Revert behavior. PreferencesFile keeps its accepted-state lease, weather witness and recovery rules. Statistics keeps its generation/journal protocol; Workshop keeps immutable records and manifests.

The duplication also extends to Workshop library preferences and drafts: both write/flush/verify temporary bytes and publish through their own transaction. Race records have a recoverable previous book, whereas PreferencesFile's previous copy marks an unacknowledged transaction. These are useful consumers for small byte-I/O primitives, not interchangeable recovery policies. [Library preferences][r-library-write] [Draft publication][r-draft-write] [Race records][r-race-write]

Telemetry consent is a decisive counterexample to universal backup recovery: its separate store deliberately has no restorable previous grant, and disabling first attempts to remove the earlier grant. Reusing a generic “restore last good settings” policy would conflict with that intention. This is not a guarantee that every current filesystem failure preserves opt-out: the initial removal result is ignored, so simultaneous removal and new-write failure needs its own consent-persistence investigation. A helper cannot promise durable revocation when every persistent write/removal is refused. Share only a mechanism whose contract actually matches. [Consent contract][r-consent-store]

**Acceptance.** Exercise short/truncated write, failed readback, destination removal/rename failure, corrupt or future-schema input, two writers where supported, and Keep/Revert with failed persistence. The UI must retain the appropriate draft/baseline and must not emit a successful commit for failed publication. Start with test_display_preferences.gd, test_settings_ui.gd, test_renderer_guard.gd and test_renderer_preference.gd, plus targeted injected failures. Consent tests must prove that backup recovery cannot resurrect an earlier enabled choice; separately start with an enabled grant and inject simultaneous removal and new-write failure, distinguishing current-session shutdown, the reported save error and the next-launch outcome. These are proposed checks, not results of this audit or a claim of power-loss durability.

### R02 — Medium: give startup a lightweight, transaction-aware presentation view

**Evidence.** Startup.read_presentation intentionally avoids the large Preferences preload graph, but reads settings.cfg and its display companion directly and repeats UI-scale validation. Normal Preferences.load_from obtains the PreferencesFile lease and performs recovery. If a supported current file and verified previous file remain from interrupted publication with no lingering lock, the intro can read the current language before the shell restores the previously accepted language. With a lingering lock, the shell instead fails closed; it does not automatically recover. [Intro reader][r-startup-reader] [Normal preference load][r-preferences-load] [Recovery rules][r-preferences-file]

**Consolidation.** Introduce a small read-only presentation projection at the existing app-state boundary. Reuse the display scale predicate and characterize the store's transaction states without loading aircraft/weather/presentation construction into the intro. Keep startup read-only; normal recovery remains with the store. Busy, corrupt and future-version inputs need explicit outcomes rather than a second independently maintained recovery algorithm. Recovery failure can leave normal Preferences reading valid fields from the current file with writable=false; it does not always select previous/default. A lock-existence check is not a snapshot protocol: a writer can intervene between reads, and preferences may legitimately change before Home loads. Define supported stable-state behavior and a safe best-effort fallback; promise cross-handoff equality only if an actual snapshot/lease protocol establishes it.

**Acceptance.** Compare intro and Home presentation under the defined stable-state contract for normal EN/ES settings, absent settings, interrupted current-plus-previous publication, held/stale lock, corrupt previous/current files, future schemas, reduced motion and every admitted UI-scale increment. Add deterministic writer interleavings and explicit best-effort outcomes. Preserve direct/headless startup behavior and verify that intro reads do not write or migrate player data. Extend startup/preferences/display tests; the mismatch is statically derived, not rendered evidence.

### R03 — High: finish adopting the checked engine runner in visual tools

**Evidence.** The required scenario phase in app/capture.sh calls tools/scenery/scenario.sh. That wrapper discards every engine/Xvfb/timeout exit with “|| true”, then accepts a completion marker unless its narrower line-start ERROR/SCRIPT ERROR expression matches. Scenery capture/budget and world parity/time wrappers contain variants of the same pattern. By contrast, tools/godot/run_checked.py already combines process exit, timeout, bounded logs, required markers, ANSI-normalized/indented SCRIPT and SHADER diagnostics, and admission integration. [Capture-suite caller][r-capture-caller] [Scenario wrapper][r-scenario-wrapper] [Scenery wrapper][r-scenery-wrapper] [World wrapper][r-world-wrapper] [Checked runner][r-checked-runner]

**Consequence and limit.** An engine that prints the marker and then exits nonzero, times out, or produces a diagnostic missed by that expression can pass the wrapper's engine-verdict step. Subsequent image/report checks can still fail independently. This is a source-derived conditional gap, not a reproduced successful CI run containing engine errors.

**Consolidation.** Migrate one wrapper at a time to the existing checked mechanism inside an admitted visual-capture owner. Preserve Xvfb/process-tree ownership, checked exit status, each marker, expected output files, image/synchronization checks, previous/latest/history behavior and the declared resolution/renderer. Do not add another generic launch framework or use this cleanup to change image baselines. This is not a universal drop-in shell replacement: without inherited admission, the focused enrolled-host adapter requires the worker's exact engine executable, rejects an Xvfb wrapper as the command and rejects application arguments after “--”. Route the whole capture through the appropriate reviewed admission path; never weaken it just to reuse the runner. [Focused admission boundary][r-checked-admission]

**Acceptance.** Use fake-engine fixtures for nonzero-after-marker, timeout-after-marker, missing marker, ANSI/indented/shader errors and successful execution; retain real scenario/image gates on an appropriate admitted host. Existing historical budget/version refusals must survive. CI-09's separate visual-skip issue is not closed by this change.

### R04 — High: consolidate cancellation around bounded ownership of unfinished import work

**Evidence.** AircraftCreator.cancel_import invalidates the generation, requests cancellation, puts the job into a static abandoned-job collection and returns the screen to an available state. The ordinary STL/GLB worker path calls read_bounded and inspect_bytes without consulting that cancellation token. A new import blocks abandoned non-ordinary package jobs but admits another ordinary job. A slow ordinary import can therefore remain alive while repeated Cancel → choose again creates further unfinished tasks. The Choose button is disabled during inspection, so an ordinary double-click is not the claimed UI sequence. [Creator worker/admission][r-creator-jobs] [Cancel and retirement][r-creator-cancel] [Choose eligibility][r-creator-choose]

Source bytes are capped per import; that is not an aggregate bound on active/abandoned work, decoded meshes or observations. The source demonstrates a missing owner-level bound, not a measured memory leak or OOM. Reaping completed jobs and rejecting stale results already work as explicit mechanisms and should be preserved. The Phoenix plan already calls for aggregate reservations and bounded work; this extends that invariant to the current ordinary route. [Import bounds][r-import-limits] [Existing import plan][r-phoenix-plan]

**Consolidation.** Reuse the ownership principle already visible in HomePreviewResources: one active operation, a bounded latest pending intent, and complete retirement of obsolete work before reuse. Keep this owner local to Creator initially, but bound work across Creator instances and every submission route. An _start_import-only guard is insufficient: saved-source _begin_open and ClearView conversion also call _start_task. Put admission at or before all submissions, preserving saved bytes, opening edit baselines and package-phase ownership. Add cooperative cancellation where the parser can support it, or drain a noncancelable operation before starting its replacement. Preserve generation checks even after introducing bounds. [Saved-source submission][r-creator-open] [Conversion submission][r-creator-convert]

A common policy does not make the worker implementations interchangeable: ResourceLoader jobs, private geometry jobs, Creator parsers and the flight scene loader have different completion/resource rules. Do not put them behind a universal JobManager merely to share method names. [Home bounded admission][r-home-resource-owner]

**Acceptance.** Inject a slow ordinary worker and repeatedly cancel/reselect; assert bounded admitted jobs and reserved bytes, newest-intent adoption, no stale publication, closing/reopening and saved-source re-admission without dangling UI references, complete reap/join, and mixed open/import/package-job coexistence. Measure memory and responsiveness separately if claiming an optimization. Existing Creator asynchronous import and Home preparation checks are starting points.

### R05 — Medium, concrete retirement: remove superseded controller UI nodes after moving their real consumers

**Evidence.** Controller setup creates four invisible ProgressBars with an explicit comment saying gimbals superseded them and tests still read them. Each preview update writes both the conditioned sample and those bars. A layout test even checks the hidden throttle bar's rectangle. The same screen creates a visible BindingChip plus hidden legacy binding Label/TextureRect nodes for every action; it computes prompts and updates the hidden nodes before updating the chip. Tests depend on the legacy names. The hidden label also supplies the real chip's radio-navigation override, so these nodes are not yet removable by simply deleting construction. [Hidden meters][r-hidden-meters] [Preview updates][r-preview-updates] [Legacy binding nodes][r-hidden-bindings] [Binding updates][r-binding-updates] [Legacy tests][r-hidden-tests]

**Consolidation and deletion.** Make the current presentation controls the tested contract. First move conditioned-value assertions to the sampled values plus the real labels/gimbals, and layout assertions to visible controls. Then delete the hidden bars, their map and repeated writes. In a separate small change, use BindingChip's existing label_text/has_glyph presentation interface, pass the calibrated roll/pitch override directly, migrate named-node callers and tests, then remove the old Label/TextureRect construction and the setup-only prompt-texture cache if nothing else uses it. Do not delete the row that still carries the visible source-axis label. [BindingChip interface][r-binding-chip]

**Acceptance.** Preserve absolute and centered throttle, inversion, disconnect state, Xbox/PlayStation/generic prompts, JETI named/unknown switch labels, radio menu wording, conflict and held-state presentation, focus, save/cancel and remapping. Verify actual visible controls at 1080p and required smaller-layout cases. This is both code retirement and test improvement: a hidden node's value or rectangle is not proof of what the player sees. Test migration must preserve behavioral expectations rather than merely stop old assertions failing.

### R06 — Medium: one field-diagnostic mechanism for the shared time/sky controls

**Evidence.** Home's Weather/Conditions dialog and the paused TimeOfDayDialog reuse TimeOfDayControls and SkyControls. WeatherDialog translates structured failures into a field-owned inline explanation, reveals the relevant tab/advanced section, and schedules guarded focus/scroll. TimeOfDayDialog discards the corresponding time/night/moon details for a generic input error; sky failure uses its generic apply-error path. The child controls already expose structured field/control/label/code information for relevant validation failures. [Weather diagnostics][r-weather-diagnostics] [Paused apply][r-time-dialog] [Existing field helper][r-field-helper]

**Consolidation.** Extend the small FieldDiagnostic boundary with reusable presentation/focus mechanics or an adjacent owner-local presenter. Callers supply the field issue and their tab/reveal actions. Keep Home's physical-weather draft separate from the paused dialog's visual-only commit; preserve real flight staging/commit errors and the draft after refusal. Do not copy the entire WeatherDialog or centralize every domain validator in the UI.

**Acceptance.** Invalid date, offset, location, sky number and missing option; correct tab/reveal/focus; translated, readable inline errors; stale deferred callback after closing or changing generation; real flight apply failure retains the modal and draft. Existing A13 Conditions work remains completed; this is adoption in a distinct paused route.

### R07 — Medium: share Workshop model bounds, retain distinct preview and thumbnail behavior

**Evidence.** WorkshopPreview and WorkshopThumbnail independently traverse descendant MeshInstance3D nodes, transform all eight local AABB corners along the current ancestor walk and merge bounds. Their root-transform helper is one of the exact scan matches. Both exclude the root itself from the descendant search and stop the walk at a non-Node3D ancestor; unrestricted root-relative geometry is not established for every possible hierarchy. Their empty behavior differs intentionally: live preview supplies a unit-cube fallback, while thumbnail creation refuses empty/tiny geometry. Live camera fitting also includes a moving pass and optionally a smoke plume; the still thumbnail does not. [Preview bounds/fitting][r-preview-bounds] [Thumbnail bounds/fitting][r-thumbnail-bounds]

**Consolidation.** Extract only the existing mesh-bounds traversal, returning an explicit found/bounds result so callers retain empty and degenerate policies. Keep current root inclusion rules, transform order and treatment of non-Node3D ancestors. Broader hierarchy support would be a separate rendering/identity correction. Preserve isolated worlds, materials, lighting, frozen variant identity, cancellation generations, thumbnail cache and each camera's framing.

**Acceptance.** Nested translations/rotations/nonuniform and negative scales, null mesh, non-Node3D ancestors, no mesh and tiny geometry. Follow existing Workshop preview/thumbnail tests with rendered live/still framing checks; headless cache/refusal tests alone do not validate a generated image. Never share a mutable scene/resource instance as the shortcut to sharing this calculation.

### R08 — Medium/high: declare native qualification cases once, keep qualification policies explicit

**Evidence.** The qualification script roster is repeated in research/native-kernel/package.py, the native export plugin, NativePackage's diagnostic list and app/tools/native_qualification.gd. Source CI and actual-package loops separately enumerate modes and required markers. There is a concrete coverage asymmetry: the Linux source-native job explicitly requires helicopter-radio, whereas the Windows source-native job's listed branch checks stop at helicopter. The Windows actual-package loop does require helicopter-radio. This is not a claim that Windows has no such qualification. Mac intentionally has a narrower fixed-wing scope. [Package roster][r-native-package-roster] [Export roster][r-native-export-roster] [Runtime roster][r-native-runtime-roster] [Mode mapping][r-native-modes] [Linux source job][r-native-source-jobs] [Windows source job][r-native-windows-source] [Windows package modes][r-native-windows-modes] [Linux package modes][r-native-linux-modes]

**Consolidation.** Have the existing native-package owner declare case ID, source, applicable platform/backend, source/package mode and expected marker, with small generated or checked projections for Python, GDScript and workflow consumers. Start with a consistency check if generating code would add more machinery than it removes. Keep script admission closed, actual-native selection, package receipts, “preloaded=false”, unsupported-domain refusal and negative controls.

The common roster must not make tests self-confirming: an accidentally removed case must fail an independently reviewed required-case expectation, not disappear from both execution and the expected set. Keep platform/source/package distinctions as explicit policy; decide the Windows source asymmetry deliberately rather than silently treating it as equivalent coverage.

**Acceptance.** Remove or rename each required case/marker in disposable fixtures and prove refusal; verify all generated/checked projections; retain source-native, packaged-native, reference-fallback and Mac-scope tests independently. No platform qualification was run here.

### R09 — Medium: expose one current engine-pin description to the tools

**Evidence.** RCV native verification, testqueue worker/pool admission, release preflight and release-manifest construction independently parse the shell engine pin with different regexes and different responsibilities. The worker records binary SHA-256/SHA-512 values but its direct digest pin comparison is Windows-specific and compares sets of hashes; pool admission reads the engine version from a verified snapshot; the RCV verifier binds expected hashes to named binary roles. These are different current checks, not proof of a Linux failure. Converting the worker's set comparison to named-pair enforcement is a separately reviewed hardening change, not mere parsing equivalence. [RCV pin reader][r-rcv-pin] [Worker reader][r-worker-pin] [Pool snapshot reader][r-pool-pin] [Release reader][r-release-pin] [Manifest reader][r-release-manifest-pin]

**Consolidation.** Provide a structured, validated description at the existing engine-pin owner, or first share one pure parser accepting supplied text/bytes. Keep one authority for versions and named hashes; avoid a second manually maintained manifest. Snapshot consumers must read their verified candidate bytes, not the live working tree, and must not execute candidate shell text to obtain metadata.

Keep engine download/installation, worker admission, template-member verification, historical benchmark identities and custom Mac-engine policy separate. This change should make their deliberate differences visible, not erase them.

**Acceptance.** Missing/duplicate assignments, malformed hashes, reordered fields, changed version, swapped Windows GUI/console binaries under the explicitly chosen policy, candidate snapshot differing from live checkout, each supported current platform, retained historical pins and custom-engine refusal. Source-pin/schema changes must preserve cache/snapshot and release-manifest SOURCE_INPUTS dependencies and fail closed. Extend existing pin/preflight/worker tests rather than introduce another installer.

### R10 — Medium: one maintained source for the live package/research flight-input adapter

**Evidence.** app/tools/package_flight_input.gd and research/performance/sustained_input.gd are byte-identical 5,555-byte blobs at this revision. Both are live: the package observer preloads the app path, and sustained_flight.gd dynamically loads its research sibling. GOD TEST and Mac promotion explicitly include the research path in their frozen source identities. Therefore the two files are not independently dead. [Package consumer][r-package-observer] [Research consumer][r-sustained-caller] [Frozen source roster][r-godtest-roster] [Mac source identity][r-macos-source-roster]

**Consolidation.** Choose one maintained implementation, preferably at the package-compatible app/tools boundary, and keep a thin research adapter if its entry point is still useful. A generated checked copy is an alternative when a self-contained snapshot genuinely requires one. Update active source manifests to include the implementation actually executed as well as wrappers; hashing only a newly thin wrapper would weaken provenance.

The identical app/tests/check_native_pack.gd and historical native_package_smoke.gd need the same caller/evidence classification before retirement. The RCV ground-effects test copy also matches current app code, but its surrounding research directory contains different historical implementation and recorded inputs. These matches establish investigation candidates, not permission to rewrite frozen evidence.

**Acceptance.** Exercise both source and actual exported observer routes, matching command schedule/tick behavior, completion and exit semantics; verify the canonical implementation is present in exports and frozen campaign inputs. Preserve old receipts as historical identities; regenerate only current manifests through their owners. Delete a redundant live copy only after all active callers and provenance move.

### R11 — Medium, bounded deletion candidates: retire code whose replacement is already explicit

Two stronger candidates have positive replacement evidence rather than merely old names:

| Candidate | Current replacement and proposed boundary | Required proof |
| --- | --- | --- |
| Glow two_stroke/four_stroke _finite_outputs | Both evaluators now check finite scalar outputs inline before allocating the result dictionary; the retained helper has no production/test caller in the inspected application source. Remove the two unused predicates and stale explanatory references, retaining the inline checks and failure results. Do not centralize an unused helper. | Check dynamic/tool callers, parse and existing two/four-stroke/oracle/coupling tests; preserve finite failure behavior, including constant-zero two-stroke valve torque; account for the changed physics source fingerprint. |
| ClearView Setup._model_type and HELICOPTER_TYPE | Setup.is_helicopter now delegates to Installation.rotorcraft using admitted provider/tag metadata. Converter still writes the original receipt and the rotorcraft tag. Remove only the unused private receipt reader and constant after consumer checks. | Preserve current tag/provider admission, fixed-wing refusal, helicopter donor selection, reopen and export. Keep receipt contents and converter tags. A receipt parser and a tag are not semantically interchangeable for metadata-stripped inputs. |

[Glow current check and retained helper][r-glow-two] [Four-stroke counterpart][r-glow-four] [ClearView replacement][r-clearview-setup] [Source installation identity][r-source-installation] [Converter receipt/tag][r-clearview-converter]

These are proposed small deletion changes, not deletions performed by this audit. The name-only candidate scan also flags many debug bridge methods, but DebugBridge dispatches them dynamically with a constructed method name. Those commands have current clients and must remain. Native package/admission routines with sparse apparent callers require platform and promotion review; they are not included in the deletion recommendation. [Dynamic debug dispatch][r-debug-dispatch]

### R12 — Low/medium: consolidate small pure primitives within their own domains

The broad scan provides several exact candidates beyond the first vehicle pass. They should follow the higher-value ownership and verification fixes.

| Domain | Exact shared mechanism | Preserve |
| --- | --- | --- |
| Time of day | SolarPosition and TimeOfDayConfig have identical Gregorian date and ASCII-digit checks | Existing 2000–2100 range, leap-year rules, independent validation at both public entry points and each error message. Config also uses digit checking for clock fields. |
| Glow engines | Two/four-stroke _read_number, _sample and _empty_result match | Distinct combustion laws, cycle frequency, table/domain requirements, native/reference contracts, prevalidated path and arithmetic order. _read_table is not identical: two-stroke has an additional query guard; characterize that difference before sharing it. |
| Scalar lake geometry | Three _polygon_bounds copies and two point-segment-distance copies match | Float64/scalar types, caller validation, empty/degenerate admission, contact/event ordering and source identity. Coordinate with U05 rather than create a parallel geometry subsystem. |

[Time config][r-time-validator] [Solar validation][r-solar-validator] [Glow helpers][r-glow-two] [Four-stroke helpers][r-glow-four] [Lake-loader geometry][r-lake-geometry] [Hull geometry][r-hull-geometry] [Lake collision geometry][r-lake-collision-geometry]

Prefer a domain-local helper or an existing lower-level owner. A global Common/Utils library would hide different admission contracts behind similarly named functions. Tiny duplicated wrappers that dispatch to different implementations are not worthwhile abstractions. For the glow sampler, preserve the expression/evaluation order and measure any hot-path overhead before claiming a performance benefit. Keep the mathematical oracle independent.

## 9. What to retain, what can retire, and how to organize it

The following dispositions prevent “cleaning” away active contracts:

| Area | Disposition at this revision | Reason / next step |
| --- | --- | --- |
| Hidden controller bars and legacy binding nodes | Retire after consumer/test migration | Explicit visible replacements exist, but tests and radio override still depend on the old path; R05. |
| Unused glow predicate and ClearView reader | Small deletion candidates after bounded checks | Explicit current replacement; R11. |
| Live duplicate flight-input implementation | Consolidate, then remove or generate the duplicate | Both current consumers and frozen source manifests must migrate; R10. |
| Frozen three.js prototype | Retain now; CI cost policy is a separate decision | It documents the platform comparison and is still built/typechecked/tested/captured in CI. Current shadow selection forces prototype and production coverage; path scoping has not made it inactive. Finish the owning CI rollout deliberately before retiring a job or source tree. |
| Authored research data and generated app data | Retain both roles with one authoring source | The repair-recipe generator validates/serializes authored data into the packaged file; runtime and tests depend on the generated projection. Identical bytes do not imply independent ownership or dead data. |
| Economy “legacy” catalog | Retain | Normal load_for calls load_legacy_for, and the v3 cost companion binds its generated catalog and physical-source hashes. Renaming/removing it requires a schema/provenance migration, not a text cleanup. |
| Timber/Vantage legacy inspector facades | Retain current contracts; move callers before retirement | Timber still has inspection, clearance, imported-model and crash consumers; source/geometry identities are recorded. Shared production construction does not eliminate metrology/CLI compatibility. |
| GDScript reference physics, native backend and old replay/schema readers | Retain required supported paths | These provide independent specification, unsupported-platform fallback and recorded identity/compatibility; deleting them changes product and verification scope. |
| Frozen research snapshots, original sources and campaign evidence | Retain provenance | Consolidate active commands and indexes, but do not edit old snapshots to match new runtime or remove a baseline merely because its bytes match today. |
| DebugBridge command methods | Retain | Constructed dynamic dispatch defeats a simple literal-call scan; R11. |

[Prototype CI][r-prototype-ci] [Shadow policy][r-ci-shadow] [Economy generator][r-economy-generator] [Economy consumer/test][r-economy-consumer] [Current catalog chain][r-economy-catalog] [Cost identity][r-economy-cost] [Timber facade][r-timber-facade] [Inspector identity][r-timber-inspector]

**Organization should follow responsibility and dependency.** Keep shell routes and accepted settings in app_state/UI; keep data/schema rules at their domain owners; put Workshop-only geometry and importer ownership with Workshop/Creator; retain engine process verdicts under tools/godot and native package definitions under the native-package owner. Use a small mapping of source → generator → runtime projection → validation in the existing owning guides. Do not move the repository en masse into a new “core” folder, scatter generic managers, or replace the current owner registry with another master plan.

The website, telemetry service and simulator have different deploy/runtime boundaries. Share reviewed schemas, generated metadata or fixtures where the contract matches; do not make the website or service import Godot runtime code, and do not force telemetry consent/retention into general game statistics persistence. No unsupported site/service refactor is proposed from inventory alone.

## 10. Recommended next implementation sequence

Keep the earlier controls characterization and independently required repairs in their owning tracks. The new work can be reviewed in separate small changes:

| Order | Concrete change | Why this order | Completion gate |
| --- | --- | --- | --- |
| 1 | R03 scenario wrapper adopts checked runner | Strong existing owner; closes a source-derived verification gap used by the capture suite | Fake-engine failure matrix, real admitted scenario/image checks, complete process retirement |
| 2 | R01 display publication uses verified mechanism | Protects a user-visible commit boundary before broader settings restructuring | Failed-write/readback fixtures plus Keep/Revert and existing display behavior |
| 3 | R04 bound Creator ordinary import admission | Establishes resource ownership before sharing cancellation utilities | Slow-worker cancel/reselect/close checks and bounded outstanding work |
| 4 | R05 remove hidden meters, then legacy binding nodes | Clear replacement; improves tests and removes obsolete runtime maintenance | Current visible UI/control contract and required rendered checks |
| 5 | R11 remove the isolated obsolete helpers | Small, reviewable source retirement with explicit replacements | Caller/package checks, affected regression/identity gates |
| 6 | R08 native case consistency, then R09 pin reader | Fewer independently maintained upgrade/qualification definitions | Independent omission/marker/hash negative cases across declared platforms |
| 7 | R10 canonical flight-input adapter | Removes a live duplicate while making provenance complete | Both source/package consumers and updated active source manifests |
| 8 | R02/R06/R07 small presentation seams | Reuse existing owners after characterizing their different policies | Startup transaction cases, visible diagnostics, model bounds/framing |
| 9 | R12 domain primitives | Useful incremental cleanup; lower payoff than ownership fixes | Public refusal behavior, numerical identity and affected consumer checks |

These rows are proposals for existing UI/AC/AE/TOD/physics/PT/SC/DT/NK/DX owners. They do not rename existing steps or mark them complete. Do not combine deletion, behavior repair, directory moves and numerical changes in one broad “cleanup” commit.

Track useful outcomes: fewer independently maintained publication/launch/qualification paths; actual old callers retired; tests asserting current visible behavior; complete source identities; bounded pending work; and unchanged accepted physics/compatibility. Net line count and the number of classes are secondary. FPS, import memory, startup time and CI-duration improvements require their own measurements.

## 11. Continuation verification and limits

The continuation ran repository/tree and source inventory, exact-function/blob comparisons, current caller/configuration inspection and documentation checks. Material findings were checked against original source, and retirement candidates were distinguished from generated projections, dynamic entry points and frozen evidence. The independent challenge led to explicit limits for startup interleavings, every Creator task-submission route, enrolled visual-runner admission, named versus set-based engine hashes, consent persistence failures and the exact preview hierarchy traversal. The review retained small existing owners and rejected universal store/job/camera abstractions. Final documentation verification is summarized in the publication commit.

No game source, tool implementation, test, generated physics, schema, engine pin, CI policy or evidence baseline was changed. No engine, native build, capture, device, performance, package or full-CI campaign was executed. The capture false-pass sequence, failed display publication, canceled-import resource accumulation and startup presentation mismatch are source-supported verification targets, not reproduced incidents. The proposed work is ready to scope into reviewable changes; runtime acceptance remains to be executed for each actual change.


[r-corsair-geometry]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/aircraft/f4u_corsair_geometry.gd
[r-avanti-geometry]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/aircraft/avanti_s_blender_geometry.gd
[r-display-write]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/display_preferences.gd#L158-L171
[r-settings-keep]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/settings_screen.gd#L1352-L1374
[r-guard-write]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/renderer_guard.gd#L84-L107
[r-preferences-file]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/preferences_file.gd#L117-L218
[r-consent-store]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/telemetry/telemetry_consent_store.gd#L1-L72
[r-startup-reader]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/startup.gd#L505-L532
[r-preferences-load]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/preferences.gd#L95-L133
[r-capture-caller]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/capture.sh#L331-L338
[r-scenario-wrapper]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/scenery/scenario.sh#L12-L40
[r-scenery-wrapper]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/scenery/capture.sh#L13-L24
[r-world-wrapper]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/world/parity.sh#L18-L40
[r-checked-runner]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/godot/run_checked.py#L25-L143
[r-creator-jobs]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/aircraft_creator.gd#L571-L647
[r-creator-cancel]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/aircraft_creator.gd#L709-L725
[r-creator-choose]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/aircraft_creator.gd#L2338-L2346
[r-import-limits]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/workshop/creator/limits.gd
[r-phoenix-plan]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/docs/plans/phoenix-aircraft-import/implementation.md
[r-home-resource-owner]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/home_preview_resources.gd#L48-L68
[r-hidden-meters]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/controller_setup.gd#L1375-L1396
[r-preview-updates]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/controller_setup.gd#L3400-L3432
[r-hidden-bindings]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/controller_setup.gd#L1451-L1476
[r-binding-updates]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/controller_setup.gd#L3508-L3539
[r-hidden-tests]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tests/test_controller_sections.gd#L279-L290
[r-binding-chip]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/controls/binding_chip.gd#L69-L139
[r-weather-diagnostics]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/weather_dialog.gd#L925-L1047
[r-time-dialog]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/time_of_day_dialog.gd#L244-L275
[r-field-helper]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/field_diagnostic.gd#L1-L26
[r-preview-bounds]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/workshop_preview.gd#L471-L551
[r-thumbnail-bounds]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/workshop_thumbnail.gd#L390-L444
[r-native-package-roster]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/research/native-kernel/package.py#L25-L46
[r-native-export-roster]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/addons/native_kernel/export_plugin.gd#L12-L23
[r-native-runtime-roster]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/native_package.gd#L6-L12
[r-native-modes]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tools/native_qualification.gd#L7-L16
[r-native-source-jobs]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/.github/workflows/ci.yml#L412-L429
[r-native-windows-modes]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/.github/workflows/ci.yml#L1231-L1240
[r-native-linux-modes]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/export.sh#L302-L311
[r-rcv-pin]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/ci/check_rcv_native.py#L31-L69
[r-worker-pin]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/testqueue/worker.py#L248-L284
[r-pool-pin]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/testqueue/pool.py#L636-L650
[r-release-pin]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/ci/release_preflight.py#L67-L86
[r-package-observer]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tools/package_flight_observer.gd#L1-L25
[r-sustained-caller]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/research/performance/sustained_flight.gd#L190-L208
[r-godtest-roster]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/godtest/runner.py#L38-L65
[r-macos-source-roster]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/research/native-kernel/macos_promotion.py#L191-L210
[r-glow-two]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/physics/glow/two_stroke.gd#L218-L399
[r-glow-four]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/physics/glow/four_stroke.gd#L237-L417
[r-clearview-setup]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/workshop/creator/clearview/setup.gd#L396-L419
[r-source-installation]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/workshop/creator/source_installation.gd#L20-L61
[r-clearview-converter]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/workshop/creator/clearview/converter.gd#L203-L240
[r-debug-dispatch]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/debug/debug_bridge.gd#L586-L596
[r-time-validator]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/environment/time_of_day_config.gd#L397-L440
[r-solar-validator]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/environment/solar_position.gd#L118-L161
[r-lake-geometry]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/data/lake_loader.gd#L270-L329
[r-hull-geometry]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/physics/hull_contact.gd#L839-L849
[r-lake-collision-geometry]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/lake_collision.gd#L580-L590
[r-prototype-ci]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/.github/workflows/ci.yml#L89-L113
[r-ci-shadow]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/ci/policy.py#L125-L139
[r-economy-generator]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/research/crash-economics/build_runtime.py#L1121-L1175
[r-economy-consumer]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tests/test_economy_repair_planner.gd#L1-L22
[r-economy-catalog]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/economy/catalog.gd#L16-L37
[r-economy-cost]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/economy/cost_profile.gd#L21-L39
[r-timber-facade]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/aircraft/timber_model.gd#L1-L51
[r-timber-inspector]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/aircraft/inspect_timber.gd#L197-L216
[r-library-write]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/workshop/library_preferences.gd#L144-L245
[r-draft-write]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/workshop/draft_store.gd#L428-L495
[r-race-write]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/multirotor/race_records.gd#L81-L117
[r-checked-admission]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/testqueue/integration.py#L204-L235
[r-creator-open]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/aircraft_creator.gd#L3185-L3207
[r-creator-convert]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/aircraft_creator.gd#L760-L772
[r-release-manifest-pin]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/release/manifest.py#L220-L234
[r-display-file-write]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/display_preferences.gd#L367-L413
[r-native-windows-source]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/.github/workflows/ci.yml#L610-L624


[architecture]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/docs/STACK.md
[vehicle-model]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/vehicle_model.gd#L1-L102
[prior-plan]: https://github.com/bultodepapas/OpenRCsimulator/blob/3095afd95220232e8e659d53635acab5104ee94c/docs/plans/vehicle-runtime-consolidation.md
[prior-matrix]: https://github.com/bultodepapas/OpenRCsimulator/blob/3095afd95220232e8e659d53635acab5104ee94c/docs/research/vehicle-runtime-consolidation-2026-11-21/MIGRATION-MATRIX.md
[audit-ledger]: ../../external%20Audits/CONSOLIDATED-AUDITS.md
[environment]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/environment.gd#L17-L162
[controller-service]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/input/controller_service.gd
[lens-stack]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/lens/lens_stack.gd
[route-dispatch]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L363-L416
[direct-route]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L604-L614
[aircraft-args]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/main.gd#L3405-L3410
[quad-route-test]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tests/test_mr_activity.gd#L450-L459
[ground-registry]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/ground/ground_scene.gd#L362-L419
[ground-button]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/ground/ground_scene.gd#L687-L705
[shell-ui-role]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L2447-L2456
[shell-controller-exclusion]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L2815-L2817
[ground-role-test]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tests/test_controller_car.gd#L73-L107
[ground-controls]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/research/rc-monster-truck/README.md#L196-L205
[selection-service]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/input/controller_service.gd#L114-L159
[quad-fallback]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/multirotor/multirotor_scene.gd#L476-L506
[store-matching]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/input/controller_profile_store.gd#L301-L320
[quad-profile-refusal]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/multirotor/multirotor_scene.gd#L595-L625
[activity-launches]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L910-L1105
[airship-lake]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/airship/session.gd#L320-L391
[quad-lake]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/multirotor/session.gd#L366-L380
[airship-clearance]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/airship/session.gd#L501-L515
[quad-clearance]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/multirotor/session.gd#L994-L1007
[quad-world]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/multirotor/session.gd#L716-L736
[collision-validation]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/scenery/collision_world.gd#L980-L1001
[airship-prepare]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/airship/session.gd#L91-L236
[quad-prepare]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/multirotor/session.gd#L162-L261
[ground-field]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/ground/ground_scene.gd#L456-L485
[airship-field]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/airship/airship_scene.gd#L319-L339
[quad-field]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/multirotor/multirotor_scene.gd#L332-L351
[fixed-log-writer]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/flight_log.gd#L350-L420
[airship-log-writer]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/airship/flight_log.gd#L164-L227
[quad-log-writer]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/multirotor/flight_log.gd#L186-L254
[airship-log-header]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/airship/flight_log.gd#L1-L89
[quad-log-header]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/multirotor/flight_log.gd#L1-L103
[airship-replay]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/airship/flight_log.gd#L277-L351
[airship-replay-cli]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tools/airship_flight_log_cli.gd#L34-L49
[quad-replay]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/multirotor/flight_log.gd#L445-L456
[blimp-logging]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/docs/FLIGHT-LOGGING.md#rc-blimp-logs
[manual-save]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/manual_trace_save.gd
[ground-export]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/ground_vehicle/session.gd#L1020-L1086
[prepared-reset]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/simulation.gd#L113-L205
[fixed-reset]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/flight_session.gd#L3844-L3888
[airship-stop]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/airship/airship_scene.gd#L834-L848
[quad-stop]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/multirotor/multirotor_scene.gd#L1356-L1370
[departure]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L5091-L5127
[plane-lens]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/main.gd#L306-L351
[heli-lens]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/helicopter_main.gd#L304-L326
[airship-lens]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/airship/airship_scene.gd#L238-L271
[ground-lens]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/ground/ground_scene.gd#L785-L818
[quad-lens]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/multirotor/multirotor_scene.gd#L985-L1021
[world-context]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/world/world.gd#L94-L153
[workshop-world]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L3893-L3995
[vehicle-roster]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/vehicle_roster.gd#L1-L140
[roster-tests]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tests/test_home_vehicle_roster.gd#L29-L54
[airship-quantities]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/physics/airship/airship_data.gd#L564-L605
[quad-quantities]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/physics/multirotor_data.gd#L1036-L1068
[airship-audio]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/airship/airship_scene.gd#L752-L802
[quad-audio]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/vehicles/multirotor/multirotor_scene.gd#L1279-L1352
[airship-ocv]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/physics/airship/airship_dynamics.gd#L588-L597
[quad-ocv]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/physics/multirotor/controlled_plant.gd#L344-L354
[plane-ocv]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/physics/electric_supply.gd#L199-L210
[ground-tick]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/ground_vehicle/session.gd#L2172-L2240
[nitro-step]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/physics/ground_vehicle/nitro_dynamics.gd#L87-L141
[quad-controller]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/physics/multirotor/controlled_plant.gd#L294-L332
[native-policy]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/docs/STACK.md#native-backend-policy
[source-identity]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/sim/flight_log.gd#L425-L501
[flight-logging]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/docs/FLIGHT-LOGGING.md
