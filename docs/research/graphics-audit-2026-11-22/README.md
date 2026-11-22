# Graphics and FPS audit — current-main follow-up, 22 November 2026

## Implementation follow-up from `dc59add8e`

These entries retain their recorded component evidence. The [sixth pass](sixth-pass.md#remote-repairs-and-integration-boundary) distinguishes the later presentation refactor and I01 source-pin mismatch from the earlier replay receipt.

| Finding | Change and verification |
| --- | --- |
| [T04](vehicles-and-aircraft.md#t04-fixed-wing-flap-animation-reads-a-full-advisory-state) | Flap animation reads the accepted actuator angle directly. Across 18 headless cases using Avanti, P-51 and Extra data, angles matched the previous render input byte for byte and the full advisory dictionaries remained equal. For a valid actuator on the two equipped aircraft, one air-data call and two density calls fell to zero per visual read. |
| [T08](menus-and-transitions.md#t08-settings-builds-its-complete-theme-twice-in-a-row) | Settings keeps the theme created by its screen surface. Across four headless combinations of scale, compact layout and opacity, construction went from two theme builds to one. A live opacity or scale change still rebuilt once. All 317 compared theme entries and 196 control records matched at construction and after each preview. |
| [M01](measurement-integrity.md#m01-initially-unfocused-wayland-can-receive-the-seatless-focus-override) | Rendered tours require observed focus before selection. An explicit seatless Wayland diagnostic and older synthetic-focus receipts are ineligible for comparison. The driver regression injects immediate focus, delayed focus and timeout. Physical desktop focus remains unverified. |
| [M02](measurement-integrity.md#m02-focus-wait-frames-receive-the-next-phases-index) | A separate setup phase owns focus-wait callbacks. The reducer withholds phase metrics when the recorded and streamed counts disagree. Regression packets cover a wait-side stall, a chunk boundary and an interval crossing into selection. |
| [U02](rig-sampler-experiment.md) | The Nitro adapter reads its packed float32 interpolation result directly when building the transform. With the actual parent and candidate code, all 38,874 track/input pairs matched byte for byte on macOS, including the retained audit digest. The two scene builds also matched mesh transforms and visibility in all 173 RCV-37 poses. Shared axis preparation and rendered FPS measurement remain open. |
| [U03](fourth-pass-ground.md#u03-nitro-service-status-repeatedly-reconstructs-its-full-state-each-frame) | The Nitro service check takes one state snapshot per eligible call. On Godot 4.8 beta2 (macOS arm64), the moving case went from six snapshots to one and the stationary case from ten to one. Electric and unprepared sessions took zero in both builds. The service regression covers speed and wheel thresholds, refuelling, restore and byte-exact replay. |
| [U12](fourth-pass-rendering.md#u12-live-show-effects-re-invert-the-same-world-transform-for-each-particle-or-segment) | Each spark or trail pool computes the inverse when its first visible item needs it. In a headless macOS arm64 comparison against `738717037`, 32 sparks or 63 trail segments each required one inverse. Faded, expired and missing-root cases required zero. Transforms, colors, visual bounds and both culling bounds matched byte for byte across 12 comparisons, including moving cameras and nonuniform root scales. Rendered FPS remains unmeasured. |

## Audit record

**Latest: [sixth pass, native boundaries and old-hardware cost models](sixth-pass.md).** The latest-main source review pins `85a2475f60029a4b6b09f23f643119bceea84a45`, including fixed render scale and newer UHD 630 evidence. Publication preserves the concurrently updated audit branch through `ee46d96b`; its runtime is not combined with main without a fresh companion rebind. The latest presentation refactor also exposes a pinned source-identity mismatch, recorded as I01. This pass traces two RC shader experiments, residual star-buffer construction, and a quantified continuation of F17 spatial-weather statistics. The reproducible paused-view pixel model withholds the 67% observation and explicitly excludes track cost. Independent reviews preserve derivative, normal, validity, callback and lifetime contracts; smaller native/Off-path ideas remain a watchlist. No production optimization or new measured FPS gain is claimed.

**Fifth-pass record: [previous uncovered paths](fifth-pass.md).** At main `0f859b5f358f4807877ec8bd7fe8009bc3856d3f`, nine conditional investigations covered paint loading/residency/LOD, input dispatch, quad sampling, throttle decoding, propagation search, mechanical audio and first-rain warm-up. Its asset counts and measurements retain that source identity.

**Fourth-pass record: [deeper vehicle/rendering investigation](fourth-pass.md).** Thirteen further traced items cover cars, drones, helicopters, retractable aircraft, Home and lighting. A source-bound Nitro sampler experiment has byte-identical tested outputs and a 19.6–27.7% median paired component-time reduction across six process/workload summaries; this is not FPS or production visual qualification. The audited simulator-source CI completed successfully; latest main `c20a074de` adds only release/download website content and has a separate in-progress CI run. The branch integrates that latest main. Detailed traces, retained raw timings and native/platform follow-ups are linked there.

## Third-pass snapshot

**The audit branch now includes current main `7940a4081e10994f34c858c4acac3d7a1a271464`.** This pass reviewed the new performance tours, stutter map, measurement-hardening tests, automatic-graphics repairs, release qualification and GitHub CI, then traced additional drone, car, aircraft and menu costs.

The result is **11 additional source-confirmed optimization opportunities and two measurement-integrity findings**. The lead reproduced the phase-attribution defect with the existing reducer. No FPS gain is claimed: the source paths are confirmed, their current end-to-end benefit is unmeasured, and no production optimization or graphics-setting change is implemented here.

The earlier [audit](../graphics-audit-2026-11-21/README.md) and [second pass](../graphics-audit-2026-11-21/second-pass.md) remain historical records. Their published branch head was `2c03b78720c20453d26ca78bc3022dbdd905f00a`; the previous main cross-check was `6b2228c7633a34e38cb05d92e3ca50893810e02b`. This report updates the conclusions using the newer source and evidence, preserving prior records rather than silently rewriting their receipts. `T01–T11` and `M01–M02` are local audit labels, not new implementation-track IDs.

## Reports

| Report | Contents |
| --- | --- |
| [Fourth pass and numeric experiment](fourth-pass.md) | U01–U13, deeper source traces, byte parity and component timing, completed CI and platform gates |
| [Current main and new tests](current-main-and-tests.md) | Source refresh, rendered evidence, CI, repaired/open finding ledger, missing vehicle coverage |
| [Vehicles and aircraft](vehicles-and-aircraft.md) | Quad telemetry, car surface queries, flap state, wet pools, obstacle indices, signals, fly-by and guarded heli/airship paths |
| [Menus and transitions](menus-and-transitions.md) | Controls construction, Settings theme/polling, profile storage and correct transition boundaries |
| [Measurement integrity](measurement-integrity.md) | Wayland focus eligibility, phase-attribution source trace, six synthetic witness cases and limits |
| [Priorities and validation](priorities-and-validation.md) | Cost models, native implementation choices, platform matrix and discriminating experiments |
| [CI evidence](main-refresh-evidence.json) / [offline witness evidence](phase-focus-evidence.json) | Source-bound, machine-readable observations |
| [Reproducer](../../../research/performance/graphics-audit-2026-11-22/README.md) | Repeatable offline witness against the unmodified current reducer |

## Strongest new opportunities

| ID | Confirmed current work | Smallest useful candidate | Scope / limiting condition |
| --- | --- | --- | --- |
| T01 | Electric quad telemetry evaluates forces, contacts, all rotor loads and derivatives to read two bus values | Shared exact bus-input/solve helper and accepted-frame bus-only projection | Existing tick cache; GDScript plant with ordinary or scripted pilots; race/invalid bus/fingerprint contracts |
| T02 | Car presentation normally performs center + four wheel full road queries, including physics wall fields | Exact presentation surface projection | Effects/input/pause guards; distinct positions; observable diagnostics and course identity |
| T03 | Controls builds all five pages; the hidden action page has 111 Buttons with effects created during construction and initialized on attachment | Scope/defer hidden-page setup only after stage attribution | Later decoration is idempotent; measure first-page-use cost and preserve all input/draft behavior |
| T04 | Flap animation calls the full airspeed/density advisory getter for the accepted angle | Validated angle-only projection | Avanti, Corsair and other equipped aircraft; keep full status for actual consumers |
| T05 | Dry car wet-effects paths still iterate water/mud slots and hidden rings | Zero-activity fast path with transition cleanup | Existing off/pause guards, accepted wet state, audio and residual-effect behavior |
| T06 | Quad entry/rebind independently builds three same-world spatial indices | One immutable prepared index shared by three query adapters | Nonempty scenery; preserve ordering and world isolation |
| T07 | Accepted car tick signal builds a detached full telemetry payload ignored by the normal activity subscriber | Optional lightweight activity notification, retaining full public observer payload | Profile first; subscription and mutation ownership are public contracts |
| T08 | Settings builds its complete Theme twice during construction | Remove the redundant assignment after equivalence checks | Native resources and icon cache already exist; likely smaller component |
| T09 | Controls eligibility can repeatedly load/validate/lease the same profile store | One bounded validated refresh snapshot or reuse within one eligibility decision | Connected-device branches; preserve authority, locking, serial identity and external changes |
| T10 | Hidden Settings Graphics status normally rebuilds a broad report and reads configuration | Visible-page summary with immediate refresh and separate safety checks | Never suspend display-trial timeout or fallback detection |
| T11 | Fly-by placement repeats the final identical obstacle query | Reuse the final result for the proven pure adapter | Placement only; Pilot default does not use it; small historical costs |

The findings describe unwanted or potentially avoidable work. They do not imply that each path is a frame bottleneck. The [cost models](priorities-and-validation.md) quantify call counts and possible bounds without inventing timings.

## What the new measurements change

The [retained stutter map](../god-test/2026-11-21-stutter-map.md) provides actual rendered, native-aircraft-physics observations with sound muted. Its source snapshots differ from this main, so it prioritizes investigation rather than attesting current-source performance.

| Retained host | Useful observation | Qualification limit |
| --- | --- | --- |
| Windows RTX 3090 / 1080p | Flight means 174–185 callback FPS; loading worst intervals about 1.0–1.1 s; Controls phases about 0.64–0.76 s | Single passes; broad phase intervals; no presented-frame causal attribution |
| M1 / mirrored external 1080p | Flight means 74–97; Home 42–51; loading worst intervals about 2.65–2.85 s; Controls about 0.42–0.46 s | Not the native Retina panel gate; thermal state unrecorded; different source/workload and device-wide utilization |
| Linux UHD 630 / shared LXC / Medium | About 9–13 callback FPS and 0.43–0.63 simulation pace; loading about 35.7–44.5 s | Headless Weston compositor, incomplete drawable evidence, two circuit timeouts, one forced shutdown; Automatic would select Low |

The Windows and M1 Settings phases show roughly 0.28–0.32 s worst intervals. These phase ranges include Pause/open/dwell/close/resume as applicable; they do not diagnose the named screen constructor. The 2.798 s first Windows `selection` interval covers Home configuration and is additionally subject to raw focus-wait attribution review.

The Linux pace ratios are consistent with the existing 240 Hz / 12-step catch-up ceiling at that cadence. They do not establish which CPU/GPU/compositor cost caused the slowdown. The quad and both cars still need their own matched rendered baselines; a three-aircraft result cannot fill that gap.

## Evidence corrections and current CI

The VQ-07h work repairs incomplete calibration persistence and the recorded test-owned Node leak; its focused 109 calibration checks belong to the recorded repair snapshot. The 204-test hardening receipt likewise belongs to its recorded source. They should not be described as fresh test counts on `7940a408`.

At the independently fetched **2026-11-22 14:32:10 UTC** snapshot, exact-main Windows queue CI succeeded: GOD TEST ran **210 tests, 7 skipped**. The old missing-`psutil` failure is no longer a current blocker. CI for the previously reviewed `6b2228c` later completed successfully. Current-main core CI had successful unit/native/build lanes, while visual captures and integration 0 were still running; full success was not established by that observation. The [evidence report](current-main-and-tests.md) and JSON retain the exact identities and limits.

Calibration workload mixing, provider identity and the stale High-veto scope remain open in source and the owning automatic-graphics plan. New complete-record guards do not repair those separate issues.

## Reproduced measurement issue

During a focus wait with no active phase, the driver labels frames with the next phase's index. The reducer groups those frames into selection without reconciling declared phase boundaries.

- A synthetic 400 ms wait-side stall appears as a selection maximum, although every actual selection interval is 10 ms.
- In a second synthetic stream, smooth waiting changes selection's reported p95 from 40 ms to 10 ms and its mean from 25 to about 91.18 interval-derived FPS.

These are deterministic offline counterexamples, not simulator benchmark results. A separate receipt check shows that initial-focus/Wayland override fields do not reject a packet, while a later-loss counter still does. The [full report](measurement-integrity.md) distinguishes the source-proven pathway, the synthetic classifier behavior and the unperformed physical-host validation.

## Review and scope

The work followed the repository's `AGENTS.md`, `docs/SUBAGENTS.md`, applicable source guidance and `openrc-tools` routing. Three bounded source reviewers covered vehicle paths, menus, and evidence/CI; cross-review challenged the strongest findings. Helpers were requested with the guide's research profile (`gpt-6.1-terra`, maximum reasoning); effective runtime settings beyond that request were not independently observed. The lead owned integration, independent CI reads, primary-source research and the offline reproduction. No helper launched an engine or shared-host job.

Review corrections included the true Controls effect-creation stage, conditional Settings polling, bounded track-wall scans, the car's always-installed default circuit, native lake/Nitro distinctions, race telemetry command semantics and source-fingerprint implications. Guarded helicopter magnifier, airship telemetry/light paths, event-driven UI effects and existing caches are recorded as counterevidence.

The branch contains reports and the offline witness, plus integration of the requested main update. Future implementation should start with measured component attribution and the smallest native/engine change that preserves physics, ownership, visibility, replay and failure contracts. The concrete platform work required for FPS qualification is in [priorities and validation](priorities-and-validation.md).
