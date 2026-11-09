# 06 — Research, source reconciliation and verification notes

**Prepared:** 2026-11-09. This file separates source observations, executed software checks, economic research and proposed product decisions. The implementation plan and contracts are proposals. The retained logs establish only the explicitly stated test scope.

## 1. Exact source scope and later GitHub changes

The audit checkout is [commit f47d1dc6cccb141936407d0217eafdc465558190](https://github.com/bultodepapas/OpenRCsimulator/tree/f47d1dc6cccb141936407d0217eafdc465558190). During handoff preparation, GitHub `main` was observed at [f7b58bd830d4a5eb78901d00514ce1fc18286477](https://github.com/bultodepapas/OpenRCsimulator/tree/f7b58bd830d4a5eb78901d00514ce1fc18286477), nine commits ahead. The [complete comparison](https://github.com/bultodepapas/OpenRCsimulator/compare/f47d1dc6cccb141936407d0217eafdc465558190...f7b58bd830d4a5eb78901d00514ce1fc18286477) lists 217 changed paths. This count is below the comparison API's file cap; the recorded path list was not a truncated first page.

The handoff retained commit metadata, changed paths and relevant patches in [baseline_drift_review.json](data/baseline_drift_review.json). It also compared all 13 current `app/economy/*.gd` Git blob identities with the audit tree: all matched, as recorded in [current_economy_blob_ids.json](data/current_economy_blob_ids.json). The changed-path review found no changes to the economy runtime catalog, aircraft source files, crash-economics research sources, relevant economics tests, contact-event schema, hull contact, impact snapshot or gear-damage module. This establishes the reviewed source relationship, not a passing current-head integration run.

Two nearby files changed. `main.gd` gained SceneDetail graphics diagnostics and frame-time support; its reviewed economics integration was unchanged. `flight_session.gd` gained the observer air/wind function, shifting later line numbers without changing the reviewed cost/contact functions. The glow flight law and trace support also changed, so an old recorded flight or solver identity must not be transferred to the newer source by assumption. Other commits affected scenario cache source binding, Workshop trial presentation, native solver identity and visual quality. The newer repository guidance explicitly requires graphics options to preserve physics behavior and prioritizes actual 1080p hardware qualification.

All code line links in the detailed specifications deliberately target the audit commit. At implementation start, record the then-current branch, inspect drift again and follow its applicable instructions. Do not force a developer back to the old application merely to match an audit document. The historical reproducer needs the exact old revision; the implementation needs an explicitly chosen current base.

## 2. Existing documents and evidence worth reusing

The project already contains significant crash and economics work. Read it with the runtime open, because a plan, research note or isolated helper does not prove production integration.

| Existing repository location | Why the developer should read it | How to use it |
| --- | --- | --- |
| [docs/STACK.md](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/STACK.md) and [AIRCRAFT_CONTRACT.md](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/AIRCRAFT_CONTRACT.md) | Shared-kernel boundary, aircraft contract, stable identities and authoring rules | Constrain new contact/economics adapters; keep price decomposition outside physical mass accounting |
| [docs/CRASH-DAMAGE-PLAN.md](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/CRASH-DAMAGE-PLAN.md) | Existing crash-damage direction and accumulated work | Reconcile this handoff with the owning track and avoid duplicate plans |
| [docs/plans/crash-damage-economics.md](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/plans/crash-damage-economics.md) | Canonical economics plan | Incorporate accepted work packages using repository track IDs |
| [docs/plans/crash-realism.md](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/plans/crash-realism.md) | Adjacent crash and presentation scope | Keep visual work and financial authority separate while sharing accepted facts |
| [CR-39 investigation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/crash-damage-investigations/CR-39/README.md) | Existing hull/incident and reporting investigation | Read conclusions with the matching source and tests, not as current-head certification |
| [CR-36 electric pricing](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/crash-damage-investigations/CR-36d/electric.md) and adjacent CR-36/38 research | Existing component, fleet, service and price review | Extend dated observations and correct package scope; preserve history |
| [research/crash-economics](https://github.com/bultodepapas/OpenRCsimulator/tree/f47d1dc6cccb141936407d0217eafdc465558190/research/crash-economics) | Source price books, aircraft costing, recipes, generators and Python tests | This is the authoring route for generated runtime catalog changes |
| [docs/tools/README.md](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/tools/README.md), [tools/debug/README.md](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/debug/README.md), [FLIGHT-LOGGING.md](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/FLIGHT-LOGGING.md) | Checked execution, actual application control and replay evidence | Reuse these tools rather than writing another simulator-driving harness |

The audit's [source_index.json](evidence/source_index.json) retains further source IDs and the consolidated external-audit document location. It is a navigation aid; code descriptions in files 02 and 05 provide the tighter line-level references. Historical 720p screenshots do not establish the repository's primary 1080p qualification.

## 3. Why the current ranges become so wide

The most important problem is the combination of an incomplete production assessment with different kinds of uncertainty being reported together. At the baseline, modeled propeller strikes can force a propeller action; other mapped contacts predominantly open inspections. The isolated component/energy helpers are not a connected production damage law, and normal play does not produce the broader inspection/repair resolutions needed to narrow the bill. Terminal flight does not identify which individual parts actually failed. See [runtime call graph](02_RUNTIME_IMPLEMENTATION_SPEC.md#1-current-call-graph-and-real-boundaries) and the [ten retained probes](evidence/audit_probe_results.json).

Constructed current-behavior probes demonstrated these exact calculations:

| Probe | Observed baseline result | Interpretation |
| --- | --- | --- |
| Unassessed terminal Jensen incident | Low $0; high $1,331.34; total unknown | High is a complete-build replacement ceiling, not a prediction of this collision's losses |
| Same terminal assessment with one confirmed propeller | Low $5.39; high $1,331.34; total unknown | One known local purchase does not resolve the remaining terminal uncertainty |
| Fully resolved constructed Jensen prop-only assessment | $5.39 complete parts total | Calculator can produce a narrow result when supplied a complete resolution; this fixture is not the normal-play receipt producer |
| Extra with the same known $5.39 action | Known subtotal $5.39; total incomplete; high unknown | Whole-dossier missing data can block an otherwise isolated known local action |
| Terminal Jensen plus $5 already-incurred inspection, if that fee is sunk | Existing high still $1,331.34 | Under that explicit fee condition, replacement plus incurred inspection is $1,336.34; fee timing must be modeled |
| Lumber composite wing row | $115.95 known component amount | The row includes a bare-wing reference and four servo proxies, not proof all servos failed |

The full Jensen source estimate spans $827.34–$1,331.34 around a $994.33 nominal build, a $504 width. Its authored contributions are $170 airframe, $125 engine, $40 servos, $15 receiver battery, $4 fuel and $150 labor. These are existing source assumptions in the [aircraft costing book](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/research/crash-economics/aircraft-costing.json), not a statistical interval measured from crashes. The repair model should not inherit that entire width for every local incident.

The proposed remedy has three parts: resolve common game damage locally, determine whether the affected scope is complete, and price compatible repair/purchase alternatives. Keep source-price variation, alternative repair decisions and missing information as separate explanations. A modest known bill is preferable when justified; an unresolved bill stays unresolved when a relevant fact or price is truly missing. A cosmetic range cap would hide the problem.

## 4. Important new findings during handoff preparation

### Corsair variant and retail coverage conflict

The physical `wing_joiner` provenance says CARF plug-in wings with aluminium tubes, while economic research references the Navy folding-wing ARF 795000 and folding spares 791215/791216. The [physical source](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/data/aircraft/f4u_corsair_250.json#L896-L905) and [costing references](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/research/crash-economics/aircraft-costing.json#L1250-L1270) must be reconciled; neither proves the other wrong. Existing wing rows are unpriced, so this is an import/mapping blocker rather than evidence that players already received a wrong-wing bill.

The [manufacturer's regional list](https://carf-models.com/en/products/f4u-1d-corsair/id/301/region/5) distinguishes $754 folding-wing spares from $341 plug-in outer panels and an $812 center wing. These are different products and coverage boundaries. Do not turn them into a low/high range for one installed wing. Review outer/center sections, surfaces, joiners, hardware and geometry before attaching an exact price.

The historical research JSON is retained unchanged in `evidence/`. For prospective imports, use [price_observations_reviewed_2026-11-09.json](data/price_observations_reviewed_2026-11-09.json): P16/P17 are downgraded to unresolved-variant economic references and P22 to an unmatched alternate package. The correction log preserves previous labels and reasons. P01 already excludes the 55AX and FS-64V propellers, which have distinct authored products.

The final review also corrected P18–P21 and P24, for eight classification corrections in total. Corsair main-gear provenance names estimated Sierra Giant Scale assemblies, so a CARF retract or wheel set is not automatically the exact installed product; the tail reference lacks an exact SKU. A sold Corsair fuselage needs coverage mapping to the modeled front/rear groups. The specific A200 commercial ARF needs revision and delivered-package reconciliation. Prices and URLs are preserved; their evidence relationship is qualified. These corrections do not assert an existing incorrect charge for the currently unpriced gear rows.

### The normal game route is a necessary test boundary

At [main.gd's startup guard](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/main.gd#L1169-L1184), reporting requires a report-enabled, non-scripted run with neither capture nor trace mode. Therefore a successful scripted flight, trace or isolated calculator test can bypass the feature under review. AC-44 requires the actual owner, accepted contact, automatic assessment/resolution, revision, visible report and archive through normal play. Deliberately excluded routes remain useful negative controls.

### Schema and granularity are real implementation constraints

Catalog, contact and inspection v1 schemas reject unknown fields. Physical inventory IDs cannot be allocated twice across current catalog components. Partial inspection receipts already exist, but a full v1 inspection includes every economic row, even labor, and carries special total-loss semantics. These facts rule out an apparently easy implementation that duplicates one mass ID for several prices or silently adds new receipt keys. File 05 provides the companion/adaptation design. `SourceRef` is a proposed normalized reference name, not an existing native type found in this baseline.

### A passing gate must produce useful common-incident estimates

Independent review found a loophole in an earlier draft: a route could claim support while returning only unknowns. The final plan requires a route-by-common-incident-class coverage ledger, automatic production assessment, and prices or reviewed allowances for all essential affected groups before the all-airplanes label is removed. A priced propeller alone is insufficient when wings and gear remain unusable. The review also closed inconsistencies around sealed-event conflict detection, ordinary gear telemetry, optional timed aftermath, surplus packages and immutable historical prices. These are decisions in the handoff, not implemented fixes.

## 5. Pricing investigation and remaining research decisions

The handoff contains **27 reviewed prior observations, 17 additional or rechecked observations, and two unpriced research leads**. These are observation counts, not 44 unique installed parts or 44 approved imports. Their exact amounts, currency, sold units, package evidence, dates and blockers are in [file 04](04_FLEET_AND_PRICE_WORKBOOK.md) and its JSON companions. No purchase or destination checkout quote was made.

Useful additional evidence includes the distinct 55AX/FS-64V propellers; plug-in Corsair components; Moki's standard-engine accessories versus an electric-starter variant; and the [SebArt A200 price list](https://www.sebart.it/download/sebart-pricelist.pdf), which identifies component sets in EUR with a stated VAT basis. Current A200 revision, electric versus authored pneumatic retracts, and the correct P100RX pipe remain binding decisions. The [Electron combo](https://www.electron-retracts.com/product/avanti-s-sebart-combo/) starts at €806 excluding tax, with options affecting the result; it does not identify the authored pneumatic installation. The [Moki manufacturer](https://www.mokimotor.de/produkte/motoren/moki-250/) describes a standard engine with ignition and ring muffler, but that does not establish every item supplied in another vendor's box.

Use this ordered research queue during CC-10/11:

| Decision | Required evidence or accepted game policy | Completion consequence |
| --- | --- | --- |
| Corsair installed wing type and whole-wing purchase coverage | Aircraft owner resolves conflicting provenance; reviewed manufacturer part membership | Exact wing binding allowed only after resolution; otherwise a clearly scoped allowance/analogue is needed |
| Electric Stik servo and receiver identities | Installed-product evidence, or explicitly selected economic analogues | Prevent timing-reference text from becoming a fictitious installed SKU |
| P-51 airframe and gear | Defined modeled build/short-kit scope or reviewed class allowances | Complete a game price book without claiming an exact unidentified retail kit |
| A200 structure/retract/pipe revision | Dimensions, SKU/version, bundle content; A200-13 price if used exactly | Avoid mixing a different-size/revision kit or electric gear into pneumatic scope |
| Engine/turbine accessories | Sold-package membership, including ignition/ECU/pump/muffler/mount boundaries | Prevent duplicate accessory charges and unsupported survivor credits |
| Lumber and MoonRunner packages | Required-unit crosswalk and explicit unvalued surplus | Compare PNP versus individual parts as alternatives; never add both complete baskets |
| Repair labor and materials | Localized rate basis, authored task durations, eligibility and shared operations | Make labor meaningful and bounded without pretending one shop rate is universal |
| Fictional/obsolete parts | Source-based economic analogue or an explicit allowance with reviewer and rationale | Close common game coverage while preserving honest product identity |

A manufacturer's price establishes the price of its listed product, not the installed fit or a component's crash strength. Stock wording is an observation, not guaranteed delivery. Missing prices remain null in research; an approved game allowance is a separate authored value with its own provenance. Preserve native currencies and tax inclusions; a mixed-currency sum is invalid until a dated conversion policy applies. An offline USD-only game price book can avoid that conversion path in the first release while retaining the foreign evidence for research.

For labor, [Ray & Robin's service page](https://mainehobbies.com/services/) provides a $30/hour RC-shop example. Durations such as a ten-minute prop change or a thirty-minute foam-wing task remain authored test assumptions. They are not quoted repair times. Under those illustrative assumptions, $5.39 plus $5 labor is $10.39, and $59.99 plus $15 labor is $74.99. Included inspection/setup operations must not be added twice. JetCat's service-approval threshold is not a fixed crash fee; only applicable sourced service quotes or declared game allowances can support such a charge.

## 6. The 40 versus 500 km/h example

For the audited loaded Avanti mass of 11.438578 kg, `0.5 × mass × speed²` gives approximately 706.09 J at 40 km/h and 110,325.79 J at 500 km/h, a 156.25-fold difference. These calculations are retained in [audit_probe_results.json](evidence/audit_probe_results.json). They concern total translation, not energy absorbed by a turbine, receiver, wing or ground.

Use the example to motivate scenario sensitivity: a glancing wingtip encounter, a hard landing and a direct nose collision can have very different local exposure even at the same forward speed. Surface compliance, normal speed, contact region, rotation, mounting, separation, fire and recovery policy matter when represented. The game can deliberately choose convincing outcomes for well-defined scenarios. Neither this research nor software tests establish a universal 40 km/h survival rule, a 500 km/h all-destroyed threshold, or a probability that a particular receiver survives. Version the chosen game rules and test their boundaries.

## 7. What was executed, and what remains proposed

| Evidence | Result and scope |
| --- | --- |
| Original focused Godot audit | 12 existing scripts, 674 assertions; final successful logs retained; source manifest contained 217 byte-matched files |
| Original constructed audit probes | Ten checks matched current source behavior; several deliberately demonstrate faults or limitations |
| Original Python/generator observations | 67 Python tests and both catalog/runtime `--check` commands reported passing; their raw stdout was not separately retained |
| New portable reproduction | Fresh checked import, the same 12 scripts/674 assertions and ten probes passed at the pinned old commit; 14 checked reports report success |
| New source/data checks for reproduction | All 217 historical source hashes checked; 79 scripts selected; 114 JSON inputs plus translation, recipes and checked runner verified against pinned Git blobs; exact engine version and binary hash recorded |
| GitHub drift review | Nine commits, 217 changed paths, 13 unchanged economics blobs; a source comparison, not a current-head application test |
| Proposed acceptance matrix | 46 cases remain unexecuted target specifications; no release pass is implied |
| Full-app and real-world qualification | No new graphical flight, native hardware/performance qualification, complete checkpoint integration, quantitative crash calibration or cross-platform release certification was performed for this handoff |

The [portable reproducer](tools/reproduce_baseline.py) reconstructs a fresh isolated project from the developer's exact checkout. It excludes one hash-pinned runtime-only load from `AircraftCatalog.ground_start_support()` because that branch is not exercised by the economics fixtures; full flight remains outside the harness. It preserves source bytes and fails closed on errors. It refuses a wrong engine version and an already existing output directory. Its [selection](evidence/reproducer_verification/selection.json), [summary](evidence/reproducer_verification/summary.json), logs and checked reports are included. Repository setup still owns trusted acquisition and verification of the official Godot binary.

The delivered evidence omits the reproducer's generated checkout copies, imports/cache and isolated user profile. Those are reconstructible through the tool and the exact repository; retained manifests, checked logs, reports and probe output document the run. The original `recorded_economy_runner.py` is historical, path-specific evidence. Use the portable tool for repeat execution, and the full repository tooling for candidate acceptance.

## 8. How to keep improving without inflating scope

Treat source observations as dated evidence, game parameters as explicit decisions, and test results as candidate-specific execution. A new price observation should not change an old bill. A changed damage profile should not silently reinterpret an old incident. A new aircraft should enter through the same installed-component/profile/package contracts and expose missing support before release.

The highest-value next research is installation and package identity, followed by task eligibility/labor and comparison against independent RC repair experience where available. Large numerical sweeps over unsupported strength constants would add apparent precision without closing those gaps. Release an honestly scoped, deterministic and useful game model after its software gates pass; pursue physical-validation claims through separately designed evidence and holdouts.
