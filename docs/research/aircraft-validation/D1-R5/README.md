# D1-R5 — Wing-strip calibration acceptance

**Status:** implementation and focused verification complete; full integration run pending, 2026-10-08.
**Owner:** Codex induced-calibration integrity agent. **Scope:** loader acceptance only.

## Defect and repair

The loader solves the section slope `a0` in `[0.1, 50] /rad` so that
`a0 × mean_row_sum(E) = CLa − (S_tail / S_wing) × a_tail`, with
`E = (I + a0 K)⁻¹`. A finite iteration count or rounded midpoint does not prove
that equation has been satisfied. Previously, an unreachable target silently
returned a boundary model.

Reproduction: in an in-memory Stik input, set horizontal area to 0.4 m² and
slope to 6.3/rad (both individually allowed). The old loader accepts a target of
−0.8450131858/rad while producing +0.0992258266/rad: residual 0.9442390124/rad.
Setting horizontal area equal to wing area and slope to the aircraft's 4.58/rad
makes the target exactly zero; the old loader accepts nonfinite derived downwash.
These are synthetic invalid configurations, not proposed aircraft parameters.

`_induced_map` now returns failure for a nonfinite/nonpositive target, a nonfinite
final map, or a final slope residual above `1e-10 × max(1, |target|)` /rad. It also
checks offsets before publishing derived fields. The loader reports the calibration
failure and returns an empty model. Existing session rejection preserves the prior
flight. The tolerance is numerical acceptance, not aerodynamic uncertainty.

Valid solve arithmetic, the DATA-2b midpoint optimization, input data and force laws
are preserved. No endpoint inversions or per-tick work are added. This verifies the
existing calibration contract; it does not independently validate lift or damping.

## Proof

- [Before](before.log): the new 115-check regression has **34 failures** against
  the old loader. [After](after.log): **115 checks pass**, including negative,
  zero, too-small and upper-unreachable targets, nonfinite targets, constructed
  roots at both supported bounds for all four aircraft, lift offsets including
  twist, and invalid initial/reloaded aircraft.
- [Verification](verification.json): **96 complete fleet load pairs are byte
  identical**, including diagnostics and input identity. [Paired samples](pairs.log)
  were collected during the integration suite and are not a performance benchmark.
- [NaN](nan.log), [infinity](infinity.log) and [finite wrong map](finite_wrong_map.log)
  injections produce **12/12 empty-model refusals**. [Removing residual acceptance](missing_residual.log)
  permits four wrong maps and makes the verifier fail as expected. Faults run only
  in temporary loader copies.
- [Fleet](fleet.log): all **16 fingerprints** match the G2-R1 snapshot: steady RPM
  grids, level/glide trims and 240-tick flight endpoints for four aircraft.
- Read-only numerical review found no blocking issue. The final residual gate is
  sufficient for this fixed-geometry calibration; generic inverse hardening is
  outside this change.

## Reproduction

Run `app/test.sh` and the [verification tool](../../../../research/aircraft-data/d1-r5/README.md).
For this exact loader revision, reconstruct the prior snapshot without modifying
shared source:

```sh
patch --reverse --output /tmp/d1-r5-baseline.gd app/physics/aircraft_data.gd \
  < docs/research/aircraft-validation/D1-R5/change.patch
python3 research/aircraft-data/d1-r5/verify.py \
  --baseline /tmp/d1-r5-baseline.gd --output /tmp/d1-r5-new-proof
```

[Patch](change.patch) and [source hashes](verification.json) identify this dated
comparison; later loader changes require the matching revision.

Suggested commit message after integration passes:

```text
fix(physics): reject unsatisfied wing-strip calibration (D1-R5)

Proof: 115 regression checks; 96 exact fleet pairs; 12 solver-fault refusals;
residual negative control; 16 unchanged flight fingerprints; full app suite.
```
