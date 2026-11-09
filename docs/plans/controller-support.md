# Xbox, DualSense and general controller qualification plan

Status: source implementation and focused controller audit corrections delivered, 2026-11-08; verified radio menus and shareable diagnostics added to current source, 2026-11-09. Physical qualification remains open. The owner prioritizes Xbox and/or DualSense on Windows. The [current player guide](../FIRST-LAUNCH.md#controller-settings-current-source) describes implemented behavior; [dated research and evidence](../research/controller-support-2026-10-14/README.md#software-audit-and-corrections) retain the original defects, primary references, implementation checks and audit results.

This plan tracks remaining work and acceptance. It does not treat synthetic tests as controller certification. The current engine is Godot 4.8-beta2; [STACK](../STACK.md) and the verified engine downloader own its exact identity.

The 8 November controller audit produced a focused correctness revision under D6-GP-01/02/03, F3-GP-02 and UI-15-GP-01. It corrects reduced-range direction calibration, ambiguous legacy matching and cache invalidation, truthful absolute-throttle previews, new radio defaults, calibration metadata retention and generic action continuity. [Findings and verification](../research/controller-support-2026-10-14/README.md#controller-audit-corrections-2026-11-08) record those repairs. The later [radio-menu and diagnostics work](../research/controller-support-2026-10-14/README.md#radio-menus-and-diagnostics-2026-11-09) adds the source flows; physical and exported-build qualification remains open.

## Ownership and delivered scope

Use the existing [track registry](../README.md#tracks-plans-and-step-ids). Input owns D6/F1/F3/F4/F6 steps and `app/input/`; the product shell owns UI-10/UI-12/UI-15 and `app/ui/`, `app/app_root.gd`, localization and focus. Session changes coordinate with fixed-wing, HELI and RCV owners; exported package checks coordinate with DT/PT. No aircraft physics ownership transfers to this work.

| Steps | Implemented source contract | Acceptance still open |
| --- | --- | --- |
| D6-GP-01/02 | Radio-only calibration, V2 profiles, legacy preservation, validated transactional persistence | Physical calibration/restart recovery; damaged storage and failed activation regression checks remain mandatory |
| F3-GP-01/02/03 | Automatic startup/Home defaults, manual flight/UI overrides, connection generations, loss/focus recovery, immediate verified gamepad readiness, separate activity semantics | Physical startup/hot-plug, sparse events, sleep and two-device fault cycles |
| D6-GP-03 | Scalar shaping, Mode 1/2 rate throttle and fixed-wing absolute-trigger preset | Physical endpoint, drift and independent-trigger checks; no automatic hardware suitability certification |
| UI-10-GP-01 / UI-15-GP-01 | Draft setup, channel mapping, remap, conflict checks and explicit Save/Cancel | Native primary flow, remap release isolation, dirty-draft and error recovery |
| UI-15-GP-01-R1 (external audit A11 F01) | New profile uses a separate UUID and device-default draft; successful Save frees the New slot while retaining calibration provenance; Update and Duplicate keep their existing meanings | [57 regression and 283 existing software checks](../research/controller-support-2026-10-14/README.md#new-profile-identity-2026-11-06-ui-15-gp-01-r1); physical controller and native visual qualification remain open |
| D6-GP-02-I3 / UI-15-GP-01-I3 | Field-level mapping errors, conflict participants, focus/filter recovery and rejected-assignment feedback | [Software checks](../research/controller-support-2026-10-14/README.md#controller-field-errors-2026-10-26-github-3); native rendered/controller qualification remains with UI-12-GP-01 |
| D6-GP-06 / UI-15-GP-02 | Three typed AUX requests and optional camera/light/smoke/flap/gear actions; source conflicts and preview | Physical high-index controls; jet flaps and retractable gear are implemented by the aircraft/ground owners |
| D6-GP-06-R1 / HUD-11-R2 | Aircraft-scoped B/Circle gear and RB/R1 smoke defaults; preserved remaps/AUX, held-menu-button isolation, equipment availability/status in the guide | [Software evidence](../research/controller-support-2026-10-14/README.md#aircraft-auxiliary-defaults-2026-10-15-d6-gp-06-r1); physical controller qualification remains open |
| D6-GP-06-R2 | A/Cross flap detents and View/Share restart defaults; remappable restart button/channel, saved overrides and explicit Continue after reset | [Software evidence](../research/controller-support-2026-10-14/README.md#complete-flight-button-defaults-2026-10-15-d6-gp-06-r2); physical controller qualification remains open |
| D6-GP-06-R3 / RCV-05-R2 | Helicopter arm/hold/curve/trainer defaults and activity-aware setup; held motor cut dominates hold release; car reset and lights shortcuts preserve device ownership | [Software evidence](../research/controller-support-2026-10-14/README.md#helicopter-and-car-buttons-2026-10-16-d6-gp-06-r3-rcv-05-r2); physical qualification and configurable car mappings remain open |
| D6-GP-06-R5 (external audit A6 F2) | Bound flap and gear targets survive pause, menu and focus holds. An unarmed bound channel is "no command" (`RcInput.auxiliary_request_valid`), not a zero request; fresh OFF re-arms it, and smoke keeps its off-at-boundary pump semantics | `test_aux_pause_retention.gd` (19 checks): axis and button bindings, full/intermediate/retracted flaps, gear up/down, three hold kinds, re-arming, kernel inputs and actuator continuity; the input/AUX suites pass. Synthetic controller; physical transmitter qualification remains open |
| D6-GP-06-R4 / D6e-R6 | Airplane L3 dual-rate default, configured joystick shaping, saved overrides and held-menu-axis isolation; effective rates and bindings in the guide | [Software evidence](../research/controller-support-2026-10-14/README.md#airplane-dual-rates-across-controllers-2026-10-26-d6-gp-06-r4--d6e-r6); physical device qualification remains open |
| UI-12-GP-01 | Selected-gamepad menu routing, EN/ES prompts, free Kenney glyphs and family override | Keyboard-free flow on physical Xbox/DualSense; app-wide navigation beyond the primary flow |
| UI-12-GP-02 | Optional verified radio menus use calibrated roll/pitch and distinct physical Accept, Back and Pause controls; throttle is excluded. Save commits the profile and keyboard-or-profile menu preference together; a saved profile is restored only on a unique eligible match | [Synthetic journey checks](../research/controller-support-2026-10-14/README.md#radio-menus-and-diagnostics-2026-11-09) exercise Home, Controls, popups, Pause/settings, resume, accident, reconnect and Home. Real radio, native desktop, second-launch and exported-build qualification remain open |
| F1-GP-01 | Bounded button/axis reports and metadata | Native reports with actual devices, model/firmware/transport recorded |
| F1-GP-02 | Controls exports a new redacted diagnostic JSON with build/engine/OS, draft profile, calibrated channels, effective actions and bounded observed input; current samples are per-axis, not synchronized | [Focused software checks](../research/controller-support-2026-10-14/README.md#radio-menus-and-diagnostics-2026-11-09). Per-route firmware/transport evidence, exported-build checks and physical qualification remain open |
| F6-GP-01 | Native baseline/current input-seam cost comparison | Full-session/display and filmed physical latency; rerun seam measurements if conditioning changes materially |

Scope is one flight controller plus a menu gamepad or an explicitly verified radio. Startup/Home selects a connected device automatically, with keyboard as the no-device fallback; active flights retain explicit ownership and disconnection recovery. Manual flight selection applies for the current run. The saved menu preference is keyboard or a profile UUID, restored only with an eligible unique match; connection IDs are never persisted as identities. Unknown/ambiguous devices still require explicit configuration before flight. A failed draft must leave the valid active profile intact; invalid active samples must still fail safe. The [player guide](../FIRST-LAUNCH.md#controller-settings-current-source) owns priority and override details.

Four primary flight axes and smoke/flaps/gear AUX requests are available within Godot's 10 axis and 128 button slots. These are API limits, not a promise of physical channels. Equipment defaults follow the active vehicle. Helicopters support their own arm, rotor hold, curve, trainer and light actions; their latched motor cut differs from fixed-wing throttle cut. Ground driving retains its own fixed steering/RT/LT/reverse scheme. The guides state which requests have no vehicle implementation.

The input path is registry -> selected profile -> scalar conditioning/device readiness -> activity commands; the shell separately routes flight/menu/calibration/capture actions. Simulation state stays float64. No solver, actuator law, aircraft dataset, trace ordering or golden flight changes belong to this plan.

The [JETI radio subtrack](jeti-support.md) owns manufacturer-supplied DC-16II evidence, family identification, configured physical switch labels, clean action defaults and maintained two-/three-position input under D6/F1/F4/F6-JETI-* and UI-15-JETI-*. Its [2026-10-19 software implementation](../research/radio-input/D6-JETI-01/README.md) reuses these controller contracts. The [original intake](../research/radio-input/D6-JETI-00/README.md) records external basic-flight success; actual Godot switch mapping and native package qualification remain open under the subtrack's plan.

## Remaining work, in order

| Priority / step | Concrete work | Completion evidence |
| --- | --- | --- |
| P1 / UI-12-GP-02 qualification | Qualify the implemented verified radio menu route on each supported device/OS/transport | Second-launch Home → flight → Pause/settings → resume → accident → Home journey, Mode 1/2, throttle exclusion, popup/repeat/capture, fresh center/OFF and disconnect/focus cases. First-time calibration and verification, text entry and native OS dialogs may use keyboard, mouse or a separate gamepad. |
| P2 / F1-GP-02 qualification | Retain a shareable diagnostic export and per-route qualification record for each tested device | Exact build and OS, observed inputs, profile/actions and limitations, plus actual model/firmware and USB/Bluetooth mode where independently known. Identifiers are redacted by default; unexposed metadata stays unknown. The existing standalone bounded input report remains available. |
| Ongoing regression gate / D6-GP-02, F3-GP-02, UI-15-GP-01 | Preserve the completed audit fixes: calibration settings, corrupt-store rejection, activation rollback, stable draft/capture ownership, verified gamepad readiness, radio arming and key-chord validation | Focused audit tests and existing suites pass; whole-app parse and final changed-file parses pass. Recheck these contracts on later input changes; dated evidence records the limits of repository-wide testing. |
| P1 / F1-GP-01 + D6-GP-03 | Inspect each available physical device and record all expected axes/buttons. Test RT/LT individually and together at 0/50/100%, stick direction/range and 30-second idle drift | Native F1 report, exact model/firmware/transport, profile revision and observed range table |
| P1 / UI-12-GP-01 | Complete Home -> Controls -> select/configure/test -> aircraft -> launch -> pause -> settings -> resume -> Home -> quit without keyboard/mouse | EN/ES focus/scroll/cancel record on each primary controller; slider, selector, popup and remap cases included |
| P1 / F3-GP-02 + F4-GP-01 | Run the fault protocol below on Windows source and exported package | Ten reconnect cycles per primary path; focus, suspend, stale device ID and two-device isolation results; no automatic resume or thrust |
| P1 / F6-GP-01 | Measure physical response after correctness qualification on the same host/build | At least 30 filmed transitions per primary transport; median/p95, resolution, FPS/display settings and separate software timing |
| P2 / F4-GP-02 | Add DS4, third-party modes, accessible controllers, actual RC radios and Linux/macOS as hardware becomes available | Each model/mode/OS/transport has its own matrix row; Windows results do not close other platforms |
| Optional / D6-GP-04 | Bounded configurable rumble/light feedback after the Windows gate | Capability fallback, finite duration and stop-on-hold/loss/exit tests; no input or physics effects |
| Optional / D6-GP-05 | Motion camera feasibility; advanced haptics/adaptive triggers only after a separate decision | Native API/backend feasibility, USB/BT evidence, calibration and performance; no force-feedback realism claim |

Do not estimate the already delivered core again. Windows qualification effort depends on hardware availability and discovered faults; schedule its rows after inventory. Optional effects, mixed-controller flight, trainer handover, arbitrary HOTAS expansion and console exports are outside the current delivery.

### Explicit gaps and acceptance rules

- The trigger preset is user-selectable today; the application does not prove independent analog hardware automatically. The test view and native report must establish this before qualifying a row. Combined/digital triggers use a rate-stick preset or another explicitly validated source. Automatic observation-based preset eligibility is a separate enhancement, not a completed gate.
- A recognized standard gamepad is ready from its first valid live poll, including direct fixed-wing launches. No neutral dwell, button-release gate or axis-motion gesture is required. Paused stick movement does not revoke readiness; Continue remains explicit and rate throttle stays frozen until resume. Unknown/raw layouts retain their evidence gate. Radios retain low-throttle arming. See [readiness evidence](../research/controller-support-2026-10-14/README.md#gamepad-readiness-2026-10-15-f3-gp-02-r2).
- Ordinary menus freeze virtual rate throttle and show it before explicit resume. Focus loss invalidates physical sample evidence, including radio low-throttle evidence. Lost continuity/profile changes return to the activity's safe held state; helicopter collective policy remains distinct.
- Saving preflights the selected activity and reports failure without closing setup. Recalibration changes calibrated ranges/AUX only, retaining other V2 settings. An unreadable store is an error, not an empty installation eligible for automatic defaults.
- Capture owns the chosen device and consumes the matching release before returning to navigation. Device loss cancels capture. Dirty profile edits must not disappear through profile/device selection.
- Radio menu opt-in requires calibrated primary channels and distinct physical Accept, Back and Pause sources; an axis source cannot share a flight axis. The challenge verifies the current mapping and association. Relevant edits or recalibration invalidate its proof. A new connection or focus recovery requires fresh center and OFF events; a polled zero is not evidence. When the same verified radio controls flight and menus, launch, Continue and automatic restart resumption require current-connection roll/pitch center evidence, including when the pilot uses keyboard or mouse. Keyboard and mouse remain recovery inputs.
- The shareable report describes the current setup draft and observed selected-device events. Per-axis last samples and normalized values are not simultaneous or age-qualified; unobserved controls and unexposed physical counts remain unknown. It is not hardware, RF-loss or latency evidence.
- Input requests alone do not establish aerodynamic or contact behavior. Runtime capability checks admit the jet's implemented flaps/retractable gear and installed Stik smoke pump; jet smoke remains unavailable. Equipment implementation belongs to its aircraft/physics/render owners, not to the button preset.
- The former source findings and architecture proposal are retained as dated evidence, not represented as current defects or unbuilt classes. Source completion is independent of the physical release gates below.

### Automated verification

Follow the [shared verification scope](../tools/shared.md#verification-scope): run focused audit tests and affected profile/store/registry/action/setup/menu/conditioning/RC rearming/calibration/AUX/flight-adapter suites. Include fixed-wing, helicopter and ground selection regressions, keyboard recovery and EN/ES navigation when those boundaries change. Parse modified production GDScript; drafts stay outside `app/` until they parse. Required CI retains full production coverage. A focused local pass does not replace that gate; inspect logs and completion, not only exit codes.

Required adverse cases include malformed/nonfinite bindings, bad recovery files, failed save/apply, mismatched device IDs, a held button during selection/capture, cancellation/disconnect, profile replacement, focus recovery with raised throttle, neutral drift before Continue, AUX rearming and multiple controls held together. Synthetic events verify routing; they do not verify SDL enumeration, transport or latency. Do not re-record golden flights to hide input regressions.

New radio starters require the mapping wizard before Save; a recognized family name does not establish channel order or throttle polarity. Existing saved profiles retain their effective actions and explicit recovery. New radio/raw-joystick profiles have clean actions with keyboard recovery; **Use safe radio actions in draft** remains a reviewable opt-in for older profiles. Absolute-trigger throttle keeps direct endpoint normalization, and its unused deadzone/expo controls are disabled. Joystick `stick_rate` is rejected with a diagnostic because the generic joystick sampler does not implement it.

**Learn axis** supports flight shortcuts and Pause: explicitly confirm OFF, hold ON, then return OFF. It uses measured finite endpoints and hysteresis, including reduced/reversed/offset ranges. Existing signed raw-threshold bindings remain valid. The verified radio menu adapter also accepts learned axis bindings for Accept and Back; calibrated roll/pitch provide navigation. Learned ranges are not passed directly into generic native InputMap navigation or used to advance calibration.

USB disconnect and RF loss are separate qualification cases. A wireless receiver can remain enumerated after transmitter-off; unchanged controls are not evidence of link loss. Record the observed failsafe behavior for every wireless route, and label unobservable RF loss as a limitation. No new RF-loss detector or physical latency claim is introduced by these fixes.

### Hardware matrix

Initial status for every physical row is **untested**. Record actual model/revision; “Xbox” alone is not an adequate hardware identifier.

| Priority | Device / mode | Connections and platform | Release meaning |
| --- | --- | --- | --- |
| Required | Available Xbox Wireless Controller, exact generation recorded | Windows, USB and Bluetooth where that model supports it | Both applicable rows must pass to claim both transports. |
| Required | DualSense, exact revision recorded | Windows, USB and Bluetooth | Separate primary acceptance rows; direct SDL path first. |
| Required isolation | Xbox + DualSense together; controller + radio; duplicate descriptors in software | Windows | Only chosen ownership controls flight/UI; explicit switch and reconnect behave correctly. |
| Conditional | Xbox Wireless Adapter, Xbox 360, Elite | Windows, actual supported adapter/cable | Do not infer results from the first Xbox model. |
| Breadth | 8BitDo/GameSir or another third-party device | Each available XInput/DInput/Switch mode, cable/dongle/BT | Modes are separate rows. Include known disconnect-hang candidates if available. |
| Breadth | DualShock 4, Switch Pro/class-compatible and accessible controllers | Available desktop connections | Digital triggers, button layout or absent features degrade explicitly. |
| Regression | One actual EdgeTX/other RC transmitter | Its documented USB joystick mode | Radio channels/curves, calibration, arming, verified menu ownership and isolation require their own recorded checks. |
| Alternate path | Steam-emulated controller; another wrapper only if already used by the owner | Windows, wrapper/version/config recorded | Qualify separately; no wrapper becomes a mandatory dependency. |
| Cross-platform | At least one Xbox and one PlayStation controller | Linux and macOS, applicable USB/BT | Native OS evidence required; Windows or WSL does not close these rows. |

Each row retains build hash, engine, OS build, controller model/firmware, transport, available metadata, driver/wrapper mode, profile revision, report, video/test record, observed capabilities and outcome (`pass`, `limited`, `fail`, `untested`). Avoid publishing serial numbers; retain redacted or local association identifiers. Missing hardware leaves that row open.

### Physical acceptance procedure

1. With a fresh test profile, connect before launch and after Home appears. Verify automatic selection, no-device keyboard fallback, saved-profile priority and manual overrides. Inspect recognized identity and verify all expected buttons and axes. Confirm 0%, 50% and 100% trigger readings and both triggers together.
2. Select/configure the controller and complete the primary menu flow without keyboard/mouse. For radio, perform initial calibration and verification with keyboard, mouse or a separate eligible gamepad, then repeat the supported flow after a second application launch. Text entry and native OS dialogs remain explicit exceptions. Confirm prompts, focus, scrolling and cancel semantics in English and Spanish.
3. At rest, observe 30 seconds without unintended command or menu movement. Sweep each flight axis, verify direction/endpoints, check virtual throttle hold and confirm the selected preset's displayed explanation.
4. Fly the Stik ground start and an airborne start; inspect launch throttle explicitly. Perform a circuit and landing. Repeat representative pitch-sensitive aircraft behavior with its normal-rate profile; preserve full-rate CLI behavior. Pilot feel ratings remain separate from software checks.
5. Repeat at least ten disconnect/reconnect cycles, including under throttle, during pause and during setup; include controller sleep, Bluetooth power-off, Alt+Tab, minimize and PC sleep/resume. Expected result is recoverable hold/failsafe, no unintended command and no auto-resume. Record any engine hang separately.
6. Connect a second controller and a radio. Change discovery order, select each deliberately, disconnect the selected device while the other remains present, and verify no cross-control or silent takeover.
7. Restart the application and repeat selection/calibration recovery. Exercise USB-to-Bluetooth transition and legacy-profile import. Firmware update testing is a separate recorded experiment when available, not a mandatory firmware mutation during acceptance.
8. Repeat the core scenario in the exported Windows package outside the editor; test fullscreen/window focus with the DT owner. Verify helicopter and truck input regression scenarios before claiming app-wide compatibility.

Proposed usability target: a mapped Xbox/DualSense reaches the Controls test view in under 60 seconds without file editing; first-time calibration, if requested, completes within three minutes. These are acceptance targets to measure, not current performance claims.

For F6, compare at least 30 filmed transitions per qualified primary transport at a fixed FPS/display setting; report median/p95 and camera timing resolution. Measure press/motion-to-first-visible-control-response separately from aircraft motion, which includes servo/flight dynamics. Event callback spacing is not USB polling rate or motion-to-photon latency. Proposed regression budget: no added render-frame queue and no reproducible increase beyond measurement uncertainty; investigate rather than average away a failed row.

### Gates

| Gate | Required closure |
| --- | --- |
| Safe input | Calibration cannot silently change device kind; ownership and neutral/focus/loss transitions pass; existing radio/keyboard and activity contracts preserved. |
| Usable controller | Remap/profile persistence and complete primary menu flow pass with correct prompts; setup requires no configuration-file edits. |
| Windows supported | Actual Xbox and DualSense applicable USB/BT rows pass in the exported build, including fault cycles and user flight. If a family is unavailable, release wording names only the tested family. |
| Measured response | Baseline/final software and physical latency evidence retained; no unexplained added frame or significant regression. |
| Additional platform/model | Its own native matrix passes; it does not inherit Windows support status. |

## Risks, dependencies and rollback

- **Backend hang:** a main-thread SDL lockup cannot be repaired by a GDScript timeout. Reproduce against the exact pinned engine and device, then qualify a specific upstream fix/engine version separately. Keep an affected row unsupported until resolved.
- **Identity collision or virtual duplication:** selection must remain possible even with identical names/GUIDs. Do not hide a device using a broad SDL ignore rule or infer physical origin from an emulated label.
- **Mapping-layer confusion:** distinguish application action remap from SDL hardware mapping. Test any database override on the actual backend and restart boundary; reuse upstream mapping tools rather than inventing a HID mapper.
- **Shared-session regression:** land changes through the existing holds/command seams, preserve HELI/RCV semantics and AUX bindings, and coordinate UI/shared files with their owners.
- **Changed feel:** retain migrated 0.08/0.3/0.5 defaults initially. Optional tuning is visible, reversible and measured. Do not apply transmitter expo twice or alter aircraft mechanics to compensate for controller handling.
- **Rollback:** keep legacy calibration intact, version profiles/presets, and make new UI/registry integration revertible per step. A reverted build can still use the old file. Profile edits activate only after validation and explicit save; an error cannot overwrite the last working setup.

The next acceptance work is native Xbox/DualSense USB/Bluetooth qualification and exported-package fault cycles when hardware is available. Keep optional effects gated on that evidence; remaining hardware rows do not inherit software-test results.
