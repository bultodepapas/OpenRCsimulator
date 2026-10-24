# VAL-AUD-2026-10-23 — Independent physics audit and FUEL-04-R1

2026-10-23. One bounded numerical correction is implemented: the reference mass
inventory no longer accepts a zero or empty inertia inverse after arithmetic
overflow, or calls the asserting inverse helper on singular/underflowed inputs.
This is an API numerical defect, not an explanation for ordinary flight behavior.
The reverse-flow aerodynamic finding below remains open. No aircraft coefficients,
generated data, golden flights or integration laws were changed.

## Scope and coordination

Base commit: `e76a72f5b25f1787564ec8c34056428fa2cafe5a`. Native engine:
`4.7.2.stable.official.ed1daf0bf`, fixed steps at 240 Hz. HEAD alone does not
identify this shared working tree. Existing lighting, Corsair and ground-physics
edits were preserved. Another session changed `simulation.gd`, `vehicle_model.gd`
and their contract tests during the audit; those changes are not this audit's work.

All eleven requested specialists used Luna Max, in waves of at most three.
Investigation/review agents had read-only source access and separate scratch
outputs. The lead alone edited the two correction files. The execution sequence
was architecture and independent audits, adversarial review, a failing reproduction,
implementation, then independent regression and evidence review.

| Specialist | Substantive contribution and disposition |
| --- | --- |
| Repo Cartographer | Traced input conditioning → actual servos → aircraft load evaluators → shared RK4 kernel, and identified existing flight/replay probes. No architectural defect asserted. |
| Physics Bug Hunter | Rejected a catalog low-speed propeller-force singularity: installed normal-force tables start at zero. Rejected missing transient propeller reaction in the coupled shaft route: propeller and rotor reaction terms already combine correctly. |
| Mathematical & Numerical Auditor | Reproduced huge/tiny reference-inertia failures. Found no actionable fixed-datum sign, stage moment-transfer, quaternion or RK4 defect in the reviewed paths. |
| Pure Physicist | Derived section-plane force passivity and the reverse-axial-flow fuselage-side extrapolation below. Did not claim total-airframe energy injection. |
| RC Flight Dynamics Expert | Confirmed the optional body-side term affects Extra/F4U and that existing aerobatic cards can reach reverse axial flow; separated documented stall/spin/wake limitations from coding defects. |
| Control Systems Specialist | Reviewed mapping, rates/expo, flap mixing and actual servo deflections; 94 checks passed. Transmitter hardware rate/expo settings are not reconstructed by log metadata, although conditioned commands replay. |
| Flight Test Pilot | Executed 15 existing card procedures on each of the MAX-55AX Stik and Extra. Reported actual maneuver failures and absent hover/torque-roll coverage. This was an automated pilot. |
| Deep Research Scout | Checked primary NASA sources on body-force applicability and full-angle modeling. A forward-flow gate is a possible domain limit, not a validated reverse-flow law. |
| Good Enemy | Required screening before raw inversion, scaled fallback and preservation of ordinary arithmetic; challenged immediate aerodynamic gating and supported a separate force-model investigation. |
| Regression Guardian | Independently passed seven suites / 325 checks and original diagonal reproductions; found the mixed-dynamic-range rejection limitation below. |
| Evidence Auditor | Verified the distinction between complete recordings, exact replay and candidate comparisons; rejected the missing-import baseline attempt. A suspected Stik identity mismatch was disproved: Jensen reference and MAX-55AX are distinct, explicitly named installations. |

## FUEL-04-R1: reference inertia inversion

Implementation: [mass_inventory.gd](../../../app/physics/mass_inventory.gd),
`evaluate_reference`; regression:
[test_fuel_mass_reference.gd](../../../app/tests/test_fuel_mass_reference.gd).

Previously, the evaluator called `RigidBody.inertia_inverse` before checking
positive definiteness. It then treated a finite inverse as sufficient:

- `diag(1e150, 2e150, 3e150)` has finite cofactors but an overflowing determinant.
  Evaluation returned `ok=true` with a zero inverse; `J*(J_inverse*e_x)=0`.
- Scaling that diagonal to `1e-150` underflowed its determinant to zero and logged
  a singular-tensor assertion. An ordinary singular tensor also reached the assertion.
- Large tensors with off-diagonal entries could produce a NaN determinant and an
  empty inverse after the assertion; the empty finiteness loop could accept it.
- A well-conditioned tensor scaled to `1e-105` exposed loss of relative precision
  from a subnormal determinant, even without complete underflow.

The correction screens the leading minor and determinant before raw inversion,
using the same determinant arithmetic as the helper. Ordinary normal-range cases
retain the original inverse arithmetic. Nonfinite, subnormal or invalid cases use
the existing scaled SPD inverse; failure returns `ok=false`. This reuses the
geometry inventory's numerical method rather than imposing aircraft-size limits.

The smallest normal binary64 value is expressed as `pow(2.0, -1022.0)`. A direct
probe found that this pinned engine parses the decimal literal
`2.2250738585072014e-308` as zero. The first correction attempt therefore failed;
the exact power-of-two expression and the complete regression pass are retained.

The regression checks `J*(J_inverse*e_i)=e_i` on all three axes for a
well-conditioned, nondiagonal physical tensor at six scales, including `1e±200`
and `1e-105`. It also checks clean rejection of singular/indefinite tensors and
unrepresentable inverses. Existing historical equality checks at six fuel levels
for three glow installations and the momentum/refinement experiment still pass.

**Conditioning limit:** `diag(1e200,1e200,1e-200)` is rejected by the existing
max-entry normalization, although its diagonal inverse is representable: the
smallest normalized entry underflows. Arbitrarily ill-conditioned tensors are not
qualified by this repair. Rejection is preferable to accepting an invalid inverse.

## Isolated flight comparison

The exploratory baseline contains 28 six-second Jensen reference Stik/Jet pulse
flights, all complete and finite. Only two were exact-replayed: Jensen normal
pitch-positive and Jet normal yaw-positive. This does not establish 28 exact replays.

For the actual correction comparison, an independent copy of the app was taken
before the mass edit. It included the concurrent kernel guards, held fixed for
both sides. The first recording attempt lacked imported scene resources; its
checked runner failed, and those recordings were excluded. After a clean import,
four six-second recordings completed: positive/negative pitch pulses on the
finite-fuel MAX-55AX Stik and Jet. Each was exact-replayed before the correction.
Only `app/physics/mass_inventory.gd` then changed in that isolated copy; a complete
tracked-file hash comparison verifies that boundary.

| Property | Result |
| --- | --- |
| Baseline solver fingerprint | `3fc1a2345a5c024e6b2dd232f0ad75ff62aa571a71d18c9d3ef0c6fff175c4b1` |
| Candidate solver fingerprint | `13b8d848df6df2cab646374c03a93f9651e240dfa634209ff77c7b52ff95df10` |
| Exact baseline replay | Four complete logs, 1,441 rows each; `solver_changed=false` |
| Candidate replay | Same aircraft files and command tapes; four complete logs, `solver_changed=true` |
| CSV comparison | No numerical divergence in exported channels on any of the four tapes |

Candidate comparison is not exact replay certification across changed sources,
and neither operation validates real-aircraft dynamics. Logs retain markers,
aircraft snapshots, live mass and internal states. The Jensen reference Stik in
the exploratory run is not the MAX-55AX installation in the correction comparison.

## Reverse-flow finding: retained, not repaired here

The Extra and F4U declare the optional body-side term in
[aero.gd](../../../app/physics/aero.gd):

```text
Fy = 0.5*rho*(S*CYbeta*u*v - A_cross*sqrt(v*v+w*w)*v)
```

`CYbeta` is negative and derived from forward-flight estimates. For `u<0`, the
first term gives positive lateral-axis power. The drag contribution is
`-0.5*rho*A_cross*sqrt(v*v+w*w)*v*v <= 0`. At V=20 m/s, alpha=179 degrees,
beta=5 degrees and rho=1.225 kg/m³, direct evaluation of these coefficients gives
approximately +1.69 W net for the Extra's isolated side-force contribution and
+8.48 W for the F4U's. These are component calculations, not total-airframe power:
the complete force/moment work budget was not evaluated.

The small-angle reduction `q*S*CYbeta*beta ≈ 0.5*rho*S*CYbeta*u*v` assumes forward
flow. Signed extrapolation through reverse axial flow lacks matching evidence.
Small lateral velocity remains small beta when u reverses because the air-data
denominator uses `sqrt(u*u+w*w)`. Existing body-side tests use forward flow; the
generic envelope tail-slide fixture uses the Stik without this optional term.

Primary context:

- [Allen and Perkins, NACA Report 1048](https://ntrs.nasa.gov/citations/19930090962):
  potential and viscous body-force contributions depend on the modeled regime.
- [Jorgensen, NASA TR R-474](https://ntrs.nasa.gov/citations/19770026166): high-angle
  body forces depend on geometry and separation; its Mach/angle ranges do not
  validate these RC aircraft.
- [NASA NDARC theory handbook, sections 8 and 10-3.3](https://rotorcraft.arc.nasa.gov/ndarc/media/Files/reportsAndPapers/Johnson%20TP-20220000355%20v1.pdf):
  explicit full-angle continuations and force-axis definitions provide a modeling
  precedent, not an RC calibration. Its reverse-sideslip treatment is not the same
  as alpha near 180 degrees with small beta.

The Scout supported `max(u,0)` as a conservative forward-flow applicability gate;
Good Enemy required a separate negative-u Extra fixture and complete work budget
before adopting a force change. The lead chose that bounded follow-up: keep the
current finding visible, do not tune coefficients or imply a validated reverse law.

## Scripted flight observations

Card `ft-card-v5`, MAX-55AX Stik and GP Extra 300S .60, calm air. Each completed
15/15 procedures without script errors: trim sweep, power-off/on stalls, Vmax,
roll rate, loop, knife-edge, inverted flight/holds, upright spins, takeoff,
landing, turning/held stalls and slow rolls. Procedure validity is distinct from
achieving a maneuver target.

| Model output | MAX-55AX Stik | Extra |
| --- | ---: | ---: |
| Maximum level speed | 38.92 m/s | 41.23 m/s |
| Power-off stall speed | 9.56 m/s | 11.05 m/s |
| Knife-edge target | Both full-throttle holds sustained; both 50% holds failed | All four holds failed |
| Upright spins | Entered and recovered in both directions | Entered and recovered in both directions |

Failed knife-edge intervals had full rudder saturation. These results are model
predictions, not grounds for arbitrary authority increases. Hover, harrier and
torque roll are absent from the harness. Crosswind, flapped landing, human pilot
acceptance and matched physical aircraft measurements were not tested.

Source files changed on disk during this card run. Launch/end/handoff hashes are
retained; these observations are not the isolated correction experiment above.

## Verification and retained evidence

The independent regression run passed seven programs, 325 checks, with no engine
diagnostics: fuel reference 49, mass inventory 65, glow flight physics 110,
dynamic contact 38, live fuel mass 13, contact boundary 12 and contact session 38.
Additional checked runs passed rates 41, servo 6, actuators 47, rigid body 15,
integrator 9 and rotor coupling 17. No target-hardware performance claim is made.

The canonical `app/test.sh` attempt was blocked before execution by WSL startup
error `Wsl/Service/CreateInstance/E_FAIL` (code 6, failure step 2), including a
simple retry. A clean LF Linux clone was prepared at
`/home/bulto/openrc-deep-audit-20261023`; the suite did not run. All 1,224 native
application scripts passed `--check-only`. The fuel-reference test changed after
its initial parse and passed a separate final parse and the 49-check execution.
Results and source hashes are recorded in [verification.json](verification.json).
This is not a full-suite pass.

The [compact manifest](manifest.json) binds the retained JSON reports and
regeneration scripts. Four exact/candidate replay pairs and their comparison
reports are retained under `fuel-exact/` and `fuel-candidate/` beside this report.
The complete evidence bundle is local generated output at
`tmp/deep-audit-2026-10-23/retained-bundle/evidence.zip`, not part of a fresh checkout.
Its SHA-256 is `818d0011ca257439df17ef2655a5002ac37dc36311168ce493f029e248901280`.
It preserves the four accepted baseline `.orfl` files, exact/candidate CSVs,
checked logs, failing probes, exact source bytes, and scripted-card traces.
The Evidence Auditor verified all 3,881 members against the full local manifest.
Rejected attempts are explicitly identified in `verification.json`; their logs
remain in the local bundle. The larger exploratory 28-log set remains in ignored
`tmp/deep-audit-2026-10-23/baseline-pulses/`; its summary and two exact replays are
also in the bundle. No images or full source archives are added to Git.

To reproduce the numerical regression, use the checked runner documented in
[TOOLS](../../TOOLS.md) on `res://tests/test_fuel_mass_reference.gd`. To repeat the
flight experiment in a disposable checkout:

1. Check out the named base commit and apply the retained
   [baseline source patch](../../../research/physics-audit-2026-10-23/baseline-source.patch).
   This restores the four concurrent app edits held constant in the experiment.
   For byte-identical historical source, overlay `baseline-sources/app/` from the
   local bundle; otherwise require the recorded baseline solver fingerprint before
   treating a new run as a reproduction of this source identity.
2. Import the app with the pinned engine. Run the
   [four-flight recorder](../../../research/physics-audit-2026-10-23/record_reference_pulses.gd)
   through the checked runner, using `--path <checkout>/app`, the recorder's
   absolute path as `--script`, and user arguments
   `--out=<output> --stik-baseline=res://data/aircraft/stik_glow_55ax_2t.json
   --jet-data=res://data/aircraft/sebart_avanti_s_a200.json`.
3. Exact-replay each baseline `.orfl` before changing source. Then replace only
   `app/physics/mass_inventory.gd` with the correction, candidate-replay the same
   recordings with the same aircraft JSON, export CSV and compare.

The regenerated recorder has corrected descriptive text for its four cases;
the original local recording script/report retained the parent recorder's broader
method description. Case lists and inputs, not that inherited description, define
actual coverage. Exact replay requires matching sources and engine;
[FLIGHT-LOGGING](../../FLIGHT-LOGGING.md) defines the replay/export commands.

Next priorities are the isolated reverse-flow force budget and applicability
decision, aircraft-matched stall/spin/knife-edge measurements, transmitter/pilot
acceptance, and completing the canonical suite on a working Linux environment.
