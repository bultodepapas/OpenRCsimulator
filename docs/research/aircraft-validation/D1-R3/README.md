# D1-R3 — landing-gear support polygon

2026-10-07 · **Status: implemented and verified.** Scope: [D1-R3](../../../../ROADMAP.md#audit-repairs); prerequisite of E3b2 (runway start).

## Confirmed defect

Audit finding [physics B3](../../project-audit-2026-10-06/physics.md#b3--ground-setup-accepts-a-cg-inside-the-gear-bounding-box-even-when-it-is-outside-the-support-polygon): `AircraftData._landing_gear` accepted a CG whenever its x and y each lay between the contacts' extremes, which is a bounding-box test. On HEAD `89a082d` the [probe](probe.gd) still accepts the audit's layout: contacts (0, −0.18), (1, 0.18), (1, 0) with the Stik CG (0.1209, 0) outside the support triangle ([before](before.txt)). Current aircraft were never affected; the gap is in the validator.

## Physics of the check

Rigid gear at rest stands on a **lower facet** of its contacts' convex hull: a plane through three contacts with every other contact on or above it. Gravity then acts along that facet's normal. The airplane stands when the CG lies above the facet and its projection along the normal falls strictly inside the facet polygon. This judges a taildragger at its nose-up three-point attitude rather than in body axes. The P-51 rests 13.9° nose-up, and a CG ahead of its mains at that attitude noses over even if a body-axis test would accept it.

`AircraftData.ground_support(points, cg)` checks every lower facet and returns the best one: `supported`, `margin` (m from the CG projection to the nearest polygon edge, positive inside), `facet`, `tilt` and `height`. The margin uses the **hull edges of the whole coplanar facet**: a square layout with the CG at the centre has margin = half width, where a per-triangle test would see zero on both diagonals. Contacts within 1 mm of a facet plane count as on it, far below the 1–3 cm static sag. Contacts further out of plane are judged as rigid, which is conservative. The function is public so the E3b2 static solve can reuse it. The loader adds no derived model fields, so flights, traces and checkpoints are unchanged.

Any `landing_gear` section still means "the airplane stands on this". A retracted or in-flight-only gear configuration (Avanti, later) needs an explicit flag when a consumer exists; no speculative schema was added (Gate 2 policy).

## Proof

- [Probe after](after.txt): the audit layout is refused ("the CG projects 0.124 m outside the support polygon … cannot stand on its wheels"); the Stik and P-51 data still load.
- [`test_aircraft_data.gd`](../../../../app/tests/test_aircraft_data.gd): 81 checks, 0 failed. They cover:
  - the margin of both real aircraft against an independent side-view formula (Stik 0.0964 m to the main axle at 0.52° tilt; P-51 0.2538 m at 13.9°), with tilt exact to 1e-9;
  - the audit layout, collinear contacts and all wheels on one side;
  - a taildragger CG moved 0.30 m forward (nose-over);
  - a square facet with a centred CG (margin 0.2 m, all four contacts), the same facet with the CG 5 cm beyond an edge (−0.05 m), and a CG below the wheel plane.
- **Mutation checks** on scratch copies: always-supported fails 6 checks; per-triangle margins fail the square case; projecting along body z instead of the facet normal fails both side-view checks.
- **Full suite:** `app/test.sh` with its own `XDG_DATA_HOME` exits 0 (91 sections, 364 s), goldens unchanged ([summary](suite-summary.log)). All 16 960-tick flight fingerprints still match the Gate P `oracle-1` hashes.

The old "no contact on each side of the CG" message is replaced by the single support message; its test now expects "cannot stand".
