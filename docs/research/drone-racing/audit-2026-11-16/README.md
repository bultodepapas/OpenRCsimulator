# FPV drone racing audit — 2026-11-16

## Verdict and scope

The ION R5 FPV activity and local racing mode are implemented and have substantial working software coverage. This audit and its follow-up identify **19 actionable findings: 2 P1, 12 P2 and 5 P3**, plus the qualification and product gaps listed below. The most urgent problems concern controller authority: a refused saved profile can become a ready default mapping, and an accepted Flight mode AUX assignment can also arm or disarm the motors.

**Audited source:** [`cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`](https://github.com/bultodepapas/OpenRCsimulator/commit/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b), the remote `main` head verified at audit start. **Delivery branch:** `audit/fpv-drone-racing-2026-11-16`. This branch contains findings, diagnostic reproducers and portable verification summaries. Raw logs and host-specific runner metadata are excluded from publication. It does not change production behavior or claim to repair the findings.

The review covers the Home and direct-launch routes, controller profiles and AUX inputs, arming and lifecycle, flight controller and allocator boundaries, motor/pack/airframe models, contact and crash detection, race geometry and event ordering, session/checkpoint/replay contracts, result persistence, camera/OSD/help, generated aircraft data, tests and current implementation documentation. Three independent reviews covered controls/product, physics, and racing/persistence; an adversarial review challenged reachability and severity claims before integration.

**Fresh software verification:** 25 existing FPV-related suites passed **1,120 checks**, with zero checked-run engine errors and warnings in the final selected runs. The generator consistency check passed. Additional diagnostic probes reproduce issues the existing suite does not cover. Passing those probes means the baseline problem was observed; it does **not** mean the behavior is correct. The [verification record](evidence/verification.json) and [test matrix](evidence/test-matrix.md) distinguish normal tests, expected defect observations, and the deliberate malformed-record error.

This is a comprehensive review of the available implementation, not proof that no other defects exist. Hardware acceptance, native rendering/performance, full repository CI, and selected-build physical validation remain open. No normal pad-start flight is claimed for a defect demonstrated only with a component fixture or the research air-start route.

**Follow-up investigation:** [stronger scene/session witnesses and compared repair options](follow-up.md) extend A03, A07 and A10, exercise Start/AUX ownership, bound the normal pad-start regeneration claim, and test an existing persistence recovery pattern. The follow-up adds A19 to the original 18 findings: a matching gamepad arrival can leave the active verifier stale and silently disarm the scene. [The active remediation programme](../../../plans/drone-racing.md#16-audit-remediation-programme-2026-11-16) now owns implementation order and acceptance; the findings below remain the dated, unrepaired baseline.

**Repair status (2026-11-17).** All 19 findings now have software repairs and desired-behaviour regressions; see the [plan's repair status](../../../plans/drone-racing.md#165-repair-status-2026-11-17). The findings below remain the dated baseline. The probes in this folder still describe the baseline: after the repair they are expected to stop observing their defects.

## Priority and evidence conventions

| Priority | Meaning in this audit |
| --- | --- |
| P1 | Fix before broad controller-dependent pilot acceptance: incorrect control authority or unintended arming/disarming. |
| P2 | Correctness or recoverability defect in an admitted workflow/model; implement and verify in the next focused repair work. |
| P3 | Lower-impact robustness, identity, metadata or communication defect. |

“Scene” means the real application scene/service path with injected device observations where stated. “Component” means production classes exercised with a controlled fixture; reachability from ordinary flight may remain unproven. “Source” means a verified code path without an end-to-end fault injection. Severity reflects impact and exposure, not just the presence of an assertion.

## Findings at a glance

| ID | Priority | Finding | Evidence |
| --- | --- | --- | --- |
| A01 | P1 | Rejected controller profile becomes flyable default mapping | Scene + synthetic verified gamepad |
| A02 | P1 | Flight mode AUX on LB also toggles motor arming | Input adapter + controlled plant |
| A03 | P2 | Ordinary hold/resume silently converts invalid Arm AUX into motor OFF | Input/plant reproduction + scene source |
| A04 | P2 | Direct launch bypasses the current saved controller store | Route reproduction + source |
| A05 | P2 | Direct launch removes gamepad menu bindings and never reinstalls them | Route/InputMap reproduction |
| A19 | P2 | Matching gamepad arrival leaves a stale verifier and disarms without a hold | Real service/registry/scene with synthetic devices |
| A06 | P2 | Damped regeneration admits charge above pack capacity | Integrated tick + supported research air start |
| A07 | P2 | Rotor/terrain test misses an uphill disc rim intersection | Collision component geometry |
| A08 | P2 | Loader admits a custom battery that cannot supply hover power | Strict loader + independent power bound |
| A09 | P2 | Prepared-data path accepts negative aerodynamic drag | Session admission + load evaluation |
| A10 | P2 | A finish can precede an earlier modeled gate contact within the same tick | Collision/director component counterexample |
| A11 | P2 | A full unsaved-result outbox has no activity recovery path | Eight failed saves + repaired storage |
| A12 | P2 | Distinct sessions can silently overwrite each other's result file | Two actual session results, same filename |
| A13 | P2 | Result/book replacement unlinks the old file before rename | Source; failure window not injected |
| A14 | P3 | Pad-reset abort reports tick zero and a “none” reason code | Session reproduction |
| A15 | P3 | Course identity omits terrain-dependent post solids | Track component counterexample |
| A16 | P3 | Empty record-book entry passes loading, then fails during apply | Malformed-file probe + script error |
| A17 | P3 | OSD preference write failure is silently ignored | HUD/storage failure probe |
| A18 | P3 | Static help advertises shortcuts overridden by explicit AUX | HUD/input probe |

## Controls and activity lifecycle

### A01 — Refused controller profile becomes a ready default

**Trigger and actual behavior.** Supply an unsupported controller-store version while a known gamepad is selected. `ControllerService.profile_for_device()` returns `{}` deliberately when resolution is refused. The multirotor scene forwards that empty dictionary to `RCInput.connect_device()`, which interprets it as permission to select its built-in Gamepad Mode 2 profile. The source becomes ready and the scene can resume and arm.

**Evidence.** [profile_refusal.gd](repros/profile_refusal.gd) writes an isolated version-999 store, instantiates the real service and quad scene, injects a synthetic verified gamepad, and demonstrates rejection → empty resolver result → built-in mapping → ready scene → arming. The final arm input is an injected keyboard arm key, not a physical gamepad press. A healthy empty-store control produces an explicit default profile, proving refusal need not be conflated with first-use defaults. Ten checks passed.

**Impact.** For a selected known gamepad, a corrupt, unsupported, ambiguous or otherwise refused configuration can become a different valid mapping without the pilot resolving the refusal. The reproduced case is unsupported version; the other refusal branches share the same empty-result contract and are source-based extensions of the finding.

**Source.** [controller_service.gd](../../../../app/input/controller_service.gd), `_resolve_stored_profile_locked`; [multirotor_scene.gd](../../../../app/vehicles/multirotor/multirotor_scene.gd), `_connect_selected_controller`; [rc_input.gd](../../../../app/input/rc_input.gd), `connect_device`. The fixed-wing consumer explicitly rejects an empty resolved profile in [flight_session.gd](../../../../app/sim/flight_session.gd).

**Repair and acceptance.** Preserve a distinct “resolution refused” state through the scene/input boundary and keep flight commands unavailable. Retain explicit defaults for a healthy new-device case. Cover unsupported/corrupt stores, ambiguous associations, resolver failure and a healthy empty store, including scene resume/arm refusal.

### A02 — Flight mode AUX on LB also arms and disarms

**Trigger and actual behavior.** A valid gamepad profile binds Flight mode to LB and leaves explicit Arm AUX unbound. The generic profile validator accepts this assignment. The quad still polls LB as its hard-coded arm shortcut, so the same button press selects a mode and arms; another press changes the mode request and disarms.

**Evidence.** [controls.gd](repros/controls.gd), `mode_button_arms`, uses a normal string-key profile, production input adapter, and controlled lab plant. It confirms profile validation, the Flight mode request, armed motor state, and the subsequent disarm. This is synthetic input, not physical controller qualification.

**Source.** [multirotor_input.gd](../../../../app/input/multirotor_input.gd), `ARM_BUTTON`, `MODE_BUTTON` and `sample`; [controller_actions.gd](../../../../app/input/controller_actions.gd), effective bindings and profile conflict validation. The quad shortcuts are outside the shared action ownership check.

**Repair and acceptance.** Give every active physical binding one authority across shared actions, AUX channels and quad shortcuts. Either reject an incompatible assignment with a useful explanation or suppress the inherited shortcut when AUX owns that control. Verify LB-as-mode and RB-as-arm, explicit/legacy AUX, held buttons, reconnects and ordinary default profiles. The RB mirror is a source concern, not a separately executed observation in this audit.

### A03 — Ordinary hold/resume drops Arm AUX and cuts motors

**Trigger and actual behavior.** A radio with explicit Arm AUX is armed in flight. A non-integrating paused poll disables/reset-gates AUX authority. On the first resumed tick, the radio may be ready while its Arm AUX request is invalid. The quad adapter converts that invalid request to `0`, which the flight controller treats as a real disarm command. A keyboard toggle survives the same ordinary hold.

**Evidence.** [controls.gd](repros/controls.gd) arms a controlled plant at 20 m, performs one ordinary `sample(DT, false)`, then resumes with the physical switch still ON. It observes a ready input, arm OFF and disarmed motor mode. The keyboard control remains armed. The real scene uses the same non-integrating poll during hold/resume and allows resume based on readiness.

The fresh-OFF recovery rule is legitimate and must not simply be deleted. The defect is the mismatch between “invalid/no command,” actual motor OFF, and a UI offering an ordinary flight resume. OFF events while AUX is disabled cannot qualify the requested recovery before resuming.

**Source.** [rc_input.gd](../../../../app/input/rc_input.gd), `poll`, `set_auxiliary_enabled`, `auxiliary_request_valid`; [multirotor_input.gd](../../../../app/input/multirotor_input.gd), `sample`; [multirotor_scene.gd](../../../../app/vehicles/multirotor/multirotor_scene.gd), `_can_resume`, `handle_action`, hold polling.

**Repair and acceptance.** Define an explicit same-source pause versus authority-loss recovery contract. Preserve required neutral/OFF evidence without silently resuming an airborne craft into a motor cut. Test the whole activity with Arm AUX, ordinary pause, focus loss, device/profile change and keyboard controls, and verify the menu explains any mandatory reset/rearm.

### A04 — Direct launch uses legacy controller storage

**Trigger and actual behavior.** `--multirotor=openrc-fpv5-x1` returns from AppRoot initialization before creating `ControllerService`. The scene consequently has no profile resolver and connects its first detected device through `MultirotorInput`, whose fallback path is `user://rc_calibration.cfg`. Current Controls settings are persisted in `user://controller_profiles.cfg`.

**Evidence.** [direct_route.gd](repros/direct_route.gd) confirms the actual direct route creates the quad, omits the service/resolver and points at the legacy store. No real radio was attached; the resulting wrong/stale/missing mapping on such a device is established by source flow, not a hardware session.

**Impact.** The same saved controller configuration does not have route parity. A known gamepad may use defaults; a radio may be unconfigured or use an older legacy mapping. Intentionally skipping Home preferences does not justify silently substituting controller calibration.

**Source.** [app_root.gd](../../../../app/app_root.gd), direct multirotor branch in `_ready`; [multirotor_scene.gd](../../../../app/vehicles/multirotor/multirotor_scene.gd), `_connect_selected_controller`; [multirotor_input.gd](../../../../app/input/multirotor_input.gd), `profiles_path`, `connect_first_device`; [controller_profile_store.gd](../../../../app/input/controller_profile_store.gd), `DEFAULT_PATH` and `LEGACY_PATH`.

**Repair and acceptance.** Initialize the same controller service for both routes, or make a deliberately isolated direct route reject saved-controller assumptions explicitly. Verify V2 axis mapping, inversion, throttle policy, deadzones and AUX match the interactive route; retain fail-closed behavior from A01.

### A05 — Direct gamepad menu navigation has no binding owner

AppRoot removes joypad UI events through `UiInput.isolate_joypads()` before its direct-route early return. The controller service normally installs the selected UI device, but is absent here. The quad's `_refresh_controller_ui()` is empty; handling Start to open a menu does not restore directional/accept/back bindings.

[direct_route.gd](repros/direct_route.gd) first installs synthetic gamepad UI mappings, enters the direct route, and verifies those mappings are gone. The device ID is an InputMap fixture, not an enumerated physical pad. The same no-op also means an in-activity UI-device change is not applied by this scene; that extension is source evidence.

**Source.** [app_root.gd](../../../../app/app_root.gd), initial joypad isolation and `_refresh_controller_ui`; [ui_input.gd](../../../../app/ui/ui_input.gd), `isolate_joypads`/`set_gamepad`; [multirotor_scene.gd](../../../../app/vehicles/multirotor/multirotor_scene.gd), `_refresh_controller_ui`.

**Repair and acceptance.** Use the shared UI-device ownership path in the quad and initialize it on direct entry. Verify a selected pad can open, navigate, activate and close the menu; another device must not acquire UI or flight authority accidentally. A04 and A05 share initialization work but affect distinct contracts and need separate acceptance checks.

### A19 — Matching gamepad arrival silently disarms the active source

**Added by the follow-up.** The original selected gamepad stays connected and selected when a second same-family device arrives. Registry ambiguity advances its generation, but the quad's selected-controller sync returns on equal numeric ID and leaves its verifier bound to the old generation. The next accepted activity tick is unready and disarms the motor without pausing; removing the duplicate does not restore verification.

**Evidence.** [duplicate_pad_scene.gd](experiments/duplicate_pad_scene.gd) exercises the real service hotplug/refresh, registry, input adapter and activity, with synthetic device enumeration and OS-focus/SDL confirmation. An injected keyboard action first arms the selected-pad session. A different-family device is a passing continuity control. All 12 observation checks pass. This is a software integration witness on the pad, not a physical-controller or airborne trajectory. [Detailed evidence and the additional constructed same-handle case](follow-up.md#a19-a-second-matching-pad-invalidates-the-active-verifier-without-a-hold) retain the reachability limits.

**Source.** [multirotor_scene.gd](../../../../app/vehicles/multirotor/multirotor_scene.gd), `_bind_gamepad_confirmation`, `_joy_connection_changed`, `_sync_selected_controller` and `_physics_process`; [controller_registry.gd](../../../../app/input/controller_registry.gd), ambiguity generation; [controller_service.gd](../../../../app/input/controller_service.gd), refresh and verification; [AppRoot](../../../../app/app_root.gd), active-activity automatic-selection and device-change wiring.

**Repair and acceptance.** Reconcile matching-evidence generations with actual physical continuity. Reverify an uninterrupted authority only under the shared profile/identity policy; otherwise hold and explain recovery before accepting an unready flight tick. Test duplicate arrival/removal, a different-family control, serial-qualified profiles, true identity replacement and same-handle reconnect. Do not treat every generation bump as either permission to reuse stale authority or an unexplained motor cut.

## Physics and data admission

### A06 — Full pack can accumulate charge above capacity

**Actual behavior.** The damped motor law can produce negative pack current. Charge integration has no upper-capacity bound, while SOC telemetry clamps to 1.0. Over-capacity state remains valid and consumed mAh becomes negative. The model also lacks a corresponding pack overvoltage/charge acceptance policy.

**Evidence.** [physics.gd](repros/physics.gd) supplies an admitted full-pack armed frame with 3,000 rad/s shafts. One accepted tick changes charge from **4,680 C to 4,680.126441782 C**, SOC stays **1.0**, and consumed charge is **−0.035122717 mAh**. Its initial evaluated bus is **26.208018 V** with **−33.600600 A** pack current. This first fixture is synthetic; it does not establish normal ground-start reachability.

The stronger [air_start_regen.gd](repros/air_start_regen.gd) uses the supported research/test `start="air"`, 20 m altitude and full SOC with the unmodified shipped document. It does not edit a frame. Initial shaft speed is **929.268985 rad/s**. One ready OFF tick consumes charge to **4,679.9975 C**; one zero-throttle ON tick raises it to **4,680.013055018 C**, with armed motors, SOC 1.0, negative consumed mAh and no fault. The normal player route starts on the pad; its reachability is still unproven.

**Source.** [controlled_plant.gd](../../../../app/physics/multirotor/controlled_plant.gd), `_evaluate`, charge derivative, SOC and `state_validator`; [session.gd](../../../../app/sim/multirotor/session.gd), `_start_frame`. [The plan's pack contract](../../../plans/drone-racing.md#44-four-motors-and-one-battery) already requires charge/overvoltage handling before signed current.

**Repair and acceptance.** Define a coherent charge acceptance, overvoltage and excess-energy/dissipation policy; do not merely clamp displayed SOC. Cover full/near-full pack braking, the supported air start, normal discharge, energy balance and boundary transitions.

### A07 — Rotor disc can intersect sloped ground without a strike

The rotor test chooses the disc point furthest down in world vertical, then samples terrain only there. On an incline, the point with greatest terrain penetration can be an uphill rim point instead. A level rotor is the simplest counterexample.

**Evidence.** [physics.gd](repros/physics.gd) uses the valid height-field contract `h(n,e)=0.5n`, shafts at 1,000 rad/s and a front hub 2 cm above its local terrain. The uphill rim penetrates by **0.012385 m**, the frame is accepted by the state validator, and `crash_reason` is empty. This is an already-overlapping component state, not a flown stock-field collision. A 0.5 slope is not categorically outside the RC overlay's ramp gradients, but no complete ramp trajectory was demonstrated.

**Source.** [controlled_plant.gd](../../../../app/physics/multirotor/controlled_plant.gd), rotor portion of `crash_reason`; [airfield_track.gd](../../../../app/physics/ground_vehicle/airfield_track.gd), terrain ramp construction. The miss exists at the sampled endpoint and is separate from the acknowledged lack of sub-tick impact location.

**Repair and acceptance.** Evaluate the rotor footprint against terrain using local surface orientation or a conservative height-field/disc intersection. Test uphill/cross-slope level discs, tilted discs on flat and sloped terrain, stopped props, and the shipped RC ramp environment. Preserve the distinction between collision geometry and measured physical airframe contact.

### A08 — Custom pack can pass hover admission despite an impossible power bound

The strict loader's hover checks evaluate motors at open-circuit voltage without solving the loaded shared pack. Battery resistance is admitted independently. It can therefore accept a document that its own electrical model cannot sustain in hover.

**Evidence.** [physics.gd](repros/physics.gd) changes only the shipped document's battery resistance from **0.03 Ω to 10 Ω**. Loading and preparation succeed. For a 25.2 V Thevenin source, maximum terminal power is `Voc²/(4R) = 15.876 W`. The admitted hover thrusts require approximately **77.365259 W** at the motor terminals before auxiliary load. An independent ideal equal-loading lower bound on propeller mechanical power is about **51.76 W**, already beyond the pack maximum. This is a custom-data validation failure; it says nothing adverse about the shipped 0.03 Ω pack's ability to hover.

**Source.** [multirotor_data.gd](../../../../app/physics/multirotor_data.gd), battery validation and hover feasibility/derived diagnostics; the electrical law and allocator use the loaded bus later.

**Repair and acceptance.** Solve equilibrium with the same coupled bus, motor and auxiliary-current law used by the plant, including the intended low-charge acceptance point. Reject infeasible packs with an explanatory error. Cover resistance, charge, auxiliary draw and actuator constraints without weakening current stock-document checks.

### A09 — Prepared-data path accepts negative drag

`Session.prepare()` accepts a prepared dictionary after shape/finite checks that do not enforce the strict loader's nonnegative drag invariant. The downstream plant uses the resulting coefficients directly.

**Evidence.** [physics.gd](repros/physics.gd) changes prepared `airframe.drag_areas_m2` to `[-1.0, 0.012, 0.020]`. Session preparation succeeds. A disarmed craft moving at 10 m/s receives **+61.25 N** in its direction of travel, adding **612.5 W** through the drag term. This is a deliberately tampered prepared-data/candidate path. The normal quad scene loads its catalog JSON through the stricter loader and does not reproduce this with shipped data.

**Source.** [session.gd](../../../../app/sim/multirotor/session.gd), prepared-data branch and `_prepared_shape_error`; [controlled_plant.gd](../../../../app/physics/multirotor/controlled_plant.gd), aerodynamic drag evaluation; [multirotor_scene.gd](../../../../app/vehicles/multirotor/multirotor_scene.gd), ordinary catalog data path.

**Repair and acceptance.** Share physical invariant validation between raw and prepared admission, including candidate replay. Negative drag must be rejected transactionally; finite/shape checks alone are insufficient. Verify raw/prepared parity and that refusals do not mutate an accepted session.

## Racing, result integrity and recovery

### A10 — Finish validity ignores collision-time uncertainty within a tick

The plant timestamps an obstacle crash at the end of the accepted physics tick, while the director interpolates a gate crossing inside that tick. A final crossing can therefore complete a valid race before the later-stamped crash, even when the model's collision proxy already intersected the gate before the crossing.

**Evidence.** [racing.gd](repros/racing.gd), `_finish_after_earlier_contact`, uses the real prepared course, obstacle query, plant `crash_reason` and race director. A synthetic 24 m/s chord starts clear of a gate box: clearance **0.168541212 m**, proxy radius **0.167950351 m**. Before reaching the gate plane it has clearance **0.167934928 m**, inside that proxy. The real detector reports `Obstacle strike`, yet the event sequence is `race_gate,race_lap,race_finish,crash` and the projected race result is valid.

This is a component counterexample, not a complete wrapped physics tick or a flown legal-race tape. The fixture supplies a qualified chord and final-lap director state. It establishes inconsistency with the simulator's conservative spherical collision predicate, not proven contact by a physical rotor/hull. The present endpoint event convention explains the result; the unresolved correctness issue is whether such an uncertain finish may be ranked as valid.

**Source.** [controlled_plant.gd](../../../../app/physics/multirotor/controlled_plant.gd), obstacle crash detection/event timestamp; [race_director.gd](../../../../app/sim/race/race_director.gd), event sorting and finish transition; [race_model.gd](../../../../app/sim/race/race_model.gd), wrapper/result projection.

**Repair and acceptance.** Locate the relevant impact or adopt a conservative same-tick finish validity rule with an explicit uncertainty interval. A microsecond tie tolerance cannot resolve a contact known only within a 1/240 s tick. Cover crashes before, at and after a last-gate crossing and retain a composed physics-tick/flight-tape regression before closing this issue.

### A11 — Full unsaved-result outbox cannot recover in the activity

The session correctly retains failed writes and refuses to start when eight results are pending. The scene retries saves only when another terminal result arrives. Once the outbox is full, new starts are refused, so that event-driven retry mechanism cannot produce another terminal attempt. Repairing storage alone does not release the block. The menu exposes no retry/discard action, and leaving the activity frees its session and pending outbox.

**Evidence.** [racing.gd](repros/racing.gd) creates real countdown/pad-reset aborts, directs saves to a deliberately blocked path and observes pending failures grow from 1 through 8. After repairing the directory, start is still refused. This reproduces the session and the activity's save-trigger pattern; it is not a complete UI disk-failure exercise. Earlier failures can retry on a later terminal result; the finding specifically concerns the full bound and exit handling.

**Source.** [session.gd](../../../../app/sim/multirotor/session.gd), `MAX_PENDING_RESULTS`, `save_results`, `tick_once`; [multirotor_scene.gd](../../../../app/vehicles/multirotor/multirotor_scene.gd), `_on_race_result`, start refusal message and Home action; [app_root.gd](../../../../app/app_root.gd), activity teardown.

**Repair and acceptance.** Add a bounded explicit retry/recovery path, retain pending records across teardown or require an informed discard decision, and report the actual storage/outbox problem instead of a generic return-to-pad hint. Verify intermittent failure, eight pending results, repaired storage, retry idempotence and Home/re-entry without silent loss.

### A12 — Result filename is not unique across sessions

Each session starts its result sequence at zero. A filename combines track ID, second-resolution UTC time and that per-session sequence. Two distinct sessions writing the same course/second/sequence receive the same target, which is replaced without checking the record's identity.

**Evidence.** [racing.gd](repros/racing.gd) prepares two actual sessions with different throttle-limit/controller identities and generates real countdown/reset aborts in the same second. Both report one successful save to the same filename; the second record replaces the first. This is credible for concurrent/batch sessions and rapid abort/restart workflows, not a claim that every normal-length race overwrites its predecessor. The diagnostic prints the filename and both payload identities when rerun; the portable summary records its successful observation.

**Source.** [session.gd](../../../../app/sim/multirotor/session.gd), `_result_sequence`, `_publish_result`, `save_results`.

**Repair and acceptance.** Assign a persistent globally unique attempt identity at publication, preserve it on retry and use no-clobber semantics or verify same-ID/same-content replacement. Test concurrent sessions, clock equality, retries, resets and restored envelopes. Timestamp precision alone is weaker than an actual identity contract.

### A13 — “Atomic” replacement deletes the previous file first

Both per-attempt `save_results` and record-book `save_file` flush a temporary file, explicitly remove an existing target, then rename the temporary file. Between removal and successful rename, the prior committed target is absent. A rename failure or process interruption can lose the last visible valid book/result; the temporary file is not automatically recovered by the loader.

**Evidence level.** Source-confirmed operation ordering. This audit did not inject an OS crash or cross-platform rename failure and does not claim such an event was observed. A12 separately demonstrates that the existing replacement is exercised for distinct attempt collisions. The record book normally uses replacement on each update.

**Source.** [session.gd](../../../../app/sim/multirotor/session.gd), `save_results`; [race_records.gd](../../../../app/vehicles/multirotor/race_records.gd), `save_file`.

**Repair and acceptance.** Use a platform-qualified atomic replacement primitive or a recoverable commit/backup protocol without an unprotected unlink gap. Test failure before and during commit, startup recovery and Windows/macOS/Linux behavior. Keep claims about crash durability separate from complete-file write and rename semantics.

### A14 — Pad-reset abort loses its original terminal context

`reset_to_pad` captures an in-progress attempt and changes its phase/reason strings, commits a new tick-zero simulation, and then publishes the old result. Publication reads the new `sim.tick`. The reason code is not changed alongside `reason="pad_reset"`.

**Evidence.** [racing.gd](repros/racing.gd) aborts a real countdown after tick 2. The result reports `terminal_tick=0`, `reason="pad_reset"`, and `reason_code=REASON_NONE`. This harms diagnostics/replay correlation even though the UI can display the reason string.

**Source.** [session.gd](../../../../app/sim/multirotor/session.gd), `reset_to_pad` and `_publish_result`; [race_director.gd](../../../../app/sim/race/race_director.gd), reason enumeration.

**Repair and acceptance.** Capture terminal metadata from the old accepted envelope before reset, and define an explicit consistent reset reason/code. Test countdown and active-race resets, nonzero ticks, partial laps and normal aborts.

### A15 — Course record identity omits resolved post solids

Track preparation uses local terrain heights to construct solid gate posts, but its course identity hashes the gate/pad geometry without those resolved frame boxes. Distinct physical courses can therefore share the record-book key.

**Evidence.** [racing.gd](repros/racing.gd) changes terrain by 0.2 m at one post with a synthetic discontinuous ground callable. The post changes from `down=-1.7, half_down=1.7` to `down=-1.8, half_down=1.6`; course identity is unchanged. The changed portion is below the aperture. No pair of shipped environments or actual conflated record was demonstrated.

Full session restore separately checks environment and collision identities. This is **not** evidence of bypassing that restore guard.

**Source.** [track.gd](../../../../app/sim/race/track.gd), frame construction and identity input; [race_records.gd](../../../../app/vehicles/multirotor/race_records.gd), course-keyed records; [session.gd](../../../../app/sim/multirotor/session.gd), restore identity guards.

**Repair and acceptance.** Include the authoritative resolved collision geometry, with a versioned identity contract, or explicitly define why some solids are excluded from ranked course equivalence. Verify unchanged-course stability and changed-solid separation with an admitted real environment fixture before elevating its practical severity.

### A16 — Empty record entry passes loading and fails on the next result

`RaceRecords._entry_is_valid` uses default values for missing fields, so a course entry `{}` is accepted with `dropped=0`. `apply` reuses that entry and directly accesses `best_total_s` and `best_lap_s`, which do not exist.

**Evidence.** [minor_findings.gd](repros/minor_findings.gd) writes a syntactically valid isolated book with an empty entry and verifies acceptance. Its explicitly flagged error mode calls the production `apply` method on that entry; the portable test matrix records the observed missing-key script error and checked-run rejection. This requires malformed saved data; no normal writer producing `{}` was found. The activity attempts the authoritative per-attempt save before applying the book, so do not infer automatic loss of that attempt file from this error.

**Source.** [race_records.gd](../../../../app/vehicles/multirotor/race_records.gd), `load_file`, `_entry_is_valid`, `apply`; [multirotor_scene.gd](../../../../app/vehicles/multirotor/multirotor_scene.gd), `_load_records`, `_on_race_result`.

**Repair and acceptance.** Require all fields consumed by `apply`, or normalize accepted entries into one complete canonical schema. Retain/set aside malformed source data according to the existing recovery policy. Test missing fields, wrong types and bounds, then ensure the next valid result updates the book and shows its card without a script error.

## Presentation and saved preferences

### A17 — Failed OSD preference save has no feedback

On the interactive route, the HUD updates its in-memory layout and calls `Osd.save_config`, but ignores the returned boolean. Cycling layout still flashes the new layout name. A later load restores the old value or default when the write failed.

**Evidence.** [minor_findings.gd](repros/minor_findings.gd) points settings at a unique nonexistent parent directory, verifies the save fails, changes Freestyle to Full, sees the ordinary layout message, then reloads Freestyle. No existing player preferences are touched. Direct-route in-memory-only OSD preferences are intentional and are not part of this finding.

**Source.** [multirotor_hud.gd](../../../../app/vehicles/multirotor/multirotor_hud.gd), `_apply_config`, `cycle_layout`; [osd_model.gd](../../../../app/vehicles/multirotor/osd_model.gd), `save_config`.

**Repair and acceptance.** Keep the usable in-session change but indicate it could not be saved, with a retry when appropriate. Cover layout, units and panel edits, successful persistence, blocked storage and the intentional in-memory route.

### A18 — Static Help panel does not follow explicit AUX ownership

The Help panel still advertises arm/disarm on E or gamepad LB and mode changes on M or RB, with legacy Landing gear wording. Explicit Arm and Flight mode AUX bindings disable those respective toggles, so following the help can have no effect. The header also assumes Mode 2 despite supported alternate mappings.

**Evidence.** [minor_findings.gd](repros/minor_findings.gd) reads the actual help text, creates a valid profile with both explicit AUX bindings, and confirms the advertised E/M toggles do not override them. The dynamic arming hint already uses binding metadata; the issue is limited to static help.

**Source.** [multirotor_hud.gd](../../../../app/vehicles/multirotor/multirotor_hud.gd), `HELP_LINES`, `_update_texts`; [multirotor_input.gd](../../../../app/input/multirotor_input.gd), `arm_aux`, `mode_from_switch`, `sample`.

**Repair and acceptance.** Generate relevant help from the active profile and source, including explicit AUX labels and the correct stick mode. Verify keyboard, default gamepad, Mode 1, calibrated radio and explicit/legacy AUX profiles, keeping the existing dynamic hints consistent.

## Missing features and qualification gaps

These are not additional newly reproduced bugs. They are declared limitations, incomplete workflows or acceptance evidence still needed, assessed against the [current plan](../../../plans/drone-racing.md) and runtime. The frozen [FPV proposal](../../../../FPV/00_START_HERE.md) is historical design input, not proof that implemented features are absent.

| Area | Gap and consequence | Required next evidence or delivery |
| --- | --- | --- |
| Selected-build physical fidelity | Mass/CG/inertia, thrust/torque/RPM/current and pack transient parameters remain partly derived, borrowed or estimated. Passing software tests cannot qualify the real assembly. | Selected-build measurements, uncertainty and held-out comparison under DR-40 physical validation. |
| Aerodynamics | The transparent rotor/load baseline does not establish descent/VRS, oblique-flow, propwash or ground-effect fidelity for racing maneuvers. | Qualified small-prop model and maneuver/envelope validation; do not add cosmetic shake as a substitute. |
| Powertrain limits | The present implementation does not establish physical ESC current limiting, thermal behavior, realistic charging/overvoltage or calibrated transient behavior. A06 exposes one concrete boundary defect. | Explicit bounded laws, energy accounting and selected-build comparison. |
| Controller realism | Acro/Angle, rate curves and software sample-rate qualification exist; sensor noise/delay and exact firmware/hardware equivalence are not established. | Measured latency and closed-loop responses, saturation and low-voltage recovery, justified modeled limits. |
| Impact timing | Strike, depletion and related cuts remain endpoint-resolution approximations. A07 is an endpoint geometry miss; A10 is a race-validity consequence of time uncertainty. | Located events or explicit conservative rules and timestep/convergence tests. |
| Native controllers | Real radio/gamepad mapping, hotplug/focus recovery and OS-specific acceptance remain open. Injected inputs do not replace them. | Native acceptance with actual supported devices after A01–A05 are corrected. |
| Performance and visuals | Prior plan evidence says the whole-step p95 target was exceeded on one PC. This audit performed no valid new target-hardware timing or screenshot qualification. A rendered launch was unavailable because this workspace has no display/Xvfb. | 1920×1080 first: frame pacing, latency, CPU/GPU cost, readability and edge-marker inspection on target hardware. |
| Player settings | The rates backend exists, but a complete rates/settings flow and 4:3 FPV presentation are absent from the accepted product slice. | Coherent user settings, persistence, input ownership and visual acceptance. |
| Course/rule breadth | Two local upright-gate courses exist. Tilted/dive gates, flags, published rule formats and a full course picker/editor remain open; federation compliance is not established. | Explicit supported geometry/rules and independent scoring cases for each new capability. |
| Replay user workflow | `.orfl` recording, exact and candidate replay are implemented and tested. No dedicated quad user-facing CLI/CSV inspection workflow is surfaced alongside the fixed-wing/blimp tools. | Expose and document a supported multirotor analysis/export path without duplicating replay logic. |
| Race/presentation expansion | Ghosts, richer four-motor audio, effects and broader capabilities remain deferred. | Product decision and delivery under the owning DR steps, not a claim of existing regression. |
| Documentation | ROADMAP still says there is no playable drone/race route. The current plan reuses DR-40 for both local records and selected-build physical validation. | Reconcile status and allocate unambiguous ownership IDs without rewriting dated evidence. |

### Policy questions deliberately not counted as confirmed bugs

- **Checkpoint rollback versus pending-result retention.** The racing probe demonstrates that restoring an older envelope replaces a newer pending outbox. An existing test explicitly expects whole-envelope rollback. Decide whether unsaved external results are session state or an independently retained publication queue before calling this an accidental defect. The stronger ordinary workflow failure is A11.
- **Pause and competition validity.** The proposal's practice/competitive distinctions do not establish the shipped local rule policy. Decide whether pausing changes eligibility or labeling; do not silently change it during a storage repair.
- **Crafted checkpoint chronology.** Structural validation is not automatically proof of impossible-history rejection. Stronger chronology/admissibility testing is warranted for imported race state, but no normal UI exploit or authoritative leaderboard exists here that was demonstrated by this audit.
- **Anti-windup at pre-allocation torque limits.** Source inspection suggests further closed-loop saturation/recovery coverage is useful. A held-state synthetic integration example alone is insufficient to establish a flyable maneuver defect, so it is not counted above.
- **Throttle-reset sampling.** Applying a reset and then integrating a nonzero input in the same tick can be a deliberate discrete-time convention. Clarify the command contract before treating it as a bug.

## Verification, reproduction and limitations

### Environment and identity

- Godot **4.8.beta2.official.cafc17a19**, Linux x86_64, headless/Dummy audio. The pinned binary was verified against the repository getter's SHA-512: `428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9`.
- Generated multirotor JSON SHA-256: `82f1ff64a572e8afd23c1cf84e824ee784bf7d04d5635ac18792001c3dbeeb62`; `research/drone-racing/openrc-fpv5-x1/derive.py --check` passed.
- Unchanged tracked production source at the audited commit; isolated checkout, profiles and result directories. Existing other worktrees were not modified. The test pool was unavailable because its host configuration was missing, so checks used the repository's local checked runner.
- Fresh import completed with zero errors and eight unrelated OBJ/PBR material warnings. One initial activity run was rejected because the sparse checkout lacked fixed-wing authoring files used by Home. After adding those tracked sources, the unchanged activity suite passed 96 checks with no diagnostics. This was an audit setup issue, not an FPV defect.
- An initial controls probe had two fixture-validation failures because its dictionary keys did not match the serialized profile form. It was corrected to string keys and rerun successfully. Both attempts are identified separately in the portable summary; only the reviewed run supports A02/A03.

### Running the probes

Use a disposable checkout at the baseline, a complete resource import, the repository's pinned Godot binary and isolated profiles. These scripts intentionally reproduce baseline defects and are kept outside `app/`; they must not become “green” desired-behavior regressions unchanged.

```sh
AUDIT_GODOT="$(app/get-godot.sh)"
AUDIT_DIR="$PWD/docs/research/drone-racing/audit-2026-11-16"
export XDG_DATA_HOME="$PWD/tmp/fpv-audit-repro/profile"
export OPENRC_RACE_AUDIT_DIR="$PWD/tmp/fpv-audit-repro/race-results"

python3 tools/godot/run_checked.py --label fpv-audit-import --timeout 480 -- \
  "$AUDIT_GODOT" --headless --path app --audio-driver Dummy --import

python3 tools/godot/run_checked.py --label fpv-audit-controls --timeout 120 -- \
  "$AUDIT_GODOT" --headless --path app --audio-driver Dummy \
  --script "$AUDIT_DIR/repros/controls.gd"
```

Run `physics.gd`, `racing.gd`, `profile_refusal.gd`, `direct_route.gd`, `air_start_regen.gd` and `minor_findings.gd` in the same way. `direct_route.gd` supplies `--multirotor=openrc-fpv5-x1` through AppRoot's `user_args` fixture itself; do not add another process argument. `racing.gd` refuses a missing isolation directory setting and creates a unique child; the filename case is time-dependent and reports inconclusive failure if it cannot align the records within its bounded attempts.

To intentionally reproduce A16's engine error, repeat `minor_findings.gd` with `OPENRC_AUDIT_EXPECT_SCRIPT_ERROR=1`. The checked runner **must reject** that run for the missing-key script error. Do not hide it by accepting the process's own exit code. The normal mode verifies the malformed entry's admission without invoking the error.

Raw engine logs and original runner reports contain workspace-specific metadata and are excluded from this published branch. [verification.json](evidence/verification.json) retains portable outcomes, source/engine identities, probe hashes and original-log hashes. [test-matrix.md](evidence/test-matrix.md) gives each suite, count and outcome; the supplied probes reproduce the diagnostic observations on the pinned baseline. [ui-smoke.md](evidence/ui-smoke.md) records the live headless Home → quad → course/OSD → race → reset → Home inspection. No screenshot or actual controller input is implied by that smoke test.

### What the passing coverage establishes

The selected suites cover data, allocation/rates, shared electrical bus, controlled plant, sample-rate and fast-path comparisons, session/frame/log replay, input/AUX, gate/track/director/model scoring, records, complete scripted races and exact race replay, kernel integration, camera, OSD, visual structure and activity/controller lifecycle. This is substantial positive evidence that the implemented baseline works within its tested conditions; the edge cases above demonstrate why aggregate passing counts are insufficient for qualification.

The full repository suite, required CI status, all supported OSes, physical radios, native 1080p rendering, meaningful performance measurements, long endurance campaigns and real-world flight measurements were not completed here. Existing dated native captures and measurements remain historical evidence; this audit does not re-certify them.

## Recommended repair order and closure criteria

The sequence below records the original audit recommendation. The [current programme](../../../plans/drone-racing.md#16-audit-remediation-programme-2026-11-16) refines it with explicit alternatives, dependencies and closure tests; the follow-up now includes the real composed A10 tick, still from an initialized state.

1. **Controller authority:** A01–A03 first. Preserve source validity and single-owner bindings, then define ordinary pause versus recovery. Close only with scene-level negative and positive controls, followed by a real-radio/gamepad session.
2. **Route parity:** A04–A05. Share controller and UI ownership initialization; verify direct and Home routes use the same intended configuration without weakening refusal behavior.
3. **Result retention:** A11–A13 and A16. Establish stable attempt identity, durable recovery and safe replacement. Test transient failures, full outbox, same-second sessions and malformed books before adding more ranking features.
4. **Physics boundaries:** A06–A09. Define admissible electrical/terrain/data domains, then use independent physical bounds and energy checks. Keep synthetic, research-air-start and stock-pad evidence separately labeled.
5. **Scoring and metadata:** A10, A14–A15. Resolve collision-time uncertainty, retain the old attempt's terminal context and define course identity. A10 requires a composed tick/tape check to complement its current component witness.
6. **Pilot communication:** A17–A18 and stale status documentation. Make current ownership and persistence visible, then complete the native and physical qualification gaps before expanding realism claims.

For every repair, first convert the relevant diagnostic observation into a desired-behavior regression that fails on this baseline. Run the affected existing suites through the checked runner, retain the same identity/provenance discipline without publishing host metadata, and update this audit by linking the repair commit and its evidence rather than changing the dated baseline findings.
