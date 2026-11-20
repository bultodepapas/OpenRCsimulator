# Round 1: ten additional handheld-control investigations

**D6-HH-00/R1 — completed research, 2026-11-20.** These ten investigations extend the [initial audit](README.md), at research commit `49b55c036dfe9a92d6f5b7b11f831e0cd1b7eea4`, with unchanged runtime baseline `a27c44fcaec0401de852c9a2f791041e34e3974d`. Engine evidence uses Godot `cafc17a192acf67903910a68aeb3c076c0907a4b`, including its vendored SDL 3.4.12. The lead inspected material source findings independently of the research helpers. No device, Steam partner configuration, native bridge binary or exported package was tested.

The [implementation plan](../../plans/handheld-controller-automation.md) owns proposed behavior. Findings below distinguish inspected source, documented API behavior and conditional failure scenarios. A proposed test is not a test result. [Round two](round-2.md) subsequently completed the selected ten follow-ups and refines optional-native failure handling, session-only compatibility review, unavailable recovery and reason-specific continuity.

## R1-01 — Can an optional Steam integration really be absent?

**Evidence.** Linux/Windows [export presets](../../../app/export_presets.cfg) embed the PCK and exclude `addons/*`. The [project](../../../app/project.godot) has no Steam startup owner. A proposed extension installed under a conventional addon directory therefore needs an explicit packaging decision. Godot distinguishes missing/dependency-failed extensions from successful loading [S1]. Steam initialization can fail independently, and its relaunch helper can start a different installed executable [S2].

**Gap.** Handling only `SteamAPI_Init` failure is insufficient: a missing linked DLL/SO or an unconditional GDScript type reference can fail before that check. Offline client, absent client, wrong App ID, unavailable extension and configuration loading are different conditions.

**Decision.** Add a load-stage contract to D6-HH-03: optional bootstrap; no unconditional Steam-dependent script type; one initialization, callback-pump and shutdown owner; idempotent partial teardown; explicit package filters and dependencies. The portable launch path must not automatically relaunch through Steam. Keep a deliberate development App ID file out of release depots. Qualify the actual binding and compile options before choosing automatic versus explicit Steam input pumping.

**Acceptance / next question.** Remove the extension and its dependency independently; test incompatible binary, no client, offline client, wrong working directory and successful Steam launch. In each supported fallback, Home and SDL controls remain usable. Round two must resolve startup order before selecting a binding.

## R1-02 — Does a handle establish live source ownership?

**Evidence.** SDL returns a Steam handle for an opened gamepad, with zero indicating unavailable association [S3]. Steam can enumerate native-action controllers without an emulated gamepad. Configuration and slot-change callbacks expose useful coarse information, but do not attribute every synthetic keyboard/mouse event to a controller [S4]. OpenRC [observations](../../../app/input/controller_service.gd) currently begin with Godot joypads.

The pinned [SDL header](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/thirdparty/sdl/include/SDL3/SDL_gamepad.h) explicitly calls for Steam initialization before SDL initialization. The pinned [main startup](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/main/main.cpp) initializes SERVERS extensions before joypads and SCENE extensions afterward. A scene/autoload initializer is therefore late relative to that documented ordering; a compatible early extension seam remains a candidate, not an adopted solution.

**Gap.** A valid handle is neither persistent identity nor proof that two arbitrary streams are duplicates. Pure native endpoints need no invented Godot ID. Keyboard-emulating hybrid layouts may lack the provenance needed for action-level duplicate suppression. The pinned [SDL event driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/sdl/joypad_sdl.cpp) publishes association at connection and contains no remap/Steam-handle-update event case.

**Decision.** Treat association as generation-scoped evidence. Invalidate on relevant configuration, slot and lifecycle changes; never join by order, name or VID/PID alone. Do not promise arbitrary mixed-layout deduplication or suppress real keyboard input with timing heuristics. Investigate event freshness and the early initialization seam in round two.

**Acceptance.** Native-only, emulated and hybrid layouts; two identical pads plus radio; slot reordering without unplugging; delayed/unknown/conflicting association; real keyboard alongside synthetic input; repeat native Linux, Windows and Proton separately.

## R1-03 — Will packaged layouts preserve custom configurations?

**Evidence.** Steam's manifest references external on-disk configuration paths and requires partner-side selection [S5]. OpenRC's embedded PCK alone cannot establish client-visible VDF discovery. Binding revision rules can replace configurations or remove layers; a loading configuration is not the same as an unbound action [S4].

**Gap.** Bundling a VDF as `res://` does not demonstrate Steam can read it. A development manifest override can mask broken release discovery. Preserving OpenRC profiles does not guarantee preservation of Steam's separate custom layouts.

**Decision.** Stage manifest/VDF files outside the PCK, hash them with the release, and verify discovery in a clean client session without development override. Keep migration flags affecting legacy gamepad/mouse layouts off while that baseline remains supported. Review native-layout major revisions explicitly and test rollback. Use globally unique semantic action IDs and per-endpoint context ownership. Distinguish loading, wrong context, unsupported action and deliberately unbound action; an overlay binding panel cannot be the only recovery route.

**Acceptance / next question.** Old custom native, gamepad-only and mouse/keyboard layouts across revisions; missing/corrupt manifest; absent overlay; changed context while holding Accept; multiple origin alternatives and unknown glyph enum values. Round two must make promotion, rollback and essential-action recovery concrete.

## R1-04 — What does an empty Linux controller list mean?

**Evidence.** OpenRC sees only what Godot enumerates. SDL documents separate device-node access and udev joystick-classification failures [S6]. Flatpak exposes device classes according to package permissions; `input` grants `/dev/input`, not every HID/raw USB path, and is not specific to one selected controller [S7].

**Gap.** Absence in Godot cannot distinguish unplugged hardware, host permission, classification, sandbox visibility or provider representation. A USB portal is not automatically an evdev/Bluetooth repair. A Flatpak package cannot silently repair host rules.

**Decision.** Extend the existing [Linux delivery owner](../../plans/linux-support-distribution.md), without adding another input stack. Report observed facts and offer reversible recovery: intended controller selection, reconnect, supported launcher and applicable mode checks. Only evidence of a particular host problem should lead to distribution/device-specific support. No generic root launch, world-writable devices, broad input-group membership or all-device sandbox access.

**Acceptance / next question.** Distinguish absent, denied, misclassified, sandbox-hidden and visible-but-unmapped fixtures for each offered package. Keep recovery accessible. Round two must identify what the exact engine can actually observe, so diagnostics do not invent a permission failure or encourage an unnecessary package migration.

## R1-05 — Can an OEM mode change preserve the same logical controller?

**Evidence.** ASUS documents Auto/Gamepad/Desktop behavior and an embedded-controller recovery option [S8]. Lenovo documents attached/detached controller presentation changes [S9]. Microsoft distinguishes XInput slots from physical identity and documents combined triggers for XUSB through DirectInput [S10]. These sources do not prove the exact IDs that OpenRC will observe on any model.

In [ControllerRegistry](../../../app/input/controller_registry.gd), identity fields drive generation changes; logical mapping/capability revisions are not themselves a continuity token. [ControllerService](../../../app/input/controller_service.gd) caches a profile against device ID and generation. A changed representation with unchanged recognized identity is a conditional stale-compatibility case.

**Decision.** Separate physical equipment, OEM mode, observed endpoint and player choice. Prefer the in-game controller picker. Model-specific OEM troubleshooting must explain how to re-enable the embedded pad or restore Auto; OpenRC must not disable drivers. Add a representation revision only when evidence supports it, with unknown remaining unknown. Clear affected caches/actions and hold flight on a verified representation change.

**Acceptance / next question.** Built-in plus external pad, changed player order, one/both detached controls, mode changes, independent trigger behavior and same-ID mapping changes. Round two investigates the engine's missing refresh events and a bounded fallback; no family-wide mapping promise follows from these guides.

## R1-06 — Is a matching saved profile the calibrated physical unit?

**Evidence.** [The association writer](../../../app/input/controller_service.gd) records GUID, VID/PID, optional serial and legacy key. [The store](../../../app/input/controller_profile_store.gd), `_association_matches`, accepts a serial match before checking GUID; `match_profile` checks ambiguity among currently connected devices. [V2 validation](../../../app/input/controller_profile.gd) rejects unknown association keys. SDL describes GUID as a platform-dependent device-class identifier, and serial is optional [S11].

**Counterexamples.** A same-serial device can expose a different mapping representation. Separately, serial-less radio A can be saved and unplugged, then same-family radio B can arrive alone and be the only current match. Snapshot uniqueness does not establish historical unit identity. These are source-derived cases, not observed hardware incidents.

**Decision.** Separate association confidence from mapping/calibration compatibility. Keep data intact; treat uncertain raw-radio association as a review suggestion before activation, with no new airplane-gamepad centered-dwell rule. A schema migration or validated sidecar is necessary before adding fields. Keep local identity/calibration/UI-device preference and temporary/rollback/lock files outside broad Steam Cloud selection. Cloud can replace matched files across machines and, with Dynamic Cloud Sync, during suspend [S12]; a local lock does not govern that external writer.

**Acceptance / next question.** Serial match with changed representation, sequential same-family replacement, simultaneous duplicates, unknown provider, USB/Bluetooth transition, migration and downgrade, cancellation preserving saved bytes. Round two specifies a minimally disruptive compatibility and persistence policy plus shareable diagnostic redaction.

## R1-07 — Are apparent keyboard gaps actually missing controller routes?

**Evidence.** [Workshop preview](../../../app/ui/workshop_preview.gd) already exposes focusable standard-view, orbit and zoom buttons. Its keyboard handlers do not prove a missing controller route. [Workshop](../../../app/ui/workshop.gd) also maintains explicit page navigation and popup flows. Conversely, [main](../../../app/main.gd) handles wheel brake, aircraft mechanisms, glow controls and flight-log commands outside the current [semantic action list](../../../app/input/controller_actions.gd); the inspected UI routes did not establish complete alternatives for those functions.

**Gap.** A blanket instruction to add a command menu is too coarse. A low-frequency toggle differs from a continuously held brake; an accessible menu cannot silently change a hold into a latch. Existing focusable widgets still need visual/exported verification. Xbox accessibility guidance supports single, non-simultaneous navigation and equivalent routes for auxiliary menu controls [S13]; it is design evidence, not an OpenRC certification.

**Decision.** Produce a concrete command inventory with capability, current entry point, semantic mode, alternative route and closure evidence. Reuse existing camera widgets. For genuinely missing commands, dispatch semantic intent through the owning activity; keep mechanical checks and release behavior. Make menu operation possible with sequential digital navigation and Accept/Back, without requiring paddles, pointer emulation or a simultaneous chord.

**Acceptance / next question.** Controller-only reachability in full and compact layouts; no hidden focus or popup escape cascade; hold/release across dialogs; commands absent or explained when the vehicle lacks the capability. Round two classifies the missing commands instead of allocating arbitrary new buttons.

## R1-08 — Can a platform keyboard safely edit existing fields?

**Evidence.** [Project translations](../../../app/project.godot) cover English plus Spanish, Simplified Chinese, Brazilian Portuguese, German, French, Italian, Russian and Japanese. A Latin-only grid is not equivalent text-entry coverage. In the pinned [LineEdit API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/LineEdit.xml), assigning `text` does not emit `text_changed`; IME, selection and composite characters have explicit behavior. [Workshop](../../../app/ui/workshop.gd) search/name/numeric fields and [customization](../../../app/ui/workshop_customization.gd) subscribe to change/submit signals and maintain separate pending edits.

**Gap.** Pasting a modal result into a widget is not sufficient to run validation, refresh search or commit one edit. A global synthetic Enter could submit the wrong dialog. The current Workshop FileDialog uses filesystem access and the engine's custom default; the pinned [FileDialog API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/FileDialog.xml) can force native dialogs in sandboxed Linux. An in-game browser cannot grant access that the sandbox has not granted.

**Decision.** Define a field adapter with begin/edit/accept/cancel semantics, selection, validation and one owning commit path; distinguish modal-result and injected-key keyboards. Qualify input language independently of translated UI. Reuse maintained composition/input services where possible; record incomplete provider/locale rows honestly. An accessible in-game file route may browse only already-authorized roots; retain the portal/native grant boundary for external files.

**Acceptance / next question.** Search, profile/build naming, numeric/hex fields, unsaved changes, selection replacement, accents/composite characters, Chinese/Japanese composition, cancel and late results. Round two checks Windows desktop integration, locale feasibility and exactly-once field transactions.

## R1-09 — Does the long-gap watchdog cover real sleep?

**Evidence.** [ControllerService._process](../../../app/input/controller_service.gd) detects a gap strictly above 5,000 ms only for an attached connected session. [AppRoot](../../../app/app_root.gd) attaches fixed-wing/helicopter sessions; quad, airship and ground use their own activity adapters. The existing watchdog test calls `_process` directly. The pinned [main loop](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/main/main.cpp) runs physics before idle processing, so a post-gap tick can precede that check if no earlier focus/disconnect boundary intervenes.

The pinned [Unix clock](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/unix/os_unix.cpp) uses `CLOCK_MONOTONIC_RAW` or `CLOCK_MONOTONIC`; Linux documents that these exclude system-suspend duration [S14]. Process freeze and actual system sleep are therefore different experiments. Optional Steam overlay/resume callbacks add signals but require a working callback pump [S15].

**Decision.** Preserve the gap fallback for detectable stalls, but do not call it a universal sleep detector. Gate input consumption before the first affected simulation step after a recognized boundary. Keep per-activity recovery rules, including quad fresh OFF→ON when focus/source invalidation requires it, and airship/ground-specific holds. Stationary controls are not stale merely because they produce no movement events.

**Acceptance / next question.** 4,999/5,000/5,001 ms fixtures; actual sleep versus process freeze; overlay with/without OS focus change; held controls; all activity adapters; no simulation integration after a recognized boundary until deliberate recovery. Round two resolves signal ordering and a common ingress contract without changing the kernel.

## R1-10 — Does 240 Hz imply fresh 240 Hz controller input?

**Evidence.** [Project settings](../../../app/project.godot) specify 240 physics ticks/s and at most 12 catch-up steps/rendered frame. [RcInput](../../../app/input/rc_input.gd) and activity sessions own fixed-tick conditioning/integration. The cap permits at most 180 ticks/s at a sustained 15 rendered frames/s: an arithmetic limit, not a measured device result. The fixed-wing scene disables global input accumulation; quad owns/restores that setting, while inspected ground/airship paths do not establish equivalent ownership. Godot documents input buffering separately from physics [S16].

**Gap.** Physics frequency is not USB/Bluetooth report frequency or measured latency. Reusing a sampled button state over several ticks must not re-emit a press; a short press between polls may be lost. Provider curves can combine with OpenRC shaping. Quad emits calibrated pre-expo sticks and its own controller's rate throttle: an additional unused internal accumulator is not proof of double integration in the output.

**Decision.** Name one owner per curve, rate integrator, sample history and action edge. Record render cadence, physics cadence and provider observations separately. Give global input-accumulation settings a lifecycle owner and restoration rule. Do not change the 240 Hz kernel or tune physics to compensate for input/display delay. Preserve provider/raw and conditioned evidence; post-conditioned replay cannot validate the mapping.

**Acceptance / next question.** Tick-indexed equivalence plus separate physical response measurements; low/high frame rates, brief presses, pause, held throttle, stale generation and activity switching. Do not infer common clocks for SDL events, Godot observations and video. Round two defines a finite qualification matrix and measurable evidence before setting an absolute latency target.

## Primary references

All accessed 2026-11-20. Exact engine/source links appear with their findings. Existing project links resolve to the audited branch; runtime code is unchanged.

| ID | Source |
| --- | --- |
| S1 | [Godot GDExtensionManager](https://docs.godotengine.org/en/latest/classes/class_gdextensionmanager.html) |
| S2 | [Steam API initialization/relaunch](https://partner.steamgames.com/doc/api/steam_api), [SDK overview](https://partner.steamgames.com/doc/sdk/api) |
| S3 | [SDL Steam handle](https://wiki.libsdl.org/SDL3/SDL_GetGamepadSteamHandle) |
| S4 | [Steam input actions, configuration and slot callbacks](https://partner.steamgames.com/doc/api/isteaminput?language=english) |
| S5 | [Steam action manifests](https://partner.steamgames.com/doc/features/steam_controller/action_manifest_file) |
| S6 | [SDL Linux troubleshooting](https://wiki.libsdl.org/SDL3/README-linux), [Linux hidraw](https://docs.kernel.org/hid/hidraw.html) |
| S7 | [Flatpak device permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html), [host integration limits](https://docs.flatpak.org/en/latest/introduction.html) |
| S8 | [ASUS Ally FAQ](https://www.asus.com/support/faq/1050046/) |
| S9 | [Lenovo Legion Go guide](https://download.lenovo.com/pccbbs/pubs/legion_go_8/user_guide/en/index.html) |
| S10 | [Microsoft XInput/DirectInput comparison](https://learn.microsoft.com/en-us/windows/win32/xinput/xinput-and-directinput), [XInput slots](https://learn.microsoft.com/en-us/windows/win32/xinput/getting-started-with-xinput) |
| S11 | [SDL joystick identity](https://wiki.libsdl.org/SDL3/CategoryJoystick), [optional serial](https://wiki.libsdl.org/SDL3/SDL_GetJoystickSerial) |
| S12 | [Steam Cloud](https://partner.steamgames.com/doc/features/cloud?language=english) |
| S13 | [Microsoft XAG 107](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107) |
| S14 | [Linux clock semantics](https://www.man7.org/linux/man-pages/man2/clock_gettime.2.html) |
| S15 | [Steam overlay](https://partner.steamgames.com/doc/features/overlay), [Steam utility callbacks](https://partner.steamgames.com/doc/api/isteamutils?language=english) |
| S16 | [Godot input accumulation](https://docs.godotengine.org/en/stable/classes/class_input.html), [physics step cap](https://docs.godotengine.org/en/stable/classes/class_engine.html) |

## Round-one disposition and next round

Accepted: early native loading and packaging gate; live representation evidence; explicit Steam migration/rollback; differentiated Linux recovery; calibration compatibility; semantic command inventory; locale/field transactions; suspend-aware lifecycle qualification; separate timing evidence. Rejected: assuming every keyboard handler is a controller gap, automatic OEM driver changes, class GUID as unit identity, timing-based universal deduplication, a Latin-only keyboard as universal coverage, and 240 Hz as a latency result.

Only after completing these ten investigations, the next ten were selected: early bootstrap feasibility (11), metadata refresh contract (12), layout promotion/rollback (13), observable Linux recovery (14), profile compatibility/migration (15), diagnostic privacy/evidence (16), command semantics (17), desktop text-entry transactions (18), lifecycle ingress ordering (19), and finite release qualification (20). Each must change a decision, specify a discriminating test or explicitly retain an unresolved limit; no objection quota applies.
