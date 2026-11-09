# CR-40 — Crash-cost handoff remediation

2026-11-09. Implemented preview, with release gates open. This record reconciles the supplied [senior handoff](<../../../../external Audits/OpenRC_Crash_Cost_Senior_Handoff/README.md>) with the current application. `external Audits/CRASHES.MD` was empty. The implementation began at `300dc4e`; unrelated scenery work advanced the shared baseline to `5fe6aee` during the session. The retained verification receipts identify the working source separately from HEAD.

## Implemented boundary

Normal interactive fixed-wing flights use a separate, generated financial companion and automatic deterministic local game rules. Aircraft mass, inertia, flight laws, generated aircraft data and the shared kernel are unchanged. A financial result is a scoped game estimate, not a real serviceability or structural-failure prediction. X-Cell remains unsupported because its financial installation is absent.

The companion covers 11 fixed-wing routes, including the three retained glow configurations and all three registered finite-pack variants. It supersedes inclusive legacy financial allocations only through the explicit `openrc-aircraft-economics v2` adapter. Jensen structures/gear are separate groups; Lumber's bare wing excludes its four grouped servos; Avanti local structures exclude its turbine/gear. F4U core/ignition remains a single provisional package where independent box contents are unresolved. Foreign-currency spare leads and unmatched folding-wing products were not silently imported as exact installed parts.

Unquoted groups have dated, explicit authored USD game allowances. They are design decisions, not new seller observations or compatibility evidence. Retained offers keep their actual observation dates and notes. Default local estimates exclude DIY and commissioning labor, tax, shipping and recovery. Explicit selected repair choices retain their own labor/material basis. V1 repair rounding remains its documented ceiling policy; historical receipts are not reinterpreted as half-up.

Accepted hull contacts and an opt-in accepted-endpoint gear compression proxy feed local profiles. Normal shallow support does not open an incident. Gear compression is neither incoming wheel velocity nor impact work. Protected electronics/powertrain groups remain inspection scoped. A terminal powered ground-disc observation preserves a coincident propeller fact without stopping or modifying the already-frozen engine/body. It has a separate v2 observation format; closed v1 event semantics remain intact. Extra gear observations are disabled on technical and report-disabled routes. Statistics ignore cost-only support packets and retain their original physical-contact threshold.

The owner retains persistent peaks, bounded per-component summaries, episode cursors and recent ID/digest proof independently of its diagnostic journal. Exact retained duplicates are no-ops; conflicting/stale evidence is refused atomically. Reimpact reopens affected reuse/repair and retains applicable inspection fees; replacement cannot be downgraded. Journal truncation alone cannot manufacture a damage card or erase later mapped damage. True coverage loss, water, unmapped contacts and unknown prior history stay explicit. A refused notification warns through the live owner/UI at the frame boundary; that session-only warning does not rewrite an immutable accepted archive.

Money completeness covers assessed incident components separately from whole-build coverage. Missing unrelated prices cannot poison a local quote; missing affected prices remain unknown. Already-incurred fees reconcile across alternatives. Whole replacement remains a comparison unless like-scope feasibility and fees justify an incident ceiling. Bounded package search supports pairs, overlap and unvalued surplus, and states optimality only within the declared candidate set. Shared-repair aggregation preserves explicit material purchases, consumption and evidenced shared labor.

Economics checkpoint v2 binds source, profile, catalog, recipes and contact identity, including bounded summaries/proof and evidence revisions. Validation precedes commit. Old v1 paired ledgers are explicitly refused; old reports remain view-only. Restart starts a fresh financial ledger. Physics-only restore retains an unknown-history warning, even after an earlier contact ended. V3 purchase comparisons are validated when reports reopen.

## Authoring and regeneration

The authoritative authored companion is [cost-profiles.json](../../../../research/crash-economics/cost-profiles.json); its [generator](../../../../research/crash-economics/build_profiles.py), [schema](../../../../app/data/schema/openrc-cost-profiles-v2.schema.json) and runtime `cost_profile.gd` enforce separate contracts. Generated runtime files are never edited directly.

1. Declare every required installed financial group, its physical parent(s), quantity, basis and notes. Shared parents require an exact reviewed child crosswalk; the old inclusive row cannot also be charged. A material component cannot have an empty physical parent. Services are outside the default parts inventory.
2. Bind qualified hull/gear/propeller IDs to local targets and an explicit response. An inspection-candidate list is not a list of co-located failures. Unknown affected unit counts remain inspection scoped.
3. Pin reviewed exact base and registered-pack byte hashes in the source. The generator refuses geometry or installation drift even if IDs are unchanged. A source change requires reviewing the physical/economic crosswalk before deliberately updating those pins. Arbitrary Workshop sources cannot inherit stock estimates.
4. Preserve the legacy price-catalog digest, companion source digest and generator digest. The adapter refuses a stale catalog/companion pairing, including a same-price metadata refresh. Refreshes do not change frozen historical reports.
5. Run `python research/crash-economics/build_runtime.py`; `--check` verifies both the closed v1 artifacts and the companion. Run the focused authoring, profile, fleet and incident checks with the repository's checked runner. Adding a fixed-wing catalog route requires a corresponding profile; missing support fails generation.

Runtime limits include a 1 MiB profile document, 128 financial rows per route, 256 zones, 64 admitted events per tick/64 KiB event batch, 128 journal entries/64 KiB journal, 128 recent proofs/open contacts, 16 inspections and a 256 KiB latest archive. Additional summary/checkpoint validation bounds are defined by their versioned readers. There is no network lookup or archive I/O inside accepted-tick callbacks.

## Evidence and limits

The retained [verification ledger](verification.json) distinguishes consolidated checked execution, offline authoring/schema checks, constructed fleet fixtures and native observations. Full logs and images stay in ignored `tmp/`; no screenshots are committed.

The native Windows Compatibility session used the pinned Godot 4.8 beta2 and actual 1920×1080 output. Home → runway → flight created the real owner/profile and quiet support produced no card. An input-driven Jensen crash at accepted tick 562 automatically reported 12,538 cents: 11,999 for the local wing allowance plus 539 for the propeller, with related powertrain inspections unresolved. A later Lumber input-driven crash reported 6,798 cents: bare wing 5,999 plus propeller 799, without four intact wing-servo charges. English/Spanish report and expanded layout were inspected; the latest archive reopened across Home/new-flight transitions. These are bounded journeys, not all-fleet desktop or performance qualification.

The constructed fleet fixtures exercise real serialization → owner → automatic assessment → calculator for local structure, ordinary/hard gear proxies or explicit gearless scope, and prop/no-prop handling on all 11 fixed-wing routes. They never inject final component dispositions. They establish software behavior for those inputs, not accepted-solver trajectories, physical realism or the whole 46-case handoff matrix. Separate production integration checks cover actual session contacts, effects on/off, 30/60/144 publication cadence, paired rollback and archive/reset behavior.

Independent Good Enemy review was source/data read-only. It found and prompted fixes for source/catalog drift, default pack admission, bundled purchases, quantity, receipt progression, archive consistency, scoped wording and the statistics threshold. Agent review is not an independent physical experiment.

## Remaining gates

- The complete CC-00–18 handoff is not closed. Keep preview labels and Gate CR open. Candidate-specific required CI/full-suite qualification, complete eight-route desktop journeys and incident-class coverage, human acceptance and nominated-hardware timing remain separate work.
- Grouped repair/shared-fee costing and purchase alternatives are verified interfaces/comparisons. A versioned normal-play multi-choice/purchase transaction and persistent inventory are not implemented. Existing explicit individual repair receipts remain available.
- Water recovery/immersion, delayed thermal propagation, stopped-blade phase, scenery prop strikes, calibrated secondary/internal damage, real serviceability and damaged-flight behavior are unsupported or pending. A visual fire is never billing evidence.
- Exact Corsair and A200 spare revisions, other unresolved installed product identities and independent repair invoices require their own source/owner review. Authored game allowances do not close those research questions.
- X-Cell needs its own financial inventory, rotorcraft contacts, profiles and validation. A complete fixed-wing preview cannot be advertised as complete catalog economics.

The [economics plan](../../../plans/crash-damage-economics.md) owns the remaining acceptance matrix. This record does not authorize publication or remove physical-validation requirements.
