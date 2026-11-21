# Controls acceptance matrix

Generated from [control-cases.json](control-cases.json) by [verify_plan.py](../../../research/vehicle-runtime-consolidation/verify_plan.py) with `--write-matrix`. Edit the JSON, then regenerate. This is a proposed case ledger, not executed gameplay evidence.

The [control contract](CONTROL-CONTRACT.md) defines semantics; [quality gates](QUALITY-GATES.md) define admission, identities and receipts. Apply cases only to their touched seams or claimed release scope. Existing suites are starting points and may need extensions; their names do not prove case coverage. All cases in this audit revision are **UNRUN**, with no passing runtime receipt.

| Case | Obligation | VRC steps | Evidence level |
| --- | --- | --- | --- |
| [C01](#c01) | Stale connection cannot authorize resume | VRC-01, VRC-03, VRC-04, VRC-05 | synthetic real-consumer integration |
| [C02](#c02) | Relevant profile change invalidates stale permission | VRC-01, VRC-03, VRC-04, VRC-05 | synthetic integration |
| [C03](#c03) | Retired activity rejects late work | VRC-01, VRC-04, VRC-05, VRC-07, VRC-08 | synthetic real-owner integration |
| [C04](#c04) | Independent holds and explicit player intent | VRC-01, VRC-04, VRC-05 | synthetic real-consumer integration |
| [C05](#c05) | Verified gamepad readiness stays immediate | VRC-03, VRC-04, VRC-05 | synthetic integration |
| [C06](#c06) | Radio evidence survives correct temporal boundaries | VRC-03, VRC-04, VRC-05 | synthetic integration |
| [C07](#c07) | Held menu keys cannot become flight axes | VRC-03, VRC-04, VRC-08 | synthetic real-shell integration |
| [C08](#c08) | Capture owns binding and release | VRC-03, VRC-04, VRC-08 | synthetic UI integration |
| [C09](#c09) | Text input and action edges remain separate | VRC-03, VRC-04, VRC-08 | synthetic UI integration |
| [C10](#c10) | Admitted quad Pause reaches the real consumer | VRC-03, VRC-05 | synthetic real-activity integration |
| [C11](#c11) | Airship native menu map follows the UI role | VRC-03, VRC-05 | synthetic mapping plus rendered integration |
| [C12](#c12) | Uncached airship profile refusal can recover explicitly | VRC-03, VRC-05 | synthetic real-activity integration |
| [C13](#c13) | Legacy concurrent saves retain acknowledged updates | VRC-02, VRC-03 | multiprocess software fault injection |
| [C14](#c14) | Every admitted range has truthful endpoints | VRC-03 | boundary-value software integration |
| [C15](#c15) | Shaping, rates and trims keep their order | VRC-03, VRC-08, VRC-09 | numerical input-path integration |
| [C16](#c16) | Quad frame sampling and curve ownership stay distinct | VRC-03, VRC-05, VRC-09 | kernel/input integration |
| [C17](#c17) | Quad fallback remains held with correct recovery | VRC-03, VRC-05 | synthetic activity and rendered qualification |
| [C18](#c18) | AUX no-command preserves owned targets | VRC-03, VRC-04, VRC-09 | synthetic command-path integration |
| [C19](#c19) | Hold sampling does not drift virtual throttle | VRC-03, VRC-04, VRC-05, VRC-09 | synthetic temporal integration |
| [C20](#c20) | Invalid samples fail through the owning safety gate | VRC-03, VRC-05, VRC-09 | software fault injection |
| [C21](#c21) | Save and activation report the route's true result | VRC-02, VRC-03, VRC-08 | software storage/activation integration |
| [C22](#c22) | Storage interruption does not invent defaults or success | VRC-03 | software persistence fault injection |
| [C23](#c23) | Restart and rollback retain usable player profiles | VRC-03, VRC-10, VRC-11 | software restart and package compatibility |
| [C24](#c24) | Managed, direct and trial routes remain explicit | VRC-00, VRC-03, VRC-04, VRC-05 | route inventory and integration |
| [C25](#c25) | First post-gap tick is observed before policy changes | VRC-03, VRC-05, VRC-09 | software investigation; native qualification separate |
| [C26](#c26) | RF loss and USB removal are qualified separately | VRC-11 | physical device qualification |
| [C27](#c27) | Fixed-wing refusal and committed faults remain distinct | VRC-02, VRC-07 | transaction fault injection |
| [C28](#c28) | Other families do not inherit a false reset guarantee | VRC-05, VRC-07 | family-specific transaction characterization |
| [C29](#c29) | Exit and tentative detach preserve owned data | VRC-02, VRC-05, VRC-07 | lifecycle fault injection and integration |
| [C30](#c30) | Detached status is truthful and cannot mutate authority | VRC-01, VRC-04, VRC-05, VRC-08 | projection contract and UI integration |
| [C31](#c31) | Replay respects source identity and candidate limits | VRC-00, VRC-02, VRC-03, VRC-06, VRC-07, VRC-09, VRC-11 | owned replay workflow; execution pending |
| [C32](#c32) | Actual native execution is qualified separately | VRC-02, VRC-05, VRC-06, VRC-09, VRC-11 | native/reference and platform qualification |
| [C33](#c33) | Primary gamepad player flow remains usable | VRC-04, VRC-05, VRC-08, VRC-11 | rendered player-flow qualification |
| [C34](#c34) | Verified radio menus preserve center and command evidence | VRC-03, VRC-04, VRC-05, VRC-11 | synthetic route plus physical qualification |
| [C35](#c35) | Device and transport fault cycles match the claim | VRC-11 | physical device and OS qualification |
| [C36](#c36) | Input optimization does not add hidden delay | VRC-03, VRC-08, VRC-09, VRC-11 | software performance; physical latency separate |
| [C37](#c37) | Lifecycle repetition exposes retained resources | VRC-07, VRC-08, VRC-09, VRC-11 | lifecycle integration and target-host soak |
| [C38](#c38) | Exported controls evidence binds to the actual package | VRC-10, VRC-11 | exported-package qualification |
| [C39](#c39) | Usability and accessibility claims remain truthful | VRC-04, VRC-08, VRC-11 | rendered accessibility and human usability |
| [C40](#c40) | Adversarial transition sequences retain invariant oracles | VRC-03, VRC-04, VRC-05, VRC-11 | proposed stateful integration extension |

## C01

**Stale connection cannot authorize resume.** Owners: F3-GP-02, UI, affected family. Apply when: Selection, status, intent dispatch or resume ownership changes.

- **Fixture and trigger:** With a real affected shell/activity and valid profile, display ready; disconnect, reuse the numeric handle or select a different source before dispatching the old resume intent.
- **Required outcome:** The owner revalidates the current connection/generation and full family gate. Stale evidence grants no accepted tick/action. Existing guarded recovery remains available; no adapter cache supplies authority.
- **Existing test starting points:** [test_controller_registry.gd](../../../app/tests/test_controller_registry.gd), [test_controller_audit_identity.gd](../../../app/tests/test_controller_audit_identity.gd), [test_controller_pause_recovery.gd](../../../app/tests/test_controller_pause_recovery.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Record old/current source identity, actual dispatch chain, pause/hold state and first accepted command or its absence. Status: **UNRUN**; receipt: none.

## C02

**Relevant profile change invalidates stale permission.** Owners: D6-GP-02, F3-GP-02, UI. Apply when: Profile activation, readiness projection or queued intents change.

- **Fixture and trigger:** Capture ready status, then successfully change a relevant mapping/action/calibration or role before Continue. Separately inject a failed managed Save that retains the previous profile.
- **Required outcome:** Dispatch validates the actual accepted profile and applicable readiness. A successful relevant change cannot reuse stale evidence; a failed managed Save does not invent a new active profile. Harmless fields need not invalidate unrelated state.
- **Existing test starting points:** [test_controller_settings_save.gd](../../../app/tests/test_controller_settings_save.gd), [test_radio_menu_service.gd](../../../app/tests/test_radio_menu_service.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Accepted profile/mapping identities and observed gate/refusal; no new universal revision mechanism is presumed. Status: **UNRUN**; receipt: none.

## C03

**Retired activity rejects late work.** Owners: UI, family lifecycle. Apply when: Bridge listeners, async/deferred work or activity replacement changes.

- **Fixture and trigger:** Queue status/resume/profile/load completion for activity A; cancel or replace it with B before completion. Repeat unsubscribe/dispose and deliver a late callback.
- **Required outcome:** Late work cannot resume, mutate, close recorders or clear listeners belonging to B. The original job retains safe retirement ownership; repeat cleanup is limited to owned resources.
- **Existing test starting points:** [test_flight_session_staged.gd](../../../app/tests/test_flight_session_staged.gd), [test_ui_screen_stack.gd](../../../app/tests/test_ui_screen_stack.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Activity identity, queued/completed operation order, listener counts and actual state/recording outcomes; extend beyond existing fixtures where absent. Status: **UNRUN**; receipt: none.

## C04

**Independent holds and explicit player intent.** Owners: UI, F3-GP-02, family sessions. Apply when: Pause/resume or launch/restart consumers move.

- **Fixture and trigger:** Combine menu with controller-loss/calibration/fault holds; clear only the menu hold. Separately run ready Home Fly and guarded restart through their current shell routes.
- **Required outcome:** Remaining holds prevent unauthorized progress and expose their recovery reason. Preserve owner ordering and existing Fly/restart intent; do not force an extra Continue on already-admitted launch or auto-resume after loss.
- **Existing test starting points:** [test_controller_pause_recovery.gd](../../../app/tests/test_controller_pause_recovery.gd), [test_controller_recovery_focus.gd](../../../app/tests/test_controller_recovery_focus.gd), [test_ui_screen_stack.gd](../../../app/tests/test_ui_screen_stack.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Active hold set, shell screen identity, operation result and first tick; test actual shell plus session. Status: **UNRUN**; receipt: none.

## C05

**Verified gamepad readiness stays immediate.** Owners: F3-GP-02, D6-GP-03. Apply when: Trusted connection, polling or readiness changes.

- **Fixture and trigger:** Use a verified standard gamepad fixture and its first valid trusted poll without prior motion/neutral dwell. Compare a distinct unverified/raw fixture and applicable managed/direct routes.
- **Required outcome:** Verified pad readiness retains its existing first-valid-poll behavior without new dwell or motion gesture; invalid/unverified evidence is not elevated. Continue/launch admission still follows the owning activity.
- **Existing test starting points:** [test_controller_pause_recovery.gd](../../../app/tests/test_controller_pause_recovery.gd), [test_controller_integration.gd](../../../app/tests/test_controller_integration.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Fixture trust identity, poll/readiness trace and actual gate; do not generalize raw-fixture neutral-dwell tests. Status: **UNRUN**; receipt: none.

## C06

**Radio evidence survives correct temporal boundaries.** Owners: D6-GP-02, F3-GP-02, UI-12-GP-02. Apply when: Radio polling, action edges, focus/reconnect or verification integration changes.

- **Fixture and trigger:** Hold ON or throttle raised before selection/reconnect/focus recovery; inject ordinary polled zeros, unrelated events, then the applicable real LOW/OFF/center evidence. Separately exercise a completed same-generation verification challenge seed.
- **Required outcome:** Ordinary unverified polls do not fabricate required recovery evidence; edge actions need the owning OFF/ON policy. Preserve the trusted finite center/OFF verification seed and separate raw-radio LOW evidence.
- **Existing test starting points:** [test_rc_input.gd](../../../app/tests/test_rc_input.gd), [test_controller_edge_continuity.gd](../../../app/tests/test_controller_edge_continuity.gd), [test_radio_menu.gd](../../../app/tests/test_radio_menu.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Event/poll origin, generation, verification proof, edge transitions and first accepted command, including near-threshold jitter. Status: **UNRUN**; receipt: none.

## C07

**Held menu keys cannot become flight axes.** Owners: UI-12, D6, fixed-wing shell. Apply when: Keyboard polling, pause exit or held-key masks move.

- **Fixture and trigger:** Select Continue with Down still physically held; observe first flight poll/tick, then release and press again. Hold an independent second axis and compare positional radio sticks.
- **Required outcome:** Down cannot become pitch until its owning per-axis mask sees release; a new press works. Other axes retain independent mask behavior and radio positional inputs are not keyboard-masked.
- **Existing test starting points:** [test_controller_routing_audit.gd](../../../app/tests/test_controller_routing_audit.gd), [test_e2e_input.gd](../../../app/tests/test_e2e_input.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Actual shell close-pause ordering, global key poll, masked command and first accepted tick; event consumption alone is insufficient. Status: **UNRUN**; receipt: none.

## C08

**Capture owns binding and release.** Owners: UI-15-GP-01, D6. Apply when: Capture, selected-device leases or focus handoff changes.

- **Fixture and trigger:** Capture an assigned Pause/Back using the selected controller or supported keyboard; send a foreign-controller event and the matching release; cancel or lose the connection while the draft is dirty.
- **Required outcome:** Supported keyboard/selected-device capture works; foreign devices cannot bind. Matching release cannot escape into navigation/flight. Cancellation/loss restores the documented focus/draft state without silently saving or discarding unrelated edits.
- **Existing test starting points:** [test_controller_setup_safety.gd](../../../app/tests/test_controller_setup_safety.gd), [test_controller_capture_scroll.gd](../../../app/tests/test_controller_capture_scroll.gd), [test_controller_audit_setup.gd](../../../app/tests/test_controller_audit_setup.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Capture owner, selected generation, draft before/after, consumed release and absence of unintended activity action. Status: **UNRUN**; receipt: none.

## C09

**Text input and action edges remain separate.** Owners: UI-12, UI-15, action owners. Apply when: Keyboard shortcuts, text focus or action dispatch moves.

- **Fixture and trigger:** Type a remapped Back chord in an editable field, exercise explicit Escape, repeat keydown and simultaneous modifier release, then perform the same shortcut outside text/capture.
- **Required outcome:** Typing is not navigation or flight action; documented Escape recovery remains. Edge actions dispatch once under the actual chord/repeat policy and work in their supported non-text context.
- **Existing test starting points:** [test_controller_binding_audit.gd](../../../app/tests/test_controller_binding_audit.gd), [test_controller_routing_audit.gd](../../../app/tests/test_controller_routing_audit.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Focused widget, consumed events, action count and visible recovery; fixed keyboard axes do not imply full keyboard remapping. Status: **UNRUN**; receipt: none.

## C10

**Admitted quad Pause reaches the real consumer.** Owners: DR-14, DR-16, UI-15-GP-01. Apply when: Quad or shared action admission/dispatch changes.

- **Fixture and trigger:** For each retained supported radio button, learned-axis or custom-key Pause form, validate and save/activate, then exercise applicable OFF/press/release through the real activity; otherwise verify explicit refusal/disable before Save. Retest P/Escape and the existing pad route.
- **Required outcome:** Every presented supported form actually pauses; otherwise assignment is refused before misleading success. Foreign/stale sources and held/repeat events cannot trigger extra actions. Resume retains quad readiness and arm/rate policy.
- **Existing test starting points:** [test_controller_actions.gd](../../../app/tests/test_controller_actions.gd), [test_controller_audit_vehicle_quad.gd](../../../app/tests/test_controller_audit_vehicle_quad.gd), [test_mr_controller_authority.gd](../../../app/tests/test_mr_controller_authority.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Setup-to-activity integration witness with selected binding, action count and session pause; input/plant-only fixtures are insufficient. Status: **UNRUN**; receipt: none.
- **Known baseline:** GCA-01; reproduce separately, then assert the repaired oracle.

## C11

**Airship native menu map follows the UI role.** Owners: BL-10, BL-12, UI-12-GP-01, F3-GP-02. Apply when: Airship menu/role mapping or shared native mapping changes.

- **Fixture and trigger:** Lose UI role, reuse its old handle without selecting it and verify clearing; then select a different handle, change eligibility/binding and select keyboard-only. Separately intentionally select an eligible reused handle. Exercise the real callback chain.
- **Required outcome:** Unselected reused-handle events cannot use a stale map; when a different handle is selected only that role's map matches. Intentional selection of the reused handle rebuilds its current eligible role/profile mapping and works. InputMap matching alone cannot distinguish physical generations sharing one number. Flight role stays unchanged; qualify focusable HUD separately.
- **Existing test starting points:** [test_controller_audit_vehicle_airship.gd](../../../app/tests/test_controller_audit_vehicle_airship.gd), [test_airship_activity.gd](../../../app/tests/test_airship_activity.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** InputMap before/after and actual native HUD focus/action; physical reused-device behavior is a separate row. Status: **UNRUN**; receipt: none.
- **Known baseline:** GCA-02; reproduce separately, then assert the repaired oracle.

## C12

**Uncached airship profile refusal can recover explicitly.** Owners: BL-10, F3-GP-02, D6-GP-02. Apply when: Airship resume/profile resolution or shared recovery changes.

- **Fixture and trigger:** Hold the V2 store lease from another instance before fresh uncached selected connection; refuse lookup, release contention, then choose Continue on the same connection. Also retain busy/corrupt/ambiguous and stale-selection variants.
- **Required outcome:** Release alone never resumes. Explicit recovery re-resolves current ownership and proceeds only through live armed/low-throttle/centered-yaw gates. Repeated refusal stays held with reachable recovery; a cached success remains distinct.
- **Existing test starting points:** [test_controller_audit_vehicle_airship.gd](../../../app/tests/test_controller_audit_vehicle_airship.gd), [test_airship_activity.gd](../../../app/tests/test_airship_activity.gd), [test_controller_store.gd](../../../app/tests/test_controller_store.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Lease, resolver call, current generation/profile, actual Continue gate and HUD outcome. Do not invent an airship Controls button. Status: **UNRUN**; receipt: none.
- **Known baseline:** GCA-03; reproduce separately, then assert the repaired oracle.

## C13

**Legacy concurrent saves retain acknowledged updates.** Owners: D6-GP-02, fixed-wing calibration, HELI, AUX persistence. Apply when: Legacy calibration/smoke writer, caller or storage transaction moves.

- **Fixture and trigger:** Two processes load the same seeded legacy file; schedule competing different-device, same-device and calibration-versus-smoke writes using a barrier only in an identified disposable source copy.
- **Required outcome:** After repair, acknowledged updates survive under the documented merge policy or explicit contention/retry is returned. Unrelated sections remain. Failed publication does not falsely acknowledge success; V2 concurrency remains separately intact.
- **Existing test starting points:** [test_rc_calibration.gd](../../../app/tests/test_rc_calibration.gd), [test_controller_audit_concurrency.gd](../../../app/tests/test_controller_audit_concurrency.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Process schedule/instrumentation hashes, responses and unmodified-reader results. Existing V2 concurrency tests alone do not cover legacy; no power-loss durability claim. Status: **UNRUN**; receipt: none.
- **Known baseline:** GCA-04; reproduce separately, then assert the repaired oracle.

## C14

**Every admitted range has truthful endpoints.** Owners: D6-GP-02, D6-GP-03. Apply when: Profile validation, normalization, import or readiness changes.

- **Fixture and trigger:** Use external absolute and signed profiles below/at/above the chosen minimum-span contract, including 5e-7 historical witness, off-center sides and inversion; save/reload/import and poll real readers.
- **Required outcome:** Endpoints produce documented finite full/idle commands or activation refuses with a field-specific error. No admitted misleading idle/readiness. Ordinary calibrated profiles and recoverable files remain intact; tiny wizard-unreachable inputs are not generalized to all pilots.
- **Existing test starting points:** [test_controller_profile.gd](../../../app/tests/test_controller_profile.gd), [test_controller_profile_hardening.gd](../../../app/tests/test_controller_profile_hardening.gd), [test_rc_input.gd](../../../app/tests/test_rc_input.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Exact profile bytes, admitted/refused result, endpoint outputs and distinct gamepad/radio LOW behavior. Status: **UNRUN**; receipt: none.
- **Known baseline:** GCA-05; reproduce separately, then assert the repaired oracle.

## C15

**Shaping, rates and trims keep their order.** Owners: D6-GP-03, fixed-wing controls, UI preview. Apply when: Conditioning, preview data, rate selection or tick input changes.

- **Fixture and trigger:** Use declared nonzero raw samples and independently computed expected values for Mode 1/2, offset/inverted calibration, transmitter versus simulator rates, pad expo, airplane normal/sport rates and retained trims. Include absolute-trigger endpoints and both triggers.
- **Required outcome:** Each stage applies its owned transform exactly as characterized; no double expo or lost trim. Preview describes its actual stage, absolute throttle retains direct normalization and hold paths do not integrate rate throttle. Do not impose airplane curves on quad.
- **Existing test starting points:** [test_controller_profile.gd](../../../app/tests/test_controller_profile.gd), [test_controller_rates.gd](../../../app/tests/test_controller_rates.gd), [test_controller_conditioning.gd](../../../app/tests/test_controller_conditioning.gd), [test_controller_flap_mix_profile.gd](../../../app/tests/test_controller_flap_mix_profile.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Raw/profile/conditioned/session/accepted-command values, justified numerical tolerance and stage labels; add actual consumer witness if absent. Status: **UNRUN**; receipt: none.

## C16

**Quad frame sampling and curve ownership stay distinct.** Owners: DR, SF, D6. Apply when: Shared input sampling or quad adapter/FC boundary changes.

- **Fixture and trigger:** Feed identical pre-expo pilot frames through the real quad path, including stages within one tick and held/recovery intervals; compare accepted FC state/input before and after extraction.
- **Required outcome:** FC sample remains once per tick under the existing framed-sampled protocol; stage evaluation does not resample or reapply airplane shaping. Checkpointed controller memory and accepted commands remain identical where guaranteed.
- **Existing test starting points:** [test_dr_multirotor_kernel.gd](../../../app/tests/test_dr_multirotor_kernel.gd), [test_controller_audit_vehicle_quad.gd](../../../app/tests/test_controller_audit_vehicle_quad.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Pilot frame, sampling count, stage calls, accepted memory and checkpoint identity; actual backend scope stated. Status: **UNRUN**; receipt: none.

## C17

**Quad fallback remains held with correct recovery.** Owners: DR-14, DR-16, F3-GP-02, UI. Apply when: Quad source selection, focus recovery or Continue changes.

- **Fixture and trigger:** Compare ordinary same-source pause with focus/source loss while another controller, including radio/unknown kind, remains connected. Observe automatic fallback, paused stored motor state, Continue and first resumed tick.
- **Required outcome:** Fallback does not auto-resume and invalidates arm continuity. Preserve ordinary frozen rate throttle versus source/focus recovery reset/disarm. Identify the replacement source before Continue as an explicit owner-qualified GCA-G3 acceptance; do not silently change paused stored-frame semantics.
- **Existing test starting points:** [test_mr_controller_authority.gd](../../../app/tests/test_mr_controller_authority.gd), [test_controller_audit_vehicle_quad.gd](../../../app/tests/test_controller_audit_vehicle_quad.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Selected source/generation, display, pause/arm state before and after first tick; any UI/policy repair is separate behavior work. Status: **UNRUN**; receipt: none.
- **Known baseline:** GCA-G3; reproduce separately, then assert the repaired oracle.

## C18

**AUX no-command preserves owned targets.** Owners: D6-GP-06, aircraft equipment, UI. Apply when: AUX sampling, hold/rearm or command reuse changes.

- **Fixture and trigger:** Set bound flap/gear targets, enter menu/focus/source holds, poll unarmed axis/button bindings, then send applicable fresh OFF and ON. Include smoke separately.
- **Required outcome:** Unarmed bound AUX is no command, not zero/retract. Existing flap/gear targets and actuator continuity remain; smoke follows its separate off-at-boundary policy. Rearming cannot invent an extra edge.
- **Existing test starting points:** [test_aux_pause_retention.gd](../../../app/tests/test_aux_pause_retention.gd), [test_controller_aux_runtime.gd](../../../app/tests/test_controller_aux_runtime.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Validity flags, requested targets, accepted inputs and actuator state with axis/button variants. Status: **UNRUN**; receipt: none.

## C19

**Hold sampling does not drift virtual throttle.** Owners: D6, affected family. Apply when: Polling, virtual throttle or pause/resume ordering changes.

- **Fixture and trigger:** Where the family has rate throttle, hold a nonzero rate stick through ordinary pause and repeated nonintegrating samples, then resume through the proper owner; separately test refused/faulted tick boundaries.
- **Required outcome:** The held value follows the existing family policy without menu drift or duplicate integration. Characterize pre-tick input accumulator behavior under refusal/fault; do not invent universal rollback with physical state.
- **Existing test starting points:** [test_controller_pause_recovery.gd](../../../app/tests/test_controller_pause_recovery.gd), [test_rc_input.gd](../../../app/tests/test_rc_input.gd), [test_controller_audit_vehicle_quad.gd](../../../app/tests/test_controller_audit_vehicle_quad.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Accumulator and sample sequence, integrate flag, hold value and first accepted command; preserved family exceptions named. Status: **UNRUN**; receipt: none.

## C20

**Invalid samples fail through the owning safety gate.** Owners: D6-GP-02, F3-GP-02, family input. Apply when: Validation, sampling reuse or controller readiness changes.

- **Fixture and trigger:** Inject NaN/Inf, an absent or invalid reader callable, invalid profile axis indices and known ownership loss; include held unbound buttons where they affect existing edge readiness. Distinguish these observable failures from a physically absent axis reported as zero.
- **Required outcome:** Failures exposed by the validated reader/profile contract cannot become trusted readiness or retain stale authority. Preserve the family's fail-safe/hold and bounds/finite validation across cached/live paths. Do not invent missing-channel detection where the API returns ordinary zero; hardware counts/trigger independence remain separately qualified.
- **Existing test starting points:** [test_controller_profile_hardening.gd](../../../app/tests/test_controller_profile_hardening.gd), [test_rc_input.gd](../../../app/tests/test_rc_input.gd), [test_controller_external_audit.gd](../../../app/tests/test_controller_external_audit.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Injected sample/profile bytes, rejection reason, current readiness and accepted-command absence or documented safe fallback. Status: **UNRUN**; receipt: none.

## C21

**Save and activation report the route's true result.** Owners: D6-GP-02, UI-15-GP-01, fixed-wing, HELI. Apply when: Setup Save/apply, calibration completion or persistence callbacks move.

- **Fixture and trigger:** Inject managed V2 store/preflight/activation failure and compare the prior accepted profile. Separately fail a direct fixed-wing/heli legacy save after calibration has activated in memory.
- **Required outcome:** Managed transaction retains its documented rollback. Direct legacy may remain active but NOT saved; communicate that truth and preserve existing recovery. Do not claim durable success or universal activation rollback; a stronger guarantee is separate behavior work.
- **Existing test starting points:** [test_controller_settings_save.gd](../../../app/tests/test_controller_settings_save.gd), [test_controller_calibration_session.gd](../../../app/tests/test_controller_calibration_session.gd), [test_controller_calibration_disclosure.gd](../../../app/tests/test_controller_calibration_disclosure.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Before/after file and active profile, response/HUD message, draft state and subsequent restart result. Status: **UNRUN**; receipt: none.

## C22

**Storage interruption does not invent defaults or success.** Owners: D6-GP-02, profile storage. Apply when: Store admission/publication/locking or migration changes.

- **Fixture and trigger:** Exercise corrupt/unreadable input, denied write, interrupted publication/lock ownership and competing reader with fresh isolated files; distinguish V2 and legacy contracts.
- **Required outcome:** Managed V2 corrupt/unreadable stores remain errors and legacy writers do not overwrite unreadable input. Characterize direct legacy load_profile, which can return an empty result for absent or unreadable input; stronger reader discrimination is separate behavior work. Acknowledgement/recovery follows its route, with no unbounded tick-path retry or unproved power-loss guarantee.
- **Existing test starting points:** [test_controller_store.gd](../../../app/tests/test_controller_store.gd), [test_controller_persistence.gd](../../../app/tests/test_controller_persistence.gd), [test_controller_audit_concurrency.gd](../../../app/tests/test_controller_audit_concurrency.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Fault schedule, file/lock state, error/result, recovered profile and storage-contract limitation. Status: **UNRUN**; receipt: none.

## C23

**Restart and rollback retain usable player profiles.** Owners: D6-GP-02, UI, DT. Apply when: Profile compatibility, default interpretation or release rollback is affected.

- **Fixture and trigger:** Start with copied accepted profiles and menu preference; save supported edits, restart candidate, then reopen under retained baseline build. Cover legacy import and ambiguous/reused device identities.
- **Required outcome:** Structural PRs preserve schema, acknowledged overrides and documented selection semantics. No persisted numeric handle is treated as stable identity. A version change requires explicit migration/rollback proof rather than assumed source revert.
- **Existing test starting points:** [test_controller_persistence.gd](../../../app/tests/test_controller_persistence.gd), [test_controller_profile_creation.gd](../../../app/tests/test_controller_profile_creation.gd), [test_controller_auto_defaults.gd](../../../app/tests/test_controller_auto_defaults.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Build/profile bytes, launch logs, selected roles and recovered user-visible settings; original player files remain protected. Status: **UNRUN**; receipt: none.

## C24

**Managed, direct and trial routes remain explicit.** Owners: UI, D6, family route owners. Apply when: A launch route or common service dependency changes.

- **Fixture and trigger:** Inventory and execute the affected supported Home, direct-launch and Workshop-trial routes with declared keyboard, verified pad or radio profile; include standalone/external-driver no-input mode where supported.
- **Required outcome:** No mandatory service breaks an intentional service-free route. Home preferences and direct legacy/profile behavior retain their declared scope. Unsupported menu/binding combinations are labeled before use, not inferred from another activity's pass.
- **Existing test starting points:** [test_controller_integration.gd](../../../app/tests/test_controller_integration.gd), [test_controller_audit_shell.gd](../../../app/tests/test_controller_audit_shell.gd), [test_airship_activity.gd](../../../app/tests/test_airship_activity.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Actual route/catalog/launch flags, services present, profile resolver, offered controls and first accepted command; matrix exclusions explained. Status: **UNRUN**; receipt: none.
- **Known baseline:** GCA-G2; reproduce separately, then assert the repaired oracle.

## C25

**First post-gap tick is observed before policy changes.** Owners: F3-GP-02, DR, BL, RCV, fixed-wing/HELI. Apply when: Scheduling or gap/focus/recovery behavior moves; not an unrelated status projection.

- **Fixture and trigger:** Use an injected monotonic clock at the actual activity tick boundary to model a long application processing gap without focus/disconnect events; compare steady-input sparse events and a normal cadence.
- **Required outcome:** Record whether any stale command is accepted before hold detection, then choose and test an explicit family-owned policy if needed. Do not claim a confirmed native sleep defect, infer loss from stationary axes or attach incompatible sessions just to reuse a watchdog.
- **Existing test starting points:** [test_controller_recovery_focus.gd](../../../app/tests/test_controller_recovery_focus.gd), [test_mr_controller_authority.gd](../../../app/tests/test_mr_controller_authority.gd), [test_airship_activity.gd](../../../app/tests/test_airship_activity.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Clock/tick/admission trace and current behavior classification; any changed policy requires a separate repaired oracle and native suspend qualification. Status: **UNRUN**; receipt: none.
- **Known baseline:** GCA-G1; reproduce separately, then assert the repaired oracle.

## C26

**RF loss and USB removal are qualified separately.** Owners: F1-GP-01, F4-GP-01, radio device owner. Apply when: A physical radio or wireless route is claimed supported, or its recovery changes.

- **Fixture and trigger:** On identified hardware, select separate applicable subcases: USB unplug, Bluetooth power/sleep, and transmitter-off with a separately enumerated receiver. A USB-only radio need not have an RF receiver in its input path; record inapplicable subcases.
- **Required outcome:** Record observed input/failsafe behavior per applicable transport. No unchanged-axis/RF-health inference or synthetic USB result qualifies transmitter loss. Inapplicable and unobservable RF status remain distinct from a pass or failure.
- **Existing test starting points:** No automated witness claimed; follow the named qualification owner. The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Exact device/firmware/OS/transport/build, report/video and observed recovery; no hardware test was performed by this audit. Status: **UNRUN**; receipt: none.
- **Known baseline:** GCA-G4; reproduce separately, then assert the repaired oracle.

## C27

**Fixed-wing refusal and committed faults remain distinct.** Owners: SF, fixed-wing session, FL, UI-FS. Apply when: Reset/restore/reload/observer transaction moves, not merely a status view.

- **Fixture and trigger:** Inject candidate refusal before commit, then observer fault/reentry after a separately accepted reset or restore. Record old/new flight, writer and statistics identities.
- **Required outcome:** Precommit refusal preserves old accepted frame/writer with no publication. Postcommit fault leaves the accepted frame paused, emits the owner-specified outcome once and closes the correct old footer; restore remains noncredit. Do not retry a committed reset as if rolled back.
- **Existing test starting points:** [test_flight_reset_transaction.gd](../../../app/tests/test_flight_reset_transaction.gd), [test_reset_publication.gd](../../../app/tests/test_reset_publication.gd), [test_restore_publication.gd](../../../app/tests/test_restore_publication.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Commit receipts, exact frame/inputs, callback sequence, old footer/ticks and correct statistics-generation or noncredit result. Status: **UNRUN**; receipt: none.

## C28

**Other families do not inherit a false reset guarantee.** Owners: BL, DR, family recorders. Apply when: Airship/quad reset or recorder publication is explicitly included in a later slice.

- **Fixture and trigger:** Inject airship reset rejection after resetting notification and quad context-changing reset observer/failed retry; observe recorder state and accepted physical frame at every boundary.
- **Required outcome:** Characterize actual ordering before extraction. Current early recorder notification is not called fixed-wing-style rollback. Preserve current behavior in structural work, or define and prove a separately owned preservation repair; no lost-byte incident is assumed from source alone.
- **Existing test starting points:** [test_airship_session.gd](../../../app/tests/test_airship_session.gd), [test_airship_flight_log.gd](../../../app/tests/test_airship_flight_log.gd), [test_mr_flight_log.gd](../../../app/tests/test_mr_flight_log.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Fault-injection timeline, recorder/footer/completeness and state; scope remains outside the first pause/resume bridge. Status: **UNRUN**; receipt: none.

## C29

**Exit and tentative detach preserve owned data.** Owners: UI, FL, RCV, DR, worker owner. Apply when: Replacement, recording finalization, export, disposal or worker lifetime moves.

- **Fixture and trigger:** Cancel/fail replacement after tentative detach; repeat close/cancel; inject writer/export failure and pending race results; deliver late loader completion. Exercise explicit discard only through the existing owner choice.
- **Required outcome:** Tentative detach does not finalize the surviving flight. Report publication/export failure and preserve/recover data where the owning contract guarantees it; label incomplete or unrecoverable output truthfully. No automatic discard, wrong-owner close, duplicate callback or live-worker join that blocks required main-thread work.
- **Existing test starting points:** [test_flight_session_staged.gd](../../../app/tests/test_flight_session_staged.gd), [test_airship_flight_log.gd](../../../app/tests/test_airship_flight_log.gd), [test_mr_flight_log.gd](../../../app/tests/test_mr_flight_log.gd), [test_controller_car.gd](../../../app/tests/test_controller_car.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Owner identities, replacement result, file/sample/outbox state and retirement order; no universal close API required. Status: **UNRUN**; receipt: none.

## C30

**Detached status is truthful and cannot mutate authority.** Owners: UI, session owners, D6. Apply when: Status projection, operation availability or HUD adapter changes.

- **Fixture and trigger:** Mutate nested values returned to a test view; read status for multiple holds, unsupported operations and unknown backend; change relevant model/profile/external-driver state and replace activity.
- **Required outcome:** No view mutation changes authority or another view. Unknown/unsupported is not ready/false-native; dynamic operation availability follows current owners. Old status cannot authorize new activity actions, and shared profiles retain valid other-family bindings.
- **Existing test starting points:** [test_controller_prompts.gd](../../../app/tests/test_controller_prompts.gd), [test_ui_screen_stack.gd](../../../app/tests/test_ui_screen_stack.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Before/after owner values, detached alias checks, projected reason/support and actual consumer behavior; minimal new fixture is proposed where absent. Status: **UNRUN**; receipt: none.

## C31

**Replay respects source identity and candidate limits.** Owners: FL, SF, physics. Apply when: Trajectory, tick input, physics or recording identity may change, or the owning gate requires replay.

- **Fixture and trigger:** For supported fixed-wing tapes, exact-replay complete baseline on its matching solver/backend. Compare candidate in exact mode if identity genuinely matches; otherwise use supported compatible candidate mode, an owner differential harness or remain blocked. Include mismatch/unsupported-domain negatives. Other families use their actual tape/checkpoint contracts.
- **Required outcome:** Fixed-wing exact mode retains identity rejection and reports its matching recorded backend; explicit candidate mode reports its actual reference backend. Report mode, completeness, ticks and solver_changed truthfully. Other families meet their own contracts. No identity rewriting, recovered-prefix equivalence, unsupported servo bypass or claim that replay retests raw input.
- **Existing test starting points:** [test_golden.gd](../../../app/tests/test_golden.gd), [test_flight_log_inputs.gd](../../../app/tests/test_flight_log_inputs.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Tape/engine/source/backend/config identities and complete CLI or owner-specific harness/checkpoint reports as applicable. Golden helper and short synthetic input tapes do not replace selected flight evidence. Status: **UNRUN**; receipt: none.

## C32

**Actual native execution is qualified separately.** Owners: NK, SF, physics, DT. Apply when: Native callback/context/selection/package behavior or native performance claims are affected.

- **Fixture and trigger:** Run applicable owner parity/fault/refusal/restore tests on the actual qualified native path and matching reference; include absent/mismatched library and unsupported live configuration.
- **Required outcome:** Requested native or reference fallback does not count as native. Preserve identity/ABI and atomic transaction, fail/reject under the owning admission, and keep package/OS gates separate. Candidate-mode reference replay alone cannot close this case.
- **Existing test starting points:** [test_native_stage.gd](../../../app/tests/test_native_stage.gd), [test_dr_multirotor_kernel.gd](../../../app/tests/test_dr_multirotor_kernel.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Actual backend/call coverage, engine/toolchain/library/source/data identities and owner-selected full roster; the listed scripts are only entry points. Status: **UNRUN**; receipt: none.

## C33

**Primary gamepad player flow remains usable.** Owners: UI-12-GP-01, UI-15-GP-01, DT. Apply when: The affected UI integration or release claims a gamepad route.

- **Fixture and trigger:** Use the real offered Home/Controls/test/save/launch/Pause/settings/recovery/Home path on a declared activity; exercise EN/ES, popups, scrolling, cancel, dirty drafts and selected-device prompts.
- **Required outcome:** Supported primary flow works with the selected controller and documented keyboard/text/OS-dialog exceptions, without accidental flight actions or unreachable recovery. Synthetic focus checks do not certify native or physical usability.
- **Existing test starting points:** [test_controller_menu.gd](../../../app/tests/test_controller_menu.gd), [test_controller_setup.gd](../../../app/tests/test_controller_setup.gd), [test_controller_prompts.gd](../../../app/tests/test_controller_prompts.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Actual display/renderer/activity/build and UI record; source and exported physical-device results separately labeled. Status: **UNRUN**; receipt: none.

## C34

**Verified radio menus preserve center and command evidence.** Owners: UI-12-GP-02, D6, UI shell. Apply when: An actually supported verified radio-menu route, proof or shell gate changes.

- **Fixture and trigger:** After verification, relaunch and exercise the supported menu/flight journey with one radio for both roles. Lose focus/reconnect, then try mouse/keyboard Continue before center evidence; separately test command OFF and the trusted challenge seed.
- **Required outcome:** Same-radio applicable launch/Continue/restart requires current center evidence even for mouse/keyboard. Radio commands separately require their OFF/rearm policy. Trusted same-generation verification seed remains valid. Throttle never becomes menu navigation; other-role combinations retain their policy.
- **Existing test starting points:** [test_radio_menu.gd](../../../app/tests/test_radio_menu.gd), [test_radio_menu_service.gd](../../../app/tests/test_radio_menu_service.gd), [test_radio_menu_journey.gd](../../../app/tests/test_radio_menu_journey.gd), [test_radio_menu_delivery.gd](../../../app/tests/test_radio_menu_delivery.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Mapping/action proof, source generation, center and command evidence, actual shell gate and supported activity. Radio Pause alone does not qualify radio menus. Status: **UNRUN**; receipt: none.

## C35

**Device and transport fault cycles match the claim.** Owners: F1-GP-01, F3-GP-02, F4-GP-01, DT. Apply when: A device/OS/transport is claimed supported or its affected physical recovery is qualified.

- **Fixture and trigger:** Use each applicable actual hardware-matrix row: idle drift, independent triggers, multiple devices and at least ten disconnect/reconnect cycles, including specified throttle/pause/setup and focus/sleep cases as applicable; test startup ordering and supported USB/BT modes separately.
- **Required outcome:** No unintended command/auto-resume, correct selected ownership and recoverable holds under the documented family policy. Windows/USB does not qualify another OS/transport. Unavailable hardware or a hung/incomplete run remains unqualified.
- **Existing test starting points:** No automated witness claimed; follow the named qualification owner. The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Build/engine/OS/model/firmware/transport/wrapper/profile, actual report/video and outcome per row; unknown metadata stays unknown. Status: **UNRUN**; receipt: none.
- **Known baseline:** GCA-G4; reproduce separately, then assert the repaired oracle.

## C36

**Input optimization does not add hidden delay.** Owners: F6-GP-01, PT, VQ, D6. Apply when: Sampling/buffering/shaping changes or a response/performance improvement is claimed.

- **Fixture and trigger:** Pin baseline/candidate sources differing by the intended change, match replayable inputs/assets/engine/backend/workload and alternate repeated runs with an unchanged control. Separately follow physical F6 filmed transitions when claimed.
- **Required outcome:** Preserve sample age/order and first accepted command without unexplained frame queue, invalid-sample masking or behavior drift. Report measured full-workload distributions and uncertainty. Callback counts or replay timing cannot certify physical response.
- **Existing test starting points:** [test_controller_conditioning.gd](../../../app/tests/test_controller_conditioning.gd), [test_controller_edge_continuity.gd](../../../app/tests/test_controller_edge_continuity.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Software event/sample/tick/display trace, paired raw measurements/p50/p95/tails/memory; physical F6 has its own at-least-30 filmed transitions and camera resolution, with no promised gain. Status: **UNRUN**; receipt: none.

## C37

**Lifecycle repetition exposes retained resources.** Owners: PT, UI, DT, family lifecycle. Apply when: Lifecycle resources/listeners change or integration/release soak is claimed.

- **Fixture and trigger:** Repeat the owner-defined Home/Fly/Workshop/reset/exit workload after warmup with fault/cancel branches; use the applicable global performance or desktop campaign, without conflating their different lengths.
- **Required outcome:** No unexplained retained-memory/object/listener/worker growth or duplicate event action; pending data follows owner policy. Incomplete soak stays incomplete, and a short finite run cannot establish absence of every leak.
- **Existing test starting points:** [test_flight_session_staged.gd](../../../app/tests/test_flight_session_staged.gd), [test_ui_screen_stack.gd](../../../app/tests/test_ui_screen_stack.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Declared iteration/time roster, source/host/backend, retained counts and memory over time; device/GPU contention controlled. Existing unit tests are not the soak. Status: **UNRUN**; receipt: none.

## C38

**Exported controls evidence binds to the actual package.** Owners: DT, UI, D6, NK. Apply when: Scene/import/UID/backend dependencies move or packaged support is claimed.

- **Fixture and trigger:** Build the scoped target package with pinned inputs; launch outside editor on its native OS and repeat affected selection/save/restart/focus/recovery routes with required assets and actual backend.
- **Required outcome:** Packaged resources and identities match the artifact; no editor-only path or missing dynamic asset is silently skipped. Native/reference and physical-device claims match actual execution, with source-only evidence labeled separately.
- **Existing test starting points:** [test_radio_menu_delivery.gd](../../../app/tests/test_radio_menu_delivery.gd), [test_controller_diagnostics.gd](../../../app/tests/test_controller_diagnostics.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Executable/package/source/engine/manifest hashes, OS/backend/device and completed route receipts; existing software delivery tests alone do not certify package playability. Status: **UNRUN**; receipt: none.

## C39

**Usability and accessibility claims remain truthful.** Owners: UI-15-UX, D6-UX, UI-12, pilot acceptance. Apply when: Prompts, Controls UI or controller/pilot usability is affected or claimed.

- **Fixture and trigger:** Follow the owning formative-usability protocol with supported device and EN/ES layouts; inspect accessible names/focus, error recovery, custom remaps and applicable display targets. Distinguish fixed keyboard map from future D6-UX-02.
- **Required outcome:** No inaccessible action name, disappearing dirty draft or misleading unsupported mapping. Record measured setup/recovery outcomes and user limitations; Mode 1/2 alone does not prove handedness or assistive-device support, and source tests do not establish pilot feel.
- **Existing test starting points:** [test_controller_prompts.gd](../../../app/tests/test_controller_prompts.gd), [test_controller_setup_safety.gd](../../../app/tests/test_controller_setup_safety.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Real UI/participant procedure and observations with device/build/display, existing owner targets and missing accessibility/physical rows explicit. Status: **UNRUN**; receipt: none.

## C40

**Adversarial transition sequences retain invariant oracles.** Owners: D6, UI, affected families. Apply when: Shared input/lifecycle integration changes enough to create interacting transitions.

- **Fixture and trigger:** Declare bounded seeds and event/poll/tick schedules combining select/rebind, held input, menu/capture, focus/loss, Save refusal, Continue, replacement and restart on the affected real consumer; record covered transition pairs.
- **Required outcome:** Assert the selected C01–C24 invariants at each relevant boundary with independent expected outcomes. Preserve a minimized reproducer on failure; generated sequences do not replace required named scenarios or imply coverage of unvisited combinations.
- **Existing test starting points:** [test_controller_routing_audit.gd](../../../app/tests/test_controller_routing_audit.gd), [test_controller_edge_continuity.gd](../../../app/tests/test_controller_edge_continuity.gd), [test_controller_audit_shell.gd](../../../app/tests/test_controller_audit_shell.gd). The actual case/fixture must be reviewed or implemented before execution.
- **Evidence:** Actual new/extended harness, seeds, coverage roster, event trace and diagnostics; candidate mutations only in isolated disposable copies if used to prove oracle sensitivity. Status: **UNRUN**; receipt: none.
