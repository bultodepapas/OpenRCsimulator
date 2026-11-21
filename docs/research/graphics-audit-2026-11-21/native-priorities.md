# Native optimization priorities

The user's preference for native code is consistent with the repository's architecture: use built-in/native bulk operations, then bounded C++ evaluators behind the existing transaction and parity boundary where measured cost justifies them. A translation into C++ is not itself a performance result. Current native coverage and platform exceptions appear in [runtime-native.md](runtime-native.md#actual-native-coverage-interpretation).

## Recommended order

| Order | Work item | Smallest useful experiment | Why this precedes a broader rewrite |
| --- | --- | --- | --- |
| 1 | Trustworthy calibration and complete timing | Resolve C1–C3; compare full callbacks, actual backends and uninstrumented control | Prevents testing the wrong workload or hiding the expensive work |
| 2 | Nitro artifact identity cost | Current source/package attribution; immutable packaged identity or explicit mutation invalidation with all existing guards | Eliminating repeated file/buffer work may help even when the body solver is already native |
| 3 | Reference companion evaluators | Individually prepare/admit one supported agent with the existing evaluator; expand only after parity | Reuses an existing C++ seam; does not require a new fleet integrator |
| 4 | Accepted-state observer duplication | Same-tick detached contact result or existing combined audio wind/air helper, only for matching predicates | Removes duplicate work before paying a new interop/ownership cost |
| 5 | Field and meadow construction | Attribute one large unit; bounded preparation, lazy projected setup and compact native/built-in buffers | Existing staging/caching already exists; reduce the residual unit |
| 6 | Sky, water, cloud-cache and grass GPU cost | Native engine subpass/material/batching/publication experiment for the measured pass | C++ cannot remove a GPU synchronization or pixel burden merely by issuing it faster |
| 7 | Larger stage batching / worker architecture | Only after current fleet and remaining profiles show need | Has much greater determinism, transaction, lifecycle and validation cost |

These orders are investigation priority, not claimed millisecond rankings. A captured GPU-bound target can move item 6 ahead of a CPU experiment. Preserve all physics at 240 Hz, float64 stages and the accepted simulation clock; renderer changes cannot feed collision or simulation decisions.

## Companion native admission is not automatic inheritance

Current agents create reference-default low-level sessions. A native player does not establish that an agent has the same world, spawn, track, supported stage or solver identity. Linux/Windows fixed-wing stage reuse is plausible only after individual preparation/admission and native-call verification. A nonempty RC circuit currently refuses native and agents copy the player's track. The Apple automatic stock domain also rejects the external spawn heading used by companions, while the Mac companion-enabled player route is separately conservative. These are current refusal contracts, not switches to remove casually; see [FlightSession admission](https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/sim/flight_session.gd#L741-L805), [agent setup](https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/ai/companions/agent.gd#L35-L89), and [Mac domain](https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/sim/native_macos_domain.gd#L150-L180).

Start with one admitted, supported configuration; prove actual stage/context calls and refusal when mutated. Compare 0–3 agents at primary display targets with the same ordered inputs. Require full callback and frame tails, sim/wall, per-agent states and events, and lifecycle/failure checks. If the supported domain excludes a target configuration, report reference fallback; a future domain extension is its own correctness and package qualification task.

## Why cross-agent SIMD batching is not a drop-in wrapper

Each agent calls `FlightSession.step_external_tick()` and synchronous `Simulation.step()`. RK4 stage N+1 depends on prior outputs; adaptive substeps and event-location paths can differ between agents. A bulk function around already-serial complete steps cannot combine their internal callbacks. True cross-agent stage batching requires a new coordination boundary, suspended/continued stages or a redesigned native contract, with divergence and fallback handling. It could cost more than it saves for the current maximum of three companions. See [stage orchestration](https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/sim/simulation.gd#L474-L579) and [external tick ownership](https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/sim/flight_session.gd#L3183-L3285).

Preserve the common pre-player snapshot, planning-before-advance order, serial commit and world-damage publication, each private weather/RNG and input state, fault/rollback/reentry, and recording order. Per-session ORFL files explicitly do **not** implement fleet-decision/shared-world replay; their presence cannot certify equivalence. A pure planner worker over immutable snapshots is a separate existing AFC-27 proposal and should remain separate from the solver experiment.

## Native implementation boundaries

**Math and transaction:** preserve the repository's qualified floating-point behavior and compiler switches, reduction order, finite checks, signed zeros/NaN handling where required, guard refusal, checkpoints and solver identity. Do not enable fast-math or approximate transcendental functions for an apparent microbenchmark win. Windows NK-4 math evidence, Linux admission and Mac screened-domain rules are separate qualifications. Engine ABI and both native source and binary digests matter.

**Data movement:** prefer a compact contiguous representation and one bounded bulk operation when the profile shows dictionary/object overhead. Godot's [MultiMesh guidance](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) supports native bulk buffers, but whole-batch culling and extra draw calls still trade off. For meadow construction, retain the entire candidate/ranking decision and exact ties; defer heavy final record creation only after preserving the selected members/species.

**Ownership and threads:** move only detached, exclusively owned data preparation to a worker. Publish scene/resource changes at the allowed engine boundary. Godot's [thread guidance](https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html) warns about active-tree access and GPU synchronization; verify exact pinned APIs before implementation. A cloud readback may block regardless of whether GDScript or C++ calls it. A previous direct viewport-texture experiment failed on Mac, so retain validation/fallback and prove a new publication scheme there.

**I/O and observability:** a native immutable identity or bounded writer can remove interpreter/file overhead, but must not weaken live-source mutation checks or mark a truncated stream complete. Keep sequence/checksum semantics, backpressure, error propagation and teardown. The file cache already exists; removing redundant physical source reads requires a stronger ownership contract, not another unchecked cache.

## Experiments to defer unless attribution changes the decision

- A new engine fork for routine scene/resource batching that built-in Godot APIs can perform.
- A general native rewrite of all GDScript, including low-cost UI and policy code.
- Lower physics rate, approximate integrator/math or renderer-dependent physical inventory.
- Parallel mutation of live sessions/scene nodes or unqualified cross-agent stage batching.
- A blanket platform renderer switch based on a relative GPU-score table. The named UHD 630 comparison already contradicts a universal Mobile-faster assumption in its tested setup.
- Disabling diagnostics, guards or visual features solely to make the benchmark pass; record their actual product configuration and measure bounded alternatives.

These are deferrals based on evidence and contract cost. They can be reconsidered when a current profile identifies the exact bottleneck and an owner-reviewed experiment has an attainable correctness and hardware gate.
