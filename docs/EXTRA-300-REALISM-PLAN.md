# Extra 300S RC flight realism

2026-10-11 · Revision 2 · **Status: audit and bounded corrections complete; engine verification delivered with baseline-suite exceptions. Physical acceptance remains open.** Prefix: EX-. This scoped plan executes EX-06, EX-08 and EX-09 substeps from the [aircraft plan](EXTRA-300-PLAN.md), following the completed [aircraft contract](../AIRCRAFT_CONTRACT.md). Revision 1 established the scope and acceptance before code changes.

## Objective and ownership

Improve the Great Planes Extra 300S .60 GPMA0236 as a 64 in balsa RC aerobatic model. Audit all flight behavior: trim, controls, propulsion, conventional aerobatics, inverted flight, stall/spin, takeoff/landing, energy and lifecycle. Distinguish numerical verification from measured physical fidelity. Keep the experimental label; neither full-size Extra data nor modern 3D foam-model behavior is a substitute for this kit.

The lead owns this plan, `research/extra-300/ex06/`, `docs/research/extra-300-realism/`, the narrow EX-05 generator/data changes, an Extra installation/envelope test, the Extra-only dry/loaded balance assertion in `test_aircraft_catalog.gd`, and the matching propeller geometry parameter. Source geometry changes go through its compiler. Existing hinge names, input semantics and shared force equations stay stable. Ground, UI, weather, scenery and other-aircraft work remain with their owners. Active uncommitted main/UI/weather/scenery edits appeared during audit; preserve them. No external developer messaging endpoint is available: this is an ownership reservation, not an acknowledgement.

Bounded Luna/max tasks separately audit primary sources and implementation. The lead reviews their findings and integration. A frozen pre-change app plus source hashes provides the comparison baseline.

EX-08 integration follow-up: the full suite exposed `research/ground-contact/e5a/session.gd` still initializing only wash state after the GP wheel-state migration. Scope includes replacing that test fixture's initializer with the session's complete continuous-state initializer and rerunning its original contact/refinement thresholds. This is a research-fixture repair, not a ground-force change.

## Findings and selected corrections

| Boundary | Finding | Disposition |
| --- | --- | --- |
| Aircraft identity and geometry | EX-05 derives a tapered, symmetric-section, zero-dihedral airframe with its own control geometry, mass and derivatives | Preserve the independent Extra derivation; never substitute Stik handling constants |
| Engine installation | Visual geometry declares 2° right / 0.5° down thrust, while physics remains axial and uses an arbitrary point on that axial line | Enable the existing angled-thrust module, deriving the actual propeller hub and CG-relative arm from the visual thrust frame; verify force, torque and angular momentum signs |
| Balance condition | Manual p43 specifies empty-tank balance. The generator solves its virtual balancing mass with 0.146 kg of fuel already aboard, making the empty aircraft about 6.5 mm aft of the intended datum | Solve balance on the dry inventory, then add the same prescribed half-tank fuel; derive loaded CG, mass and inertia. No fuel-burn feature or measured-ballast claim. Expected virtual ballast 0.0873 → 0.1425 kg, loaded mass 3.3643 → 3.4195 kg, loaded CG about 6.14 mm forward of the dry target |
| Propeller appearance | Physics identifies a 12×6 Sport; mesh twist uses a provisional 12×8 | Use 12×6 pitch in the existing generated visual model; retain the explicitly borrowed 11×6 Ct/Cp proxy and its limits |
| Controls | High-rate mechanical throws follow manual dimensions; the manual recommends low rate for first flight and normal maneuvers | Audit both travel sets and their angular equivalents. Preserve mechanical maxima and avoid hidden transmitter expo/rate duplication |
| Aerodynamics | Derived attached-flow model is coherent but uses estimated CL limits, inertia distribution and drag; no identified low-Re airfoil polar | Test the complete envelope and sensitivity, without inventing measured targets or retuning coefficients to make maneuvers pass |
| Low-speed powered flight | No Extra-specific torque-balance engine, propwash or P-factor module | Record effects and residual failure of qualitative manual expectations; do not disguise missing mechanisms with rudder bias or force multipliers. Any next module needs its own data and acceptance |
| Ground behavior | Current GP wheel profiles already provide rotating unbraked wheels and terrain interaction; Extra has a fixed taildragger | Reuse and verify that interface; do not duplicate or retune the ground solver in this step |

Primary evidence: [source audit](research/extra-300-realism/EX-06/primary-sources.md), original Great Planes manual and plan, O.S. MAX-61FX specifications/propeller recommendations, and the existing EX-01 geometry/EX-05 derivation. The manual supplies qualitative handling guidance, not numeric stall speed, spin rate, Vne or structural limits.

## Steps and acceptance

| ID | Step | Proof | Status |
| --- | --- | --- | --- |
| EX-06a | Full aircraft audit and before-change snapshot | Reviewed sources/consumers, mass-condition calculation, baseline handling and metrics | Complete; [audit and evidence](research/extra-300-realism/README.md) |
| EX-06b | Correct balance condition and installed thrust frame; match propeller pitch | Regenerated v2 data/report/geometry; 17 installation checks; old-data negative control rejects 11; other aircraft byte-identical | Complete; [installation log](research/extra-300-realism/EX-06/after/installation.log) |
| EX-08a | Flight-envelope and lifecycle qualification | Existing 12 handling checks plus 24 airborne/7 ground cases at 240/480 Hz; checkpoint/reset and real-app trim; repaired E5a fixture passes 84 checks | Software evidence complete: 186/199 unit files and 27/27 downstream sections pass; 13 failures reproduce on baseline. Physical takeoff-yaw target unmet |
| EX-09a | Publish comparison and next physical gates | Before/after numeric changes and flight metrics; assumptions labeled; manual rate guide, remaining gaps and reproducible commands | Complete for this audit; [results and physical gates](research/extra-300-realism/README.md). Original EX-09 independent flight contrast remains open |

Acceptance is established before tuning: dry longitudinal CG within 1 µm of the plan target; loaded mass/CG independently satisfy component sums within 1e-6 SI; visual/physical unit shaft axes and hub positions agree within 1e-6; thrust/moment match independent `r × F − Q axis` at static and moving conditions within 1e-9 relative/absolute; no gear, flap, battery or fuel-consumption system is implicitly enabled. New axes must affect loads through the existing consumers and reset/replay must retain configuration identity.

For flight, require valid six-axis trim at the declared start, 30 s hands-off altitude within 1 m and speed within 0.2 m/s, finite airborne trajectories, both-direction control response, and existing loop/stall/spin thresholds without relaxed tests. Inverted and low-rate maneuver metrics are recorded as model predictions; use analytic gravity/load/sign checks instead of unmeasured pilot ratings. Keep all four aircraft contracts and unaffected-aircraft golden checks passing. Run the full app suite on an isolated source snapshot, with engine errors treated as failures; report any concurrent unrelated failure precisely. Validate generated outputs on Windows and Linux and from a clean copy. Measure relevant tick cost, without calling a busy workstation a target-machine qualification.

## Risks and explicit limits

Correct right/down thrust changes trim and throttle-to-yaw/pitch coupling. Without a calibrated propwash/P-factor model, correct right thrust alone cannot establish the manual's power-on left-turn behavior; record that limit explicitly. Empty-tank balance changes loaded mass/CG/inertia and corresponding derived terms intentionally. Virtual balancing mass remains bookkeeping, not an installation recommendation. Propeller tables, engine dynamics, ground coefficients and post-stall behavior still need aircraft-specific measurements and qualified pilot feedback. Do not widen a regression tolerance, change unrelated aircraft or add self-leveling to conceal a discrepancy.

## Acceptance disposition

The installation, mass-condition, finite-flight, original handling, generator, contract, replay and unchanged-aircraft gates pass. The [verification summary](research/extra-300-realism/EX-08/verification-summary.json) accounts for the complete suite, including a continuation after baseline failures, isolated UI repetition and the corrected E5a rerun. Thirteen unrelated baseline failures remain with their owning tracks; the suite is not green. All source and numerical evidence is in the [combined report](research/extra-300-realism/README.md).

Takeoff yaw fails the manual's qualitative expectation despite the verified shaft geometry. Gear forces, low-Re/post-stall aerodynamics and the installed engine/prop remain unmeasured. Ground probes do not qualify a product runway start, continuous circuit or stopping distance; aerobatic, crosswind, pilot and target-hardware acceptance remain open. No calibrated 3D-flight or overall physical-fidelity claim follows from completion of this audit.
