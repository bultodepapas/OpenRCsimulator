# Gate P — bounded native slipstream experiment

2026-10-07 · **Status: Linux experiment verified; Gate P remains unmet. Windows and macOS recipes are unrun.** This supports an isolated performance experiment; it does not add a production dependency.

## Result and decision

**The bounded port improves powered P-51 cost but does not meet Gate P. Keep it experimental; do not add a production native dependency yet.** On the owner-confirmed target (Linux KVM, Intel i5-10500, 12 logical CPUs), P-51 trim falls from 732.8/757.5 to 484.2/461.3 µs/tick (34–39% lower), and stall from 870.3/879.7 to 618.6/594.6 (29–32% lower). The unchanged 500 µs/tick budget still fails in stall on both runs and ground on one. Every P-51 regime has a batch-p95 overrun in both native runs; additional overruns occur in the fleet table below.

At four ticks per 60 fps frame, native P-51 stall consumes 2.38–2.47 ms at the median and 2.53–2.76 ms at batch p95, against the 2 ms physics allocation. These are CPU physics costs, not rendered-frame/GPU measurements. The ground and stopped-engine spin fixtures bypass the native kernel; variation there and in non-P-51 aircraft is a control for host noise, not a native-kernel improvement or regression claim.

At the stalled initial fixture, native slipstream costs 19.3–20.1 µs/load evaluation; aero still costs 68.7–68.8 and propulsion 18.5–18.6. The next bounded performance investigation should target the remaining local-aero path and account for the evolving contact workload. Do not extrapolate initial-state component timings into a complete-flight budget. Before any production adoption, add powered ground/spin coverage, repeat the whole-fleet distributions, and build/run the Windows and macOS recipes under the same numerical policy. No broader physics rewrite is accepted by this result.

## Verification

- [Kernel report](results/kernel.json): **10,046 checks, zero failures**. Of 10,021 load comparisons, 10,004 are byte-identical; worst scaled error is `3.552713678800501e-15` against `1e-12`. Valid-boundary checks prevent malformed-input tests from passing vacuously; refusal produces a complete rollback with no completed-step signal.
- [Flight verification and source manifest](results/verification.json): **32/32 four-second fingerprints are byte-identical** across the two pairs. Every sampled body/auxiliary component difference is zero; all mode/tick comparisons are exact. Each fixture completes 960 ticks without a fault, at the shared 240 Hz setting.
- [Native-copy full suite](results/native-full-suite.log): all 172 scripts parse, 66 GDScript test programs pass, plus math-sensitivity, model/data contracts, trace checks and 30/60/144 fps independence; zero engine errors. No goldens were re-recorded and no tolerance was widened.
- [Comparator mutation tests](results/comparison-tests.log), [lint](results/lint.json) (zero errors, the same 11 baseline warnings), and [scene smoke with seeded input fuzz](results/smoke.json) (3/3 scenes) pass. Scene smoke ran after timing, with isolated user data.
- [Build evidence](build.json) records the pinned dependency/compiler versions, source/library hashes and strict floating-point flags. The comparison starts from committed application `fe26ef0`; it records the experiment source hashes separately because the experiment is uncommitted during measurement.

## Fleet timings

All values are µs/tick, shown as run 1 / run 2. **Bold exceeds 500.** Each row reports the same whole-tick method. Raw reports retain all samples and initial-state component profiles: [oracle 1](results/oracle-1.json), [native 1](results/native-1.json), [native 2](results/native-2.json), [oracle 2](results/oracle-2.json).

| Aircraft / fixture | Oracle median | Native median | Oracle batch p95 | Native batch p95 |
| --- | ---: | ---: | ---: | ---: |
| Ugly Stik / trim | 268.7 / 290.1 | 287.0 / 275.4 | 330.3 / 352.4 | 351.6 / 346.9 |
| Ugly Stik / stall | 320.0 / 338.6 | 322.1 / 317.8 | 408.9 / 390.9 | 359.5 / 343.0 |
| Ugly Stik / spin | 437.1 / 427.8 | 424.5 / 423.8 | **518.7** / 476.6 | 469.4 / **538.5** |
| Ugly Stik / ground | 304.5 / 298.6 | 311.8 / 328.2 | 348.3 / 420.3 | 402.7 / 358.7 |
| Extra 300S / trim | 291.4 / 264.5 | 279.6 / 284.3 | 367.3 / 302.0 | 340.8 / 354.3 |
| Extra 300S / stall | 331.6 / 362.9 | 336.0 / 345.5 | 438.8 / 439.0 | 362.5 / 398.9 |
| Extra 300S / spin | 432.6 / 429.3 | 406.6 / 437.3 | **501.2** / **729.4** | 439.6 / **567.9** |
| Extra 300S / ground | 415.9 / 435.4 | 410.4 / 417.7 | 496.8 / **558.9** | 448.8 / 469.6 |
| P-51D / trim | **732.8** / **757.5** | 484.2 / 461.3 | **767.8** / **835.6** | **659.2** / **549.1** |
| P-51D / stall | **870.3** / **879.7** | **618.6** / **594.6** | **1009.8** / **1036.8** | **690.5** / **633.1** |
| P-51D / spin | 434.2 / 453.3 | 460.3 / 455.6 | **522.3** / **519.3** | **505.8** / **533.9** |
| P-51D / ground | 484.7 / 488.5 | **509.9** / 484.1 | **536.1** / **527.8** | **595.3** / **601.6** |
| Avanti S / trim | 323.0 / 320.6 | 318.1 / 319.0 | 421.1 / 343.4 | 430.4 / 459.8 |
| Avanti S / stall | 378.0 / 395.4 | 375.9 / 385.3 | 459.2 / 471.1 | 441.0 / 450.6 |
| Avanti S / spin | 418.8 / 444.3 | 418.9 / 420.6 | 476.0 / **574.2** | **503.9** / 482.4 |
| Avanti S / ground | 430.4 / 445.8 | 431.8 / 417.0 | **515.2** / **550.3** | 462.9 / 488.0 |

## Reproduce the comparison

```sh
python3 research/native-slipstream/build.py --jobs 4 \
  --output .tools/native-slipstream/libopenrc_slipstream.so
python3 research/native-slipstream/run.py \
  --library .tools/native-slipstream/libopenrc_slipstream.so \
  --output /tmp/gate-p-results
```

The comparison runner requires Python 3.10+ and a clean committed `app/`. It creates two fresh local clones at the current HEAD, imports their resources, and replaces the slipstream route only in the native clone. Downloaded tools are shared through an explicit cache link. Production code, data and goldens are untouched. `--quick --skip-suite` is diagnostic only and records those omissions. A successful runner exit means verification passed; the report records performance-budget acceptance separately.

The native boundary takes body state (13 doubles), air-relative velocity (3), resolved model/control dictionaries, a thrust/torque pair (2), and density. The adapter extracts the pair from propulsion's three-value `[thrust, torque, advance ratio]` result. Propulsion and the remainder of Dynamics stay in GDScript. Native refusal becomes six nonfinite load sentinels, which the existing simulation guard rejects with full rollback. See [kernel mapping and semantics](kernel-notes.md).

The oracle checks use 10,000 seeded cases, 20 stopped/reverse/zero-flow cases, one implicit-axis case and explicit malformed-input/refusal checks. Random cases vary velocity, body rates, deflection, CG, incidence and wash parameters; 6,394 cases produce nonzero wash loads. Load agreement uses `1e-12 × max(1, |reference|)` per component. Model values are decoded on every call, preventing stale cached geometry.

After the complete native-copy `app/test.sh`, the runner measures four aircraft across trim, stall, spin-like and ground fixtures. Each timing run uses 16 batches of 120 ticks, plus a separate 960-tick replay from each fixture. Ordering is oracle/native, then native/oracle. No builds or other test engines overlap accepted timing runs; the owner's pre-existing renderer remains running. Each replay compares the initial and every subsequent body/auxiliary state using unchanged H9 component budgets, with exact mode and clock checks. Byte hashes additionally include start-of-tick loads. The comparator's mutation tests reject tolerance overruns, nonfinite data, mode/clock changes and truncated sample streams.

Timings include the whole simulation tick, including dictionary conversion and the GDScript/native crossing. Component timings describe the fixture's initial state, not its entire evolving trajectory. The p95 is a percentile of **120-tick batch averages**, not individual-tick latency. Extra/Avanti ground fixtures do not have configured gear; both ground and spin-like fixtures stop the engine, so neither measures powered takeoff/spin cost. These are performance/verification fixtures, not independent flight-physics validation.

## Binding and compiler pin

The installed engine reports `4.7.2.stable.official.ed1daf0bf`. Build against the 4.7 extension API using official `godot-cpp` `10.0.0-stable` at commit `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`. Version 10 is independent of the Godot release number and accepts API versions 4.3 through 4.7. The lock records the exact SCons 4.10.1 wheel URL and SHA-256. The script installs that wheel in `.tools/native-slipstream/venv`, checks the source commit, and keeps downloaded/build artifacts under ignored `.tools/`.

The generated binding build uses the pinned `feature_profile` containing `OS` and `RefCounted`; godot-cpp adds Object ancestry and its required loader classes. `OS` is needed by godot-cpp's own `print_string.cpp`. The first unrestricted archive attempt hit Linux's per-command argument limit. This bounded profile keeps the GDExtension static link small. Add a class to the locked profile if the isolated wrapper later needs another Godot class.

Linux is the verified host target. The observed environment is Ubuntu 24.04.4 x86_64, Python 3.12.3, and GCC 13.3.0. The extension and godot-cpp compile with `-fno-fast-math -ffp-contract=off`; use explicit `double` for kernel values. These options constrain compiler arithmetic but do not promise bit-identical results across CPU architectures or math libraries.

The built shared library, tool versions, source hashes, feature profile, and strict-flag compile database check are recorded in [`build.json`](build.json). The library is local under ignored `.tools/`; the evidence does not claim runtime validation or a portable binary.

## Build on Linux

From the repository root:

```sh
python3 research/native-slipstream/build.py \
  --output .tools/native-slipstream/libopenrc_slipstream.so
```

The script builds `template_release` for the host architecture and copies the resulting shared library to the requested path. The default output is `.tools/native-slipstream/libopenrc_slipstream.so`. Use `--target template_debug` only when a debuggable library is needed. The pinned Godot API level is 4.7; the library has only been targeted at the installed Godot 4.7.2 runtime.

## Windows and macOS recipes

The build script accepts a native-host build on each platform. Keep the same Godot API, godot-cpp commit, SCons wheel, release target, and class interface. These recipes have not been executed here.

Windows x86_64: install Python 3.9+, MSVC v143 14.44 from Visual Studio 2022 17.14, and Windows 11 SDK 10.0.22621.0. In a Visual Studio Developer PowerShell at the repository root, run:

```powershell
py -3 research/native-slipstream/build.py --platform windows --arch x86_64 `
  --output .tools/native-slipstream/openrc_slipstream.dll
```

The script applies `/fp:strict` when SCons selects MSVC. Do not use MinGW with this recipe.

macOS: install Python 3.9+ and Xcode 26.1.1 Command Line Tools with the macOS 26.1 SDK. Verify the installation with `xcodebuild -version` and `xcrun --sdk macosx --show-sdk-version`. On Apple Silicon build `arm64`; on Intel build `x86_64`:

```sh
python3 research/native-slipstream/build.py --platform macos --arch arm64 \
  --output .tools/native-slipstream/libopenrc_slipstream.dylib
```

The script applies strict Clang floating-point flags. This pinned recipe is unrun. No cross-platform or universal binary build is configured.

## References and limits

- [Godot 4.7 SCons build guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/cpp/build_system/scons.html): SCons is the godot-cpp build system and API files track Godot versions.
- [Godot 4.7 C++ GDExtension guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/cpp/gdextension_cpp_example.html): use matching bindings and the `.gdextension` entry symbol.
- [Official godot-cpp README](https://github.com/godotengine/godot-cpp/blob/10.0.0-stable/README.md): v10 versioning, API selection, and forward compatibility.
- [Godot 4.7 Windows toolchain](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_windows.html) and [macOS toolchain](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_macos.html): platform compiler setup.
- [Apple Xcode 26.1.1 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_1-release-notes): selected macOS toolchain pin.

This experiment establishes same-host numerical agreement and measured powered-trim/stall cost reductions for this bounded port. It does not establish cross-platform binary compatibility, deterministic cross-CPU arithmetic, powered takeoff/spin performance, flight fidelity or production readiness.

## Ready-to-paste commit message

```text
research(Gate-P): verify bounded native slipstream without production adoption

Proof: 10,046 kernel checks; 32 exact 960-tick flight fingerprints;
full native-copy app/test.sh; 3 scene smokes; two paired fleet runs.
P-51 stall improves to 595–619 us/tick but still misses the 500 us budget.
```
