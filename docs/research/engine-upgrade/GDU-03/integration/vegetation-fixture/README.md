# GDU-03: current population fixture

2026-10-25. The full unit collection found a stale exact population count in
`test_landscape_vegetation.gd`: it expected seven moving people. Running the
same current scenery source/data on official 4.7.2 and 4.8-beta1 produces five
on both engines. Both retain five procedural motion nodes, no procedural crowns
or shrub tips, 24 population placements and identical reported geometry counts.
The diagnostic copy only adds failure details to the original assertion.

The expected count is now five, with actual motion/population counts in any
failure message. The assertion remains exact. All 38 existing vegetation
checks pass on 4.8, including source identities, damage hide/restore, tree
counts, repeatable geometry and per-subsystem triangle budgets. No production
scenery code, placement data or geometry changed.

[Verification](verification.json) binds the two original-failure diagnostics,
the corrected run and relevant source hashes. Their checked logs report no
engine errors or warnings; the two intentional historical failures remain
separate from positive evidence. Raw outputs are under
`D:/OpenRCsimulator-experiments/gdu03-vegetation/`. This is software fixture
consistency, not a rendered-image or performance comparison.
