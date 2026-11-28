# Native execution and admission

Scope: the decisions, alternatives and evidence behind native execution and admission. These records retain the context of each choice; linked guides and the [current roadmap](../../ROADMAP.md) own implemented behavior and remaining work. [Decision index](../DECISIONS.md).

## Native acceleration keeps the reference as its specification

The current NK-6 choice permits whole-tick native integration while `Simulation` retains commit, publication and recovery. The evaluator-only restriction in the original SF-08/NK-3 record below is superseded by the November 26 decision. [Current contract](../STACK.md#native-backend-policy).

**SF-08 / NK-3.** Keep the GDScript reference selectable and replace only an identified evaluation boundary. Receipts and replay bind the actual backend; unsupported configurations or unverified artifacts retain the reference. Owner-directed NK-3 promotion supersedes the blanket fixed-wing deferral: ordinary application flights request native by default for the verified Linux x86_64 aircraft catalog and admitted conditions, including coupled electric/battery, finite glow, liquid combustion, turbine and helicopter capabilities. The shared kernel and existing start, weather and runtime contracts remain authoritative. Completed flights, startup refusals, runtime refusals and terminal collisions carry separate evidence. Low-level sessions remain reference by default. NK-4 admits Windows x86_64 source/debug runs on the same evidence rule: a MinGW-w64 build with engine-matching math (no `sincos` fusion, the Windows engine's lerp order, SSE2 `sqrtsd`) is bit-identical, so the D3 NaN-class tolerance tier is not used; its installation sits beside the Linux one, never over it ([NK-4](../research/native-kernel/NK-4/README.md)). Windows release packages, macOS admission and target-host Gate P remain separate qualifications.

The [NK-3 promotion](../research/native-kernel/NK-3/README.md#expanded-linux-qualification-2026-10-29) records the original adoption and its qualified expansion. The original [SF-08 policy](../research/simulation-foundation/README.md#6-backend-policy-sf-08) retains its historical rationale and qualification requirements; its blanket port deferral and platform inventory are superseded. Its target-host evidence must not be presented as satisfied by the local promotion. Admission and packaging details live in the [native guide](../../research/native-kernel/README.md#normal-flight-backend-selection).

**Owner, 2026-11-20: native is the runtime, GDScript the specification.** Performance and flight-feel work runs on the native backend; confirm the logged backend before measuring. The GDScript reference is not retired: the C++ mirrors it bit for bit, so it remains the specification, the qualification oracle, the fallback and the only physics for imported aircraft, servo law, the airship and the multirotor. Historical `.orfl` baselines and replay keep their recorded backend. A fallback from a native request must be visible, not just a log line. [Legacy modes audit](../research/legacy-modes-audit-2026-11-20/README.md).

**DX-06, 2026-11-20; explicit owner preference.** Prefer native development and the native kernel whenever feasible and appropriate, including when planning new simulation work. The [shared native-development rules](../../AGENTS.md#native-development) own that preference and its implementation/target-platform criteria. Choosing native does not require first exceeding 500 µs; the budget, reference contract and qualification gates still apply. GDScript remains appropriate where its integration and maintenance advantages serve the task. This is a development direction, not evidence that a new backend, platform or workload is qualified.

**Owner, 2026-11-26: a native core, not native helpers (NK-6).** Offered native helpers inside the GDScript tick transaction or a native tick, the owner chose "núcleo nativo, todo nativo". This supersedes the rule that native code evaluates only model callbacks while `Simulation` integrates. For a model whose stage the kernel owns, the kernel integrates the tick from its first stage to the accepted endpoint. That covers RK4 and its substeps, the declared-event locator and every refusal, with the model's remaining GDScript callbacks called where the reference calls them. Later NK-6 steps port those callbacks, step policies and the helicopter tick. `Simulation` keeps the commit, publication, checkpoints and fault recovery. It runs any tick the kernel does not answer. The GDScript reference stays selectable and is the specification: every native tick must be byte-identical to it, and backend identity, replay and qualification rules are unchanged. [NK-6a](../research/native-kernel/NK-6a/README.md).

**DT-MAC-04n1–n4, source-editor admission.** The Apple ARM64 port retains that
stage boundary and float64 authority. Initial source-default adoption used an exact
host, engine, receipt, binary and stock-selection marker. The later
[DT-MAC-11a decision](native-execution.md#default-to-native-physics-on-supported-apple-silicon-flights)
removed that marker prerequisite for automatic admission, while retaining the
screened domain, engine/source/library identity and live guards. Keep
explicit research opt-in and release diagnostics separate. A changed on-disk
receipt cannot qualify a different library already loaded in the process. Use a distinct native Mac bundle identity
that binds the signed dylib, qualification manifest and final reference-bundle
receipt. Reusing the reference-only identity would make exact replay ambiguous.
The [Mac native guide](../../research/native-kernel/README.md#experimental-macos-arm64)
owns the implemented contracts and the [source-default evidence](../research/native-kernel/DT-MAC-04n4/README.md)
records the November 14 source-default qualification and its remaining gates.

The initial assessment deferred automatic admission. The later source-default
work enforces a smaller verified domain instead of treating failed fleet rows as
qualified. Source-editor adoption does not establish normal hardened signing,
downloaded-package trust, physical realism, FPS or energy gains. Public native
distribution remains deferred by owner instruction.

On November 14, B5 source `9386f5e5...` was adopted on the qualified M1 after
current-source numerical, fleet, sustained/resource and required CI gates.
The ledger binds actual canonical Main/replay and prepared Home/flight checks.
Technical Home checks used headless/Dummy with scenery audio off; normal
audio-enabled shutdown remains open and was not silently accepted as clean.

## Default to native physics on supported Apple Silicon flights

**DT-MAC-11a, 2026-11-16; explicit owner decision.** Normal macOS ARM64
Home and Quick Flight sessions request the native evaluator without requiring a
performance-promotion marker. Keep the stock production-trim domain, immutable
live configuration, exact engine/OS/library/source identities, package receipts,
applicable engine-pair binding and runtime guards. Unsupported or unavailable
native configurations retain reference fallback; explicit reference selection
remains authoritative. Low-level technical tools keep their reference default.

This is a product-default policy, not a claim of higher FPS or a passed performance
campaign. Preserve the failed performance screen and the separate qualification
tools. Public Developer ID distribution remains deferred. Measurement and package
limits belong in [DT-MAC-11a](../research/desktop-delivery-investigations/DT-MAC-11a/README.md).

## A native flight freezes its guarded configuration

**F1 / NK-6p, 2026-11-27; explicit owner decision.** Once the kernel accepts a fixed-wing native stage, the
session's guarded containers become read-only all the way down: the aircraft dictionary, the hull contact and the lake
(`NativeConfiguration.freeze_guarded`). Godot cannot make a container writable again. The configuration guard
therefore proves each frozen root's shape by its identity and drops its deep comparison per tick (16–42 → 6–8 µs).
A later container write fails where it is made, as an engine read-only error, instead of faulting the next native
tick. Packed arrays are the exception: the engine shares a packed array's buffer with every alias, so an element
write changes it in place even under a read-only parent. Each packed leaf therefore keeps a bitwise watch, and such
a write still faults the next native tick. Replacing a root with another instance still refuses the tick. Writable
containers keep the guard's comparison.

No production code writes these containers after setup. The guard's own tests turn the freeze off to keep covering
that comparison ([test](../../app/tests/test_native_frozen_configuration.gd)). Revisit if a feature must edit the
aircraft during a native flight: it should replace the dictionary at an accepted boundary instead.
