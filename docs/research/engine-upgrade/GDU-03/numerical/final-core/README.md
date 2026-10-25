# GDU-04: final-core numerical follow-up

2026-10-25. The unchanged GDU-04 runner was rerun on a fresh 248-file snapshot
after the minimum-normal constant relocation and the companion owner's
FlightSession invalid-start correction. Official 4.7.2 and 4.8-beta1 again
produce identical results. Every output stream also matches both original
engine outputs exactly.

| Compared output | Final result |
| --- | --- |
| 18 fixed-wing calm/turbulent trajectories | 960 ticks, 961 rows each; all 9,625,376 trajectory bytes per engine unchanged |
| Five seeded raw PCG32 streams | Words and advancing RNG states unchanged; both final engines match the existing independent Python recurrence |
| Five seeded OU streams | Initial samples and all updates unchanged |
| Imports and numerical probes | Four checked invocations pass, zero errors/warnings |

The 28 retained binary streams match four ways: original 4.7.2, original 4.8,
final-source 4.7.2 and final-source 4.8. The initial checkpoints and downstream
tapes are generated/restored through the same existing fixture; no original
output, golden flight or recording was rewritten.

Against the original tested closure, only three core files differ after CRLF
normalization: `physics/math3d.gd`, `physics/mass_inventory.gd` and
`sim/flight_session.gd`. The first two preserve the exact constant expression
at the [transcendental boundary](../../integration/math-boundary/README.md).
The separate FlightSession change explicitly resets throttle to zero when
airborne-start validation fails; it does not alter these valid-start
trajectories. Their final raw hashes are retained and still match root after
the runs. Presentation/admission JSONs are frozen as snapshot inputs, not
represented as the final later package or companion-requalification identity.

[Comparison](comparison.json), [source manifest](source-manifest.json) and
[four-way output/checked-run verification](verification.json) bind this new
evidence. All copied projects, profiles, full arrays and logs stay on D under
`D:/OpenRCsimulator-experiments/gdu04-final-core-20261025/`. Engine caches and
profiles are isolated; the concurrently running full-suite copy was not changed.

The [original experiment's limits](../README.md) still apply: this is a bounded
fixed-input numerical comparison, not trim-solver equivalence, every maneuver
or vehicle, physical validation, platform/performance qualification, or exact
cross-engine `.orfl` replay. Exact engine/source admission remains strict.
