# OpenRC Simulator: collision and damage audit

**Date:** 17 November 2026, America/Bogota.
**Audited revision:** [`a7de9b35676d891bc2034cc344b910d9e1ef9c61`](https://github.com/bultodepapas/OpenRCsimulator/commit/a7de9b35676d891bc2034cc344b910d9e1ef9c61).
**Audit branch:** `audit/collision-damage-2026-11-17`.
**Deliverable:** source audit, reproducible counterexamples, verification record, and a staged improvement plan. This branch does not change application physics or re-record flight goldens.

**Remediation — 20 November 2026:** the audit is now on main, and the [remediation ledger](remediation-2026-11-20.md) is the current status of every CR-AUD record and the improved, batch-ordered plan. Raw logs, reports and recordings stay at the audit commit (tag `audit/CR-AUD-2026-11-17-evidence`). The dated text below remains the audit record.

**Latest continuation — twenty game investigations, 20 November:** [two sequential rounds of ten](game-collision-studies-20-2026-11-20.md) inspect eighteen pinned public game sources and two first-party proprietary-game documentation sets, with the second round chosen from the first round's gaps. At application `48580b75a796fc6048fb77cdd69875c94ebb69e0`, the [109 source anchors](game-collision-sources-2026-11-20.json) and [provenance](game-collision-provenance-2026-11-20.json) support contact, fracture/support, material-effect, source-lifetime and cost experiments. [Crash plan §11](../../../plans/crash-realism.md#11-game-source-integration-two-rounds-of-ten--20-november-2026) integrates them into existing owners. These are twenty additional studies, not replacements for the earlier twenty. No runtime, game execution, new defect count, physical validation or measured optimization is claimed.

**Twenty research investigations, 19 November:** [collision, fracture, debris, particles, fire, smoke and sound inspiration](crash-inspiration-20-2026-11-19.md) compares 43 primary-source reference records with application `a866d880d8edbe84d2c59780624c35c8c7f107fc`. It adds twenty distinct proposals and gates, integrated into [crash plan §10](../../../plans/crash-realism.md#10-research-integration-twenty-investigations--19-november-2026) and the existing GP/CR/SM/AUD owners. The [source index](crash-inspiration-sources-2026-11-19.json) and [provenance](crash-inspiration-provenance-2026-11-19.json) separate literature, source inspection and proposed work. This is documentation-only research; it adds no new defect IDs, runtime tests, implemented physics, rendered captures or measured optimization.

**Nonfatal-contact continuation, 19 November:** the [near-miss, brush, scrape and water review](nonfatal-contact-review-2026-11-19.md) examines application revision `d736ee8a2eab0b59b0fa2c561a1eef07f5fae396`. It adds **CR-AUD-31 through CR-AUD-34** for conservative scenery padding, remaining-tick motion, terminal-only water policy and moving-interface normal-speed diagnostics. The [verification](nonfatal-contact-verification-2026-11-19.md) retains four probes and seven existing controls: **749 qualifying checks, 747 passes and two desired-behavior failures**, with zero checked engine diagnostics in those executions. Three resource-incomplete attempts are excluded. The two failures concern related geometry fixtures; passing policy characterizations do not certify physical correctness. The earlier 30-record register is not fully revalidated at this new revision. The requested behavior is integrated into [crash plan §9](../../../plans/crash-realism.md#9-recoverable-contact-and-near-misses--19-november-2026) and the existing GP/CR owners; no production force-law change or calibrated survival envelope is claimed.

**Earlier current-main continuation — 19 November:** the [realism and fleet review](current-review-2026-11-19.md) audits application revision `372053ac9448942e154801e3299cf77669161d08`. It reconciles all 27 prior records: **CR-AUD-15 is repaired**, while the other 26 retain their relevant defect/capability logic. It adds **CR-AUD-28 through CR-AUD-30** for non-scenery slope severity, quad severity from settled velocity, and false helicopter person attribution. That continuation contains **30 scoped records, 29 unresolved at that revision**. This includes capability gaps and bounded presentation fixtures, not 29 fully flown regressions. The [current verification](current-verification-2026-11-19.md) records **23 probes / 484 checks / 56 desired-behavior failures**, three passing existing controls totaling 122 checks, six excluded script attempts and the limits of the isolated exact-source component project. The dated baseline assessment and older counts below remain historical.

**18 November continuation:** the [second code investigation](deep-dive-2026-11-18.md) adds **CR-AUD-16 through CR-AUD-20**, with five new executed probes covering delayed rotor reference frames, quad checkpoint consistency, mixed ground/scenery arbitration, persisted crash-pause metadata, and terminal quad obstacle aftermath. Its [verification](deep-dive-verification-2026-11-18.md) and [implementation plan](deep-dive-plan-2026-11-18.md) are separate from the original campaign below. That continuation brought the package to twenty scoped records; the dated assessment and counts below remain the first investigation's record.

**18 November third investigation:** [energy, collision identity, and geometric boundaries](edge-cases-2026-11-18.md) adds **CR-AUD-21 through CR-AUD-24**. Four final probes contain **73 checks, 67 passes and six desired-behavior failures**, with zero checked engine diagnostics. The new records concern quad prop-contact passivity, airship recording identity, a submicron hard-capsule entry, and a small powered-prop rim penetration on a dry bank. The [plan](edge-case-plan-2026-11-18.md) and [verification](edge-case-verification-2026-11-18.md) state their different evidence boundaries. That investigation brought the package to **24 scoped records**, including the earlier capability gaps and stale test assertion; this is not a count of 24 end-to-end flown regressions.

**18 November fourth investigation:** [contact geometry and damage localization](contact-ownership-2026-11-18.md) adds **CR-AUD-25 through CR-AUD-27**: quad prop response across a finite-box gap and contact masking by a separated nearer box; car body-region damage selected by sideways velocity despite a front-only probe hit; and a bounded deployed-wheel/scenery capability gap. Three final probes contain **65 checks, 58 passes and seven desired-behavior failures**, with zero checked engine diagnostics. The [plan](contact-ownership-plan-2026-11-18.md) separates geometric admission, damage ownership and wheel-obstacle response; the [verification record](contact-ownership-verification-2026-11-18.md) retains exact scripts, controls, the excluded parse error and a separately derived terrain projection. There are now **27 scoped records**. The fourth pass includes direct-transition, accepted-tick and capability evidence; it does not establish uniform fleet-wide crash validation.

## Original 17 November assessment

**The baseline has substantial collision infrastructure, but it is not ready to claim uniform collision behavior across the fleet or physically validated progressive fracture.** The most urgent gaps are inconsistent world composition and dropped nonterminal contact candidates. The visual aftermath also has independently reproducible coordinate, mass-property, shape-ownership, and clock inconsistencies. Existing plans already disclose several larger capability limits; this audit distinguishes those from newly demonstrated counterexamples.

The register contains **15 separately scoped records**: 13 functional/presentation findings at different evidence levels, one explicitly identified car-scenery capability gap, and one stale regression-test assertion. That count is not a claim of 15 end-to-end flown regressions. Each record states its source, reproduction or source-only basis, controls, consequence, correction, and acceptance gate. Read [verification](verification.md) before using a check count or a fixture result as a release claim.

The audit covers all **13 Home-selectable vehicle IDs**: eight fixed-wing aircraft, one helicopter, one quad, one blimp, and two cars. It also covers the three hidden technical fixed-wing configurations and the shared infrastructure they use. Coverage means source inventory and the documented selected checks; it does not mean every vehicle was flown through every scenario.

## Read the package

| Document | What it answers |
|---|---|
| [Twenty game studies — 20 November](game-collision-studies-20-2026-11-20.md) | Adaptive 10+10 selection, game-code/documentation evidence, accepted/rejected transfers and one proposed experiment per game |
| [Game source index](game-collision-sources-2026-11-20.json) / [provenance](game-collision-provenance-2026-11-20.json) | Twenty identities, 109 source anchors, exact pins/blobs, sequential selection, application comparison, review corrections and documentation checks |
| [Twenty research investigations — 19 November](crash-inspiration-20-2026-11-19.md) | Twenty source-backed ideas, current-code reuse, proposed deltas, cost tradeoffs, existing owners and future acceptance cards |
| [Research source index](crash-inspiration-sources-2026-11-19.json) / [provenance](crash-inspiration-provenance-2026-11-19.json) | 43 primary-source reference records, scope limits, application/source identities and documentation-only verification |
| [Nonfatal contact review — 19 November](nonfatal-contact-review-2026-11-19.md) | Near miss versus contact, wingtip/prop/water branches, 300 km/h arithmetic, four scoped records and integration with current physics/feedback/damage owners |
| [Nonfatal contact verification](nonfatal-contact-verification-2026-11-19.md) | Eleven qualifying executions, precise direct/accepted-path limits, excluded resource attempts and portable reproduction |
| [Round-six evidence manifest](evidence/round6/manifest.json) | Pinned source/resource/probe hashes, raw logs/reports, classifications and counts for the focused nonfatal pass |
| [Current-main review — 19 November](current-review-2026-11-19.md) | Current fleet/object coverage, reconciled findings, three new defects, realism priorities and performance gates |
| [Current-main verification](current-verification-2026-11-19.md) | Exact source/engine, 26 qualifying executions, excluded attempts, recordings and portable reproduction commands |
| [Round-five evidence manifest](evidence/round5/manifest.json) | Per-run classifications, assertion totals, checked diagnostics, script/file hashes and exact log paths |
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
| [Third investigation](edge-cases-2026-11-18.md) | Four additional findings with numerical measurements, controls, source anchors and scope limits |
| [Third-investigation plan](edge-case-plan-2026-11-18.md) | Coupled contact energy, atomic recording boundaries, geometry tolerances and disc/terrain coverage |
| [Third-investigation verification](edge-case-verification-2026-11-18.md) | Four final probes, three real recordings, four retained earlier revisions and exact reproduction instructions |
| [Fourth investigation](contact-ownership-2026-11-18.md) | Three additional findings covering finite prop geometry, car damage localization and wheel/scenery ownership |
| [Fourth-investigation plan](contact-ownership-plan-2026-11-18.md) | Three correction slices with contact identity, damage mapping, wheel response and qualification gates |
| [Fourth-investigation verification](contact-ownership-verification-2026-11-18.md) | Three final probes, 65 checks, one excluded parse failure and a separately derived gear-support witness |

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
