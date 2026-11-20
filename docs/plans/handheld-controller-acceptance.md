# Handheld controller acceptance contracts

**Status: proposed acceptance, 2026-11-20. No case below is a test result.** This is the acceptance companion to the [authoritative handheld plan](handheld-controller-automation.md), informed by [round one](../research/handheld-controls-2026-11-20/round-1.md) and [round two](../research/handheld-controls-2026-11-20/round-2.md). It defines evidence for the existing D6/F1/F3/F4/UI-HH steps, not another implementation track. The [parent controller contract](controller-support.md#explicit-gaps-and-acceptance-rules) and activity owners remain authoritative.

## What a completed configuration means

A configuration is one named device/model, OS, native/Proton runtime, launch path, exposed provider, relevant OEM mode and controller transport. A Windows result does not qualify SteamOS or Proton. One Legion Go attachment mode does not qualify another. A family name, passing unit test or observed SDL mapping cannot close a physical row.

For every promised configuration, the exported game must complete the controller journey, preserve saved choices, recover from the required faults and retain evidence. Optional services may fail within their supported failure contract without removing the portable journey. If the only available endpoint loses every usable recovery binding, that controller-only row is blocked, even if keyboard recovery works.

## Implementation dependencies and gates

| Gate / owner | Required before closing the gate | Blocking evidence still needed |
| --- | --- | --- |
| Portable metadata / D6-HH-01 | Lossless handle decoder, observed/unknown/withheld distinctions, no stale association promoted to current | Exact pinned-engine metadata fixtures and refresh strategy |
| Selection and compatibility / D6-HH-02/07 | No active takeover; uncertain raw calibration reviewed before flight/menu activation; V2 review/cancel leaves bytes intact | Service and direct-adapter tests, current-connection range/AUX evidence |
| Full journey / UI-12-HH-01, UI-15-HH-01 | Reachable navigation, usable semantic commands, editor transactions and authorized file routes | Exported UI and provider/locale coverage |
| Continuity / F3-HH-01 | Event and physics consumers share the recognized-boundary gate and reason-specific recovery | Ordered traces plus actual OS/overlay/sleep behavior |
| Shareable evidence / F1-HH-02 | Versioned allowlist, whole-capture bounds, truthful disclosure and no-overwrite output | JSON/stdout/stderr adversarial fixtures and existing CLI compatibility |
| Steam bootstrap / D6-HH-03 | Optional load failure contract, Steam-before-SDL startup trace, one lifecycle owner | Exact binding/SDK/binary/template pair; Windows and Linux exports |
| Native actions / D6-HH-04/05 | Explicit opt-in, usable contexts/bindings, fresh ownership, packaged manifest and tested rollback | Authorized partner configuration and actual client/hardware campaign |
| Release / F4-HH-01/02 | Complete per-configuration evidence below | Exact equipment, exported builds and physical results |

The portable gates can proceed without a Steam App ID. The early-bootstrap spike can run in parallel, but must pass before choosing a Steam integration. Extra controls/rumble and expanded device families follow correctness; they do not block a completed standard-layout route. A narrow upstream metadata hook is an option to qualify, not permission to replace the engine or add a second polling stack.

## Continuity contract

The guarantee starts when the application recognizes a relevant boundary. It cannot retroactively undo a simulation step before a late OS callback. Close the gameplay gate synchronously before subsequent event-driven actions and physics consumption; an already executing tick may finish. Defer presentation changes if necessary. Native-thread notifications use safe marshaling/flags.

| Reason / activity | Required preserved behavior |
| --- | --- |
| Initial verified, focused standard airplane gamepad | Existing first-live-poll readiness; no new centered dwell or release gesture. |
| Ordinary airplane Pause or focus hold | Preserve staged rate throttle and explicit Continue. For the same standard gamepad, retain verified focused-poll recovery without a stick gesture, including stationary sticks. |
| Actual airplane controller disconnect | RcInput resets to idle and clears staged start/rate state; reconnect must not restore a held-throttle assumption or advance flight. |
| Ordinary quad Pause | Preserve the current pause/arm contract for an unchanged input source; do not convert every Pause into focus invalidation. |
| Quad focus/source invalidation | Revoke arm according to the current adapter; require fresh low-throttle OFF→ON recovery. |
| Helicopter | Keep collective, arming, curve and hold policy with its session; preserve rejection of unsupported trigger-absolute profiles. |
| Airship | Keep its paused zero-rate-throttle and recovery low-throttle/yaw policy. |
| Ground vehicle | Keep neutral steering/trigger readiness and activity-local selection. |
| Verified provider/representation continuity loss | Hold through the owning activity's reviewed reason-specific policy, clear stale edges and requalify before explicit recovery. Do not pretend it is an actual cable disconnect merely to reuse code. |
| Harmless duplicate-family arrival for an already selected generic source | Reevaluate pending matching, but preserve the existing uninterrupted active-flight protection. A registry-generation increment alone is not proof of continuity loss. |
| JETI identity-ambiguity change | Preserve the registry's explicit flight/UI selection invalidation and resulting hold; the generic-source exception does not apply. Changing this policy requires separate JETI-owner review and verification. |

Preserve independent crash/reset/activity holds. Continue must not clear those accidentally. Release previously delivered virtual/menu holds; discard old arm/restart/Continue intents. Allow readiness observations while gameplay is gated. Each accepted digital intent is delivered at most once in the current continuity epoch; analog levels retain their existing fixed-tick integration owner.

**Readiness versus physical freshness:** preserve the implemented same-source standard-gamepad focused-poll recovery after ordinary focus return; its stationary-stick Continue regression must pass. It is an application readiness contract, not proof of when hardware generated a sample. For actual suspend/provider discontinuity, name the provider's demonstrated drain, repump, generation or post-boundary evidence mechanism. Cached levels, Godot receipt time, a handle still in Steam's list, three seconds elapsed or an unchanged stick do not independently prove that stronger claim. Missing evidence leaves that qualification pending; it must not silently impose a new ordinary-focus movement gate. Any changed recovery rule needs explicit activity/input-owner review. Do not introduce a stationary-controller timeout.

**Ordered fixtures:** inject boundary recognition before event flush, during action dispatch, between event dispatch and physics, before a catch-up tick and immediately before Continue. Record boundary recognition, gate closure, source epoch, accepted action and simulation-step ordering. Test down/up while gated, a late old-source callback, repeated notifications and unavailable optional signal sources. Separate actual suspend from process freeze and exercise the 4,999/5,000/5,001 ms watchdog boundary.

## Required failure and compatibility cases

| Case group | Minimum cases and expected outcome |
| --- | --- |
| Handles and metadata | Absent/zero/malformed/type variants; values above 65535 and 2^53; signed/unsigned boundaries around 2^63 and uint64; no lossy JSON number. Both-live slot swap and handle change without reconnect must invalidate stale links. |
| Optional native loading | Missing extension/dependency, supported returned load errors, absent/offline client, API failure and partial shutdown. Portable startup remains usable within that supported contract; arbitrary native crashes are not contained by a flag. |
| Raw profile compatibility | Same serial with changed representation; serial-less A unplugged then B alone; calibrated joystick; uninterrupted generic duplicate arrival and JETI ambiguity invalidation as separate cases; review interrupted by reconnect; edited mapping; failed raw travel/throttle/AUX evidence. No active flight/menu profile before required review. |
| Review/persistence | Review/cancel has byte-for-byte V2 equality; a changed association normally uses Duplicate/new UUID; Save keeps existing validation/lease/activation rollback. Later V3/sidecar work must test torn data and a stale readable V2 `.rollback`, including downgrade. |
| Standard gamepad preservation | Clean/saved startup, first focused verified poll, stationary verified-pad Continue after ordinary focus return, Mode 1/2 rate behavior, explicit trigger preset, keyboard preference, separate menu pad, no takeover by drift or arrival. |
| Native-action recovery | Loading/wrong context/unbound essential actions; pure native without SDL peer; absent overlay; service loss; mixed synthetic keyboard provenance. Use only demonstrated fallback routes; irrecoverable controller-only combinations remain blocked. |
| Linux discovery | No endpoint → unknown cause; actual candidate denial only when observed under the app's credentials/namespace; node visibility and classification reported separately; read-only input without rumble accepted as limited capability. |
| Semantic command access | Mechanism capability/state guards, paused-rejected command usability, hold/release brake, glow controls and recording eligibility. No F-key synthesis, accidental latch or implicit Continue. |
| Text and files | Modal versus injected input, selection, change/submit/focus-exit validation, invalid text, cancel, late result, screen switch, DPI/dock changes and authorized-root/portal boundary. |
| Diagnostics | Identifying strings in names/paths/errors/nested metadata; JSON plus stdout/stderr; global reconnect/byte limits and omission counts; no calibration writes; local CLI v1 compatibility. |

Use the nearest existing tests listed in the main plan. Add only behavior tests needed for these contracts; do not mirror implementation details or alter physics goldens. Tests using synthetic devices or event injection prove software behavior, not physical controller compatibility.

## Text-entry and command closure records

Each shipping editor gets an owner and a short record: purpose, free-text/numeric/hex constraints, change/commit path, focus-exit behavior, cancellation scope, applicable keyboard provider and supported input locales. Include Controls profile naming, Workshop search/build naming and numeric/customization fields, and Creator/import/export flows. Record each provider/locale as passed, blocked or not tested; UI translation alone does not close text input.

Modal results may affect only the still-current editor generation. Floating/system keyboards require exclusive editor focus and isolation while dismissing or changing screens. A dismissed keyboard does not mean the edit was accepted. Preserve the field draft on provider failure and avoid submitting twice. English/Spanish fallback tests do not qualify Chinese/Japanese composition or every maintained locale. Controller-visible error feedback is part of the journey.

For each missing command, record semantic intent, capability guard, binding/context, reachable interaction and observed result. Paused-rejected mechanisms need a usable running interaction or an explicitly reviewed single-intent staging contract after deliberate Continue; a button added to Pause is insufficient. Held brake release must survive ownership loss. Existing Workshop camera widgets are tested before proposing new ones.

## Finite physical campaign

Start with available equipment covering the routes below. Split each into exact model, firmware, transport and mode records. These are campaign groups, not six inferred hardware passes. The [main matrix](handheld-controller-automation.md#physical-qualification-matrix) retains target priorities and conditional alternate operating systems.

| Campaign group | Distinct route coverage |
| --- | --- |
| Portable desktop baseline | Native Windows and native Linux, direct launch; standard pad plus separate RC/menu-pad coexistence. |
| Windows handheld | Exact Xbox Ally/Ally X or available model, direct and Steam launch; intended Gamepad/Auto mode, external pad and relevant system/OEM overlay. |
| Steam Deck | Native SteamOS and the Windows build through Proton separately; built-in controls, dock/external controller and desktop/standalone discovery where offered. |
| Steam Machine | Native and Proton separately when equipment is available; exact external controller/transport, controller order and living-room display. |
| Steam assisted/native actions | Each offered OS/provider route, clean/user layouts, service unavailable, native-only/emulated/mixed cases and configuration rollback. |
| Additional hardware/modes | Legion attachment/FPS modes, Go S SteamOS, Claw and other available handhelds; test exposed differences before extending support. |

For **every promised configuration**, run clean and saved/custom-profile journeys and at least ten reconnect plus ten actual sleep/resume cycles. Include Home → vehicle/field → flight → Pause → Settings/Controls → explicit Continue → restart → Home → Quit, then shipping Help, Workshop, Creator, text and file operations. The parent targets remain under 60 seconds to Controls test view for a mapped Xbox/DualSense and within three minutes for first calibration when requested; record time to flight separately without inventing a target.

Exercise axes/directions/ranges, diagonal movement, idle drift for 30 seconds, simultaneous buttons, independent offered triggers, held Accept/Back/throttle, controller order and a second controller arriving. Include focus/overlay repetitions and dock/display changes. Use risk-based pairwise combinations for additional faults after these mandatory cases; pairwise coverage does not waive the core journey or cycle counts.

Follow 1080p-first desktop qualification, then higher/docked resolutions, plus each handheld's real native panel and UI scale. Record output/drawable/render size where relevant. A docked 1080p pass does not prove Deck 1280×800 readability. Test the shipping export, not only source/editor execution.

## Timing and evidence requirements

Measure only after correctness. Keep these results separate:

| Measurement | What it establishes / does not establish |
| --- | --- |
| F6 synthetic processing cost | Cost of a named software seam; excludes hardware transport and display. |
| F1 Godot callback times | Event arrival after engine mapping; not USB polling frequency or physical latency. |
| F6a filmed raw-axis marker | Physical crossing to the fixed-wing RcInput marker, when that exact connected/sample path is active; not automatically another provider, conditioned command, servo or aircraft response. |
| Conditioned command/replay comparison | Fixed-tick adapter semantics for the supplied input; cannot validate the physical mapping that produced it. |

Retain at least **30 valid filmed transitions per qualified primary transport within each claimed timing-changing OS/provider route**, at fixed settings. The existing marker reads `session.radio.axes`; a pure native Steam endpoint without that RcInput peer is outside its demonstrated scope. Qualify a named observation point in the path actually consumed by flight, or another appropriate method, before claiming that route's latency; otherwise leave it pending. The same USB/Bluetooth transport does not make two providers equivalent. This is a future measurement requirement, not a requirement to build a new tool for the research delivery.

Report median, nearest-rank p95, count, rejected trials and measurement uncertainty. At 240 camera fps, the frame interval alone is about 4.17 ms; include other timing uncertainty. Compare the same host/build setup with a baseline using the parent budget: no added render-frame queue or reproducible increase beyond uncertainty. Do not manufacture an absolute latency target from a polling rate.

Record actual render/physics cadence at approximately 15/20/30/60/120 fps where attainable, VSync/display cap and activity-entry history. The 12-step cap at 240 Hz mathematically limits sustained 15-render-fps execution to 180 physics ticks per wall second; label slow simulation separately. Test brief presses across sampling phases, held presses, accumulation setting restoration and generated/delivered/sampled/dispatched counts. Preserve one shaping/rate owner and never queue arm commands to conceal missed polling edges.

The qualification record retains exact game/engine/native binary, OS/kernel, device/firmware/OEM mode, Steam/Proton/client, transport, profile/layout revisions, display settings, clock domains, event counts, omissions and observed outcomes. Keep identifying raw records controlled; a separately previewed shareable report uses its own allowlist and bounds. Reproducible failures remain visible rather than averaged into a pass.

## Release decision

Close D6-HH-00 as research only. Close implementation steps with their focused software/export evidence, and close a physical configuration only after its campaign passes. A missing bridge, partner setup, device, working portal or locale provider is an explicit pending/blocked dependency. No Steam/Xbox compatibility badge follows from this checklist. Roll back optional application state deliberately; Steam custom-layout rollback is tested separately from executable/profile rollback.
