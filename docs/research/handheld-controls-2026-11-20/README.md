# Handheld controller automation research

**D6-HH-00 — 20 November 2026; initial audit plus twenty additional investigations complete.** Research and source inspection only. No handheld, controller, exported game or Steamworks application was exercised. The [implementation plan](../../plans/handheld-controller-automation.md) owns proposed work; its [acceptance companion](../../plans/handheld-controller-acceptance.md) specifies the gates. [Controller support](../../plans/controller-support.md) retains the implemented input contracts.

## Scope and conclusion

Automatic controls are feasible across native Windows and Linux/SteamOS, with a separate Windows-through-Proton qualification route. Build on OpenRC's existing Godot/SDL controller implementation. Add a complete controller-operated interface and optional Steam services, then qualify individual hardware configurations. A device's brand is insufficient evidence of its exposed controls, selected OEM mode or physical identity.

The scope includes Steam Deck, the current Steam Machine with external controllers, ROG Xbox Ally/Ally X, the older ROG Ally family, Lenovo Legion Go/Go S, MSI Claw and other Windows/Linux handheld PCs. Steam Machine is a living-room PC, so it needs an external-controller and docked-display journey, not a built-in-handheld assumption. Xbox Ally runs Windows; this does not require an Xbox console port. Android handhelds and closed-console exports are separate projects. [V2, V9, O1]

## Audited identities and method

| Item | Inspected identity / scope |
| --- | --- |
| OpenRC source | `bultodepapas/OpenRCsimulator`, main commit `a27c44fcaec0401de852c9a2f791041e34e3974d` |
| Engine pin | `app/get-godot.sh`: `4.8-beta2`, `4.8.beta2.official.cafc17a19` |
| Engine source | `godotengine/godot` commit `cafc17a192acf67903910a68aeb3c076c0907a4b`; relevant API XML, SDL driver and input defaults inspected |
| Bundled controller backend | SDL `3.4.12`, upstream `f87239e71e42da91ca317a12eefb82cfbf3393eb`, recorded in the pinned engine's third-party manifest [G5] |
| Research | Valve, Microsoft, Godot, SDL and device-manufacturer primary sources, accessed 2026-11-20; public binding-maintainer material for the optional Steam integration |
| Evidence limits | Static source/API review. No measured input latency, device mapping, firmware behavior, suspend result, performance result or compatibility certification |

The audit used current code before historical plans. In particular, the documentation registry still describes Controls UX and EdgeTX as proposed, while their owning plans and source record delivered software. This investigation does not re-plan those delivered features or rewrite their unrelated status rows.

## Twenty additional investigations

The [first round](round-1.md) completed ten gap investigations before the next ten were selected. The [second round](round-2.md) resolves the resulting startup, freshness, persistence, transaction and qualification questions. Primary platform documents were checked against exact pinned engine and current application source; source-derived counterexamples are distinguished from observed hardware failures. All twenty are complete as research, with implementation and real-environment tests still pending.

| First ten: gap | Next ten: resulting design decision |
| --- | --- |
| [01 Optional Steam failure stages](round-1.md#r1-01--can-an-optional-steam-integration-really-be-absent) | [11 Early native startup](round-2.md#r2-11--can-optional-steam-startup-precede-sdl-without-an-engine-replacement): qualify a minimal pre-SDL seam and supported loader failures before binding adoption. |
| [02 Steam association and ownership](round-1.md#r1-02--does-a-handle-establish-live-source-ownership) | [12 Metadata freshness](round-2.md#r2-12--what-would-make-steam-association-genuinely-current): cached live handles cannot prove correct pairing after slot swaps. |
| [03 Manifest and custom-layout migration](round-1.md#r1-03--will-packaged-layouts-preserve-custom-configurations) | [13 Native promotion and rollback](round-2.md#r2-13--how-do-native-actions-enter-fail-and-roll-back): session opt-in, separate context readiness and explicit unrecoverable controller-only cases. |
| [04 Linux discovery and permissions](round-1.md#r1-04--what-does-an-empty-linux-controller-list-mean) | [14 Observable Linux recovery](round-2.md#r2-14--what-linux-recovery-can-the-application-substantiate): report actual observations, retain unknown causes and avoid broad privilege changes. |
| [05 OEM mode and representation changes](round-1.md#r1-05--can-an-oem-mode-change-preserve-the-same-logical-controller) | [15 Minimal compatibility policy](round-2.md#r2-15--what-is-the-smallest-safe-saved-calibration-change): session review for uncertain raw calibration, distinct from ordinary gamepad startup. |
| [06 Profile identity, persistence and Cloud](round-1.md#r1-06--is-a-matching-saved-profile-the-calibrated-physical-unit) | [16 Shareable diagnostics](round-2.md#r2-16--what-may-a-shareable-diagnostic-report-honestly-claim): preserve local CLI, add an allowlisted globally bounded report and honest disclosure. |
| [07 Command and navigation inventory](round-1.md#r1-07--are-apparent-keyboard-gaps-actually-missing-controller-routes) | [17 Semantic command completion](round-2.md#r2-17--which-missing-commands-need-more-than-another-menu-button): retain hold/toggle guards and resolve paused-rejected interactions. |
| [08 Text-entry and file boundaries](round-1.md#r1-08--can-a-platform-keyboard-safely-edit-existing-fields) | [18 Desktop editor transactions](round-2.md#r2-18--can-desktop-keyboards-preserve-real-editor-transactions): preserve draft/validation/focus semantics and qualify provider/locale coverage. |
| [09 Sleep clock and activity coverage](round-1.md#r1-09--does-the-long-gap-watchdog-cover-real-sleep) | [19 Event-and-tick continuity](round-2.md#r2-19--where-must-continuity-loss-stop-command-consumption): gate on recognized boundaries and preserve reason-specific activity policy. |
| [10 Sampling, frame rate and latency](round-1.md#r1-10--does-240-hz-imply-fresh-240-hz-controller-input) | [20 Finite qualification campaign](round-2.md#r2-20--what-finite-evidence-is-enough-to-qualify-a-configuration): exact configuration rows, mandatory fault cycles and correctly bounded timing measurements. |

The rounds deliberately cross-link topics: representation findings feed both metadata and calibration, while persistence/diagnostic findings share evidence requirements. The authoritative plan incorporates the conclusions; the round reports preserve evidence and limits. A dated [baseline-drift note](../../plans/handheld-controller-automation.md#verification-rollout-and-open-dependencies) records the comparison with later main without changing the audited runtime.

## What OpenRC already implements

| Existing behavior | Source / consequence for this plan |
| --- | --- |
| Automatic startup/Home selection | [`controller_service.gd`](../../../app/input/controller_service.gd), `_apply_automatic_defaults_locked`: saved matching profile, radio, known gamepad, then other device; automatic changes are blocked during an active session. Preserve that policy and explicit overrides. |
| Separate pilot and menu devices | [`controller_registry.gd`](../../../app/input/controller_registry.gd) maintains `flight` and `ui` roles, connection generations, disconnect edges and ambiguous associations. A new pad must not take over a live flight. |
| Saved V2 profiles and transactional setup | [`controller_profile.gd`](../../../app/input/controller_profile.gd), [`controller_profile_store.gd`](../../../app/input/controller_profile_store.gd) and [`controller_setup.gd`](../../../app/ui/controller_setup.gd) already own mapping, drafts, persistence and recovery. |
| Standard gamepad readiness and throttle | [`rc_input.gd`](../../../app/input/rc_input.gd), `poll_device`: a verified, focused standard pad becomes ready from its first valid poll. Rate throttle integrates at the fixed tick; radios retain fresh low-throttle evidence. Do not restore the superseded centered-dwell gesture. |
| Default layouts and vehicle-aware actions | `ControllerProfile.defaults` supplies Mode 1/2 rate throttle and an explicit trigger-throttle preset. [`controller_actions.gd`](../../../app/input/controller_actions.gd) owns context-aware actions and aircraft/helicopter capabilities. |
| Selected-device menu navigation | [`ui_input.gd`](../../../app/ui/ui_input.gd) installs mappings for exactly one menu pad and isolates other joysticks. Verified radio navigation has a separate adapter. |
| Graphical Controls workspace | The [Controls UX plan](../../plans/controls-setup-ux.md) records UI-15-UX-01…08 and D6-UX-01 as delivered. The Setup assistant remains an offer, not a mandatory startup wizard. |
| Focus and discontinuity protection | [`app_root.gd`](../../../app/app_root.gd) opens Pause and clears actions on continuity loss. `ControllerService._process` detects a greater-than-five-second processing gap for an attached session. Extend and verify these paths. |
| Prompts and diagnostics | [`controller_prompts.gd`](../../../app/ui/controller_prompts.gd) supports Xbox/PlayStation/Nintendo/generic families and user override; existing F1 reports and redacted setup diagnostics provide the starting evidence tools. |

These are source findings, not confirmation that a particular handheld currently works.

## Concrete gaps found

### 1. Steam metadata is dropped, and a diagnostic field has the wrong domain

`ControllerService.observed_devices()` reads `Input.get_joy_info()`. `ControllerRegistry._normalize_observation()` retains its own named fields but drops the Steam association and capability hints. It therefore cannot currently use that association to relate two input providers.

More specifically, [`input_report_data.gd`](../../../app/input/input_report_data.gd) sends `steam_input_index` through `optional_index()`, which permits at most six decimal characters and values up to 65535. In the pinned Godot SDL driver, the misleadingly named field is produced by `itos(SDL_GetGamepadSteamHandle(gamepad))`: it is a Steam `InputHandle_t`, not a small slot. Larger valid values become `null` in the report. [`test_input_report_buttons.gd`](../../../app/tests/test_input_report_buttons.gd) uses the artificial value `"2"`, which does not cover this mismatch. [G2, S1]

**Implementation implication:** introduce a version-scoped metadata decoder and retain the handle losslessly as an opaque decimal string. Keep it separate from Godot IDs, connection generations and Windows XInput slots. Do not use it as persistent physical identity or pass it through JSON floating-point numbers. SDL defines zero as unavailable. The pinned engine's `itos(int64_t)` also introduces a signed boundary for SDL's unsigned 64-bit return; preserve the raw representation and verify round-trips around 2^63, including signed encodings, through the chosen native binding. Include 2^53 + 1 and the uint64 boundaries in synthetic tests. This is a source-level boundary risk, not an observed hardware handle. Update the diagnostic schema deliberately; retain redaction and distinguish unavailable, invalid and withheld data. [G6, S1]

### 2. Family glyphs are not Steam action origins

`ControllerPrompts.resolve_family()` already handles manual override and conservative family recognition. However, there is no Steam origin query or Deck/Steam Controller action-label integration. An emulated Xbox name cannot prove which physical device the player holds. A family image alone also cannot describe a Steam user remap or chord.

**Implementation implication:** preserve the current presentation fallback. In gamepad emulation, `GetActionOriginFromXboxOrigin` translates standard buttons into device-family origins but explicitly ignores user remapping. An associated handle therefore does not reveal arbitrary physical remaps/chords. Show OpenRC's effective logical binding with a truthful fallback. The later native-action provider can query origins using actual action-set/action handles and refresh them on configuration/context changes; an origin alone must not be treated as a full chord/activator description. Cache images separately and never change control semantics when a glyph family changes. [V3, V5]

### 3. Desktop text input is a separate feature

No Steamworks keyboard, Windows gamepad keyboard or shared desktop controller text-entry service was found in the audited runtime. The exact engine's `DisplayServer.virtual_keyboard_show` support is documented for Android, iOS and Web, not desktop Linux/Windows. A focusable `LineEdit` therefore does not establish a controller-only text-entry path. [G4]

Microsoft provides a Windows gamepad keyboard route through `CoreInputView::TryShow(CoreInputViewKind::Gamepad)`. Its sample requires Windows 11 24H2 build 26100.3613 or later; the named enum requires suitable SDK headers. The call can decline. Steam offers its own text-input services. An in-game controller keyboard is the portable fallback, including standalone Linux, unavailable overlays and older Windows configurations. [M1, M2, V4]

The adapters have different completion semantics: Steam's modal text dialog returns submitted text through its dismissal flow, while its floating keyboard sends OS key events and only signals dismissal. Windows `TryShow`/`TryHide` control a system keyboard, not an asynchronous submitted-text result. Use editor-generation checks for modal results and explicit focus/input isolation plus dismissal for floating/system keyboards. [V4, M4]

### 4. Existing navigation needs a complete product inventory

The project has substantial navigation and capture handling; it is not starting from mouse-only menus. Remaining acceptance must cover every reachable shipping flow: initial screens, settings, aircraft/field selection, Help, profile naming/search, dialogs, pause/restart, imports/exports and recovery. Native file pickers and external-page launches require particular review.

Source examples needing inventory include F10/F11 flight logging and F6…F9 glow-engine controls in [`main.gd`](../../../app/main.gd), and the fixed-key entries in [`controls_reference.gd`](../../../app/ui/controls_reference.gd). A keyboard handler is evidence to investigate, not proof that no alternate UI route exists. Add missing player-facing routes through semantic commands; debug-only shortcuts need not become gamepad buttons.

### 5. Lifecycle and provider changes need explicit qualification

The project explicitly sets `input_devices/joypads/ignore_joypad_on_unfocused_application=false`. The engine exposes an opt-in guard, but toggling it without auditing release events, raw calibration, embedded dialogs and existing recovery would be a behavior change. Existing shell/session safeguards remain authoritative. [G1, G3]

Steam overlays, Game Bar, OEM overlays, sleep, dock changes and virtual-controller replacement may not all resemble an ordinary disconnect. Provider/configuration changes must reach the existing continuity path without double actions, stale held inputs or automatic Continue. No such physical test was performed here.

## Platform findings

### Steam Deck, Steam Machine and SteamOS

Valve's current checklist covers default controller operation, appropriate prompts and controller-accessible text entry. Its performance/display checks remain separate from this input project. Internal completion cannot award a Steam compatibility badge. [V2]

For basic controls, Steam's gamepad-emulation path can feed the same Godot/SDL implementation as ordinary gamepads. Preserve RC radios: Valve specifically advises against opting Generic/DirectInput devices into Steam remapping for games supporting specialized sticks/wheels. [V1]

The current `ISteamUtils` reference exposes `IsRunningOnSteamHardware()` and `IsRunningUnderProton()`, while `IsSteamRunningOnSteamDeck()` is deprecated from SDK 1.65. Its broader recommendations page still contains a note about future detection APIs; use the more specific API reference and verify the selected binding. Hardware detection should inform presentation/diagnostics, not determine button indices. [V4, V6]

Steam's native action interface can supply logical actions, current origins, glyphs and optional motion. It is a later provider option, not a prerequisite for the baseline. `SteamInput.Init()` returning true does not establish a valid loaded action configuration. Pure action layouts may have no emulated gamepad slot; this matters for fallback and device association. [V3, V1]

Official layouts can be delivered with an action manifest in the depot. Author/export them with a supported Steam client and version them beside the implementation. Keep ordinary actions reachable without paddles or gyro. Mixed mouse-style camera and stick input should coexist without flickering keyboard prompts. [V7, V6]

### Windows handhelds

Microsoft's 14 November 2026 guidance provides `RtlGetDeviceFamilyInfoEnum` and `DEVICEFAMILYDEVICEFORM_GAMING_HANDHELD` (`0x2E`). The sample recommends responding to actual properties and state rather than putting all behavior behind that form-factor flag. A missing or generic form-factor value must not disable controller support. [M1, M2]

ROG Xbox Ally's Xbox button opens system facilities; it is not a dependable in-game Pause button. Armoury Crate SE owns device modes, remaps and other manufacturer settings. MSI likewise documents GamePad/Desktop modes. Microsoft explicitly notes that Desktop/mouse mode may prevent recognition of gamepad input. The game should describe possible causes and retain touch/mouse recovery, without claiming it detected or changed an OEM mode. [O1, O2, O5, M2]

Lenovo publishes a SteamOS Go S guide. Its detachable Legion Go guide describes different input presentations depending on attachment, including Dual D-input when one controller is detached. Test model, firmware and attachment state explicitly; do not silently join two raw joysticks into a pilot controller. [O3, O4]

Standard XInput mappings do not guarantee access to arbitrary extra buttons. Device-side gyro or rear-button hardware may be exposed only through OEM remaps, a different provider, or not at all. Neither a hardware feature list nor a controller-family string establishes application-visible support. [M3]

### What the pinned engine already provides

The pinned engine exposes `has_joy_vibration` and experimental joypad motion-sensor/touchpad APIs. Use capability checks and `get_joy_gyroscope(device)` for an exposed controller sensor; the older general `get_gyroscope()` API concerns mobile device sensors. Desktop gyro does not inherently require a second SDL integration. [G1]

Godot device numbers are connection handles, and metadata types need normalization. The pinned SDL implementation serializes USB IDs and XInput indices as decimal strings. Existing OpenRC USB normalization already handles these; the Steam handle needs a different domain. Unknown metadata stays unknown. [G2]

### Native Linux, Proton and alternative operating systems

Qualify native Linux/SteamOS and Windows-through-Proton separately, preserving the existing [Linux delivery plan](../../plans/linux-support-distribution.md) for runtime, packaging, input permissions and portal behavior. Steam desktop mode, Gaming Mode and a directly launched binary are separate environments.

Valve provides Windows resources for Deck/Machine with additional-driver qualifications. Treat Windows on those devices, and community Linux installations on Windows handhelds, as separate conditional configurations. Do not promise driver coverage for every model or make changing the user's operating system part of controller automation. [V8]

## Alternatives and decision

| Approach | Decision / reasoning |
| --- | --- |
| Extend the current Godot/SDL path | **Baseline.** Already used by profiles, menus, calibration and vehicle adapters; works without a storefront account. |
| Steam assistance over emulated gamepad input | **Next Steam increment.** Add proven identity association, device-family glyphs within emulation limits, keyboard and lifecycle services while retaining existing command sampling. |
| Full native Steam Input actions | **Conditional later increment.** Valuable for named remapping and extra controls; requires complete provider ownership, action/configuration validation and migration rules. |
| A separate GameInput or SDL polling stack | **Defer.** No baseline gap justifies duplicate controller ownership and another mapping/persistence system. A narrow Windows platform-service bridge remains reasonable. |
| One hardcoded preset per handheld name | **Reject as the architecture.** Virtual gamepads, external pads, firmware modes and identical names defeat brand-based assumptions. Allow narrowly evidenced, versioned exceptions only. |
| Required community layouts or OEM macros | **Reject as the default experience.** Essential operations must be reachable from the shipped layout and in-game interface. |

GodotSteam is a candidate binding, not an adopted dependency. Its official GitHub repository points to Codeberg; GitHub release assets are described as overflow copies. Select and pin a maintained upstream commit, SDK, binaries and licenses during the integration spike, then verify compatibility with this exact beta engine and export templates. Public release labels do not prove ABI or API coverage. [B1]

## Primary source catalog

All sources below were accessed on **2026-11-20**. Bracketed IDs in this report refer to this table. API availability is source evidence; hardware qualification remains pending.

| ID | Primary source | Evidence used |
| --- | --- | --- |
| G1 | [Godot Input API at the exact engine commit](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/Input.xml) | Metadata, connection enumeration, motion, rumble and focus APIs; experimental feature limits |
| G2 | [Pinned Godot SDL driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/sdl/joypad_sdl.cpp) | Actual decimal-string serialization and Steam-handle origin |
| G3 | [Pinned Godot input implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/input/input.cpp) | Focus setting implementation/default |
| G4 | [Pinned Godot DisplayServer API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/DisplayServer.xml) | Desktop virtual-keyboard capability gap |
| G5 | [Pinned third-party manifest](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/thirdparty/README.md) | SDL 3.4.12 identity |
| G6 | [Pinned Godot string declarations](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/string/ustring.h) | Signed `itos(int64_t)` versus unsigned `uitos(uint64_t)` serialization boundary |
| S1 | [SDL_GetGamepadSteamHandle](https://wiki.libsdl.org/SDL3/SDL_GetGamepadSteamHandle) | Unsigned 64-bit Steam handle; zero means unavailable |
| V1 | [Steam gamepad-emulation best practices](https://partner.steamgames.com/doc/features/steam_controller/steam_input_gamepad_emulation_bestpractices) | Emulation, device association and specialized-controller opt-in |
| V2 | [Deck and Machine compatibility review](https://partner.steamgames.com/doc/steamhardware/compat) | Controller defaults, prompts, text entry and review scope |
| V3 | [ISteamInput](https://partner.steamgames.com/doc/api/isteaminput?language=english) | Actions, origins, initialization and configuration/provider capabilities |
| V4 | [ISteamUtils](https://partner.steamgames.com/doc/api/isteamutils?language=english) | Current hardware/Proton detection, keyboard services and resume callback |
| V5 | [Steam Input developer introduction](https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_devs) | Resolve current action origins and controller configuration |
| V6 | [Preparing for Deck and Machine](https://partner.steamgames.com/doc/steamhardware/recommendations) | Mixed input, prompt stability and automatic text entry; older detection note treated cautiously |
| V7 | [Action manifest files](https://partner.steamgames.com/doc/features/steam_controller/action_manifest_file) | Ship versioned official configurations in depots |
| V8 | [Steam hardware Windows resources](https://help.steampowered.com/en/faqs/view/6121-ECCD-D643-BAA8) | Separate Windows configuration and driver/support limits |
| V9 | [Steam Machine support guide](https://help.steampowered.com/en/faqs/view/1180-0BA6-4A75-B7CA) | Current Machine, Linux desktop and external-display context |
| M1 | [Microsoft handheld guidelines](https://learn.microsoft.com/en-us/gaming/gdk/docs/gdk-dev/pc-dev/handheld/handheld-guidance?view=gdk-2610) | Updated 2026-11-14; form factor, gamepad UI and keyboard API |
| M2 | [Microsoft handheld sample](https://learn.microsoft.com/en-us/samples/microsoft/xbox-gdk-samples/handheldbestpractices/) | OEM mode limit, keyboard OS floor, capability-based guidance |
| M3 | [Microsoft controller hardware interfaces](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/input/hardware/input-hardware-interfaces?view=gdk-2610) | XInput and generic HID capability boundaries |
| M4 | [Microsoft virtual keyboard support](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/input/overviews/virtualkeyboardsupport?view=gdk-2604) | Windows system-keyboard show/hide API and distinction from console text-result APIs |
| O1 | [ASUS ROG Xbox Ally](https://rog.asus.com/co/gaming-handhelds/rog-ally/rog-xbox-ally-2025/) | Windows platform and system Xbox button |
| O2 | [ASUS Armoury Crate SE guide](https://rog.asus.com/support/faq/1050220/) | OEM modes, remapping and device-specific features |
| O3 | [Lenovo Go S SteamOS guide](https://download.lenovo.com/pccbbs/pubs/legion_go_s_8arp1/user_guide/en/go_s_steam.html) | Official third-party SteamOS handheld route |
| O4 | [Lenovo Legion Go guide](https://download.lenovo.com/pccbbs/pubs/legion_go_8apu1/user_guide/en/index.html) | Attachment states, input modes and FPS mode |
| O5 | [MSI Claw guide](https://www.msi.com/Handheld/Claw-Guide) | GamePad/Desktop modes and manufacturer-managed features |
| B1 | [GodotSteam upstream pointer](https://github.com/GodotSteam/GodotSteam), [release listing](https://github.com/GodotSteam/GodotSteam/releases) | Maintainer's Codeberg move; binding evaluation remains open |

## Open evidence

No Steam App ID, partner configuration, qualified binding or owned handheld inventory was established in this audit. These affect the Steam integration and hardware schedule, not the ability to implement the portable baseline. A missing feature needs a capability fallback; it must not be represented as successful device detection.

Before promising a supported row, retain the exact build, engine, OS, Steam/Proton versions where applicable, OEM mode, controller model/firmware, transport, profile/config revision and journey results. Record software checks, physical controls, pilot acceptance, package validation and performance as separate results. The plan defines the tests and promotion gates.
