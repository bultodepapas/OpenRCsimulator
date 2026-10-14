# Xbox, DualSense and general controller support plan

Status: proposed, 2026-10-14. Priority confirmed by the owner: Xbox and/or DualSense on Windows. The first deliverable is reliable fixed-wing flight and the complete primary menu flow with one selected controller. Radios, helicopter and ground-vehicle behavior must retain their existing contracts. Linux/macOS and additional controller families follow through explicit compatibility rows.

Build on Godot 4.7.2's SDL backend, existing RcInput, calibration, session holds and F1/F6 tools. The immediate repair is the gamepad-to-radio calibration path. Then add durable profiles, explicit device ownership, safe source transitions, remappable actions and controller navigation. Physical acceptance is required before advertising a model/connection as supported.

## Ownership and scope

This is an implementation plan under existing [track ownership](../README.md#tracks-plans-and-step-ids), not a new input framework or a new physics track. Source findings and primary references live in the [dated research](../research/controller-support-2026-10-14/README.md). Current player commands remain in [FIRST-LAUNCH](../FIRST-LAUNCH.md); developer commands remain in [TOOLS](../TOOLS.md#radio-diagnostics).

| Owner | IDs used here | Owned or coordinated files |
| --- | --- | --- |
| Physics/input | D6-GP-*, F1-GP-*, F3-GP-*, F4-GP-*, F6-GP-* | `app/input/`, input tests, fixed-wing session sampling; coordinate `app/sim/flight_session.gd` and `app/main.gd` |
| Product shell | UI-10-GP-*, UI-12-GP-*, UI-15-GP-* | `app/ui/`, `app/app_state/`, `app/app_root.gd`, `app/i18n/`, UI tests; implements F5 setup within these steps |
| Helicopter and ground vehicle | Shared integration gates in F3-GP-02/F4-GP-01 | Their existing sessions/adapters and tests; no transfer of HELI/RCV physics ownership |
| Desktop/release | F4-GP-01/02 evidence coordinated with DT/PT | Native exported packages, build identity and platform qualification |

Core scope: one active flight controller, optional separate selected gamepad for menus, persistent controls, Windows Xbox/DualSense USB/Bluetooth, keyboard/mouse recovery, English/Spanish prompts. Multiple connected devices are supported through selection and isolation; combining two controllers into one aircraft, trainer/student handover, arbitrary HOTAS axis expansion, console exports and advanced DualSense effects are outside the first delivery.

## Baseline and priorities

| Priority | Current finding | Required outcome |
| --- | --- | --- |
| P0 | K starts a radio-only wizard for a gamepad and can save it as `kind = radio` | Calibration must preserve the device's intended semantics. Provide recovery for already affected profiles. |
| P0 | First enumerated controller wins; a new connection can take over keyboard flight | Explicit choice and a paused handover; a connection alone never takes control of an active flight. |
| P0 | Gamepad rate throttle auto-arms; radio freshness and ground neutral handling differ | A defined state machine per control mode; no unexpected thrust or collective after focus, replug or profile changes. |
| P1 | Gamepad mapping/shaping is fixed; unknown pads default to radio semantics | Validated gamepad/joystick profiles, remap, inversion, adjustable deadzones and throttle modes. |
| P1 | Menus intentionally exclude every joypad; buttons mainly serve smoke AUX | Selected gamepad can configure, launch, pause, resume and exit without keyboard/mouse. Radios remain isolated. |
| P1 | Home instructions describe the wrong gamepad arming procedure | Instructions derive from the active profile, not just a device name. |
| P1 | Hardware tests are synthetic; F1 observes axes only | Native device/button/transport evidence and reproducible qualification rows. |
| P2 | No user-facing glyph/capability policy | Correct prompts and optional rumble; motion/light capabilities remain optional. |

Preserve the working protections: active-device loss already idles and pauses, radio profiles have strict validation, and gamepads already avoid double expo. Do not rewrite these as if they were absent.

## Target input architecture

```text
Godot SDL events and selected-device polling
              |
       device registry and connection generation
              |
       context router: flight / menu / calibration / capture
          /                                      \
  device profile and shaping               UI/action bindings
          |                                      |
  arming and handover gate                 selected UI controller
          |
  activity adapter: fixed wing / helicopter / ground vehicle
          |
  existing commands, rates, trims, actuators and 240 Hz simulation
```

Use small testable GDScript classes. Proposed additions are `controller_registry.gd`, `controller_profile.gd`, `controller_profile_store.gd`, `controller_actions.gd` and a small gamepad conditioning helper under `app/input/`. Add each only when its step needs it. Keep RcInput's pure sampling seam; there is no need for a native driver or a second SDL instance.

The registry owns enumeration and selection across Home and activities. A session consumes the selected source instead of independently selecting `pads[0]`. The UI owner owns routing and focus. Device callbacks update observations; simulation commands are sampled at the existing fixed-tick boundary. Button edges use a bounded queue/latch and are consumed once, even if several simulation ticks occur in one rendered frame. Paused frames do not accumulate rate throttle or queued flight actions.

Keep channel values in GDScript `float` and `PackedFloat64Array`. Godot motion-sensor vectors, if later used, are input-boundary data and must not become float32 simulation state. The change must not alter the solver, aircraft data, actuator laws, trace tick ordering or replay interpretation.

### Device ownership and identity

1. Enumerate all devices and display name, intended role, connected state and profile. Distinguish keyboard, gamepad, RC radio and unconfigured joystick. `is_joy_known` helps select a preset; it does not prove physical identity or RC suitability.
2. The current Godot device ID is a connection handle, never a persisted identity. Add an application connection generation and clear cached axes, button edges and arming evidence on selection/disconnect/profile changes.
3. Save profile UUID independently of hardware. Store normalized VID/PID, available serial, raw name, GUID, platform and observed backend hints as matching evidence. Missing metadata is allowed; serials can be absent or duplicated. Never infer a reliable transport from name alone; record user-confirmed USB/Bluetooth/adapter when necessary.
4. Prefer an unambiguous saved association. A family match may suggest a profile but must not silently grant flight ownership. Two identical devices use an explicit “press a button/move a control on this device” identification step while paused. Ambiguous reconnects stay unselected.
5. A USB/Bluetooth or firmware change can produce a new identity. Offer to reuse logical bindings, then verify range/inversion and neutral; do not silently copy calibration or reset to an unsafe default.
6. A second physical or virtual controller must not affect the selected source. Warn about ambiguous duplicate candidates without hiding or merging devices by name. Standalone SDL and Steam/other emulated paths get separate test records.

### Profile format and migration

Introduce `schema_version = 2` in `user://controller_profiles.cfg`. Keep existing `user://rc_calibration.cfg` read-only during migration and rollback. These names are proposed application storage, not new tracked configuration files.

| Section | Required data and rules |
| --- | --- |
| Identity | Profile UUID, user-visible name, `kind` (`gamepad`, `radio`, `joystick`), association evidence, preset revision |
| Axes | Logical channel, source axis, range kind, min/center/max where relevant, inversion; unique required flight assignments unless an explicit supported mix permits reuse |
| Conditioning | Per-axis deadzone and expo, existing aircraft-rate policy, optional outer calibration; finite bounded values, zero-width ranges rejected |
| Throttle | Explicit `stick_rate`, `trigger_absolute` or `radio_absolute`; rate, idle threshold and neutral requirements belong to that mode, not to brand detection |
| Actions | Semantic action to key/button/axis threshold, context, press/hold behavior; validate conflicts and keep a recovery route |
| Presentation | Glyph family `auto/xbox/playstation/nintendo/generic`, optional rumble enable/intensity; presentation never changes mappings |
| Auxiliary | Preserve validated smoke binding and existing unrelated extensions; capability-specific actions must not silently consume flight axes |

Load into a candidate, validate the whole profile, then activate and save through a temporary file with rollback on failure. Save failure is visible and keeps the last working configuration. Invalid/unknown versions cannot activate flight control. Do not overwrite the old file or delete it after the first successful migration.

Import valid legacy radio profiles without changing their output. A known gamepad with a legacy radio profile is ambiguous: offer “keep as radio/custom device” or “restore gamepad preset”, show the changed throttle semantics and require a paused neutral check. Do not automatically classify every saved radio profile as a corrupted gamepad. Provide reset-to-preset, duplicate profile and cancel-without-saving.

### Flight conditioning and presets

Apply calibration, scalar deadzone, one expo stage, aircraft travel rates and then trims in an explicit order. Preserve the current no-second-expo behavior. A radio keeps its transmitter curves. A flight stick is not a character movement vector: do not normalize roll/pitch together with `Input.get_vector`, which would couple their available command magnitudes.

Separate source kind from throttle mode. Today's `rates_active()` uses `is_rate_throttle()` as a proxy for gamepad versus radio; adding an absolute-trigger gamepad without correcting that predicate would incorrectly bypass the aircraft's normal rates. Both gamepad throttle modes must retain the gamepad shaping/rates policy.

For a calibrated centered scalar `x`, use `d(x) = sign(x) * max(0, (abs(x)-dz)/(1-dz))`, followed by `e(x) = (1-expo)*d + expo*d^3`. Clamp valid inputs to their configured range and reject NaN/infinity before use. The present 0.08 deadzone, 0.3 expo and 0.5/s throttle rate are migration defaults, not measured optima. Let the pilot adjust them with a live response preview. Diagnose noise at rest; do not silently add smoothing or extra latency.

| Preset | Flight binding | Arming and pause behavior |
| --- | --- | --- |
| Gamepad Mode 2, default | Right X roll, right Y pitch with pull-back positive; left X yaw; left Y rate throttle, up increases | Centered stick holds the virtual throttle. Initial throttle is zero except an explicit valid airborne-start policy. Neutral evidence and deliberate start/resume are required. |
| Gamepad Mode 1 | Right X roll, right Y rate throttle; left X yaw, left Y pitch | Same rate semantics. Synchronize actual mapping and HUD labels; today's HUD Mode 1/2 display preference alone must not be represented as a binding change. |
| Trigger throttle, fixed wing | Right X/Y roll/pitch, left X yaw, RT/R2 absolute throttle; unused left Y is unbound by default | Standardized trigger rest 0/full 1. Never apply the radio `(-1…1) -> (0…1)` conversion to an already normalized trigger. Require release before arming. |
| Radio/custom joystick | Existing independently calibrated AETR or user-selected channels and absolute throttle | Preserve unshaped channel output and the existing fresh event at or below 5% idle. Unknown devices stay unconfigured until roles/ranges are confirmed. |

Radio absolute throttle, spring-centered rate throttle and helicopter collective are separate concepts. Retain the helicopter's explicit airborne-start/collective policy; do not apply fixed-wing trigger presets to it automatically. Ground vehicles retain right-trigger acceleration, left-trigger braking and existing neutral gates. Shared infrastructure must not unify these semantics accidentally.

Only offer absolute-trigger throttle when an independent analog channel is observed. Digital-only or combined-trigger devices use the rate-stick preset unless the user explicitly configures another validated source. For an absolute-trigger airborne start, show the actual throttle in the paused preview, require release/arming first, and use the pilot's freshly observed setting at explicit launch; never substitute an unseen midpoint or silently inject the rate preset's stored throttle.

For a fixed-wing rate-stick preset, a runway start stages virtual throttle at zero; a validated airborne start stages the finite `start.throttle` value in [FlightSession](../../app/sim/flight_session.gd). Show that value while paused. After fresh neutral evidence and explicit launch, seed the integrator exactly once through `set_rate_throttle_for_start`; centered stick then holds it. A restart/respawn repeats the selected scenario's rule, never inherits the previous integrator value, and requires launch confirmation. Missing/out-of-range start throttle blocks launch. A reconnect or focus return is not a new scenario start and cannot silently reseed trim power. This intentionally makes fixed-wing gamepad starts consistent with the declared start condition; add command-level tests for runway, level, half-power and glide starts without changing the physics golden baselines.

Keep full throw at valid individual-axis endpoints; do not force a circular physical stick to produce unreachable simultaneous corners. Any later circular-to-square option needs its own feel study and command fixtures.

### State transitions and focus

Use explicit states such as `UNSELECTED`, `WAITING_FOR_NEUTRAL`, `READY`, `ACTIVE`, `HELD` and `LOST`; state names are implementation suggestions. A neutral state does not automatically resume a session.

| Trigger | Required transition |
| --- | --- |
| Connect while flying with another source | Register device and offer selection later; active commands remain with their current owner. |
| Explicit source/profile/mode switch | Hold session, clear transient controls, validate the candidate, obtain post-selection neutral evidence, then explicit resume. |
| Active disconnect | Preserve existing idle/neutral/failsafe pause; stop feedback, clear ownership and pending actions. No automatic keyboard or second-pad takeover. |
| Reconnect | Resolve association; ambiguity requires selection. Clear stale evidence, obtain neutral/release and require resume. |
| Menu or remap capture | Freeze flight and rate integration; only the top context consumes relevant actions. Closing the menu cannot also trigger a flight action. |
| Focus loss, sleep/resume | Hold and disarm applicable controls. Focus gain alone never resumes. Recheck connection/selection before accepting commands. |
| Invalid samples/profile | Stop command acceptance and surface a specific error; retain a safe recoverable session. |

For a gamepad, the proposed neutral gate is 200 ms inside the configured stick deadzones with bound analog triggers at or below 0.05, after post-transition input evidence and release of held action buttons. Check required bound channels only, never nonexistent axes. These are initial engineering settings to validate, not hardware measurements. If the backend never reports an untouched neutral axis, guide a short move-and-return/release; a default polled zero must not count as independent proof. Confirm that this does not trap controllers with sparse events.

For ordinary gamepad menu pause, preserve the virtual throttle while frozen and display it before explicit resume. On disconnect or profile change, reset to idle and show the change. Absolute radio throttle retains its established policy unless input was cleared or ownership changed; do not impose centered-stick arming on a transmitter. Helicopter recovery keeps collective/engine distinctions visible. Rate integrators advance only on accepted simulation ticks.

Focus loss preserves the fixed-wing rate-throttle value in a held snapshot, freezes integration and invalidates arming evidence. Focus return with the same still-connected generation requires fresh neutral/release, shows the held throttle and waits for explicit resume before restoring that value. Any intervening disconnect, source/profile change or OS sleep invalidates the snapshot: restart at idle with a visible message and require fresh arming/resume. If OS sleep cannot be distinguished reliably on a platform, uncertain continuity follows the lost-device policy; qualify this in native tests. Helicopters retain their explicit collective preview/recovery contract and never silently replace held collective with fixed-wing throttle zero; ground vehicles return neutral commands and require their existing neutral gate.

Pin `ignore_joypad_on_unfocused_application` deliberately only after testing the setting with these gates; turning it on can clear state without proving physical neutral. Do not infer a disconnected/frozen device merely from an interval without motion events: stationary controllers may be event-silent. A true heartbeat watchdog requires backend evidence not currently available to the sampler.

### Actions, navigation and prompts

Create semantic actions for pause, resume/confirm, back/cancel, camera cycle, view reset, trims, overlay preset, throttle cut, calibration and supported auxiliaries. Keep existing physical-key behavior as the default keyboard bindings. Reset/restart stays inside a confirmation flow rather than an easy accidental flight button. Keep OS-reserved Guide/PS buttons out of essential bindings.

Proposed common bindings are south button A/Cross for accept, east B/Circle for back, Menu/Options for pause, north Y/Triangle for camera cycle, and D-pad for menu navigation or flight trims according to context. A hold action for throttle cut may be added with a visible progress cue and remap; do not overload its button with another active flight action. Exact optional button assignments are verified in the UI step before freezing presets.

The UI adapter accepts events only from the selected menu gamepad. Use device-scoped InputMap events or an explicitly filtered adapter; never re-enable wildcard joystick UI actions globally. Keep radio axes/buttons isolated even if SDL reports the radio as a known gamepad. When ownership changes, replace only bindings owned by this adapter and clear held state.

Give every primary screen initial focus, visible focus, directional neighbors and predictable back behavior. Preserve focus across push/pop and dynamic lists. Test buttons, sliders, selectors, scroll areas, confirmation dialogs and empty/disconnected lists. Configure repeat centrally, initially 350 ms delay and 100 ms interval, then verify usability. Capture remapping consumes press and release before returning to the parent screen. A mouse move or harmless axis drift must not steal controller ownership or make prompts flicker.

Scope the keyboard-free acceptance flow precisely: Home -> Controls -> select/configure/test -> aircraft choice -> launch -> pause -> settings -> resume -> return Home -> quit. Audit all reachable screens, including Workshop and vehicle activities, before making a broader “full application controller support” claim. Auto-generated profile names allow completing the primary flow without text entry.

Reuse [Kenney Input Prompts](https://kenney.nl/assets/input-prompts) with pinned archive/hash/license. Match glyphs to the active binding and allow manual family override for virtual/emulated pads. Generic controls use neutral button labels when uncertain. Keep English/Spanish instructions and glyph alt text synchronized with the profile and action registry.

## Ordered implementation steps

All implementation rows below are **pending**. Each row is a separately reviewable change; its proof belongs under the existing input/UI evidence families. Dependencies name rows in this table.

| ID | Work and principal files | Dependency | Proof required | Estimate |
| --- | --- | --- | --- | --- |
| F1-GP-01 | Extend `input_report_data.gd` / `input_report.gd` with bounded button transitions, feature presence, selection/profile context and declared transport/firmware notes. Preserve v1 readers or version the report explicitly. | None | Existing F1 fixtures plus buttons, reconnect IDs, malformed metadata and bounded long-run report tests; native baseline reports for available pads | 0.5–1 day |
| D6-GP-01 | Prevent gamepad entry into the radio-only K wizard in fixed-wing/helicopter; correct Home/HUD instructions; expose safe preset recovery without silently deleting legacy profiles | None | Reproduce calibration conversion with a synthetic gamepad, then prove guard/recovery; legacy radio calibration and smoke preservation still pass | 0.5–1 day |
| F3-GP-01 | Add registry, explicit flight/UI ownership and reconnect matching; replace independent first-device choices in Home/session/ground integrations | F1-GP-01 | Two devices, duplicate descriptors, reordered IDs, connection during flight, already-connected alternate, firmware/transport ambiguity | 2–3 days |
| D6-GP-02 | Add profile schema/store/validation and transactional legacy import; persist role, mappings, shaping, actions and auxiliary bindings | D6-GP-01, F3-GP-01 | Valid radio output unchanged; gamepad type preserved; malformed/unknown schema rejected; failed write/cancel/rollback do not lose prior data | 2–3 days |
| D6-GP-03 | Add Mode 1/2 and fixed-wing trigger throttle; adjustable scalar deadzones/expo; explicit shaping contract and preview | D6-GP-02 | Endpoint/neutral/sign tests, independent triggers, rate integration at 30/60/144 render FPS, no second expo, trims unchanged | 2–3 days |
| F3-GP-02 | Integrate neutral, focus and handover states with fixed-wing holds; preserve helicopter collective and truck neutral/brake behavior | F3-GP-01, D6-GP-03 | Loss/focus/profile/menu transitions cannot inject thrust or resume; command-state regressions for all three activities | 2–3 days |
| UI-10-GP-01 | Controls screen: device and role selection, preset, live mapped/conditioned channels, calibration, test, reset/save/cancel and recovery messages; implements F5 | D6-GP-02, F3-GP-02 | New device setup without file edits; cancel leaves current settings intact; no input affects the aircraft during setup | 2–3 days |
| UI-15-GP-01 | Semantic actions and remap capture for keys/buttons/thresholds; conflict checks, hold/press rules and recoverable defaults | D6-GP-02, UI-10-GP-01 | Wrong device ignored; held button cannot double-trigger; duplicate conflict detected; pause/back recovery remains available | 1–2 days |
| UI-12-GP-01 | Selected gamepad menu routing, focus traversal, action prompts and free glyph import; audit primary flow and activity boundaries | UI-15-GP-01, F3-GP-02 | Keyboard-free primary flow on Xbox/DualSense; radio cannot navigate; nested dialogs, sliders and EN/ES readable | 3–4 days |
| F4-GP-01 | Native Windows source and exported-build qualification, physical matrix, release notes and guide update | All core input/UI rows | Required hardware rows and fault scenarios pass; published scope lists tested models/transports and remaining gaps | 2–3 days |
| F6-GP-01 | Input-to-command cost checks and filmed latency using F6 tools; compare baseline versus final on the same host | F1-GP-01; final after F4-GP-01 | Software timing and physical latency reported separately with distributions and uncertainty; investigate any extra frame/regression | 1–2 days |
| F4-GP-02 | Extend qualified rows to DualShock 4, third-party XInput/DInput, Switch-class/accessible controllers, RC radios, Linux and macOS | Windows gate | Each new model/mode/OS/transport independently passes; unsupported/missing capabilities have explicit status | 3–6 days per available coverage batch |
| D6-GP-04 | Optional bounded rumble and light feedback, disabled or configurable; use capability checks and stop on hold/loss/exit | Windows gate | No effect on input/physics; disabled/unsupported paths work; finite-duration effects terminate correctly | 1–2 days |
| D6-GP-05 | Optional motion-sensor camera experiment; adaptive triggers/advanced haptics only after a separate feasibility decision | Windows gate, owner need | Capability/calibration, USB/BT and performance evidence; fallback preserved; no claim of force feedback realism | Separate estimate after spike |

Core estimate: **18–28 engineering days**, approximately 4–6 working weeks for one developer with hardware available, including the Windows qualification and latency rows. This excludes waiting for devices, engine-backend fixes and optional breadth/features. Keep engine upgrades in a separate PR with an exact pin and complete regression evidence.

Suggested deliveries: first publish the calibration guard/recovery and baseline diagnostics; next deliver selected-device/profile/safety infrastructure; then complete UI/remap; finally qualify Windows packages. Do not advertise the final feature at an intermediate delivery.

## Verification and release gates

### Automated contracts

Extend relevant existing tests: `test_rc_input.gd`, `test_rc_calibration.gd`, `test_e2e_radio.gd`, `test_rates.gd`, `test_ui_input.gd`, `test_ui_pause.gd` and F1 tests. Add focused profile/registry/action tests only for the new contracts. Synthetic `Input.parse_input_event` checks event routing, not SDL enumeration or hardware compatibility.

Required cases include nonfinite values, missing metadata, reused connection IDs, two identical devices, button down before selection, simultaneous triggers, diagonal sticks, drift, inverted Y, zero-span calibration, profile-change rearming, write failure, disconnect inside the wizard, reload, and keyboard fallback chosen explicitly. Verify one action per press across catch-up ticks and no rate-throttle integration during menu/focus holds. Maintain deterministic command replay and existing radio/keyboard/golden-flight contracts; do not re-record golden physics flights to conceal an input regression.

Draft scripts remain outside `app/` until they parse. Run focused native Windows checks, then the canonical `app/test.sh` and relevant report/tool checks after integration. Inspect logs as well as exit codes. Documentation-only changes require link/diff checks, not a full flight regression suite. Run performance comparisons on an otherwise idle host after correctness tests.

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

1. With a fresh test profile, connect before launch and after Home appears. Inspect recognized identity and verify all expected buttons and axes. Confirm 0%, 50% and 100% trigger readings and both triggers together.
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

The next bounded implementation is D6-GP-01 together with F1-GP-01 evidence: protect the existing gamepad calibration path, correct its instructions, and establish native Xbox/DualSense baselines before larger integration work.
