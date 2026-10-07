# H9 — Replay tolerance and recording policy

2026-10-06 · **Status: complete; 42 focused checks, legacy replay and full Phase H regression pass.** Main-line ROADMAP H9.

`app/tests/replay_policy.gd` defines fixed comparison budgets. Engineering scales make reported normalized error meaningful; acceptance uses the listed absolute limits. These are numerical regression budgets, not flight-model uncertainty bands.

| Component | Unit | Scale | Absolute tolerance |
| --- | --- | --- | --- |
| Position | m | 1 | 1e-6 |
| Body velocity | m/s | 1 | 1e-6 |
| Quaternion component | unitless | 1 | 1e-9 |
| Body rate | rad/s | 1 | 1e-6 |
| Shaft / turbine speed | rpm | 10,000 | 1e-5 |
| Servo position | normalized command | 1 | 1e-9 |
| Engine mode, tick and timestep | discrete | — | exact |

Body limits preserve existing v1 acceptance. Auxiliary limits are selected numerical budgets: 1e-5 rpm is 1e-9 of the 10,000 rpm scale; 1e-9 servo command matches the attitude budget's relative order. They exceed observed local serialization error by several orders while detecting deliberate component mutations. They are not derived from real-world sensor resolution. Revisit them only with measured cross-platform error and physical/numerical justification; never loosen them to hide a model change.

New `openrc-golden v1` recordings carry additive policy, platform/build stamp, auxiliary checkpoints and mode checkpoints. The stamp names OS, architecture, CPU, complete Godot version/hash, source commit/dirty describe or exported build identity, and tick rate. Existing files remain readable and are not re-recorded for this behavior-preserving work. Their absent metadata remains explicitly legacy/unknown rather than receiving an invented historical stamp.

Readers validate finite numeric rows and strictly increasing integer checkpoint ticks, reject partial metadata extensions, and require initial/final checkpoints. A recorded tolerance is descriptive: changing it cannot override the code's accepted budget. Exact mode comparison converts already-validated JSON integer-valued numbers to integers; Godot's Array comparison otherwise distinguishes JSON float elements from int64 modes.

Reference CI: `.github/workflows/ci.yml` runs `app/test.sh` on Ubuntu 24.04 x86_64 with the pinned Godot. Other platforms use these same budgets but currently produce manual/non-gating evidence until an actual CI job is added. The stamp records where a result was produced; it does not claim unrun Windows/macOS comparisons. Same-build binary fingerprints are diagnostics for behavior-preserving refactors, not portable lockstep guarantees. [H8](../H8/README.md) covers exact full-state checkpoint replay; [H7](../H7/README.md) measures sensitivity to adjacent transcendental results.

## Proof

`test_replay_policy.gd` passes 42 checks: half-budget values accepted, twice-budget and nonfinite values rejected for each component; stamped JSON round trip; each body/aux component mutation; discrete mismatch; incomplete extension; immutable acceptance budgets; timestep-stamp mismatch/type rejection; and legacy v1 replay. The round-trip body differences were ≤3.56e-15 m, ≤1.78e-15 m/s, ≤5.56e-17 quaternion component and ≤2.23e-16 rad/s on this host.

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_replay_policy.gd
$(app/get-godot.sh) --headless --path app --script res://tests/test_golden.gd
```

Sources: [policy](../../../../app/tests/replay_policy.gd), [golden reader/recorder](../../../../app/tests/golden_flights.gd), [mutations](../../../../app/tests/test_replay_policy.gd), [CI](../../../../.github/workflows/ci.yml). Original repository MIT work; no external material copied.

Commit message: `H9: stamp golden records and enforce component budgets; prove 42 checks and legacy replay`

Final integration evidence: [suite, scene/resource checks and source fingerprints](../H8/integration-verification.json).
