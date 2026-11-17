# EdgeTX airplane controls plan

Status: phase 1 software implemented 2026-11-17 ([implementation evidence](../research/radio-input/D6-ETX-01/README.md); captures, F1 in the quad scene, the banner and hardware gates open); owner decisions pending for phases 2 and 3. Goal: when an EdgeTX/OpenTX radio is plugged in over USB, one short guided setup leaves **every stick and switch working for airplanes**: sticks, retractable gear, flaps with real detents, smoke, restart and dual rates — applied by the radio, or (phase 3) by OpenRC from each aircraft's manual. An in-flight help panel names the radio's own switches ("CH5 · SD → Landing gear") and says who applies rates and the flap mix. [Audit, EdgeTX sources and evidence](../research/radio-input/D6-ETX-00/README.md); no radio was connected for this audit.

Phase 1 extends existing contracts only. Phases 2 and 3 change two of them and start only after the owner decides (see [Decisions](#decisions-requested-from-the-owner)). Related homes: [controller support](controller-support.md) (sampling, arming, hardware gates), [controls setup UX](controls-setup-ux.md) (workspace, capture overlay, Setup assistant), [JETI support](jeti-support.md) (maintained-switch groups), [drone racing §17.1](drone-racing.md#171-dr-14d-preconfigured-controls) (quad arm/mode), [flight overlays](flight-overlays.md) (control guide, HUD-11-R2).

## Ownership and step IDs

| Prefix | Owner | Paths |
| --- | --- | --- |
| D6-ETX-* | Input (physics track, D6) | `app/input/`, `app/tests/test_edgetx_*` and the existing AUX/profile tests named per step |
| D6-ETX-08 | Physics/session, owner-approved | `app/sim/flight_session.gd` (rate selection only) |
| UI-15-ETX-* | UI | `app/ui/controls/`, `app/ui/controller_setup.gd`, `app/ui/help_screen.gd`, `app/i18n/` |
| HUD-ETX-* | Flight overlays | `app/render/overlays/controls_guide.gd`, overlay snapshot, `app/ui/controls_reference.gd` |
| F1-ETX-*, F4-ETX-* | Controller hardware gates | Evidence under `docs/research/radio-input/` |

`app/main.gd` and `app/vehicles/multirotor/` are shared: coordinate with their owners. One writer per path.

## Target experience

1. Plug in the radio (model set to **USB Joystick (Classic)**, RF off). OpenRC recognizes it and shows a non-blocking offer: *"EdgeTX radio detected — set up airplane controls (about 1 minute)"*. Nothing changes until the pilot accepts and saves; a saved profile always wins.
2. The Setup assistant shows the layout card below, calibrates the sticks (existing wizard, with every radio rate switch at 100 %) and runs a **switch check**: "Flip SD (landing gear) to DOWN… now UP". Each function binds to whatever control actually moved; any function can be skipped.
3. Save. In flight the control guide (open by default in the Pilot overlay preset; **F1** toggles it) lists each function by channel and switch with live state ("Gear: Up", "Flaps: take-off 33 %", "Dual rates: on your radio") and says when a switch must be cycled to take control.

## OpenRC EdgeTX layout v1

Channels are a recommendation for the radio's mixer: OpenRC binds by observed movement, so another layout also works. Switch letters follow the EdgeTX Plane wizard where it has a default. The transport column is **expected** until F1-ETX-01 records hardware.

| CH | Airplane | FPV quad (phase 2, same profile) | Suggested source | Expected Classic transport | Why |
| --- | --- | --- | --- | --- | --- |
| 1–4 | Aileron, elevator, throttle, rudder (AETR) | Roll, pitch, throttle, yaw | Sticks | Axes | Calibration establishes order and direction |
| 5 | **Landing gear** (OFF = down) | Arm (high end only) | SD (wizard gear) | Axis | Kept off CH7/CH8 |
| 6 | **Flaps**: up / take-off / landing | Flight mode | SA (wizard flaps), 3-position if available | Axis | Kept off CH7/CH8 |
| 7 | Dual-rate switch, **phase 3 and only when OpenRC applies rates** | — | SC (wizard D/R) | Axis | Optional |
| 8 | Free | Free | — | Axis | CH7/CH8 order may differ on Windows; absent on Linux Classic |
| 9 | Restart (momentary) | Restart on the pad | SH | Button 1 | Same as DR-14d |
| 10 | **Smoke** (2-position) | — | SE or SB | Button 2 (pressed when channel > 0) | Buttons avoid the CH7/CH8 problems |
| — | Throttle cut | Throttle cut | SF, radio Special Function "Override CH3 −100" (wizard default) | — | Stays on the radio; OpenRC sees idle |

Until phase 3, dual rates and expo stay in the radio's Inputs (wizard style: SC, 100/75/50 %, expo 30). Expected Linux Classic behaviour (inference, [E5](../research/radio-input/D6-ETX-00/README.md#1-edgetx-facts-primary-sources)): six axes as a gamepad, no CH7/CH8. OpenRC-owned rates there would need Advanced mode (interface Joystick; a 3-position switch as three "Normal" buttons) or radio-owned rates.

## Design

### Recognition (D6-ETX-01)

Classify a device as `radio` from the USB pair `1209:4F54` when SDL does not report it as a known gamepad. The broad family-name list in `edgetx_radio.gd` (it includes "pocket", "boxer", "zorro") only selects the offer and draft for devices that are not `known`; it never reclassifies a device. A known gamepad with the EdgeTX pair (expected on Linux Classic) is reclassified only after F1-ETX-01 evidence and an owner decision, as [the controls contract](controls-setup-ux.md#contracts-the-redesign-must-keep) requires. Existing name-token promotion (`RcInput.RADIO_NAMES`) is unchanged.

### Airplane preset and switch check (D6-ETX-02…04, UI-15-ETX-01)

Preset `edgetx_airplane` ("EdgeTX airplane", revision 1) is an **intent table** — function, suggested channel and switch, safe OFF position — plus AETR on axes 0–3 as every radio preset. Its AUX bindings are created only by the switch check; skipping a function leaves it unbound. After F1-ETX-01 confirms an OS's mapping, the preset may carry that OS's defaults, as DR-14d does for the quad.

For each function the switch check asks for the OFF position, then each other position, and binds the control that moved: an axis (largest delta; endpoints and 2 or 3 resting positions learned), a button (level), or a maintained-switch group (Advanced "Normal" buttons). It reuses `ActionAxisCapture`, the capture overlay and the existing rejection rules. OFF is learned, not assumed: gear OFF = down, flaps OFF = up, smoke OFF = off.

The starting draft follows the activity that opened Controls: airplane → `edgetx_airplane`, quad → `edgetx_fpv` (unchanged for FPV pilots).

Binding changes, each with known-answer tests and bit-identical amounts when the new fields are absent (`test_jeti_runtime.gd:163` and `test_controller_aux_runtime.gd:54` assert 0.5 for a centred flap axis):

- **Presentation metadata (D6-ETX-03):** optional `channel` (1–32) and `label` (≤ 24 characters) on axis and button AUX bindings and on the restart action. `SmokeAux.valid_binding` validates `label` only for switch groups today; extend validation, never values.
- **Positions and flap detents (D6-ETX-04):** axis bindings gain optional learned `positions` (resting values of a 2- or 3-position switch), and `aux.flaps` an optional `detents: "aircraft"`. With both, positions map to the aircraft's detents: up / take-off fraction / full (P-51 1/3, Vantage 0.4), or up / full. The airplane activity supplies the detents when an aircraft loads (`main.gd` already computes them). This is new semantics in `SmokeAux` and `RcInput.auxiliary_amount`, outside the solver identity; flight logs already record the requested flap fraction.

Preset touchpoints: `ControllerProfile.defaults()` allowlist and name (`controller_profile.gd:38, 62-66`); diagnostics preset enum (`controller_diagnostics.gd:96`); Controls preset picker, help text and apply path (`controller_setup.gd:2645-2652, 2683`, modelled on `_apply_edgetx_fpv_preset`) and its key-copy lists (`controller_setup.gd:2715, 2754, 2793`).

### Rates in phase 1

The radio applies rates and expo, as today. The guide says "Dual rates and expo: on your radio"; the card shows the wizard-style setup and the calibration note.

### In-flight help (HUD-ETX-01…04)

- **Control guide, radio rows:** "Landing gear · CH5 · SD — Up", "Flaps · CH6 · SA — take-off 33 %", "Smoke · CH10 · SE — off", "Dual rates — on your radio", "Flap → elevator mix — OpenRC/radio" (existing owner field), "Throttle cut — on your radio", "Restart · CH9 · SH". Without metadata: "Axis N" / "Button N", as today.
- **Sync cue:** while a bound AUX has no fresh OFF evidence (`auxiliary_request_valid() == false`), its row says "Flip SD to DOWN to take control", and the warnings bar shows it once.
- **F1** toggles the guide in the airplane flight (`main.gd`) and the quad scene (`multirotor_scene.gd` has its own key handler); a bindable `controls_help` action and the existing Esc → Flight overlays path remain (macOS laptops send F1 only with Fn). Helicopter, airship and ground scenes are out of scope here. `controls_reference.gd` gains the row, which `test_controls_reference` enforces.
- **Flight-start banner,** once per profile revision: "EdgeTX · gear SD · flaps SA · smoke SE · F1 help", auto-hiding after 8 s outside the 1080p instrument areas.
- **Help screen:** replace the contradictory "select Advanced Joystick" text (audit A10) with the Classic checklist and the card.

### Phase 2: one profile for airplane and quad (D6-ETX-05, D6-ETX-06)

A pilot flying both vehicles needs CH5/CH6 to mean gear/flaps on the airplane and arm/mode on the quad, as each EdgeTX model does. Today two AUX channels may never share a control (audit A7). Proposed rule: sharing is allowed only between disjoint vehicle families derived from `AUX_CHANNEL_CAPABILITIES` (quad: `arm`, `flight_mode`; airplane: the rest); same-family duplicates, AETR overlaps and action/AUX conflicts stay errors. Every user of `ControllerActions._same_aux_control` must agree: profile validation (`controller_actions.gd:259-269`), action-versus-AUX checks (`:289, :297`), `aux_owned_buttons` (`:530`), `binding_conflicts_aux` (`:547`, used for the quad's restart in `multirotor_input.gd`), `effective_bindings`, and the Controls conflict/swap codes (`controller_setup.gd:80-82, 4403-4466`) and capture.

The combined preset derives the quad's bindings from the **same learned CH5/CH6 controls with their own endpoints**: arm ON only at the high position (DR-14d), flight mode low Angle / middle and high Acro; gear and flaps keep theirs. Values are never copied between families. Saved `edgetx_fpv` profiles get an "Add airplane switches" draft merge (UI-15-ETX-03). This keeps vehicle meaning in the AUX ids, not a profile vehicle field, but it narrows the [per-vehicle-profile exclusion](controls-setup-ux.md#explicitly-out-of-scope) and needs decision 1.

### Phase 3: OpenRC standard rates for radios (D6-ETX-07, D6-ETX-08)

This **reverses** a standing contract: [controls setup UX](controls-setup-ux.md#explicitly-out-of-scope) excludes simulator shaping for radios ("duplicates EdgeTX and risks double expo"), and [D6e](../research/radio-input/D6e/README.md) and `flight_session.gd:4169` state that a radio always passes through. It needs decision 2, a DECISIONS entry and an amended out-of-scope line before any code lands.

Design: an explicit profile field `rates_owner`, modelled on `flap_elevator_mix_owner`. `transmitter` remains the default for every radio profile, new or saved; `simulator` is an opt-in at setup ("OpenRC applies each aircraft's manual rates — set your radio's Inputs to 100 %, no D/R, no expo"). With `simulator`, the session shapes radio sticks with `controls.rates` (normal, sport, full) and their expo, and a `rates` AUX switch selects the profile by learned position (2 positions: normal / the session's high profile; 3: normal / sport / full, where full means raw sticks). A bound rates AUX owns the function: `rates_toggle` and N are refused with a note, as gear does. Joystick-kind profiles keep today's simulator rates.

The input part (D6-ETX-07) and the session part (D6-ETX-08) land together; validation rejects `rates_owner = "simulator"` until both exist, so no profile can claim OpenRC rates that nothing applies.

- **Input touchpoints (D6-ETX-07):** `AUX_CHANNEL_IDS` and `AUX_CHANNEL_CAPABILITIES` (`controller_actions.gd:13-15`); `RcInput._extra_aux` and `_AUX_ACTION_DEFAULTS` (`rc_input.gd:53-54`); `RcCalibration.EXTRA_AUX_CHANNELS` (`rc_calibration.gd:31`, or recalibration drops the binding); diagnostics AUX iteration and owner field (`controller_diagnostics.gd:96-114`); profile upgrade and calibration merge (`controller_profile.gd:138-145, 231-248`); Controls key-copy lists; deliberate update of `test_multirotor_arm_mode_aux.gd:143-145, 160-161`, which pin the AUX list.
- **Session and consumers (D6-ETX-08):** `rate_profile_available()` admits radio profiles whose owner is `simulator`; the AUX is read at the existing input boundary beside flaps and gear (`flight_session.gd:3110-3122`) and every change emits `rate_profile_changed`, which the recorder logs (`flight_log.gd:158, 336-338`); `main.gd:1955-1961` and the guide's rates row (`controls_guide.gd:166-176`) stop keying on profile kind. Solver identity changes: requalify exact replay and the native stage.

Applying rates in `app/input/` instead was rejected: it duplicates `shape_sticks`, hides the active profile from flight logs and splits the HUD label from the session.

## Decisions requested from the owner

1. **Phase 2:** allow vehicle-scoped AUX sharing so one EdgeTX profile serves airplane and quad (recommended), instead of keeping separate profiles per vehicle.
2. **Phase 3:** reverse the "radio always applies its own rates" contract by adding an opt-in `rates_owner = "simulator"`, with the small `flight_session.gd` change and its requalification. Recommended default remains the radio.
3. **F1** as the in-flight help key (airplane and quad).
4. Whether a shipped EdgeTX model template or own Lua setup tool is worth researching (UI-15-ETX-04).

Record accepted answers in [DECISIONS](../DECISIONS.md) and amend the affected plan lines before the dependent step lands.

## Steps

| ID | Priority | Work | Acceptance evidence |
| --- | --- | --- | --- |
| D6-ETX-00 | done | Audit and sources. | [Evidence](../research/radio-input/D6-ETX-00/README.md) |
| F1-ETX-01 | P0 | Capture one physical EdgeTX radio with `--input-report` ([format](../research/radio-input/F1/README.md)) on native Windows, then Linux and macOS if available: Classic and Advanced (Joystick interface, 3-position Normal buttons), a test model with one switch per channel CH5–CH10. Record Godot `name` and `raw_name`, VID/PID, `known`, GUID, per-channel axis and button indices and ranges. | Annotated report per OS/firmware/mode; confirms or corrects E5/E6, A2/A3 and the card's transport column. |
| **Phase 1** | | | |
| D6-ETX-01 | P0, software done | Recognition by USB pair for non-known devices; names select only the offer/draft. | `test_edgetx_airplane`: every maker by `1209:4F54` (decimal, hex, int IDs), name-only, JETI claim, a known gamepad with the pair stays a gamepad. |
| D6-ETX-02 | P0, software done | `edgetx_airplane` intent-table preset (`EdgeTxRadio.AIRPLANE_LAYOUT`) and its touchpoints; draft follows the opening activity; `edgetx_fpv` unchanged. | Preset validates; diagnostics enum; `test_edgetx_switch_check` (airplane draft for a recognized radio); `test_mr_controls_presets` unchanged. |
| D6-ETX-03 | P1, AUX done | `channel`/`label` metadata on axis/button AUX bindings. Restart-action metadata is open (the guide shows "Button N"). | Validation tests; amounts identical with and without metadata. |
| D6-ETX-04 | P1, software done | Aircraft flap detents (`detents: "aircraft"`): equal position bands map to up / take-off / full, so no learned-position field was needed. | Known-answer tests: P-51 → 0 / 1/3 / 1, Vantage → 0 / 0.4 / 1, two detents → 0 / 1, linear without the field or detents; `test_jeti_runtime` and `test_controller_aux_runtime` unchanged. |
| UI-15-ETX-01 | P0, software done; captures open | Switch check: on the EdgeTX airplane preset the assistant's Switches step lists gear, flaps, smoke and restart with "CH5 · SD · start at DOWN"; an unbound AUX learns an axis switch (OFF→ON→OFF) or a button pressed after OFF, with conflict Swap/Replace; layout channels get their names; flaps opt in to detents. The existing one-time "New controller detected" offer and calibration steps are reused. | `test_edgetx_switch_check` (axis, button, off-layout axis, other presets unchanged). Open: EN/ES captures at 1080p, then 1440p/4K, 720p last; Linux-order and Advanced-button journeys need F1-ETX-01. |
| UI-15-ETX-02 | P1, partly done | Help text fixed (A10) and gives the layout; preset help text in Controls; player guide paragraph in [First launch](../FIRST-LAUNCH.md). Open: a test tying the guide text to the layout constants. | EN plus seven catalogs. |
| HUD-ETX-01 | P0, software done; captures open | Control guide radio rows: "CH5 · SD" from metadata, throttle cut and flap-mix owner rows for radios, rates row unchanged ("The radio sets its own rates"). | `test_edgetx_airplane` (text); `test_overlay_manager`. Open: 1080p EN/ES captures, 200 % text. |
| HUD-ETX-02 | P0, airplane done | F1 toggles the guide in the airplane flight; keyboard reference row. Open: the quad scene (its file was under concurrent edit) and a bindable `controls_help` action. | `test_controls_reference`, `test_edgetx_airplane`. |
| HUD-ETX-03 | P1, guide done | The guide row says "Move SD to OFF to take control" while a bound gear/flaps/smoke switch awaits OFF. Open: the one-time warnings-bar entry. | Covered by source review; runtime test with a live session open. |
| HUD-ETX-04 | P1, open | Flight-start banner once per profile revision. The overlays have no transient-message API yet; the guide is shown by default in the Pilot preset. | — |
| **Phase 2** (decision 1) | | | |
| D6-ETX-05 | P1 | Vehicle-scoped AUX sharing across every `_same_aux_control` user and the Controls conflict/capture path. | Gear+arm and flaps+mode on one axis allowed; gear+smoke, arm+mode, action+AUX rejected; capture accepts arm on a control owned by gear; quad arms only from `arm` when bound; airplane ignores quad AUX. |
| D6-ETX-06 | P1 | Combined preset with quad bindings derived from the learned CH5/CH6 controls. | Middle position never arms; derived endpoints independent of gear/flaps; Linux-order fixture keeps arm off the throttle axis. |
| UI-15-ETX-03 | P2 | "Add airplane switches" for saved `edgetx_fpv` profiles. | Draft merge keeps calibration and quad AUX; nothing saved before Save. |
| **Phase 3** (decision 2) | | | |
| D6-ETX-07 | P1 | `rates_owner` and the `rates` AUX in the input layer, with every touchpoint above. | Profile, upgrade, calibration and diagnostics tests; legacy radio and joystick profiles keep their rates; the AUX-list tests updated deliberately. |
| D6-ETX-08 | P1 | Session rate selection for `simulator`-owned radios, signal emission, guide/main consumers. | `test_rates`, `test_controller_rates`, recorder tests; exact replay of a recorded radio flight with a mid-flight rate switch; solver identity change recorded; native stage rebuilt or fallback reported. |
| **Later** | | | |
| D6-ETX-09 | P2 | Optional bindable actions for keyboard-only equipment: wheel brake (hold), wing fold, canopy, tailhook. | Capability-scoped action tests; unavailable equipment explained. |
| UI-15-ETX-04 | P2, research | EdgeTX model template or own Lua setup tool: YAML schema per radio family, switch availability, licence (EdgeTX wizard code is GPLv2: write our own). | Research note only; nothing shipped without a tested radio and owner approval. |
| F4-ETX-01 | P1 | Physical qualification on native Windows source and an exported package: detection, assistant, calibration, switch check; P-51 (gear, flap detents, smoke), Vantage (flap mix both owners), a fixed-gear aircraft (functions explained as unavailable); restart; phases 2–3 when delivered. | Per build/OS/firmware/radio report; Linux and macOS are separate rows. |

## Contracts kept

- Draft, Save and Cancel as in the controls plan; previews never reach the aircraft. Saved profiles are never rewritten; new fields default to today's behaviour.
- Radio arming (fresh low throttle), fresh-OFF AUX arming, disconnect protection and Back/Pause recovery are unchanged.
- A recognized family name proposes a draft; only calibration and the switch check establish channel order. Known gamepads are not reclassified without F1 evidence and an owner decision.
- One source per function: a bound AUX owns gear, flaps, smoke or rates; the matching press actions explain the refusal.
- Rates, expo and the flap mix are applied exactly once, by the side the profile names, and recorded for replay.
- Help and graphics changes do not alter input values or physics; display work follows the 1080p-first priorities.

## Out of scope

Radio firmware changes, EdgeTX mixer features inside OpenRC (curves, custom mixes, channel reorder, failsafe), per-vehicle profile storage, branded radio art, telemetry to the radio, trainer/buddy-box links, F1 help in helicopter, airship and ground scenes.

## Risks

- **OS mapping:** CH7/CH8 order and Linux gamepad remapping are inferred. Mitigation: bind by movement; intent-only preset until F1-ETX-01.
- **Double rates or expo:** both radio and OpenRC shaping. Mitigation: radio default, explicit opt-in owner, checklist, guide row.
- **Shared CH5 (phase 2):** a radio model built for the quad sends arm on CH5 while an airplane flies. On the ground the gear cannot retract with weight on the wheels (`flight_session.gd:4423, 5497`); the guide names each function per vehicle.
- **Solver identity (phase 3):** older logs lose exact-replay identity and the native stage may need rebuilding; isolated in D6-ETX-08 behind approval.
