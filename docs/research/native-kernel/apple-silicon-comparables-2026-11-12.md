# Apple Silicon comparable projects: gains, benefits and limits

**Reviewed:** 2026-11-12. **Owners:** DT/PT and SF/NK, supporting DT-MAC-04n1–04n4. **Method:** primary project documentation, author measurements and research papers; no local or remote benchmarks executed.

This is a dated supplement to the [native implementation plan](../../../APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md#3-technical-research-and-references). The repository was clean at `e766561c7cebc6b0d69b650449ace66f8b225cc2` when this follow-up started. The supplement does not refresh the plan's earlier runtime/source audit or qualify a new backend. The [Apple master plan](../../plans/apple-silicon-performance.md) retains status and adoption ownership.

## Findings that affect the decision

There are credible examples of substantial Apple-native improvements. Their mechanisms differ: optimized CPU libraries, large GPU grids, rendering backends, and better CPU/GPU work distribution. None establishes the gain of a same-host, byte-identical float64 Godot evaluator for a single 240 Hz RC flight.

The evidence supports keeping the existing staged approach: measure the complete workload, port only the evaluator when justified, preserve scalar correctness, then try matching CPU optimizations. GPU results for millions of elements provide useful design examples for future independent workloads, not a reason to change the authoritative physics precision.

Ratios below are either explicitly attributed reported values or calculations from the stated times/rates. For fixed work, speedup is `old_time / new_time`; for throughput, `new_rate / old_rate`. A 2× speedup means 50% less time, not a 200% time reduction. Energy efficiency, throughput and frame rate remain separate metrics. Results were not independently reproduced here.

## 1. MATLAB: an already-native application benefits from a better CPU library

Mike Croucher's **2023-12-13** MathWorks report compares OpenBLAS with Accelerate in **MATLAB R2023b Update 4**, on the same plugged-in **10-core M2 Pro MacBook Pro, macOS 13.3.1**. Matrix multiplication at N=1,000 took **17.2 → 4.6 ms**, about **3.74×**; N=10,000 took **6.8977 → 3.3186 s**, about **2.08×**. The same report records a regression: N=10,000 eigenvalues took **145.4076 → 201.57 s**, about **39% more time**. These are library-operation measurements, not a simulator/FPS result or byte-equivalence proof. [MathWorks measurements and benchmark script link](https://blogs.mathworks.com/matlab/2023/12/13/life-in-the-fast-lane-making-matlab-even-faster-on-apple-silicon-with-apple-accelerate/).

A separate **2025-08-19** report gives a broader-workload check: the same R2024b CNN training benchmark on a 10-core M2 MacBook Pro, changing BLAS, had warm runs **70.7/70.5 → 47.7/47.4 s**, approximately **1.48–1.49×**. It includes one epoch over 50,000 images and augmentation; only three sequential trials, with a slower first run. Training precision/accuracy equivalence is not established by those timings. [MathWorks training experiment](https://blogs.mathworks.com/matlab/2025/08/19/deep-learning-training-in-matlab-has-just-gotten-faster-on-apple-silicon-macs/).

**OpenRC inference:** replacing an interpreter is not the only source of native benefit; an existing native implementation can benefit from an appropriate tuned library. The operation and complete-consumer gains must be measured separately. This provides no reason to insert a matrix library into short scalar RK expressions that do not perform matching matrix work.

## 2. AppleAccelerate.jl: real float64 gains, with important baseline controls

The project's **July 2026** tables identify an **M2 Max, macOS 26, Julia 1.12.6, v0.8.0 master**, with minimum-of-five-trial timing and published scripts. Its separate N=4,096 float64 GEMM thread sweep gives **OpenBLAS 52.5 vs Accelerate 314.8 GFLOPS at one thread**, about **6.00×**. At eight threads it is **354.1 vs 618.1**, only **1.75×**. Float64 elementwise addition/multiplication are near parity or slower; sparse matrix-vector N=10,000 takes **2,117 µs with Apple vs 508 µs with SuiteSparse**, about **4.17× slower**. The documentation is mutable and reports best times, not latency tails or exact output identity. Its internal hardware explanations are not needed to accept the measured rows. [Project benchmark tables, environment and scripts](https://julialinearalgebra.github.io/AppleAccelerate.jl/dev/benchmarks/).

**OpenRC inference:** compare against an optimized CPU baseline, include the intended thread budget, and benchmark the actual operation. Float64 availability does not establish scalar-engine byte identity. A library's headline matrix gain cannot be generalized to sums, sparse work or small aircraft vectors.

## 3. Elastic-wave simulation: approximately 10× for a large FP32 grid

Gebraad and Fichtner's **arXiv:2206.01791v3, 2022-06-28**, compares C++/OpenMP and Metal on a **2021 M1 Max MacBook Pro, 10 CPU/32 GPU cores**. Their elastic-wave solver at **5,000×5,000** reports approximately **10×** versus eight CPU threads, with some surrounding work remaining on CPU. All simulations use **FP32**. That 5,000×5,000 point had only limited measurements; the authors report unpredictable RAM exhaustion above roughly 2,000×2,000. For simpler one-dimensional operations, serial CPU remained fastest up to roughly **65,536 elements** in their tests; that is an observed workload threshold, not a universal GPU cutoff. [Paper, sections 3–5](https://arxiv.org/html/2206.01791v3).

**OpenRC inference:** regular grids with substantial parallel work can justify Metal and benefit from unified memory. A thirteen-value body plus comparatively small continuous blocks has a very different workload shape. The FP32 result does not meet OpenRC's float64/byte-oracle contract, and the reported gain does not predict one flight tick's latency.

## 4. Blender: large visible gains by changing the graphics backend

Blender's **2023-01-13** developer report compares **OpenGL and the upcoming 3.5 Metal viewport**. On the same **M1 Ultra Mac Studio**, Tree Creature playback was **12.6 → 65.4 fps at 1920×1080**, about **5.19×**, and **12.6 → 34 fps at 3840×2160**, about **2.70×**. On M1 Max, Amy playback was **19 → 24 fps**, about **1.26×**. These are selected graphics workloads, not physics or a general gain across scenes. [Blender developer measurements](https://code.blender.org/2023/01/introducing-the-blender-metal-viewport/).

**OpenRC inference:** if measured frame time is limited by rendering/driver work, that boundary may offer the largest visible benefit. OpenRC already has a Metal renderer; the relevant comparison is its current configured renderer and workload. A historical OpenGL-to-Metal migration cannot be counted again as a benefit of a new C++ evaluator. Cold shader work, steady playback and resolution must remain separate comparisons.

## 5. Neutron transport: keeping selected work on CPU improves energy efficiency

Changyuan Liu's **arXiv:2401.11455v2, 2024-03-17**, studies an **M2 Max with 8P+4E CPU cores and 38 GPU cores**. In the same hybrid transport code, CPU sorting instead of GPU sorting improved ExaSMR efficiency from **3.7k → 4.5k particles/s/W** for fresh fuel and **2.5k → 3.0k** for depleted fuel: approximately **22% and 20%**. These are energy-efficiency results, not FPS or tick-latency results. The GPU code is FP32; its larger comparisons with OpenMC also change precision, particle counts and other numerical work, so those larger ratios are not clean port effects. [Paper, configuration and table VII](https://arxiv.org/html/2401.11455v2).

**OpenRC inference:** unified memory can make a carefully chosen CPU/GPU partition worthwhile; moving every operation to GPU is not the goal. Any energy claim for OpenRC still needs matched completed work, thermal/power context and actual measurement. Less elapsed time or CPU utilization alone does not prove better joules per tick or battery life.

## 6. OpenMM: a faster GPU kernel is not a whole-simulation gain

In **OpenMM issue #3924, 2023-01-20**, Philip Turner reports an M1-targeted, stripped-down interaction-block kernel: **25,573 → 17,337 µs**, approximately **1.48×**, after unrolling and a Metal prefix-sum primitive. Further experiments changed algorithms and storage precision; those are separate candidates. The thread explicitly discusses conservative interaction admission when reducing precision. The timings cover an isolated kernel and particular setup, not complete MD throughput; the issue does not fully specify the chip variant, repetitions or numerical parity for the quoted pair. [Author experiment and maintainer review](https://github.com/openmm/openmm/issues/3924).

**OpenRC inference:** inspect the generated implementation rather than assuming the compiler applies an optimization. Preserve the numerical/admission rule, include full call-boundary overhead, and measure the consumer. A local GPU optimization neither demonstrates direct float64 support nor qualifies an entire simulation.

## 7. MuJoCo: the close architectural counterexample

The **MuJoCo 3.3.5** MJX documentation warns that its accelerator implementation can be **10× slower for a single scene**, while targeting thousands of parallel scenes. This is published architectural guidance, **not a measured M1 result with a specified configuration in that passage**. The page's separate M3 Max `testspeed` throughput example uses multiple parallel CPU rollouts; its total steps/s is not the latency of one scene. [Versioned MJX guidance](https://mujoco.readthedocs.io/en/3.3.5/mjx.html#the-sharp-bits), [testspeed semantics](https://mujoco.readthedocs.io/en/latest/programming/samples.html#testspeed).

**OpenRC inference:** single-flight latency and batch simulation throughput are different products. A GPU design for parameter sweeps or training may be useful without benefiting the live single-aircraft loop. Do not import batch-oriented numerical shortcuts or solver tuning into a byte-preserving port.

## 8. Dolphin: numerical consistency and delivery are part of the port

Dolphin's **2021-05-24**, updated **2021-06-03**, native M1 report describes an existing AArch64 backend, universal delivery and cross-JIT netplay tests. Rounding defects had caused physics desynchronization in selected games; fixing them enabled tested sessions to synchronize, with limited coverage. Its cross-machine performance/energy comparisons and Rosetta baseline are not an estimate for OpenRC, whose Mac engine already runs natively. [Dolphin's original port report](https://dolphin-emu.org/blog/2021/05/24/temptation-of-the-apple-dolphin-on-macos-m1/).

**OpenRC inference:** reuse the existing evaluator seam and test exact trajectories, replay, backend identity and real packages. A fast primitive without numerical and delivery correctness is an incomplete port. Dolphin's JIT memory requirements are specific to its execution model and do not imply that an ordinary compiled OpenRC evaluator needs a JIT entitlement.

## Benefits worth measuring for OpenRC

| Potential benefit | Evidence that would establish it | What does not establish it |
| --- | --- | --- |
| Lower CPU cost per accepted flight tick | Same-host complete-session per-tick distributions with actual native execution and identical input/state tapes | A matrix/NEON microbenchmark or another project's ratio |
| More margin for expensive contact, weather or aircraft laws | Current worst required regimes meeting the owning budget without changing timestep, inputs or laws | A fast trim mean alone |
| Better frame consistency/input responsiveness | Matched packaged 1080p product runs, pacing/hitches and input observation | Detached throughput or GPU utilization alone |
| More graphics/effects headroom | The same 1080p scene/preset measured with the new backend, with rendering attribution and unchanged physics | Spending hypothetical CPU savings on unmeasured GPU features |
| Lower energy/thermal load | Energy per accepted tick/simulated second plus sustained power/thermal context | Lower CPU percentage, a short burst, or a different machine's watts |
| Faster offline sweeps | Completed independent scenarios/s, numeric/replay policy and bounded resources | Treating aggregate batch steps/s as single-flight latency |
| Sustainable native support | Shared laws, small platform shim, reproducible packages, qualified domain and tested reference recovery | A one-off dylib or a successful compile |

## Translating a local speedup into practical benefit

The following are **accounting scenarios, not measured gains or forecasts**. If the replaced evaluator occupies fraction `f` of total tick CPU time and becomes 2× faster, `new_tick / old_tick = 1 - f + f/2`:

| Measured evaluator share assumed for illustration | Tick time saved | Complete-tick speedup |
| --- | ---: | ---: |
| 20% | 10% | 1.11× |
| 40% | 20% | 1.25× |
| 60% | 30% | 1.43× |

For a serial accounting example, a 16.67 ms frame containing 2.0 ms of physics, half of it evaluator work, would save only **0.5 ms**, about **3% of frame time**, if that evaluator doubled in speed. CPU/GPU overlap or a GPU bottleneck can reduce the visible effect further. This is why the benchmark must retain the complete tick and live application as separate levels.

No defensible Apple-native OpenRC gain interval follows from these heterogeneous studies. The retained [NK-3 Linux](NK-3/README.md#expanded-linux-qualification-2026-10-29) and [NK-4 Windows](NK-4/README.md#measured-cost) evidence is closer to this evaluator, but still cannot establish a Mac result. Do not average external ratios or multiply independent case-study gains.

## Consequences for the existing plan

| Existing step | Concrete research consequence |
| --- | --- |
| Baseline / DT/PT | Attribute evaluator, observers and rendering separately; record native process architecture and optimized baseline, not Rosetta or a scalar straw baseline |
| DT-MAC-04n1 | Keep same-host malformed-inclusive float64 exactness ahead of speed; published FP32/toleranced successes do not relax the gate |
| DT-MAC-04n2 | Reuse existing C++ preparation/context/ABI and keep platform-specific arithmetic small; measure boundary and allocation costs |
| CPU experiments | Include actual short-vector sizes and intended thread budget; try Accelerate/NEON only for a matching measured operation |
| DT-MAC-04n4 | Require complete-session benefit and actual 1080p package/pacing checks; report energy and offline throughput separately |
| Optional future GPU work | Demand an independent large consumer and explicit numerical contract; do not create a GPU flight solver merely because a grid benchmark is fast |

The published cases strengthen the case for a measured, narrow native path and existing rendering optimization. They do not change the entry/promotion gates, justify an engine fork, establish hardware qualification or authorize implementation.
