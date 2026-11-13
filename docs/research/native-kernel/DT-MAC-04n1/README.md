# DT-MAC-04n1: ARM64 evaluator implementation evidence

**Date:** 2026-11-13 UTC. **Status:** experimental implementation and bounded M1 assessment completed; automatic admission and production delivery deferred.
**Starting source:** `e2fbce921c01b061d5c93102c35adabd45b39ad1`, initially clean.
**Owners:** SF/NK with DT/PT/FL. The [implementation plan](../../../../APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md) owns the remaining gates.

## Host and implementation

The target is ANGELA_AIR, MacBookAir10,1, M1/8 GiB, macOS 27.0.1 build `26A434`, on AC power. The unchanged official ARM64 Godot `4.8.beta2.official.cafc17a19` has SHA-256 `2051c48febe532a5b156ffd8dd0c9381f74e40fde9177faff07a713851baba80`. Its existing Hardened Runtime entitlement disables library validation; no host signature, entitlement or system-security change was made. See the [M1 guide](../../../tools/macos-m1.md).

The scalar Apple Clang ARM64 shim uses ordered `fadd`, `fsub`, `fmul` and `fdiv`, with a register barrier for the `pow` exponent. The x86 branch remains separate; no SIMD, float32 simulation state or kernel architecture change was introduced. The experimental builder uses Apple Clang 21.0.0 (`clang-2100.3.34.2`), SDK 27.0 and the pinned godot-cpp/API/SCons. Its 11.0 deployment target is not evidence of older-OS compatibility. Compilation, Mach-O, dependencies, dSYM UUID and the selected signature are checked before the dylib is hashed. Developer ID signing support is implemented but has no real-certificate positive test; source10 uses ad-hoc signing.

Mac source and package admission require a per-launch experimental opt-in, and ordinary launches retain reference. This is a fixed-wing testing route, not an enforced qualified aircraft/domain allowlist or a full-fleet claim. Helicopter admission remains excluded. Source and packaging details are in the [native evaluator guide](../../../../research/native-kernel/README.md#experimental-macos-arm64).

## Source10 target evidence

The source10 candidate used the M1 checkout at the starting commit plus the recorded source overlay. Its ABI 2 ARM64 dylib has SHA-256 `c1d8730c3f8e157ac0f24acd79c94b16f211e0c5e07357b79fb5e499db2da7d8`; native-source SHA-256 is `288918db4a3639c4494ad9a48f6326adaf31b371d4f7f6158f3f9b6a722bb8f0`, lock SHA-256 is `9a3eb33b5aae340e9403c6f7bd5a8bf4a39b4e5a5477a9c91bea6f8a593339db`, and builder SHA-256 is `8666d3b3e1c568c60a6c8ef84e3ef183d4cd1fbe280512c72c8a45b8510edbb2`. Its engine, toolchain and mirrored inputs are bound by the build receipt. This identifies the tested candidate, not any earlier or later exported bundle.

| Check | Observed result |
| --- | --- |
| Exact oracles | All 17 applicable positive base, stage, trajectory, family and weather reports passed: **1,323,114 / 1,323,114 comparisons identical**. These are comparisons, not a count of distinct states or flights. |
| Mutation control | The separately built stage mutant produced the expected failure: 28,350 mismatches and 100,314 identical out of 128,664 comparisons; its run was valid. |
| FPCR control | The disposable control flipped FZ, the real loader/oracle detected the changed calling-thread control state, and the control verified restoration. |
| Source admission and replay | Mac stage policy: 57 checks; launch policy: 78 checks; flight-log suite: 4,412 checks, all passing. Installed source stage, lifecycle and replay tests passed their native markers, with 97, 343 and 190 checks respectively. |
| Initial source10 portable checks | 299 distinct Linux tests passed across native (175), performance (47), receipt (23), flight-log (33) and research-preparation (21) suites. The later fleet-verifier correction has its separate 62-test result below. These are not native CI or hardware evidence. |

The oracle roster excludes helicopter admission. Source lifecycle and replay checks do not establish final-package replay, full fleet coverage, physical validation or promotion. A changed builder, runtime, library, harness or other bound input requires the affected evidence to be refreshed.

A later review found that an empty `--candidate=` could select exact replay internally while reporting candidate mode. The CLI now refuses that value before log inspection. The real subprocess regression, including a nonempty-path control, passed on a separate UI10 copy; `evidence/source10-cli-fix-overlay.json` identifies the two changed files. Frozen source10/fleet and package11 reports do not execute this later correction. The correction changes prepared-app/package identity, while leaving the native dylib and mirrored-law inputs unchanged.

### Source10 CPU screen

The frozen `evidence/performance10-source-screen-contract.json` specified three trim cases, five alternating reference/native pairs per case, 2,400 warmup and 14,400 sampled ticks. These are 10 and 60 seconds of simulated time. All owned correctness, UI, compiler and transfer work ended before the serial primary campaign; no timing data was excluded or sample cap extended. The host remained on AC, with low-power mode off and Foundation reporting nominal at the campaign endpoints. Endpoint snapshots do not establish continuous thermal awareness.

| Detached source case | Complete pairs | Median run-mean reference µs | Median run-mean native µs | Median paired ratio | Paired native reduction |
| --- | --- | --- | --- | --- | --- |
| Jensen Ugly Stik, legacy prescribed RPM | 5/5 | 528.701 | 287.157 | 1.845× | 45.54–46.03% |
| Stik Electric 6S, ideal supply | 5/5 | 701.580 | 310.396 | 2.259× | 55.59–55.93% |
| Extra 300S, finite glow | 0/5 | Unqualified | Unqualified | Unqualified | Unqualified |

Every accepted pair had matching typed physical fingerprints and actual native context/stage coverage. Jensen run p95 callback costs were 555–560 µs reference and 315–316 µs native; p99 were 559–565 and 318–320 µs. Electric p95 were 729–734 and 340–342 µs; p99 were 734–738 and 344–345 µs. These run distributions are not pooled aircraft statistics or a product pacing guarantee.

The Extra fixture crashed at tick 7,524 in every role and repeat, after 2,400 warmup and 5,123 completed sample ticks. Its retained prefix fingerprints matched, but incomplete runs provide no accepted performance ratio. The three-case campaign therefore correctly reports failure with 25 issues, all from that case; the two completed cases are descriptive source results, not a complete campaign pass.

Three Jensen A/A pairs per backend completed. Absolute mean-ratio deviations were 0.277–0.542% for reference and 0.107–0.544% for native, much smaller than the observed Jensen gap. Three observer-on/off pairs per backend also completed: wall-time differences ranged from −5.588 to −0.316 µs/tick for reference and −0.215 to 2.335 for native. Negative differences expose unresolved measurement variation; no overhead or noise was subtracted. Electric has no separate A/A control and remains descriptive. Five pairs do not establish population confidence.

The measured callback includes session input conditioning, the shared simulation transaction, collision and accepted-step callbacks. The detached probe excludes rendering, audio, real devices and the real-time scheduler. It supports a source CPU opportunity, not FPS, energy, long-soak, 1080p or signed-release adoption. Raw runs, final source guards and controls are under `source/tmp/macos-port/performance10/`; `evidence/performance10-analysis.json` is the descriptive reducer output.

### Separate resource diagnostic

After primary timing ended, direct Godot launches completed the same Jensen tape with the existing process sampler and frozen host companion. Sampled peak RSS was 539.7 MiB for reference (13 samples) and 543.7 MiB for native (9). These include startup and retained probe arrays, with different process durations; they establish neither a memory reduction nor a leak. Host streams had complete collector coverage, 14/10 snapshots and no local drops; absent pressure callbacks leave the initial pressure value unknown. Source/install identities remained unchanged. See `source/tmp/macos-port/resource10/` and its `summary.json`. Energy and sustained behavior remain unqualified.

### Earlier source08 timing smoke

One source08 observer-on Jensen Ugly Stik trim pair completed 30 warmup and 120 sampled ticks per backend with matching fingerprints and native context/stage coverage. Mean measured callback cost was 520.275 µs for reference and 282.4 µs for native, a descriptive 1.8423× reference/native ratio for this one pair. It was a headless source-editor smoke, with neither A/A nor observer controls. It does not establish repeatable benefit, a tail-budget result, FPS, sustained behavior, source10 performance or release-package performance. The separate source10 screen above does not retroactively qualify this smoke.

### Ordered-math witness

A standalone M1 test of the actual math header passed its 13-value overload and FMA witness: separately rounded arithmetic produced `0000000000000000`, while explicit `fma` produced `bc90000000000000`. Optimized disassembly retained a call to `_pow` for the literal exponent. The task's `ordered-math10/receipt.json` records the witness. The same source/header corpus also passed a standalone Linux x86_64/G++ 13.3.0 witness. These are header results, not Godot-parity or native CI proofs; the source10 oracles provide separate same-host comparisons.

## Sanitizer controls

For source08, disposable ASan-only and UBSan-only positive-control libraries compiled and linked with their corresponding Godot sanitizer definitions. On this specific M1/OS and unchanged official Godot host, the sanitizer runtimes were refused with `Sanitizer load violates platform policy`: ASan failed during runtime insertion and UBSan failed when its extension dependency was loaded. Neither intended detector was demonstrated, so neither sanitizer is a pass and the sanitizer gate remains open. This observation does not establish that sanitizers are unavailable on every Mac.

The attempted instrumentation covered `nk_kernel.cpp` and code compiled inline into that translation unit. Godot and the prebuilt godot-cpp archive were uninstrumented. A separately identified compatible diagnostic host would still need its own positive control and cannot substitute for exact product-engine oracles. No leak or general memory-safety qualification is claimed.

## Package and host preflight

An earlier package export correctly reported a MoonRunner authoring-proof SHA-256 mismatch against the linked historical authoring assets. After restoring the current authoring inputs from the real Git checkout, the package09 development export completed with zero errors and one `export-manual` warning because `OPENRC_BUILD_*` was unset. Outer app signing then failed because the `.gdextension` descriptor was placed in `Contents/Frameworks`; the descriptor was subsequently moved to `Contents/Resources`.

Package10 used the source09 dylib (`ccad64f8ea89360241be37879744f1a553fde0f311f74b26c310991253d26937`). Its ordinary hardened host had empty entitlements and passed strict signature verification, but actual native loading failed because the process and ad-hoc dylib had different Team IDs. No project Developer ID signing identity was available on the host.

Package11 was a disposable clone of that source09 package, signed with an explicit `disable-library-validation` entitlement. This deliberately changes that development app's security policy and conflicts with the plan's normal library-validation requirement; it is not distributable, a release package, or evidence for source10. Its stage test passed 97 checks in 44.9 seconds. Lifecycle first timed out at 600 seconds; a fresh run with a 1,800-second limit passed 343 checks in 1,004.420291 seconds while other correctness work was active. A profile was not symbolicated, so no cause or performance attribution is claimed. Its replay test passed 190 checks.

Package11's actual CLI replayed 65 native rows and 65 reference rows exactly, with `mode=exact`, complete/ok reports and `solver_changed=false`. Native-to-reference candidate replay completed with `solver_changed=true`. Replay without the experimental opt-in refused the native recording. Disposable-clone controls refused a missing native receipt, its corrupted reference link and a changed descriptor; descriptor refusal preceded native class preload. Reference exact replay still worked when the native receipt was absent. See `evidence/package11-cli-summary.json` and `evidence/package11-receipt-controls.json`. None closes the normal hardened-package gate.

The separate signing audit correctly refused a real ad-hoc app as Developer ID. On the M1, actual `codesign --entitlements - --xml` output for package10's empty 184-byte plist was accepted, and package11's 250-byte plist with the validation exception was rejected. The tool and tests do not establish a real Developer ID positive, notarization or quarantine behavior.

The preflight recorded a native ARM64 Python process and a system-reported 1440×900 display. No Rosetta installation receipt was found; no x86 execution or installation was attempted. Drawable and render pixels were not verified. A single Foundation snapshot reported nominal thermal state and low-power mode off; nominal does not establish sensor availability or a sustained thermal result. Instruments was not found. The inventory does not qualify 1080p, rendering, energy or package behavior.

The official general headless debug smoke failed first at `controller_capture_scroll`'s scroll-position assertion, then cascaded through Home recovery. It remains a failure. A separate directed Home/Fly/restart/Home check passed, observed the actual reference backend and exited zero without reported leaked objects. This is functional software evidence with private research preferences, not a rendered or full-smoke pass. Initial directed attempts are retained, including an unknown exit status from separate CLI processes and an incorrect Home assumption for the existing direct-flight CLI route.

The explicit CLI flight and restart also observed the native backend and exited zero. Paired verbose direct-flight exits reported the same 19 audio stream/playback objects in reference and native. This identifies a shared shutdown observation; it does not establish leak freedom or explain the audio retirement. Evidence: `evidence/source10-ui-direct2-summary.json`, `evidence/source10-ui-native-cli-summary.json` and `evidence/source10-active-exit-summary.json`.

## Current-source fixed-wing fleet

All eleven shards finished against the current declaration: 1,428 fixed-wing rows and 14 excluded rotorcraft rows. The corrected aggregate independently verified **1,386 healthy flights** with identical typed initial/warmup/sample fingerprints, 600 warmup and 2,400 sample ticks per backend, stable backend identities and native context/stage coverage on every native tick. **42 rows remain open** and the aggregate verdict is **fail**, with no invalid or missing shard.

| Open rows | Count | Evidence limit |
| --- | --- | --- |
| Raw matching reference refusals / runtime-domain refusals | 20 | 16 startup and four runtime observations require their separate Mac boundary qualification; they are not flights. |
| Linux-pinned FS64V, P-51, Avanti and Turbo boundaries | 10 | Two typed-trial pins and eight startup-proof pins were not satisfied on Mac. Preserve the historical fixtures and current failed reports. |
| Electric 6S crosswind/spatial-crosswind runway starts, pack/ideal and hull on/off | 8 | The native-first harness could not reset. A separate unchanged reference factory refused all eight with no native class preload; this does not turn the original failures into qualified pairs. |
| MoonRunner X99 | 4 | Historical X8 observations remain inapplicable; these rows were explicitly unqualified. |

The first aggregate rejected every shard because its verifier required base-only FPCR fields in fleet reports. The correction binds the exact base-oracle report cited by the installed receipt, reusing the strict build/report/log/source verifier before and after aggregation. `--qualification-root` identifies build10 independently of the fleet `--tool-root`. FPCR was observed in that separate base process, **not in each fleet process**. No fields were injected into old reports, no hashes or fixtures were rewritten, and no flight was repeated for the correction. The original aggregate and the corrected one are both retained at `source/tmp/macos-port/fleet10-campaign/` and `fleet10-campaign-fixed/`. The final full verifier suite passed 62 portable tests on both Windows and Linux. The final campaign tool SHA-256 is `79c04e2c870b573bb4e338f261b73aaa53f2e02a1e17b95443e7dab1b24d7a4c`; this Python-only correction does not change the oracle harness, runtime or dylib.

These finite stock tapes support their named software-equivalence cases, not arbitrary input histories, physical realism or an enforced runtime domain. The opt-in still admits unqualified fixed-wing configurations; full-fleet or automatic Mac promotion is deferred.

## Earlier feasibility and retained evidence

Build 03 compiled and linked 63 translation units and passed the initial command, Mach-O, dSYM and ad-hoc-signature checks. The official host loaded the extension and preserved nine special PackedFloat64 fixtures. The first component smoke found 17 NaN-payload differences, all in `lerpf`; the observed Apple ordering `from + (to - from) * weight` removed them. Build 04 then produced 593,941 identical component comparisons and 128,664 identical stage comparisons. Source08 and source09 also completed the then-applicable oracle rosters; no earlier result qualifies source10 or its packages.

The initial checker incorrectly rejected an earlier `-fno-exceptions` despite the later effective `-fexceptions`; it now checks the final option. The Apple `nm -u` parser was also corrected for output without a `U` column. These corrections and their original failed runs are retained.

Task root: `/Users/gius/OpenRC-m1-work/macos-native-port-20261113T004500Z/`. The isolated research preparations use native `clonefile(2)` with content checks; their linked historical **authoring** assets were separate from current runtime resources. The initial 5.4 GiB free limited the campaign; user-authorized removal of regenerable caches recovered about 2.33 GB without removing installed applications, documents, credentials or frozen campaigns.

Key evidence under the task root:

- `evidence/build10-family-summary.json` and `source/tmp/macos-port/build-10/`: source10 oracle reports, checked logs, candidate/mutant receipts, binaries and symbols.
- `evidence/build09-family-summary.json` and `source/tmp/macos-port/build-09/`: the previous candidate's oracle reports, checked logs, build receipts and artifacts.
- `evidence/build08-family-summary.json` and `source/tmp/macos-port/build-08/`: the earlier source08 reports, checked logs and artifacts.
- `source/tmp/macos-port/fpcr-control-08/control-receipt.json`, `source/tmp/macos-port/diagnostic08-asan-02/` and `source/tmp/macos-port/diagnostic08-ubsan-02/`: detector control, sanitizer commands, logs and failure summaries.
- `evidence/source08-{policy,launch,flight-log,stage,lifecycle,replay}-driver.log` and their checked-run directories; `source/tmp/macos-port/source08-smoke/session_baseline.json` and its raw runs.
- `evidence/package08-export-driver.log`, `evidence/current-authoring09.json`, `evidence/package09-export-u2ahxo9o/report.json`, `evidence/package09-sign-driver.log` and `evidence/preflight09/`: the export, signing and host observations above.
- `evidence/signing-audit-real-entitlements10.json`: actual signing-audit rejection and entitlement-output checks; package10/11 logs retain the separate loader and diagnostic outcomes.
- `evidence/build-01-driver.log`, `evidence/build-02-driver.log`, `evidence/effective-clang-driver.log`, `evidence/load-proof-01.json` and `source/tmp/macos-port/build-04/`: initial failures and feasibility evidence.

Local ignored snapshots are `tmp/macos-port/candidate08-evidence.tar.gz`, SHA-256 `77acd1afd2a8ce816af8b697d8ad1e302cc326d04e6f48b224baa09496507e9d`; `tmp/macos-port/candidate09-evidence.tar.gz`, SHA-256 `244015afd46a9d02398f35bd12a69619e3e75edc27fdd5637ead9b1e58e2c930`; and `tmp/macos-port/candidate09-bound-source.tar.gz`, SHA-256 `342962cd415a5ac4873f280c1ecf51262e3f2359582b709084158c0f28b2974f`.

The frozen source10 snapshot is `tmp/macos-port/candidate10-bound-source.tar.gz`, SHA-256 `26d4e3c3fc22a8306d86c91a61d12ac6dda02541ad868e9b35346ec791c47fa7`; its later CLI correction is retained separately. Linux's final A/A fixtures and standalone x86 witness are in `tmp/macos-port/linux-policy-inputs/supplement10.tar.gz`, SHA-256 `1bb287a8075e19cfe88cab08f0aa87936b0e0bcfe28d5e3c041103f34eae15d0`.

`tmp/macos-port/candidate10-evidence.tar.gz`, SHA-256 `5f97ddd292a0dc321ee42139a163d7f4425086489b3f3c33e97c05eba05e315b`, retains source10 build artifacts, proof/logs, original and corrected fleet ledgers, raw CPU/controls, resource series and forensic package host/sidecar deltas. It is not a runnable or distributable package. The excluded package PCK is retained in the original `tmp/macos-port/package10-export.zip`, SHA-256 `7199e6e27b7d0715e68d8c256a612e373b4cb775e81868ae840c89360721686c`; that ZIP predates native sidecar staging and is not the final native release. Final portable verifier logs are `tmp/macos-port/fleet-fixed-windows-full.log` and `tmp/macos-port/linux-policy-inputs/fleet-fixed-full.log`.

The Windows enrolled focused GDScript job `T-56c300ce719148a7b9c45428dfde56ce` failed input materialization before Godot launched. This is infrastructure failure, not a test pass or a demonstrated runtime regression. No unowned worker was restarted or enrollment bypassed. Portable fixtures and the standalone x86 witness do not replace required Linux/Windows runtime CI.

Final teardown observed no Godot/OpenRC process and stopped only the task-owned temporary `caffeinate` after matching its PID, creation time and arguments. `tmp/macos-port/task-teardown10.json` retains the receipt. No permanent sleep setting was changed.

## Decision and next gates

The owner confirmed on 2026-11-13 that public distribution is deferred.

Retain the implemented scalar ARM64 route as an explicit fixed-wing experiment. The M1 evidence demonstrates exactness on the exercised corpus and a material detached CPU reduction in two completed cases. It does not justify automatic admission: the fleet has 42 open rows, the third long case failed, sanitizer positive controls were not established, and the normal hardened package could not load the ad-hoc dylib. No production release or full implementation-plan completion is claimed.

DT/PT owns delivery, real 1080p/display and sustained/energy measurements; SF/NK owns the admitted domain, numerical diagnostics and native CI; FL owns backend-pinned replay. Keep reference and the retained source/dylib artifacts as rollback paths. Requalify affected evidence after a changed engine, compiler/SDK/OS, signed library, runtime, data, harness or final package. The first production follow-up needs an available matching Developer ID Application certificate, separately qualified signed bytes and normal library validation; the diagnostic entitlement exception is not an alternative delivery path.

## Open gates

- **Final candidate and package:** verify the normally hardened final signed package's loading, identities, negative controls and replay. Development ad-hoc signing is not Developer ID or notarization; a matching Developer ID host and dylib require separately signed and requalified bytes.
- **Fleet and runtime scope:** qualify the 42 open rows, including MoonRunner and Mac-specific boundaries, or enforce an explicitly narrower qualified domain before promotion.
- **Diagnostics and CI:** demonstrate supported sanitizer positive controls; run required cross-platform checks and a Mac CI route with actual native-success markers. Current native-kernel CI jobs target Ubuntu and Windows; no native Mac job is configured.
- **Performance and delivery:** qualify complete representative cases, final live 1080p and sustained behavior, and supported signing, quarantine, Finder/offline and Intel/Rosetta checks. The completed source screen and its controls do not close these gates. Leave unavailable energy and display channels open. No automatic Mac admission or product-performance claim follows from source10.
