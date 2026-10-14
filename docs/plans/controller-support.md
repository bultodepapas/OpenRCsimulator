# Xbox, DualSense and general controller qualification plan

Status: source implementation and focused software audit delivered, 2026-10-14. Physical qualification remains open. The owner prioritizes Xbox and/or DualSense on Windows. The [current player guide](../FIRST-LAUNCH.md#controller-settings-current-source) describes implemented behavior; [dated research and evidence](../research/controller-support-2026-10-14/README.md#software-audit-and-corrections) retain the original defects, primary references, implementation checks and audit results.

This plan now tracks remaining work and acceptance. It does not count implemented classes as future work or treat synthetic tests as controller certification. Godot stays pinned to 4.7.2; engine upgrades require a separate change and qualification.

## Ownership and delivered scope

Use the existing [track registry](../README.md#tracks-plans-and-step-ids). Input owns D6/F1/F3/F4/F6 steps and `app/input/`; the product shell owns UI-10/UI-12/UI-15 and `app/ui/`, `app/app_root.gd`, localization and focus. Session changes coordinate with fixed-wing, HELI and RCV owners; exported package checks coordinate with DT/PT. No aircraft physics ownership transfers to this work.

| Steps | Implemented source contract | Acceptance still open |
| --- | --- | --- |
| D6-GP-01/02 | Radio-only calibration, V2 profiles, legacy preservation, validated transactional persistence | Physical calibration/restart recovery; damaged storage and failed activation regression checks remain mandatory |
| F3-GP-01/02/03 | Automatic startup/Home defaults, manual flight/UI overrides, connection generations, loss/focus/neutral gates, separate activity semantics | Physical startup/hot-plug, sparse events, sleep and two-device fault cycles |
| D6-GP-03 | Scalar shaping, Mode 1/2 rate throttle and fixed-wing absolute-trigger preset | Physical endpoint, drift and independent-trigger checks; no automatic hardware suitability certification |
| UI-10-GP-01 / UI-15-GP-01 | Draft setup, channel mapping, remap, conflict checks and explicit Save/Cancel | Native primary flow, remap release isolation, dirty-draft and error recovery |
| D6-GP-06 / UI-15-GP-02 | Three typed AUX requests and optional camera/light/smoke/flap/gear actions; source conflicts and preview | Physical high-index controls; flap aerodynamics/retractable contacts are separate unimplemented aircraft capabilities |
| UI-12-GP-01 | Selected-gamepad menu routing, EN/ES prompts, free Kenney glyphs and family override | Keyboard-free flow on physical Xbox/DualSense; app-wide navigation beyond the primary flow |
| F1-GP-01 | Bounded button/axis reports and metadata | Native reports with actual devices, model/firmware/transport recorded |
| F6-GP-01 | Native baseline/current input-seam cost comparison | Full-session/display and filmed physical latency; rerun seam measurements if conditioning changes materially |

Scope is one flight controller plus an optional separate menu gamepad. Startup/Home selects a connected device automatically, with keyboard as the no-device fallback; active flights retain explicit ownership and disconnection recovery. Manual selections override defaults for the current application run. Profiles match identity evidence, not persisted Godot connection IDs. Unknown/ambiguous devices still require explicit configuration before flight. A failed draft must leave the valid active profile intact; invalid active samples must still fail safe. The [player guide](../FIRST-LAUNCH.md#controller-settings-current-source) owns priority and override details.

Four primary flight axes and smoke/flaps/gear AUX requests are available within Godot's 10 axis and 128 button slots. These are API limits, not a promise of physical channels. Camera/light/smoke operations use existing fixed-wing capabilities; helicopter camera actions work, but throttle cut, lights, smoke and flap/gear behavior are not shared flight capabilities. Ground driving retains its own steering/RT/LT/reverse scheme. The guide states which requests have no aircraft implementation.

The input path is registry -> selected profile -> scalar conditioning/neutral gate -> activity commands; the shell separately routes flight/menu/calibration/capture actions. Simulation state stays float64. No solver, actuator law, aircraft dataset, trace ordering or golden flight changes belong to this plan.

## Remaining work, in order

| Priority / step | Concrete work | Completion evidence |
| --- | --- | --- |
| Ongoing regression gate / D6-GP-02, F3-GP-02, UI-15-GP-01 | Preserve the completed audit fixes: calibration settings, corrupt-store rejection, activation rollback, stable draft/capture ownership, fresh neutral readiness and key-chord validation | Focused audit tests and existing suites pass; whole-app parse and final changed-file parses pass. Recheck these contracts on later input changes; dated evidence records the limits of repository-wide testing. |
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
- A gamepad requires fresh mapped flight-axis samples, released buttons and a configured neutral dwell. Readiness while paused must be revoked if controls leave neutral. Untouched polled zero is not fresh evidence; test sparse-event hardware with move-and-return instructions.
- Ordinary menus freeze virtual rate throttle and show it before explicit resume. Focus loss invalidates physical sample evidence, including radio low-throttle evidence. Lost continuity/profile changes return to the activity's safe held state; helicopter collective policy remains distinct.
- Saving preflights the selected activity and reports failure without closing setup. Recalibration changes calibrated ranges/AUX only, retaining other V2 settings. An unreadable store is an error, not an empty installation eligible for automatic defaults.
- Capture owns the chosen device and consumes the matching release before returning to navigation. Device loss cancels capture. Dirty profile edits must not disappear through profile/device selection.
- Flap/retract requests do not establish aerodynamic or contact behavior. A separate aircraft capability change must validate physical behavior before the UI can claim operational flaps/retracts.
- The former source findings and architecture proposal are retained as dated evidence, not represented as current defects or unbuilt classes. Source completion is independent of the physical release gates below.

### Automated verification

Run focused audit tests and the existing profile/store/registry/action/setup/menu/conditioning/RC rearming/calibration/AUX/flight-adapter suites. Include fixed-wing, helicopter and ground selection regressions, keyboard recovery and EN/ES navigation. Parse every GDScript file after integration; drafts stay outside `app/` until they parse. Run the canonical `app/test.sh` for repository acceptance and record its exact scope/failure if shared work prevents completion. Inspect logs, not only exit codes.

Required adverse cases include malformed/nonfinite bindings, bad recovery files, failed save/apply, mismatched device IDs, a held button during selection/capture, cancellation/disconnect, profile replacement, focus recovery with raised throttle, neutral drift before Continue, AUX rearming and multiple controls held together. Synthetic events verify routing; they do not verify SDL enumeration, transport or latency. Do not re-record golden flights to hide input regressions.

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
| Regression | One actual EdgeTX/other RC transmitter | Its documented USB joystick mode | Radio channels/curves, calibration, arming and UI isolation stay intact. |
| Alternate path | Steam-emulated controller; another wrapper only if already used by the owner | Windows, wrapper/version/config recorded | Qualify separately; no wrapper becomes a mandatory dependency. |
| Cross-platform | At least one Xbox and one PlayStation controller | Linux and macOS, applicable USB/BT | Native OS evidence required; Windows or WSL does not close these rows. |

Each row retains build hash, engine, OS build, controller model/firmware, transport, available metadata, driver/wrapper mode, profile revision, report, video/test record, observed capabilities and outcome (`pass`, `limited`, `fail`, `untested`). Avoid publishing serial numbers; retain redacted or local association identifiers. Missing hardware leaves that row open.

### Physical acceptance procedure

1. With a fresh test profile, connect before launch and after Home appears. Verify automatic selection, no-device keyboard fallback, saved-profile priority and manual overrides. Inspect recognized identity and verify all expected buttons and axes. Confirm 0%, 50% and 100% trigger readings and both triggers together.
2. Select/configure the controller and complete the primary menu flow without keyboard/mouse. Confirm prompts, focus, scrolling and cancel semantics in English and Spanish.
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
