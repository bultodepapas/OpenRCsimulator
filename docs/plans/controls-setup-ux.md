# Controls setup UX plan

Status: software delivered 2026-11-12 for UI-15-UX-01…08 and D6-UX-01 ([implementation and verification](../research/controls-ux-2026-11-12/README.md#implementation-2026-11-12)); open: UI-15-UX-00 baseline inventory, UI-15-UX-09 glyph extension (blocked: the pinned Kenney archive URL returns HTTP 403 to automated download), UI-15-UX-10 formative usability, D6-UX-02 keyboard remapping, physical-device qualification. Goal: make calibration and button/axis assignment for EdgeTX/OpenTX and JETI radios, Xbox, PlayStation, other gamepads and the keyboard **graphical, guided and obvious**, using the conventions players already know from games and RC simulators. [Audit, screenshots method and external references](../research/controls-ux-2026-11-12/README.md).

This is a presentation and flow redesign over the existing controller contracts. It does not change profiles' meaning, conditioning, arming, readiness, physics or aircraft data. [Controller support](controller-support.md) keeps the input contracts and hardware gates; [JETI support](jeti-support.md) keeps JETI identity and switch groups; [menu redesign](menu-redesign.md#settings-and-controls) keeps the shell, theme and navigation rules.

## Ownership and step IDs

UI owns `UI-15-UX-*` (`app/ui/`, Controls screens, glyph presentation, i18n, UI tests). Input owns `D6-UX-*` (`app/input/`: new bindable functions, keyboard remap data, detection helpers). Coordinate `app/app_root.gd`, the flight session and HUD with their owners. Follow the [ownership registry](../README.md#tracks-plans-and-step-ids); one writer per path.

## Problem summary

The logic is good: movement-based radio channel detection, endpoint and throttle verification, V2 drafts with Save/Cancel, conflicts, presets, switch groups, glyph families. The presentation is a settings form:

1. Calibration is text and numbers ("Radio axes: +0.12 −0.98 …"); there is no stick picture or motion feedback.
2. Axes are assigned by typing a Godot axis index into a SpinBox; only the radio wizard detects movement.
3. Live feedback is four thin bars; no gimbal view, endpoint envelope or curve.
4. The modal is capped at 1160×780 px (about 60 % of a 1080p screen); Buttons shows four rows and help text is ellipsized.
5. Calibration is hidden behind "Choose radio profile" on Devices; there is no first-connection assistant.
6. The screen is not about the selected device: keyboard sessions show a gamepad preset and gamepad buttons.
7. Keyboard flight keys and shortcuts cannot be remapped.
8. FPV quad arming from a radio requires binding the **Landing gear** AUX; there is no visible "Arm" function.
9. "Clear"/"Remap"/"Learn axis" buttons have no action in their accessible names; the table-layout Invert checkbox has no name.
10. Close and Esc discard the whole draft, including a just-finished calibration, without asking.
11. Buttons is one flat list of about 38 actions for every vehicle; helicopter rows show on airplanes and vice versa.
12. Save errors are raw identifiers ("Binding conflict: camera_cycle and trim_left") in a footer clipped to 1–3 lines; conflicts are rejected, never offered as a swap.
13. Words disagree: the wizard says AILERON/ELEVATOR/RUDDER and "press Enter", Controls says Roll/Pitch/Yaw and the button says Next.

Details and file references: [findings A1–A15](../research/controls-ux-2026-11-12/README.md#findings-presentation-and-flow).

## Target experience

Copy, do not invent:

- **Setup assistant on first connection** (QGroundControl, Liftoff, VelociDrone): detect → identify → mode → calibrate → test → switches → save, one step per page, with a progress strip and Back/Next.
- **The device is the picture** (console games, Steam Input): a gamepad diagram with glyphs and leader lines, a generic two-gimbal transmitter with a switch row, or a keyboard keycap map. Pressing anything highlights it on the picture and in the action list.
- **Press to assign** (every PC game): select an action, "Move or press the control…" with a countdown and Esc/Back to cancel; axes, buttons and switch positions are detected, never typed.
- **Conflicts resolved in place**: "R1 is already Smoke. Swap / Replace / Cancel".
- **Search by input** (Microsoft Flight Simulator): press a control to jump to its action.
- **Live curve** (MSFS, DCS): deadzone/expo graph with a moving dot on the current stick value.
- **Reset** per category and for the whole profile; changes stay in the draft until Save.

## Information architecture

Replace the centred 1160×780 modal with a full-screen **Controls workspace** at 1080p (48 px safe inset, matching [menu redesign](menu-redesign.md#settings-and-controls)). Three regions:

| Region | Content |
| --- | --- |
| Left rail (≈320 px) | Device cards: icon/glyph family, display name, kind (Radio / Gamepad / Keyboard), status (connected, calibrated, needs setup), roles (Flight, Menus). "Set up this device" primary action. Keyboard is always a card. |
| Centre (device view) | The device picture with live input: two gimbal squares and switch lamps for radios; gamepad diagram with sticks, triggers and buttons; keyboard keycap map. Tabs below it: **Sticks**, **Switches & buttons**, **Response**, **Profile**. |
| Right (actions) | Action list for the active vehicle (airplane, helicopter, FPV quad, car), grouped Flight / Camera / Equipment / Menu, each row a binding chip (glyph or physical label) with a conflict badge and the live highlight. |

At 1440p/4K the regions widen and the picture scales (vector drawing, no bitmaps). At 720p the right column moves under the centre and the rail collapses to a device picker; this is the tertiary target.

## Components

All are `Control._draw()` or existing-glyph widgets in `app/ui/controls/` (new folder), presentation-only, fed by the same preview providers the current screen uses (`axis_preview_provider`, `button_preview_provider`).

| Component | Draws | Used by |
| --- | --- | --- |
| `StickGimbalView` | Square gimbal, live dot with short trail, centre cross, deadzone ring, measured min/max envelope, requested-direction arrow and target zone | Calibration, Sticks tab, test step |
| `ChannelBar` | Bidirectional or one-ended (throttle) bar with endpoint ticks, centre mark and percent | Calibration, Sticks tab, radio channel monitor |
| `ResponseCurve` | Output vs input for deadzone + expo (+ rate), live dot | Response tab |
| `BindingChip` | Kenney glyph or physical label ("Sa ▲", "Axis 5 > 60 %", key cap), conflict badge, live-press glow | Action list, conflict dialog |
| `SwitchLever` | 2/3-position lever with the active position lit and its label | Switch capture, radio view |
| `DevicePicture` | Gamepad layout from existing glyph SVGs at fixed anchors with leader lines; generic transmitter (two gimbals, switch row, no brand); keyboard map from `KeyCap` | Centre region |
| `CaptureOverlay` | "Move or press the control for *Flaps*…", countdown ring, detected control preview, Esc/Back cancel | All assignment |

## Guided flows

### Setup assistant (all devices)

Opens automatically for a newly connected unknown device, and on demand from its card ("Set up this device"). It never starts flight and never saves without the final step.

1. **Identify.** Show the detected name and suggested kind with pictures: Radio / Gamepad / Joystick. Unknown devices must choose (existing rule). JETI and recognised gamepads preselect.
2. **Mode.** Mode 1 / 2 (radios also 3 / 4 if the input owner adds them) as two transmitter pictograms showing which stick does what; gamepads also offer "Triggers throttle".
3. **Calibrate** (radios and raw joysticks only; gamepads skip). See below.
4. **Test.** Move everything; gimbals, bars and a small aircraft silhouette deflecting ailerons/elevator/rudder confirm direction. A "Reverse" toggle sits next to each channel that looks wrong.
5. **Switches & buttons.** Suggested essentials for the active vehicle (radio: Arm/throttle cut, flaps, gear, smoke, camera, restart, pause; quad: Arm, flight mode). Press-to-assign each, or Skip.
6. **Summary & Save.** Picture with every assignment labelled; Save, Back or Cancel. Save uses the existing transactional store.

### Radio calibration (EdgeTX, OpenTX, JETI, other USB radios)

Keep `rc_calibration.gd` as the state machine; replace the text card with a visual one for both the preflight and in-flight routes (one shared view, two hosts).

- Before step 1, an **EdgeTX/OpenTX checklist** card: model USB Joystick (Classic) selected, internal/external RF off, sticks calibrated on the radio, no duplicate expo (radio or simulator, not both). JETI: USB joystick mode and stick mode. Links to the EdgeTX USB joystick page.
- Each step shows both gimbals with an animated arrow to the requested position and a target zone; the detected channel lights up as the pilot moves ("Detected: channel 3"), and Next becomes primary only when the step's evidence is valid (existing thresholds). Errors from the wizard appear as a coloured banner under the picture.
- A **channel monitor** strip shows all raw axes as `ChannelBar`s, so a pilot sees which ones move.
- The final verification (throttle FULL then LOW) is an animated throttle bar with two check marks.

### Press-to-assign and conflicts

One `CaptureOverlay` for buttons, axes as buttons (Learn axis), switch positions and keys. It keeps today's capture ownership: selected device only, consume the release, device loss cancels. On conflict it offers Swap, Replace or Cancel; Swap is atomic in the draft. "Hold to clear" and a Clear action remain.

### Keyboard

The keyboard card shows the current map as key caps on a keyboard picture (physical positions, labelled in the player's layout through `key_labels.gd`). With D6-UX-02 the flight axes and shortcuts become remappable through the same overlay; until then the keyboard view is read-only and says so.

## Steps, in order

| ID | Priority | Work | Acceptance evidence |
| --- | --- | --- | --- |
| UI-15-UX-00 | P0 | Baseline: native 1080p captures of today's Controls and calibration with a synthetic radio and gamepad; list current controller UI tests that pin layout or node names. | Captures outside git; a test inventory in the evidence README. |
| UI-15-UX-01 | P0 | Visual calibration: `StickGimbalView`, `ChannelBar`, channel monitor and checklist in one shared calibration view hosted by `radio_calibration_setup.gd` and `calibration_card.gd`. No change to `rc_calibration.gd` thresholds or steps. | Existing calibration/disclosure tests pass; new widget tests (dot position, envelope, throttle one-ended); native 1080p capture of every step with a synthetic radio. |
| UI-15-UX-02 | P0 | Quick wins on today's screen: accessible names on every Remap/Clear/Learn axis/Capture/Invert ("Remap Flaps down"); truncated help becomes a focusable "?" popover (reachable by gamepad); friendly error text naming actions by label, with the field focused; one glossary (Roll/Pitch/Yaw/Throttle with "aileron/elevator/rudder" as secondary words) and button-accurate prompts ("press Next"). | Debug-bridge `look` shows unique names; EN/ES 100/200 % captures at 1080p with no ellipsis; glossary check in source and `es.po`. |
| UI-15-UX-02b | P0 | Unsaved-changes guard: a dirty marker on the title and Save; Close/Esc with a dirty draft asks "Save / Discard / Keep editing" (Save goes through the existing transactional Save; Esc during capture still only cancels the capture). | Tests: clean close is immediate; dirty close asks; calibration-only draft counts as dirty; Discard leaves the active profile unchanged. |
| UI-15-UX-02c | P0 | Vehicle-aware action list: show the active vehicle's actions first (airplane, helicopter, FPV quad, car) using `action_capabilities`; other vehicles' rows behind "Show all vehicles". | Rows match capabilities for each activity; hidden rows keep their bindings and validation. |
| UI-15-UX-03 | P1 | Controls workspace layout (full screen, three regions, device cards, a real Keyboard card instead of a default gamepad profile when no device is present). Split `controller_setup.gd` behind a façade, one seam per step: `ControllerSetupDraft` (draft/context map, calibration and menu origins, validation), `BindingCapture` (input routing, release tokens, axis capture, generation checks), one view per page, a validation presenter. Keep the public signals/methods used by `app_root.gd` and the private names and node names tests use until those tests are migrated in the same step. | Controller setup/menu/capture/scroll suites pass; 1080p, 1440p, 4K, 720p captures; focus and gamepad-only navigation of every page. |
| UI-15-UX-04 | P1 | `DevicePicture` and live highlight: gamepad diagram (Xbox/PlayStation/Nintendo/generic glyphs), generic transmitter, keyboard map; pressing a control highlights it and its action row. | Synthetic gamepad/radio events light the right part; prompt family override still presentation-only. |
| UI-15-UX-05 | P1 | Press-to-assign for **axes** on the Sticks tab ("Move the stick you want for Roll") and for AUX axes (radio switches and pots exported as axes), measuring Off/On endpoints by moving the control, reusing `ActionAxisCapture` and the wizard's thresholds; the index/endpoint SpinBoxes move to an Advanced disclosure. A jittering radio throttle must not end capture. | Tests: largest-delta detection, ambiguity rejection, inversion detection, cancel, device loss, draft only. |
| UI-15-UX-06 | P1 | `CaptureOverlay` with conflict Swap/Replace/Cancel and search-by-input; reset per category. | Existing conflict/field-error tests plus swap atomicity, reset scope and search routing. |
| UI-15-UX-07 | P1 | Setup assistant (six steps) for new devices and on demand; existing explicit-kind and "no automatic calibration" rules kept (the assistant asks). | Synthetic journeys: Xbox, DualSense, EdgeTX-like radio, JETI fixture, unknown joystick; Cancel at each step leaves the active profile untouched. |
| UI-15-UX-08 | P2 | `ResponseCurve` on the Response tab with live dot; trigger-throttle presets keep their disabled deadzone/expo. | Curve matches `conditioning` output at sampled points (same function, not a copy). |
| D6-UX-01 | P1 | Named vehicle functions: **Arm** and **Flight mode** for the quad as remappable actions/AUX (today arm reuses the gear AUX, gamepad arm/mode are hard-coded LB/RB and mode cannot come from a radio), with migration of existing gear-bound arm profiles, shown in the action list for the active vehicle. | Multirotor input tests: arm from the new binding, migrated profiles keep arming, fresh-OFF arming rule unchanged. |
| D6-UX-02 | P2 | Keyboard remapping for flight axes and shortcuts as profile data (physical keycodes), with conflict checks and reset; `controls_reference.gd` reads the effective map so Help/Home/hints stay consistent. | Keyboard/controls-reference tests updated; replay of a keyboard flight is unchanged with the default map. |
| UI-15-UX-09 | P2 | Glyph subset extension from the pinned Kenney 1.5 archive: LT/RT, L2/R2, ZL/ZR, stick directions; provenance updated. | PROVENANCE lists each new file and SHA of the archive; no generated art. |
| UI-15-UX-10 | P2 | Formative usability: at least three first-time users per family available (radio, gamepad, keyboard) complete "set up and fly" without help. | Task log: time to first flight (targets from [controller support](controller-support.md#physical-acceptance-procedure): gamepad < 60 s, radio calibration < 3 min), wrong turns, failures. |

Hardware qualification rows in [controller support](controller-support.md#hardware-matrix) and [JETI](jeti-support.md) remain separate gates; this plan's captures with synthetic devices do not close them.

## Contracts the redesign must keep

- Draft/Save/Cancel: nothing activates or persists before Save; a failed Save leaves the active profile. Calibration writes only the draft.
- Capture: selected device only, release consumed before navigation resumes, device loss/focus loss cancels, maintained switches captured by transition.
- Radio safety: fresh low-throttle arming, connection generations, verified radio menu proofs invalidated by relevant edits, throttle excluded from menu navigation.
- Explicit device kind for unknown devices; recognised family names never imply channel order.
- Glyph family is presentation-only; bindings are stored by physical control.
- No live apply: widgets edit the draft only; previews never reach the aircraft.
- A gimbal or test preview is never centre/OFF evidence for verified radio menus or arming; mapping/action edits still invalidate menu verification.
- Back and Pause recovery bindings stay mandatory; radio navigation locks stay.
- Calibration keeps non-AETR settings and AUX and still reports `aux_warning`.
- The in-flight calibration card never takes focus; it shares the visual widget, not the presenter.
- Known gamepads are not reclassified as radios and calibration never starts by itself, without a separate owner decision. A radio that SDL reports as a known gamepad needs F1 evidence first.
- Graphics/UI changes do not alter simulation input values, conditioning or physics.

## Explicitly out of scope

- Branded transmitter art (EdgeTX/RadioMaster/JETI) without permission; the generic transmitter drawing is enough. A JETI-branded view stays behind [UI-15-JETI-03](jeti-support.md#steps-and-acceptance).
- Hardware mapping (SDL GameControllerDB edits), firmware changes, EdgeTX-side mixing features.
- Third-party glyph addons duplicating `controller_prompts.gd`.
- Force feedback, motion controls and HOTAS expansion.
- Radio-side shaping in the simulator (curves, rates, mixes, channel reorder, failsafe): it duplicates EdgeTX and risks double expo.
- 3D animated controller models: performance cost on modest PCs without clarity gain.
- Per-vehicle profiles: `controller_profile.gd` has no vehicle field; the vehicle-aware list (UI-15-UX-02c) covers the clarity need first.

## Verification

Follow the [verification scope](../tools/shared.md#verification-scope): parse changed GDScript, run controller setup/menu/capture/calibration/AUX/profile tests touched by each step, use the [debug bridge](../../tools/debug/README.md) for native captures (1080p first, then 1440p/4K, then 720p; EN/ES; 100/200 % text) and `debugctl monkey` on the Controls workspace. Keep screenshots out of git unless a step's evidence needs a specific one. Input-side steps (D6-UX-*) also run the multirotor/keyboard/flight-action suites and the flight-logging replay rule if a default changes.

## Risks

- **Large file split.** `controller_setup.gd` is 3,339 lines with many tests bound to node names. Extract page by page behind the existing public API; rename nothing tests rely on in the same step.
- **Two calibration hosts.** Build one view, two thin hosts; do not fork behaviour.
- **Assistant fatigue.** Always skippable; never auto-reopens after Cancel for the same device in a session.
- **Performance.** Live views redraw only while visible and only on changed samples; no per-frame allocation (graphics budget rule).
