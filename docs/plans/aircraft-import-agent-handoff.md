# Aircraft import: next-agent handoff

**Original baseline audited:** `2a3cf04dbbdaf486b9c9c8e983463d828f90c64a`.
**Follow-up production baseline:** `08f948265d40d83fbb4726a302b9e1c9490ccfce`, incorporated into this branch; original `.gd` and `app/data/` contents unchanged.
**Audit branch:** `audit/aircraft-import-closeout-2026-11-17`.
**Task:** finish the player journey from downloaded source aircraft to a supported, saved, restartable flight. This handoff is navigation and work discipline; the [closeout plan](aircraft-import-closeout.md) owns sequence/acceptance, and existing AC/AC-CV plans retain step IDs, shared ownership and broader gates.

## Read in this order

1. Root `AGENTS.md`, repository tool/admission guidance and current `git status`.
2. [Closeout plan](aircraft-import-closeout.md), especially the product contract, Phase 0A/0B and your next phase.
3. [Implementation guide](aircraft-import-implementation.md) for your phase's concrete seams, proposed pseudocode and test recipes.
4. [Dated audit](../research/aircraft-creator/import-closeout-2026-11-17/README.md), [original verification](../research/aircraft-creator/import-closeout-2026-11-17/verification.md) and [follow-up observations](../research/aircraft-creator/import-closeout-2026-11-17/followup-02/README.md). Preserve their separate source/run identities.
5. Current code at your work boundary. Compare later main changes to the follow-up SHA; carry new evidence forward without claiming old checks tested newer code.

## Start with this packet

**AC-CV-00 / Phase 0A:** complete one candidate's field-by-field semantic/dependency table and decide the smallest capability/data prerequisite. The [26-model lexical ledger](../research/aircraft-creator/import-closeout-2026-11-17/followup-02/corpus-eligibility.md) is already available, with checked hashes and record locations; it does not complete physical eligibility. Extra 330 Red is the v6 translation reference; Beginair is a v5 shared-template ambiguity regression. Neither is a flight specimen. End with a supported specimen or a named owner/prerequisite, not another broad format survey.

The missing UID sidecars are **already supplied upstream**. Preflight passed on `08f94826`; [other required CI/export failures remain](../research/aircraft-creator/import-closeout-2026-11-17/followup-02/evidence/ci-upstream.json). Recheck the eventual implementation candidate and coordinate those failures with their owners. Independently, repair the reproduced invalid-inventory draft loss and last-model cancellation behavior. The physics owner can investigate v4 explicit-backend/contact-context integration, exact effective launch settings and failed-start recording rollback. Freeze the actual specimen/domain before its qualification campaign (Phase 0B).

**Next source-adoption packet:** AC-CV-05/06 and AC-06, the smallest justified physical-dependency/adoption path that completes that candidate, using the guide's coordinated writer/reader changes. The 128-row display report is not its complete physical input. Reuse the existing compiler/loader/Store/resolver. Do not begin by rebuilding the converter, catalog, persistence layer or entire wizard.

## Keep these boundaries intact

- Current successful conversion is visual; receipts say `physics_imported=false`. Reports and an explicit estimated-installation declaration do not implement physical adoption.
- Source values, checked derivations, user inputs and reviewed estimates for genuinely missing fields keep distinct provenance. A partial estimate can complete the same source-aware configuration when qualified and labelled; replacing powertrain/topology creates a separate configuration and is not faithful source reproduction.
- No mass reduction, invented battery/propeller curves, duplicated inventory, hidden omitted gear/engines, or mesh-derived aerodynamic truth to force eligibility.
- Recognized ClearView trial/publication guards remain until the actual source-aware candidate, numerical domain and real context pass. A successful trim, unit suite, resolver or private numerical diagnostic cannot grant flight.
- Current production and private experimental numerical laws are different evidence. The private max-piece campaign's 58/8/2 result is unqualified and unadopted; preserve its failures rather than treating it as the shipped law.
- Existing SourceRef and captured publication are implemented. Hash consistency does not prove external definition-to-physics derivation. Apply the closeout's semantic verification policy before accepting received pairs for flight.
- Raw validity and property override ownership belong to the document. A new document-bound launch must not reuse a candidate predating an invalid edit; an already frozen independent trial remains a different state. Current replacement of whole Estimated items is documented behavior, not proof of property-level ownership.
- Archive hides listings without revoking a valid pinned revision. Runtime closure and retained original-source closure are distinct; preserve AC-CV-07's exact claims.
- Preserve old raw records and meaning. Recompile or converter upgrades create new revisions. Preserve failed/cancelled edits and every required negative test.

## Finish each packet with evidence

Use this compact record in the owning phase's dated evidence; do not create another backlog:

```text
Existing step / phase:
Baseline and integrated commit:
Owner and changed source/schema boundaries:
Player-visible outcome:
Source fixture and semantic assumptions:
Positive and counterexample checks, commands and retained reports:
Observed result and exact remaining limitation:
Next packet, dependency and exit condition:
```

A packet is complete only when its stated boundary is proven and its continuation is specific. Use the smallest relevant checks while editing, then required integration/CI gates for that boundary. If a hypothesis fails twice without progress, the lead must select another bounded mechanism or record a concrete blocker; do not keep generating variants or rerunning the same audit. Never relabel incomplete, failed or unresolved evidence as success.
