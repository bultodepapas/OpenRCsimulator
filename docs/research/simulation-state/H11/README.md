# H11 — landing-gear contact stability and accuracy

2026-10-07 · **Status: complete within the stated fixture limits; full suite and corrected 72-check contact probe pass.** Main-line step [H11](../../../../ROADMAP.md). Numerical verification only; this is not flight or landing-gear validation.

## Policy outcome

Keep the current 240 Hz integrator and existing loader admission rule unchanged. The H11 evidence supports a bounded Stik-family test envelope: 1.0–18.21 kg, 2–18.14 mm static-sag proxies, nominal contact damping ratios ζ = 0.2–0.7, and the same three-wheel tricycle layout scaled from the Ugly Stik. The largest coupled ratio that passed the switching-touchdown budget was ρ = ωmax/240 = 0.291798. The test's 0.30 label is a rounded screening ceiling; no result in the 0.2918–0.30 gap was measured. This is not an admission rule for other inertia tensors, damping, contact layouts, surfaces, or aircraft.

The current loader remains at its existing heave proxy limit ωheave·dt < 0.1. H11 does not loosen or replace that conservative data check. A coupled-mode value is only a local linear screen; acceptance comes from the switched-contact trajectory, energy and refinement checks below.

## Method

The probe uses the production `Ground.loads`, `Ground.compressions`, spring-energy calculation, `Simulation.step()` and RK4 path. For each contact subset it forms the upright three-coordinate stiffness matrix for heave, roll and pitch, `K = Σ ki JiᵀJi`, with `Ji = [1, yi, −xi]`. A vertical wheel force has no yaw torque, so the free yaw coordinate is eliminated from the full inertia tensor with the Schur complement `Ieff = Irp − [Ixz,Iyz]ᵀ[Ixz,Iyz]/Izz`; the remaining mass block includes effective Ixy. The probe whitens this heave/roll/pitch system, computes the largest symmetric eigenvalue, and reports `ωmax = √λmax`. All nonempty subsets are screened. A synthetic tensor with nonzero Ixy, Ixz and Iyz is checked against a closed-form full generalized eigenvalue. The mode frequency is diagnostic; it does not model the clipped damping or the discontinuity when a wheel makes or breaks contact.

For dynamic probes, tyre forces are disabled to isolate normal gear loads. Each touchdown starts 15 mm above the mean wheel plane with a scaled 0.35 m/s sink speed and runs for 1 s. Ring-down starts from a settled three-wheel state with 20% of static sag displacement plus a small roll/pitch perturbation and runs for 1 s. Results compare states sampled every 0.05 s at 240, 480 and 960 Hz. The 240/480 sampled-trajectory budget is Δposition ≤ 1 mm, Δvelocity ≤ 0.01 m/s, Δattitude ≤ 2 mrad and Δrate ≤ 0.02 rad/s. Per-tick mechanical energy gain must be ≤ 1e-9 J; this is a numerical tolerance, not an energy-conservation claim.

## Results

| Fixture | Mass | Static sag | Nominal ζ | Coupled ρ at 240 Hz | Ring-down h/h₂ error ratio | Touchdown Δx / Δv / Δθ / Δω at 240 vs 480 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Light, scaled Stik | 1.00 kg | 18.14 mm | 0.2 | 0.096900 | 16.11 | 0.157 mm / 0.00333 m/s / 0.0815 mrad / 0.00088 rad/s |
| Stik contact data | 2.89 kg | 18.14 mm | 0.4 | 0.096900 | 16.10 | 0.042 mm / 0.00092 m/s / 0.389 mrad / 0.00409 rad/s |
| Stik, stiffer | 2.89 kg | 10 mm | 0.4 | 0.130496 | 16.01 | 0.040 mm / 0.00092 m/s / 0.362 mrad / 0.00522 rad/s |
| Giant scaled Stik | 18.21 kg | 18.14 mm | 0.7 | 0.096900 | 16.31 | 0.249 mm / 0.00714 m/s / 1.069 mrad / 0.01484 rad/s |
| Giant, stiffer | 18.21 kg | 5 mm | 0.4 | 0.184549 | 16.44 | 0.172 mm / 0.00653 m/s / 0.647 mrad / 0.01547 rad/s |
| Stik, stiff edge | 2.89 kg | 2 mm | 0.4 | **0.291798** | 15.79 | 0.055 mm / 0.00111 m/s / 0.249 mrad / 0.00819 rad/s |

All six bounded fixtures passed the trajectory budget, switched twice during touchdown, and stayed below the 1e-9 J resolved-energy-gain tolerance. Smooth ring-down had no contact switches and showed h/h₂ error ratios 15.79–16.44, close to fourth-order refinement. NIST gives the classical RK4 one-step formula and its O(h⁵) local truncation term for sufficiently smooth solutions; that smooth-interval behavior does not extend across contact switching.

The 0.5 mm Stik-sag stress fixture is outside the tested envelope at ρ = 0.583596. Its ring-down settled on only two wheels and changed contact mode; its smooth-order ratio was 0.80. Touchdown switched contact 10 times. It still showed no resolved energy gain, but 240/480 errors were 0.287 mm, 0.02893 m/s, 2.497 mrad and 0.10165 rad/s; the velocity, attitude and rate exceed the declared budget. Halving the tick again to 960 Hz remained over budget for velocity and rate. This result rejects a 240 Hz accuracy claim for that fixture; it does not select a substep count or solver change.

## Current catalog coverage

The test loads every entry in `aircraft_catalog.gd`. Actual Stik data screens at 2.885 kg and ρ = 0.096900 across its seven nonempty contact subsets; its equal-mass-share damping estimates are about ζ = 0.401. Its tensor has Ixz = +0.0072395 and Iyz = +0.0004553 kg·m², so the free-yaw correction is negligible for this mode screen. The actual P-51 data screens at 21.50 kg and ρ = 0.095602, with the mains as the limiting subset and equal-mass-share damping estimates about ζ = 0.300. The P-51 tensor has Ixz = −0.269807 kg·m²; its mode ratio changes from 0.095494 when yaw coupling is incorrectly frozen to 0.095602 with the free-yaw reduction. These are mode screens only: this H11 run does not claim P-51 ring-down or touchdown accuracy. The Extra data has no active landing-gear contacts to screen. Avanti also has no gear contacts in its current gear-up, in-air configuration. Those absences are recorded rather than filled with assumed geometry.

## Reproduction and evidence

Run `$(app/get-godot.sh) --headless --path app --script res://tests/test_contact_policy.gd`. The [72-check targeted log](targeted.log) and [machine-readable measurements](verification.json) are saved beside this report. The check is included automatically by `app/test.sh`; the final full suite is owned by the main line.

This step changed no production physics. In particular, it does not alter [the loader's existing contact check](../../../../app/physics/aircraft_data.gd) or the [normal contact law](../../../../app/physics/ground_contact.gd).

## Sources and limits

- [Numerics architecture and performance investigation](../../roadmap-investigations/01-numerics-architecture-performance.md) and [ground handling and collisions investigation](../../roadmap-investigations/04-ground-handling-collisions.md): project hypotheses and E1 contact-law context.
- [NIST Digital Library of Mathematical Functions, §3.7(v), Runge–Kutta method](https://dlmf.nist.gov/3.7#v): standard fourth-order RK update and O(h⁵) one-step term under the stated smoothness condition.
- [Contact-policy probe](../../../../app/tests/test_contact_policy.gd): reproducible coupled-mode calculation, fixtures and dynamic assertions.

The scaled Stik cases are controlled numerical fixtures, not measured landing gear. The coupled eigenvalue calculation linearizes around upright contact and does not establish switched-contact stability by itself. Tire friction, sloped/rough fields, hull contacts, contact travel failure, model-specific P-51 dynamics and pilot acceptance remain outside this result.

Final integration evidence: [suite, scene/resource checks and source fingerprints](../H8/integration-verification.json).

Commit message: `H11: bound coupled contact policy; prove 72 checks with full-inertia modes and step refinement`
