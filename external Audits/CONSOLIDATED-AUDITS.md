# External audits — consolidated review

Consolidated on **2026-11-06**, including the developer remediation, Apple Silicon/Metal handoffs, Extra 300 (both rounds), Corsair (both rounds) and UI/UX accessibility audits (both rounds). **Read this document first.** It organizes thirteen distinct source reports, merges overlapping recommendations, and preserves the distinction between reported defects, experimental optimizations, and model limitations. The thirteen source reports retain their original content under descriptive filenames in this directory; four byte-identical copies of A1 were removed.

This is a synthesis of the supplied reports, not a new audit of the current working tree. Technical results below are attributed to their original source snapshots. No fix, performance gain, physical validation, or completed project gate is established by this consolidation. Current implementation status belongs to the [documentation map and owning tracks](../docs/README.md).

## Contents

1. [Sources, duplicates, and chronology](#1-sources-duplicates-and-chronology)
2. [Main conclusions](#2-main-conclusions)
3. [Correctness and measurement findings](#3-correctness-and-measurement-findings)
4. [Physics findings and model limitations](#4-physics-findings-and-model-limitations)
5. [Mathematical optimization register](#5-mathematical-optimization-register)
6. [Reported performance and kernel experiment](#6-reported-performance-and-kernel-experiment)
7. [Follow-up order and acceptance evidence](#7-follow-up-order-and-acceptance-evidence)
8. [Tools and platform constraints](#8-tools-and-platform-constraints)
9. [Evidence availability and original-file fingerprints](#9-evidence-availability-and-original-file-fingerprints)

## 1. Sources, duplicates, and chronology

The labels A1–A13 identify source documents in this consolidation; they are not implementation step IDs.

| Source | Original document | Scope and source identity |
| --- | --- | --- |
| A1 | [Apple Silicon audit — apple-silicon-performance-audit-2026-11-05.md][A1] | Audit associated with 2026-11-05; latest reviewed commit `fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab`. Source research and synthetic benchmark-reducer checks; Mac timings quoted from existing repository campaigns. No new native Mac benchmark. |
| A2 | [Mathematical Optimization Lab][A2] | Frozen commit `3df2791752fe2c1faad132fcb11febbb0ae788d1`, timestamp **2026-11-06 01:23:16 UTC**. Twelve portable numerical probes; Linux x86-64, CPython 3.12.14, NumPy 2.3.5, SciPy 1.17.0. No Godot execution or target-GPU measurement. |
| A3 | [Stage-validation reuse — stage-validation-reuse-experiment.md][A3] | Experimental single-file kernel patch against `3df2791752fe2c1faad132fcb11febbb0ae788d1`. Godot `4.8.beta2.official.cafc17a19`, Linux x86-64, Intel Xeon Platinum 8573C, reference GDScript backend, 240 Hz. No date stated in the report. |
| A4 | [Propulsion and energy audit — propulsion-energy-audit-2026-11-06.md][A4] | Dated 2026-11-06, reviewed commit `3df2791752fe2c1faad132fcb11febbb0ae788d1`; same official Godot beta2 on Linux x86-64, isolated minimal 240 Hz project. |
| A5 | [Fixed-wing aerodynamics review — fixed-wing-aerodynamics-review.md][A5] | Reviewed commit `3df2791752fe2c1faad132fcb11febbb0ae788d1`; Godot beta2, float64 state, isolated sparse app copy and user profile. No date stated in the report. |
| A6 | [Developer audit and remediation handoff — developer-audit-remediation-2026-11-06.md][A6] | Dated 2026-11-06; consolidates two audit passes at `3df2791752fe2c1faad132fcb11febbb0ae788d1`. Linux headless/debug Godot `4.8.beta2.official.cafc17a19`, GDScript reference backend, normally 240 Hz. Six reported defects F1–F6 and six optimization opportunities O1–O6; no production fixes or native execution. |
| A7 | [Apple Silicon and Metal Optimization Handoff][A7] | Dated 2026-11-06, America/Bogota. Combines historical `fc018b38` audit, shader/architecture experiments at `93ffbb101917dff86ecc2632f07e2e45c450a178`, and separate CPU/physics results at `3df2791`. Pinned Godot beta2, Linux x86-64, Python 3.12.14/NumPy 2.3.5; CPU screens, shader-language checks and headless camera-method checks, but no new native Metal GPU execution. Not the same mathematical lab as A2. |
| A8 | [Extra 300 physics and optimization audit][A8] | Attached report dated 2026-11-06, reviewed `codex/m1-native-validation-20261106` at `e72d878b6b4a89209dfe1a992ba119921dcdd34c`. Two Extra-specific physics consistency defects, three optimization opportunities and one visual defect. Pinned Linux Godot/headless probes; 13 reported successful checked receipts; no new production fixes, complete suite, native qualification, rendered flight or full replay campaign. |
| A9 | [F4U Corsair physics and optimization audit][A9] | Experiments at `84f4657814c157f1556f965861c0ab8623f48d8e` on `codex/m1-native-validation-20261106`; report also checks subsequent `e72d878` and says it does not alter the responsible files. No report date stated; received 2026-11-06. One material rate-datum inconsistency, one smaller thrust-lookup defect, two optimization opportunities and two unpromoted candidates. Reported isolated diagnostics, not full flight/native/render qualification. |
| A10 | [Extra 300 round-two trim and reload audit][A10] | Reviewed `8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd`; package dated 2026-11-06. Adds E300-07 trim-result RPM reuse and E300-08 stale propeller geometry after F5, excluding first-pass E300-01–06 and already-covered downwash reuse. Pinned Linux solver comparisons and actual headless app/debug-bridge F5 events; no full-startup, target-GPU or native performance qualification. |
| A11 | [UI/UX, configuration integrity and accessibility audit][A11] | Dated 2026-11-06; reviewed `codex/m1-native-validation-20261106` at `e72d878b6b4a89209dfe1a992ba119921dcdd34c`, Godot `4.8.beta2.official.cafc17a19`. Nine new findings F01–F09 and one reproduced case R01 in an existing design concern. Actual headless application, production-component and source evidence are separated; no fresh native visual, physical-controller, screen-reader or renderer qualification. |
| A12 | [Corsair collision, flap geometry and presentation handoff][A12] | Dated 2026-11-06; experiments at `3751e35e1cccf574c4446d21273a4d5ecaf80ddf`. Closing source comparison at `842339369a58e7320177a6caecf22a7dc012ec0f` found responsible files unchanged; that later revision was not the executed baseline. Adds CF-05–07, excluding A9 CF-01–04 after checking the A1–A11 ledger. Two correctness counterexamples and one measured presentation-component opportunity; no production modification or full-scene/native qualification. |
| A13 | [Incremental UI/UX exit, settings and feedback audit][A13] | Dated 2026-11-06; reviewed `3751e35e1cccf574c4446d21273a4d5ecaf80ddf` with pinned Godot 4.8 beta 2. Eight additional findings UI2-01–08 and unmeasured loading candidate OBS-01. Seven component witnesses plus separate headless Settings/Conditions and navigation checks; native visuals, physical devices, audio, screen readers and target loading cadence unverified. Reconciles two historical ledger versions and the prior dedicated UI review; does not claim to have reviewed this later A1–A12 ledger. |

### Source names and duplicate removal

The folder contains this consolidated document and thirteen source reports. Source contents are unchanged; only filenames were improved. The four numbered copies `Pasted markdown (1).md` through `Pasted markdown (4).md` were deleted after confirming their SHA-256 matched the retained Apple Silicon report. They contained no independent evidence.

| Original filename | Retained filename |
| --- | --- |
| `Pasted markdown.md` | [apple-silicon-performance-audit-2026-11-05.md][A1] |
| `OpenRC_Mathematical_Optimization_Lab.md` | [mathematical-optimization-lab.md][A2] |
| `FINDINGS.md` | [stage-validation-reuse-experiment.md][A3] |
| `FINDINGS2.md` | [propulsion-energy-audit-2026-11-06.md][A4] |
| `FINDINGS3.md` | [fixed-wing-aerodynamics-review.md][A5] |
| `NEWONE.MD` | [developer-audit-remediation-2026-11-06.md][A6] |
| `NEW.MD` | [apple-silicon-metal-optimization-handoff-2026-11-06.md][A7] |
| Attached `Pasted text.txt` (Extra 300 audit) | [extra-300-physics-optimization-audit-2026-11-06.md][A8] |
| Attached `Pasted text.txt` (Corsair audit) | [f4u-corsair-physics-optimization-audit-84f4657.md][A9] |
| Attached `Pasted text.txt` (Extra 300 round two) | [extra-300-round2-trim-reload-audit-8e5f2f0.md][A10] |
| Attached `Pasted text.txt` (UI/UX audit) | [ui-ux-accessibility-audit-2026-11-06.md][A11] |
| Attached `Pasted text.txt` (Corsair senior-developer handoff) | [f4u-corsair-collision-flaps-presentation-audit-3751e35.md][A12] |
| Attached `Pasted text.txt` (incremental UI/UX audit) | [ui-ux-round2-exit-settings-feedback-audit-3751e35.md][A13] |
| `README.md` (consolidation) | `CONSOLIDATED-AUDITS.md` |

### Differences between snapshots

| Topic | A1 snapshot | Later A2 snapshot | How to read the difference |
| --- | --- | --- | --- |
| Missing UID sidecars | Reports failed release preflight at `fc018b38` because five sidecars are missing. | Says the missing sidecars have been added. | Keep the failure as historical evidence. Do not carry it forward as a confirmed current failure or infer that all CI is now green. |
| Reconstruction default | Native is the default; Spatial is available; Temporal is a separate trial. | Auto is the default, selecting supported MetalFX modes while retaining at least 1,000 internal rows, otherwise Native. A2 says Auto selects Native at 1080p. | Defaults changed. Record effective mode and dimensions in every new comparison rather than relying on either historical default. |
| Earlier report identity | A1 explicitly names `fc018b38` as its latest audited revision. | A2 §1.2 calls an earlier guide frozen at `93ffbb101917dff86ecc2632f07e2e45c450a178`. | These are different source references. The supplied files do not establish that A2's earlier guide is exactly A1. |
| Cloud-cache evidence | Earlier C2 timing describes an RGBA8 ground/near-grass tile; enabled implementation uses RG16F and C5b sky relief. | A2 screens additional mathematical candidates, often using analytic low octaves as a proxy for the filtered cache. | Neither earlier C2 timing nor portable A2 screens qualifies the exact current cache and shader combination. |

## 2. Main conclusions

| Topic | Consolidated conclusion | Evidence class |
| --- | --- | --- |
| Corsair continuous collision, flap transfer and presentation | A12 adds missed interior raised-track contacts (CF-05), an omitted local-flow projection in flap lift-reference transfer (CF-06), and discarded overspeed-advisory work in render flap reads (CF-07). | Accepted-tick counterexamples, production-load cross-product oracle and isolated presentation timing/parity, respectively. Separate from A9 CF-01–04; no occurrence-rate, physical-fidelity or FPS claim. |
| Incremental UI exit and settings reliability | A13 prioritizes a garage recording failure that does not block root quit, premature Workshop recovery deletion, transient save errors and overbroad display-test rollback. Adds field-specific validation, hint/audio/localization consistency and a briefing-preparation candidate. | UI2-01–08 are separate report IDs; OBS-01 is unmeasured. Final quit was intercepted, Workshop canceled-exit consequence is inferred, and native behavior is not qualified. |
| UI choices, focus and save outcomes | A11 prioritizes profile identity, session/default isolation, scoped weather presets and usable focus after successful controller recovery; also covers Help, editing-key conflicts, save feedback and accessibility. | Nine new findings plus one reproduction of an existing concern. Evidence ranges from actual headless app routes to source inspection; these are historical findings, not current-fix verification. |
| Extra 300 trim finalization and F5 reload | A10 reports two redundant steady-RPM searches per bounded glow trim finalization (E300-07), and physical/visible propeller diameter divergence after accepted same-ID reload (E300-08). | Tested solver candidate with byte-identical results; actual headless F5-route state/transform witnesses. Separate from E300-03 stage-mass reuse and E300-06 blade handedness. No new aerodynamic calibration is justified by these findings. |
| Corsair force/moment and thrust continuity | A9 reports CF-01 rate moments supplied about CG where ARP is required, and CF-02 a final-table thrust discontinuity from the extrapolation floor. | Scoped generator/runtime and accepted-tick witnesses. CF-01 is a Corsair recurrence related to earlier Stik datum work and A8's Extra finding, not another count of those same aircraft defects. |
| Corsair work elimination | A9 isolates repeated retract-data validation within one build (CF-03) and repeated full-vector calculations in the offline VLM generator (CF-04). | Synthetic construction-component timing and byte-identical generated output, respectively; no measured aircraft-loading/FPS gain. Stationary-pose cache was slower; gasoline-result reuse had inconclusive timings. |
| Extra 300 generator consistency | A8 reports E300-01 mixed CG/ARP moment conventions and E300-02 missing installed blade camber in generated crossflow tables; it recommends resolving both before retuning. | Production-code diagnostic witnesses at `e72d878`, not physical calibration or current-fix verification. These are distinct from A5's earlier documented force-arm conventions. |
| Extra 300 performance and presentation | A8 adds stage-local mass reuse, a mesh-memory tradeoff, custom-paint shader sharing, and reversed visual blade handedness. | Sampled parity, headless buffer/resource measurements and geometric direction checks; no whole-app speedup or rendered-flight qualification. |
| Additional shader and renderer experiments | A7 prioritizes a small zero-contribution sky patch, bounded density evaluation and a high-octave hash lattice; it also develops polynomial, integer/angular/ground, crop-camera and rate-map proposals. | Portable numerical, front-end and camera-method evidence; no new GPU speedup for these candidates. A7's historical working-cache profile is separately scoped below. |
| Admission, commands, and truck energy | A6 prioritizes F1 Workshop first-tick rejection after qualification, F2 changed flap/gear targets after pause, and F6 positive tire/brake work. | Scoped production-code/session counterexamples; priorities are the external report's recommendations, not current project labels. |
| Observer, fuel trial, and recording contracts | A6 reports F3 track-support disagreement, F4 an ineffective sub-ULP fuel sentinel, and F5 empty-block log rejection. | Geometric/numerical/serialization counterexamples with explicit limits. F4 is distinct from A4's lost firing counter. |
| Downwash pre-step optimization | A6 O4 reports about 42% less callback cost in its spatial-weather workload, with sampled exact outputs and refusal controls. | Headless component experiment, not 42% whole-tick or FPS improvement; separate from A3 and A2 M09/M10. |
| Glow firing counters | A4 reports a pre-exhaustion crank firing lost when a tick ends with fuel starvation. It is a counter/lifecycle defect at the reviewed snapshot. | Production-session witness plus discriminating controls; current repair status not checked. |
| Benchmark integrity | A1 demonstrates that synthetic receipts can pass despite Native fallback or GPU-profiler instrumentation, and identifies incomplete rendering identity. | Reproduced reducer behavior and source inspection at A1's snapshot. |
| Rendering lifecycle | A1 identifies conditional cloud-bake, renderer-recovery, and custom-shoreline risks. | Source-derived risks; not reproduced Mac/display failures. |
| Apple performance | Recorded campaigns point first to ground/cloud GPU work and then sustained presentation at actual 1080p. | Historical measurements; no latest-default sustained 1080p/60 qualification established by these reports. |
| Mathematical work reduction | A2 prioritizes M01 corner reuse, M02 solar chord geometry, and cheap M03 relief scheduling; M09/M10 merit evaluation where physics cost is measurable. | Proposed implementations and portable mathematical screens, not measured device speedups. |
| Kernel validation reuse | A3 reports exact comparisons and measurable component savings; full-session changes are small/noisy. | Experimental patch, limited software verification and headless timings. |
| Fixed-wing aerodynamics | A5 establishes no new serious production defect. Two candidates are documented conventions; one selector asymmetry remains unresolved and low-impact in its witness. | Model/source review and diagnostic probes, not physical validation. |

Throughout this document, **reported confirmed** means demonstrated within the original report's scope, **conditional risk** means a source-derived failure condition, **candidate** means unpromoted work, and **documented limitation** means an acknowledged model assumption. Mathematical proof in real arithmetic, sampled floating-point agreement, source operation counts, and target-device measurements are separate evidence classes.

A6 arrived later in this folder but reviews the **same commit as A2–A5**, not a newer implementation. Its six-defect count belongs to its two-pass handoff, not to the entire consolidated collection. A4's firing-counter defect remains separate; A6 F4 supplies the fuel-boundary-rounding finding that A4 explicitly excluded. A6's ground-effect discussion overlaps A5 and is retained once as a documented convention. Neither A6's inconclusive validation microbenchmarks nor A3's positive component results supersedes the other: they describe different experiments.

### A7 overlap and evidence reconciliation

- **Revision and archive identity:** A7's shader mathematical lab is frozen at `93ffbb`, whereas A2 explicitly freezes its separate lab at `3df2791`. Their similarly named ZIPs, polynomial constructions, sample sets and bounds must not be merged into one experiment. The relevant artifacts are distinguished in §9.
- **Historical defects:** A7 repeats A1's UID, effective-render, profiler, identity, cache readiness, recovery and shoreline findings. These remain the existing entries in §3, not new defects. A2 reports added UIDs; A7's instruction to recheck historical CI does not reopen them as proven current failures.
- **Corrected C5 diagnosis:** A7 attributes the old black-output C5 failure to Mobile/Metal sky sampling of a ViewportTexture and reports a stable ImageTexture fix. It explicitly supersedes an earlier interpolation-based explanation. This does not erase the separately measured errors of its later post-threshold relief bundle.
- **Later CPU findings:** A7 §18 repeats A6 F6, O4, O5 and bounded rotor/runout/replay controls at `3df2791`. Keep their detailed evidence and limits in §§3, 4 and 6; do not add another defect count or pool repeated timings.
- **Related mathematics:** A7's remaining-noise density bounds differ from A2 M03's relief-contribution budget. Its high-octave hash lattice differs from A2 M01's coarse-corner sharing. Solar LUT versus A2 M02 chord geometry are separate alternatives. A7 parcel/derivative screens overlap A2 M12/M05 conceptually but use distinct controls and result sets.

## 3. Correctness and measurement findings

### Incremental UI/UX: exit, settings and feedback

**Source: [A13][A13], reviewed `3751e35`.** UI2-01–08 and OBS-01 are this report's identifiers, not project tracker steps. P1 protects recoverable work; P2 addresses unreliable workflows; P3 covers consistency/discoverability/feedback. A13 first read an earlier consolidation, then reconciled the frozen revision's A1–A9 ledger, the 62-item UI-30 audit, later investigations/plans and the previous dedicated UI review. Its two ledger versions are historical provenance, not evidence that the current consolidation has fewer sources.

| Finding | Reported behavior and evidence boundary | Recommended repair and acceptance |
| --- | --- | --- |
| **UI2-01 — P1, garage recording does not veto quit** | Production GroundScene and AppRoot window-close handlers tested together with synthetic active recording/injected export failure: recording stops once, export fails once, pending data remains and garage reopens, yet root reaches final quit. Root enumerates `flight` and `_workshop_previous_flight`, excluding `ground_vehicle`. Ground-only control blocks exit. **Final quit was intercepted**: unsafe exit path proved, no observed loss of a real recording. | One root coordinator must include ground recording in save/retry/stay/explicit-discard decisions. A failed participant prevents quit until resolved. Test active/pending recordings, repeated close, retry success, Stay and Discard and quit. Distinct from UI-30's garage Return-to-Home guard; trigger is competing window-close ownership. |
| **UI2-02 — P2, countdown erases failed-save feedback** | Component and current headless app: non-writable display store makes `keep_changes()` show error 10; next `_process()` replaces it with the 15-second display-test countdown although draft remains unsaved. Existing deadline/saved-value checks do not establish error persistence. | Separate persistent save outcome from countdown activity. Preserve safety deadline; error survives frames/ticks until success or resolution. Check immediate failure, next frame, multiple ticks, retry success and expiry, explaining restored display and remaining unsaved work. Distinct from A11 F06's language-save error sent only to Home. |
| **UI2-03 — P2, display expiry discards unrelated drafts** | Component/actual Settings controls: volume `0.4`, opaque panels `true`, then Borderless test; after 15 seconds, mode returns to `windowed` but volume becomes `1.0` and opacity `false`, whole draft equaling saved. Expiry calls general `_revert()`. Saved preferences were not corrupted; headless evidence does not qualify native window behavior. | Separate saved state, current draft and known-good display baseline. For trial keys T, restore only `D'[k]=B[k]` when k is in T; otherwise retain `D[k]`. Reapply combined draft and recompute dirty state. Preserve explicit Revert all. Test edits before/during countdown, repeated display changes, failed Keep, expiry and deliberate full reversion. |
| **UI2-04 — P2, Conditions diagnoses visible tab** | Component/actual dialog: invalid wind-speed text, switch to Time of day, Apply; dialog reports invalid time/date/location instead, stays there and retains accepted wind `1.5 m/s`. `_on_apply()` validates across tabs while `_show_error()` uses current tab. Invalid data is correctly refused. | Return owning tab, field ID, error code and localized explanation; reveal/scroll/focus the field after layout and preserve other edits. Proposed matrix covers each invalid-origin tab against Apply from all five tabs, empty/pasted/out-of-range values; only wind→Time of day was reproduced. Separate from UI-30 error-color work. |
| **UI2-05 — P2, Workshop recovery deleted before commit** | Dirty draft with completed recovery snapshot; direct call to `_navigation_finish()` (wired to Discard, **button not activated**) deletes snapshot/stops timer before next navigation stage. One second later dirty in-memory draft remains without snapshot. Root trace-failure→Stay can abort quit without rearming recovery by source inspection; **full sequence not executed**. Risk is later shutdown before another edit schedules recovery, not immediate draft erasure. | Separate permission to discard from global transition commitment. Delete only at commit; preserve/refresh live-draft recovery if another participant blocks/cancels. Existing aircraft-editor plan already requires delayed discard. Integration gate: dirty draft→snapshot→Quit→Discard→trace save failure→Stay retains draft and recovery. |
| **UI2-06 — P3, hidden keyboard hint expires** | Production hint component with synthetic session/shortened duration: controller-owned hidden time advances unpaused counter, emits `done`; later keyboard switch leaves hint invisible. Root completion persistence is source-inspected, not exercised, and no physical controller was used. | Count only visible, relevant, advancing exposure; retain time during pause/controller ownership/loss. Test controller-first→keyboard, switching, pause, loss/recovery, dismissal and preference reload after valid completion. Separate from broader first-run tutorial work; future per-input guidance may need per-family completion. |
| **UI2-07 — P3, hidden tabs miss focus cues** | Production Overlays temporarily uses `FOCUS_NONE` on inactive pages; MenuAudio observes once, conditionally subscribes to focus, and other subscriptions can mark controls observed. Modern control requests a cue; activated Classic control acquires focus without another request. Measured **cue requests with Dummy audio/synthetic navigation**, not audible output. | Subscribe eligible interactive controls to future focus independently of initial visibility; keep active-surface/visibility/deliberate-navigation gates at signal time. One cue per eligible deliberate move, none for silent autofocus, no duplicates after repeated switches. Keep policy in shared observer. |
| **UI2-08 — P3, radar cardinal localization** | Source inspection: Pilot radar hardcodes N/E/S/W while Weather compass uses existing translations (Spanish west O, German east O, Japanese glyphs), even on fresh creation in one locale. No rendered clipping or player navigation error demonstrated. | Reuse cardinal translation policy/strings, shared provider if needed; leave bearing/heading math unchanged and invalidate cached face on locale/font change. Compare English/Spanish/German/Japanese at initial/live locale changes, glyph fallback, centering and larger text. Distinct from stale-localization-on-change findings. |

A13 explicitly excludes prior profile overwrite, recovery focus, Help scrolling, remapped Back editing, Natural Random Moon leakage, startup scaling, hover-only help and existing Home-to-Fly loading work from the new count. Preserve A11's evidence and any separately recorded implementation updates; this report does not reset their disposition.

### UI/UX: configuration integrity, navigation and accessibility

**Source: [A11][A11], reviewed `e72d878`.** A11's F01–F09 and R01 are local audit labels, distinct from A6 F1–F6 and A2 R01–R02. P1 denotes configuration integrity or continuity of control before a wider polished release; P2 denotes material usability/accessibility failures; P3 denotes a bounded quality improvement. These are the author's priorities, not assigned project step IDs.

| Finding | Reported behavior and evidence | Proposed repair and acceptance boundary |
| --- | --- | --- |
| **A11 F01 — P1, New profile identity** | Production-component reproduction: selecting the `-1` New profile entry leaves the existing draft identity intact; saving a new name replaces that profile, leaving one entry with the original ID. Owners: `controller_setup.gd`, `controller_profile_store.gd`. | Make creation an explicit fresh-ID draft transition, or use a disabled placeholder plus Create action; distinguish Create, Duplicate and Update. Create/change/save/reload must retain both IDs and original mappings; cover Cancel, duplicate names and switching. Separate from existing unsaved-draft confirmation work. |
| **A11 F02 — P1, recovery loses Pause focus** | Production Pause/Screen/ScreenStack/input components reproduce both timing orders: successful recovery hides the action captured as return-focus target, before or after restoration. D-pad Down/Accept, keyboard Down and Tab do not reacquire focus. Earlier recovery coverage kept the device lost. | Active keyboard/gamepad menus need a visible enabled target. Restore a valid opener or explicit fallback, and repair later hide events without stealing newer valid focus. Test actual recovery with a separate menu pad and Keyboard/replacement flight controller, both timings; Resume may gain focus but must never activate automatically. |
| **A11 F03 — P1, Moon persistence scope** | Actual headless Natural Random → Pause → lighting → No moon → Apply writes normal `moon` from `real` to `off` despite `remember_lighting_selection=false`; reload retains `off`. Direct `--quick-flight` attempts to save a Moon-only preference dictionary and logs missing `language`; editor closes, flight stays paused, sentinel file remains unchanged. This is a script error, not a crash. Owners: AppRoot Moon/Apply paths and `Preferences.save_to()`. | Stage and validate Moon with all lighting fields under one route-aware persistence owner and save outcome. Check normal defaults survive Natural Random restart/end and direct-flight edits; direct flight must avoid normal preference access and errors. Moon being committed before later operations creates a source-level partial-transaction risk; a player-triggered failed-sky transaction was **not reproduced**. Rejected combined edits must remain atomic. |
| **A11 R01 — P1, wind preset overwrites air** | WeatherDialog reproduction: Steady breeze changes custom 1,500 m / 35 °C to reference 0 m / 15 °C as it installs 3 m/s wind. Whole-preset `_set_fields()` replaces the base and atmosphere controls. This is a new counterexample within a known requirement, not a tenth new finding. | Scope and merge only owned fields. Wind-only presets must preserve custom and standard-column atmosphere through Apply/reload; Cancel preserves the draft. Hot and high, Cool dense air and Standard dry ISA column intentionally own atmosphere: retain and disclose their composite effect. Removing atmosphere from every preset would be incorrect. |
| **A11 F04 — P2, gamepad Help scrolling** | Production-component checks at **1920×1080**: available scroll distance is 349 px at 100% text and 2,833 px at 200%; repeated selected-pad navigation leaves offset zero while keyboard End reaches bottom. The handler accepts only `InputEventKey`; the body has no focusable content to drive `follow_focus`. | Route selected/remapped-pad scrolling while the reading region is focused, or expose navigable controls. Retain device filtering against RC axes and direct Close/Back. Test every section in English/Spanish at both scales, repeat/limits/reopen/close, keyboard Home/End/Page keys and mouse wheel. Distinct from earlier Help organization and keyboard tests. |
| **A11 F05 — P2, Back captures editing keys** | Component host uses the verbatim production AppRoot router, real LineEdit and action validator: default Backspace edits `123` to `12`; accepted Back→Backspace mapping cancels the modal instead. Early `_input` consumes it before GUI editing. Actual Conditions supports editable fields/cancellation, but the full saved-profile-to-Conditions route was **not executed**. | Let editors consume ordinary editing keys before remaining shortcuts, or guard focused editors. Test actual saved Backspace and printable-key mappings, typing/deletion, Back after editing, modifiers, capture, popups, recovery and controller Back. Relates to UI-30 SC-5 Escape/dirty-draft work but adds an editing-key conflict. |
| **A11 F06 — P2, invisible language-save failure** | Actual paused app with newer-schema protected preferences loaded through the production loader: `writable=false`; choosing Español changes live locale to `es`, but Settings retains its translated immediate-save promise/generic preview, with no failure message. File is byte-identical and reload returns `en`. Fixture was installed during the isolated run, not by relaunching the whole app. | Report accepted/session-applied/saved outcomes to the active screen, not only Home. Explain failure in the selected language, give reason and Retry when possible; preserve newer-file protection. Test protected and unwritable destinations, unchanged file, and successful save clearing stale error. A specific missing-error route, not another broad transaction-model finding. |
| **A11 F07 — P2, startup text scale and semantics** | Source inspection: startup reads language/reduced motion but not saved display `ui_scale`; BrandIntro uses viewport-fit custom drawing for status/Skip rather than semantic controls. No assistive-technology reproduction. | Keep branding, use lightweight semantic status/Skip and validated saved scale without importing the heavy application graph. Native acceptance: 100%/200%, English/Spanish/CJK, reduced motion on/off, loading/error announcements and keyboard/pad Skip. The skip event must not also activate Fly after handoff. |
| **A11 F08 — P2, instrument explanations** | Source inspection: `overlays_dialog.gd` puts interpretation/availability descriptions in checkbox hover tooltips without visible focus-help. This is the instrument selector, separate from the prior aircraft-catalog tooltip issue. | Wrapped explanation follows focus and hover, with localized accessibility description where appropriate. A keyboard/pad user must discover purpose and limits of every instrument without a mouse, including 200% text. Actual assistive-technology output remains untested. |
| **A11 F09 — P3, arrow-key text equivalents** | Source inspection: custom `key_cap.gd` directional triangles lack application-provided direction text/accessibility names; localized arrow labels already exist in `key_labels.gd`. | Retain graphics with localized semantic names or a coherent action-row instruction; avoid duplicate announcements. Inspect the accessibility tree and listen to all four directions/actions using target-platform screen readers, translations and changed keyboard layouts. A debug snapshot alone cannot qualify this. |

**A11 F01 implementation update (2026-11-06):** New now switches to a separate device-default draft and UUID, preserves pending edits when switching profiles, and frees its draft slot only after successful Save. The real-store regression preserves both profiles even with equal names; Update, Duplicate, cancellation, failure/retry and calibration provenance are covered. [UI-15-GP-01-R1 evidence](../docs/research/controller-support-2026-10-14/README.md#new-profile-identity-2026-11-06-ui-15-gp-01-r1) records 57 new and 283 existing passing checks. Device-association ambiguity policy is unchanged; this is software verification, not physical-controller or native visual qualification.

**Prior-work reconciliation.** A11 reports reading this consolidation, UI-30, the subsequent menu delivery plan and current PR comments. R01 supplements UI-30 SC-8 preset placement/wording and the sky/cloud plan's unrelated-tab preservation requirement. Keep existing owners for broad typography, modal shells, overlay scaling and theme refresh. The graphically retained Home/Workshop captures predate the reviewed build and support design context only; they do not verify current visuals or establish new defects in every control state.

### Extra round two: E300-08 F5 installation-geometry synchronization

**Source: [A10][A10], reviewed `8e5f2f0`.** Startup applies the validated glow propeller diameter to the visual model. Successful F5 calls `session.reload()` and updates model CG, but omits that geometry setter even though the session rebuilds the physical collision disc. This is a developer reload-route correctness defect, distinct from A8's reversed blade handedness. E300-07's solver optimization is recorded in §6.

A10 uses the actual Extra flight scene and real F5 events through the debug bridge in disposable data copies. The 12→13-inch counterexample changes both aircraft and glow-installation JSON coherently under the same aircraft ID; it is an accepted synthetic developer edit, not a shipped/calibrated 13-inch catalog option.

| E300-08 operation | Accepted diameter / physical strike radius | Visual scale and outcome |
| --- | --- | --- |
| Stock launch and no-op F5 | 0.3048 m / 0.1524 m | 1.000000, consistent. |
| Change aircraft diameter alone, then F5 | Previous accepted values retained | 1.000000; inconsistent installation correctly refused. |
| Coherent 13-inch edit, then F5 | 0.3302 m / 0.1651 m | **1.000000, stale**, despite successful reload/trim. |
| Fresh launch with the same 13-inch files | 0.3302 m / 0.1651 m | 1.083333, correct fresh initialization. |
| Restore stock files in that flight, then F5 | 0.3048 m / 0.1524 m | **1.083333, stale** in the reverse direction. |

The required absolute scale is accepted/authored diameter, here 13/12. After increasing diameter via F5, blur radius remains about 0.152428 m against physical radius 0.1651 m, a **12.67 mm** radial mismatch. Reverse reload leaves visible radius about 0.165131 m against physical 0.1524 m. The authored mesh tip's roughly 28 µm nominal overrun is much smaller; no boundary-strike flight was run to demonstrate a collision consequence.

The existing `AirplaneBuilder.apply_propeller_diameter()` succeeds when invoked diagnostically and updates propeller/blur transforms. It computes from authored diameter, making repeated application idempotent. Diameter-only changes do not inherently require a blur rebuild: blur update copies the propeller global transform before its early return, while profile radius is local. A shared accepted-installation helper for startup and successful reload should refresh dependent extents and explicitly handle presentation failure after physical commit.

Regression must exercise **actual F5**, including no-op/repeated reload, accepted diameter changes both ways, rejected installation mismatch, and physical disc/solid/blur transforms. A setter-only test misses the wiring error; the nominal installation test passed 17 checks without covering F5. A10's diagnostic setter call is not a production repair. Headless app runs retained landscape-resource UID fallback warnings, so this proves observed state/transform behavior, not rendered pixels or target-GPU acceptance.

### Corsair second pass: CF-05 continuous contact and CF-06 flap transfer

**Source: [A12][A12], executed `3751e35`.** The author prioritizes CF-05 highest for correctness in this pass. These findings are additional to A9 CF-01–04; CF-05 concerns collision search, not A6 F3's support/statistics discrepancy, and CF-06 concerns flap force-location translation, not CF-01's rate-moment datum.

**CF-05 — endpoint admission misses raised-track crossings.** `flight_session.gd` skips a hull point when final `_rc_point_depth(candidate, hull, index) <= 0.0`; the depth helper also returns zero for points ending at/below flat-ground datum. An endpoint without penetration does not exclude an interior crossing. Both reported witnesses use valid constructed resets followed by real accepted ticks, the stock **23-point Corsair crash hull** and its right wingtip.

| Witness | Reported result and discriminating control |
| --- | --- |
| Tabletop, endpoint below datum | Crossing of composed field/track surface at interpolated fraction **0.124858** is missed by the track detector; session publishes flat-ground collision at **0.966441** instead, **3.5066 ms** later at 240 Hz. |
| Roller, both endpoints clear | Every hull point is clear at both endpoints, but the selected wingtip penetrates **0.932 mm** at sampled fraction **0.503**. The soft-contact tick is accepted without track impact and with an empty crash record. Making that interior pose the endpoint yields a collision, isolating the endpoint-admission failure. |

Crossings use the resolver's position/shortest-nlerp interpolation, **not dense RK trajectory reconstruction**. The submillimetre witness proves a counterexample, not frequency in player flights. Separate continuous signed terrain clearance, raised-dirt contact ownership and first-event search/arbitration. Search potentially intersecting interior intervals even with two clear endpoints; extra bisection iterations cannot recover an excluded candidate. A12 describes conservative interval search and a possible clearance bound, not an implemented repair. Regress both witnesses, rotating poses, the existing **5 cm relief threshold**, competing contacts and rollback.

**CF-06 — flap lift-reference transfer lacks direction projection.** Stock Corsair places incremental camber lift **0.075281 m aft** of the strip force point. For body displacement `dr=(-dx,0,0)` and incremental lift `dF=dL*(f2/Vp,0,-f0/Vp)`, the cross product requires `dMy=-dx*dL*(f0/Vp)`. Runtime `aero.gd` uses `-dx*dL`. Uniform flow at zero body rates reduces the missing factor to `cos(alpha)`; general repair must use **each station's actual local flow**, not one aircraft-wide angle.

Production `Aero.loads` diagnostics use stock data, **23 m/s**, **1.225 kg/m³**, full **30° flaps**, zero rates and other controls neutral:

| Angle of attack | Current offset contribution (N·m) | Cross-product transfer (N·m) | Current minus geometric (N·m) |
| --- | ---: | ---: | ---: |
| 0° | −14.616299 | −14.616299 | Approximately zero |
| +12° | −13.403083 | −13.110194 | −0.292890 |
| +20° | −18.482263 | −17.367646 | −1.114617 |
| +30° | −14.342156 | −12.420671 | −1.921485 |

A copied model changes only offset to zero; an independent oracle derives incremental lift from strip-force differences and applies the cross product. Other five wrench components remain numerically unchanged and clean-flap outputs are byte-identical between original/zero-offset models. This establishes internal force-location inconsistency, not real-Corsair error or a specific handling effect.

The proposed narrow correction retains the optional `lift_reference_offset_m` guard and active-flap/nonzero-plane-speed branch, multiplying `lift_q_area * flap_delta_cl * offset` by `f0 / plane_speed`. Preserve separate thin-airfoil section couple and profile-drag moment. A12 describes controls for absent/zero offset, clean flaps, zero/reverse flow, angular rates, spatial wind and finite fuel. Review this physics correction independently before more flap-pitch tuning.

### Corsair force/moment datum and thrust-lookup findings

**Source: [A9][A9], experiments at `84f4657814c157f1556f965861c0ab8623f48d8e`.** Keep CF-01–04 as the external report's IDs. A9 says it checked the subsequent `e72d878` change and found the responsible files unchanged; that is not a fresh audit of today's branch. CF-03/04 are in §6 below.

**CF-01 — Rate-derivative moment reference.** The generic runtime correctly transfers ARP forces/moments to CG. The Corsair generator derives `Cmq` with a squared tail-to-CG arm and fin `Cnr` with a squared fin-to-CG arm, then emits them into ARP fields. Its `CLq` tail force uses a tail-to-ARP arm, so force and moment derivations also mix datums. The fin kinematics independently establish the CG reference, beyond the generator's comment. At zero angles, the extra terms are `CLq*(xCG−xARP)/c` in pitch and `CYr*(xCG−xARP)/b` in yaw, with authored aft-positive x and coefficient chord `c=S/b`.

| CF-01 quantity | Stored CG-derived field | Additional runtime transfer | Realized CG derivative |
| --- | ---: | ---: | ---: |
| Pitch damping Cmq | −10.193066 | +0.789336415 | −9.403729585 |
| Yaw damping Cnr | −0.093768 | +0.004090166 | −0.089677834 |

The loaded reference-inventory witness uses x separation 0.0742843807412 m, chord 0.518605 m and span 2.777778 m. Magnitudes are **7.7439% weaker in pitch and 4.3620% weaker in yaw** than those stored CG-derived coefficients; these are not whole-aircraft handling percentages. Production `Aero.loads` at 23 m/s recovers the predicted derivatives with central perturbations ±0.02, ±0.002 and ±0.0002 rad/s, entirely in the empirical branch. Coincident longitudinal CG/ARP removes the extra terms; diagnostic in-memory moment shifts recover the target values.

Production level trim converges near α=3.54535°, β=0.51218° while retaining the inconsistency. Its angle-corrected pitch transfer is 0.809636836; at separate pitch/yaw rates of 0.2 rad/s, aerodynamic moments differ from the reference-shift diagnostics by **0.441908 N·m pitch / 0.0640453 N·m yaw**, vanishing at zero rate. Static trim therefore does not qualify rate-response consistency.

Repair the complete force/moment rate pairs at a declared reference-inventory datum, angle and wake condition, then transform dimensional moment derivatives to ARP once before normalization. Keep the correct generic ARP-to-live-CG transfer; do not merely tune `Cmq` by the measured offset or replace the reference datum with empty-tank plan CG. Generate/regenerate through the owning pipeline and independently check zero/trim angles, mixed rates, fuel-dependent mass and empirical/local transitions. This is a Corsair recurrence of the convention addressed for Stik under D6e-R1/D11g, and is related to A8 E300-01; each aircraft generator still needs its own evidence. The audit shifts are diagnostics, not validated replacement physics.

**CF-02 — Endpoint/floor discontinuity.** Corsair's thrust table ends at `J=1.35`, `CT=−0.1029`, while shared extrapolation applies `CT_FLOOR=−0.1` only beyond the table. Interpolation preserves the final authored value, but immediately outside returns −0.1: a coefficient jump of **+0.0029**, not an ordinary interpolation slope change.

| CF-02 witness | Reported result and limit |
| --- | --- |
| Boundary samples at 1.35−1e−9 / 1.35 / 1.35+1e−9 | CT −0.102899999772 / −0.1029 / −0.1. Power coefficient stays continuous; a nearby J=1.30 control changes CT only about 5.14e−10 at the same perturbation. |
| Dimensional thrust | Diameter 0.762 m, 1,750 RPM, density 1.225 kg/m³: about **1.01889 N** jump at roughly 30.00375 m/s axial speed. |
| Finite-fuel production stage comparison | About 1.012 N forward-force and 0.04625 m/s² forward-acceleration difference with the session's own atmosphere/coupled mass. |
| Reachable crossing | Valid constructed engine-off state starts at J=1.35001/1,750 RPM; one accepted 240 Hz tick reaches J=1.3469053786/1,753.2005673 RPM without fault. This is not evidence of visible jerk or sustained handling failure. |

For that extrapolation form, continuity requires `floor ≤ last_value`. Define a declared per-propeller floor or table-aware shared rule, preserving in-table values. Test final values above/equal/below the floor, neighboring binary64 inputs, ordinary interpolation and the engine-off crossing. The same interaction appears in other data, including P-51; avoid a Corsair-specific kernel branch. Keep lookup continuity separate from uncertain propeller calibration and from previously reported reverse-flow limitations.

### Extra 300 generator and presentation findings

**Source: [A8][A8], reviewed `e72d878b6b4a89209dfe1a992ba119921dcdd34c`.** Preserve E300-01–06 as external finding identifiers. A8 reports two physics consistency defects, three optimization opportunities (in §6 below), and one visual defect. It is a later source snapshot than A2–A6 and does not overwrite their historical findings or establish present-day repair status.

| ID | Reported mechanism and witness | Suggested correction and scope |
| --- | --- | --- |
| **E300-01 — Mixed moment reference points** | Aircraft coefficients must describe moments about the aerodynamic reference point (ARP); runtime transfers forces to the CG once. Extra's generator instead uses the loaded-CG fin arm in part of `Clb`, labels `Cmq` about CG, and uses a CG arm in fin `Cnr`, mixing conventions with nearby ARP-derived coefficients. | Correct the owning generator's force/moment reference invariants and regenerate through its pipeline. Do not globally replace CG arms: rotational-inflow arms and moment arms have different roles. This is a contract inconsistency, not A5's unproven polygon-centroid/pressure-center alternative. |
| **E300-02 — Camber omitted from crossflow derivation** | Installed propeller has `zero_lift_angle_rad=-0.10223236266152576` (about −5.8575°), correctly used by runtime shaft thrust/torque. The generator omits it from the section mapping used for normal-force/P-factor tables, whose Python mirror defaults to zero. All 44 shipped entries are reproduced exactly before adding only camber. | Reuse one installation-to-section adapter, retain optional-field defaults, and regenerate aircraft data/dependent identities. Add an independent table-to-installed-section invariant; comparing loads against the same shipped tables cannot detect this error. The consistent method is not independently calibrated propeller data. |
| **E300-06 — Visual blade handedness opposes spin** | Actual mesh places the +X blade's leading edge toward +Y, while positive-RPM finite-glow presentation rotates about local −Z, so point velocity is toward −Y. The leading-minus-trailing-edge vector dotted with `ω×p_mid` is negative for production spin and positive for reversed-spin control. | Correct leading edge, camber and pitch geometry together, preserving physical rotation conventions and stable nodes/hinges. Inspect stopped appearance, rotation, blur and strikes. Headless geometric witness establishes a presentation inconsistency, not an error in physical shaft/thrust signs or rendered visual acceptance. |

**E300-01 load and damping details:** stock full-tank values `CYb_fin=−0.35510923 rad⁻¹`, CG 0.02842429 m above ARP, and span 1.6256 m imply excess `ΔClb=+0.00620923 rad⁻¹`. At 20 m/s, density 1.225 kg/m³, α=0°, β=+5°, neutral controls/zero rates, settled wake, no ground effect and 12,000 RPM, correcting only that fin contribution changes aerodynamic roll from −0.328074 to −0.431661 N·m and combined roll from −0.919021 to −1.022608 N·m: **−0.103587 N·m**. This is 24.0% of the diagnostic aerodynamic component or 10.1% of diagnostic combined roll, not measured error in complete aircraft response. Negative sideslip reverses the correction; other load components and propulsion/slipstream contributions remain unchanged, with local-flow selector zero.

Small symmetric rate probes give generated/effective-CG `Cmq` −9.360761/−9.157953 and `Cnr` −0.180871/−0.178734, matching the extra force-arm translations (about 2.17%/1.18% less negative). The narrow static fix uses `CYb_fin*(fin_height−ARP_height)/span`, not total `CYb`: fuselage side force is already at ARP. Enabling optional `wing_body_cl_beta` also changes the local-regime roll law, so it is not merely a validation switch. A8 reports 29 production-witness checks, covering signs, rate symmetry, unaffected loads and moment-datum algebra.

**E300-02 coefficient and dimensional details:** adding camber to the same derivation changes normal/P-factor coefficients as follows. Values are six-decimal table values; “consistent” means consistent with the installed section within that method.

| Advance ratio J | Stock → consistent normal coefficient | Stock → consistent P-factor coefficient |
| --- | --- | --- |
| 0.30 | 0.001884 → 0.002474 | 0.002999 → 0.005058 |
| 0.50 | 0.004456 → 0.006239 | 0.002978 → 0.006713 |
| 0.70 | 0.006712 → 0.010410 | 0.000957 → 0.006488 |
| 0.80 | 0.007221 → 0.012175 | 0.000000 → 0.005572 |

At J=0.5, stock coefficients are 28.6%/55.6% below the respective consistent results. Before nonnegative clamping and rounding, independent identities are `ΔCN=3J²ΔCT/(2π²)` and `ΔCM=JΔCT/(2π)`, with a zero-camber control. At 12,000 RPM, diameter 0.3048 m, J=0.5 (30.48 m/s axial speed) and 10° disc-flow angle, production loads change normal magnitude 0.327244→0.458185 N and P-factor magnitude 0.066660→0.150265 N·m. Vertical crossflow changes the full wrench by about −0.08360 N·m yaw and +0.04753 N·m pitch including the force arm; **shaft thrust/torque remain byte-identical**. A8 reports 46 new production-load checks (both crossflow directions, aligned flow, zero RPM and Python/runtime thrust agreement). Existing installation tests pass 17/17 but use the same shipped tables, so they do not independently validate the omitted parameter.

### Developer handoff: F1–F6

**Source: [A6][A6].** Preserve its finding IDs and scope. Its recommended P1 means repair before relying on the affected path, P2 an observable correctness defect, and P3 a limited numerical/tooling defect. F6's P1 concerns energy-law correctness, not a demonstrated application crash. These are historical report classifications; current repair status has not been checked.

| ID / priority | Reported reproduction and consequence | Repair boundary and acceptance |
| --- | --- | --- |
| **F1 / P1 — Workshop stepping admission** | A synthetic Extra 300S draft sets `engine_main=0.311 kg`, `wing_main=0.270 kg`, `fuselage_rear=0.089 kg`, each with `source="measurement"`. These are schema-admitted counterexample inputs, not real measurements. `Trial.freeze` derives mass 3.0795476 kg and two gear substeps; Club-runway qualification and reset converge at cruise trim 0.5. First `sim.step()` faults at tick 0: whole-tick policy cannot honor two contact substeps. | Gear spring accuracy requests smaller steps, while glow installs a whole-tick event policy. Reject the incompatible combination before flight or compose contact/event segments atomically. Do not remove the guard or clamp subdivisions to one. Test first tick, contact becoming reachable, event ordering, complete rollback, and one input/AUX/RNG update/publication per accepted tick. Checked stock glow models used one substep; a general stock-start failure or later airborne landing failure was not demonstrated. |
| **F2 / P1 — Pause overwrites bound AUX targets** | Synthetic EdgeTX-style Avanti: flaps axis 4 and gear axis 5 are armed low, then held at +1. Across ordinary `pause_menu` hold/resume, accepted ticks 2→3 change flap request 1→0 and gear target up→down despite unchanged switch values. | AUX reset clears readiness; the session consumes an unarmed zero as a valid command. Separate command validity from amount or retain accepted position requests. Cover axis/button bindings, all flap/gear states, pause/menu/focus, deliberate rearming and physical actuator continuity; keep smoke-pump and disconnect/calibration/throttle policies explicit. This is not instantaneous actuator travel or a physical-transmitter/unbound-toggle result. |
| **F3 / P2 — Statistics omit circuit terrain** | Stik at NED `[39, -4, -0.755]` on the default Club circuit has track height 0.515 m and physical wheel compressions `[0.0119176434, 0.0128185565, 0.0145762139] m`. Observer reports valid sample, wheels `[-1,-1,-1]`, no support, and `clearance_ok=true`. | Early bound omits track height: gear reach 0.3505990400 m should retain this candidate with combined bound about 0.8655990400 m. Clearance/orientation also omit track, so fixing the bound alone is insufficient. Reuse composed `environment.ground()` and `ground_max_height()` identities; check ramps, edges, field/lake, mutations and complete detector episodes. Witness is staged geometry, not equilibrium or a measured false landing count. |
| **F4 / P3 — Connected glow trial rounds onto reserve** | With reserve 0.0042846 kg, binary64 ULP is 8.673617379884035e−19 kg; `reserve + 1e-30` equals reserve. The intended connected trial instead selects fuel-unavailable behavior during event localization. | Prefer explicit connected-trial state; an alternative representable sentinel requires equivalent lifecycle/native handling and downstream checks. Test neighboring floats, independent constant-flow event timing, integrated torque/force, and native/reference parity. Diagnostic `+1e-12` is not a qualified fix. Production still reaches reserve/emits stop; no crash or visible handling consequence established. |
| **F5 / P3 — Empty continuous-state log rejects itself** | Valid in-memory Stik via `AircraftData.validate_and_derive`, before optional file-boundary wheel profile, has an empty continuous block. Record/save succeeds; inspection fails with `Initial sample disagrees with checkpoint: continuous`. Snapshot omits the empty key, initial sample includes `[]`, reader requires the key. | Normalize legally absent v1 optional blocks to empty or emit explicit empty blocks while preserving compatibility. Check record/inspect/replay for absent, empty and nonempty states; retain malformed-data rejection. All checked flyable catalog entries had nonempty blocks, so this is not a general catalog-recording failure. |
| **F6 / P1 — Tire/brake constraints can add energy** | Acceleration-relaxation target and symmetric magnitude limits permit positive tangential contact or brake work. Production-solver examples, stock Bisonte energy balance, and a from-rest drive sequence demonstrate the tire defect; a separate brake example/scan establishes the brake defect. | Enforce dissipative admissibility with the existing load-scaled force limit, preserve static reactions at zero slip, and qualify combined slip, reversal, holding, load loss, stage-integrated energy, convergence and backend parity. A magnitude-only force circle is insufficient; independent component sign clamps impose a different constraint. Native equations were inspected but not executed. |

**F4 timing detail:** from `reserve + 1e-7 kg`, production versus connected-trial diagnostic exhaustion times are 1.763268/0.877741 ms (Stik 55AX), 1.373147/1.144313 ms (Stik FS64V), and 1.702545/0.847247 ms (Extra). Reported differences are 0.885527, 0.228833, and 0.855298 ms; displayed columns round independently. The roughly 5e−13 s event `time_error_bound_s` bounds the root bracket, not accuracy of a trajectory using the wrong trial law. Initial-flow estimates support the diagnosis but are not physical stopping-time measurements. This is separate from [A4's firing-counter finding](#glow-fuel-event-counter-defect).

**F4 implementation update (2026-11-06):** the V5 glow law now uses a representable connected-trial successor in GDScript and C++, without adding fuel to physical inventory. The independent constant-flow regression locates 0.800 ms at 120/240/480 Hz; focused checks, baseline/candidate tapes and 8,046 identical native comparisons are retained in the [FUEL-12-R3 evidence](../docs/research/fuel-systems/FUEL-12/README.md#connected-main-tank-trials-fuel-12-r3-2026-11-06). Historical V4 traces remain readable; normal checkpoint restore requires the current law. A4's separate firing-counter repair is recorded below. This is software verification, not full CI, complete native installation or physical qualification.

### F6 energy and reachability evidence

For stationary ground and this nonelastic tangential model, A6 requires `F_long*s_long + F_lat*s_lat ≤ 0` and `Q_brake*ω_relative ≤ 0`. Slip includes full contact-point translation, body rotation, suspension and wheel motion. The implementation has normal elastic energy, but no tangential/brake elastic store to explain positive work. At zero slip/spin, static reactions can have either sign with zero instantaneous work.

The scalar relaxation law requests `F = (−s/τ − a_free)/W`. If positive slip is already decelerating faster than the target, the force can point with slip. An identity 14×14 mass-matrix production-solver case with `s=1`, `a_free=−2`, `τ=1`, and 10 N cap returns +1 N/+1 W after two sweeps; the analogous brake case returns +1 N·m/+1 W. This isolates the solver, not a physical truck.

| A6 evidence | Reported result | Limit |
| --- | --- | --- |
| Stock Bisonte instantaneous energy balance | Flat road, `mu=0.9`, `rolling=1.0`, body speed 5 m/s, wheel spin 30 rad/s, radius 0.1 m, throttle 1/brake 0: slip +2 m/s and about +10.96036 N per tire after six sweeps. Motor +468 W, rolling −5.683934337 W, tires **+87.682882561 W**, total +549.998948224 W. | Positive tire contribution is about 18.7% of motor input at this instant, not lap average. It does not depend on the known 128-sweep cap. |
| Independent energy derivative | Central directional differences of production total energy along the public state derivative agree with total +549.998948224 W within 6.3e−8 W for four epsilon values from 1e−4 to 1e−7 s. | Includes body/hub/axial-rotor kinetic, gravity and elastic energy; selected witness has zero body rate, suspension and vertical velocity. |
| Ordinary drive/brake sequence from rest | Throttle 0–1.50 s, brake 1.50–1.75 s, throttle 1.75–2.75 s, brake 2.75–3.50 s; no overlap, steering or reverse. All 840 steps accepted; throttle reapplication yields **+168.812180765 W** tire power, with 25 positive tick-start samples. | Production flat-road trajectory, not a rendered circuit lap. No positive brake work in this ordinary sequence. |
| Outer-step refinement over first 2.25 s | Peak positive tire power: 168.812180765 W at 240 Hz, 168.803890401 W at 480 Hz, 168.800126563 W at 960 Hz, about 0.0071% change. | Supports a force-law defect rather than a timestep cure. Positive-only work sums are sampled estimates, not net created energy or exact RK-stage integrals. |
| Separate brake scan | 486 valid cases without refusals include +108 W brake power at negative wheel spin with simultaneous throttle/brake. | Admitted core state, not a demonstrated player-input sequence. |

A6 proposes adding `F·s ≤ 0` to the existing load-scaled force disk under its mobility-metric projection, and the brake power condition at nonzero relative spin. These are necessary energy constraints, not a complete calibrated tire law. A repair intentionally changes physics and needs solver/checkpoint identity handling and explained trajectory changes; no contact-law patch is supplied as validated production work.

### Apple rendering and benchmark audit

All rows below come from [A1, §3][A1]. They describe its frozen snapshot. Suggested responses are retained recommendations, not work completed here.

| Finding | Trigger and consequence | Reported status and follow-up |
| --- | --- | --- |
| Release preflight lacks five UID files | Missing sidecars stop release preflight; app, visual, native-qualification, and release-build jobs are skipped. | Historical observed CI failure. A2 reports the additions; verify the relevant gate before treating the baseline as accepted. |
| Measured cache differs from enabled cache | C2 measured RGBA8 ground/near-grass caching; later RG16F also feeds C5b sky relief and becomes the graphical default. | Qualification mismatch. Identify ground-only, sky-only, and combined candidates separately. |
| Cache published before bake success | A zero-filled texture is enabled immediately. After three process callbacks, failed/empty graphical readback can leave the placeholder cached and enabled after the temporary viewport is freed. | Conditional risk, not a reproduced Mac incident. Keep analytic rendering until successful validation; define failure, retry, and fallback behavior. |
| Requested and effective rendering disagree | A synthetic MetalFX Spatial request passes even though effective rendering records Native fallback. | Reproduced acceptance defect. Compare requested/effective renderer, reconstruction provider, scale, MSAA, and fallback state. It does not prove historical campaigns used the wrong renderer. |
| Instrumented runs remain eligible | A synthetic checked invocation containing `--gpu-profile` can receive `performance_pass=true`. | Reproduced acceptance defect. Keep profiler/HUD/diagnostic runs distinct from clean acceptance measurements. |
| Fixture identity omits cache changes | Sixteen named hashes omit the new cache implementation/shaders; normalized scenarios omit cache environment and effective bake state. | Source-derived identity gap. Bind full rendering source identity plus explicit cache state. A retained full-source manifest may distinguish revisions even when fixture identity does not. |
| Recovery confirms callbacks, not displayed images | `_process` progress can satisfy the renderer guard without proving valid display output. | Conditional risk. Add evidence appropriate to graphical recovery. |
| MetalFX activation confirmer races | An older confirmer in an on/off/on sequence can clear the pending marker for a newer activation. | Conditional lifecycle risk requiring a focused transition case. |
| Custom shoreline cut can fail while lake metadata is published | A hole wholly inside one source triangle is rejected by clipping; attachment can log failure and still publish lake/physics metadata. | Conditional custom-lake mismatch. A focused fixture is needed; this is not evidence that the default lake is broken. |

The five historical sidecars are `app/app_state/renderer_guard.gd.uid`, `app/render/cloud_shadow_map.gd.uid`, `app/render/cloud_shadow_map.gdshader.uid`, `app/tests/test_cloud_shadow_map.gd.uid`, and `app/tests/test_renderer_guard.gd.uid`. The original includes the [failing CI receipt](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42120685263/job/127571913297).

The cache default at A1 applies to every non-headless display server, including Compatibility/OpenGL. `OPENRC_CLOUD_SHADOW_MAP=0` selects its analytic baseline; an unset variable must not be interpreted as disabled. A 2048² RG16F tile occupies 16 MiB, so four retained tiles use 64 MiB before temporary buffers. Layered weather derives different seeds and may fall back to analytic noise: a single-deck result cannot establish a layered-weather gain.

### Glow fuel-event counter defect

**Source: [A4, first finding][A4].** At fuel exhaustion, `GlowFlight.step` integrates and locates the event, then applies the stopped endpoint's zero firing fraction to lifecycle acceptance for the entire tick. A crank opportunity before the stop can therefore disappear from accepted `fire_count`. Trace `glow_fire_events` and the audio voice consume these counters.

- **Public-session witness:** stock `stik_glow_55ax_2t`, public `set_fuel_start_fill()` and `reset()`, then two ordinary `Simulation.step()` calls. Fill `0.01428833552836` leaves approximately 0.000000786168 kg of usable fuel above the specified 5 mL unusable residue. This is an intentional API-boundary case, not an ordinary Home-menu fill claim.
- **Observed tick:** tick 2 adds one opportunity and zero fires, stops for exhaustion without a simulator fault, and records 3.984254 J of chemical work. Estimated opportunity time is 0.0074020 s; the located event is reported at 0.0081907 s. The ordering estimate does not independently qualify fuel-event timing.
- **Discriminating control:** a valid constructed state at 8113.948 relative RPM and phase 0.9 gives one opportunity/zero fires with one 240 Hz step, versus one opportunity/one fire with two 480 Hz half steps. The first half remains burning; both paths record approximately 3.679 J of chemical work.
- **Counter isolation:** passing the identical bounded continuous candidate through acceptance with firing fraction 0 versus 1 changes only the fire counter. Replacing the endpoint fraction with the initial fraction is a diagnostic, not a general fix.
- **Suggested correction:** account for opportunities on their accepted event segments, carry the deterministic accumulator, and define before/at/after-stop ordering. Preserve the accepted continuous solution and rollback; cover multiple opportunities and an event-free control.

This finding establishes a lifecycle/counter error within the report. It does not establish incorrect shaft torque, fuel mass, trajectory, or audible waveform, and it excludes the separately known fuel-boundary-rounding issue. No natural full-tank exhaustion flight was run.

**A4 implementation update (2026-11-06):** the V6 glow law counts committed source-mode intervals, carries the accumulator, assigns exact-boundary opportunities to the closing interval, and preserves atomic rollback. Public 55AX/FS64V/Extra fill/reset tapes retain one previously lost fire with every non-firing CSV value unchanged. The [FUEL-12-R4 evidence](../docs/research/fuel-systems/FUEL-12/README.md#accepted-combustion-counters-fuel-12-r4-2026-11-06) records before/at/after, fractional, feed-line, rotor/pickup, zero-probability and real Simulation rollback checks. Endpoint probability remains a mean-cycle approximation, not physical spark-time validation.

## 4. Physics findings and model limitations

These items must remain separate from the reported defects in §3.

### Extra round-two observations and bounded controls

**Source: [A10][A10].** These are not additional confirmed aerodynamic defects or permission to adopt the diagnostic substitutions.

| Observation | Reported evidence | Interpretation |
| --- | --- | --- |
| Polar attachment versus induced-source retention | Constructed −20° angle of attack, 20 m/s: source weights all zero while active polar attachment is about 0.566–0.619. Replacing source weights with polar attachment diagnostically changes Fz by about 22.37 N. | Significant sensitivity, but no contract requires these quantities to match and no independent negative-angle evidence chooses the correct law. Clarify/validate the intended relationship before tuning. Distinct from A5's selector asymmetry. |
| Maximum-station-speed roll-rate cusp | At 14° and 20 m/s, one-sided Fz derivatives approach −0.264606 and +0.264606 N/(rad/s); a fixture-specific control identifies max-speed normalization as the cause. | Continuous response can contain a first-order absolute-roll-rate term even when central difference at zero is zero. About 0.026 N at 0.1 rad/s in this fixture; no material handling/integration failure established, and no generic wake correction proposed. |
| Finite-fuel controls | 23 checks across four offered fills, live mass/CG/inertia, starter prime/momentum, cut/restart replay and reset refueling. Independent fixed-datum inertia differs by at most about 5.56e−17 kg·m². | Bounded software checks, not long-flight/physical tank validation. A 16-tick cut/restart recording replays sampled arrays exactly. |
| Excluded concerns | Rotating-shaft scenery behavior traces to a documented contact convention; apparent Workshop scaling issue is unreachable because finite-glow Extra refuses the operation. | Do not promote these to new defects. First-pass E300-01–06 and existing downwash-air reuse are explicitly excluded from the new-finding count. |

A8 explicitly excludes earlier reverse-flow discontinuity, trim/failsafe concerns, airflow/cache opportunities, missing wing propwash and known knife-edge/hammerhead limits from its new-defect count. It reproduces a coasting-propeller strike omission but attributes that coverage to existing **GP-17**, rather than adding another discovery. A5's earlier “no new serious defect established” verdict remains scoped to that review; it does not rule out A8's different generator findings on a later revision.

| Item | Reported observation | Disposition |
| --- | --- | --- |
| Relative-shaft propeller power convention, A4 | Constructed stopped-source Extra sample: zero hub flow, 30 RPM relative shaft speed, body roll −400°/s. Propeller torque +5.777973 µN·m; absolute shaft speed −36.6667 RPM. Combined mechanical power is +22.185824 µW, versus −18.152038 µW with zero roll. | Quantified consequence of the documented mean axial-propeller/relative-shaft model, which omits blade-by-blade body-rate inflow. No flown trajectory, new undisclosed regression, or physical calibration established. |
| Slipstream versus ground effect, A5 | Tail downwash is scaled by ground effect, but the washed-minus-free slipstream increment is not. Extra, P-51, and Corsair declare both modules. | Explicitly documented height-independent slipstream increment. Changing it would be a physics-law change, not a demonstrated bug repair. |
| Extra lower-rudder force arm, A5 | Polygon-centroid x is 0.980531 m versus tail reference 0.849684 m. At 15 m/s, 12,000 RPM and 25° rudder, lower-piece force is 2.077987 N; using the centroid would add −0.271898 N·m yaw. Twenty decomposition cases match the full wake. | The geometric centroid is not a measured pressure center. The legacy reference-plane convention is documented; the alternative arm is not established as physically correct. |
| Negative-angle stall-selector asymmetry, A5 | Initial selector uses `a1` for both signs, while station selectors distinguish `a1`/`n1`. Turbo Lumber at −14°, 20 m/s: diagnostic weight 0.7037029102 versus production 0.9358366063; pitch moment changes from 5.118864385 to 5.071713366 N·m, about 0.92%. Seven-aircraft/positive-angle controls report no load failures. | Unresolved low-impact candidate. The one-expression variant exposes a difference; it is not a recommended or physically validated repair, and no substantial flight consequence is shown. |

Detailed assumptions and original evidence locations remain in [A4][A4] and [A5][A5]. Their numerical checks are software/model-consistency evidence, not aircraft validation.

### Additional bounded controls and known limitations from A6

| Investigation | Reported outcome and boundary |
| --- | --- |
| Selected baseline tests | `test_simulation.gd`: 11 checks; RC input: 41; AUX runtime: 38 with expected overlap warning. These do not cover F2's full session composition or establish full-suite success. |
| Rotor/body and inflow checks | 600 X-Cell states without refusals, maximum power-identity residual about 9.1e−13 W; 27,150 scalar inflow samples, maximum residual about 1e−13. Bounded controls, not full physical validation. |
| P-51 fuel runout | Runway start at valid 1.01% fill exhausts at 0.934817 s and continues 15 s without the suspected fault; a 200 m airborne start also continues. Legacy sub-1-RPM hold is documented; runway speed settles near 0.85135 RPM. |
| Event checkpoint replay | P-51 checkpoint tick 210 through 280 and Turbo Lumber rotor-stop tick 1430 through 1490 retain byte-identical subsequent checkpoints/events under prescribed held inputs on the reference backend. |
| Electric reverse breakaway | A stopped electric propeller reaches an already documented/tested unsupported-domain refusal in a stock glide/roll sequence. Separate model-domain work, not a newly discovered defect. Other reviewed electric/battery/ESC/fuel/mass/turbine paths yielded no additional serious defect in the handoff. |
| Known truck convergence/asymmetry | Symmetric braking witness returns success at the 128-sweep cap with yaw acceleration −0.0114509624 rad/s²; a cap-only diagnostic reaches update tolerances after 1,766 sweeps with −0.0000239593 rad/s². Reversing contact-pair order reverses yaw. Both force and brake tolerances already participate in early-out; unconditional success at the cap is the known limitation. |
| Convergence trajectory scope | A separate four-second sequence hits the cap in 671/960 tick-start evaluations but reaches only about 0.206 mm lateral offset and 0.00232° yaw; it is still moving at the end. This does not establish another new severe defect. Small updates are not a full complementarity residual, and nonunique reaction distributions need care. |
| Ground-effect/propwash convention | Overlaps A5's documented convention above. A6's exploratory numerical comparison was not retained in recovered packages, so A6 adds no quantitative magnitude claim. |

The known cap/asymmetry limitation is **distinct from F6's newly reported positive-work law**, whose stock energy witness converges in six sweeps.

## 5. Mathematical optimization register

**Source: [A2][A2].** Preserve its original M01–M12 and R01–R02 experiment identifiers. Results in this section are analytical proofs under stated assumptions, source analysis, or portable numerical models. No candidate has a measured Apple-GPU speedup in this lab. Full derivations, coefficients, source links, and probe names remain in the original.

A2 identifies partial-fBm exits, hash atlases, octave dictionaries, solar LUTs, crop rendering, relief caches, and rasterization-rate maps as topics already discussed in the frozen repository's `optimization help.md`. It does not count those ideas as new lab results or rerun their campaigns.

### Cloud and sky

| ID / source section | Candidate and useful reported result | Required boundary |
| --- | --- | --- |
| **M01**, §3 | Share four coarse value-noise corner hashes across three displaced relief queries when their wrapped lattice cells match: 12 source-level hashes become 4 on that path. Same-cell rates 82.49%, 97.20%, 99.14% for three tested light elevations; selected float32 and seam checks show zero difference. | Keep each query's original interpolation and original fallback at cell crossings. No saving when clustering is disabled. Unguarded sharing produced errors up to 1.0. This does not remove two thirds of the whole cloud shader and does not generalize to fine octaves. |
| **M02**, §4 | Replace ordinary solar `acos` with chord coordinate `c = sqrt(2 - 2μ)`, transforming disc thresholds too. Global real-arithmetic normalized halo error bound: 1.7838854e−4. Screened 1,162,773 distinct float32 cosines; sampled combined `0.35H + 4D` difference at one default radius: 6.0601160e−5. | Disc ramp is an approximation, not an algebraic identity. The halo bound does not bound the disc or GPU rounding. Preserve dynamic radius, limb/squash mode, occlusion, radiance generation, and multiply error by actual HDR solar contribution. |
| **M03**, §5 | Use monotonic relief endpoints to bound omitted density queries. Midpoint error is at most half the interval width before consumer weighting. At budget 0.001, cheap-decision query averages range 0.621–2.809 versus 3 in four selected screens. | Start with the cheap far bound; retain original density for silhouettes, occlusion, and other consumers. Classic and layered clouds require different color multipliers. Bound all layers/approximations together. Sample requests do not equal issued GPU work. |
| **M04**, §6 | Reject zero-support sun/moon aureole work by dot-product cutoff before inverse trig; ordinary disc has its own support. In 1,002,126 sampled inputs, two-ULP downward guards showed zero false culls. | Empirical guard is not a proof for every GPU math mode. Keep moon antialiasing derivatives ahead of varying early-outs, and keep optional solar limb/squash behavior distinct. A 45° cap's 14.64% sphere coverage is not viewport frequency. |
| **M11**, §9 | Approximate transmission `exp(−z)` only for bounded `z ∈ [0, 2.16]`. Degree-five Horner polynomial: sampled maximum error 2.6417046e−5 across 398,536 float32 inputs; real-coefficient truncation bound 2.6422810e−5. | Lower priority until exponential cost is measured. Rounded degree-six/seven results exceed ideal truncation bounds; the sampled endpoint slightly exceeds ideal 2.16. Five multiply-add stages may cost more than the exponential. Combine its error with M03. |

For M03, with body density and samples bounded to [0, 1] and normalized directions, the relief factor is nonincreasing in each unknown sample. Its coefficient satisfies `0.38 ≤ B ≤ 0.50`. A cheap far-sample sufficient bound is `E_far ≤ k B (1 − exp(−0.4)) / 2`, where `k` is the **actual consumer's** color contribution. A 1e−7 margin prevented budget overruns in one CPU stress screen; it is not a certified Metal margin. The hypothetical 32-lane coherence screen likewise does not establish Apple's pixel-to-SIMD mapping.

M01's portable model substitutes analytic low octaves for the actual filtered RG16F cache. Its four-query extension and cross-cell deduplication may remove more arithmetic but retain more live data and bookkeeping. Begin with the smaller three-query case and retain wrong-seed, disabled-cache, periodic-boundary, and both-ray-sign controls.

M03 also requires sampler/derivative discipline around varying branches. A2's source uses a non-mipmapped linear cache sampler; future mipmapped/anisotropic routes need gradients computed before divergent flow or a validated explicit-LOD/gradient operation. This is an implementation boundary, not evidence of an existing shader defect.

### Ground shading

| ID / source section | Candidate and useful reported result | Required boundary |
| --- | --- | --- |
| **M05**, §7.1 | Compute the base noise footprint once, then divide by the constant octave scales. Source spelling reduces eight vector derivatives/lengths to two of each. In 500,000 synthetic quads, maximum macro-noise difference 9.06e−6; dry-patch weight difference 3.50e−5. | Tolerance-based rendering change: differencing rounded transformed coordinates is not byte-identical. Keep derivatives outside divergence; cover ground, near-grass, lake-bank, and the bank's separate 2.8 m call. Inspect compiler reuse first. |
| **M06**, §7.2 | Share relief phases/cosines; omit sine work only where amplitude gradient is zero. In 300,000 samples, maximum slope-component difference 7.45e−9; modeled normal-angle difference 4.77e−7 degrees. | Preserve `∇h = A∇W + W∇A`, including feather-edge amplitude gradients and surface precedence. Physics terrain stays unchanged. Update affected literal-substring tests without treating a CPU mirror as GPU proof. |
| **M07**, §7.3 | Skip one photographic anti-tiling endpoint when its blend weight is exactly 0 or 1: three texture requests instead of six for the affected material. 29.54% endpoint positions in a uniform-area disk; same-endpoint quad rates fall as pixel footprint grows. | Finite texture values, original explicit gradients before branching, and exact endpoints only. Divergence may erase savings. Shared grass/dirt indices and offsets are another same-position reuse opportunity; cover normals and lake banks too. |
| **M08**, §7.4 | Share grass/dirt tangent frame in overlap pixels; normalize/blend in tangent space, project once, and retain final normalization. Across 400,000 synthetic normals: median angular difference 1.82e−6°, p99 6.12e−6°, maximum 0.0001394°. | Preserve dirt-only and grass-skipped paths, incoming normal magnitude where relevant, frame conditioning, and rigid view-transform assumptions. The model omits real texture decoding, view transform, and GPU execution. |
| **M12**, §10.3 | Guarded parcel rejection preserves selected IDs/factors in 250,000 random and 70,000 boundary samples with empirical guard 1.000001; averages 4.88 square roots versus nine in the random set. | **Research only.** Unguarded squared-distance ranking changes float32 tie behavior and material identity: raw crop-factor difference up to 0.283, default faded factor up to 0.133. Near threshold retain original roots and strict comparison order; GPU rounding/branch cost remain unresolved. |

### Same-evaluation physics reuse

| ID / source section | Candidate | Exactness contract |
| --- | --- | --- |
| **M09**, §8.1 | Pass already validated reference/spatial wing-flow results into the matching `local_loads` evaluations. For six strips, removing two passes implies 11,520 fewer source-level `atan2` evaluations and 23,040 fewer square roots per simulated second at four stages/240 Hz on that qualifying route. | Reuse only within the exact same RK evaluation and matching inputs. Distinguish reference/spatial and optional wake inputs. Preserve validation order, NaNs, signed zero, refusal, rollback, and serial reductions. Operation counts exclude additional events/substeps and are not timings. |
| **M10**, §§8.2–8.3 | Lazily prepare identical flap invariants once per evaluation; prepare clean-strip source factors once per source strip. Preparation falls from `A×N` to `N` for `A` active receivers and `N` strips; map products remain. Smaller glow-propeller opportunity: reuse axial-speed square and half-density across 12 annuli. | Keep original expressions and multiplication/accumulation order, and avoid evaluating a branch that was previously unused. No cross-stage, cross-tick, changed-control, changed-wind, or clean/flapped cache reuse. |

A2's native probes explain why algebra alone is insufficient: reassociating quaternion rotation changed at least one component in 9,673 of 10,000 binary64 cases (maximum difference 1.42e−14), and sharing apparently equivalent flow intermediates changed signed-zero bytes in a fixed case. Do not normalize intermediate RK quaternions or reorder reductions as part of a performance refactor. M09/M10 are separate from A3's kernel-validation candidate.

### Rejected or deferred alternatives

| Proposal / source section | Reported result | Disposition |
| --- | --- | --- |
| Local gradient replaces displaced cloud relief, §10.1 | Analytic derivative agrees with central differences, yet finite-displacement lighting error reaches 0.573 at low sun and 0.126 near overhead light. | Rejected shortcut: a local tangent changes the finite-distance optical-depth heuristic. |
| **R01**, footprint-aware noise statistics, §10.2 | A two-point moment model improves one conditional-bias statistic, but active-density RMSE remains about 0.039–0.067 against 16×16 supersampled footprints. | Do not ship residual-mean/moment substitution as a filtered equivalent. Filter thresholded density and lighting with a justified footprint/correlation model. |
| **R02**, analytic terrain-wave box filtering, §10.4 | Sinc filtering under constant amplitude and locally affine footprint skips any/all terms in 9.98%/7.68% of synthetic cases within a chosen budget. Filtered slopes themselves differ from current point samples: p99 0.00497, maximum 0.01055. | Separate visual-quality research, not a parity refactor. Perspective and amplitude edges need treatment; use moving supersampled references. A simpler pointwise bound skips all waves in only 1.54% of tested weights. |
| Generic fog pruning, §10.5 | Under sampled defaults, omitting a whole shaded contribution bounded by 0.03 at budget 1/255 becomes eligible only beyond about 5,728 m: roughly 0.017° depression from a 1.7 m camera. | Weak priority for the default pilot view; other fog/aerial cases may differ. Albedo error alone does not bound final shaded color. |
| Unguarded parcel ranking | Float32 distance ties change which material is selected. | Rejected version of M12; only the guarded research route remains. |

### A7 shader experiments at the separate 93ffbb baseline

**Source: [A7, §§7–14][A7].** Use the source section numbers below, not new M identifiers: A2's M01–M12 belong to a different lab. All numerical counts are scoped screens, logical work counts or conditional proofs. A7 supplies no native Metal timing for these candidates.

| A7 section / candidate | Reported result | Conditions, negative controls and disposition |
| --- | --- | --- |
| **§7 — Density interval termination** | With five nonnegative noise weights totaling 31/32, bound unfinished octaves and stop only when local post-cluster coverage proves smoothstep density exactly 0 or 1. Original screens report 105,144,320 parameterized comparisons without CPU differences. One grid skips 44.897% of octave work, or 37.415% including clustering. | Reused coordinates are not independent device observations. Keep complete ambiguous evaluations and raw-noise/tile consumers. Check placement depends on coverage. Unlike A2 M03, this omits internal octaves at saturation rather than approximating the contribution of whole displaced queries. |
| **§7 — C5b conditioned extension** | Bound the remaining 3/32 then 1/32 after cached low octaves. Four active-body/offset scenarios average 4.0781, 2.5404, 4.8447 and 2.3213 requested high octaves instead of six (19.25–61.31% logical reduction). Eighteen scenarios plus offsets show zero CPU bit mismatches; deliberately wrong remaining bound yields 9,717. | Harness computes all octaves and models half-float tile plus ideal interpolation, so it does not time early exits. The earlier 1e−5 normalized margin and later 1e−4 raw-sum margin have different units; neither certifies GPU rounding. Retain outward error bounds, seeds/seams/fallback and valid derivative flow. Proposed nearest/exact-fetch min/max atlas adds 16 MiB/seed and is unimplemented. |
| **§8 — High-octave hash lattice** | A repeated 1024² RG16F atlas stores octave-3/4 corner hashes, retaining original quintic interpolation. Three fully evaluated offsets trade 24 source hash calls for six new fetches plus three existing low-tile samples; +4 MiB/seed. Eight scenarios ×8,192 positions: maximum current-C5b→candidate density/active-relief differences 0.0001339316/0.0002461076. | Keep half-texel offset, explicit LOD 0, seed/readiness fallback, low cache and analytic silhouette. Missing offset/wrong seed cause octave errors 0.62684/0.96920. Hypothetical eight-bit interpolation gives density/relief errors 0.00071239/0.0011220, not a Metal specification. Full-analytic→current/candidate density errors 0.0152022243/0.0152694583 are different comparisons. Direct UNORM modeling does not prove supported texture formats or undo prior half quantization. |
| **§8 — Independent octave mip levels** | Proposed five separately authored lattices, 1024² through 64², total 1,396,736 samples: about 2.664 MiB R16F or 5.328 MiB R32F/seed. Ideal binary16 corner model bounds fBm error by 2^−12 and threshold density by 0.00146484375. | Unimplemented alternative, not ordinary generated mips: octave seeds differ. Actual mip upload/filter support, periodicity, stretched fields, sampler rounding and output lighting remain open. |
| **§10 — Integer hash factoring** | Modular neighbor additions reduce source multiplication spelling from 16 to seven per four-corner query for supported periods 4, 64, 128, 256, 512, 1024. 34,348,032 corner and 1.5 million point comparisons show no CPU bit mismatch with the same wrapped coordinates. | Preserve float wrapping/floor/interpolation and fallback for unsupported layouts. Removing float wrap changes 38,197/250,000 and 19,125/250,000 outputs in two domains. Wrap-once screens do not settle Metal/subnormal/FTZ behavior. This is per-query algebra, not A2 M01 cross-query sharing or the §8 texture path. |
| **§11 — Three-change zero-contribution patch** | At `93ffbb`, patch applicability and full-sky language checks pass: move existing nonpositive sun-disc-dot return earlier; skip directional scatter power when uniform `sun_scatter==0`; skip classic cloud density when its existing horizon fade is zero. | Preserve independent cirrus, notably `0.02 < EYEDIR.y ≤ 0.03`, moon derivatives and layered composition. Skipped work in this patch has no texture/derivative calls. Claim is intended bounded inputs with finite intermediates, not universal bit equality. Alpha-zero layered subtract/subtract expressions need a separate rounding decision; no GPU images/timing supplied. |
| **§12 — Aureole support** | Guarded dot cutoff 0.7071057558059692: zero false culls over 1,977,069 CPU values, 18 conservative retained zeros; unsafe 0.71 cutoff produces 5,840 false culls. | A distinct guard/sample set from A2 M04. Sphere-cap area is not viewport frequency. Keep moon `fwidth` ahead of varying control flow. |
| **§12 — Air-mass algebra** | Remove a sqrt/square round trip using the same rounded horizontal-length square and original clamp. Across 1,101,341 inputs: maximum air-mass difference 7.62939453125e−6, default sun-path difference 5.960465e−7, normalized moon-path 3.576279e−6. | Real identity, not bit identity. GPU dot contraction and inverse-square-root lowering lie outside the CPU model. |
| **§12 — Moon tangent / shared powers** | Cartesian tangent with original trig fallback at squared xy radius ≤1e−12: 550,006 directions, 25,002 fallbacks, maximum vector difference 3.47552e−7. Shared five-multiply chain produces powers 8/12/24; 996,895-input errors about 1.95e−7/2.97e−7/5.96e−7. | Keep longitude for UVs and polar fallback. Share only the same light cosine, preserve no upper clamp and small overshoot. Compiler strength reduction, registers and the moon's small screen area limit expected benefit. |
| **§13 — Pilot distance and hash palette** | Same pilot-distance arguments can be shared with wrapper retained for other consumers. Anti-tiling bounded indices suggest a palette: one million coordinates, indices 0–7, zero differences for the same CPU float32 hash; two hashes potentially removed, both textureGrad calls remain. | No measured speedup. Retain entries 8/9 and dynamic fallback; double-generated constants differ by up to 0.00474655 in supplied controls. Literal-hash dispatch/target folding need GPU equality checks. Uniform pilot-anchor and stable material caches remain proposals needing update/lifetime design. |
| **§13 — Parcel ranking and guarded rejection** | Naive squared ranking changes 6,640 site pairs/1,692 colors in 900,000 adversarial points, maximum raw component difference 0.2948699; 500,000 random points miss the problem. Guard `q > d2*d2*(1+1e−5)+1e−5` preserves IDs/colors across all 1.4 million points while avoiding 45.74%/43.98% logical roots in the random/adversarial sets. | Reject naive exactness claim. Guard is empirical and differs from A2 M12's 1.000001 experiment. Keep original roots/order for potential winners; branch cost may erase savings. Raw color differences precede outer blending/display. |
| **§13 — Shared derivative footprint** | Four scales, 250,000 synthetic quads each, show maximum filtered-noise differences from 1.12057e−5 to 1.75923e−4; scale 37 has two threshold flips. | Distinct screen from A2 M05. Rounded divide/translate before lane differences is not the real chain rule. Preserve derivative legality and qualify moving transitions. |
| **§14 — Warped solar LUT** | 512×1 R16F, 1,024 bytes, `t=sqrt((1−μ)/2)` with texel-center mapping: maximum normalized halo error 0.0006784201 over 820,197 float32 dots; about 0.000237447 after the 0.35 coefficient. Uniform-dot 512-entry error is about 0.35095. | Low priority; ideal interpolation and assumed precision, not final HDR error. Linear clamped/no-mip data and ready fallback required. Replacing halo alone leaves the `acos` shared with the analytic disc, so it adds a sqrt/fetch while removing only the exponential unless separately restructured. Distinct from A2 M02 chord geometry. |
| **§14 — Post-threshold relief bundle** | Baking near/mid/far thresholded densities into RGBA16F costs 2/8/32 MiB per combination at 512²/1024²/2048². At 2048², maximum scalar-relief error is 0.04254 default or 0.04963 clustered low sun; lower resolutions are worse. | Deprioritized for error/memory. Two 32 MiB replacement buffers plus existing 16 MiB tile already total 80 MiB before overhead. Light-ray drift needs invalidation; a +0.05 x-ray change raises default maximum error to 0.08776. This is separate from the corrected old black-texture failure and from A2's local-gradient rejection. |

**A7 §9 polynomial evidence is separate from A2 M11.** It uses the representable endpoint `X=2.1600000858306885`, center `C=X/2`, centered Horner evaluation, and original `exp` fallback outside the domain. An exact rational order-32 Taylor polynomial is converted/truncated in Chebyshev form, then coefficient quantization is bounded. Conditional floating-point bounds additionally cover center subtraction and Horner rounding under stated IEEE round-to-nearest, gradual-underflow and correctly rounded FMA assumptions.

| A7 polynomial degree | Real bound including quantized coefficients | Conditional IEEE-RN FMA bound | Observed host-FMA maximum |
| --- | --- | --- | --- |
| 5 | 2.641706e−5 | 2.660503e−5 | 2.645865e−5 |
| 6 | 2.026621e−6 | 2.214913e−6 | 2.112994e−6 |
| 7 | 1.57923e−7 | 3.46265e−7 | 2.7069e−7 |
| 8 | 4.34325e−8 | 2.31783e−7 | 1.6788e−7 |

The host screen compares 1,250,008 inputs with NumPy binary64 exponential, not interval-certified exact samples. Separately rounded multiply/add bounds for degrees five/six are 2.666935e−5/2.279280e−6; nine host out-of-domain/nonfinite fallback cases pass. These do not certify Metal fast math or NaN payloads. A bounded relief multiplier ≤0.5 halves the corresponding scalar transmission bound before color/postprocessing; A7's cited degree-six 1.013311e−6 is derived from the **real** bound, not the GPU or FMA bound. Native MSL sketches were not Metal-compiled. Degree five/six remain experiments against actual exponential lowering; more degree can increase dependent arithmetic with diminishing rounding benefit.

### A7 larger renderer proposals

**Native-pixel aircraft crop, §15:** render a lower-scale background plus a padded off-axis crop at one physical output pixel per crop pixel, sharing the full World3D and occluders, then composite before native UI. Existing aircraft-only magnifier infrastructure is not equivalent. Actual pinned Camera3D tests cover 96 configurations: 3,168 projection comparisons within 0.0086895 px; 1,056 inverse-ray comparisons within 2.884674e−6; 1,152 clipping checks excluding exact boundaries; matching camera-space depth; 72 wrong-offset controls rejected. These are camera geometry results, not rendered seams or performance.

The off-axis crop's `project_ray_normal()` disagrees in 792/1,056 cases (maximum vector difference about 1.29545); use validated main-camera pixel mapping or inverse projection. A7 also records an off-axis `project_position()` inversion diagnostic failure. Recheck on engine changes. The shaded-area model `s²+p` gives 0.5444 at two-thirds background scale and 10% crop, **not** 45.6% GPU savings: duplicated culling/submission/shadows, postprocessing and composition are omitted. Qualify occluders, motion/padding/hysteresis, large-crop fallback, effects, exposure/fog/depth/LOD, jitter, resize and total CPU/GPU time.

**Native Metal rate maps, §16:** separate row/column rasterization rates are not arbitrary 2D masks or display refresh control. At pinned engine `cafc17a`, ordinary Metal VRS texture creation errors, but external native `MTLRasterizationRateMap` import and render-pass assignment expose a real integration seam. Desktop `Viewport.VRS_TEXTURE` does not automatically connect it to built-in Mobile scene rendering. No native prototype/timing was completed; an engine patch may be needed but was not proven inevitable. Prototype simple-scene import/unwarping, then built-in integration, screen/depth/transparency/MSAA/history consumers and complete-frame benefit. Existing private texture storage, Metal 3 dispatch and transient-buffer TODOs are not standalone optimization results or proof of wasted traffic.

**Layered-cloud bounds, §17:** premultiplied front-to-back transmittance can bound omitted far radiance, but reordered floating-point results and solar occlusion must be covered. `exp(−8*density)` has sensitivity up to eight before solar intensity/display processing; arbitrary alpha cutoff near bright sun is insufficient. Retaining all densities and omitting only negligible far relief is a less aggressive candidate. Classic single-deck weather offers no general multilayer saving; no implementation/timing is reported.

## 6. Reported performance and kernel experiment

### Additional historical cache measurements reported by A7

At its `93ffbb` baseline, A7 describes a stable 2048² RG16F ImageTexture per seed: R holds full five-octave ground/near-grass noise; G holds the unnormalized first three octaves for C5b relief. The last two relief octaves and sky silhouette remain analytic. Base storage is 16 MiB/seed before copies and overhead. The reported stable-texture correction is distinct from readiness/failure qualification.

| A7 historical result | Scope and limit |
| --- | --- |
| Working C2+C5b tile off/on/default: 26.20/23.45/23.44 ms GPU | About 2.75 ms or 10.5% off/on difference in **single profiled runs**, not clean repeated acceptance or a new current-source measurement. |
| Separate 1920×1080 pilot/aircraft-ground stills: maximum difference 2/255, none above threshold | Named still-image scenes only; no moving-flight or sustained qualification. |
| Earlier combined C1+C2+D1: 61 FPS, p95 17.28 ms, p99 29.11 ms | Short diagnostic; p99 still missed the cited screen. It cannot isolate or sum each component's effect. |
| Sky relief disabled: about 2.34 ms less GPU time; historical shoreline D1 about 2.3 ms | Separate diagnostic ablations, not additive savings or candidate guarantees. |
| Mask-only wrapping: 28.40 versus 28.42 ms | Reverted as no useful M1 gain; integer source simplification alone is not evidence of faster rendering. |

The original attribution and Metal/GL results below overlap A7's retelling and are retained once. A7 additionally identifies the R4 host as MacBookAir10,1, macOS 27.0.1, AC power, and reports native-Retina p95 around 27.2–28.5 ms for the short Metal/GL comparisons. These are historical host/workload details, not current configuration claims.

### Apple measurements quoted by A1

These are **existing repository campaign results**, not measurements made during this consolidation or new native measurements by A1. The primary attribution workload used an M1 MacBook Air, seven-core GPU, 8 GiB RAM, Mobile/Metal, Medium scenery, pilot camera, and 2560×1600 display; its short sweep used 10 s warmup plus 20 s observation.

| Workload/change | Reported result | Interpretation limit |
| --- | --- | --- |
| Internal scale 1.0 → 0.5, 4× MSAA | 38.3 → 89.6 FPS, about 2.34× | Strong pixel-work signal, not matched-quality or sustained 1080p acceptance. |
| Main-thread sample / GPU attribution | About 57% waiting on GPU; 28.42 ms total GPU, 22.34 ms opaque | Supports GPU-first investigation in this workload. |
| Hide ground / disable ground cloud shadows | About 11.08 ms / 3.55 ms less GPU time | Separate ablations; savings cannot be added. |
| Separate sky diagnostic, clouds disabled | About 7.59 ms less GPU time | Different diagnostic; not additive to ground results. |
| Hide tested vegetation group | About 0.06 ms difference | Low priority for that view, not every scene. |
| Five short beta2 Metal-versus-GL pairs | 32.2–36.3% higher FPS with Mobile/Metal | Short comparison, distinct from sustained beta1 evidence. |
| Earlier beta1 seven-file bundle; three 30 min runs per role | 17.64–23.17% higher paired FPS; all 73 common complete state/input hash windows match | Candidate p95 about 31.2–31.8 ms and p99 43.8–44.4 ms remain outside intended pacing target. Bundle contains six shaders and lighting WeakRef reuse. |
| Earlier C2 RGBA8 cache | 28.09 → 25.72 ms GPU | Does not qualify later RG16F/C5b default. |
| Retina reconstruction comparison | Native 28.26 ms; MetalFX Spatial at about two-thirds scale 18.68 ms; bilinear at same scale 16.87 ms | MetalFX adds reconstruction cost; stills favored thin aircraft detail, but motion/readability needs qualification. |
| MSAA sweep | 4× → 2× about +2% FPS; disabling about +10% | Workload-specific; preserve thin-edge quality when comparing alternatives. |

Output dimensions and internal 3D dimensions must be recorded separately. At 2560×1600 output, 0.75 scale is **1920×1200**, and roughly two-thirds is **1707×1067**. Neither is actual **1920×1080 output**. Per-axis scale changes pixel count quadratically.

### Stage-validation reuse experiment

The following kernel experiment is independent of A7's rendering profiles and A6 O4's pre-step candidate.

**Source: [A3][A3].** The candidate changes only `app/sim/simulation.gd`. After the packed body-plus-continuous array has passed finiteness checks, it checks quaternion norm directly instead of slicing and rescanning the same 13 body values. A local `verified_joint` fact skips duplicate checks immediately after successful joint validation, only where no callback/mutation intervenes.

The candidate retains calculated-derivative checks, split/body-only checks, and first-stage checks after `model.rotor_momentum`, because that callback can invalidate a previously returned array. It preserves norm expression order/thresholds and has no persistent cache. Future changes must preserve that short read-only interval or revalidate.

| Verification reported by A3 | Scope |
| --- | --- |
| 44,025 derivative-equivalence checks | Seeded packed states, invalid sizes/fields, nonfinite values, signed zero, quaternion thresholds/overflow, and callbacks mutating returned derivatives. |
| 3,840 exact derivative-array comparisons | Four stages over 960 synthetic ticks, including joint, split, and body-only routes, plus stage inputs, outputs, states, loads, and faults. |
| 120 stock joint-stage samples per aircraft | Default Stik, finite-glow Stik, and Avanti; byte fingerprints for loads, continuous/body derivatives, and rotor momentum. |
| Three complete 720-tick flight recordings/replays | Each compares 721/721 rows without divergence. Baseline replay has `solver_changed=false`; candidate correctly has `solver_changed=true`. Exact matched rows do not establish unchanged solver identity or every checkpoint/event/platform case. |
| Nine existing tests pass | Simulation, vehicle model, contact substeps, event protocol/refinement, continuous state, ground-vehicle kernel, helicopter startup, and generalized coordinates. Full CI and rendered/physical validation were not performed. |

Component timing used 16 alternating AB/BA pairs, CPU 0 affinity, an editor/debug engine on a shared Linux host, with all samples/outliers retained. Percentage reductions are medians of paired percentages, **not ratios of the displayed independent medians**.

| Headless workload | Baseline median | Candidate median | Median paired reduction | Pair range |
| --- | ---: | ---: | ---: | --- |
| Packed guard, 1 continuous value | 1.986 µs/call | 1.491 µs/call | 27.13% | −44.48% to +35.96% |
| Packed guard, 4 continuous values | 2.104 µs/call | 1.704 µs/call | 22.04% | −24.21% to +29.35% |
| Packed guard, 25 continuous values | 3.319 µs/call | 2.734 µs/call | 17.59% | −26.75% to +37.61% |
| Synthetic joint-stage kernel | 78.085 µs/tick | 69.973 µs/tick | 11.30% | −4.86% to +22.78% |

Larger headless session comparisons used eight alternating process pairs per aircraft, 120 warmup and 480 sampled ticks. Default Stik's median paired tick-median reduction was **2.25%**; Avanti's was **0.19%**. Paired fingerprints matched, but timing variation prevents a reliable session-speedup conclusion. These runs omitted scenery collision, rendering, presentation/audio, and OS input. Body-only performance, native evaluation, full application, GPU, and target-hardware 1080p gains remain unmeasured.

### Developer handoff opportunities O1–O6

**Source: [A6, Optimization opportunities][A6].** These IDs are independent of A2's M/R register. Preserve existing correctness fallbacks; source-operation counts alone are not timing results.

| ID | Opportunity and reported evidence | Qualification boundary |
| --- | --- | --- |
| **O1 — Native circuit terrain** | At the audited snapshot, auto circuit policy can enable the Club circuit on detected dedicated GPUs at High/Extreme detail. A nonempty track intentionally prevents native stage admission, so a visual-detail choice can also change physics backend. | Implement/qualify matching composed terrain rather than removing the guard. Cover heights, normals, edges, wheels/hull, mutations, replay and fallback; record selected backend. No measured speedup. |
| **O2 — Native companion admission** | Player selects native before setup; companion sessions retain the low-level reference default. Three companions plus player imply 960 model ticks per simulated second at 240 Hz, before stages/substeps/observers. Pilot decisions every fourth tick do not reduce physics cadence. | Apply the same pre-setup capability rules and fallback; O1's track restriction also applies. Qualify traffic, fleet trajectories/recordings, reset/crash and fallback. Lowering physics cadence is a separate numerical change. No measured speedup. |
| **O3 — Prepared hull reach** | Circuit broadphase rebuilds a hull radius with per-point slices/norms; 26 Stik points imply 6,240 such operations/s, or 24,960 for four aircraft. `HullContact.prepare`/`prepare_geometry` already prepare detached geometry and reach. | Reuse only a conservative bound matching live geometry. Define admission/mutation invalidation and rollback; object identity alone cannot guard in-place edits. Profile actual allocation/tick cost; no measured speedup. |
| **O4 — Shared downwash pre-step air** | Same callback/state/time computes air twice: internally through `_wing_cl`, then for speed. One shared result halves wind queries; exact/refusal comparisons and about 42% spatial-weather callback reduction are reported below. | Keep lag formula and supported dispatch, environmental purity, invalid-data refusal and rollback. No cross-stage Air receipt reuse or whole-application speedup claim. |
| **O5 — Prepared wind station geometry** | Unguarded prototype matches 402 sampled comparisons across three normalized models. Eight noisy paired batches give median `stage_air` cost about 247.53→225.00 µs, seven favoring preparation. | **Not ready:** replacing `station_ys[0]` with NaN makes baseline reject while cached prototype succeeds. Timings exclude required guards/invalidation. Establish immutable validated geometry or supported mutation invalidation; continue sampling state/time/wind/density every stage. |
| **O6 — Shared rotor-stage calculations** | Domain precheck and aerodynamic/main-rotor stage overlap hub airflow, transition and advance-ratio work. One fixed-state diagnostic measures entire precheck at 2.187–2.433 µs/call and entire stage at 145.909–157.040 µs/call. | Component costs, not removable-work totals or candidate savings. Preserve rejection classification, domain/finite checks and replay. Lower priority until a tested stage-local candidate shows useful benefit. |

A6 also screened overlapping `Air.compute` work and repeated scalar/state validation without persuasive timing improvement. Those explorations are neither new defects nor production-ready patches; they do not invalidate A3's separately measured validation-reuse experiment.

### O4 measured downwash pre-step candidate

The active lag path requires a valid model, nonempty envelope, horizontal `downwash_lag_length`, and valid auxiliary index. `_wing_cl` returns a dimensional wing lift-velocity proxy in m/s despite its name. A6's replacement obtains one `air_data(s, sim.time())` result for both `Aero.wing_wake_velocity(...)` and speed, retaining the exact first-order lag update. Spatial Stik weather samples datum, six wing stations, both tails and propulsion: ten wind positions instead of twenty per callback.

Original timings used ten alternating batches of 128 warmed fixed-state calls on a shared Intel Xeon Platinum 8573C with the pinned debug editor. Values are **medians of batch-mean callback costs**, not tick-latency percentiles. Fresh reconstruction results stay separate.

| Workload | Original baseline → candidate | Original reduction | Reconstruction baseline → candidate | Reconstruction pairs favoring candidate |
| --- | --- | --- | --- | --- |
| Legacy steady, queries 2→1 | 77.33594→69.67578 µs | 9.9% | 80.65625→75.26172 µs | 7/10 |
| Spatial eight-mode weather, queries 20→10 | 577.63672→331.13281 µs | 42.7% | 605.01172→350.93359 µs | 9/10; about 42.0% reduction |

All original paired batches favored the candidate. Reported production `_kernel_pre_step` checks include 192 byte-identical outputs, 24 accepted integration steps in each weather mode with matching body/auxiliary/continuous/mode arrays, and four matching refusal/rollback cases: invalid legacy datum, invalid spatial datum, invalid station after a valid datum, and pending weather reset.

The direct helper call bypasses potential `_wing_cl` subclass dispatch. A production change must preserve supported dispatch or explicitly establish its contract. Reuse is limited to the same callback, state, model, density and time. Although the GDScript pre-step is shared across backends, no native extension was loaded; native/reference trajectory and refusal qualification remains open. The report does not measure the callback's fraction of full tick time, so **42% callback savings cannot be reported as 42% tick or FPS savings**.

### Extra 300 optimization opportunities E300-03–05

**Source: [A8, §§3–5][A8].** These are distinct from A3 validation reuse, A6 O4 airflow reuse, O5 station geometry, and A2 M09/M10. None establishes a whole-app frame-time gain.

| ID | Mechanism and reported evidence | Remaining qualification |
| --- | --- | --- |
| **E300-03 — Stage-local mass properties** | `point()` computes `_stage_mass_context()`, but stock Extra lacks `fuel_feed`, so no `evaluation.mass` is returned and `evaluate()` recomputes CG, six inertia components and inverse tensor. Ordinary four-stage/240 Hz path duplicates 960 evaluations per simulated second, excluding events/endpoints/observers/contact subdivisions. A qualifying soft-hull query can compute a third time. | Guarded prototype reuses only without feed/feed-line blocks, with exactly zero line fuel and finite main fuel `0 < fuel ≤ capacity`. Ordinary stage calls fall 2→1; qualifying hull stages 3→2. Further ground reuse remains unimplemented. Keep validated private stage context, callback/refusal order, and no reuse across stages or fuel events. Operation count is not measured speedup. |
| **E300-04 — Loft mesh indexing** | `SurfaceTool.index()` before the existing commit reduces repeated vertex attributes. Exact Godot-value comparisons re-expand indices and retain all present attributes, triangle order, mesh path/local transform, before and after custom-paint preparation. | Memory tradeoff: headless construction became slower. Preserve per-instance nodes/hinges/paint ownership if indexing once or sharing immutable meshes. Reject the tested post-commit `create_from()` alternative, whose extra encode/decode changed decoded normals/tangents. Buffer lengths are not total RAM or GPU allocation. |
| **E300-05 — Custom-paint shader sharing** | Stock finish already shares one Shader across five variants. Custom preparation creates 14 distinct Shaders with identical source; representative opaque/untextured paint creates another 14 final Shaders with identical source. | Share immutable Shader resources by exact generated code and relevant alpha/texture variant; retain separate ShaderMaterial uniforms and instance ownership. Not evidence of 28 GPU compilations, measured frame savings, or a qualified `.orskin` import lifecycle. |

E300-03 compares 90 direct stages (72 accepted, 18 refused), unchanged default public `point()` outputs, 48 accepted airborne/engine-cut ticks, 16 runway ticks, and four near-exhaustion ticks with two event records. The existing glow-flight program passes 110 checks on each version. Still open: explicit `point(..., true)` callers, supported callback/mutation behavior, native/reference parity, recordings/checkpoints/replay, other aircraft configurations and controlled full-session timing.

| E300-04 measured buffer quantity | Stock | Indexed candidate |
| --- | ---: | ---: |
| Vertices across distinct mesh resources | 53,204 | 10,878 |
| Serialized ArrayMesh vertex/attribute/index buffers | 1,317,552 bytes | 373,176 bytes |
| Same buffers after custom-paint preparation | 1,825,800 bytes | 1,475,672 bytes |
| Instance triangles | 19,502 | 19,502 |

Stock buffer savings are 944,376 bytes (**71.68%**, about 0.901 MiB/model for those buffers), falling to **19.18%** after the paint adapter expands target triangles. After warmup and 16 alternating Linux headless pairs, median build times are **96.19 ms baseline / 103.24 ms candidate**, with median paired change **+8.5%**. Paired percentages need not equal the ratio of independent medians. Noisy samples do not support faster construction; a memory benefit must be evaluated with its lifecycle cost.

### Corsair optimization opportunities CF-03–04 and negative results

**Source: [A9, §§3–5][A9].** CF-03 is construction-time validation reuse, distinct from A3's kernel validation. CF-04 is offline generation, distinct from M09/M10 runtime physics reuse.

| ID | Reported mechanism/evidence | Qualification boundary |
| --- | --- | --- |
| **CF-03 — Duplicate retract-rig validation** | Imported construction calls geometry validation, which validates the rig; subsequent `Retraction.bind()` immediately scans the same data again. Corsair rig has 101 samples ×17 carrier nodes (1,717 poses), plus 606 wheel-path vectors. Prototype retains public `bind()` validation and uses a private immediately-validated construction handoff. | Preserve scene-dependent unique bindings/parents, rest transforms, wheel helpers and stowed-pose checks. Rig contents must remain unchanged between validation/binding; no stale receipt or cross-build identity cache. Any copying/guards enter the measured cost. |
| **CF-04 — Offline VLM vector reuse** | Matrix entry calls `horseshoe(...)` separately for each of three components although each call returns the full identical vector. Store it once, then retain original multiplication/summation order. For 80 panels and 14 solves, matrix calls fall 268,800→89,600; total including unchanged tail/Trefftz work falls 371,840→192,640. | **179,200 fewer evaluations (48.19%)**, with complete JSON output bytes identical across all heights and both fits; baseline also passes retained-data tolerance. No elapsed-time benchmark and no in-flight execution: this is a generator cleanup, not FPS improvement. |

CF-03's eight alternating pairs with four builds/batch report median batch means **15.9835→8.3696 ms/build**, median paired reduction **49.69%**, range **25.46–67.93%**, all eight pairs favoring the candidate. These are noisy component batch means, not individual-load latency percentiles or ratios of the displayed medians. The candidate passes 21 bind-level and eight synthetic complete-build assertions, covering malformed poses, wheel paths, bindings, transforms and public articulation structure. Fixtures use real generated Corsair geometry inside synthetic hierarchies, **not the actual GLB/textures/materials**. Qualify real Corsair and Avanti construction and the actual selection/start route before claiming loading-time benefit.

| Unpromoted A9 candidate | Reported result | Decision |
| --- | --- | --- |
| Stationary gear-pose cache | 24,850 sampled transform/rest comparisons match, but stowed 37.08→45.74 µs/call, deployed 35.19→44.74, moving 41.75→86.28; every measured pair favors original. | Reject this guarded prototype. Source checks cost more than interpolation. Unchanged extension does not justify skipping `apply()`: restore sampled pose before adding suspension compression. Cheaper immutable-data design remains unmeasured. |
| Legacy gasoline propeller-result reuse | Narrow handoff between propulsion/slipstream matches 291 load/refusal checks. Ten timing pairs split five/five, with changes from −9.91% to +22.53%. | Defer; no reliable speedup. Electric hub inflow is not interchangeable with legacy datum inflow, and shaft torque uses different floating-point operation order. Require suitable profiling and contract evidence before substitution. |

### Extra round two: E300-07 trim-result RPM reuse

**Source: [A10][A10].** The bounded glow level-trim solver already retains `x_rpm` corresponding to accepted Newton iterate `x`. Result construction nevertheless calls `_evaluate()` without that RPM and then `_rpm()` again, triggering two redundant steady searches. Glow equilibrium searches 128 RPM intervals plus engine-table knots, selects restoring roots and bisects them; this is materially more work than reusing the scalar. It is separate from Jacobian RPM reuse, A8 stage-mass reuse and A6 downwash-air reuse.

The candidate passes optional RPM into `_result()` and final evaluation only on the bounded glow level path. Its invariant is `x_rpm = steadyRPM(x)`; rejected line-search trials retain their RPM locally, preserving the last accepted pair even for failed-trim diagnostic exits. Reported independent review covers all five affected result exits. Root selection, equations/tolerances and fallback for glide, legacy and electric propulsion remain unchanged.

| E300-07 case | Original → candidate steady-RPM searches | Removed |
| --- | --- | ---: |
| Extra level trim at 22 m/s | 19 → 17 | 2 |
| Half-power cruise search | 202 → 174 | 28 |
| Excessive-idle refusal | 30 → 24 | 6 |
| Stopped-engine glide | 0 → 0 | 0 |

Half-power search performs 14 finalizations, removing 28 searches (13.86%) with exactly unchanged full-fuel/reference-atmosphere cruise output, including about 32.45912 m/s and 10,784.934 RPM. Work counts are distinct from timing improvements.

| Warm, uncached solver calculation | Baseline median | Candidate median | Median paired reduction / consistency |
| --- | ---: | ---: | --- |
| Extra level trim, 22 m/s | 148.67 ms | 134.18 ms | 10.1%; candidate faster in 24/24 pairs. |
| Extra half-power cruise search | 1,518.48 ms | 1,332.00 ms | 12.0%; faster in 17/24 pairs; paired-reduction IQR about −5.2% to +13.2%. |

Pinned Linux Godot, uninstrumented variants, two warmup pairs then 24 measured alternating pairs per case, with other audit CPU work paused. Paired reductions are not ratios of independent medians. Exact removal of searches is stronger evidence than a fixed 12% gain. Existing launch-trim cache hits bypass the work; model/fuel/atmosphere changes requiring recomputation are relevant. Full startup, FPS, GPU and native-backend cost were not measured.

A10 reports **87 audit checks**, including **34 byte-identical complete results** and unchanged input models; repository trim-integrity **731 checks** and cruise-trim **22 checks**; exact complete-result comparison on all **48 timing pairs**. Cases cover full/10% fuel, reference/hot-high atmospheres, speeds, half-power/warm starts, failed/invalid requests and glide, with legacy/electric/four-stroke controls. Patch applicability passed at `8e5f2f0`; it is a tested candidate, not a current production implementation claim.

### Corsair second pass: CF-07 angle-only flap presentation

**Source: [A12][A12].** `main.gd` rendering consumes only `angle_deg` from `session.flap_state()`, which also calculates an overspeed advisory using airspeed/density. Spatial airspeed prepares the whole Corsair station-airflow structure. A successful full-status read uses **1 wind / 2 density queries** in legacy weather and **10 wind / 2 density queries** in spatial weather (datum, six wing stations, two tails, propeller), including stowed flaps. The angle-only candidate needs **zero of either query**.

The prototype reads accepted actual flap fraction and live maximum angle without a persistent cache. A12 reports **268 parity checks** for invalid auxiliary values, input enabled/disabled, both weather modes, maximum-angle changes and folded-wing hinge transforms, plus a separate short-input fallback check.

| Input-enabled presentation workload | Baseline median | Candidate median | Median paired reduction |
| --- | ---: | ---: | ---: |
| Legacy weather | 62.13 µs | 46.66 µs | 22.39% |
| Spatial weather | 581.47 µs | 46.92 µs | 92.11% |

Each workload has **eight alternating pairs**, **128 calls per batch**, candidate faster in all eight. The external report also retains disabled-input cases and raw batches; the supplied summary does not provide their values. Timings include control-surface/flap/fold updates in a **synthetic imported hierarchy**, excluding remaining rendering, GPU work and physics integration. These are component savings, **not FPS gains**. Use a small shared presentation accessor; HUD/control consumers needing full advisory status must keep it. Real Corsair GLB integration, lifecycle checks and matched full-scene profiling remain qualification work. This is distinct from CF-03 build-time validation and CF-04 offline VLM reuse.

### Incremental UI/UX: OBS-01 Natural Random preparation

**Source: [A13][A13].** Briefing entry and Another flight set busy, generate a scenario, synchronously `setup()`/`reset()` a candidate FlightSession, then clear busy before returning, without yielding a frame. The successful path therefore cannot display its temporary Preparing flight state between those writes. **Scheduling is source-established; perceptible delay is unmeasured.** This is separate from UI-34c Home-to-Fly staging/cancellation/first-frame work and A11's frozen-intro redraw candidate.

Measure accepted-input→visible acknowledgement, generation, session preparation, ready state and longest frame over aircraft/seeds, cold/warm. If material, render acknowledgement first and divide eligible work into bounded units under the existing job owner; one yield does not make later computation asynchronous. Repeated rerolls need request generations to prevent obsolete publication. Any cache validity key must include aircraft/configuration, environment, seed and relevant model/schema revisions. Preserve identical validated scenarios/correct cancellation; no stall duration or FPS gain is claimed.

### UI/UX loading and frozen-intro profiling candidate

**Source: [A11][A11].** Loading stages, cancellation, first-frame checkpoints and Home preparation already exist (`flight_loading.gd`, `flight_scene_load.gd`, `home_flight_preparation.gd`). Native evaluation should distinguish input-to-feedback latency, longest uninterrupted main-thread segment, genuinely rendered ready frame, cancellation acknowledgement/completion, and cold/warm conditions. Resource readiness, scene construction, world preparation and first usable drawing are separate milestones. Keep the dedicated worker until an alternative proves equivalent lifetime/cancellation and pinned-engine behavior; do not infer permission to move arbitrary active scene-tree operations onto a worker.

A11 identifies one **unmeasured, low-priority** candidate: `BrandIntro.seek()` freezes playback while `_process()` still updates shader parameters and queues redraws. Stop frozen processing only with explicit invalidation, including a `status_text` setter/signal so loading/failure messages cannot become stale. No CPU/GPU/frame-time/battery improvement was measured. Preserve the owned Tween, temporary application-processing disable during handoff, and skip-input consumption boundary; this is distinct from measured physics/shader candidates above.

## 7. Follow-up order and acceptance evidence

A10 proposes two independent follow-ups: integrate the bounded trim-result reuse with its accepted-iterate invariant and exact/refusal checks, and repair F5 geometry synchronization with public-route regression. Neither requires aerodynamic recalibration. Retain the separate A8 generator priorities and A10's unresolved aerodynamic observations; current-source disposition must precede applying historical candidate patches.

For Corsair, A9 recommends: repair complete rate-force/moment datum derivation; define shared continuous thrust extrapolation; apply output-preserving offline VLM reuse; then qualify the synchronous retract-validation handoff. Use the [Corsair integration plan](../docs/F4U-PLAN.md) and [aircraft contract](../docs/AIRCRAFT_CONTRACT.md). Physics repairs intentionally change affected behavior and need regenerated data, explained expected results and flight qualification. Work-elimination candidates must preserve outputs/refusals. Keep reference-inventory and live-fuel CG separate; do not require parity with defective physics as the repair criterion.

For the Extra-specific work, A8 recommends **E300-01 and E300-02 before aerodynamic/propulsion retuning**, then completing E300-03 parity and measuring full-session cost. Keep E300-04's memory tradeoff, E300-05 shader sharing and E300-06 presentation correction separately reviewable. Use the [Extra guide](../docs/EXTRA-300-PLAN.md), [aircraft contract](../docs/AIRCRAFT_CONTRACT.md) and existing owning generators; do not hand-edit generated aircraft physics data or hide an intentional physics correction inside a performance patch.

This is a reading and triage sequence synthesized from the reports, not a second implementation plan. Existing owners and step IDs remain authoritative in the [track registry](../docs/README.md#tracks-plans-and-step-ids).

| Order | Follow-up | Authoritative home |
| --- | --- | --- |
| 1 | Reconcile each finding against the actual candidate source; verify the UID/CI history, effective-render validation, diagnostic eligibility, and full rendering identity. | [Apple Silicon performance plan](../docs/plans/apple-silicon-performance.md), [CI/tool index](../docs/tools/README.md) |
| 2 | Triage A6's P1 findings: F1 admission/stepping composition, F2 command validity through pause, and F6 tire/brake passivity. Keep each repair independently reviewable. | [Aircraft Workshop](../docs/AIRCRAFT-WORKSHOP.md), [controller plan](../docs/plans/controller-support.md), [RC vehicle plan](../docs/plans/rc-monster-truck.md) |
| 3 | Resolve F3 observer terrain, F4 connected trials, F5 empty-block compatibility, and A4's separate firing-counter defect. Coordinate F1/F4/A4 event interfaces while retaining distinct acceptance cases. | [Glow engines](../docs/GLOW-ENGINES.md), [fuel system](../docs/FUEL-SYSTEM.md), [flight logging](../docs/FLIGHT-LOGGING.md) |
| 4 | Qualify cloud-cache readiness/fallback and graphical lifecycle, then distinguish ground, sky, layered-weather, and combined cases across supported renderers. | [Apple Silicon plan](../docs/plans/apple-silicon-performance.md), [atmosphere tools](../tools/atmosphere/README.md) |
| 5 | Evaluate A6 O4 first within its measured CPU opportunities, then O3 and guarded O5/O6; qualify O1/O2 terrain/admission coverage separately. Compare A3 and M09/M10 independently where physics cost warrants it. | [Kernel boundaries](../docs/STACK.md#boundaries-and-data-flow), [native-kernel research](../research/native-kernel/README.md), [AI companions](../docs/AI-FLIGHT-COMPANIONS.md) |
| 6 | Test M01, M02, and cheap M03 independently; keep M04 separate. Compare half-resolution clouds as a separate A1 proposal. | [Graphics tools](../docs/tools/graphics.md), [optimization priorities](../docs/plans/optimization-priorities.md) |
| 7 | Use capture to select pass-dependency/ground work; evaluate M05–M08 one at a time, then reconstruction/MSAA quality tradeoffs. Retain M11/M12 and R01/R02 at their lower/research priority. | [Apple technical background](../docs/APPLE-SILICON-TECHNICAL-BACKGROUND.md), [graphics tools](../docs/tools/graphics.md) |
| 8 | Qualify native Mac exports, cold/first-use behavior, recovery, and sustained finalists with actual presentation evidence. | [Shared M1 workflow](../docs/tools/macos-m1.md), [Apple Silicon plan](../docs/plans/apple-silicon-performance.md) |

Additional A1 proposals retained in this sequence:

- **Half-resolution sky clouds:** use stock Godot low-resolution sky passes for expensive clouds while retaining full-resolution celestial/horizon detail and reflection/IBL behavior. Quarter subpass pixel count does not imply quarter total frame cost; test sky-heavy and ground-heavy views, single/layered clouds, moving edges, and solar occlusion.
- **Small shader-variant set:** separate meaningful cloud/detail/screen-depth cases only when unused work actually disappears. Prepare variants before flight and inspect compiled output; uniform branches may already optimize well.
- **Footprint-aware detail:** preserve existing distance/derivative guards, smooth transitions, and coverage. A2's R01 rejection limits naive octave-mean substitution; it does not reject carefully validated filtering research.
- **Screen/depth dependencies:** water, glare, and afterimages can cause full-screen copies, resolves, and pass changes. Compare scenes where the relevant material was never created; hiding it may leave persistent renderer flags.
- **Reconstruction/readability:** at 1080p compare fixed Native, Spatial 85%, and Spatial Quality configurations where supported. Include propellers, gear, control surfaces, foliage, smoke, and fast camera motion.
- **Native Mac shader baking:** A1 identifies macOS export and non-headless baking requirements at its snapshot. Enabling a preset alone is insufficient; verify package behavior and cold Home→Fly/first effects through the owning export workflow.
- **Presentation:** after GPU headroom, compare two-image and default three-image swapchain behavior where supported. Process FPS, GPU duration, input response, and on-glass frame intervals are separate measures.

A7's shader work-package sequence is an additional source recommendation, not proof that it outranks A2's candidates on current hardware: recheck baseline/receipts and contact passivity; isolate the zero-contribution sky patch; test direct-analytic and C5b density bounds separately; test the high-octave lattice atlas; compare degree-five/six transmission polynomials with native `exp`; isolate integer/shared-power/pilot-distance changes; then consider the full-scene aircraft crop and native rate-map integration. O4 and guarded O5 retain their existing CPU entries. Larger engine work needs a captured limitation, minimal supported-path prototype and fallback. Native Mac baking/prewarm remains separate release work.

### Corsair second-pass follow-up

A12 separates three independently reviewable tasks: CF-05 geometric clearance/contact ownership/first-event search; CF-06 dimensional cross-product invariants and local-flow transfer before tuning; CF-07 accepted-state presentation access without unnecessary environmental queries. Preserve the current owning tracks and verify current-source disposition before applying historical proposals. CF-05's constructed accepted ticks do not measure occurrence rate; CF-06 requires the flight-logging baseline/candidate workflow for any actual physics repair; CF-07 needs real-scene integration before claiming user-visible gains.

### Incremental UI/UX follow-up and acceptance

A13 recommends five focused changes: coordinate exit readiness/commitment (UI2-01/UI2-05); separate Settings save feedback and scoped display rollback (UI2-02/03); field-owned Conditions validation (UI2-04); hint/audio/radar consistency (UI2-06–08); then measure OBS-01 before optimizing. Its first priority is UI2-01 followed by paired Settings fixes. Current-source triage and owning tracks remain authoritative.

Acceptance extends existing theme, scale and screen-stack conventions: **1920×1080 first**, larger/ultrawide next, 720p/short windows as fallback; 150%/200% text, wrapped errors with reachable actions, complete normal/hover/focus/selected/pressed/disabled states, and agreement among visible value, label, accessible name and explanation. A13 proposes measured **4.5:1** normal-text contrast over the least favorable scenery as a target, not a result. Recovery feedback must explain outcome, retained work and resolving action; countdown announcements must not overwhelm assistive output. Exercise nested navigation/editing/Back/reopen with real devices, reduced motion and interrupted transitions. Use truthful stage names rather than invented loading percentages. These are acceptance criteria, not extra observed visual defects.

### UI/UX follow-up and native acceptance

A11 proposes: **preserve choices** (F01/F03/R01), **preserve control** (F02/F04/F05), **explain outcomes and meaning** (F06–F09), then complete native acceptance. Check both the player-visible state and stored data: a picker change does not prove saved identity, a bridge command does not prove error-free execution, and a returned screen does not prove usable focus.

At **1080p first**, then higher resolutions and finally 720p fallback, inspect focus versus selection, hover/pressed stability, understandable disabled states, truthful pending/applied/saved/failed status, 200% text/long translations and bright/dark scenery/opaque mode. Use layout containers/theme variations rather than one-language text-width fixes. These are acceptance criteria, not newly reproduced defects. Native rendering, real devices and screen readers remain required; retained historical screenshots do not satisfy this gate.

The end-to-end journey is launch with saved accessibility preferences → configure controller → edit conditions without disturbing unrelated settings → read all Help with that controller → start with responsive feedback → recover input while paused → edit session settings without changing normal defaults → restart/exit with truthful save status. Apply current-source triage before implementing historical recommendations.

### Rendering acceptance

Record source/engine identity, hardware/OS, renderer, **effective** reconstruction/cache/bake state, MSAA, output/internal dimensions, scene/weather seed, camera, and settings. Qualify **1920×1080 first**, higher resolutions second, and 720p only as fallback evidence, following the [repository policy](../AGENTS.md#display-resolution-priorities).

Check raw modified-consumer quantities and final moving images, maximum/distributional errors, seams, unsupported/mismatched seeds, boundaries, lifecycle, and extreme supported settings. A linear-RGB budget of 0.001 is not a guarantee of invisibility or one display code value; HDR, exposure, tone mapping, bloom, and temporal history can amplify visible differences. Budget combined approximations together.

Use clean matched complete-frame A/B pairs, stable power/thermal conditions, and supported GPU/CPU diagnostics collected separately. Compare median and tail times, memory trend, and visual readability. The reports recommend short alternating pairs before sustained finalists, including three 30-minute runs per role. Retain only reproducible winners, then measure their combination; do not add individual percentage gains.

A7 specifies five alternating short pairs before sustained finalists, with p50/p95/p99/p99.9 intervals, slow-frame counts, cold/transition spikes, simulation-versus-wall progress, resource/peak memory, swap/thermal state and final-five-minute behavior. Record dirty-patch, engine/template/package hashes and unavailable signals explicitly. Window points, drawable pixels and internal pixels are distinct. A property readback does not alone prove GPU feature execution; diagnostic captures and clean acceptance serve different purposes. Its cited p95 ≤18 ms/p99 ≤25 ms screens permit missed 60 Hz refreshes and are not universal display-pacing guarantees. A historical 2/255 still comparison is not a general image tolerance. `step_usec` omits some observers/publication, and CPU/GPU durations overlap rather than simply adding.

For A7 cache work, follow accepted simulation time and use owner generations so stale completions cannot publish. Seed-only raw-noise/hash lattices normally evaluate coverage, lighting and drift live; light-conditioned post-threshold bundles additionally depend on coverage, clustering, shape and ray. Do not rebuild for inputs the cached function does not contain. Cover unready/failed/wrong-seed/stale fallback, more than four seeds, layer removal, rewind, dominant-light changes, headless operation and teardown. A GPU blit replacing readback/upload needs valid sky-sampling and transition evidence so it does not reintroduce the old C5 failure.

### Physics acceptance

A6's defect probes succeed when they reproduce the old failure; a successful reproducer receipt is **not a passing repaired-product regression**. Convert counterexamples to assertions of desired behavior. Its F4 diagnostic is not an independent physical oracle, and O4 remains an experimental comparison.

Preserve float64 state, 240 Hz RK4 semantics, model/kernel boundaries, serial reduction order, accepted-tick transactions, refusal behavior, and rollback. Use component-byte/reference oracles before timing, including clean/flapped/tailless cases, nonuniform winds, zero/reverse flow, malformed inputs, NaNs, signed zero, and events. Follow [flight-log baseline and same-tape comparison](../docs/FLIGHT-LOGGING.md), retaining `complete` and `solver_changed` meanings. An intentional new solver or physics law needs its own scientific/replay contract; software agreement does not establish physical realism.

For A6's performance candidates, retain identical aircraft, track, weather, tape and accepted-tick counts; record each vehicle's selected backend/fallback reason, stage/contact/event counts, mean and p95/p99 tick cost with units, allocations, observer and companion cost. Exercise 0/3 companions, circuit off/on, and airborne/runway/contact phases. The 240 Hz interval is 4.1666667 ms, not a measured processing duration. End-to-end 1080p frame qualification remains separate from headless callback results.

## 8. Tools and platform constraints

These are the reports' recommendations and snapshot-specific constraints. Confirm installed capabilities when executing a future experiment; this consolidation did not recheck external tool versions or availability.

| Need | Retained tool/workflow guidance |
| --- | --- |
| Existing app diagnostics | Reuse [tool index](../docs/tools/README.md), [debug bridge](../tools/debug/README.md), collectors, script profiler, and Perfetto output. A2 points to atmosphere density/relief probes, `shadow_map_probe.gd`, real sky consumers, ground/stripe/grass/seam checks, and supersampled linear-light comparisons. |
| GPU attribution | Xcode captures/counters and Instruments Metal/Game Performance tools; inspect installed templates. Metal HUD and GPU-profiler runs are diagnostics. Newer heat maps/shader tools must not become unavailable M1 prerequisites. |
| CPU and memory | Time Profiler/`sample`, Allocations/VM, and Metal resource views; account for overlapping memory views. Tracy/engine tracing requires an appropriate engine build. |
| Version/hardware-specific tools | A1 associates `gpucapture`/`gpudebug` with macOS 27, shader cost graphs/heat maps with M3+, and Processor Trace with M4+. Its Power Profiler reference covers iPhone/iPad, not a Mac measurement prescription. Verify actual availability. |
| Texture/asset work | Existing Godot compression/mipmap pipeline first; `astcenc`, KTX/Basis, and `meshoptimizer`/`gltfpack` only when evidence supports the bottleneck. Pin versions and preserve aircraft node/hinge names. Cache noise compression/filtering needs separate nonlinear-coverage/relief checks. |
| Engine/platform changes | A1's pinned engine instantiates a Metal 3 driver; Metal 4 and memoryless depth/MSAA changes require engine work, not an assumed project toggle. Check sampling/copy/resolve lifetime before changing attachments. |
| Precision and specialization | `mediump` alone does not prove desired Metal half arithmetic. Inspect generated code; protect coordinates, periodic boundaries, thresholds, HDR, and angular differences. A uniform is not automatically a Metal function constant. Query capabilities/SIMD width instead of hard-coding them. |
| Native CPU optimization | ARM64/Neon, Accelerate/vDSP/vForce, PGO, and ThinLTO are conditional on measured workloads and exactness. The cited `nk::R` implementation targets GCC/x86-64/SSE2; arm64 requires a real port and platform oracles. Keep independent arithmetic separate from ordered reductions. |

A1 warns that `-fno-fast-math` alone may leave FP contraction enabled. A2 warns that some fast double-precision vector functions can offer much less than binary64 accuracy. Neither double storage nor a real-arithmetic identity guarantees byte parity. Preserve effective arithmetic flags and scalar reference behavior instead of enabling global fast math.

A7 reports the pinned rendering driver using `MathModeFast` and SPIRV-Cross MSL ignoring `RelaxedPrecision`; its conditional arithmetic bounds therefore require actual emitted-operation checks. Rendering math policy is separate from simulation's contraction/float64 contract. Its polynomial construction actually used exact-rational Python and a compiled C harness: FPCore/FPBench, Herbie, Sollya and Gappa are researched tools, and Herbie/Sollya/Gappa were not run. The polynomial is Chebyshev truncation, not a Sollya minimax result. `metal-cpp` exposes APIs rather than automatically optimizing Godot; runtime ImageTexture data is not automatically covered by static import compression. Native PGO needs representative training and held-out validation; QoS is not portable named-core pinning. A7 also retains exported-app fullscreen/Game Mode verification, fixed reconstruction presets before dynamic resolution/hysteresis, and the distinction between display interpolation, simulation rate and input latency.

Primary technical references, frozen source URLs, and derivations remain in [A1][A1] and [A2's reference section](mathematical-optimization-lab.md#references), including Apple, Godot, LLVM, Arm, Khronos, and procedural-noise/filtering research.

### A13 engine-reference scope

A13 reports checking relevant contracts against exact beta engine source `cafc17a192acf67903910a68aeb3c076c0907a4b`; 4.7 tutorials supply guidance, not frozen beta guarantees, and rolling latest docs are not treated as the contract. Its retained references cover deferred focus after layout, `_input` before GUI processing, container-owned layout, shared themes, node-bound Tween lifetime/pause semantics and actual screen-reader validation.

For loading, A13 notes early `load_threaded_get()` may block and exact-beta repeated requests retain references released by result collection. Logical cancellation should suppress obsolete publication while collecting submitted work at terminal completion; indefinitely abandoning results is not a complete lifetime policy. These are attributed research conclusions, not new engine experiments performed in this consolidation; exact links remain in A13.

## 9. Evidence availability and original-file fingerprints

### What is supplied here

This directory contains thirteen source Markdown files and this consolidated document. The reports reference additional deliverables, but those deliverables are **not included in this directory**. Their reported results are retained as source claims; the raw experiments were not rerun or independently inspected for this consolidation.

| Source | Referenced material outside this Markdown set |
| --- | --- |
| A1 | A linked `OpenRC_Apple_Silicon_Audit_2026-11-05.pdf`, described as 16 pages/55 references; GitHub source/CI and repository campaigns. The PDF's external library link remains in A1; its contents were not available in this folder. |
| A2 | `OpenRC_Mathematical_Optimization_Kit.zip`: portable probes/results under `angular/`, `noise/`, `ground/`, `native/`; uncompiled `sketches/`; `source_manifest.json`; `verification.json`; runner and pinned requirements. A2 §13 gives reproduction instructions for that kit, not for this Markdown-only directory. |
| A3 | `candidate.patch`, derivative/stock-stage probes, three flight recordings, checked-runner receipts, raw component samples, and `session_timing_no_scenery/`. |
| A4 | `audit_glow_fill_fire.gd`, `audit_glow_event_fire.gd`, `audit_propeller_roll.gd`, and checked receipts `glow-fill-fire-final-2b57tyi5`, `glow-event-fire-isolation-eusbtkbz`, `energy-import-cifyj0rq`, `roll-power-final-ubv7kj98`. |
| A5 | `probe_piece_arms.gd`, `probe_stall_selector.gd`, the isolated one-expression diagnostic `aero_sign_probe.gd`, and `checks/piece-arms-*` / `checks/stall-selector-*` receipts. |
| A6 | `OpenRCsimulator-audit-3df2791.zip` (F1–F5, manifests, original/packaged receipts, `run_audit.py`) and `OpenRCsimulator-math-audit-3df2791.zip` (F6 scalar/energy/driving/refinement, traces, O4 `prestep-candidate.patch`, exact/refusal/timing results, O5 exploration and additional controls). Both archives and their extracted directories are absent here; the second is distinct from A2's similarly themed Optimization Kit. |
| A7 | `OpenRC_Apple_Silicon_Experimental_Kit_2026-11-05.zip` (66 entries) and `OpenRC_Mathematical_Optimization_Lab_2026-11-05.zip` (69 entries, manifest covering 68 payload files), plus the original Apple PDF and separate `OpenRCsimulator-math-audit-3df2791.txt`. These are reported artifacts, not supplied here. Neither shader ZIP contains the later CPU harness, and A7's math ZIP is distinct from A2's `OpenRC_Mathematical_Optimization_Kit.zip`. |
| A8 | `Extra300_Audit_e72d878_2026-11-06.zip`, described as the full report, scripts, experimental patches, raw results and checked receipts. Only the pasted report was supplied here; its `sandbox:/workspace/...` link is an external-session artifact reference, not a local package. No archive or raw receipts were inspected for this integration. |
| A9 | `F4U_Corsair_Audit_84f4657.txt` (complete report) and `F4U_Corsair_Evidence_84f4657.zip` (probes, isolated prototypes, raw measurements, checked receipts, hashes and replay helper). The supplied summary links external ChatGPT-library files; those linked artifacts were not supplied locally or inspected here. |
| A10 | `Extra300_Audit_Round2_8e5f2f0_2026-11-06.zip`, described as complete report, trim candidate/variant builder, probes, raw pairs, fixtures, F5 transcript/logs, checked receipts and invariant review. Only the pasted text was supplied; its sandbox link is an external-session artifact reference, not an available local ZIP. No package or raw run was inspected/reexecuted for this consolidation. |
| A11 | `OpenRC_UI_UX_Audit_2026-11-06.pdf` (described as an 18-page complete review) and `OpenRC_UI_UX_Evidence_2026-11-06.zip` (fixtures, logs, settings differences, source identities, replay instructions and machine-readable findings). The pasted report preserves their external ChatGPT-library links; neither deliverable was supplied locally or inspected for this consolidation. |
| A12 | `F4U-CORSAIR-NEW-FINDINGS-3751e35-2026-11-06.md` (approximately 5,000-word detailed handoff) and `F4U-CORSAIR-EVIDENCE-3751e35-2026-11-06.zip` (report, probes, raw measurements, checked logs, hashes and replay instructions). Only the pasted summary is supplied; its external ChatGPT-library artifacts were not downloaded or inspected for this consolidation. |
| A13 | `OpenRC_UI_UX_Incremental_Audit_2026-11-06.pdf` (19-page report) and `OpenRC_UI_UX_Evidence_2026-11-06(1).zip` (probes/logs/hashes/reconstruction/prior-audit comparison). External ChatGPT-library links remain in the original; only the pasted summary is supplied here. Neither linked artifact was inspected or replayed. |

### A13 evidence boundary

A13 reports **seven final component witnesses**, successful with zero recorded engine errors/warnings; passing assertions reproduce defects rather than establish repairs. A separate current headless app reproduces the three Settings/Conditions issues and completes Home→Fly→Pause→Restart flight→Return to Home, returning focus to Fly and shutting down cleanly. The environment used the disclosed reference-physics fallback. Final garage quit was intercepted; the complete Workshop trace-failure→Stay consequence is source-inferred. Native rendering, physical controllers, audible output, screen readers and target-hardware loading cadence remain unverified. No additional typography/alignment/contrast/clipping defect or native presentation pass follows from these results.

### A12 evidence boundary

A12 reports **10 original successful checked-run receipts and seven fresh reconstruction receipts**, all complete with zero engine errors/warnings. Reconstruction covers import plus six diagnostics, **not another benchmark campaign**. These remain author-reported results; no raw receipts or full linked report were inspected or replayed here. The closing `8423393` source comparison does not move the executed baseline from `3751e35`. Bounded negative results (sampled flap-lift sweep and aerodynamic power screens) and unpromoted observations are mentioned without enough supplied detail to expand into findings. No production changes, physical Corsair validation, encounter-frequency estimate, complete rendering/FPS or native acceptance follow from this handoff.

### A11 evidence boundary

Only the supplied Markdown is integrated. A11 separates actual headless application reproductions (F03/F06), production-component mechanisms (F01/F02/F04/F05 and R01), and source-only accessibility findings (F07–F09). No fresh native graphical window, physical controller, screen reader or renderer benchmark was available; retained captures are historical. Full-route saved-profile editing, a failed-sky transaction, native visual/accessibility acceptance and frozen-intro performance remain unverified. No production source was modified by the review, and this consolidation neither reruns the fixtures nor establishes current repair status.

### A10 evidence boundary

A10's solver evidence consists of reported headless numeric/result comparisons and warm uncached timings, while its F5 evidence uses the actual application route through debug-bridge key events in headless runs with disclosed landscape UID fallback warnings. Keep those evidence classes distinct: the report does not establish rendered-pixel, target-device GPU, full-startup or native performance, long-flight replay or physical aircraft/tank validation. The short fuel replay and successful setter intervention do not broaden those limits. The original attachment is preserved verbatim.

### A9 verification boundary

A9 reports replaying eight packaged diagnostics and two imports in fresh isolated projects with required markers, `ok=true`, `complete=true` and zero engine errors/warnings. Portable VLM replay reproduces exact output comparison. Those are reported software/mathematical consistency results, not newly run checks in this consolidation. Full flight-tape comparison, native qualification, actual imported-scene timing, rendered behavior and independent aircraft measurements remain outside the audit. The original attached summary and its external deliverable links are preserved verbatim; no production fixes are claimed.

### A8 evidence and source-link limits

A8 reports 13 successful checked-run receipts with completion and no engine diagnostics, including 29-check moment-reference and 46-check propeller witnesses, mesh/direction comparisons, stage-parity pair and selected existing tests. These are author-reported headless production-code consistency results; they do not establish real Extra 300S fidelity, current fixes, full regression coverage, rendered/target-GPU behavior, native parity or full flight-log qualification. Its one paint-adapter link spells a shortened commit; use the full reviewed `e72d878b6b4a89209dfe1a992ba119921dcdd34c` identity when locating that source. The original attachment is preserved verbatim.

### A7 reproducibility and evidence limits

A7 reports checking its recovered mathematical archive against `MANIFEST.json` when assembling that handoff. This consolidation has not received or verified those archives. Its source/reference map is largely plain-text labels in the supplied Markdown; those labels do not grant access to saved artifacts or constitute locally available probes.

| Package | Retained layout and reproduction boundary |
| --- | --- |
| Earlier experimental kit | `bounds_prototype/`, `cloud_prototype/`, `solar_prototype/`, `relief_cache_prototype/`, `crop_projection_prototype/`, `metal_research/`, `verification/`. `run_cpu_screens.py --repo ...` and optional `--only lattice`, `solar`, or `relief-cache`; repository/engine not bundled. Five shader-wrapper front-end checks and separate actual Camera3D-method receipts are reported. |
| A7 mathematical lab | `interval_noise/`, `exp_polynomial/`, `integer_noise/`, `angular_algebra/`, `grass_algebra/`, `exact_support/`, `verification/`, `run_cpu_experiments.py`, `MANIFEST.json`. Python/NumPy plus C11 compiler/libm as `cc` for polynomial screens; some groups require the pinned repository. Commands were checked on Linux, not qualified for macOS. Launcher regenerates retained JSON/logs: use a copy to preserve shipped evidence. |

The mathematical lab reports seven resource checks: original and modified full sky, integer, guarded-parcel, palette, angular and polynomial wrappers, with zero errors/warnings and `OPENRC_MATH_SHADER_LANGUAGE_PASSED`. The later interval experiment is **outside those seven resources**. Dummy-renderer uniform-list/front-end validation is not Metal compilation, actual texture sampling, image parity or GPU timing. The non-mutating patch applicability check belongs to `93ffbb`; rebase rather than blindly applying the patch to current source.

Reported archive SHA-256 values (not recomputed here):

- Experimental kit: `3c80742fec67e43720ebe43716385688506186d5f696432594c268ba30b8bc73`.
- A7 mathematical lab: `7ebb1ea430f1c601596cd94f7a3ce8827a44af30dbe2d6edd508d68234fa516d`.

### A6 reproduction and package limits

The handoff describes wrappers that verify the exact engine and a 654-file application manifest, then create isolated runtimes with reduced project configuration and generated import/UID metadata. The first also copies three Workshop JSON dependencies into the required adjacent-assets layout. The original performance harness separately used 226 matching tracked GDScript files. No native extension was loaded. Relative artifact links in `developer-audit-remediation-2026-11-06.md` require the two extracted archive directories beside it; their instructions do not make those absent files available here.

| Wrapper | Cases and interpretation |
| --- | --- |
| `OpenRCsimulator-audit-3df2791/run_audit.py` | F1–F5 cases: `workshop`, `aux_pause`, `track_statistics`, `glow_timing`, `empty_log`. Repeated `--case` selects cases. `--allow-changed-source` records mismatched names/context, not replacement hashes; retain candidate hashes separately and do not call it exact baseline reproduction. |
| `OpenRCsimulator-math-audit-3df2791/run_audit.py` | `scalar`, `energy`, `truck_drive`, `wind_pair`, `wind_refusal`; optional `truck_refinement` runs 240/480/960 Hz. Generates O4 only inside its isolated runtime, verifies baseline hashes, and has no changed-source override. |

A6 provides full commands using `--repo`, `--godot`, and `--output`; both require fresh output runtimes and the pinned source/engine. Use the original instructions once the packages are available, adapting desired-behavior checks to the owning workflow for repairs. Check completion, `ok`, diagnostics, required markers and source context; receipt `elapsed_seconds` includes process startup/import and is not physics timing.

A6 reports a fresh reconstruction completing import and the five default second-pass cases with zero errors/warnings. First-pass receipts retain existing model warnings and expected calibration-overlap warnings. This consolidation did not inspect those raw receipts or rerun them. The handoff claims no rendered UI, hardware controller, native execution, full suite, full flight envelope, sustained circuit landing, GPU campaign, or independent physical validation.

Failed/aborted attempts are explicitly excluded from accepted evidence: A3's initial component benchmark reused a mutable body-derivative array and failed reset; its full-scenery probe was rejected for missing sparse-checkout textures/GLTF despite Godot exiting zero. A4's initial `roll-power-8_iqjz9_` diagnostic failed on unsupported formatting; the corrected run is separate. A4's isolated import had two unrelated translation warnings and no errors. Do not convert these failed attempts or warnings into accepted timing runs.

### Identity details retained from the reports

- A3 baseline `app/sim/simulation.gd` SHA-256: `56953f116a293a984cbc5315b9cd97dc156e63cdd98c12fbc041e6df6baaab92`.
- A3 candidate SHA-256: `d6fca823652f3f78957517a6efb20898c8acb0b86e3f125d5a8748ff3ecf6255`.
- Godot executable SHA-256 reported by A3/A4: `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`.

### Original-file SHA-256

These hashes were calculated from the supplied files at intake. They identify the thirteen retained source reports, whose content is unchanged by renaming; they do not authenticate the external experiments. Git checkout may convert line endings: A1–A5 match their recorded hashes after CRLF→LF normalization; preserve intake hashes rather than rewriting provenance when checkout bytes differ only in line endings.

| Source/files | SHA-256 |
| --- | --- |
| A1 — `apple-silicon-performance-audit-2026-11-05.md` | `db9cb4648737dc680459e29d002d7bbc7374c003865e2710cb3f8d04a1b03ea2` |
| A2 — `mathematical-optimization-lab.md` | `f43f138f605096480e74316bd18131b5d2e99e6e185f1b30f9088f224226e60c` |
| A3 — `stage-validation-reuse-experiment.md` | `0ddf88bb146f2f085204f54baa548b0c830260866eec81d0e133ddeb9690906a` |
| A4 — `propulsion-energy-audit-2026-11-06.md` | `de18844f4ebb42c3c12f4fb0a7d4c7d5425e9715979c431f6dca7f06fe89a3fe` |
| A5 — `fixed-wing-aerodynamics-review.md` | `33d19505c21a0c40ec5c7ec6162665d38322c15e10e16f8179b254016281e699` |
| A6 — `developer-audit-remediation-2026-11-06.md` | `dc5adfd6cb64860fa1ec948f002e1ffac47c16c458d875922b403104ee7c7120` |
| A7 — `apple-silicon-metal-optimization-handoff-2026-11-06.md` | `1eb780371898d91a5afec6052be9289fd900101633251ea66919da680c0b8f1b` |
| A8 — `extra-300-physics-optimization-audit-2026-11-06.md` | `af7109d1bf85e7bcdb1d3106b9aada79850e1c5f944ea9f0eb2f75f15ad326a0` |
| A9 — `f4u-corsair-physics-optimization-audit-84f4657.md` | `4626555a8dc24e3f496d5be8b88dbd9048e049c9638a2e82163f78252e757cc7` |
| A10 — `extra-300-round2-trim-reload-audit-8e5f2f0.md` | `1ae35fc0deb7d1b52b0308f4bf89534aec8930b65a5d942e4dea054b1255bf48` |
| A11 — `ui-ux-accessibility-audit-2026-11-06.md` | `113ce2b6d4e9fd16f2335bb6ad32902a2c0e50b7f6f3adcc06e7bcad01c910b0` |
| A12 — `f4u-corsair-collision-flaps-presentation-audit-3751e35.md` | `af7c91b4ffc2ca650f239f8d210822d0991466bce2f4c35f675f79f94f4fd21e` |
| A13 — `ui-ux-round2-exit-settings-feedback-audit-3751e35.md` | `a9bfddbdf4ca67ed4c10fe3074ba0adac19f38030e600577fe4c6f65674a16d4` |

[A1]: apple-silicon-performance-audit-2026-11-05.md
[A2]: mathematical-optimization-lab.md
[A3]: stage-validation-reuse-experiment.md
[A4]: propulsion-energy-audit-2026-11-06.md
[A5]: fixed-wing-aerodynamics-review.md
[A6]: developer-audit-remediation-2026-11-06.md
[A7]: apple-silicon-metal-optimization-handoff-2026-11-06.md
[A8]: extra-300-physics-optimization-audit-2026-11-06.md
[A9]: f4u-corsair-physics-optimization-audit-84f4657.md
[A10]: extra-300-round2-trim-reload-audit-8e5f2f0.md

[A11]: ui-ux-accessibility-audit-2026-11-06.md

[A12]: f4u-corsair-collision-flaps-presentation-audit-3751e35.md

[A13]: ui-ux-round2-exit-settings-feedback-audit-3751e35.md
