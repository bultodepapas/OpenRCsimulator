# Automatic controls for handheld PCs and Steam Machine

**Status: research and plan delivered, 2026-11-20; implementation and device qualification pending.** D6-HH-00 audits main `a27c44fcaec0401de852c9a2f791041e34e3974d`, using the pinned Godot 4.8-beta2. This branch changes documentation only. The [source audit and primary references](../research/handheld-controls-2026-11-20/README.md) explain the evidence and its limits.

**Research extension complete:** [round one](../research/handheld-controls-2026-11-20/round-1.md) contains ten investigations; its gaps selected the ten completed studies in [round two](../research/handheld-controls-2026-11-20/round-2.md). All twenty are integrated below. The [acceptance companion](handheld-controller-acceptance.md) defines continuity contracts, failure cases and a finite qualification campaign. These are source-based findings and proposed tests, not hardware results.

## Goal and scope

A player opens OpenRC on a supported handheld or Steam Machine, uses the available standard controller to choose a vehicle and field, flies, pauses, changes settings, enters text and exits. A known gamepad needs no mapping wizard or manual controller-enable setting. Existing user mappings, radio calibration and vehicle-specific input behavior remain authoritative.

Cover native Windows, native Linux/SteamOS and Windows through Proton as separate configurations. Priorities are Steam Deck, current Steam Machine, ROG Xbox Ally/Ally X and the ordinary Windows/Linux controller path; extend the same design to ROG Ally, Lenovo Legion Go/Go S, MSI Claw and other compatible handheld PCs. Android handhelds and Xbox/PlayStation/Nintendo console exports are outside this plan. Supporting their controllers on a PC does not create a console port.

This is a controller subtrack. It extends the [existing controller plan](controller-support.md), [Controls workspace](controls-setup-ux.md), [Linux delivery plan](linux-support-distribution.md) and [desktop delivery](../DESKTOP-DELIVERY-PLAN.md). It does not reopen aircraft physics, replace the input stack or estimate already delivered startup/profile/navigation work.

## Ownership and boundaries

| Prefix / owner | Responsibility and proposed paths |
| --- | --- |
| D6-HH-* / input | Existing `app/input/controller_service.gd`, registry, profiles, actions and report metadata; small proposed descriptor/provider modules under `app/input/` only where needed |
| F1-HH-* / controller diagnostics | Extend existing reports and retain redacted hardware evidence under `docs/research/handheld-controls-2026-11-20/` |
| F3-HH-* / input and activity owners | Ownership, provider transitions, reconnect/focus/sleep; changes at existing session boundaries, not the kernel |
| UI-12-HH-* / UI | Controller navigation, current-binding prompts, command access and focus; `app/ui/`, shared `app/app_root.gd` and maintained localization |
| UI-15-HH-* / UI and platform services | Controller text-entry service and optional platform adapters; proposed `app/ui/controller_text_entry.gd` and a narrow native bridge if required |
| F4-HH-* / device qualification with DT/PT | Physical matrix and exported-build acceptance; package changes stay with desktop/CI owners |
| D6-HH-06 / camera and input owners | Optional camera motion, extra-button conveniences and bounded rumble; keep presentation input outside aircraft laws |

Register these prefixes in the [track registry](../README.md#tracks-plans-and-step-ids). Shared flight, helicopter, quad, airship, ground, camera, export and UI paths retain their existing owners. A proposed file name is not an implemented component. Keep the fixed 240 Hz clock and float64 simulation unchanged.

## Existing foundation to preserve

The source audit confirms automatic Home selection, separate flight/UI roles, connection generations, V2 profiles, transactional Save/Cancel, Mode 1/2 gamepad presets, selected-pad menu routing, radio setup and a graphical Controls workspace. Reuse them.

Preserve the following distinctions:

| Activity / device | Existing behavior that automation must retain |
| --- | --- |
| Known standard airplane gamepad | Ready on the first verified focused live poll; no new centered dwell, stick gesture or button-release requirement before ordinary initial flight. Mode 2 uses a spring-stick rate throttle by default. |
| Unknown joystick or RC transmitter | Explicit configuration/calibration and existing evidence gates; radio low-throttle arming and verified-radio menu rules remain. |
| Ordinary airplane Pause/focus hold | Preserve staged rate throttle and explicit Continue. A stationary standard pad can regain verified focused-poll readiness without moving sticks; do not add a new focus-return gesture. |
| Actual airplane controller disconnect | Reset RcInput to idle and clear staged start/rate state. Recognition of a reconnected device never resumes the simulation or restores a held-throttle assumption. |
| Helicopter | Collective, arm, hold and curve semantics remain with the helicopter session; its current rejection of trigger-absolute profiles remains. |
| FPV quad | Existing low-throttle OFF→ON arming, modes and single shaping/rate integration. Ordinary Pause and focus invalidation have different arm-state effects; preserve those and dedicated AUX/legacy behavior. |
| Ground vehicle | Existing activity-local controller selection, LX steering, RT acceleration, LT brake and reverse; its neutral-trigger/steering readiness gate is intentional. Do not replace it with the airplane readiness rule. |
| Airship | Its own drive/hold and paused rate-throttle policy stays with its adapter. |

The [controller contract](controller-support.md#explicit-gaps-and-acceptance-rules) and current source resolve detailed behavior. An input-provider change must preserve the activity's sampled commands; replay of post-conditioning commands alone cannot test mapping, calibration or pilot adaptation.

## Design decisions

### 1. Extend the current device model

Normalize observations once at the service→registry boundary. Retain mapping kind, backend, OS, connection generation and bounded optional capabilities. Use three states for optional features: supported, unsupported and unknown. A manufacturer's feature list does not establish that a provider exposes a feature.

Separate persistent profile association from transient transport/provider data. Preserve unique-match and ambiguity handling; GUIDs and generic names are not universally unique. A Steam handle, Godot device ID or XInput slot must never become a saved physical-device identity. A provider switch may change the observable descriptor without proving that a saved raw-radio calibration applies.

Also distinguish unit-association confidence from mapping/calibration compatibility. A serial match does not establish the same axis representation; one currently connected serial-less radio does not prove it is the previously calibrated unit. For uncertain raw calibrated radio or joystick profiles, first use a **session-only review**: suggest the saved profile, verify current-connection direction/raw travel, low-throttle polarity and relevant AUX/actions, and offer “Review and use for this connection” or “Calibrate.” Reuse Controls drafts and leases; review/cancel leaves V2 bytes unchanged. Clamped previews and polled zeros are not fresh evidence. Apply the gate before flight, verified-radio menu activation and reassociation, including direct activity restoration paths. [R1-06](../research/handheld-controls-2026-11-20/round-1.md#r1-06--is-a-matching-saved-profile-the-calibrated-physical-unit), [R2-15](../research/handheld-controls-2026-11-20/round-2.md#r2-15--what-is-the-smallest-safe-saved-calibration-change)

Invalidate review on relevant profile/representation or connection changes, but distinguish match-context changes from loss of an already owned source. Preserve the existing uninterrupted generic-source duplicate-arrival protection. JETI identity ambiguity explicitly clears flight/UI selections and must retain its invalidation/hold behavior; changing that requires separate JETI-owner review and verification. Ordinary mapped gamepads keep their current startup without centered dwell. Defer durable compatibility metadata and Cloud from this slice. If later justified, prefer a versioned transactional store; a sidecar needs committed-data binding and old builds ignore it. Test downgrade because the current loader can revive a readable V2 `.rollback` even when a future primary schema is unsupported. Keep machine-local calibration/identity/UI choice out of broad Cloud selection.

**First concrete repair:** the pinned engine's `steam_input_index` is actually an opaque 64-bit Steam handle encoded as a decimal string. The registry currently drops it, and the standalone report treats it as a value bounded by 65535. Preserve it losslessly in a version-aware decoder and correct/report the diagnostic domain. Keep XInput indices separate. Treat zero as unavailable; test values above 65535 and JavaScript's exact integer range, malformed values, absent metadata and reconnect. The pinned engine serializes through signed `itos(int64_t)`, whereas SDL returns an unsigned handle: qualify signed/unsigned round-trips across 2^63 at both engine and native-binding boundaries, retaining the raw representation until decoded. This boundary risk is not an observed hardware failure. [Audit: metadata finding](../research/handheld-controls-2026-11-20/README.md#1-steam-metadata-is-dropped-and-a-diagnostic-field-has-the-wrong-domain)

Keep automatic selection at the existing startup/Home boundary. Saved explicit choices and eligible profiles win. A built-in pad, an external pad or harmless drift must not steal a running flight. With genuinely ambiguous devices, use a short controller-operated selection screen; do not silently attach calibration to the wrong device. Reuse the existing manual override and explain which controller currently owns menus and flight.

### 2. Use a progressive Steam integration

| Mode | Command owner | Added behavior / fallback |
| --- | --- | --- |
| Portable baseline | Existing Godot/SDL device path | Works in standalone exports and with Steam gamepad emulation; no Steam API dependency. |
| Steam-assisted baseline | Still Godot/SDL for commands | Optional Steam association, device-family glyphs within emulation limits, keyboard and lifecycle callbacks. An unavailable service leaves normal input usable. |
| Native Steam actions, later | One explicitly selected Steam action provider | Maps actions into existing activity adapters after configuration and association are verified. Never consume an emulated duplicate for the same action. |

Evaluate a maintained GodotSteam GDExtension against the exact engine/template pin, following its upstream Codeberg pointer. Record source commit, Steamworks SDK, binary hashes, architectures, API coverage and redistribution requirements. Prefer a narrow bridge over changing the engine or starting a second SDL/GameInput subsystem. Non-Steam exports must work without it; an export offering optional Steam services must preserve portable startup through its supported missing-library/API-failure cases.

**Resolve initialization order before selecting the bridge.** The pinned SDL header requires Steam initialization before SDL initialization. Godot's SERVERS extension phase precedes joypad initialization, while SCENE extensions and script autoloads follow it. Investigate that early native seam; a late `_ready()` call is not a qualified solution. Avoid unconditional script type references and mandatory DLL linkage in the portable startup path. Distinguish extension load failure, dependency failure, API failure, configuration loading and ready state; use one pump/shutdown owner and no automatic Steam relaunch. Current exports exclude `addons/*`, so extension placement and dependency staging need explicit verification. [R1-01/02](../research/handheld-controls-2026-11-20/round-1.md#r1-01--can-an-optional-steam-integration-really-be-absent)

Run an early-bootstrap feasibility spike before adopting a binding: a minimal CORE/SERVERS initializer may initialize Steam, but must not touch Input/SceneTree or services unavailable at that phase. Register scene-facing behavior later and trace the order in real exports. Godot can continue after a returned extension-load error; it cannot contain arbitrary ABI/native initialization crashes. The actual upstream binding and binary pair remain unqualified. [R2-11](../research/handheld-controls-2026-11-20/round-2.md#r2-11--can-optional-steam-startup-precede-sdl-without-an-engine-replacement)

Readiness requires successful Steam API initialization, a connected handle, valid required action handles and an applicable loaded configuration; the return value of `SteamInput.Init()` is insufficient. A Steam client process or a hardware-detection flag is not proof of a usable provider. SDK/binding availability gates newer APIs, including hardware/Proton detection. [Primary sources V3/V4/B1](../research/handheld-controls-2026-11-20/README.md#primary-source-catalog)

Provider arbitration must use actual association evidence. For the current pin, decode the observed Steam handle; use XInput-slot translation only when a real XInput index is known. A pure native Steam layout may have no SDL counterpart. Represent it as a separate logical endpoint with an explicit backend and generation, not an invented physical joypad ID. If association is unavailable or conflicting, keep the baseline path; never disable every native joystick because Steam is running.

Define ownership per logical device and input context, with one command source per action. On actual provider/configuration continuity loss, discard stale edges and requalify samples through the activity's reason-specific hold; retain staged state only where that contract calls for it. If native actions fail, fall back only to a verified live baseline endpoint. A native-only endpoint with essential bindings missing, no overlay and no SDL peer may have no controller-operated escape: remain held, explain available keyboard/other-controller/external-client recovery and mark controller-only qualification blocked.

The pinned engine caches connection metadata without forwarding the relevant live remap/Steam-handle updates. A cached handle still present in Steam's live list can refer to the wrong device after a two-controller slot swap. Invalidate affected links and require fresh unambiguous evidence; waiting three seconds or polling the cached dictionary does not establish it. The portable slice can leave association unknown. If needed, separately qualify a narrow upstream/engine hook using the existing SDL owner and instance map, without fake disconnects or a second stack. Public `known` and a constant SDL backend label do not identify a stable representation. [R2-12](../research/handheld-controls-2026-11-20/round-2.md#r2-12--what-would-make-steam-association-genuinely-current)

Coarse configuration flags cannot attribute synthetic keyboard/mouse input. Arbitrary mixed layouts remain unqualified where provenance is missing; offer only demonstrated supported routes and retain genuine keyboard/radio input. Do not use global disabling or timing heuristics to claim deduplication. First native-provider selection is session-only, with V2 profiles unchanged; Menu and Flight configurations/readiness pass separately before promotion. [R2-13](../research/handheld-controls-2026-11-20/round-2.md#r2-13--how-do-native-actions-enter-fail-and-roll-back)

Keep native Steam action mode opt-in until its migration and hardware gate pass. An existing custom OpenRC gamepad profile stays on the baseline unless the user deliberately selects the new provider. Do not apply a Steam remap and then silently remap the resulting semantic action a second time. Keep OpenRC rates/expo/throttle integration at their existing owner; official Steam layouts should not add a second response curve.

### 3. Ship a complete standard layout first

Retain the current `ControllerActions.effective_bindings()` defaults and saved overrides. Use the standard controller button budget for normal operation; extra hardware only adds convenience. The illustrative airplane defaults below describe current code, not a replacement map:

| Control | Existing default behavior |
| --- | --- |
| Right stick | Roll/pitch in Mode 2 |
| Left stick | Yaw and rate throttle in Mode 2 |
| D-pad | Trim in flight; navigation in menus |
| Menu/Start | Pause; existing explicit Continue flow governs resumption |
| A / B | Accept/back in menus; flaps/gear when the airplane exposes them and no override/conflict applies |
| Y / X | Camera cycle / overlay preset |
| LB / RB | Throttle cut hold / smoke when supported |
| View/Back / L3 / R3 | Restart / rates / reset view, subject to existing context and binding rules |

Do not auto-switch to trigger throttle based on an Xbox-style name or idle zeros. Keep it an explicit eligible preset until independent analog-trigger behavior has physical evidence. Do not use Steam/Xbox/Quick Access system buttons for essential in-game commands.

Inventory missing player-facing commands, then provide a controller-operated command menu or equivalent existing screen for low-frequency functions. Candidates include aircraft-specific folding wings/canopy/tailhook, wheel brake, glow start/mixture and flight logging. Check existing alternate routes before adding anything. Add genuine semantic commands to the existing action/router contract; do not implement gameplay by synthesizing F-keys. Preserve per-vehicle capability checks and context conflicts. Debug-only facilities need not occupy the player layout.

The inspected mechanism handlers reject paused operation, so adding a Pause-menu button alone does not close the gap. Choose a usable interaction under the current guard, or separately review a single staged intent dispatched only after explicit Continue and revalidated guards. Preserve continuous brake release, glow validation and recording eligibility; do not add an accidental latch, implicit resume or general action queue. Update in-flight mechanism prompts as well as the command entry point. Existing Workshop view/orbit/zoom buttons need reachability evidence, not duplicate widgets. [R2-17](../research/handheld-controls-2026-11-20/round-2.md#r2-17--which-missing-commands-need-more-than-another-menu-button)

Official Steam configurations should initially mirror this stable gamepad layout. Store/export localized configurations with the build; protect Generic/DirectInput radio handling. For the later native action route, start with Menu and Flight contexts and add a vehicle-specific set only when semantics require it. The action manifest and layout revision must travel with the matching executable. [Sources V1/V7](../research/handheld-controls-2026-11-20/README.md#primary-source-catalog)

Stage Steam-readable manifest/VDF files outside the embedded PCK and verify release discovery without a development override. Keep build/layout hashes and SDK/action revisions in an OpenRC release receipt, separate from Valve's schema. Review major/minor layout migration and rollback independently of OpenRC profiles; reverting binaries does not establish restoration of custom Steam layouts. Keep legacy gamepad/mouse migration flags disabled while those paths remain supported. Separate loading, wrong context and explicit unbinding, and prove recovery with the controls actually available. [R1-03](../research/handheld-controls-2026-11-20/round-1.md#r1-03--will-packaged-layouts-preserve-custom-configurations), [R2-13](../research/handheld-controls-2026-11-20/round-2.md#r2-13--how-do-native-actions-enter-fail-and-roll-back)

### 4. Complete controller navigation, prompts and text entry

Audit the whole journey, including startup skip/intro, Home, aircraft/field lists, Controls, Settings, Help, dialogs, Workshop, Creator, pause/reset, import/export and Quit. Every visible operation needs reachable focus, a visible selection, working Accept/Back, scroll/slider behavior and recovery after a popup or overlay. Reuse the Controls workspace and surface stack.

Extend `ControllerPrompts` rather than introducing another glyph framework. Resolve prompts from the currently displayed action and its binding/provider; retain the manual family override for the baseline and a readable fallback when identity is unknown. With emulated gamepads, show OpenRC's effective logical binding. Steam's `GetActionOriginFromXboxOrigin` can translate a standard button into device-family art, but does not account for user remapping. It cannot establish an arbitrary physical remap or chord. Use truthful logical-button/action labels and an accessible configuration route when the physical origin is unknown.

The later native-action provider can query `GetDigitalActionOrigins`/`GetAnalogActionOrigins` with actual action-set/action handles; show the returned origins without inventing unsupported chord or activator detail. Refresh OpenRC bindings and native Steam origins when their configuration/context changes. Test emulation fallback and native-action remapping separately. Keep camera mouse motion, gyro noise and small stick drift from causing prompt flicker. Mouse and keyboard must remain usable alongside a pad. [Sources V3/V5](../research/handheld-controls-2026-11-20/README.md#primary-source-catalog)

A shared text-entry service should use an available Steam keyboard, otherwise an eligible Windows gamepad keyboard, otherwise an in-game controller keyboard. The portable fallback must ship before declaring a complete standalone handheld journey. It must support the game's maintained input languages, selection/editing, spaces, deletion, acceptance and cancellation; numeric fields need suitable controls. An ASCII-only fallback cannot justify complete text-entry support for every locale.

Use an editor adapter with explicit draft/validation/accept/cancel behavior. Setting `LineEdit.text` alone does not emit `text_changed`; generic synthetic Enter is not a safe commit path. Qualify translated UI and text input separately, including the maintained Chinese/Japanese locales and composition requirements. Reuse maintained input services before proposing a new IME, and keep unsupported provider/locale combinations open. Existing Workshop camera buttons already provide alternatives to mouse/keyboard handling; audit their reachability before adding duplicate controls. A held brake needs proper hold/release semantics, not an arbitrary command-menu latch. [R1-07/08](../research/handheld-controls-2026-11-20/round-1.md#r1-07--are-apparent-keyboard-gaps-actually-missing-controller-routes)

Workshop numeric editors commit on focus exit, so OSK focus transfer must not prematurely commit. Preserve each editor's selection, validator and draft, apply a modal result through exactly one owner-approved path, and treat keyboard dismissal separately from acceptance. Cancel restores that field's draft, not unrelated document edits. Track provider/locale coverage explicitly; English/Spanish fallback tests do not qualify all maintained languages. [R2-18](../research/handheld-controls-2026-11-20/round-2.md#r2-18--can-desktop-keyboards-preserve-real-editor-transactions)

Bind each keyboard session to the current editor/screen generation and suspend gameplay actions while editing. For modal result APIs such as Steam `ShowGamepadTextInput`, accept submitted text only for the still-valid editor and ignore late results. Steam's floating keyboard instead injects OS key events; Windows `CoreInputView.TryShow` also opens a system keyboard rather than returning a submitted-text payload. Those adapters need exclusive editor focus, explicit hide/dismiss handling and input isolation during screen transitions so lingering key events cannot enter another editor or gameplay. Restore focus on cancellation. Test Unicode, long names, hidden/disabled fields, repeated requests and unavailable/declined platform keyboards. `DisplayServer.virtual_keyboard_show()` is not a sufficient desktop implementation for this engine pin. [Sources G4/M1/M2/M4/V4](../research/handheld-controls-2026-11-20/README.md#primary-source-catalog)

Qualify the Windows bridge's OS/SDK, WinRT thread/COM context and foreground Godot window without adopting a new GameInput stack. A successful keyboard-display request is not proof that editing works. Convert floating-keyboard exclusion rectangles from viewport/control units to window-relative pixels, and refresh/hide on DPI, resize and docking changes. Provider failure must preserve the editor draft for fallback. The Microsoft sample is reference material, not a tested Godot integration. [R2-18](../research/handheld-controls-2026-11-20/round-2.md#r2-18--can-desktop-keyboards-preserve-real-editor-transactions)

For files, test the actual exported native picker/portal. If a shipping flow cannot be completed by controller, add an accessible in-game path through the existing import/export service or record that row as blocked. Do not claim access to all content while silently excluding file/text dialogs. Keep permission handling with the Linux/desktop delivery owner.

An in-game browser may access only already-authorized roots; it cannot replace a required portal grant. Linux recovery must distinguish observed absence from proven classification, host permission or sandbox failure. Do not infer a cause from an empty Godot list or automatically change device privileges/OEM drivers. [R1-04/08](../research/handheld-controls-2026-11-20/round-1.md#r1-04--what-does-an-empty-linux-controller-list-mean)

The pinned SDL can silently omit a candidate whose initial read-only open fails, and may deliver input through a read-only fallback without rumble. Actual template flags, namespace and discovery path matter. Offer reversible selection/reconnect/mode/launcher checks; detailed support reports only observed candidate denial or visibility differences, leaving cause unknown otherwise. Keep package/host recovery with DT-LNX. [R2-14](../research/handheld-controls-2026-11-20/round-2.md#r2-14--what-linux-recovery-can-the-application-substantiate)

### 5. Preserve continuity across overlays, sleep and docking

Extend existing focus/disconnect recovery to the selected Steam integration and platform lifecycle events. Retain the long-frame-gap fallback; do not rely on it alone for all sleep or overlay cases. A connected controller can still lose valid input continuity.

The current greater-than-five-second check runs in idle processing for attached sessions, after physics, and the pinned Linux monotonic clock excludes system-suspend duration. It is a detectable-stall fallback, not universal sleep protection. Gate commands before the first affected simulation step after a recognized boundary, and qualify standalone/native/Proton signals independently for every activity. No motion-event timeout may classify an otherwise healthy stationary controller as stale. [R1-09](../research/handheld-controls-2026-11-20/round-1.md#r1-09--does-the-long-gap-watchdog-cover-real-sleep)

On recognition of a relevant boundary, close gameplay consumption before subsequent event-driven commands **and** physics ticks; a tick already executing may finish. Opening Pause may be deferred, but gating cannot wait for idle `_process`. Stop feedback, release delivered menu/capture holds, discard stale intents and apply the owning activity's reason-specific hold. No queued arm/restart/Continue survives. Raw readiness observations may continue behind the gate. Reassociation and prompt refresh do not resume simulation. Preserve ordinary airplane staged throttle versus actual disconnect reset, quad Pause versus focus invalidation, radio low-throttle evidence, helicopter collective, airship/ground policy and independent crash holds. [R2-19](../research/handheld-controls-2026-11-20/round-2.md#r2-19--where-must-continuity-loss-stop-command-consumption)

Evaluate Windows power notifications, available Linux logind signals and suspend-aware clocks alongside optional Steam callbacks. Qualify each actual launch route; a late callback cannot protect an earlier step retroactively. Preserve ordinary same-source standard-gamepad focus recovery through the existing verified focused poll and explicit Continue, including stationary sticks. That application readiness contract is not proof of physical sample generation after sleep. For actual suspend/provider discontinuity, name a demonstrated drain/repump/evidence mechanism or retain a pending freshness qualification; Godot receipt times and cached levels alone cannot establish it. Do not impose a new focus-return gesture or timeout without a separately reviewed owner decision. Use the [continuity contract](handheld-controller-acceptance.md#continuity-contract) for ordered event/tick tests.

The project currently keeps Godot's unfocused-joypad guard disabled. Evaluate enabling it in a focused change with the existing radio/menu/capture tests and real overlay cases. If an affected route requires raw observations, gate command consumption instead and document the reason. Do not flip the setting as an untested shortcut or claim that a focus flag alone covers Steam/Game Bar overlays.

### 6. Treat handheld extras as optional

Use actual exposed capabilities for rumble, controller gyro, touchpads and additional buttons. The pinned engine already supplies relevant queries and experimental joypad sensors. Start gyro with opt-in camera control; never map chassis motion to aircraft control surfaces automatically. Avoid consuming both raw gyro and its Steam/OEM mouse emulation for the same camera rotation.

Rear buttons may be duplicates of ordinary buttons, not independent inputs. Keep every required function available through the standard layout or command menu. Rumble remains configurable and finite, stops on focus/loss/pause/exit, and has no simulation side effects. Record provider/model/transport limits instead of promising every advertised feature.

## Execution order and completion evidence

Every implementation row below is **planned**. D6-HH-00 is complete only as a research deliverable. Each row should produce a small reviewable change and retain the relevant existing regressions.

| Step | Work | Required proof / status |
| --- | --- | --- |
| D6-HH-00 | Source audit, twenty additional investigations in two completed rounds, architecture and acceptance | Research delivered; implementation and hardware evidence remain pending |
| F1-HH-01 | Inventory available target devices and capture current behavior before changes | Exact model/OS/provider/mode; current report and complete-journey checklist; missing equipment stays pending |
| D6-HH-01 | Versioned descriptor/Steam-handle decoding, report domain and explicit association freshness | Zero/large/signed/type/unknown cases; both-live slot swap; no cached-handle requalification; qualify any narrow upstream refresh hook separately |
| D6-HH-02 | Extend the current selection model only where a demonstrated handheld/provider case needs it | Clean and saved startup, two identical pads, built-in + external, RC + pad, no mid-flight takeover |
| D6-HH-07 | Session-only compatibility review for uncertain raw radio/joystick profiles, including menu/direct routes | Fresh range/direction/throttle/AUX review; generic duplicate preservation versus JETI ambiguity hold; V2 review/cancel byte equality; no migration/Cloud dependency |
| F1-HH-02 | Versioned shareable diagnostic format with whole-capture bounds | Allowlist plus stdout/stderr checks; reconnect/byte caps; disclosed retained data; existing local CLI compatibility |
| UI-12-HH-01 | Close observed navigation and semantic-command gaps | Full journey including Creator; usable paused-rejected commands; hold/release, capability, conflict and remap evidence |
| UI-15-HH-01 | Portable transactional text entry and file coverage | Standalone journey; editor commit/cancel/focus-exit tests; provider/locale matrix and authorized-root limits |
| F3-HH-01 | Event-and-tick continuity gate, reason-specific recovery and platform signals | Ordered boundary traces, all activity policies, actual sleep versus freeze; no stale intent or automatic Continue |
| D6-HH-03 | Early optional-startup spike, then qualified Steam-assisted bridge | Exact binary/SDK/template identity; Steam-before-SDL export trace; supported load/API failures; one lifecycle owner |
| UI-12-HH-02 | Steam device-family glyphs and stable input presentation | OpenRC remap while open; truthful logical-binding fallback for unknown Steam emulation remaps/chords; reconnect and mixed camera input |
| UI-15-HH-02 | Steam OSK and optional Windows gamepad-keyboard adapter | Actual editing after show request; COM/window eligibility; late results, focus-exit, dismissal, DPI/dock geometry and draft-preserving fallback |
| D6-HH-04 | Native Steam action provider and current action origins behind an opt-in gate | Pure-action, emulation and mixed configurations; live native remaps/origins; one owner per action; migration and failure recovery |
| D6-HH-05 | Official Steam layouts/action manifest and distribution configuration | External packaged files, release receipt, clean-client discovery, custom-layout migration/rollback; RC coexistence |
| D6-HH-06 | Optional gyro/trackpad camera, rear-button conveniences and rumble | Capability absence is harmless; no double camera motion; feedback stops at lifecycle boundaries |
| F4-HH-01 | Physical primary matrix on source and exports | All required cases below with actual device evidence; no inference between OS/provider rows |
| F4-HH-02 | Additional handhelds, alternate OSes and release claims | Publish only completed configurations; retain device-specific limitations and pending rows |

The portable slice is D6-HH-01/02/07, F1-HH-02, UI-12-HH-01, UI-15-HH-01 and F3-HH-01. It can proceed without Steam partner access. The D6-HH-03 startup spike and physical baseline inventory may run in parallel; adopting the Steam bridge depends on that spike, not the reverse. Native actions depend on proven association/ownership, usable contexts and release migration; extras follow correctness. Use the [dependency and acceptance gates](handheld-controller-acceptance.md#implementation-dependencies-and-gates). No calendar estimate precedes equipment availability and bridge qualification.

## Physical qualification matrix

All rows start **not tested**. A family entry must be split into exact model/OS/firmware rows when equipment is available. N = native Linux; W = native Windows; P = Windows build through Proton. Steam Input on/off cases apply where the selected hardware and route actually expose controls; lack of a direct non-Steam interface is a recorded limit, not a fabricated pass.

| Priority / target | Runtime and launch paths | Distinct controls / cases |
| --- | --- | --- |
| P0 Steam Deck LCD and OLED | N and P in Gaming Mode; desktop/standalone discovery recorded separately | Built-in controls, dock + USB/Bluetooth pad, trackpads, user layout, sleep |
| P0 current Steam Machine | N and P through Steam; controller-operated living-room UI | Steam Controller (2026), Xbox-compatible pad, controller order, TV/dock and sleep |
| P0 ROG Xbox Ally / Ally X | W direct and Steam, OEM Gamepad and supported Auto modes | Built-in + external, Xbox/Game Bar, Desktop-mode recovery, suspend |
| P1 ROG Ally / Ally X | W direct and Steam | Exact older model/firmware; OEM modes and controller disabled/enabled |
| P1 Legion Go / Go S Windows | W direct and Steam | Attached/detached/one detached and FPS mode where applicable; no assumed raw-controller fusion |
| P1 Legion Go S SteamOS | N and P through Steam | Third-party SteamOS controls, external pad, mode and sleep |
| P1 representative MSI Claw | W direct and Steam | GamePad/Desktop, macros off/on, system overlay and resume |
| P0 regression desktops | W and N, direct and Steam | Xbox, DualSense, generic pad; keyboard/mouse; USB/Bluetooth where available |
| P0 RC coexistence | W and N; Steam on/off | Calibrated EdgeTX/JETI + menu pad, unknown radio, duplicate identities; no calibration or AUX regression |
| Conditional alternative OSes | Windows on Deck/Machine; community Linux on Ally/Claw/other PCs | Exact drivers/distribution/provider; no family-wide support claim |
| Extension other handheld PCs | AYANEO, GPD, ONEXPLAYER or another available device | Standard exposed controller first; separate OEM/extra-feature findings |

Model/OS context and limitations are supported by [the manufacturer and platform research](../research/handheld-controls-2026-11-20/README.md#platform-findings); none of these rows implies an existing OpenRC support promise.

### Test procedure for each promised configuration

1. Record build/commit, engine and native backend actually loaded, OS/kernel, Steam/Proton where applicable, OEM software/firmware, controller/transport, provider, profile revision and official/user layout revision. Redact identifiers in shared reports.
2. Use an isolated clean profile, then an existing saved/custom profile. Reach a playable aircraft from Home with no controller settings, manual axis binding or community-layout download. Preserve the parent plan's separate usability targets: under 60 seconds to the Controls test view for a mapped Xbox/DualSense and first-time calibration, if requested, within three minutes. Record time to flight and loading time separately; this plan does not assign a new numeric flight-start target. An existing saved keyboard preference must still be honored.
3. Complete Home → vehicle/field → flight → Pause → Settings/Controls → explicit Continue → restart → Home → Quit. Also exercise shipping Help, text-entry, Workshop, Creator and file flows before claiming complete controller access. Capture focus at the device's real display scale, including EN/ES and the relevant locale.
4. Exercise each standard axis and button, diagonal stick movement, endpoint/polarity, 30 seconds of idle drift and simultaneous inputs. For an offered trigger preset, prove both triggers independently and together; no automatic conversion from uncertain readings.
5. Run the parent fault protocol's ten reconnect cycles per primary route; add ten sleep/resume cycles and overlay/focus repetitions for this subtrack. Include raised throttle/held triggers, a held Accept/Back, changed connection ID, configuration change and a second controller arriving. No stuck command, duplicate action or automatic resume is acceptable.
6. Test remaps, explicit unbound actions and profile restart persistence. Changing controller order, entering Desktop/FPS mode or losing a service must yield a truthful recovery path. Reconnect must not overwrite a saved profile.
7. Test absent Steam/overlay, offline launch, a pure Steam action layout, an emulation layout, and a user-modified mixed layout where the provider is supported. Verify RC devices remain distinct and menu devices do not inject flight commands.
8. Verify the exported package on that OS, not only editor/headless runs. After correctness, use at least 30 valid filmed transitions per qualified primary transport within each claimed timing-changing OS/provider route, retaining median/nearest-rank p95, exclusions and uncertainty. The existing F6a marker covers its fixed-wing RcInput seam; a native Steam-only endpoint needs an appropriate named flight-consumed observation point or another qualified method, otherwise its timing row stays pending. Label raw-marker, conditioned/aircraft response and software timing separately. Use the [finite campaign and timing protocol](handheld-controller-acceptance.md#finite-physical-campaign); a baseline result on the same transport does not qualify another provider, and risk-based combinations do not waive journey/cycle counts.

Follow the repository's 1080p-first desktop policy, then higher-resolution/docked checks. Also qualify each handheld at its actual native panel resolution, including Deck 1280×800; a 1080p monitor result does not establish handheld readability. 1280×720 remains a fallback target. Performance and platform badges stay with DT/PT and the platform's own review; input completion does not close them.

Record actual render/physics cadence and activity-entry history. The current 240 Hz/12-step cap permits at most 180 ticks per wall second at sustained 15 rendered fps; that arithmetic is not a measured performance defect. Test short presses across sampling phases and accumulation-setting restoration. Preserve one shaping/rate owner and the existing kernel; physical report rate, callback spacing and motion-to-display response are different measurements. [R2-20](../research/handheld-controls-2026-11-20/round-2.md#r2-20--what-finite-evidence-is-enough-to-qualify-a-configuration)

## Verification, rollout and open dependencies

Extend the closest existing tests: `test_controller_auto_defaults.gd`, `test_controller_registry.gd`, `test_input_report_buttons.gd`, profile/store/persistence tests, `test_controller_pause_recovery.gd`, `test_controller_routing_audit.gd`, `test_ui_input.gd`, `test_controller_prompts.gd`, radio-menu tests, and the affected helicopter/quad/ground/airship suites. Tests using unverified pure readers may intentionally require readiness evidence; do not rewrite them to mimic the live mapped-pad path.

Use the [existing verification workflow](../tools/shared.md#verification-scope) for implementation: parse changed scripts, exercise affected activity boundaries, then required CI and physical/exported checks. Input changes require input/live-flight evidence; recorded post-conditioning replay alone cannot qualify the new mapping. Do not re-record golden flights for this UI/input work.

Ship in stages: portable baseline, Steam-assisted baseline, then opt-in native actions/extras. Preserve V2 profiles in the first slice and reset only introduced optional state on application rollback. Test Steam custom-layout rollback independently. A supported controller-only row needs a reachable fallback using its actual controls; missing essential native bindings with no alternate endpoint is explicitly blocked, not repaired by a hypothetical menu or command-line flag. Optional components must be absent cleanly from exports that do not support them.

**Diagnostic contract:** retain the existing CLI as a local developer format and add a separate versioned shareable allowlist with total record/byte/duration limits, omission counts and previewed fields. Current Controls redaction still retains calibration/action data; current CLI paths, custom names and bundled logs can disclose identifiers. Verify JSON, stdout and stderr, use no-overwrite shareable output and keep exact qualification identities separately controlled. No automatic upload is proposed. [R2-16](../research/handheld-controls-2026-11-20/round-2.md#r2-16--what-may-a-shareable-diagnostic-report-honestly-claim)

**Baseline drift review, 2026-11-20:** main advanced to `fea82ac6b213796bb5a0a5f2319d8d13d8a812d6` during research, fourteen commits beyond the audited runtime. The compared file list and relevant activity/UI diffs did not change the identified input core or engine pin; they included independent collision/crash and Creator work. This branch does not merge that work. Before implementation, rebase/reconcile with then-current main and recheck shared activity boundaries, preserving independent holds. The research links continue to describe the explicit audited baseline.

Open dependencies are the actual handheld inventory, an authorized Steam App ID/partner configuration for official layouts, a qualified binding/SDK pair, target-OS export checks and controller-accessible file/text coverage. No user permission or hardware purchase is needed to complete this research branch. Do not label the game Deck Verified, Steam Machine Verified or Xbox Handheld Optimized from this plan or synthetic tests.

**Completion rule:** automatic control support is delivered for a named configuration only when its default/saved-profile journeys, lifecycle cases, optional-service fallbacks and exported-build evidence pass. Track incomplete hardware rows explicitly rather than treating a shared SDL mapping as universal certification.
