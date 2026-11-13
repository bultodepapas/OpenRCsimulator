# Apple Silicon native evaluator: twelve investigations and plan changes

**Date:** 2026-11-12. **Owners:** DT/PT with SF/NK/FL and GDU/release owners. **Source reviewed:** `40751b55188226e69143881c7c58f16bc0a3cfff`, initially clean.

**Status:** twelve desk investigations completed using current targeted source inspection and primary documentation. No production code, native compilation, Mac session or performance experiment was run. Proposed implementation tests and hardware observations remain pending. These findings strengthen the [native implementation plan](../../../APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md), under the existing DT-MAC-04n1–n4 workstream; I01–I12 are research labels, not new implementation track IDs.

**Subsequent evidence:** the [isolated M1 follow-up](apple-silicon-m1-experiments-2026-11-12.md) records later native primitive experiments, including a NaN odd-tail counterexample. The status above describes this desk-research stage; it does not supersede the later observations or imply evaluator qualification.

## Method and outcome

Each investigation identifies a question, a gap in the preceding plan, source-backed findings, a concrete engineering consequence and a discriminating test. The [comparable-project review](apple-silicon-comparables-2026-11-12.md) remains the home for external speedup examples. This report does not infer an OpenRC Mac speedup from them or reopen completed Apple rendering work.

The existing graph was consulted for code discovery. It returned insufficient results for the current performance probe; current files and canonical tool guides were inspected directly. The runtime/binding pins and platform refusal were rechecked, not the entire simulator. Current API documentation must be reconciled with the locked source and selected Apple SDK; it does not authorize dependency upgrades.

| Investigation | Concrete reinforcement | Existing owner/step |
| --- | --- | --- |
| I01 | Observable FMA/control-state witnesses, beyond flag inspection | SF/NK, 04n1 |
| I02 | Threshold-neighbor corpus and OS/math identity requalification | SF/NK, 04n1/04n3 |
| I03 | Ordered NEON candidate and NaN/zero mutation control | SF/NK/PT, 04n2/04n4 |
| I04 | Actual small-length API/stride/alias crossover matrix | SF/NK/PT, 04n2/04n4 |
| I05 | Inclusive production timing and execution-count accounting | PT, baseline/04n4 |
| I06 | Run-level uncertainty, A/A controls and bounded experiment selection | PT, baseline/04n4 |
| I07 | Tool/device availability, thermal eligibility and energy units | DT/PT, baseline/04n4 |
| I08 | Packed-array ownership and qualified zero-copy assumptions | SF/NK, 04n2 |
| I09 | Binding round-trip, slice/dependency/deployment-floor gate | GDU/DT/NK, 04n1/04n2 |
| I10 | Early signed-host/translocation feasibility and finalization order | DT/release, baseline/04n4 |
| I11 | Explicit opt-in and one coordinated replay/identity migration | SF/FL/DT, 04n3 |
| I12 | Proven sanitizer activation, CI resource admission and change matrix | NK/GDU/DT, 04n2–04n4 |

<a id="i01"></a>
## I01 — Do compiler flags and the actual calling thread preserve arithmetic?

**Gap.** The preceding plan names strict flags, FPCR and disassembly but lacks a concrete witness that distinguishes fused from separate operations in the loaded candidate.

**Finding.** Upstream Clang documents interactions among fast math, contraction, rounding/exception assumptions and local FP pragmas; its strict model does not by itself select every denormal policy. Apple Clang must be observed rather than assumed identical to the upstream release. The generic AArch64 ABI also distinguishes FPCR controls from caller-clobbered FPSR status. [Clang controls](https://clang.llvm.org/docs/UsersManual.html#controlling-floating-point-behavior), [FP pragmas](https://clang.llvm.org/docs/LanguageExtensions.html#pragma-clang-fp), [Arm procedure-call standard](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst#simd-and-floating-point-registers).

**Plan change.** Retain per-translation-unit effective flags, relevant pragmas, inlining/LTO settings and final linked disassembly. Extend the existing math oracle with runtime bit-pattern inputs. Under round-to-nearest, `(1 + 2^-27) * (1 - 2^-27) - 1` produces `+0` using separate binary64 operations and `-2^-54` using FMA. Establish the pinned engine's result first. Observe FPCR controls before/after prepare, evaluation and refusals on the actual calling thread; do not require exception-status flags to remain unchanged.

**Proof/stop.** Use the opposite evaluation as a disposable detector control: explicit FMA if the engine yields the separate result, separate operations if it yields the fused result. Resolve an unexpected fused reference against the strict-FP design before continuing. A control-state mutant must be detected in an isolated process. Never alter the product process's FP environment to force agreement. Keep reference if required behavior cannot be characterized. This is a proposed detector, not an executed Mac result.

<a id="i02"></a>
## I02 — Are literals and mathematical calls stable across qualified software inputs?

**Gap.** “Same math symbols” and a source/engine hash do not describe compiler substitutions or macOS-provided math changes sufficiently.

**Finding.** [NK-4](NK-4/README.md#root-causes-of-non-identity-and-their-fixes) already found Windows `sin`/`cos` fusion, NaN priority and `sqrt` differences; [nk_math.hpp](../../../research/native-kernel/src/nk_math.hpp) preserves particular parser-rounded literals. These are portability warnings, not Mac findings. Clang recognizes mathematical builtins, while Apple's historical guides describe libSystem and versioned dynamic libraries. [Clang builtin controls](https://clang.llvm.org/docs/CommandGuide/clang.html), [Apple linking overview](https://developer.apple.com/library/archive/documentation/Porting/Conceptual/PortingUnix/compiling/compiling.html), [dynamic-library versioning](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/DynamicLibraries/100-Articles/CreatingDynamicLibraries.html).

**Plan change.** Extend the existing [oracle.gd](../../../research/native-kernel/oracle.gd), not a parallel harness: record coverage counts and adjacent representable values around used thresholds/literals, both signed zeros, subnormals, infinities, distinct quiet-NaN payloads, and relevant `pow`/trigonometric/`atan2` boundaries. Bind results to executable, native binary, compiler/flags, SDK and exact OS build; record loaded math-image identity where public tools expose it. Define the qualified runtime OS scope and its refusal/requalification policy before promotion; an untested software update is not automatically covered.

**Proof/stop.** One-ULP and NaN-payload mutants must fail exact comparison. A changed qualification tuple must be rejected by disposable receipt fixtures. Signaling-NaN coverage is not established by the existing NK-4 oracle: first inspect transport and document exclusions/unknowns rather than claiming all NaN encodings. Retain reference for unresolved required cases or stale qualification.

<a id="i03"></a>
## I03 — Which NEON operations preserve ordering and special-value behavior?

**Gap.** “Try SIMD” does not specify a safe first candidate or detect a mathematically familiar but semantically different helper.

**Finding.** The current `maxf(a,b)` shim is `a > b ? a : b`. For `(1, qNaN)` it returns the second operand; equal signed zeros also select the second operand. C `fmax` and Arm's distinct FMAX/FMAXNM intrinsics must not be substituted by name. [Current shim](../../../research/native-kernel/src/nk_math.hpp), [Arm intrinsics](https://arm-software.github.io/acle/neon_intrinsics/advsimd.html), [C11 draft §7.12.12.2](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf).

**Plan change.** Start with independent two-lane float64 operations, retaining within-lane operand order and scalar reductions. A concrete candidate is the final six-component multiplication by `fade` in [nk_wake.hpp](../../../research/native-kernel/src/nk_wake.hpp); preceding interval/piece accumulation order stays unchanged. This identifies a reviewable experiment, not a demonstrated win.

**Proof/stop.** Compare both orders of quiet-NaN/number, distinct payloads, signed zeros, infinities and subnormals; test actual lengths and odd tails. A deliberate `fmax` substitution must be detected by the corpus, without assuming every input differs. Check the final candidate for unwanted fusion, exact complete-stage outputs and measured inclusive cost. Reject the SIMD change if independence, identity or practical benefit is unproved.

<a id="i04"></a>
## I04 — Does a public Accelerate call win at the actual short lengths?

**Gap.** The previous large-array examples do not establish a profitable crossover or legal alias/stride behavior for short aircraft arrays.

**Finding.** Apple exposes double elementwise operations and vector transcendental functions. Their existence does not establish Godot byte identity. Apple's separate `simd` double precision discussion is not a blanket accuracy specification for vDSP/vForce. [vDSP_vaddD](https://developer.apple.com/documentation/accelerate/vdsp_vaddd), [vForce](https://developer.apple.com/documentation/accelerate/vforce-library), [simd precision](https://developer.apple.com/documentation/accelerate/double-precision-floating-point-vectors).

**Plan change.** Select one measured operation, such as six-component addition/multiplication. Build a candidate matrix of the real lengths, neighboring lengths, legal aliases, strides and odd tails. Use existing storage only where the selected API permits it. Record selected symbols, SDK declarations, deployment availability and linking behavior; do not depend on private AMX instructions or a chip-name guess.

**Proof/stop.** Exact output plus a one-ULP detector control precedes timing. Paired full calls include packing, library invocation and scratch; complete-stage timing follows. No universal crossover is asserted. Keep scalar if the API is unavailable, required aliasing is unsupported, exactness fails or total cost does not improve. A modern API must not silently raise the delivery floor or weaken fallback.

<a id="i05"></a>
## I05 — What cost does the proposed acceleration actually remove?

**Gap.** Stage-only timing can omit context preparation, wrappers and changed observer work; four stage calls cannot describe all contact/event ticks.

**Finding.** The existing [production probe](../../../research/performance/session_probe.gd) times session plus simulation callbacks; identity/counter queries and hashing are outside the per-tick stopwatch but within/around the loop. Its native check is a minimum call-coverage check, not a measurement of all physical substeps. The [native tooling guide](../../../research/native-kernel/README.md#c-development-tools-nk-3) explicitly limits research-adapter timing. Google Benchmark distinguishes elapsed latency from CPU consumption; Apple's command-buffer timing describes GPU execution separately from submission/completion. [Benchmark timing](https://google.github.io/benchmark/user_guide.html#cpu-timers), [Metal completion/timing](https://developer.apple.com/documentation/metal/mtlcommandbuffer/addcompletedhandler(_:)).

**Plan change.** Retain separate setup/first-use, tick-context, inclusive stage, complete callback and live-frame measurements. In diagnostic runs record actual stage/context counts and contact/event regime; preserve the same accepted tape. Only time intervals that are serial and nonoverlapping may be added. Preserve the production callback measurement as the adoption result rather than subtracting estimated wrapper costs.

**Proof/stop.** A disposable omitted-context/coverage mutation and an uncompleted asynchronous operation must fail the relevant verifier. No GPU flight implementation is required: the latter is a contract for any separately justified GPU consumer. Stage improvements with no material complete-workload benefit do not justify promotion. Profiling counters remain bounded and off the production hot path unless their cost is qualified.

<a id="i06"></a>
## I06 — Can noise, autocorrelation or candidate selection create a false win?

**Gap.** Five alternating pairs, percentiles and an uncertainty caveat do not yet define repeat units, A/A controls, exclusions or a bounded stopping rule.

**Finding.** NIST explains why correlated observations are not independent snapshots. A long evolving tick tape therefore cannot automatically provide thousands of independent replicates. Google Benchmark documents warmup, repetitions and randomized interleaving as separate controls, not a guarantee of significance. [NIST dependence](https://www.itl.nist.gov/div898/handbook/eda/section2/eda251.htm), [benchmark repetition/interleaving](https://google.github.io/benchmark/user_guide.html), [existing nearest-rank reducer](../../../research/performance/session_baseline.py).

**Plan change.** Before candidates, freeze the workload, warmup, per-case primary metric, pair/block ordering, eligibility/exclusions, practical threshold and maximum additional pairs. Collect same-binary A/A and observer-on/off controls. Preserve within-tape time order; use paired whole-run/block summaries for uncertainty, not independent resampling of adjacent ticks. Inspect drift/autocorrelation and retain all runs. Choose a confidence method appropriate to the run count before looking at candidate results; insufficient evidence remains inconclusive. Screen optimizations on one set, then confirm finalists on fresh tapes/runs.

**Proof/stop.** Existing reducer fixtures should distinguish an injected tail from a batch mean, reject truncation and expose A/A drift; deliberate controls use disposable data. Accept only demonstrated practical benefit beyond the declared noise controls and other gates. A sufficiently precise regression or result ruling out the practical threshold rejects the candidate. If uncertainty still admits conflicting decisions at the sample cap, report inconclusive and improve controls or defer; do not rerun until a favorable number appears.

<a id="i07"></a>
## I07 — Which tools, thermal observations and energy units are valid on M1?

**Gap.** A generic “use Instruments and power tools” instruction can require unavailable hardware features or mislabel relative/system metrics as application joules.

**Finding.** Apple's Processor Trace recording requires M4-or-later Mac hardware and supported OS/Instruments; M1 needs sampling-based tools. Current Power Profiler documentation specifies iPhone/iPad availability, so its existence is not a Mac power channel. Foundation `serious` thermal state indicates performance impact. The existing [host companion](../../../tools/godot/README.md#optional-macos-host-state-companion-dt-mac-02e) also warns that unavailable awareness may look nominal and absent memory-pressure events do not prove no pressure. [Processor Trace availability](https://developer.apple.com/documentation/xcode/analyzing-cpu-usage-with-processor-trace), [Power Profiler scope](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler), [thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum/serious).

**Plan change.** Preflight an actual tool/channel matrix: M1 Time Profiler/`sample`, supported counters/Metal tools, optional newer-device trace, and measured/estimated/relative/unavailable energy. Record power mode, supply, thermal observation coverage, clock gaps and brightness for rendered comparisons. Where watts are available, report `sum(P_i * delta_t_i) / completed_ticks` with domain and coverage; whole-system estimates are not app-only energy. Preserve unknowns. Compare sustained early/late windows and retain candidate-induced heating as a result, not an exclusion.

**Proof/stop.** Missing coverage, unsupported tools or an injected clock gap must invalidate the affected claim without inventing zero energy/pressure. Never reduce physics rate for thermal acceptance. Unsupported energy remains unclaimed; missing mandatory pacing/timing evidence keeps promotion open.

<a id="i08"></a>
## I08 — Does unified memory make current engine arrays safe zero-copy buffers?

**Gap.** The plan prohibits retained pointers but can make the ownership and alignment assumptions testable before any pooling or GPU work.

**Finding.** Godot packed arrays are passed by reference and require `duplicate()` for independent script ownership. A synchronous array view is not evidence of page-aligned, stable allocation. Apple's no-copy Metal buffer API requires a page-aligned allocation/length in one VM region, plus explicit lifetime management. Shared GPU storage still needs ownership synchronization. [Godot packed arrays](https://docs.godotengine.org/en/4.7/classes/class_packedfloat64array.html), [Metal no-copy requirements](https://developer.apple.com/documentation/metal/mtldevice/makebuffer(bytesnocopy:length:options:deallocator:)), [shared storage](https://developer.apple.com/documentation/metal/mtlstoragemode/shared).

**Plan change.** Keep the CPU port's input views scoped to the call and outputs detached. Do not wrap arbitrary Godot pointers in Metal or retain them for a future callback. If a separate GPU batch becomes justified, use explicitly owned eligible storage, checked size/alignment and completion-owned lifetime. Measure incremental prepared/scratch/result memory, lifecycle plateaus and cleanup; report process and Metal allocation metrics without adding overlapping shared-memory totals.

**Proof/stop.** Retain a result across subsequent calls, mutate a caller copy, replace/resize temporary inputs, interleave two evaluator instances and destroy/reset owners in disposable tests. Detect output aliasing, stale reads and shared scratch. Reference/refusal paths must avoid candidate-only scratch/GPU allocation. Keep simple owned copies when a valid zero-copy lifetime or practical memory benefit cannot be established.

<a id="i09"></a>
## I09 — Are binding precision, Mach-O slices and the deployment floor compatible?

**Gap.** “Build ARM64” does not prove float64 transport or matching engine ABI; simulation doubles and Godot `real_t` are different decisions.

**Finding.** The current [lock](../../../research/native-kernel/toolchain-lock.json) still pins Godot 4.8-beta2, godot-cpp `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5` and API 4.7. Godot documents GDScript float64 but precision-dependent GDExtension compatibility. The pinned binding builder exposes `precision`, `custom_api_file` and architecture/deployment settings. [GDScript types](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_basics.html), [precision compatibility](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html), [pinned binding options](https://raw.githubusercontent.com/godotengine/godot-cpp/507ed9d840c01a3c5b2a39af8bb4000bfac30bf5/tools/godotcpp.py), [pinned macOS builder](https://raw.githubusercontent.com/godotengine/godot-cpp/507ed9d840c01a3c5b2a39af8bb4000bfac30bf5/tools/macos.py).

**Plan change.** Record API JSON hash/origin and selected `api_version`/override, engine/binding precision, compiler/SDK, deployment floor and process architecture. Through the actual late-loaded extension round-trip scalar and packed doubles, including signed zero and values distinguishable only beyond float32 precision. Inspect each Mach-O slice, load commands and dependencies; derive the delivered floor from all components, not SDK age alone. An ARM64 native artifact does not qualify Rosetta.

**Proof/stop.** Wrong precision/API metadata, wrong slice, stale descriptor, unexpected dependency and too-high deployment floor must be refused in disposable fixtures. Execute on the claimed floor OS before claiming compatibility. A host/editor loading problem must be resolved before fleet work; no automatic custom-engine substitution.

<a id="i10"></a>
## I10 — Do host trust, notarization and translocation preserve final identity?

**Gap.** The earlier plan leaves notarization/stapling order and receipt accessibility under quarantine as late package details, although either can block the design.

**Finding.** Hardened Runtime library validation normally requires Apple or same-Team-ID libraries unless a relevant exception applies; inspect the actual Godot host rather than assuming its policy. A notarization ZIP cannot itself be stapled: staple its app/items, then recreate the distribution archive. Apple also documents App Translocation, which can hide resources next to the original app. The existing [Mac receipt](../../../tools/release/macos_reference_receipt.py) and [runtime reader](../../../app/app_state/native_package.gd) use a sibling receipt. [Library validation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation), [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [Apple translocation notes](https://developer.apple.com/forums/thread/724969).

**Plan change.** Make signed-host loading and receipt-location feasibility an early isolated milestone. For the notarized ZIP route: finish slices/install names, sign nested code/app, submit an archive, inspect acceptance/logs, staple/validate the app, generate its final external receipt, then seal the distribution ZIP. Retain distinct submitted/final archive hashes. Signing/combining slices may alter full binary hashes: trace the transformation and test the actual final loaded dylib, rather than replacing an old receipt hash.

**Proof/stop.** Test real downloaded/quarantined Finder launch, offline launch, normal installation, moving the `.app` alone and tampered/missing siblings. Do not strip quarantine, bypass validation or recover the original translocation path to pass. If the supported launch cannot reach required identity, decide an evidenced installation/identity design and recovery behavior before fleet work. A new trust schema/custom product engine triggers scope and effort reassessment, not assumed completion.

<a id="i11"></a>
## I11 — Can admission and identity migration remain explicit and complete?

**Gap.** A platform-loader change can unintentionally promote Mac native execution, while identity changes affect more consumers than the loader.

**Finding.** Current [Main](../../../app/main.gd) and [helicopter launch](../../../app/helicopter_main.gd) request native by default; [native_stage.gd](../../../app/sim/native_stage.gd) still blocks Mac. [flight_log.gd](../../../app/sim/flight_log.gd), [flight_log_cli.gd](../../../app/tools/flight_log_cli.gd), the [Python log tool](../../../tools/flight_log/flight_log.py), [native qualification](../../../app/tools/native_qualification.gd) and [session probe](../../../research/performance/session_probe.gd) recognize fixed identity kinds. Candidate replay currently chooses reference, making its supported comparison direction asymmetric. These findings were verified in current source; they are not API assumptions.

**Plan change.** Use one migration inventory spanning producers, loaders, checkpoint/log readers, Python/player CLI, qualification and timing. Preserve the reference-only Mac kind and historical replay. Add an explicit experimental Mac opt-in and enforced fixed-wing qualified surface before broadening any loader guard. Support that explicit opt-in in the same final packaged executable used for prepromotion qualification, while the ordinary default request remains insufficient. Keep same-backend exact replay and marked cross-backend candidate comparison as separate claims.

**Proof/stop.** The route matrix covers ordinary Home/direct flight, explicit reference/native with and without opt-in, unsupported families/helicopter, old/new/wrong identity kinds, stale/preloaded artifacts and backend changes during recording. Require actual native-success markers only in eligible rows. Do not promise reference-to-native candidate replay without a separately tested backend-selection change; the existing reverse direction can be used. Missing consumer migration or a falsely successful fallback blocks promotion.

<a id="i12"></a>
## I12 — Are sanitizer, CI and maintenance claims supported by the actual path?

**Gap.** A green sanitizer process can have no active detector, and an ARM64 VM cannot establish floor-hardware sustained performance.

**Finding.** Existing [devtools](../../../research/native-kernel/devtools.py) use disposable detector controls. LLVM describes ASan compiler instrumentation and a runtime in the final executable; a sanitized dylib alone does not prove engine-wide coverage. Hosted runner specifications describe virtual resources, not a full M1 Air/display campaign. [LLVM ASan](https://clang.llvm.org/docs/AddressSanitizer.html), [hosted runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [existing CI](../../../.github/workflows/ci.yml).

**Plan change.** Prove a known fault through the same late-loading seam with the expected marker, diagnostic, completed report and detector-driven child termination; ordinary teardown is required for the clean candidate, not the deliberately halted fault process. A diagnostic-only instrumented host, if needed, has its own identity and does not replace the exact production engine oracle. Keep sanitizer runtimes out of release dependencies. Preflight actual VM architecture/image, disk, RAM and tools before heavy import/build; make correctness/native-marker jobs required through the existing dependency chain. Insufficient resources require an explicit suitable runner or bounded qualified scope, not a skipped green gate.

**Proof/stop.** Fail inactive detectors, unexpected crashes/timeouts, absent native markers, stale receipts and wrong architectures. Required correctness CI and real-host performance remain separate evidence. Changes to math/compiler/OS, engine/API/precision, model admission/data or final signing/package inputs invalidate the affected gates. If this route requires a custom product engine or redesigned trust architecture, stop and re-estimate.

## Planning consequences and remaining evidence

The implementation plan now adds concrete proof requirements at each phase, an admission/replay route matrix, a qualification tuple, a final-artifact sequence and a change-to-requalification matrix. Early packaging/host feasibility comes before expensive fleet qualification. The conditional 29–52 person-day estimate remains for the scoped evaluator route; unresolved host-signing/translocation/identity redesign is excluded and must be re-estimated.

No investigation establishes same-host ARM64 arithmetic parity, a native evaluator gain, actual energy savings, a successful translocated package or physical RC validation. Those observations require the existing owned workflows and real target devices. This separation is deliberate: the twelve completed investigations improve what engineers must build and prove without relabelling planned experiments as completed evidence.
