# OpenRC Simulator: collision and damage audit

**Date:** 17 November 2026, America/Bogota.
**Audited revision:** [`a7de9b35676d891bc2034cc344b910d9e1ef9c61`](https://github.com/bultodepapas/OpenRCsimulator/commit/a7de9b35676d891bc2034cc344b910d9e1ef9c61).
**Audit branch:** `audit/collision-damage-2026-11-17`.
**Deliverable:** source audit, reproducible counterexamples, verification record, and a staged improvement plan. This branch does not change application physics or re-record flight goldens.

**18 November continuation:** the [second code investigation](deep-dive-2026-11-18.md) adds **CR-AUD-16 through CR-AUD-20**, with five new executed probes covering delayed rotor reference frames, quad checkpoint consistency, mixed ground/scenery arbitration, persisted crash-pause metadata, and terminal quad obstacle aftermath. Its [verification](deep-dive-verification-2026-11-18.md) and [implementation plan](deep-dive-plan-2026-11-18.md) are separate from the original campaign below. The package now has twenty scoped records; the dated assessment and counts below remain the first investigation's record.

## Assessment

**The baseline has substantial collision infrastructure, but it is not ready to claim uniform collision behavior across the fleet or physically validated progressive fracture.** The most urgent gaps are inconsistent world composition and dropped nonterminal contact candidates. The visual aftermath also has independently reproducible coordinate, mass-property, shape-ownership, and clock inconsistencies. Existing plans already disclose several larger capability limits; this audit distinguishes those from newly demonstrated counterexamples.

The register contains **15 separately scoped records**: 13 functional/presentation findings at different evidence levels, one explicitly identified car-scenery capability gap, and one stale regression-test assertion. That count is not a claim of 15 end-to-end flown regressions. Each record states its source, reproduction or source-only basis, controls, consequence, correction, and acceptance gate. Read [verification](verification.md) before using a check count or a fixture result as a release claim.

The audit covers all **13 Home-selectable vehicle IDs**: eight fixed-wing aircraft, one helicopter, one quad, one blimp, and two cars. It also covers the three hidden technical fixed-wing configurations and the shared infrastructure they use. Coverage means source inventory and the documented selected checks; it does not mean every vehicle was flown through every scenario.

## Read the package

| Document | What it answers |
|---|---|
| [Findings](findings.md) | What is wrong, how it was established, what could disprove it, and what a correction must satisfy |
| [Fleet and scenarios](fleet-and-scenarios.md) | Which vehicles and response laws exist; wing brushes, 300 km/h inputs, prop strikes, belly landings, retracts, and recovery |
| [Caps and performance](caps-and-performance.md) | Limits, units, clipping versus refusal, collision coverage, friction/rebound, and target-hardware qualification |
| [Improvement plan](improvement-plan.md) | Priorities, ownership, dependencies, staged PRs, and measurable exit criteria |
| [Verification](verification.md) | Exact engine/source identities, executed suites and probes, failed/inconclusive attempts, reproduction commands, and limits |
| [References](references.md) | Primary technical sources, repository research, equations, and evidence boundaries |
| [Evidence manifest](evidence/manifest.json) | Machine-readable provenance, retained logs/reports, probe hashes, and execution classifications |
| [18 November deep dive](deep-dive-2026-11-18.md) | Five additional evidence-backed findings, adversarial review, and leads deliberately not promoted |
| [Continuation verification](deep-dive-verification-2026-11-18.md) | Five new probes, 163 checks, 23 desired-behavior failures, one passing 33-check existing control, and retained unsuccessful attempts |
| [Continuation plan](deep-dive-plan-2026-11-18.md) | Five focused implementation slices with ownership, regression gates, and remaining research |

## Findings that should drive the next work

**World and contact consistency.** The quad and blimp prepare dry terrain at a known enabled-lake interior. The helicopter's scenery adapter filters away a detected nonterminal fuselage candidate, although the shared response control can produce a finite changed state. Cars use their course walls without general shared scenery collision coverage. These are different issues: unify geometry identity, preserve supported contact response, and define explicit unsupported capabilities.

**Contact truth and physical state.** Cutting a glow engine prevents the prop-strike guard from observing an approximately 8,090 rpm coasting disc in the controlled ground-contact fixture. A flattened impact event can identify one probe while exporting another probe's crossing fraction. A cost record, cosmetic component damage, a terminal flight condition, and a real change in mass/control/aerodynamics must remain distinguishable.

**Visual aftermath correctness.** An impact supplied at 10 m produces effects at the 4 cm field datum. An asymmetric wreck launch uses the wrong velocity reference, and a controlled C3 split changes represented linear momentum without an external or scatter impulse. Scheduled parts temporarily leave the active collision representation, core boxes do not match attachment membership, scenery callback/provisioning paths differ, and effects consume time differently from the wreck. Kerosene effects also have a declared-versus-live fuel disagreement. These findings concern visual aftermath; none authorizes calling the shared float64 flight kernel a Godot rigid-body simulation.

**Verification integrity.** The selected existing-suite campaign ends with 52 of 53 suites passing. The remaining parked-aircraft assertion expects an obsolete 19 shelter proxies; current geometry intentionally uses 24, and a diagnostic rerun confirms the other predicates pass. This is a test-maintenance defect, not an observed duplicate floor. The new audit probes separately preserve their desired-behavior failures.

**Validation and performance.** Fixed budgets are useful stability measures, but they do not prove accuracy. The audit records whether a limit clips, omits, refuses, or only documents a domain. No GPU timing, 1080p visual qualification, material-strength calibration, native/reference parity campaign, or 300 km/h full-flight certification is claimed. Those are explicit gates in the plan.

## What the requested crash scenarios mean

A light wing brush should be evaluated from the actual contact point, local normal motion, effective mass, support geometry, and friction. The current interactive soft-hull path can continue through some brushes and belly slides; that behavior is not evidence of persistent structural damage or validated survival for every aircraft.

At **300 km/h = 83.33 m/s**, a head-on normal impact and a shallow graze are materially different inputs. With effective mass equal to whole-aircraft mass, the normal kinetic term is about **3,472 J/kg** for normal incidence, but about **1.06 J/kg** at one degree to a stationary flat surface. These are arithmetic illustrations, not a safe landing envelope. Tangential work, rotation, snagging, geometry gaps, and component construction can still matter. See the scenario matrix and its explicit domain gates.

An explosion is a separate energy-source decision. Severe impact alone does not establish fuel rupture, ignition, or battery failure. The current estimated hot/cold, fuel-kind, rupture, and LiPo paths should remain typed and testable. A believable animation is not a burn-rate or structural validation result.

For a gear-up landing, actual wheel extension and support geometry matter. A retract command does not establish wheel pose; a wing with no landing gear is a different case again. The current experimental physical gear-damage module is not a calibrated stock-flight installation. Future detached components must update mass properties and any affected aerodynamic, propulsion, and control behavior through an accepted state transition before the product can claim continued damaged-flight physics.

## Recommended execution order

1. Preserve the reproductions and agree a versioned contact/geometry identity contract.
2. Correct source-off prop observations, helicopter nonterminal contact handling, and lake context composition, with accepted-tick and reset/replay gates.
3. Define car scenery support and qualify family-specific swept geometry, including thin objects, high angular motion, and capacity limits.
4. Repair visual wreck mass/COM, shape ownership, scenery, terrain, clocks, and energy-source consistency in focused PRs.
5. Develop progressive physical damage as separately evidenced component research; qualify it before enabling it in stock flight.
6. Run the integrated platform, graphics, replay, performance, and physical-validation gates before expanding fidelity claims.

The [improvement plan](improvement-plan.md) turns this order into eight reviewable work slices. Its priority labels indicate recommended scheduling, not an allegation that every item is a release-blocking regression.

## Review discipline

The audit retains negative controls, known-good behavior, earlier fixes, and its own unsuccessful attempts. Missing sparse-checkout assets, a mistaken fixture ID, an incorrect probe expectation, and engine startup stalls belong in the audit's verification record; they are not application defects. Headless numerical checks and direct function fixtures support bounded claims. Independent measurements and rendered sessions must support broader ones.

This record is a dated assessment. Later application changes require re-running the affected evidence against their own revision. Implementation work should update the owning CR/GP/vehicle plans, while this baseline remains intact for comparison.
