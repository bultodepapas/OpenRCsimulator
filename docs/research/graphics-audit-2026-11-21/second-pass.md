# Second pass — deeper graphics, native and frame-time opportunities

**Branch:** `graphics-audit` · **First-pass application:** [`57abea025f62b20233ca281d58d2acbee4ab8b8e`](https://github.com/bultodepapas/OpenRCsimulator/commit/57abea025f62b20233ca281d58d2acbee4ab8b8e) · **Newer-main cross-check:** [`6b2228c7633a34e38cb05d92e3ca50893810e02b`](https://github.com/bultodepapas/OpenRCsimulator/commit/6b2228c7633a34e38cb05d92e3ca50893810e02b), v0.3.2 · **Engine:** official `4.8.beta2.official.cafc17a19`.

The continued investigation adds **16 scoped findings and experiments**. The strongest new leads are process-thread Nitro PCM synthesis, repeated propeller calculations inside qualifying native stages, and Workshop loading/thumbnail work that survives existing caches. Accepted support-event proof work deepens the earlier contact finding, and native spatial-time preparation is explicitly a continuation of F26. Smaller hidden-feature paths and GPU/lifecycle hypotheses remain useful experiments, without being promoted to measured bottlenecks.

**Measured here:** an isolated, unchanged Nitro audio component under synthetic API inputs. **Confirmed from code:** repeated calculations, API calls, validation, retention and lifecycle transitions under the specified conditions. **Still unmeasured:** whole-product frame impact, native-candidate savings, real audio underruns, compiled shader work and physical-GPU/display behavior. This is an audit extension; production runtime, shaders, native code and workflows are unchanged.

Main advanced while the audit was running. This branch retains its original application base; it has not merged those unrelated changes. The [source inventory](second-pass-evidence.json) binds cited files to both revisions, and the detached audio fixture explicitly extracts the newer immutable revision. Findings are limited to those inspected bytes, not a promise about a moving main.

## Reports and evidence

| Deliverable | Contents |
| --- | --- |
| [Runtime and native investigation](second-pass-runtime.md) | Nitro component timings, native propeller duplication, incident proofs, hidden debug work, consented telemetry and native wind follow-up |
| [Rendering and presentation investigation](second-pass-rendering.md) | Smoke buffer/tape contracts, authored lighting, rotor-profile construction and zero-flash shader hypothesis |
| [Lifecycle and cache investigation](second-pass-lifecycle.md) | Home shadows, Library scans, warm thumbnail validation, covered-Home scale and bounded trial retention |
| [Machine-readable evidence](second-pass-evidence.json) | Source identities, raw audio samples and strict receipts, CI snapshot/log excerpts, arithmetic and review dispositions |
| [Reproduction instructions](../../../research/performance/graphics-audit-2026-11-21/README.md) | Unchanged-source, pinned-engine detached audio probe; no application, GPU or physical audio benchmark |

## Finding register

Priority means **investigation order**, not measured severity or an instruction to implement every item. Each detailed entry contains its trigger, counterevidence, smallest credible experiment and acceptance obligations.

| ID | Opportunity | Evidence and scope | Next action |
| --- | --- | --- | --- |
| S01 | Nitro PCM synthesis on the process thread | Measured detached component; selected MONSTER CAR 2 | First native producer candidate; pair whole-vehicle/audio measurements |
| S02 | Duplicate native Ct/Cp results inside one stage | Source-confirmed guarded P-51/F4U cases | Inspect optimized execution; test invocation-local reuse under exact guards |
| S03 | Support events repeat validation, JSON and proof hashes | Interactive fixed-wing contact; fresh valid events | Attribute full callback; empty-event fast path before evidence-format redesign |
| S04 | Hidden contact debug mesh cleared every frame | Both ground cars; API count only | Narrow dirty/visibility-state experiment if material |
| S05 | Broad telemetry context and empty expiry each frame | Consented eligible interactive route only | Empty-queue shortcut; profile before splitting context ownership |
| S06 | Smoke arrays cleared/submitted without births | Eligible stock/Workshop smoke; buffers already reused | Separate exact zero-buffer reuse from changed observable uniforms |
| S07 | Independent Workshop smoke derives unused emitter wash | GP Extra custom outlets; source tape still observes wash | Contract-design experiment; exact-tape requirements can rule it out |
| S08 | Authored lighting resolves hidden/unchanged patterns | Workshop lighting; shader writes already cached | Cache immutable metadata; preserve phase, preferences and retry state |
| S09 | Four rotor-profile attach attempts on entry | Cold multirotor work; builds depend on valid geometry | Extend verified offline-profile pattern if worthwhile |
| S10 | Zero-radiance storm flash expressions | Optional storms; source expression only | Native-GPU zero/nonzero-flash A/B and image comparison |
| S11 | Same-model Home shadow binding rebuilds projector | Nonempty shape/enabled cue; fallback differs | Idempotent bind experiment before another cache |
| S12 | Repeated full Library scans retain all loaded records | Workshop/Library entry; scales with saved variants | Validated summary stream; share parsing inside one load transaction |
| S13 | Warm thumbnail lookup follows validation/compilation | Readable saved variants; miss adds image retrieval | Attribute load/freeze/capture; preserve live dependency checks |
| S14 | Workshop restores a reduced Home backdrop scale | Prior Home reduction/ownership, compatible scaling | Measure root/preview pixels and ownership before policy changes |
| S15 | Trial retains a bounded inactive world/editor | Intentional rollback/lifecycle design | Unique-resource residency and return-cycle experiment, not a leak claim |
| S16 | Native spatial field repeats time-only preparation | Lower-confidence C++ continuation of F26 | Exact stage-local preparation, owned sampler lifetime and new qualification |

## What the new measurement establishes

The final Linux x86_64 component run passed **43 checks, zero errors and zero warnings**, including bounded requests, silence/phase controls and exact PCM/state equality for one block-split fixture. It timed 41 consecutive calls per case after one second of generated warm-up. Run 04 retains the full inputs, every duration, output identity and checked-runner report.

For a **synthetic** running 6,000-RPM voice input, the final median was **609 µs for 368 frames** and **1,942 µs for 1,103 frames**. Those buffers represent approximately 16.69 ms and 50.02 ms of sound. A synthetic fuel-empty/positive-RPM input with zero flow/throttle produced silent PCM while taking **564 µs** and **1,650 µs** for those sizes. This demonstrates detached implementation cost, not the duration of an actual vehicle coast-down or a product frame regression. A synthetic stopped zero-RPM input was cheaper but still entered the sample loop. The paused direct-API control returned at the timer's 0–1 µs resolution; production pause already bypasses `render()` entirely.

**All measured snapshots are hand-authored, not captured or verified vehicle telemetry.** Earlier exploratory cases contained incompatible derived fields; run 04 corrects no-combustion flow/throttle and retains every input explicitly. Running cases still contain synthetic flow/clutch combinations. The 38,000-RPM row matches the car's authored RPM ceiling only, while 45,000 RPM is the voice's separate clamp boundary. Earlier runs remain visible but are not product evidence or paired speedup trials. There is no implemented native counterpart, so **there is no measured native speedup**. Godot's compiled-producer guidance supports the experiment, not a numerical prediction ([AudioStreamGenerator](https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html)).

## Mathematical boundaries

- **Audio:** steady no-underrun playback at 22,050 frames/s and positive current RPM executes nine exhaust plus two rattle sine evaluations per sample: `22,050 × 11 = 242,550/s`. Optional clutch/transient terms raise the conditional upper bound to `22,050 × 14 = 308,700/s`; not every high-RPM case executes all fourteen. The refill target is `ceil(0.05 × 22,050) = 1,103` frames. These are source counts, not script-to-engine push counts or CPU timings.
- **Support proofs:** three continuously compressed supports, 240 fresh accepted ticks/s and valid bindings imply `3 × 240 = 720` per-event proof hashes/s. IDs contain the tick. Empty batches and ended contacts differ; these are built-in JSON/SHA operations, not 720 archive writes.
- **Smoke arrays:** four emitters, six arrays each and 32 elements per array imply 24 fills over 768 packed elements and 24 array setters per advancing presentation-clock update. No GPU byte count follows without the actual uniform layout and engine/driver behavior.
- **Native propeller:** removing one of two equal Ct/Cp evaluations halves that repeated source operation on its exact branch, not the stage. Calls per tick depend on stage/substep/observer activity; no universal four-stage-per-tick throughput is assumed.
- **Covered Home:** at unchanged output dimensions, internal pixel area changes by `(s_base / s_low)^2`. For the existing 0.70 step with base 1.0, restoring 0.70→1.0 means about 2.04 times the internal pixels, not a predicted 2.04 times GPU time. Fixed passes, preview update mode and visible coverage remain separate.
- **Whole-program gain:** if measured CPU fraction `f` improves by factor `s` without added work, the serial model is `1 / (1 - f + f/s)`. An illustrative 4% fraction made ten times faster gives about 1.037 times total CPU throughput. Neither `f=4%` nor a tenfold voice gain was measured here; GPU/display limits can prevent any FPS gain.

The [arithmetic object](second-pass-evidence.json) records inputs and results. Establish the fraction of whole-process work actually affected before justifying a native port.

## GitHub/CI follow-up

At **2026-11-21 21:20:02 UTC**, newer-main [CI run 44949712062](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44949712062) remained in progress. Its [release-preflight job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44949712062/job/136984719019) completed successfully and logged v0.3.2 at exactly `6b2228c…`. This supersedes the original missing-UID blockage **for that newer revision only**. It does not retroactively make the historical baseline pass. Native qualification, application partitions and visual captures were still running in the retained snapshot; full CI or GPU qualification is not claimed.

A separate [Windows test-queue run 44946381060](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44946381060), at `caa45ce…`, failed because `test_breakaway_child_survives_kill_on_close` imports an unavailable `psutil`. The log reports **454 tests, one error, 32 skips**; later protocol/runner/research steps were skipped. The [workflow](https://github.com/bultodepapas/OpenRCsimulator/blob/6b2228c7633a34e38cb05d92e3ca50893810e02b/.github/workflows/testqueue-windows.yml#L70-L93) configures Python and goes directly to tests, while [existing resource requirements](https://github.com/bultodepapas/OpenRCsimulator/blob/6b2228c7633a34e38cb05d92e3ca50893810e02b/tools/godot/requirements-resources.txt) already pin `psutil`. Install the owning requirements before this dependent group and rerun the actual Windows lane. This is an evidence-infrastructure defect, not an FPS finding or demonstrated process-containment failure.

## Independent review and remaining validation

Three existing specialists continued under `docs/SUBAGENTS.md`, then cross-reviewed the source findings. The lead owned component launches, source comparison, CI inspection, integration and publication. Review materially changed the result:

- Removed default Stik as evidence for wake duplication; separated gas, real glow, nonspatial hub flow and transported-wake-only branches.
- Kept `prop_torque` separate because its floating-point operation order deliberately differs. No fast-math, reference rewrite or receipt bypass is proposed.
- Corrected audio input reachability, authored/clamp limits, paused-player gating, timer semantics and result validation. The final wrapper checks persisted results and relevant fixture identities; final review also corrected no-combustion inputs and explicitly scoped all rows as synthetic.
- Reclassified broad smoke shortcuts as observable tape/uniform changes; narrowed exact-zero-buffer reuse.
- Corrected four rotor builds to attach attempts, qualified empty shadow shapes and distinguished process callbacks from display presentation.
- Identified favorites-file reads during filtering and three conditional base parses; retained dependency checks bracketing compilation.

No native library or graphics workload was launched for the new candidates. No Windows/Mac hardware, real audio playback, GPU capture, residency soak or whole-product frame trace was available. Use the existing [platform matrix](platform-validation.md), with 1080p first on general desktop targets and actual native-panel pixels first on Apple Silicon Retina. Match source/binary/backend, settings, input tape, cold/warm state and output/internal dimensions; retain whole-callback tails, presented-frame evidence and audio underrun counts where relevant. Headless logic cannot replace these measurements.

Start experiments with **S01**, invocation-local **S02**, and transaction-local parse/summary work in **S12–S13**. Attribute **S03** during actual contact, then evaluate smaller hidden-feature candidates. Treat shader changes and retained-world/scale policy as device/lifecycle investigations. Prefer reducing duplicate work in existing C++/engine APIs before adding a subsystem; use native code where the remaining interpreted numerical loop is the demonstrated cost.
