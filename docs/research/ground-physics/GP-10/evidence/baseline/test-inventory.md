# GP-10 regression inventory

Read-only inspection against the baseline at `b85ce1047a3e7798ab22b330675fc0c9e4bce912`.
Only the focused two-aircraft flight-log helpers and retained ground recorder were
executed during capture. The unit scripts below were inspected, not run by this
baseline assignment; use the existing checked runner after integration.

| Existing test | Relevant preserved contract |
| --- | --- |
| `app/tests/test_ground_terrain.gd` | Empty-table flat fixture, malformed table/coordinate rejection, deterministic height/gradient, smooth rectangle edge, nested priority, renderer rectangle mapping and shader/CPU normal agreement. |
| `app/tests/test_ground_surfaces.gd` | Fail-closed material table, runway/rotorpad/mown/rough priority, exact inclusive boundary behavior and outside fallback, per-wheel material lookup, factors/friction hand values and nonpositive friction work. Contains short numerical coast/idle scenarios; it is not a performance benchmark. |
| `app/tests/test_field_surfaces.gd` | Field rectangle priority, shifted NED coordinates, shader capacity/array agreement and explicit rendering fallback. Relevant if the physical lookup changes shared surface ordering. |
| `app/tests/test_soft_contacts.gd` | Wingtip/belly continuation, terminal/depth rules, no airborne loads, dissipative friction, repeatability, same-tick contact cache invalidation and contact-law checkpoint identity. Its existing flat-ground assumptions require review when shared terrain changes hull geometry. |
| `app/tests/test_hull_crossing.gd` | Independent analytic crossing roots, lever arm, interpolation and session impact contracts. Preserve explicit interpolation evidence limitations. |
| `app/tests/test_aircraft_contact_session.gd` | Accepted hull lifecycle, detached receipts, restored IDs, unknown-ID rejection, reset priming and ended-contact deduplication. |
| `app/tests/test_lake_surface.gd` | One lake geometry definition for terrain, water and sweeps; stable identity. |
| `app/tests/test_lake_covered_sampling.gd` | Covered-query differential fixtures for terrain/hull/lake; inspect compatibility references before changing lookup paths. |
| `app/tests/test_lake_ground_contact.gd` | Wheel and lake-terrain integration. |
| `app/tests/test_checkpoint.gd` | Exact continuations, owner/configuration/layout rejection, including malformed ground surfaces. |
| `app/tests/test_checkpoint_integrity.gd` | Atomic failed restore and complete kernel rollback/cache preservation. |
| `app/tests/test_ground_stage_queries.gd` | Exact stage-local query-hoist regression, including wheel/lake layouts and a historical reference session. Do not silently update the reference to conceal an intentional geometry difference. |

New focused GP-10 cases should compare height, normal/gradient, material identity
and coefficients at the same NED query, including rectangle edges/overlaps,
flat explicit fixtures, malformed inputs, off-field fallback and lake edges.
Check detached query results and unchanged accepted state while observing.
If unifying hull geometry intentionally changes rough-ground contact, keep the
original tapes and report candidate divergence rather than rerecording baseline.
