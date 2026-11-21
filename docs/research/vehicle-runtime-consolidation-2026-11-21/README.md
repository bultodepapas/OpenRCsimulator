# Vehicle runtime consolidation — source review (21 November 2026)

**Branch:** `plan/vehicle-runtime-consolidation-2026-11-21`. **Inspected:** `bultodepapas/OpenRCsimulator` at `main` commit `57abea025f62b20233ca281d58d2acbee4ab8b8e`. **Method:** read-only GitHub source/contract inspection and a static top-level function scan. **Engine specified by repository:** official Godot 4.8-beta2. No Godot run, physical-device test, benchmark, native build, full CI or replay was performed for this *planning* pass.

The [implementation plan](../../plans/vehicle-runtime-consolidation.md) is the authoritative step/status home (VRC-00…11, all proposed). This folder records why that plan is targeted rather than a rewrite:
- [SOURCE-INVENTORY.md](SOURCE-INVENTORY.md): named owners and actual current source sizes/function signatures;
- [inventory.json](inventory.json): machine-readable pinned file identity and counts;
- [MIGRATION-MATRIX.md](MIGRATION-MATRIX.md): what can safely share code, what must not, and candidate seams;
- [QUALITY-GATES.md](QUALITY-GATES.md): per-PR regression and performance verification, plus non-claims.

**Key source observations.** The existing kernel already separates model callbacks from integration; several vehicle sessions have similarly named lifecycle methods but different safety and checkpoint contracts. Fixed-wing `FlightSession` and the main shell/activity coordinators are large, yet a large file alone is not a confirmed defect. Aircraft v2 already has a single capability registry and shared loader. Existing session, controller and physics audit queues must be reconciled before a refactor is classified as corrective.

**Prior controls baseline:** [GCA audit at commit 895dd435](https://github.com/bultodepapas/OpenRCsimulator/blob/895dd4352c5191f1539a8b8f4df1996cd33eb86f/docs/research/game-controls-audit-2026-11-21/AUDIT.md) identified five bounded control findings; those remain external to this planning-only branch. The 22/27 checked existing-run results belong to that audit and were **not rerun** here. VRC does not claim to repair them.

**Owners read:** [AGENTS](../../../AGENTS.md), [STACK](../../STACK.md), [AIRCRAFT_CONTRACT](../../AIRCRAFT_CONTRACT.md), [AS plan](../../plans/aircraft-standardization.md), [FLIGHT-LOGGING](../../FLIGHT-LOGGING.md), [optimization priorities](../../plans/optimization-priorities.md), [consolidated audits](../../../external%20Audits/CONSOLIDATED-AUDITS.md), and existing [research/AS evidence](../aircraft-standardization/README.md). Shared code owners remain SF/physics, AS, D6/UI, BL, DR, HELI, GP/RCV, FL, PT/VQ/NK and rendering; VRC coordinates proposals but does not silently take ownership.

**Source limits:** Functions are counted only when the line begins with `func` or `static func`. Whitespace, class bodies, nested lambdas and semantic duplicate behavior are not measured. The matrices are code-review hypotheses requiring characterization, not refactored code or certified savings.
