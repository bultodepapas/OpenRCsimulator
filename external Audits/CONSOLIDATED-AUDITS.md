# External audits — pending work

Updated **2026-11-06**. This is the active queue, organized by area. Delivered changes and their evidence moved to [COMPLETED-AUDIT-WORK.md](COMPLETED-AUDIT-WORK.md). The 19 original reports remain unchanged in this folder and retain detailed reproductions, derivations, measurements and limits.

**Read status carefully:** entries require implementation, investigation or qualification. Reproduce historical findings against current source before editing; an old report is not proof of a current failure. Implemented work is removed from the implementation queue even when native/physical/release gates remain; those gates are listed separately below. Concurrent unverified edits are not classified as completed.

Each finding row includes an **Original report** link; implementation evidence remains separate from its originating audit.

## Contents

1. [UI, settings and player flows](#ui-settings-and-player-flows)
2. [Aircraft and helicopter correctness](#aircraft-and-helicopter-correctness)
3. [Performance candidates](#performance-candidates)
4. [Research and physical validation](#research-and-physical-validation)
5. [Remaining qualification](#remaining-qualification)
6. [Sources](#sources)

## UI, settings and player flows

Prioritize preservation of player work, exit decisions and control continuity. Source IDs scope finding numbers; A6 F1 and A11 F01 are different issues. Priorities retain report recommendations. Detailed old-state witnesses are in each linked original.

### Settings, help and accessibility

Source: [A11][A11].

| Pending item | Action and acceptance boundary | Original report |
| --- | --- | --- |
| **A11 F03 — P1, Moon persistence scope** | Stage and validate Moon with all lighting fields under one route-aware persistence owner and save outcome. Check normal defaults survive Natural Random restart/end and direct-flight edits; direct flight must avoid normal preference access and errors. Moon being committed before later operations creates a source-level partial-transaction risk; a player-triggered failed-sky transaction was **not reproduced**. Rejected combined edits must remain atomic. | [A11 original][A11] |
| **A11 R01 — P1, wind preset overwrites air** | Scope and merge only owned fields. Wind-only presets must preserve custom and standard-column atmosphere through Apply/reload; Cancel preserves the draft. Hot and high, Cool dense air and Standard dry ISA column intentionally own atmosphere: retain and disclose their composite effect. Removing atmosphere from every preset would be incorrect. | [A11 original][A11] |
| **A11 F04 — P2, gamepad Help scrolling** | Route selected/remapped-pad scrolling while the reading region is focused, or expose navigable controls. Retain device filtering against RC axes and direct Close/Back. Test every section in English/Spanish at both scales, repeat/limits/reopen/close, keyboard Home/End/Page keys and mouse wheel. Distinct from earlier Help organization and keyboard tests. | [A11 original][A11] |
| **A11 F05 — P2, Back captures editing keys** | Let editors consume ordinary editing keys before remaining shortcuts, or guard focused editors. Test actual saved Backspace and printable-key mappings, typing/deletion, Back after editing, modifiers, capture, popups, recovery and controller Back. Relates to UI-30 SC-5 Escape/dirty-draft work but adds an editing-key conflict. | [A11 original][A11] |
| **A11 F06 — P2, invisible language-save failure** | Report accepted/session-applied/saved outcomes to the active screen, not only Home. Explain failure in the selected language, give reason and Retry when possible; preserve newer-file protection. Test protected and unwritable destinations, unchanged file, and successful save clearing stale error. A specific missing-error route, not another broad transaction-model finding. | [A11 original][A11] |
| **A11 F07 — P2, startup text scale and semantics** | Keep branding, use lightweight semantic status/Skip and validated saved scale without importing the heavy application graph. Native acceptance: 100%/200%, English/Spanish/CJK, reduced motion on/off, loading/error announcements and keyboard/pad Skip. The skip event must not also activate Fly after handoff. | [A11 original][A11] |
| **A11 F08 — P2, instrument explanations** | Wrapped explanation follows focus and hover, with localized accessibility description where appropriate. A keyboard/pad user must discover purpose and limits of every instrument without a mouse, including 200% text. Actual assistive-technology output remains untested. | [A11 original][A11] |
| **A11 F09 — P3, arrow-key text equivalents** | Retain graphics with localized semantic names or a coherent action-row instruction; avoid duplicate announcements. Inspect the accessibility tree and listen to all four directions/actions using target-platform screen readers, translations and changed keyboard layouts. A debug snapshot alone cannot qualify this. | [A11 original][A11] |

### Exit, drafts and feedback

Source: [A13][A13].

| Pending item | Action and acceptance boundary | Original report |
| --- | --- | --- |
| **UI2-02 — P2, countdown erases failed-save feedback** | Separate persistent save outcome from countdown activity. Preserve safety deadline; error survives frames/ticks until success or resolution. Check immediate failure, next frame, multiple ticks, retry success and expiry, explaining restored display and remaining unsaved work. Distinct from A11 F06's language-save error sent only to Home. | [A13 original][A13] |
| **UI2-03 — P2, display expiry discards unrelated drafts** | Separate saved state, current draft and known-good display baseline. For trial keys T, restore only `D'[k]=B[k]` when k is in T; otherwise retain `D[k]`. Reapply combined draft and recompute dirty state. Preserve explicit Revert all. Test edits before/during countdown, repeated display changes, failed Keep, expiry and deliberate full reversion. | [A13 original][A13] |
| **UI2-04 — P2, Conditions diagnoses visible tab** | Return owning tab, field ID, error code and localized explanation; reveal/scroll/focus the field after layout and preserve other edits. Proposed matrix covers each invalid-origin tab against Apply from all five tabs, empty/pasted/out-of-range values; only wind→Time of day was reproduced. Separate from UI-30 error-color work. | [A13 original][A13] |
| **UI2-06 — P3, hidden keyboard hint expires** | Count only visible, relevant, advancing exposure; retain time during pause/controller ownership/loss. Test controller-first→keyboard, switching, pause, loss/recovery, dismissal and preference reload after valid completion. Separate from broader first-run tutorial work; future per-input guidance may need per-family completion. | [A13 original][A13] |
| **UI2-07 — P3, hidden tabs miss focus cues** | Subscribe eligible interactive controls to future focus independently of initial visibility; keep active-surface/visibility/deliberate-navigation gates at signal time. One cue per eligible deliberate move, none for silent autofocus, no duplicates after repeated switches. Keep policy in shared observer. | [A13 original][A13] |
| **UI2-08 — P3, radar cardinal localization** | Reuse cardinal translation policy/strings, shared provider if needed; leave bearing/heading math unchanged and invalidate cached face on locale/font change. Compare English/Spanish/German/Japanese at initial/live locale changes, glyph fallback, centering and larger text. Distinct from stale-localization-on-change findings. | [A13 original][A13] |

### Workshop, launch and history

Source: [A14][A14].

| Pending item | Action and acceptance boundary | Original report |
| --- | --- | --- |
| **A14 F12 — P2, unreadable builds appear absent** | Return usable summaries plus read diagnostics. Distinguish empty, filtered-out, partially unreadable and root-access failure; show healthy builds and unavailable entries with Retry/Details. Cover damaged/mixed records, valid/invalid backups, root failure and Favorites; preserve unreadable originals. | [A14 original][A14] |
| **A14 F13 — P2, helicopter launch rejection hidden** | Put launch status beside shared Fly outside page-specific containers. Preflight known incompatibility while retaining authoritative runtime validation. Offer Review Conditions; preserve airplane weather choices. Test Flight/Aircraft entry, supported/refused conditions, cancellation versus failure, focus/translations and actual tree visibility, not text alone. Logical viewport does not establish native rendered acceptance. | [A14 original][A14] |
| **A14 F15 — P2, deletion durable but screen stale** | Distinguish refused-before-commit, committed/cleanup-pending and completed. After commitment publish verified survivors and invalidate queries, or explicitly make history unavailable until safe forward recovery. Update actions with data. Screen/counters/cached and uncached queries/HUD must agree with durable state or explicitly report unavailability; choose error wording from established commitment state. | [A14 original][A14] |
| **A14 F16 — P2, flight context missing or misattributed** | Schema-aware record-to-view adapter and capture effective accepted configuration at admission. Show scenario/practice context, expanded seed/settings, actual failure events separately from enabled practice and exact airborne seconds. The 42-second fixture shown only as `<1 min` is a smaller extension, not another major finding. Unknown/unreliable legacy context stays unknown. Test ordinary/Random, enabled/disabled practice, deliberately mismatched preferences, legacy/translation and real store round-trip. | [A14 original][A14] |

### Pending presentation edits and navigation

Source: [A17][A17].

| Pending item | Action and acceptance boundary | Original report |
| --- | --- | --- |
| **UI3-01 — P1, Lighting pending state missing from history/recovery** | Preserve complete pending zone/effects values, validation and flags through unrelated history/recovery; require explicit Apply/Cancel if transition invalidates draft. Test real controls and accepted values, pending values, dirty state and action availability independently. Unlike A13 UI2-05, snapshot exists but payload is incomplete; unlike A14 F10, trigger is history restoration rather than preset replacement. | [A17 original][A17] |
| **UI3-02 — P2, Discard/load retains outgoing Smoke** | Validate target, commit replacement, clear all outgoing pending presentation buffers, configure from target and reconcile identity/dirty/actions before success. Canceled/failed load preserves complete outgoing draft. Complementary to UI3-01: ordinary edits preserve buffers, authorized successful replacement clears them; blanket clearing on refresh worsens Undo loss. | [A17 original][A17] |
| **UI3-03 — P2, refused navigation selects wrong destination** | `_active_page` authoritative; one helper reconciles both presentations on acceptance/refusal, preserving pending-field focus/scroll. With `set_pressed_no_signal()`, synchronize every grouped button because it does not unpress peers. `allow_reselect` alone leaves false indicator. After resolution, one destination selection must open it. | [A17 original][A17] |
| **UI3-04 — P2, invalid first color disables Cancel** | Pending enables Cancel; validity determines Apply. Refresh on every empty/partial/invalid change, retaining raw text until resolved. Regression must activate **visible Cancel**, not merely invoke the cancel method as existing Lighting test does. Distinct from UI3-03's selection mismatch. | [A17 original][A17] |
| **UI3-05 — P3, short-window preview focus loss** | Transfer only focus belonging to replaced controls (to Camera on collapse, suitable inline action on expansion); preserve unrelated focus, avoid continual grabbing. **390–400 px-high compatibility witness**, not 1080p visual defect; schedule after primary 1080p issues. | [A17 original][A17] |

### Related work without a new defect count

- **A17 Companions:** separate status refresh from draft initialization, preserving volume/labels/distance. Original used a solo-flight active-count fixture because enabled profile admission failed; verify real active traffic before closure. Original reports: [A17][A17].
- **A14 paint observations:** recognizable same-label cards, explained incompatible-skin fallback, localized actionable errors and practical inventory recovery. Real package/upgrade cases remain unverified; preserve existing legacy exception. Original reports: [A14][A14].
- **A18 player journeys:** correct failure-setting lifetime/Restart copy and show practice near Fly; disclose save-before-calibration; show resolved aircraft/field/start beside Fly; add state/vehicle startup guidance and radio-profile prerequisites. Use existing owners and resolver, not duplicate rules/tutorials. These are cognitive-walkthrough hypotheses, not a participant study or seven defects. Original reports: [A18][A18].

## Aircraft and helicopter correctness

### Shared kernel and ground vehicles

- **A6 F6:** enforce dissipative coupled tire/brake constraints; preserve static reactions, force limits, combined slip, reversal/load loss, rollback, stage-integrated energy and backend parity. Positive tangential/brake work needs a physical store; component magnitude limits alone are insufficient. [A6][A6]
- **Fuel residual scope:** connected-trial and firing-counter fixes do not close exact-zero feed-line derivative/timing or establish physically resolved spark probability. Investigate those separately. [A4][A4], [A6][A6]

### Extra 300 generator and presentation

Source: [A8][A8].

| Pending item | Action and acceptance boundary | Original report |
| --- | --- | --- |
| **E300-01 — Mixed moment reference points** | Correct the owning generator's force/moment reference invariants and regenerate through its pipeline. Do not globally replace CG arms: rotational-inflow arms and moment arms have different roles. This is a contract inconsistency, not A5's unproven polygon-centroid/pressure-center alternative. | [A8 original][A8] |
| **E300-02 — Camber omitted from crossflow derivation** | Reuse one installation-to-section adapter, retain optional-field defaults, and regenerate aircraft data/dependent identities. Add an independent table-to-installed-section invariant; comparing loads against the same shipped tables cannot detect this error. The consistent method is not independently calibrated propeller data. | [A8 original][A8] |
| **E300-06 — Visual blade handedness opposes spin** | Correct leading edge, camber and pitch geometry together, preserving physical rotation conventions and stable nodes/hinges. Inspect stopped appearance, rotation, blur and strikes. Headless geometric witness establishes a presentation inconsistency, not an error in physical shaft/thrust signs or rendered visual acceptance. | [A8 original][A8] |

**E300-08 — F5 geometry synchronization:** apply accepted installation diameter/CG consistently on reload; exercise actual F5 no-op/repeated, accepted diameter changes both ways and rejected mismatch, comparing physical disc/solid/blur transforms. Setter-only tests miss the wiring. [A10][A10]

### Corsair

| Pending item | Action and acceptance boundary | Original report |
| --- | --- | --- |
| CF-01 | Correct rate-moment CG/ARP convention in generator, with one runtime force transfer; independent invariant before retuning. | [A9 original][A9] |
| CF-02 | Remove final-table thrust extrapolation-floor discontinuity; cover knot continuity and refusal/domain controls. | [A9 original][A9] |
| CF-05 | Conservative raised-track first-contact search must consider interior crossings with two clear endpoints. Retain tabletop/roller witnesses, rotation, relief threshold, competing events and rollback; more bisection cannot repair skipped admission. | [A12 original][A12] |
| CF-06 | Include actual station-flow projection in flap lift-reference cross product; preserve optional/zero-flow branches and separate section/drag couples. Resolve before flap-pitch calibration. | [A12 original][A12] |

Sources: [A9][A9], [A12][A12]. Constructed contacts establish counterexamples, not encounter frequency or physical-aircraft fidelity. CF-03/04/07 are performance work below.

### Helicopters

Source: [A15][A15].

| Pending item | Action and acceptance boundary | Original report |
| --- | --- | --- |
| **H01 — P1, grounded heading reference accumulates** | Track heading during constrained ineffective authority and reconcile both memories with accepted heading before pickup. Preserve legitimate powered ground yaw and airborne coasting tail authority; drive hold alone is too broad a guard. Accepted-state/rollback/native parity matter. Test both signs, wrap crossings, centering/arm/spool/liftoff, blocked-powered versus real turns, recontact/checkpoints; assert reference error and target, not only integral. Existing ground-tracking requirement, distinct from inverted Euler-heading limitation. | [A15 original][A15] |
| **H02 — P2, low-RPM blend domain gap** | Keep bounded law where other member invalid, avoid activation arbitrarily near singularity, or reject unsupported combined start/weather before launch. Review main/tail transitions, finite checks, stop/refusal/rollback; do not hide with removed guard, zero wind or unjustified ratio clamp. Test both seams/adjacent floats, accepted-weather startup/coast-down, tail saturation and reference/native equivalence. Distinct from prior broad low-speed/high-flow refusal and one-second coast-down test. | [A15 original][A15] |
| **H03 — P2, successful lake context not passed to contact** | Carry validated terrain identity through support/impact, bounds/ground effect, camera, aftermath/audio, reset/checkpoint and backend eligibility. Audio also resamples dry terrain. Test stock/custom/disabled lakes, dry landscapes, both edges/normals/support/first contact/restart/restore. Explicit unsupported/terminal water policy may remain; flotation is not required. Separate from failed-shoreline-attachment fix `0fced1b`/PR 8; this is successful attachment lacking physics context. | [A15 original][A15] |
| **H04 — P2, mode confirmation goes stale** | Store source/destination, input generation and displayed effect; recompute at confirmation, refresh and require another press if materially changed. Preserve radio input; postmix preview validity includes cyclic/trainer saturation. Test unchanged/moved sticks, both directions, saturation/pause/cancel/controller recovery. Distinct from possibly intentional curve discontinuity; existing test covers unchanged stick only. | [A15 original][A15] |
| **H05 — P2, safe point used to reject whole rotor disc** | Retain outer bound; use exact planar support or bounded subdivision/interval/remainder for microrelief, preserving swept ordering. Dense sampling finds witnesses, not proof of conservatism. Test both witnesses, tilt/flat boundaries, both rotors, speed thresholds, crests, scenery competition and rollback. Inverted very-low sub-centimetre proxy counterexample, not exact blade-phase intersection/frequency; known HELI-33 phase/elasticity limits do not excuse invalid proxy rejection. | [A15 original][A15] |
| **H06 — P3, collective display is premix** | Use accepted postmix presentation telemetry, optionally separate requested angle/saturation. Audit callers before globally changing accessor: startup pickup, mode preview and audio proxy use it. Compare same-state electronics across signs, saturation, trainer/direct and mode transitions; define accepted versus interpolated display. Separate from missing achieved physical servo dynamics. | [A15 original][A15] |
| **H07 — P3, laboratory HX trim contract** | Reject unsupported FBL trim before success, or emit controller-specific result. Supported neutral-rate sticks plus collective/trim must reproduce converged wrench/shaft balance without double cyclic bias. Round-trip each accepted controller/mode then small integration step. Preserve attitude-reference refusal and all HX gates. **No playable-HX exposure.** | [A15 original][A15] |

Prioritize H01/H04, then H02 and H03/H05. Keep historical playable X-Cell, laboratory HX and articulated inspector separate. H07 has no playable-HX exposure; known release gates and achieved-servo limitations are not new defects.

## Performance candidates

Require current-source triage, correct output/refusal behavior and matched workload measurements. Component savings are not FPS. Preserve mutation checks, arithmetic/reduction order, signed zero and rollback; same-evaluation reuse is not permission for persistent caches.

| Source / ID | Pending candidate | Qualification boundary | Original report |
| --- | --- | --- | --- |
| A3 | Stage-validation reuse | Validated immutable/admitted data or supported mutation checks; full outputs/refusals and actual tick workload. | [A3 original][A3] |
| A6 O1/O2 | Native circuit terrain and companion admission | Same composed-ground/capability/fallback rules, fleet trajectories and lifecycle; do not remove guards. | [A6 original][A6] |
| A6 O3 | Prepared conservative hull reach | Live geometry identity/invalidation and real allocation/tick cost. | [A6 original][A6] |
| A6 O5 | Prepared wind-station geometry | Repair stale-NaN refusal mismatch before measuring guarded candidate. | [A6 original][A6] |
| A6 O6 | Shared rotor-domain/stage work | Stage-local exact reuse and rejection classification; full precheck cost is not removable cost. | [A6 original][A6] |
| A8 E300-03 | Stage-local mass properties | Feed/line/reserve boundaries and complete stage/refusal parity. | [A8 original][A8] |
| A8 E300-04 | Loft mesh indexing | Memory benefit versus slower construction; decoded attributes/triangles/hinges/ownership and actual import lifecycle. | [A8 original][A8] |
| A8 E300-05 | Immutable custom-paint Shader sharing | Separate per-instance ShaderMaterials/uniforms and variant identity; real import/render measurement. | [A8 original][A8] |
| A10 E300-07 | Reuse accepted trim RPM during finalization | Accepted-iterate invariant, complete result bytes, fallbacks/refusals; warm uncached timing is not full startup. | [A10 original][A10] |
| A9 CF-03 | Fresh retract-validation handoff | Preserve public validation, scene bindings and mutation checks; profile real GLB construction. | [A9 original][A9] |
| A9 CF-04 | Offline horseshoe-vector reuse | Complete generated JSON bytes/source pipeline; fewer generator calls are not FPS. | [A9 original][A9] |
| A12 CF-07 | Angle-only accepted flap presentation accessor | Keep full advisory for HUD/control consumers; actual GLB, lifecycle and whole-scene profile. | [A12 original][A12] |
| A15 O01/O02 | Remove overwritten angular derivative / one hull square root after maximum | Sampled parity exists; both timing campaigns inconclusive, stable complete-workload benefit still required. | [A15 original][A15] |
| A13 OBS-01 | Natural Random briefing/reroll preparation | Measure input acknowledgement, longest frame, generation/setup/ready, cold/warm; stale generation/cancel ownership. | [A13 original][A13] |
| A11 intro | Frozen-intro event-driven redraw | Explicit status/error invalidation; profile first. | [A11 original][A11] |

A6 O4 is implemented and listed only under remaining qualification, not as an unimplemented optimization.

### Rendering math and platform experiments

### Cloud, ground and same-evaluation math

Source: [A2][A2].

| Pending item | Action and acceptance boundary | Original report |
| --- | --- | --- |
| **M01 — Same-cell coarse cloud hash sharing**, §3 | Keep each query's original interpolation and original fallback at cell crossings. No saving when clustering is disabled. Unguarded sharing produced errors up to 1.0. This does not remove two thirds of the whole cloud shader and does not generalize to fine octaves. | [A2 original][A2] |
| **M02 — Solar chord-coordinate approximation**, §4 | Disc ramp is an approximation, not an algebraic identity. The halo bound does not bound the disc or GPU rounding. Preserve dynamic radius, limb/squash mode, occlusion, radiance generation, and multiply error by actual HDR solar contribution. | [A2 original][A2] |
| **M03 — Bounded density-query omission**, §5 | Start with the cheap far bound; retain original density for silhouettes, occlusion, and other consumers. Classic and layered clouds require different color multipliers. Bound all layers/approximations together. Sample requests do not equal issued GPU work. | [A2 original][A2] |
| **M04 — Zero-support solar/lunar rejection**, §6 | Empirical guard is not a proof for every GPU math mode. Keep moon antialiasing derivatives ahead of varying early-outs, and keep optional solar limb/squash behavior distinct. A 45° cap's 14.64% sphere coverage is not viewport frequency. | [A2 original][A2] |
| **M11 — Bounded exponential polynomial**, §9 | Lower priority until exponential cost is measured. Rounded degree-six/seven results exceed ideal truncation bounds; the sampled endpoint slightly exceeds ideal 2.16. Five multiply-add stages may cost more than the exponential. Combine its error with M03. | [A2 original][A2] |
| **M05 — Shared base noise footprint**, §7.1 | Tolerance-based rendering change: differencing rounded transformed coordinates is not byte-identical. Keep derivatives outside divergence; cover ground, near-grass, lake-bank, and the bank's separate 2.8 m call. Inspect compiler reuse first. | [A2 original][A2] |
| **M06 — Shared relief phases and derivatives**, §7.2 | Preserve `∇h = A∇W + W∇A`, including feather-edge amplitude gradients and surface precedence. Physics terrain stays unchanged. Update affected literal-substring tests without treating a CPU mirror as GPU proof. | [A2 original][A2] |
| **M07 — Exact anti-tiling endpoint texture skip**, §7.3 | Finite texture values, original explicit gradients before branching, and exact endpoints only. Divergence may erase savings. Shared grass/dirt indices and offsets are another same-position reuse opportunity; cover normals and lake banks too. | [A2 original][A2] |
| **M08 — Shared grass/dirt tangent frame**, §7.4 | Preserve dirt-only and grass-skipped paths, incoming normal magnitude where relevant, frame conditioning, and rigid view-transform assumptions. The model omits real texture decoding, view transform, and GPU execution. | [A2 original][A2] |
| **M12 — Guarded parcel-distance pruning**, §10.3 | **Research only.** Unguarded squared-distance ranking changes float32 tie behavior and material identity: raw crop-factor difference up to 0.283, default faded factor up to 0.133. Near threshold retain original roots and strict comparison order; GPU rounding/branch cost remain unresolved. | [A2 original][A2] |
| **M09 — Same-evaluation airflow reuse**, §8.1 | Reuse only within the exact same RK evaluation and matching inputs. Distinguish reference/spatial and optional wake inputs. Preserve validation order, NaNs, signed zero, refusal, rollback, and serial reductions. Operation counts exclude additional events/substeps and are not timings. | [A2 original][A2] |
| **M10 — Prepared flap and source-strip invariants**, §§8.2–8.3 | Keep original expressions and multiplication/accumulation order, and avoid evaluating a branch that was previously unused. No cross-stage, cross-tick, changed-control, changed-wind, or clean/flapped cache reuse. | [A2 original][A2] |
| **R01**, footprint-aware noise statistics, §10.2 | Do not ship residual-mean/moment substitution as a filtered equivalent. Filter thresholded density and lighting with a justified footprint/correlation model. | [A2 original][A2] |
| **R02**, analytic terrain-wave box filtering, §10.4 | Separate visual-quality research, not a parity refactor. Perspective and amplitude edges need treatment; use moving supersampled references. A simpler pointwise bound skips all waves in only 1.54% of tested weights. | [A2 original][A2] |

- **A7 additional shader math:** bounded density, high-octave lattice, polynomial/integer/angular/ground proposals need exact compiled-operation/Metal and consumer checks; CPU screens are not GPU qualification. Original reports: [A7][A7].
- **A7 architecture:** crop projection, native rate maps, attachment/resolve cost, resource/import/compression, PGO and reconstruction proposals need isolated prototype plus complete affected-consumer and target-hardware evidence. Original reports: [A7][A7].
- **Rejected or inconclusive:** solar support candidate was reverted after M1 screening; Corsair stationary-pose cache was slower and gasoline reuse timing inconclusive; naive parcel pruning changes material identity; unguarded wind geometry loses refusal. Revive only with new evidence, not as ready-to-ship changes. Original reports: [A2][A2], [A6][A6], [A9][A9].

## Research and physical validation

| Source | Pending program | First useful result | Original report |
| --- | --- | --- | --- |
| A5 / A10 | Stall-selector, flow-convention and small rate-cusp investigations | Establish independent contract/diagnostic significance before promoting an aerodynamic defect. | [A5 original][A5], [A10 original][A10] |
| A16 Corsair | Reference installation/input/fuel/CG identity; trim/control/damping/energy; flap/elevator and contact calibration | Matched 0°/15°/30° flap comparisons after CF-06. Heavy forum aircraft do not calibrate 21.5 kg half-tank reference. Separate inertia from steady-rate damping; real-aircraft evidence required. | [A16 original][A16] |
| A16 sound | Identified Moki RPM/load/listener-controlled audio | Preserve duplicate-prop suppression; numerical ORFL does not replay audio/camera. | [A16 original][A16] |
| A19 rotor | Matched rotor thrust/torque/power dataset benchmark | Fitting versus held-out conditions, uncertainty, dimensional zero-RPM behavior; thrust alone is insufficient. | [A19 original][A19] |
| A19 actuator/linkage | Achieved servo bench, stage-state coupling and geometry maps | Measured output/delay/load and independent analytic checks; withheld combinations/binding regions. | [A19 original][A19] |
| A19 drive | Two-speed/freewheel energy stand separate from governor | Signed work, engagement/overrun/stop convergence and momentum accounting. | [A19 original][A19] |
| A19 identification | Correct timestamps/frames and sequential component identification | Whole-flight validation and scaled sensitivities/uncertainty; `loads_t_s` lag is an analysis requirement, not a defect. | [A19 original][A19] |
| A19 extension/training | Justified aero complexity, conservative contact, repeatable practice and audio | Keep HX gates and X-Cell separation; demonstrated helicopter trace/checkpoint paths, no unverified ORFL assumption or simulator realism ranking. | [A19 original][A19] |

A16/A19 propose experiments, not completed physical validation. A18 participant tasks should test imagined expectations against actual outcomes. Source originals retain formulas, conditions and negative results; referenced external packages must be obtained/inspected before relying on unavailable raw evidence.

## Remaining qualification

| Implemented or historical area | Pending gate | Original report |
| --- | --- | --- |
| A11 F01/F02; A6 F2 | Physical transmitter/controller and native visual qualification beyond software regressions. | [A11 original][A11], [A6 original][A6] |
| A14 F10/F11 | Native interaction/visual acceptance and applicable required CI; retain localization/coverage limits without reopening repaired data loss. | [A14 original][A14] |
| A13 UI2-01/UI2-05; A14 F14 | [UI-31-R2](../docs/research/menu-investigations/UI-31/README.md#coordinated-departures-ui-31-r2-2026-11-06) repairs coordinated departures with 910 focused checks. Native OS close, physical controllers, rendered/assistive-technology acceptance and required full CI remain separate. | [A13 original][A13], [A14 original][A14] |
| A6 F1 | Optional future support for refused multi-substep glow requires independently qualified contact/event composition; safe admission refusal is already delivered. | [A6 original][A6] |
| A6 F3 | Dynamically flown/physical landing and target cost; constructed geometry fixtures do not establish those. | [A6 original][A6] |
| A6 F4 / A4 | Full applicable CI/native installation/physical gates; zero-total feed-line derivative remains separate. | [A6 original][A6], [A4 original][A4] |
| A6 F5 | Locate or retain passing checked absent/empty/nonempty record-inspect-replay receipt. Implementation exists, but this review did not establish its specific passing receipt. | [A6 original][A6] |
| A6 O4 | Native rebuild/oracle, required full app/visual CI and sustained 1080p full-scene measurements. Reported isolated spatial full-step median 7.47% is not FPS. | [A6 original][A6] |
| A1/A7 rendering hardening | Actual MetalFX execution, valid displayed recovery, native lifecycle/readability. Callback/property observations alone are insufficient. | [A1 original][A1], [A7 original][A7] |
| A1 instrumentation | Verify current reducer rejects profiler/HUD/diagnostic contamination before accepting timing; historical source claims are not current gate proof. | [A1 original][A1] |
| A1/A7 cache | Qualify current RG16F ground/sky/layered configuration separately; old RGBA8/single-profile figures are not current acceptance. | [A1 original][A1], [A7 original][A7] |
| All visual work | 1920×1080 first, higher resolutions next, 720p fallback; native rendered/device/accessibility evidence as appropriate. | [A11 original][A11], [A13 original][A13], [A18 original][A18] |

This reorganization changes documentation only. It does not rerun runtime suites or certify physical accuracy, releases or native performance.

## Sources

Use originals for detailed witnesses and historical baselines. The [provenance appendix](COMPLETED-AUDIT-WORK.md#source-provenance) retains source snapshots and intake hashes, without marking whole reports completed.

| Source | Original |
| --- | --- |
| A1 | [Apple Silicon audit — apple-silicon-performance-audit-2026-11-05.md][A1] |
| A2 | [Mathematical Optimization Lab][A2] |
| A3 | [Stage-validation reuse — stage-validation-reuse-experiment.md][A3] |
| A4 | [Propulsion and energy audit — propulsion-energy-audit-2026-11-06.md][A4] |
| A5 | [Fixed-wing aerodynamics review — fixed-wing-aerodynamics-review.md][A5] |
| A6 | [Developer audit and remediation handoff — developer-audit-remediation-2026-11-06.md][A6] |
| A7 | [Apple Silicon and Metal Optimization Handoff][A7] |
| A8 | [Extra 300 physics and optimization audit][A8] |
| A9 | [F4U Corsair physics and optimization audit][A9] |
| A10 | [Extra 300 round-two trim and reload audit][A10] |
| A11 | [UI/UX, configuration integrity and accessibility audit][A11] |
| A12 | [Corsair collision, flap geometry and presentation handoff][A12] |
| A13 | [Incremental UI/UX exit, settings and feedback audit][A13] |
| A14 | [UI/UX Workshop, launch and statistics continuation][A14] |
| A15 | [Helicopter controls, contact, trim and optimization audit][A15] |
| A16 | [Corsair flight-feel and realism research plan][A16] |
| A17 | [Workshop pending-state and menu-flow audit][A17] |
| A18 | [Player journeys cognitive walkthrough][A18] |
| A19 | [Helicopter rotor, actuator and drivetrain research plan][A19] |

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
[A14]: ui-ux-workshop-launch-statistics-continuation-3751e35.md
[A15]: helicopter-controls-contact-trim-audit-3e652a8.md
[A16]: f4u-corsair-flight-feel-realism-research-plan-2026-11-06.md
[A17]: ui-ux-workshop-pending-state-menu-flow-audit-3e652a8.md
[A18]: ui-ux-player-journeys-cognitive-walkthrough-2e2e349.md
[A19]: helicopter-rotor-actuator-drivetrain-research-plan-d0b672b.md
