# H6 — Centralized transcendental calls

2026-10-07 · **Status: complete; guard, mutation and full Phase H regression pass.** Main-line ROADMAP H6.

## Contract and change

Physics and simulation scripts route engine transcendental functions through `physics/math3d.gd`. The wrappers retain Godot's existing built-ins internally, so routing does not introduce a new approximation. The guard covers `sin`, `cos`, `tan`, inverse trigonometry, `sqrt`, `pow`, `log`, `exp`, and hyperbolic functions. It scans every GDScript file in `physics/` and `sim/`, masking comments and strings, with `math3d.gd` as the sole built-in boundary.

`app/test.sh` runs the guard and its mutation self-test. The self-test places a bare `sin(` in a temporary isolated source tree and requires rejection; it does not mutate the working project. H7 also compares each per-tick state/auxiliary/mode SHA-256 from the wrapper build with an isolated copy that replaces wrapper call sites by the same direct built-ins.

## Verification

[`guard.log`](guard.log) records the clean scan and rejected injection. [`H7 evidence`](../H7/verification.json) records identical per-tick replay fingerprints for all four air goldens.

```sh
python3 app/tests/check_transcendentals.py
python3 app/tests/check_transcendentals.py --self-test
app/test.sh
```

This verifies call routing and same-build behavior. It does not claim cross-platform bitwise identity or independently validate the flight model.

Sources: [math wrappers](../../../../app/physics/math3d.gd), [guard](../../../../app/tests/check_transcendentals.py), [test hook](../../../../app/test.sh), [numerics investigation](../../roadmap-investigations/01-numerics-architecture-performance.md). No external material used.

Final integration evidence: [suite, scene/resource checks and source fingerprints](../H8/integration-verification.json).

Commit message: `H6: route physics math through wrappers; prove guard injection rejection and unchanged replay hashes`
