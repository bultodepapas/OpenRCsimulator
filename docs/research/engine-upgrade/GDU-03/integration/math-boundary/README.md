# GDU-03: minimum-normal constant at the math boundary

2026-10-25. The H6 guard found a pre-existing direct transcendental call in
`physics/mass_inventory.gd`: its minimum-normal constant used
`pow(2.0, -1022.0)` outside `physics/math3d.gd`, the sole physics math boundary.

The expression and explanatory decimal-parser comment now live in Math3D;
MassInventory aliases `M.MIN_NORMAL_FLOAT64`. The power expression, threshold
comparisons, inverse arithmetic and physical-tensor acceptance remain unchanged.
No decimal substitution, guard exception or app test-file addition was made.

| Focused existing check, official 4.8-beta1 | Result |
| --- | --- |
| H6 on the preserved pre-fix frozen app | Rejects the original bare `pow` |
| H6 on final root | Pass |
| H6 isolated direct-call injection self-test | Rejects the injected call |
| Math3D test with four external constant checks | 24 checks pass |
| Mass-inventory geometry/validation | 65 checks pass |
| Fixed-datum fuel-mass reference, including extreme-scale inverse cases | 49 checks pass |
| Live fuel mass | 13 checks pass |

The same 24 Math3D/constant checks also pass on official 4.7.2 in its isolated
research project. All five focused Godot invocations report zero errors or
warnings. A disposable
copy of the existing Math3D test compares the constant, its inventory alias and
the original expression against the independent IEEE-754 binary64 pattern
`0x0010000000000000` (little-endian bytes `0000000000001000`). It also checks
that the value exceeds the independently decoded largest positive subnormal.
The existing mass/reference tests retain scaled SPD and overflow/underflow
inverse boundaries. No application test assertions changed.

[Verification](verification.json) retains exact source/test hashes, commands,
completion lines and the independent byte fixture. Raw scripts/logs remain at
`D:/OpenRCsimulator-experiments/gdu03-math-boundary/`. The separate final-source
numerical follow-up uses the unchanged GDU-04 runner and fresh isolated engine
caches. These focused checks alone do not establish whole-suite, package,
performance or physical qualification.

The [final-core numerical follow-up](../../numerical/final-core/README.md)
passes on both official engines, with all 28 streams unchanged from both
original engine outputs.
