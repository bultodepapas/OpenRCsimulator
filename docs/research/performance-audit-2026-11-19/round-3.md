# Round three: loading transactions, workload identity and remaining event boundaries

**2026-11-19 · America/Bogota.** Audited main snapshot: **`d736ee8a2eab0b59b0fa2c561a1eef07f5fae396`**. Report branch: **`audit/cpu-gpu-optimization-2026-11-19`**. This is a source audit and controlled reproduction package. It adds **F46–F48**, follows up **F02 and F07**, and records the bounded status of repairs to earlier findings.

**The new findings are two reproduced loading-control defects and one counted CPU-side lighting optimization candidate.** The retained register now contains **48 findings and review items across three dated snapshots**. Current status is recorded separately; repaired original examples remain in their historical reports. The new main has made real progress on event isolation, restore transactions, pixel identity and cloud-cache reconciliation. The remaining problems are primarily at boundaries between owners: pending Home state versus launch state, cancellation versus scene creation, sample collection versus workload identity, and local versus global collision selection.

The [original report](README.md) and [round two](round-2.md) retain their source and test identities. The audit branch keeps its original runtime base; this pass reads newer main through an isolated checkout and immutable Git blobs. It changes research, evidence and navigation documents. The [reproduction runner](../../../research/performance/audit-2026-11-19/round3/README.md) extracts the pinned main source independently of the branch's application files.

## 1. What was established

| Item | Priority | Evidence | Result |
| --- | --- | --- | --- |
| [F46](#f46) | P2 | Production AppRoot methods, controlled worker and backdrop stand-in | Early cancellation loses a pending landscape rebuild. The selected landscape and the retained Home backdrop diverge. |
| [F47](#f47) | P2 | Production AppRoot methods, counted candidate stand-in | Cancelling a helicopter launch during the prefetch drain still permits one construction and `_ready()` before rollback. |
| [F48](#f48) | P3 | Actual lighting rig and preset, headless parameter counter | An instantiated rig in OFF mode makes six subsequent material-parameter writes as its clock advances. |
| [F02 follow-up](#f02-follow-up) | P2 | Actual geometric contact query; synthetic event surfaces | Per-obstacle reduction can lose the global earliest contact anchor. Event-time metadata also needs an explicit bound contract. |
| [F07 follow-up](#f07-follow-up) | P2 | Actual calibration methods with injected samples/verdict | Acquisition can label retained samples with the final workload; automatic High rejection does not compare all newly stored workload fields. |

Priorities describe the repair/qualification queue, not measured frame-time savings. F48 is a performance candidate whose cost still needs attribution. The collision witness requires extremely fine geometry and is a deterministic-ordering boundary case, not an observed stock-flight accident.

### Verification and limits

The consolidated package completed **13 sequential checked launches** with the official Linux x86_64 **Godot 4.8 beta 2, `4.8.beta2.official.cafc17a19`**. There were **zero engine errors**. Twelve launches had zero warnings; the unmodified current auto-calibration test emitted **one ObjectDB-at-exit warning** while passing its 94 assertions. The checked runner permits warnings by default, and the warning remains in the raw evidence.

Four existing focused controls passed: resource-event stepping **90 checks**, collision tie helpers **17**, auto calibration **94**, and cloud-shadow reorder **16**. The final loading probe passed **11 checks**, including four worker-gate preconditions. Additional probes cover actual airship restore/recording, geometric contact selection, event-bound metadata, calibration finalization/reuse, hidden lighting writes and repeated backend-identity calls. Baseline-observation success means the documented behavior recurred; the new defects were not repaired in this branch.

The package pins **712 source/data/support files** and **19 fixture assets**. Its four projects copy 211 source/data files for simulation, 65 for rendering, 694 for loading and seven for the identity control; shared files appear in more than one project. These are dependency counts, not code-coverage claims. Source bytes come from Git blobs, avoiding ambiguity from checkout newline conversion. The exact engine SHA-512, source hashes, fixture substitutions, commands, checked receipts and raw logs are in [evidence](round-3-evidence.json), [source identity](round-3-source-identity.json) and the [fixture manifest](../../../research/performance/audit-2026-11-19/round3/fixture_sources.json).

The final fixture substitutions are narrow and explicit:

- The terrain-only airship probe supplies two assertion-only scenery dependencies. They fail if called; neither is invoked in the exercised path.
- Loading compiles unmodified AppRoot, Home and loading/preparation owners. Thirteen required dependency files redirect only binary-resource `preload` expressions to placeholder scene, texture or audio resources. The probe supplies controlled setup/process plumbing, a preview broker, a backdrop stand-in, a counted flight stand-in and a semaphore-gated resource loader. The real Green landscape JSON and skin-kit registry come from the pinned commit.
- Rendering uses the actual lighting rig/preset over a BoxMesh. Calibration tests inject timing samples or saved verdicts and override only the active-flight predicate where stated.
- The final runner reconstitutes smaller dependency closures than the exploratory copies. It reproduces the observations again under fresh data/config/cache directories.

This environment was unenrolled and had no configured test pool, so the repository's checked runner was used locally. No GPU rendering/timing, FPS gain, native extension, full game interaction, real controller, audio output, release executable, memory soak, macOS/Windows run or full CI qualification is established. The broader asset-dependent airship log test remained inconclusive: it printed zero failed assertions but the wrapper caught 35 engine errors from missing visual assets. It is not counted among the final controls. Failed setup/probe iterations and one nonqualifying loading-fixture exit timeout are retained separately in [the evidence index](round-3-evidence.json).

## 2. New findings

### F46

**Early launch cancellation loses the pending Home landscape rebuild.** Owners: UI-34c, DT-11a and L21–24.

The real Home landscape selector reaches `set_landscape()`. When the speculative flight-scene worker is busy, AppRoot accepts the new landscape, updates the selected field and preferences, and queues a Home rebuild instead of constructing another world immediately. `_flush_home_scene_rebuild()` retains the queued obligation while preparation remains busy. This is useful coalescing: several selections can resolve into one rebuild of the final requested landscape. [Selection signals][selection-signals] [Home selector][home-selector] [Acceptance][landscape] [Queue][rebuild]

`start_flight()` clears `_home_rebuild_queued` and `_home_rebuild_source` before its first feedback checkpoint. If the player cancels there, `_cancel_loading_before_candidate()` resumes/re-attaches the old Home world and completes cancellation. It does not restore the discarded reconciliation request. Once the worker drains, the process loop sees no queued rebuild. The new selector/preferences and the old world can therefore remain paired. [Launch clearing][launch-clear] [Cancellation][cancel] [Process owner][prefetch]

The controlled sequence used the real Green field JSON and the production field validator:

| Sequence | Observed state after worker release |
| --- | --- |
| Busy prefetch → select Green → allow worker to drain | One backdrop rebuild; selected Green, stand-in backdrop Green. |
| Busy prefetch → select Green → Fly → early Cancel → drain | Zero rebuilds; selected Green, stand-in backdrop Club; launch status `cancelled`. |

The stand-in records which source landscape the real rebuild entry point would receive. This establishes the lost transition, not the pixels of a rendered Club backdrop. It does not show flight physics using the wrong field: launch intent remains Green. The defect is that a cancelled operation can leave the player looking at a world that no longer represents the current selection.

**Repair direction.** Keep a pending reconciliation obligation until a successful departure makes that Home generation obsolete, or until a rebuild reconciles the selected configuration. Cancellation and pre-candidate failure should requeue the latest applicable Home state. A generation token or a comparison between accepted configuration and built configuration is more reliable than restoring one old Boolean blindly: the player may have made several selections before Fly, and Home may have been replaced during another route.

**Acceptance.** Add the busy-worker/change/Fly/Cancel sequence to the owning loading test, together with the no-Fly control, multiple selections, constructor failure, successful departure, repeated cancellation, Home recreation and quit. Verify the actual rendered backdrop with stock assets. Preserve preview/resource ownership and coalescing; rebuilding every intermediate selection would defeat the existing optimization.

### F47

**A cancelled rotorcraft launch constructs and attaches a candidate after the shared prefetch drain.** Owners: UI-34c, DT-11a and the rotorcraft track.

An ordinary fixed-wing Home can already have a speculative scene worker running when the player switches to the helicopter. The helicopter route bypasses fixed-wing resource/scene preparation, passes its initial cancellation check, and then waits for `_home_scene_preparation_busy()` to clear. That second loop yields across frames but checks only whether AppRoot remains in the tree. It does not recheck cancellation. [Route and drain][launch-drain] [Prefetch ownership][prefetch]

When the worker finishes, AppRoot calls `_create_flight()` and later `add_child(flight)`. Only after attachment does it convert `_loading_cancelled` into a startup error and roll the candidate back. The actual helicopter `_ready()` performs synchronous world/model/session/effects/audio setup. Setting a node's processing mode to disabled does not avoid this initialization sequence; the counted stand-in's `_ready()` is observed at attachment. [Attachment and rollback][launch-attach] [Real helicopter initialization][helicopter-ready]

| Controlled cancellation point | Candidate constructions | Candidate `_ready()` calls | Final state |
| --- | ---: | ---: | --- |
| First feedback checkpoint | 0 | 0 | Cancelled, Home retained. |
| Waiting for prior prefetch to drain | 1 | 1 | Candidate subsequently removed; cancelled, Home restored. |

The probe calls unmodified AppRoot methods and uses the actual preparation/scene-load owners with a gated loader callback. It counts a lightweight candidate. It does not build the real helicopter, time the UI freeze, measure memory or determine how often a real disk/cache produces this interleaving. The source establishes that the admitted real candidate has substantial synchronous setup; the probe establishes that cancellation does not prevent admission at this boundary.

**Repair direction.** Continue draining work whose resource ownership requires it, but distinguish completion of that drain from permission to construct the next scene. Recheck the cancellation/lifetime state during the wait and immediately before candidate creation and attachment. Route a cancelled request through the existing before-candidate rollback. Keep cancellation idempotent and preserve the worker's join/cache-publication rules.

The existing loading test already covers early cancellation and fixed-wing cancellation during its scene load. Its zero-candidate assertions do not cover this separate rotorcraft wait. Add a gate at that wait and cancel before it, during it, on the frame it finishes and at the final pre-creation boundary. The expected invariant is zero newly constructed candidates after cancellation at that boundary, alongside correct Home restoration and worker cleanup. [Existing test scope][loading-tests]

This is also an optimization opportunity with a direct correctness basis: avoiding a cancelled world build removes work at its source. It should precede attempts to accelerate that same unnecessary build with C++ or another thread.

### F48

**An explicit aircraft-lighting rig publishes hidden material parameters in mode OFF.** Owners: FW-RGB, coordinated with DT-MAC.

The flight installs the RGB rig for a configured preset/custom lighting profile. Main supplies the current mode and calls `advance()` each presentation frame. Explicit OFF, and daytime Automatic when it resolves to OFF, hide the kit and its lamps. `advance()` still walks lamp/material updates, including time-dependent values; `_set_param()` counts actual setter calls after its equality cache. [Installation][lighting-install] [Frame caller][lighting-frame] [Mode resolution][lighting-state] [Visibility][lighting-mode] [Updates][lighting-advance] [Counter][lighting-counter]

The checked fixture configured the actual `classic_rc` preset on a BoxMesh, selected OFF and examined a strobe material:

| Operation | Aggregate rig parameter writes | Tested strobe clock | Visibility |
| --- | ---: | ---: | --- |
| First advance at 1 s | 18 | 1 | Kit and strobe hidden. |
| Advance at 2 s | 6 | 2 | Kit and strobe hidden. |
| Repeat 2 s | 0 | 2 | Hidden. |
| Set ALL; advance at 3 s | 6 | 3 | Kit and strobe visible. |

The aggregate counter does not identify all six calls individually as clock writes. It does show that the equality guard removes unchanged publications while changed material values still reach setters for this hidden rig. Godot's API defines the material-uniform setter; its invocation count alone does not reveal driver uploads or GPU execution. [ShaderMaterial API][godot-3]

**Scope matters.** The stock inherited-lighting path is lazy and does not instantiate this rig through the reviewed explicit-profile path. Profile selection `disabled` already returns early. Mode OFF on an existing preset/custom rig is the observed case. One synthetic rig does not establish fleet-wide cost or a measurable frame-rate gain.

**Repair direction.** Defer publications for contributions that cannot be visible, preserve logical state, and synchronously reconcile current clock, pattern, exposure, telemetry and gates when a contribution becomes visible. A blanket early return from `advance()` is unsafe without more work: VFX advancement also tracks maneuver/cue history, even when OFF suppresses births. Skipping it can change re-enable behavior. Skins, standard emissive materials, rewind/reset, residual effects and scene-budget ownership also need deliberate handling. [VFX lifecycle][lighting-vfx]

**Acceptance.** Count the same workload in OFF, daytime Automatic, NAV, ALL and `selection=disabled`; compare resets, time rewinds, pattern changes, gear-gated lamps, exposure, telemetry-driven skins and VFX re-enable. Verify multiple views. Then measure paired complete-frame CPU/GPU cost at the target resolutions. The present result is a bounded CPU-side optimization candidate, with no claimed GPU saving.

## 3. Follow-up to existing findings

### F02 follow-up

**An exact local ordering is insufficient when a later reduction discards its anchor.**

The new event solver sorts by exact time, forms a tie group relative to the earliest root, and applies the deterministic priority/ID rule inside that group. Its six-permutation control passes. The scenery/lake helper permutation controls also pass. Those are meaningful repairs to the non-transitive comparator reported previously. [Event selection][events] [Event controls][event-tests] [Contact order helper][contact-order]

Scenery `contacts()` introduces another step: it selects one priority representative per obstacle, then orders those representatives. A representative can be later than that obstacle's true earliest contact. The second stage then forms its tie window around a later anchor. Tolerance-based reduction is not associative: reducing each subgroup first can differ from grouping the original candidates globally. [Two-stage selection][contacts]

The checked geometric witness uses two boxes, two hull probes, identity attitude and a kinematically consistent **10 m/s** translation of **10/240 m** over one 240 Hz tick. Individually evaluated contact fractions are:

| Candidate | Fraction of tick | Difference from true earliest |
| --- | ---: | ---: |
| `z_box`, point 1 | 0.499999975999245 | 0 |
| `z_box`, point 0 | 0.499999975999997 | About 0.751 × 10⁻¹² |
| `a_box`, point 0 | 0.499999976000748 | About 1.503 × 10⁻¹² |

`FRACTION_TIE` is **10⁻¹²**. The lower point index wins locally for `z_box`, discarding its true earliest anchor. `a_box` is then within the new, later representative's tolerance window and wins by ID. The full query returns `a_box` first, although it lies outside the window measured from the original global earliest contact. A wider-separation control returns `z_box`.

`first_hit()` consumes the first ordered contact and feeds flight collision processing. The probe uses hard-terminal responses for both boxes; it does not establish a changed damage severity or stock-flight outcome. Its geometry requires exceptionally fine placement. This remains **F02**, with new integration-level evidence; it is not counted as another unrelated bug. [Consumer][contact-consumer]

**Repair/acceptance.** Preserve the true earliest time through reduction, or form global tie membership before choosing obstacle representatives. Specify how representatives relate to global group membership rather than merely replacing a comparator again. Cover multiple points in one obstacle, multiple obstacles, actual `contacts()`/`first_hit()` calls, all discovery permutations and wider-gap controls. Preserve contact/damage policy and replay determinism.

#### Event-time metadata: clarify what the bound guarantees

A second component probe gives the event stepper independent linear time surfaces rooted at **0.002 s** and **0.00200000000075 s** within a 1/240 s interval. With the later event having priority, both transitions occur at the later shared boundary. The earlier event is emitted approximately **0.749999889 ps** after its exact root, but retains `time_error_bound_s ≈ 0.500000215 ps` from its own original locator bracket. A single-event control is exact and satisfies its bound; reverse priority shifts the later event early. [Shared publication][events] [Locator bracket][root-bracket]

If that field guarantees the emitted timestamp's distance from the event's original root, the observation violates the guarantee. If it only reports the original locator's bracket width, that meaning and its association with the original root must be explicit. No downstream reliance or stock fuel/engine occurrence was established, so this is retained as an F02 metadata qualification.

For the first interpretation, the triangle inequality gives a conservative starting point:

\[
\epsilon'_i \geq \epsilon_i + |t_{\mathrm{shared}}-\hat t_i|.
\]

Here `epsilon_i` bounds the individual located root and `hat t_i` is its estimated time. Coupled transitions can change another event's surface, so a complete contract must also state which pre-transition surface/root the bound describes. The useful action is to define and test that contract before porting the event code or changing numerical tolerances.

### F07 follow-up

**Persisting more workload fields helps consumers, but acquisition and automatic High selection still need consistent identity.**

Format 4 stores output pixels, a nominal internal 3D pixel count derived from the applied viewport scale, and 3D MSAA. The nominal size is not a backend allocation query; actual SDK execution, internal fallback and allocated render dimensions remain unobserved here. `needed()` and Scene Detail reuse compare relevant stored fields. Two remaining boundaries are independently exercised. [Calibration identity][calibration-identity] [Scene Detail][scene-detail]

**A. Acquisition keeps samples across a workload change.** The graphics calibrator pauses sampling when the flight is held, retaining elapsed active time and sample arrays. Settings is available from Pause and can preview a new resolution/reconstruction/MSAA configuration. On resumption, the same calibration continues. The record takes `current_workload()` at completion rather than verifying one identity throughout the sampled interval. The similarly named pause-time `cancel_calibration()` concerns the radio wizard, not this graphics calibrator. [Collector][calibration] [Attachment eligibility][calibration-attach] [Settings access][settings-open] [Settings application][settings-apply] [Effective MSAA][reconstruction]

The probe inserted **300 synthetic 20 ms GPU samples**, plus synthetic CPU/interval values, under a 3840×2160 / 4×-MSAA fixture viewport. It then changed the viewport to 1920×1080 / MSAA off and called the inherited production `_process()` to finalize. The saved complete record carried the final 1080p/off identity and `needed()` returned false for that identity. It did not match the original workload. The process used Compatibility; this does not demonstrate an actual High rejection or real GPU sample mixture. Only the active-flight predicate was overridden, and the production evaluation/storage/reuse logic executed.

The ordinary pause/settings/resume route is source-supported. Scene Detail may defer rebuilding scenery until a later world build, so resolution, reconstruction and MSAA are the concrete live-change examples here. Do not claim that every displayed setting changes every active workload immediately.

**Repair.** Capture an acquisition identity before sampling and compare the relevant applied settings and nominal workload identity at sample/resume boundaries. On a change, discard/restart or explicitly invalidate the interval. Keep retries bounded and honor explicit user settings. Merely labeling the completed record accurately with the final viewport is insufficient when its samples came from another configuration.

**B. High rejection omits stored internal workload fields.** A saved complete Forward+ High rejection at 1080p / 4× MSAA makes `needed()` false for the same workload. Changing the hypothetical workload to MSAA off makes `needed()` true, yet `rejects_high(adapter, pixels)` still returns true at the same output size. A materially smaller-screen control correctly returns false. The veto compares output-size policy but does not receive internal pixels or MSAA. [Consumer mismatch][calibration-identity]

This veto feeds automatic renderer selection on the eligible persistent exported Windows/Linux x86-64 route. Explicit High has different handling. Startup evaluates this policy before the saved display preferences are applied; the current Standard viewport is therefore not automatically the prospective High workload. [Renderer facts and plan][startup-renderer] [Startup order][startup-order]

**Repair.** Resolve the prospective High workload at the policy boundary, or define a conservative invalidation/re-evaluation policy when it is unknown. Preserve the intentional one-sided output-size policy and explicit override. The probe does not prove that the lighter workload would satisfy 60 Hz; it proves that the acquisition/reuse APIs disagree about whether the old workload is applicable.

## 4. Status of earlier repairs on this main snapshot

| Finding | Bounded status at `d736ee8a` | Remaining qualification |
| --- | --- | --- |
| F01 | Original mixed-crossing example repaired; current 90-check suite passes. | Crossings invisible to every sample and real vehicle trajectories are outside this proof. |
| F02 | Original comparator/permutation repairs pass. | Global-anchor and metadata boundaries above remain. |
| F03 | Invalid restore is prepared before reset publication. Focused active-recorder test passes. | Evaluator-failure injection and the full asset-dependent suite remain unqualified. |
| F04 | Format 4 records output pixels and invalidates older records; headless size controls pass. | Native drawable, Retina and display-scale behavior. |
| F05 | The specific larger-measurement/smaller-screen veto is guarded. | Workload-specific reuse remains F07. |
| F06 | Scene Detail uses applied scale once reconstruction metadata exists. | Native Retina, provider failure and fallback behavior. |
| F07 | Internal pixels/MSAA now participate in some reuse decisions. | Collection consistency and High-veto target identity above. |
| F08 | SubViewport activity observed during sampling is accumulated. | Root timing completeness does not imply complete GPU attribution or coverage of all one-shot views. |
| F28 | Desired cloud owners are reconciled before admission/eviction; 16 controls pass. | Synthetic texture retention is not a GPU bake or timing result. |
| F31 | Exact-zero optical density bypass is present before expensive cloud evaluation. | Shader execution, rendered equivalence and measured cost. |

Relevant current implementations: [workload identity][calibration-identity], [nominal-size limits][nominal-size], [applied scale][scene-detail], [cloud ownership][cloud-cache] and [the sky bypass][sky].

The F03 probe used a running terrain-only airship session and real recorder. NaN body, degenerate quaternion and NaN continuous input were all refused with unchanged state, inputs, continuous data, tape and tick; no reset/fault/pause was published, and recording continued. A valid restore emitted once and closed a complete three-row recording. [Restore transaction][restore] [Replacement validation][kernel-replacement]

The [structured status file](round-3-status.json) also compares the cited round-two sources. Their original fault sites remain unchanged. Some dependencies changed—graphics calibration for F36, airship restore for F39—so the status avoids claiming that every old dependency is byte-identical or that the old probes were rerun. The earlier Angle-control and conservative-terrain concerns remain higher-priority correctness work than small setter-count savings. Their original reproductions and limits remain in [round two](round-2.md).

## 5. CPU, GPU, mathematics and native-code opportunities

### Attribute the complete cost before changing the execution language

The new loading findings expose work that should be cancelled or reconciled before it reaches expensive construction. The lighting candidate exposes publication that may be unnecessary for hidden contributions. These are ownership/scheduling opportunities; translating the existing sequence to native code would retain the incorrect sequence and could retain most of the rendering-server cost.

For computational candidates already retained in F20–F26, preserve the mathematical contract: float64 state, 240 Hz accepted ticks, exact event ordering, conservative collision bounds, accepted-observer ownership, source/binary receipts and fallback behavior. Benchmark the whole session and relevant observers, not only an evaluator. Godot's profiling guidance supports attributing the dominant work; hardware-specific rendering behavior requires actual target measurements. [Existing priorities][priorities] [CPU profiling][godot-0] [GPU attribution][godot-1]

| Area | Useful next experiment | Decision gate |
| --- | --- | --- |
| F46/F47 loading | Preserve pending Home reconciliation and stop cancelled candidate admission. | Real menu state, zero post-cancel constructions at the tested boundary, drained workers and real cold/warm load traces. |
| F48 lighting | Defer invisible material publications, retain logical/VFX histories and refresh on enable. | Same visual/lifecycle behavior, reduced setter counts and paired complete-frame cost. |
| Event handling | Retain global anchors and define time-bound semantics before changing reductions or porting. | Deterministic geometric/permutation controls, accepted-state and event equivalence. |
| F20–F25 CPU work | Hoist only verified invariants; reuse accepted observations within explicit ownership boundaries. | Equivalent state/event bytes, meaningful allocation/callback reduction and full-session timing. |
| F26 native wind | Revisit the retained candidate with matching mirrored native source/receipt qualification. | Actual selected backend and whole-flight gain, including fallback; do not bypass identity guards. |
| F29 cloud transport | Separate bake, GPU readback, conversion and re-upload costs; compare GPU-resident/offline options. | Native renderer timing, peak residency and lifecycle correctness. |
| F30 vegetation | Compare spatial chunks/visible ranges with current shader collapse, across active views. | Submission/vertex savings outweigh extra draw calls without incorrect culling. |
| F07/F08 measurement | Keep acquisition identity consistent and state timing coverage explicitly. | Decisions made from applicable samples with known coverage. |

Godot's thread-safety guidance also matters to proposed loading/cloud parallelism: active SceneTree interactions and GPU-resource work have ownership and synchronization constraints. Moving a call to a worker is not a sufficient optimization design. [Thread-safe APIs][godot-2]

### Revalidated existing cost: Nitro identity reads

This pass followed the ground-vehicle tick guard into `NitroDynamics.backend_identity()`. It composes the active body identity with current artifacts for the Nitro adapter and body source. The content cache reuses SHA-256 only after reopening and comparing the actual file bytes. The guard runs before the paused early return. This is deliberate content-verification behavior already investigated in **RCV-41**, not a newly discovered missing cache. [Tick][ground-tick] [Backend guard][backend-guard] [Composite identity][nitro-identity] [Content verification][artifact-read] [Prior RCV-41 evidence][rcv41]

At the pinned source sizes, one composite lookup checks **21,400 + 103,044 = 124,444 bytes** in those two artifacts. At 240 lookups this is **29,866,560 logical bytes**, approximately **28.48 MiB**, before other identity work. That is source-derived arithmetic for the reviewed source-build path. It is not a disk-throughput measurement: operating-system caches may satisfy reads, and packaged artifact sizes/paths differ.

The small engine control made 240 repeated Nitro identity calls and 240 body-identity calls after warmup, confirming stable returned identities on the reference backend. It did not measure syscall counts. A `strace` attempt was blocked by the environment's ptrace policy before Godot launched and is explicitly nonqualifying. The cached body identity alone does not perform the same two fresh artifact reads on every call. [Body cache][body-identity]

An immutable installed-artifact/session-generation contract could make reuse cheaper, but it would change when source changes are detected. That needs an explicit owner decision and negative tests for changes/deletion/remapping/backend switches. Reusing only file size or modification time would weaken the existing contract. RCV-41 already rejected that shortcut and retained byte verification. Its historical timings and RCV-42's later transport timings are not measurements of this revision. [RCV-41][rcv41] [RCV-42][rcv42]

### Measurement priorities

Use **1920×1080 first** on ordinary target systems, with the repository's **native-panel exception for Apple Silicon Retina**. Record output, drawable and internal pixels separately, marking nominal estimates when backend dimensions cannot be observed. Keep the engine, renderer, selected native backend, aircraft/field/input tape, weather, lighting mode, MSAA, reconstruction and secondary-view state attached to each result.

For CPU experiments, collect complete callback/session distributions and observer phases; for GPU work, capture actual renderer cost, submissions, resolution and active views. Compare cold versus warm loading, recording enabled versus disabled, and relevant feature transitions. Include p50/p95/p99/max, hitch counts and simulation/wall-time behavior where applicable. Operation counts prioritize experiments; they do not substitute for these acceptance measurements. The original F27 measurement limitations remain relevant.

## 6. Organization improvements tied to these failures

The important cleanup is to make invariants have one owner. F46 and F47 arise in the same AppRoot launch sequence but involve distinct obligations: pending Home configuration, in-flight resource ownership, cancellation state, candidate admission and rollback. A small explicit launch-state object with one generation/token and clear phases would make the legal transitions reviewable. It should centralize final admission checks and rollback obligations while leaving vehicle-specific construction in its existing owners. This recommendation follows the observed state losses and late admission; file length alone is not a defect.

Calibration needs a similarly explicit interval identity. Acquisition, saved verdict applicability and automatic renderer policy should use compatible definitions while acknowledging that startup's prospective High workload differs from its current viewport. A versioned record is useful only when its producer and consumers agree about the represented work.

The existing tests also show a coverage lesson. Local helper permutations passed while composed geometry selection still failed. Fixed-wing cancellation tests passed while a separate rotorcraft wait admitted work. Add controls at these integration boundaries; avoid expanding every audit repair into an indiscriminate full-suite run. The failing boundary should have a small deterministic regression, followed by the owning real-world/renderer qualification.

## 7. Recommended sequence

1. **Preserve correctness and intent.** Keep the earlier high-priority controller/terrain work visible. Repair F46/F47 with generation-aware reconciliation and pre-admission cancellation checks; add the composed F02 geometric regression.
2. **Make calibration evidence applicable.** Repair F07 acquisition identity and define the prospective High-veto policy. Keep F08's incomplete GPU-attribution status explicit.
3. **Remove demonstrably unnecessary work.** Prototype the narrow F48 publication suppression while preserving VFX/skin/rewind behavior. Verify correctness before timing it.
4. **Profile complete workloads and then choose native/math work.** Reuse existing retained candidates and measurements as leads, qualify current source/binary pairs, and measure the target hardware. Avoid treating the RCV identity-read arithmetic, setter counts or historical benchmarks as new speedup evidence.

The deliverable includes the [new structured findings](round-3-findings.json), [updated statuses](round-3-status.json), [raw evidence](round-3-evidence.json), [source identities](round-3-source-identity.json), [primary-source ledger](round-3-sources.json) and [portable reproduction package](../../../research/performance/audit-2026-11-19/round3/README.md). Runtime repair and hardware performance qualification remain separate, reviewable work.

[launch-clear]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L1460-L1489
[launch-drain]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L1495-L1520
[launch-attach]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L1603-L1645
[cancel]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L1921-L1941
[rebuild]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L4338-L4361
[landscape]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L4481-L4510
[prefetch]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L494-L576
[selection-signals]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L850-L861
[home-selector]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/ui/home.gd#L2135-L2154
[helicopter-ready]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/helicopter_main.gd#L102-L197
[loading-tests]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/tests/test_flight_loading.gd#L598-L641
[lighting-install]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/main.gd#L3492-L3504
[lighting-frame]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/main.gd#L1547-L1561
[lighting-mode]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/lighting/aircraft_lighting_rig_3d.gd#L89-L178
[lighting-advance]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/lighting/aircraft_lighting_rig_3d.gd#L181-L263
[lighting-counter]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/lighting/aircraft_lighting_rig_3d.gd#L651-L664
[lighting-vfx]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/lighting/lighting_vfx.gd#L133-L195
[lighting-state]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/world/aircraft_light_state.gd#L24-L64
[events]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/physics/resource_event_step.gd#L89-L173
[root-bracket]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/physics/resource_event_step.gd#L254-L287
[event-tests]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/tests/test_resource_event_step.gd#L190-L238
[contacts]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/sim/scenery_collision.gd#L125-L181
[contact-order]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/sim/scenery_collision.gd#L655-L686
[contact-consumer]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/sim/flight_session.gd#L3487-L3533
[restore]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/sim/airship/session.gd#L511-L532
[kernel-replacement]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/sim/simulation.gd#L125-L158
[calibration]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/auto_calibration.gd#L100-L137
[calibration-identity]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/auto_calibration.gd#L301-L374
[calibration-attach]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L1728-L1747
[settings-open]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L1944-L1951
[settings-apply]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L2062-L2081
[reconstruction]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/reconstruction.gd#L254-L272
[startup-renderer]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_state/renderer_preference.gd#L105-L191
[startup-order]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/app_root.gd#L415-L454
[scene-detail]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/scene_detail.gd#L124-L164
[cloud-cache]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/cloud_shadow_map.gd#L85-L154
[sky]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/sky.gdshader#L213-L282
[nitro-identity]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/physics/ground_vehicle/nitro_dynamics.gd#L37-L53
[body-identity]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/physics/ground_vehicle/vehicle_dynamics.gd#L90-L101
[artifact-read]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/physics/ground_vehicle/vehicle_dynamics.gd#L140-L195
[ground-tick]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/sim/ground_vehicle/session.gd#L469-L485
[backend-guard]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/sim/ground_vehicle/session.gd#L1838-L1841
[ground-scene]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/vehicles/ground/ground_scene.gd#L492-L503
[rcv41]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/docs/research/rc-monster-truck/RCV-41/README.md#L1-L50
[rcv42]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/docs/research/rc-monster-truck/RCV-42/README.md#L1-L43
[priorities]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/docs/plans/optimization-priorities.md#L1-L110
[native-wind]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/research/native-kernel/README.md#L455-L482
[godot-0]: https://docs.godotengine.org/en/latest/tutorials/performance/cpu_optimization.html
[godot-1]: https://docs.godotengine.org/en/latest/tutorials/performance/gpu_optimization.html
[godot-2]: https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html
[godot-3]: https://docs.godotengine.org/en/latest/classes/class_shadermaterial.html
[godot-4]: https://docs.godotengine.org/en/latest/classes/class_viewport.html
[nominal-size]: https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/reconstruction.gd#L671-L691
