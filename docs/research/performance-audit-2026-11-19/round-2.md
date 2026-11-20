# Round two: traced correctness failures and optimization boundaries

Date: **2026-11-19, America/Bogota**. Continuation of the [CPU/GPU audit](README.md), on `audit/cpu-gpu-optimization-2026-11-19`.

Runtime baseline: [`894357de83762ff6e0fdc47b0024e60f3d8286b7`](https://github.com/bultodepapas/OpenRCsimulator/commit/894357de83762ff6e0fdc47b0024e60f3d8286b7). Audit parent: [`dbdd5eddceb4a4e36d58e4b83919303a70707a79`](https://github.com/bultodepapas/OpenRCsimulator/commit/dbdd5eddceb4a4e36d58e4b83919303a70707a79). Runtime source remains unchanged by this report.

## Assessment

The deeper investigation found **ten additional review items, F36–F45**: **five reproduced defects**, **four source-supported defects**, and **one counted optimization candidate**. F37 contains a second, narrowly reproduced quaternion edge case. F43 turns an existing terrain-bounds concern into a concrete accepted-session counterexample; it is not presented as a newly discovered concern. Together with the original 35 items, the branch contains **45 findings and review items**, not 45 proven gameplay bugs or measured speedups.

The next correctness work should address **terrain contact admission and Angle-controller continuity**, alongside the first report's event-ordering defects. A shortcut that skips an actual contact must be corrected before being generalized or translated to native code. Replay verdicts and settings transactions also need their stated contracts made explicit. The lake findings concern consistency between valid data, mathematical wave definitions and rendering transforms; they do not establish a GPU performance loss.

The investigation followed callers, admitted input ranges, saved state, existing tests and earlier findings. It used production methods in disposable projects, positive/negative controls and a second review of the evidence. Several initially plausible leads were excluded. Neither helper agreement nor a successful wrapper exit substitutes for the exact evidence boundary described below.

| ID | Priority | Classification | Additional finding | Existing owner |
| --- | --- | --- | --- | --- |
| [F36](#f36) | P2 | Reproduced defect | Graphics calibration reset intent survives Revert and is absent from dirty-state logic | VQ-07h, UI-24 |
| [F37](#f37) | P1 | Reproduced defect | Angle targets jump at the heading cutoff; exact half-turn tie depends on quaternion sign | DR-07, DR-09a, DR-21 |
| [F38](#f38) | P2 | Reproduced defect | Airship verify returns exact/ok despite an explicitly changed solver fingerprint | BL-08 |
| [F39](#f39) | P2 | Reproduced component defect | Airship replay ignores row-tick chronology and footer time bounds | BL-08 |
| [F40](#f40) | P2 | Source-supported, conditional | Two unavailable replay identities can compare equal and satisfy the changed-solver gate | BL-08, DR-17 |
| [F41](#f41) | P3 | Counted optimization candidate | Valid connected input polling scans 128 buttons even for the reviewed unbound-AUX case | RC input, VQ-01c |
| [F42](#f42) | P2 | Source-supported, transform calculation | Aquatic plant instance scale changes the intended world-space wave displacement | LU-22-R2 |
| [F43](#f43) | P1 | Reproduced prior lead | Center-only terrain clearance skips an overlapping quad on a valid custom ramp | DR-19/24/09b; DR-18, DR-22-R1 |
| [F44](#f44) | P2 | Source-supported, scalar calculation | Admitted shore fade above 12 m differs between water material and plant/physics paths | LU-25, LU-22 |
| [F45](#f45) | P2 | Source-supported, scalar calculation | Valid custom wave periods violate the shared shader-clock wrap assumption | LU-25, LU-22, L0d |

P1 means repair the correctness boundary before further optimization; it is not a claim of frequent crashes or quantified severity. P2 is a bounded consistency/verification repair. P3 needs current workload attribution before implementation. These F identifiers only extend this audit's register; they create no new project track.

## Source identity, execution and limits

The report checks current GitHub source against the baseline and existing audit branch. At publication, main had advanced to [`b69ac2d54871b0d798af7c61ac62d8f17e6abd3d`](https://github.com/bultodepapas/OpenRCsimulator/commit/b69ac2d54871b0d798af7c61ac62d8f17e6abd3d). Its application changes include the 0.2.8→0.2.9 version bump and later ClearView importer/UI/localization/test work. **All finding-related runtime paths and pinned fixture inputs remain identical**; the new importer work is outside this audit's claim. The [source-identity record](round-2-source-identity.json) preserves the changed-path inventory and canonical Git blob comparisons, as well as SHA-256 values of checked-out source bytes. Existing Git CRLF conversion for `app/data/fields/default.json` is recorded rather than misclassified as a runtime modification.

The final [reproduction package](../../../research/performance/audit-2026-11-19/round2/README.md) uses the official pinned **Godot 4.8 beta 2, `4.8.beta2.official.cafc17a19`, Linux x86_64**. Its SHA-512 is checked before and after collection. The manifest pins **155 source/data/support paths**, including the checked runner, reviewed shader/material files and the original preferences constant. The core project copies 119 production files and Settings copies 32; these are dependency closures, not full-app coverage.

**Twelve checked launches completed with zero errors and zero warnings:** two isolated imports and ten probe launches. They exercise settings transactions, two controller probes, input callback counts, plant transform math, custom wave math, terrain components, actual terrain sessions and two airship replay processes. All expected baseline observations recur. Checked-run success means the counterexample was observed; these are not repaired regressions.

The [raw evidence](round-2-evidence.json) retains observations, source/engine and reproduction-asset hashes, complete commands and checked receipts. Paths in its `runs` entries resolve beneath [the retained evidence directory](round-2-evidence/README.md). Log bytes and hashes are preserved. The [structured register](round-2-findings.json) adds source ranges, proposed fixes, acceptance criteria and limitations. [Primary references](round-2-sources.json) distinguish engine API context from application evidence.

The local environment was unenrolled and had no configured test pool. The existing checked runner was used sequentially. Each fixture has isolated data/config/cache directories. The substitutions are explicit: two assertion-only scenery stubs for sessions with no obstacle inventory; the preferences-path constant and fallback fonts for Settings; and unchanged extracted plant-placement functions for analytic calculations. The actual terrain, RC track, model, controller, session, kernel and replay methods under examination remain unchanged. The runner fails if an assertion-only scenery method executes.

There is **no new GPU timing, rendered frame, native backend, FPS, physical-input latency, release package, Mac/Windows, audio, memory-soak or full-CI qualification**. The Angle probe uses independently initialized component samples, not a continuous flight maneuver. The terrain case uses an intentionally overlapping research air start, not a naturally flown encounter. The lake calculations do not execute shaders. The conditional package-identity finding is source-traced, not exercised in a release executable.

## Findings

### F36

**Graphics calibration reset is outside the Settings transaction.**

`_restore_graphics_defaults()` modifies the draft and sets `_calibration_reset_pending`. A successful `keep_changes()` attempts to delete saved calibration and clears live calibration when that flag is set and the production display-profile path is active; the file-removal return value is ignored. `_revert()` restores the saved draft but leaves the flag. The action-button dirty calculation compares only draft and saved dictionaries, ignoring pending reset intent. The expiry handler restores only display-trial keys, also leaving the flag. These are distinct parts of one transaction-state problem. [Restore][settings] [Commit/revert/expiry][settings-transaction] [Dirty state][settings-dirty]

The actual Settings-method probe seeded a valid synthetic calibration file and exercised these sequences:

| Sequence | Observed baseline behavior |
| --- | --- |
| Saved 60 fps cap → Restore graphics → Revert | Draft equals saved values; the calibration file still exists; reset remains pending. |
| Same instance → change only master volume to 0.5 → Keep | The 60 fps cap stays saved, but the calibration file is deleted and live calibration becomes empty. |
| Already at recommended values → Restore graphics | Reset becomes pending while both Keep and Revert are disabled. Remeasure intent alone cannot be committed. |
| Restore with only a display-trial difference → invoke expiry handler → unrelated volume Keep | The draft returns to saved values but reset remains pending; the later Keep deletes calibration. |
| Close/destroy/reopen before the unrelated Keep | The new Settings instance has no pending flag; calibration survives. This bounds the stale intent to the same instance. |

The player-facing restore explanation promises remeasurement, but that intention is neither represented as independently dirty nor reliably canceled by explicit Revert. Deleting calibration can make subsequent automatic-graphics decisions eligible for remeasurement under the existing flight/renderer/timing conditions; the probe does not claim immediate GPU work or a measured FPS effect. [Calibration lifecycle][calibration] [AppRoot eligibility][app-root] [Settings creation][settings-creation]

**Repair.** Treat calibration reset as transaction state with explicit saved/draft intent. Include it in dirty/Keep/Revert logic, clear it on a full Revert, and decide its relation to display-only timeout explicitly. Do not blindly discard all pending graphics intent on timeout: non-display graphics edits can legitimately remain in the draft. Preserve failed-save behavior and the production-profile guard.

**Acceptance.** Cover Restore→Revert→unrelated Keep; Restore at identical values; successful Restore→Keep; failed save; a timeout with only display differences; a timeout with other graphics edits; and destruction/reopen. The executed probe directly calls methods and forces the expiry handler; it is not a timed 15-second UI interaction or full AppRoot input test.

### F37

**The Angle leveling target is discontinuous at an artificial heading boundary.**

`heading()` uses the nose's horizontal projection when its length is greater than `0.2`, then abruptly uses the airframe top direction. `_angle_rate_target()` builds a desired attitude from that heading and converts the shortest quaternion error into roll/pitch rate targets. These heading formulas need not agree at the switch. The production controlled plant samples this controller at the accepted input boundary. [Controller source][controller] [Plant sampling][plant-sampling]

The probe uses pitch `±acos(0.2) ± 10⁻⁸ rad`, with bank angles of 0, 0.3 and 2.0 rad, centered sticks and identical zero rate/filter histories. Adjacent test attitudes differ by about **2 × 10⁻⁸ rad**. They are separate initialized component samples, not consecutive flight ticks.

| Bank | Raw roll-target difference | Filtered difference | Requested roll-torque difference |
| --- | --- | --- | --- |
| 0 rad | 0 | 0 | 0 |
| 0.3 rad | **1.259565 rad/s** | **1.104456 rad/s** | **0.401138 N·m** |
| 2.0 rad | **6.070877 rad/s** | **5.323280 rad/s** | **0.610049 N·m** |

Both pitch signs reproduce the same magnitudes; zero bank is a negative control. The discontinuity is at about **78.463° pitch**, rather than only at the vertical singularity. The configured 55° limit bounds the requested tilt, not the current body attitude; switching into Angle from another mode does not guarantee an already-upright body. The existing focused test covers steady, inverted and exact-vertical states but not this cutoff. [Existing tests][controller-tests]

The torque values are **controller requests in a laboratory static actuator-map/allocator fixture**, with supply voltage zero. The controller sample uses the lab law's steady command-to-thrust mapping; no first-order motor-lag dynamics are advanced. The results do not establish actual stock-electric motor response, a crash or the frequency of a pilot-visible jump. They do establish that finite output filtering and torque clamping do not remove the input-map discontinuity.

**Additional exact half-turn case.** With the production controller method, `q = [0, 1, 0, 0]` and `−q = [0, −1, 0, 0]` encode the same inverted attitude and heading but return opposite capped roll targets, **−6.981317 and +6.981317 rad/s**. The sign rule uses `delta[0] < 0`; at exactly zero it does not select a representation-independent tie. At nearby nonzero scalar values `±10⁻¹⁰`, equivalent signs return the same target. Both exact-half-turn directions are equally short; this is a deterministic representation issue, not evidence that either physical direction is intrinsically wrong. No ordinary-flight incidence was established.

**Repair.** Specify a locally continuous near-vertical leveling policy, potentially with a retained heading/reference or a tilt-alignment formulation. Handle unavoidable singular attitudes and mode-entry/reset state explicitly. A threshold change merely relocates the first discontinuity. For the exact-half-turn tie, choose a deterministic vector-part convention when the scalar is zero; do not claim a globally continuous shortest-turn selection over every attitude.

**Acceptance.** Sweep both sides of the cutoff at multiple banks/yaws, compare equivalent quaternion signs, test mode entry and reset, and run a continuous closed-loop recovery with stock powertrain and saturation. Preserve float64 state and 240 Hz sampling. Native translation of the same branching law would preserve these defects, not repair them.

### F38

**Airship exact replay does not enforce the changed-solver result.**

The airship verifier computes `solver_changed`, checks configuration/state/terminal outcome, then assigns `exact = true` and `ok = true` without rejecting the changed identity. The multirotor verifier explicitly refuses exact replay in that case. The airship method's own contract says same solver identity. The CLI reports the flag and exits successfully on the returned `ok`. [Airship verifier][airship-log] [Multirotor comparison][mr-log] [Airship CLI][airship-cli]

The probe creates a legitimate airship session with shipped model data, terrain-only empty field, altitude 20 m and steady wind 1.5 m/s. It warms up 12 ticks and records 24 more, ticks 13–36, at 240 Hz. Public `verify()` returns complete/exact/ok with `solver_changed = false` in the control process.

A comment is then appended **only to the copied fixture's** `physics/math3d.gd`; a fresh Godot process verifies the unchanged `.orfl`. The source fingerprint changes and the recording SHA-256 remains identical, yet the verifier returns:

```text
complete=true  identity_match=true  solver_changed=true  exact=true  ok=true
```

This is a public verifier reproduction, not an edited-recording experiment. A comment-only change intentionally preserves numerical behavior so the identity policy is tested independently of divergence. It does **not** demonstrate differing physics producing the same trajectory. The fingerprint belongs to the copied dependency closure and is not a release/full-checkout solver identity.

The flag is **visible**, and the flight-logging guide already tells users to check `solver_changed` and completeness. The finding is inconsistent certification semantics, not concealment of the flag or a claim that the guide promises unchanged code. [Logging guidance][logging-guide]

**Repair.** Enforce unchanged identity before `exact` can become true, as the multirotor changed-hash guard does, and separately require available identity in both verifiers. Alternatively, explicitly redefine/separate trajectory-byte match from exact replay across API, CLI, documentation and callers. A comparison run may still be useful without being exact.

**Acceptance.** Retain same-source, comment-only changed-source, intentionally changed physics, changed session identity and incomplete-recording cases. Check CLI exit/report behavior as well as the method. The CLI path here was source-traced, not executed separately.

### F39

**Airship replay compares state rows without validating their recorded timeline.**

The writer requires consecutive accepted ticks. The inspector verifies packet integrity, hash-chain/row-count completion, EOF and array dimensions, but does not require consecutive tick labels, their offset from the checkpoint, or consistent footer tick bounds. `_replay()` consumes one input row per step and compares state/continuous bytes; row ticks are otherwise used as diagnostic mismatch labels. [Writer and inspector][airship-log] [Replay session reset][airship-session]

Starting with the valid parsed recording from F38, the component probe clones its record and independently changes: a duplicate row tick, a gap of 100 ticks, swapped first two tick labels, and footer bounds of −10/−20. The actual `_replay()` method returns exact/ok for all four. The `.orfl` file is never changed. Thus the dynamic evidence is at the **parsed-record component boundary**; the public inspector's missing semantic checks are established by reading its source, not by submitting a fully checksummed malformed file.

This is narrower than saying ordinary recordings are corrupt. The current writer does not emit these sequences, and ordinary bit changes are caught by packet/chain checks. It is a semantic-validation gap relevant to imported/recovered/future-writer data and the meaning of an exact timeline. Exported time comes from these recorded labels, so mislabeled data can disagree with the replayed row sequence. The terminal-crash comparison does already validate its own tick offset and should be preserved. [CLI export][airship-cli]

The airship replay session intentionally resets its internal tick to zero under its time-invariant wind law. That reset is not a bug. Timeline validation must compare a row with **checkpoint tick + replay tick**, require the first row immediately after the checkpoint, and interpret the writer's footer `first_tick` as the checkpoint boundary, not the first recorded row.

**Repair.** Validate the semantic time contract in the inspector and/or at replay entry before stepping. Check consecutive ticks, checkpoint boundary, final tick and footer consistency. Retain packet/chain checks; they serve a different purpose. Multirotor's per-row tick comparison is useful precedent, although its footer-bounds handling also deserves a separate focused test before claiming parity. [Multirotor replay][mr-log]

**Acceptance.** Add publicly parsed, correctly checksummed duplicate/gap/reordered/footer cases, plus valid nonzero checkpoint, empty/one-row behavior as supported by the format, terminal crash and interruption controls. This report's four component counterexamples are not a substitute for those file-boundary regressions.

### F40

**Unavailable identity must not be treated as matching identity.**

The shared identity helper returns `{kind: "unavailable", sha256: "unavailable-export"}` when a release package identity cannot be established. Airship and multirotor writers store the returned identity without rejecting that unavailable kind. Their verification paths compare SHA strings; if both sides contain the unavailable sentinel, the strings match and `solver_changed` is false. If the remaining state/configuration checks agree, the exact gate can be satisfied without a known solver identity. [Shared identity helper][identity-helper] [Airship and multirotor logs][airship-log] [Multirotor log][mr-log]

This is **conditional source evidence**, not a failure observed in a shipped package. The inspected route is an otherwise runnable release with absent/invalid identity material. For macOS, startup pins the package receipt, but an unavailable receipt is retained as an empty result rather than globally aborting the app; AppRoot can still dispatch experimental airship/multirotor sessions. Their recording actions reach the recorder without the fixed-wing recorder's explicit unavailable-identity guard. The non-Mac manifest path can also return unavailable. No claim is made that normal released packages presently lack receipts. [Package identity][native-package] [Startup][startup] [Scene entry and recording][scene-entry] [Fixed-wing guard][fixed-wing-log]

**Repair.** Make identity availability a required part of the exact contract, with an explicit diagnostic outcome. Compare identity kind/version and digest as appropriate; an unknown value must not certify equality. Recording may remain allowed for diagnostics if that is the product policy, but its report must not certify exact solver identity. Apply the rule consistently across vehicle recorders and comparison modes.

**Acceptance.** On actual release fixtures, exercise valid identity, missing/invalid package receipt, unavailable recorded identity and unavailable current identity. Keep candidate-run semantics distinct. The next verification must use correctly prepared isolated package fixtures; this audit did not execute a release template, alter a release package or establish a cross-package replay failure.

### F41

**Input polling has a concrete redundant-work candidate, with no timing claim.**

After validating a connected profile and reading axes, `RCInput.poll()` checks connection continuity. When that gate permits continuation and a button reader is present, it scans all **128** button indices and builds held-button evidence. It also samples bound AUX channels when integration is enabled and input/profile errors are absent. The reviewed standard-gamepad policy explicitly permits readiness from verified live samples without a centered dwell or button release. The held/menu call still gathers fresh input evidence with integration disabled. [Input implementation][rc-input] [Fixed-wing caller][input-callers]

With a valid profile, unbound AUX, synthetic readers and an injected verifier that confirms a synthetic gamepad, 240 direct calls produce **30,720 button callbacks and 2,400 axis callbacks**, both for active and held/menu samples. Both cases remain armed with no input/profile error and zero throttle. No physical device is verified and no menu is opened. This counts operations: it is not 30,720 physical USB polls, and it is not a measured wall-clock rate. In production, the callback reads Godot's input state. At an actual 240 calls per second, the same count would occur per second. Other profiles can early-return, and AUX bindings may add reads.

The repeated scan is an attribution target, not a proven major bottleneck. The existing binding-resolver optimization addressed a different path and should not be counted again as a new win. The fixed-wing held caller also has external-controller, enabled-input and connection conditions; not every open menu necessarily executes this loop. [Existing input performance work][input-prior]

**Candidate.** Determine which consumers require all-button held/release evidence for a given device/profile generation. For a proven eligible standard-gamepad path, investigate narrower queries or reuse one complete same-tick snapshot. A batch native API is only a later option if boundary overhead is measured and the data contract is stable.

**Acceptance.** Preserve raw-radio/event evidence, focus loss/return, hotplug, source generations, non-finite-axis invalidation, holds, rate throttle, AUX and current gamepad readiness policy. Do not replace required per-tick evidence with per-frame throttling. First measure complete input/session cost; compare allocation and dispatch counts, then profile native 1080p pacing if relevant. A C++ wrapper around the same 128 calls does not itself establish a saving.

### F42

**World-height waves are added in scaled plant-local coordinates.**

Lake plants compute a world-coordinate wave height in the lily shader, then add it to local `VERTEX.y`. Plant instances apply uniform scale: lily pads use half their diameter, approximately 0.28–0.47 for generated pads, while flowers use 1.25. The water mesh uses the matching wave equation with unit scale. There is no inverse-scale compensation. [Plant transforms and uniforms][plants] [Lily shader][lily] [Water shader and mesh][water]

Godot's spatial-shader reference defines default vertex coordinates as model/local coordinates and `MODEL_MATRIX` as local-to-world. That explains why applying a world-height displacement before a scaled model transform changes its amplitude. It does not establish any renderer-specific defect in the pinned engine. [Primary engine reference][godot-spatial]

For a yaw-only, uniformly scaled instance with scale `s`, the extra vertical displacement becomes `s × h` instead of the intended `h`; the error attributable to this transform is:

```text
displacement_error = (s − 1) × h
```

The probe runs the unchanged placement functions for the default lake, producing 105 pads and 14 flowers. At actual generated placements and time 1.25 s, a pad with scale 0.301576 and matched analytic height 0.00909381 m has a transformed displacement 0.00274247 m: approximately **−6.35 mm** relative to the unscaled expression. A flower with scale 1.25 and height −0.00327480 m differs by approximately **−0.819 mm**. The Godot Transform3D calculation closely matches the analytic `(s−1)h` result.

These are local-origin Transform3D calculations, not sampled GLB vertices or rendered pixels. Plant fade comes from instance data while water fade uses vertex UV2/interpolation; their values need not match at every visible surface point. The calculated error isolates scale under matching height/fade inputs. It does not claim the entire rendered water/leaf gap, visible submersion, culling failure or GPU cost. Intentional base offsets remain separate.

**Repair.** Apply the intended vertical displacement in world coordinates or correctly transform its vector back to local space. Preserve phase sampling, base offsets, rotation and accepted geometry scale. Switching to `world_vertex_coords` alone is insufficient if existing `MODEL_MATRIX` calculations are left unchanged. Update bounds only from a justified displacement envelope.

**Acceptance.** Compare several pad/flower scales at shore/interior positions over a wave cycle, then perform a rendered capture at the target resolution on the relevant renderers. Check normals, shading, fade, motion and bounds. The suspected lack of expanded plant AABBs remains an unverified related culling lead, not another counted defect.

### F43

**Center-only terrain clearance can skip an actual contact.**

`_contact_loads()`, strict ground-crash checks and graded ground impact handling return early when the center of gravity is more than `CONTACT_REACH = 0.6 m` above terrain sampled directly underneath it. This says nothing about higher terrain under an offset foot, body point or rotor disc. The substep policy also begins from a center-height threshold. `ground_max_height()` exists on the environment but does not rescue these plant shortcuts. [Contact loads][terrain-plant] [Strict ground checks][terrain-strict] [Graded ground checks][terrain-graded] [Substep policy][terrain-substeps]

This concern was already recorded in the drone-racing audit follow-up and packet 8. The new contribution is an actual accepted-session witness and a nearby component control. [Prior concern][terrain-prior] [Owning plan][dr-plan]

The test loads the shipped quad, default field and default RC track, then changes only the first ramp in memory to height **1.2 m**, approach **0.1 m**. The actual track validator accepts it and the field matches. A research air start at north 39 m, east −4.327 m and altitude 0.7 m above center ground is deliberately placed overlapping this steep ramp. Both strict and graded sessions prepare, resume and accept one real simulation tick. [Track admission][track] [Session preparation][mr-session]

At the admitted start, the plant's own memoized ground sampler gives:

- Center clearance **0.7000000001 m**.
- One contact point **0.277758 m inside terrain**.
- Rotor-disc witnesses intersecting terrain for rotors 0 and 1.
- Returned contact force `[0, 0, 0]`, empty strict crash reason and **one** substep.
- After the tick, no crash/fault and graded prop health still `[1, 1, 1, 1]`.

The environment's global terrain maximum is 2.732 m, so a conservative terrain bound would not have justified a free-flight early-out. The initialized rotors have hover speed even though the neutral controller mode is initially disarmed; the neutral tick coasts them rather than instantaneously removing their speed.

The separate component control uses direct RC-track sampling. At center clearance **0.59 m**, it returns nonzero force, `Propeller strike` and graded prop damage. At **0.70 m**, contact points still overlap but force and damage disappear. Its depth is 0.275712 m rather than the session's 0.277758 m because the sampling paths differ; these are related, distinct observations.

**Impact and limit.** The accelerated path violates conservative contact exclusion for an admitted terrain configuration. This does not establish a crash on the shipped course, a naturally flown first-contact trajectory, an obstacle collision failure or full physical validation. A separate helper run using real collision sources/assets agreed with the session witness; the portable retained fixture asserts that its unused obstacle stubs are not called.

**Repair.** Use a conservative bound over the whole relevant vehicle footprint and movement envelope, or explicitly refuse unsupported geometry. In positive-up notation, a sufficient no-contact condition is `z_CG − R_vertical > max terrain height over footprint`, with suitable swept-motion allowance for the interval. `R_vertical` must cover relevant contacts/rotor geometry at the current orientation. A cell maximum or conservative local envelope can retain a fast free-flight path; a global bound can be a coarse fallback. Merely increasing `0.6`, sampling only the center slope, or translating this shortcut to C++ does not establish a safe bound.

**Acceptance.** Retain the counterexample and nearby-clearance control, and add a flat-ground control; cover stock and admitted custom ramps, different orientations/footprints, natural approach trajectories, strict and graded contacts, rotor strikes, terrain caches and substep transitions. Compare complete accepted state/event history. Attribute cost only after the corrected exclusion rule is established, preserving 240 Hz and contact refinement where required.

### F44

**The water material silently narrows an admitted shore-fade range.**

The loader accepts `shore_fade_m` from 0.25 to **50 m**. Water material normalization clamps it to **12 m**, while plants and the physical lake surface use the admitted value. Consequently, the same valid authored data can produce different wave envelopes. [Lake loader][lake-loader] [Water material][water-material] [Plants][plants] [Physical surface][lake-surface]

The actual loader accepts a copy of the default lake with fade 50 m. At a common analytic distance 6 m, the source-specified smoothstep factors are:

| Consumer's fade | Calculation | Factor |
| --- | --- | --- |
| Water's clamped 12 m | `smoothstep(6 / 12)` | **0.5** |
| Plant/physics 50 m | `smoothstep(6 / 50)` | **0.039744** |

The scalar probe models the source clamp; it does not instantiate the water material or execute a shader. Actual sampled positions/fade interpolation can introduce other differences, so this ratio is not a measured rendered wave-height ratio. Default fade 5.5 m avoids this issue. The `--lake-file` route admits custom definitions only under its default-field/scenery and amplitude conditions; the candidate changes only fade and meets those constraints. [Lake-world admission][lake-world]

**Repair.** Use one explicit range and normalization contract across loading, water, plants and physics. If the renderer genuinely cannot support the full admitted range, reject it or provide a visible, intentional conversion at admission; do not silently change one consumer. Keep shader inspector hints aligned with the accepted contract.

**Acceptance.** Test minimum, default, 12 m, just-over-12 m and 50 m values through the public loader/material path. Compare the same locations/times and then validate visible shore motion/contact cues. This is a consistency fix, with no claimed CPU/GPU saving.

### F45

**The shader clock assumes periods the loader does not require.**

The shared shader clock wraps at **1024 seconds** and documents that periodic frequencies must be multiples of `1/1024 Hz`. Water and plant shaders use that clock. The physical sampler uses continuous simulation time, while the loader admits arbitrary bounded periods, including **3 seconds**, without a commensurability check. The material passes that in-range period through. [Shader clock][shader-clock] [Wave admission][lake-loader] [Physical sampler][lake-surface] [Render time propagation][clock-callers]

For a sinusoid of period `T`, resetting time by `W` is phase-continuous only when `W/T` is an integer. Here `1024 / 3` leaves a third of a cycle, so reset causes a **2π/3 phase discrepancy** for that component. Default periods 2 and 4 seconds divide 1024 and avoid the problem.

The probe validates a 3-second custom period through the real loader, uses the real `ShaderClock.value()` and physical wave sampler, and selects an actual generated pad coordinate. Between the analytic times **1023.999 and 1024.000 s**, the continuous physical down-height changes by **+0.00003391 m**. Applying the same wave expression at wrapped shader time zero instead changes by **−0.02655827 m** at that point. These are selected analytic samples, not adjacent observed 240 Hz ticks, a rendered 17-minute flight or direct GPU output.

The issue can affect visible water/plant phase relative to continuous physical water height after a wrap for admitted custom periods. This is separate from F42's coordinate-space error and F44's fade normalization. A stock-lake capture alone would not expose it.

**Repair.** Either explicitly constrain supported periods to those satisfying the shared clock contract, or supply bounded per-wave phases derived from authoritative float64 time so arbitrary admitted periods retain continuity. Update/reduce phase consistently across water and plants; preserve authored frequency and physical/render synchronization. Quietly rounding periods changes their meaning and is not a neutral optimization.

**Acceptance.** Sweep immediately before/after wraps for every admitted period class, including defaults and 3 seconds, then verify pause/resume, reset, clock origin, long sessions and rendered continuity. Bound the extra uniform-update/submission cost if phase handling moves to the CPU; no native rewrite is inherently required.

## Mathematical and native implementation priorities

The evidence favors small repairs at the existing boundaries. It does not justify lowering precision or simulation frequency. The original report's observer, flap-invariant, event-evaluation, cloud-cache and readback candidates remain relevant; this pass adds correctness constraints and one input-count candidate, not new measured speedups.

| Area | First useful change | Native/optimization boundary | Evidence required before promotion |
| --- | --- | --- | --- |
| Terrain broad phase | A mathematically conservative contact-footprint bound | Consider prepared terrain-cell bounds and batched queries only after correctness | Point/disc contacts, swept approaches, event/state parity, complete-tick attribution |
| Angle controller | Continuous local reference policy and deterministic half-turn convention | Scalar float64 implementation first; native code must reproduce the chosen law | Boundary sweeps, mode/reset behavior, stock closed-loop recovery and replay |
| Input | Determine whether all-button evidence is needed for the active profile generation | Same-tick cached snapshot or a batch boundary if profiling supports it | Input continuity/failsafe contracts, callback/allocation counts and session cost |
| Wave rendering | Consistent coordinate space, admitted parameters and time phase | Share invariants/uniforms where measured; do not duplicate wave ownership | Matched samples, rendered motion, target-resolution CPU/GPU profiling |
| Replay/settings | Make identity and pending intent explicit state | Usually ordinary control-flow repair, not a native hotspot | Public API/transaction regression tests and package-specific qualification |

For CPU work, measure the full accepted simulation callback, including observers and input, plus kernel attribution; a faster isolated helper does not establish player benefit. For GPU work, keep output/drawable/internal resolution, renderer, quality settings, scene, camera and backend receipts fixed. Qualify 1080p first except native-panel Apple Silicon Retina, following the existing project policy. Separate CPU submission, GPU completion and presentation/pacing. No percentages from unrelated historical experiments should be added together.

## Leads examined but not promoted

| Lead | Disposition |
| --- | --- |
| Deep duplication of packed float arrays | The pinned engine detaches the tested `duplicate(true)` case; no demonstrated checkpoint-alias defect from that lead. This is a different operation from the first report's dictionary-held append alias check. |
| Statistics reconfigure retaining old hop flags | The actual configure/reset path calls `_clear_hop()` and clears the relevant episode state. |
| Airship replay resets time to zero | Declared time-invariant wind/checkpoint behavior; F39 must account for its tick offset rather than label reset as a bug. |
| Non-Metal reconstruction retry/failure state | Backend availability/failure checks exist; no concrete missed guard established. |
| Tiny calibrated axis span and first capture-frame dwell | Requires a realistic admitted calibration sequence and the intended input policy; not promoted from isolated arithmetic suspicion. |
| Anti-windup before motor allocation | Previously tracked and still needs a stock closed-loop saturation/recovery experiment; no duplicate new finding. |
| Reverse-propeller contact during turtle mode | Explicit gameplay simplification, not an accidental missing damage check. |
| Plant shader displacement and static bounds | Missing expansion is a related review lead; no visible culling failure was established. |
| Controller-store mtime reuse and fabricated race history | No ordinary supported-input failure established; omitted from the defect count. |

Earlier exploratory fixture attempts included a built-in-class name collision, a missing directory required by the fingerprint scanner and a receipt-label glob that also matched the import run. These are harness setup failures, not production defects. They were corrected before the final 12-launch collection. The final evidence retains the qualifying logs; the source-identity record lists nonqualifying setup attempts so they are not mistaken for application failures.

## Recommended delivery order

1. Repair F43 and F37 with focused production regressions and complete-session acceptance, while retaining F01–F02 as first-report numerical priorities.
2. Resolve F36 transaction intent and F38–F40 exact-replay semantics. They can be small deliveries with clear contracts and focused checks.
3. Align the three lake contracts, then capture actual rendered behavior at the supported resolution/renderers. Keep default and valid-custom definitions in the comparison.
4. Profile F41 and the first report's remaining CPU/GPU candidates. Promote only a measured, behavior-preserving change with source/backend identity and complete-workload evidence.

The branch adds documentation, evidence and research probes only. It does not merge into main, implement these repairs, change gameplay law or qualify a release.

[settings]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/ui/settings_screen.gd#L1105-L1110
[settings-transaction]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/ui/settings_screen.gd#L1344-L1398
[settings-dirty]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/ui/settings_screen.gd#L1612-L1627
[settings-creation]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/app_root.gd#L1944-L1957
[calibration]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L242-L304
[app-root]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/app_root.gd#L1726-L1747
[controller]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/multirotor/flight_controller.gd#L447-L475
[plant-sampling]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/multirotor/controlled_plant.gd#L288-L325
[controller-tests]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/tests/test_mr_controlled_plant.gd#L193-L220
[airship-log]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/flight_log.gd
[mr-log]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/multirotor/flight_log.gd
[airship-cli]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/tools/airship_flight_log_cli.gd#L34-L66
[logging-guide]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/FLIGHT-LOGGING.md#L401
[airship-session]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/session.gd#L507-L524
[identity-helper]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_log.gd#L467-L493
[native-package]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/app_state/native_package.gd
[startup]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/ui/startup.gd#L70-L73
[scene-entry]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/vehicles/multirotor/multirotor_scene.gd#L1325-L1334
[fixed-wing-log]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_log.gd#L86-L88
[rc-input]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/input/rc_input.gd#L288-L405
[input-callers]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_session.gd#L3087-L3120
[input-prior]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/research/performance-report-2026-11-09.md
[plants]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lake/lake_plants.gd
[lily]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lake/lily_pad.gdshader#L19-L32
[water]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lake/water.gdshader#L126-L133
[godot-spatial]: https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/spatial_shader.html
[terrain-plant]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/multirotor/controlled_plant.gd#L531-L537
[terrain-strict]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/multirotor/controlled_plant.gd#L740-L753
[terrain-graded]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/multirotor/controlled_plant.gd#L1071-L1078
[terrain-substeps]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/multirotor/controlled_plant.gd#L690-L721
[terrain-prior]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/research/drone-racing/audit-2026-11-16/follow-up.md#L103
[dr-plan]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/drone-racing.md#L364-L374
[track]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/ground_vehicle/airfield_track.gd#L20-L47
[mr-session]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/multirotor/session.gd#L237-L365
[lake-loader]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/data/lake_loader.gd#L128-L180
[water-material]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lake/water_material.gd#L21-L52
[lake-surface]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/lake_surface.gd#L452-L467
[lake-world]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lake/lake_world.gd#L10-L32
[shader-clock]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/shader_clock.gd#L8-L36
[clock-callers]: https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/world/world.gd#L1038-L1040
