# GP-12: integrated contact capacity

2026-10-26. The shared `AircraftGroundStep` now offers the explicit opt-in law
`fixed-hub-predicted-actual-capacity-budget-halfkicks-order1-v1`.
It extends the existing two-sided operator; it is not a second aircraft
integrator or a change to the stock flight-session selector. The whole split
remains first order. Fixed hubs, fixed axes, constant mass, static default plane
and source-free/capture-free owner admission remain its qualified domain here.

## Mechanics and ownership

The old half-kick law evaluates traction capacity at endpoint normal loads.
Near touchdown/unloading, a large change in normal load can therefore make the
two sides disagree substantially even when the smooth RK path is accurate.
The new operator predicts a normal-load quadrature, publishes a finite pre-kick,
re-evaluates the actual normal path after that kick, and reserves only a proven
remaining capacity for the post-kick. If the published pre-kick cannot fit the
actual whole-piece capacity, the entire attempt refines or refuses. It never
relabels excess impulse as numerical heat or changes the normal-force model.

For each wheel row, rate = (normal_first * Nmean) * normal_last; each ordinary
half limit is rate*h/2. The multiplication order preserves the authored
rolling-moment expression Crr*N*radius. The mean is a named algebraic RK
quadrature, not a measured load, a continuous integral proof or an impact peak.
Independent brake torque has a separate rate. Scalar and elliptical reservations
retain the original finite-precision publication contract and reject unsupported
arithmetic. Original QP, work, mass and complete-path error gates still apply.

The sealed Traction context builds current-pose ring geometry and stable rows
even when a wheel has zero normal load. Installed brake rows remain present at
zero command. Stable contact/row/group IDs, coefficients and mappings bind all
actual and predictor evaluations. Packet pose bytes and time are checked;
metadata alone cannot certify the trusted owner's source/configuration closure.
The first producer supports only the exact static default-plane provider.

The predictor budget is 124 direct RHS calls per attempted tick. Receipts
separate setup, attempted, accepted and discarded computational work from
physical work. Trial callbacks cannot publish damage/events. Owner-domain
refusal can trigger refinement; mutation/malformed data is fatal, including
when a different stage already signalled a domain refusal.

## Verification

The frozen prepromotion cohort passed 409 focused assertions (packet78,
producer78, old Step167, old Traction86) plus 40 trajectory assertions. The final
installed suites passed packet78, repaired producer103, Step167, Traction86,
Accuracy84 and Electric196: 714 assertions, zero failures and zero engine
diagnostics. The earlier installed producer78 run is retained as an intermediate
result. Repeated draft/installed counts are not independent additional scenarios.

Two synthetic P-51-mechanics drop tapes each completed 180/180 accepted ticks
at 240 Hz, with all 180 complete receipts retained. Both used at most16 pieces
and the original raw error/work/QP gates. The 0.25m/s case had maximum normalized
raw error0.245864 and mechanical balance -5.4173126500e-6J; the 1.2m/s case had
error0.146617 and balance +8.5675935679e-8J. Checkpoint178 continuation reproduced
the final checkpoint and full receipts exactly. Composition touchdown, unload
and renewed touchdown occurred; these are physics-fixture observations, not a
claim that all gameplay landing/statistics events were exercised.

Compression maxima (0.126961m and 0.151857m) belong to deliberately synthetic
compliance. They do not establish plausible P-51 gear travel, calibrated bounce,
heavy-aircraft failure thresholds or measured impact response. The tapes cover
0.75s each, not a whole flight or operational landing qualification.

After promotion, root found that inherited old/current imports in two permanent
producer checks resolved to the same installed scripts. The original frozen
prepromotion comparisons were valid; the permanent test required correction.
`oracle-followup/` retains the independently generated original row results,
the already frozen four original complete Step results, hostile mutation proof,
and the installed repaired-test receipt. The four old Step outcomes comprise two
accepted gentle states/receipts and two hard-case accuracy refusals; they are not
four accepted trajectories. Mutations exercise accepted receipts, refusal
reasons and legacy row forces separately. `installed/` is that final test/fixture
projection; `production/` preserves the original five-file promotion unchanged.

## Retained evidence and limits

`frozen/` contains70 import-retargeted scripts used by the long tapes.
`construction/manifest.json` binds their original and frozen identities plus
assets and the initial five payloads. `final-integration.json` supersedes its
earlier "long tapes not yet run" field. `trajectories/*.bin.gz` are lossless,
deterministic gzip wrappers around the complete Godot Variant buffers; their
uncompressed size/SHA are in `encoding.json`. Redundant multi-megabyte JSON
serializations remain in ignored tmp and are identified, not copied, here.
Construction scripts contain historical workspace paths; they are evidence of
the executed projection, not general user-facing reproduction tools.

The final manifest binds this folder; raw-byte attributes and a disposable Git
autocrlf clone check preserve it across checkout. The full application suite,
cross-platform determinism, real-time performance, stock/fleet activation,
moving/retractable mechanisms, finite-source events and physical calibration
remain separate gates. Shaft capture is explicitly refused by this law until
its stable row mapping is qualified. No stock coefficients or golden flights
were changed to obtain these results.
