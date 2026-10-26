# Ground physics evidence

Status: implementation integrated; numerical verification recorded, physical calibration open, 2026-10-11. Owner: physics line. Prefix: GP-.

The pre-implementation plan is consolidated into [GP-05](GP-05/README.md). The pre-implementation SHA-256 was `c069c6961b976d6bf3d23c2aefcc6d7f80457ac36bd4f488beec49f2d4e93191`.

- [GP-01](GP-01/README.md): deterministic field micro-relief, analytical gradients and renderer cue.
- [GP-02](GP-02/README.md): independent force, wheel spin, rolling resistance and braking checks.
- [GP-03](GP-03/README.md): aircraft profiles, session state, trace/checkpoint identity and wheel presentation.
- [GP-04](GP-04/README.md): aircraft scenario measurements.
- [GP-05](GP-05/README.md): integration, parity, performance, tuning and remaining acceptance gates.
- [GP-06](GP-06/README.md): fleet landing-gear audit (2026-10-19): glow Stik wheel profiles, Stik contact datum, reserve-energy gear travel, visual/physics contact and reserve-drop regression tests; stiffness, bounce and wheel-shape decisions open.
- [GP-07](GP-07/README.md): Ugly Stik airframe contacts (2026-10-25): crash hull generated from the drawn model (worst sink 104 → 9.5 mm), airframe friction per field surface with load-scaled regularization, the runway strip as turf in crash presentation; ploughing, static friction and field measurements open. [Sources](GP-07/sources.json).

- [GP-08 audit and sources](GP-08/sources.md): dated 2026-10-25 research for the [advanced ground/flight masterplan](../../advanced-ground-flight-physics-masterplan.md), GP-08…23. Following implementation authorization, [frozen baseline](GP-08/evidence/README.md) and [candidate comparisons](GP-08/evidence/candidate/README.md) retain four exact air/ground cases. Full fleet/drop/performance qualification remains open.
- [GP-09a](GP-09/README.md): fixed-axis relative-wheel/body coupling foundation, actual legacy power-balance counterexample and independent energy/momentum tests. Stock flight law and moving-axis/shaft migration remain unchanged/open.
- [GP-10a/b](GP-10/README.md): typed solid-support observations and material provenance, independent relief-profile adapter, and corrected hull normals on lake banks. Round-wheel geometry, complete hull relief migration and live explicit profiles remain open.
- [GP-14a](GP-14/README.md): accepted survivable gear-up accidents, scrape/bounce deduplication, terminal escalation, rules-version coverage and real session/persistence checks. Full shared event vocabulary and physical component failure remain open.
- [GP-11 integration cohort](GP-11/README.md): exact compliant spring/stop potential and rebound dissipation, common shaft/wheel and round-wheel dependencies, optional aircraft ground authoring, and an explicit aggregate inertia reservation. Executable foundations; stock migration and physical calibration remain open.
- [GP-12 contact composition](GP-12/README.md): wheel/material impulse rows, conditional multibody admission, bounded accepted-step/refinement receipts and the existing electric-source torque bridge. Real-kernel fixtures pass; aircraft session migration, source-event composition and stock activation remain open.
- [GP-16/17 foundation](GP-16/README.md): persistent attached-gear capacity failure, potential-release ledger and generic atomic endpoint/checkpoint contracts. Actual failed support geometry and peak-load runtime integration remain open.

The delivered GP records are software and numerical checks. No independent physical RC rollout, drop or taxi calibration was available.

