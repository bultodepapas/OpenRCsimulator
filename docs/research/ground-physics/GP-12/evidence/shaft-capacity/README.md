# GP-12: stable shaft capacity

2026-10-26. The installed `ContactCapacity.capture_mapping` pairs the legacy
local bearing ordinal with an explicit `{rotor_index,row_id}` interval mapping.
Both must identify the same finite independent +e_sigma row, zero bias, one
scalar group, identical rate and declared nonnegative rotor. Step pins that
semantic identity through actual/predictor snapshots and resolves the current
ordinal only at the existing common impulse solve. Old missing-mapping paths
and their receipt keys remain unchanged.

`AircraftGroundElectric.prepare_capacity/evaluate_capacity` binds actual
prepared source/mechanics bytes and the sealed wheel context. One original
source/aero/prop/wash/common-stage evaluation supplies the bearing rate; one
shaft row is appended to the interval packet. All original sample fields stay
unchanged. No second shaft integrator, bearing force, battery event or ESC
supervision is introduced. Stock sessions do not select this operator.

## Installed checks

The focused suite passes141 assertions. Existing packet78, Step167, traction
producer103 and Electric196 suites also pass:685 installed assertions, zero
failures and zero engine diagnostics. The earlier detached489 and repeated
main-project141 are separate executions, not extra unique coverage.

The immutable original oracle contains complete source-evaluator outputs and
two old-law advances: Lie accepts; two-sided refuses its raw accuracy gate.
A deliberate +1N force mutation changed both aliases but still triggered16
frozen-output mismatches. The fixture is never regenerated from the candidate.

The actual common VehicleModel/Simulation fixture uses synthetic fixed supports,
the existing synthetic Stik electric motor/propeller, a far-separated static
plane and zero gravity. Motor-off +0.01RPM captures, closes the mechanical/work/
heat ledger and continues exactly from checkpoint. This is a narrow numerical
capture proof, not powered startup or an operational aircraft qualification.

## Powered startup remains refused

At240Hz the unchanged raw complete-path gate under16 pieces rejects powered
startup, with no accepted state/event publication. The diagnostic8/16 paths in
`buffers/mechanism.bin` retain the reason. Independent bearing reservation
(dependency−1, proof code3) keeps only the original post half-capacity even when
the at-rest pre-kick spends zero impulse. This is separate from the normal-group
contained branch, which can also leave unused capacity.

Bearing capacity is0.0143239448782706Nm. At duty0.004, electromagnetic drive is
0.00883309934160019Nm, below the estimated static threshold duty0.00648648649.
Nevertheless diagnostic endpoint RPM is0.01661338925/0.008327230011 for8/16;
shaft difference0.0008677245662rad/s exceeds its0.0001000173975rad/s bound
(score8.6757363). Work/heat differences are about8.5e-8J and the energy residual
is near roundoff. Good work closure does not prove correct static holding.
Duty0.02 yields raw score35.9912600; duty1 yields18.3812297. No budget recovery,
coefficient change, tolerance relaxation or startup-success claim occurs here.

A separately versioned recovery rule requires its own finite group-membership,
full path/source-work and trajectory proof. Existing reservation laws are intact.
Finite battery boundaries, moving mechanisms, stock activation, physical
calibration and runtime performance remain separate gates.

## Evidence scope

`source/` contains the five installed payloads; `before/` preserves three prior
runtime files. Checked receipts include rejected early development and missing-
font startup runs. Main-project checks subsequently pass after normal import
repair, documented in the sibling `fixed-brake-import` cohort. The temporary
math-only project deliberately omitted presentation autoloads; its source
identity inventory is retained, not misrepresented as main-project verification.
Selected snapshots do not form a complete repository closure. Historical
construction scripts contain workspace paths. Raw-byte attributes and a
disposable Git autocrlf clone preserve every manifest-bound payload.
