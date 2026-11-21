# Mathematical and aerodynamic hardening - 2026-11-21

The [A36 original audit](../../../external%20Audits/physics-math-aero-audit-57abea0.md) reviews `57abea025f62b20233ca281d58d2acbee4ab8b8e`. This page owns its follow-up status and evidence. Work remains within existing IAQ/AC-PX, BL, FL and CI ownership; this is not a new simulation-kernel track.

The owner requested one GitHub branch containing every finding and continued physics, mathematical and aerodynamic improvement: `audit/physics-math-aero-2026-11-21`. Original artifacts below remain unchanged; implementation commits and later measurements must retain their own source identity.

## Original evidence

| Artifact | Purpose |
| --- | --- |
| [Audit PDF](originals/OpenRCsimulator-audit-57abea0.pdf) | Nine-page report, derivations, numerical observations and limits |
| [Evidence ZIP](originals/OpenRCsimulator-audit-evidence-57abea0.zip) | Seven checked probes and reports, portable exact-source reproducer, source manifests and CI records |
| [Artifact identity](originals/SHA256SUMS) | Original file SHA-256 digests |

The ZIP contains no repository source files. Supply the original checkout and official Linux x86-64 Godot 4.8-beta2 executable to its reproducer. Four imports and six clean probes passed; the jet probe reproduces a specific expected checked failure. The blimp session uses the disclosed fail-if-used collision stub on an empty-scenery path. No rendered/native/hardware/physical qualification is implied.

## Follow-up status

| Audit ID / owning area | Work and acceptance | Status |
| --- | --- | --- |
| F1 / IAQ, AC-PX | Preserve combined propeller thrust and torque through table construction; qualify interpolation/extrapolation and caps | Pending implementation and candidate checks |
| F2 / IAQ, AC-PX | Keep body drag dimensional area consistent with final biplane/fitted geometry and uniform scaling | Pending implementation and candidate checks |
| F3 / BL-03 | Passive neutral fin forces over signed flow; retain forward behavior and qualify full-angle changes | Pending design and candidate checks |
| F4 / BL-05, SF boundary | Depletion ends battery supply; accepted charge bounds, refinement and checkpoint/replay | Pending design and candidate checks |
| F5 / IAQ, AC-PX | Escape literal jet percentage; formatted provenance and zero engine diagnostics | Pending implementation and candidate checks |
| O1 / Creator lifecycle | Retire abandoned candidates while preserving live package owners; sustained memory/setup measurements | Open optimization; serialized retention is measured, RSS/speedup unmeasured |
| G1 / CI, release | Restore 13 sidecars and complete required CI on the integrated source | Open recurrence of historical UID failure class |
| G2 / BL-07, SF boundary | Failed preparation preserves the accepted flight, tape and observers | Open reproduced invalid-API failure; UI reachability unestablished |
| G3 / BL-08, FL/UI | Retained in-flight recorder failure/limit notification and recoverable-prefix handling | Open source-level gap; injected activity test required |

## Extension sequence and gates

1. Restore verification and fix jet diagnostics without weakening gates.
2. Repair Phoenix aggregation/reference-area invariants and version the derivation; qualify old receipt/draft admission and source-matched imported performance cards.
3. Repair blimp passivity/resource boundaries with independent energy checks, timestep refinement and checkpoint/replay; preserve shared-kernel ownership and float64/240 Hz.
4. Bound Creator candidate lifetime and instrument complete setup/memory workloads before claiming optimization gains.
5. Continue physical aerodynamics: coefficient reference conventions, finite-wing/section translation, low-speed control authority, propulsion energy and source-matched flight envelopes. Distinguish a calibrated model from an internally consistent estimate.

Use the [numerical-change checks](../../tools/physics.md#numerical-change-checks), [flight logging workflow](../../FLIGHT-LOGGING.md), [imported-aircraft plan](../../plans/imported-aircraft-quality.md) and [airship plan](../../plans/rc-airship.md). Required CI, actual-native parity/selection where affected, rendered flows, pilot/physical acceptance and target-host performance remain separate gates.
