# M1 access and isolated numerical experiments

**Date:** 2026-11-12, America/Bogota; native runs on 2026-11-13 UTC. **Owners:** DT/PT with SF/NK. **Source:** `40751b55188226e69143881c7c58f16bc0a3cfff`; the local dirty files were planning documents, not experiment inputs.

**Verdict:** SSH, the pinned ARM64 engine, the existing math test and a standalone C++/Accelerate build worked. A discriminating odd-tail control found byte differences in the disposable NEON and vDSP implementations. These are primitive/toolchain findings, not an implemented or qualified native evaluator, a solver speedup or physical validation. They refine [the implementation specification](../../../APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md) and [investigations I01–I12](apple-silicon-plan-reinforcement-2026-11-12.md).

## Host, scope and retained identity

The strict, noninteractive Windows SSH route to **ANGELA_AIR**, account `gius`, Tailscale `100.79.151.42`, succeeded using the existing key and known-host verification. No key, authorization, host-key entry or power setting changed. The separate `angel` alias did not resolve `Gs-MacBook-Air.local` during this session; that does not establish whether its Mac was awake or reachable by another route.

| Input | Observed identity |
| --- | --- |
| Hardware | MacBookAir10,1; Apple M1; 8 GiB; native ARM64 Python, no Rosetta |
| OS | macOS 27.0.1, build `26A434` |
| Engine | `4.8.beta2.official.cafc17a19`, Mach-O ARM64; `codesign --verify --deep --strict` passed |
| Engine SHA-256 | `2051c48febe532a5b156ffd8dd0c9381f74e40fde9177faff07a713851baba80` |
| Compiler / SDK | Apple Clang 21.0.0 (`clang-2100.3.34.2`), selected Command Line Tools, SDK 27.0 |
| Standalone binary SHA-256 | `70f14ddc3bb99e955a11d0b0339d13638b66b8eea07c49c8585ff89308f570d8` |
| Witness source SHA-256 | `d3a7c17f63c46563adee34578f04712c896581301fb0c93ecbc6af647ce55fde` |

The initial host check found AC power, about 7.9 GiB disk free and 2.3 GiB available RAM, with swap already in use. There was no observed Godot/Clang occupancy. A new task directory used under 1 MiB, avoiding a full asset/source copy. The existing engine and frozen campaigns were preserved. The seven-file repository archive was 80 KiB and its SHA-256 was checked before extraction.

Raw inputs, failed and successful commands, binary, disassembly, preflight, checked logs and results remain at:

- Mac: `/Users/gius/OpenRC-m1-work/m1-native-feasibility-20261112T235850Z/`.
- Windows: `tmp/m1-native-feasibility-20261112T235850Z/remote-final/`, outside tracked files. `artifact-manifest-final.json` binds retained file sizes and hashes, checked after transfer. The earlier `remote/` copy preserves the primary campaign checkpoint.

The final manifest SHA-256 is `44632fc1ec6da75dcc4b0850865ff6b0cc66dda0be12c5e6114a8c4719340499`. Final teardown found no related Godot/Clang/keep-awake process and rechecked the unchanged engine executable.

The source archive contains only `math3d.gd`, `frames.gd`, their existing test and the preflight/checked-runner dependencies. The project configuration is a uniquely named microproject with no production autoloads or assets. This is not an imported production flight session. The [M1 workflow](../../tools/macos-m1.md) owns future connection and workspace setup.

## Experiment 1: actual tools and engine preparation

The existing `macos_preflight.py` completed before and after the primary experiments. Both engine architecture/version and signature checks succeeded; its executable hash remained unchanged. The preflight did not find an `instruments` executable on PATH; full Instruments/`xctrace` availability was not established. The Foundation snapshots reported nominal thermal state and Low Power Mode off; pressure was uncollected. Nominal does not prove sensor availability, and two snapshots do not describe temperature, frequency or pressure during each block. No energy was measured.

The first native build failed: the Accelerate umbrella header included `<complex>`, but Clang's default C++ search path did not find it. Inspection found libc++ headers in the **installed SDK**, while the corresponding toolchain header was absent. Adding the existing SDK directory explicitly allowed compilation:

```bash
sdk="$(xcrun --show-sdk-path)"
xcrun clang++ -std=c++17 -O3 -fno-fast-math -ffp-contract=off \
  -Wall -Wextra -isystem "$sdk/usr/include/c++/v1" \
  inputs/arm64_witness.cpp -framework Accelerate -o arm64_witness
```

`compile.log` preserves the failure; `compiler-header-diagnostic.json`, `build-adjustment.json` and `compile-sdk-headers-command.json` explain the change. Nothing was installed or repaired globally. Dependencies were Accelerate, libc++ and libSystem. A successful standalone build does not establish godot-cpp/GDExtension compatibility or an older deployment floor.

**Plan consequence:** phase 1 must execute a real compile/link, not infer toolchain readiness from discovered paths. Record the SDK header route in the effective build identity and resolve it in the existing builder before a port.

## Experiment 2: current math and observable floating-point behavior

The existing checked runner imported the microproject and ran the unchanged `app/tests/test_math3d.gd`: **20 checks, zero failures**, with no engine errors or warnings. It includes 500 rotation comparisons against the original float64 expression, boundary fixtures and accumulation checks. This is a focused software test; its render-coordinate comparison has its own tolerance.

A disposable GDScript witness decoded runtime bit strings, avoiding decimal folding. Its 17-value corpus covered both zeros, positive/negative subnormals, normal boundaries, infinities, two distinct quiet NaNs and finite values distinguishable beyond float32. Scalar and `PackedFloat64Array` round trips preserved all 17 bit patterns. This does not test transport through a native extension or signaling NaNs.

For runtime `(1+2^-27)*(1-2^-27)-1`, both the separated and expression forms in Godot produced `+0`. Standalone C++ produced `+0` for separate operations and `-2^-54` for explicit `std::fma`. C++ FPCR was `0` before/after, including round-to-nearest; that observation belongs to the **separate C++ process**, not Godot or an extension call.

The first 289-pair multiplication matrix matched Godot exactly for ordered ARM64 multiplication, NEON and `vDSP_vsmulD`. Godot `maxf` matched `a > b ? a : b`; compiled `std::fmax` differed in **33/289** cases. For example, `maxf(+0,-0)` returned `-0`, while the tested `std::fmax` returned `+0`; numeric/NaN cases also differed. Comparing numeric equality alone would miss signed-zero and payload differences.

**Plan consequence:** keep the FMA detector, runtime bit inputs and exact max-helper semantics. These observations cover this engine/compiler/OS tuple and corpus, not all arithmetic or the native ABI.

## Experiment 3: small-vector cost screen

The predeclared primary length was six, with lengths 3, 5, 7, 8, 16, 64 and 256 as context. Each process used 10,000 warmup calls per variant/length and five blocks of 200,000 calls. Order was four rotations plus one reverse block; the fifth block prevents perfect positional balance. Two processes of the same binary were retained. They are a repeatability screen, not a formal interleaved A/A campaign or confirmatory sample.

The variants were instruction-ordered scalar assembly, ordinary optimized C++, explicit two-lane NEON and vDSP. The scalar assembly is a synthetic arithmetic reference, not an ARM64 NK-3 implementation. Finite outputs matched at all eight lengths before timing, including odd tails. Checksums agreed. Disassembly retained calls inside the counted loops; vDSP called the actual framework. The ordinary C++ path used scalar work at six and vectorized work in the measured eight-element layout. Neither threshold nor instruction choice is portable to another compiler/layout.

Numbers are **median of five block means, ns/call**, shown as **process 1 / process 2**. They are not median individual-call latency or p95.

| Length | Ordered scalar | Ordinary C++ | NEON | vDSP |
| --- | --- | --- | --- | --- |
| 3 | 4.363 / 2.812 | 6.301 / 3.154 | 3.394 / 1.250 | 7.281 / 2.812 |
| 5 | 7.446 / 3.435 | 8.009 / 3.747 | 3.410 / 1.367 | 7.797 / 3.124 |
| 6 | 6.139 / 3.748 | 6.205 / 4.060 | 4.092 / 2.499 | 4.605 / 2.811 |
| 7 | 4.692 / 4.065 | 5.053 / 4.379 | 3.457 / 2.813 | 4.692 / 4.065 |
| 8 | 4.372 / 4.374 | 1.562 / 1.562 | 2.810 / 2.812 | 4.371 / 4.372 |
| 16 | 6.870 / 6.872 | 2.773 / 2.930 | 4.060 / 4.062 | 5.620 / 5.624 |
| 64 | 21.879 / 21.922 | 11.304 / 11.224 | 11.554 / 11.559 | 8.013 / 8.021 |
| 256 | 88.611 / 88.726 | 44.754 / 44.794 | 49.655 / 49.659 | 27.955 / 27.969 |

Substantial movement between processes at small lengths prevents a stable absolute benefit claim. The cause was not traced; do not attribute it to temperature or frequency. Ordinary C++ beat manual NEON at eight in both processes, and vDSP beat ordinary C++ at 64/256 in both. This supports retaining compiler/library comparisons, not a universal crossover.

Buffers were preallocated, nonaliasing, unit-stride, hot and at most 2 KiB, with repeated inputs. Calls include their wrapper/loop barrier but omit Godot crossing, packing, preparation, reductions and complete-stage work. No tick, frame, 500 µs budget or energy conclusion follows.

## Experiment 4: odd-tail counterexample

Review found that Clang reversed the scalar tail's multiplication operands in the disposable NEON function. The first corpus put a finite value in its last, odd-tail slot, so its 289 matches could not detect two-NaN priority there.

An additional **semantic control** exchanged corpus slots 12 and 16, placing negative quiet NaN `fff8000000000002` in the odd tail. The unchanged binary and pinned Godot then produced:

| Inputs at pair `[16][11]` | Godot / ordered ARM64 | NEON | vDSP |
| --- | --- | --- | --- |
| Negative payload-2 NaN × positive payload-1 NaN | `fff8000000000002` | `7ff8000000000001` | `7ff8000000000001` |

Ordered multiplication still matched all 289 Godot outputs. NEON and vDSP each differed in **1/289**. Their failure is observed; only NEON's scalar tail was inspected internally. Do not infer vDSP's internal implementation. The ordinary C++ variant was not included in either special-value matrix, so its finite screen does not establish malformed-input equivalence.

The third invocation necessarily emitted incidental timings, retained in `tail-control.log`; these are excluded from the frozen two-process timing analysis regardless of outcome. `tail-control-command.json` records that purpose. Checked Godot comparison completed without warnings/errors.

**Plan consequence:** the naive candidates fail general byte equivalence. Exercise each special value and operand order in every scalar/vector/tail position and actual length before accepting SIMD or a library. The successful original matrix cannot close that gate. A future candidate must preserve required NaN behavior or establish an explicitly enforced admissible domain; it cannot silently weaken the existing malformed-input contract.

## Remaining qualification and retention

No production file, loader policy or physics law changed. No full flight, native extension, fleet, recording/replay, sanitizer, signed-host extension loading, notarized package, GPU or 1080p experiment ran. The system-reported 1440×900 display dimensions are inventory, not drawable/presentation proof. The native port remains conditional; these results do not close a phase or justify its full budget.

Use a new workspace for repetition, preserving the primary and tail input manifests, exact engine/compiler/SDK identities, effective flags and all outcomes. The retained drivers hard-code this task directory and intentionally refuse to overwrite logs; do not rerun them against the frozen campaign. Extend existing owned build/oracle tools for implementation rather than promoting these disposable drivers into product infrastructure.
