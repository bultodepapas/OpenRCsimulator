# Project audit: roadmap, plans and research

**Status:** complete supporting audit, 2026-10-06. **Scope:** master roadmap, step sequencing, plan registry, research coverage and claims in plan review #4. This is a supporting report for the whole-project audit. Findings were recorded progressively and checked against the current implementation.

## Judgment

The roadmap has unusually strong habits for an early simulator: known-answer numerical tests precede aerodynamics; it distinguishes code verification from realism validation; parameters carry provenance; it calls for owner playtests; and it has begun replacing borrowed whole-aircraft derivatives with local loads. Those are sound foundations. The principal roadmap risk is now coordination and sequencing: the plan has grown into many concurrent aircraft and systems tracks before the first owner flight gate is closed, while some new steps assume shared state or validation work that their listed order puts later. Plan review #4 found real issues, but its own recommendations are not yet a single dependency-consistent critical path.

## Findings

### R1 — The roadmap's state-layout dependency contradicts its recommended order

**Importance:** High · **Disposition:** Fix in the roadmap before starting runway anchors; this is a sequencing correction, not a request to stop unrelated work.

**Inspected:** `ROADMAP.md` Phase H and M2, plan review #4; `docs/research/roadmap-investigations/01-numerics-architecture-performance.md`; research index.

**Found:** Phase H says H8 creates the extensible state before E3b anchors, G2 rotor speed, wash lag and M5 filters are added. The H8 description explicitly includes gear anchors among state that otherwise forces repeated golden migration. But plan review #4's recommended order puts E3b1–E3b3 and E1b before H8. E3b1 itself defines a per-tick anchor state. M2's order repeats that E3b-first sequence. The two orders cannot both preserve the stated goal of settling the state layout before those features.

**Evidence:** `ROADMAP.md` Phase H heading and H8 row (lines 163–178); M2 recommendation (line 184); review #4 “Recommended order” (near the end of the section); research 01 summary and state inventory. E3b1's row says “anchor per wheel in the per-tick state.”

**Why it matters:** If E3b anchors land first, H8 either has to retrofit/migrate them or define a generic state around an already special-case anchor representation. That is the exact repeated-retrofit cost H8 is meant to avoid. It also risks recording another set of goldens just before changing their state representation.

**Recommended action:** Place H8 (and the minimum compatible trace/golden reader work) before E3b1. Then build anchors on the settled state layout. H9's cross-platform golden policy can be decided independently; it need not block the state-layout dependency. If H8 is intentionally deferred, amend its scope to say it will not migrate already-shipped wheel anchors and provide an explicit compatibility path.

**Counterevidence / limit:** Current E1/E2/E3a ground work does not yet contain E3b anchors, so there is still time to correct this without undoing implementation. H2/H3's trajectory hashes show that the performance refactors can preserve current trajectories, but do not resolve future state-layout compatibility.

### R2 — D11's regime-consistency exit criteria do not account for every measured derivative

**Importance:** High · **Disposition:** Clarify the physics acceptance and dependency before marking D11b fixed or using it as an E3c gate.

**Inspected:** D11a/b/d and E0a2 rows in `ROADMAP.md`; research 02; `docs/research/roadmap-investigations/README.md`.

**Found:** D11b measures four derivatives over α = 0–11° and reports the current worst ratios as Clp ×1.73, Cmq ×0.28, Cnr ×0.72 and CLα ×1.34. The listed remedies assign Clp and CLα to D11d (wing strips) and Cmq / Cmα̇ to E0a2 (tail lag), but there is no explicit remedy or exit criterion for Cnr. Yet D11b says it will pass with D11d and E0a2 and the research 02 acceptance asks for Clp, Cmq(+Cmα̇), Cnr and CLα to agree within ±10% across regimes.

**Evidence:** `ROADMAP.md` D11b, D11d and E0a2 rows; research 02 § implementation steps and proposed tests; the “Facts the lead re-checked” table in the roadmap-investigations index. Cnr is named in the test; the two assigned fixes do not state how it is corrected.

**Why it matters:** A red-test-to-green-test plan is only actionable if each failing quantity has an identified physical cause and change. Otherwise D11 may end by relaxing the assertion or hiding an unresolved yaw-damping discontinuity. That matters to crosswind approach and ground-direction behavior, even if the current spin/stall work is finite.

**Recommended action:** Record each derivative's α profile before and after D11d/E0a2. If Cnr moves because the fin is now treated through local flow, say so and add a named test/step proving it. If it does not, open a focused fin/local-flow correction. Keep the acceptance at the stated tolerance or document a physical reason for a different band.

**Counterevidence / limit:** D11b is deliberately pinned as a known defect today and does not silently turn green. This is good test discipline; the gap is in roadmap causality/step closure, not an existing false pass.

### R3 — Plan review #4's validation work is placed after several steps that consume unvalidated ground assumptions

**Importance:** Medium-high · **Disposition:** Pull a small owner measurement forward before E3b3 or explicitly keep takeoff-roll claims provisional until PT2.

**Inspected:** M2 E2/E3a/E3b/PT2 rows; research 04 and 08; research notes for E2 and E3a.

**Found:** E2's tire parameters are estimates/borrowed (`C_rr = 0.04`, `μ = 0.8`, peak slip = 6°); E3a scales surface values borrowed from FlightGear, with rough-surface rolling estimated. The upcoming E3b3 proof compares the takeoff roll with a hand integral using those same coefficients and an APC propeller table. The real Stik pull/coast-down/idle-creep/takeoff-distance measurements are scheduled as PT2, after the full circuit (E3c). The internal proof can establish implementation consistency, but it cannot validate the ground model before it controls the takeoff roll and circuit.

**Evidence:** `ROADMAP.md` E2/E3a/E3b3/PT2 rows; `docs/research/ground-friction-e2.md`; `docs/research/ground-surfaces-e3a.md`; research 04's “grass rolling resistance” uncertainty; research 08's field kit ordering.

**Why it matters:** Errors in low-speed rolling resistance, steering authority or prop thrust accumulate into takeoff distance and control authority. A hand calculation that reuses the simulator's coefficients is a verification target, not an independent realism target under Roadmap rule 6.

**Recommended action:** Run the low-cost field-kit items (wheel pull/coast-down on runway and rough grass, idle creep, static thrust/rpm if safe) before accepting E3b3's distance band. Keep E3c/PT2 as the full pilot validation. Until measured, label E3b3's distance as a model-to-hand-estimate check, and do not describe it as validated takeoff realism.

**Counterevidence / limit:** PT2 explicitly requires these measurements, owner involvement is a real resource constraint, and ROADMAP says the field kit can happen at any time. So this is a dependency emphasis and claim-boundary issue, not missing awareness.

### R4 — The project has exceeded its own “close the first pilot gate, then expand” control loop

**Importance:** Medium-high · **Disposition:** Gate and scope the critical path now; defer broad aircraft and product expansion until the first owner session establishes priorities.

**Inspected:** `ROADMAP.md` “Where we are,” M1/Gate 2 and M2; `docs/README.md` track registry; aircraft plans and milestone status.

**Found:** Gate 2 is open for the first owner flight, radio compatibility, ratings, platform launch checks and independent Stik videos. At the same time, four catalog aircraft are already present, with the Extra and Avanti marked experimental and the P-51 having a sizeable simulated ground/envelope suite; UI, visual-quality and landscape work also advanced. The roadmap says milestones end in an owner-flown build and playtest feedback can reorder the next milestone, but there is no explicit rule that these parallel tracks remain prototypes or which decisions are frozen until Gate 2.

**Evidence:** `ROADMAP.md` lines 20–42 (Gate 2 status and current track summaries), M1 acceptance/open items and M2 already under way; `docs/README.md` registry states Gate 2 open while listing several aircraft as flyable/experimental and UI/visual continuations.

**Why it matters:** The risk is that untested assumptions about baseline feel, readability, radio setup and target hardware become shared interfaces before the project gets the owner's highest-value evidence. Each extra aircraft also consumes regression and documentation attention while the reference Stik's roll response is still 2.07–2.37× faster than flight-identified comparisons and the first input session is pending.

**Recommended action:** Keep Gate 2 as a real product decision point. Mark work that proceeds before it as reversible research/prototype work; do not widen shared schemas, polishing scope or aircraft promises based only on scripted tests. Make the next critical path: owner Gate 2 session (including radio and readability) → record priority/acceptance bands → close the one or two baseline defects it reveals → validate ground handling on the reference Stik → only then approve broad expansion. Technical prep that does not constrain those choices can proceed in parallel.

**Counterevidence / limit:** Gate 2's owner-dependent items and “subordinate to Gate 2” language already exist, and experimental aircraft are labeled as such. The issue is that the roadmap still reports M2 underway and many downstream tracks as next actions without a clear non-binding boundary or owner-priority checkpoint.

### R5 — The propulsion research leaves an obsolete integrator recommendation beside the resolved decision

**Importance:** High · **Disposition:** Fix the research document before G2 implementation is generalized to the rest of the aircraft.

**Inspected:** `docs/research/roadmap-investigations/01-numerics-architecture-performance.md`, `05-propulsion-engines-motors.md`, their index resolution table, and ROADMAP G2a/H8.

**Found:** Research 01 demonstrates an O(dt) split error when shaft speed is held outside the RK4 state and recommends integrating rpm in the extensible state. The cross-document resolution in the index also says “Integrate it (H8 then G2a).” ROADMAP G2a agrees. But research 05 still recommends the opposite: a linearly implicit split update in option C, rejects a 14th RK4 state as “not now,” says to use the implicit approach “anyway” for electric rotors, and retains that recommendation in “Decisions to take now.”

**Evidence:** Research 01 summary, toy convergence comparison and “Where ω lives” recommendation; index § “Where the documents disagree”; research 05 summary, implementation options C/D, final “Recommendation for this repo” and decision 2; `ROADMAP.md` H8/G2a. This is a direct contradiction, not just an unresolved alternative.

**Why it matters:** The direct propulsion document is a likely implementation entry point. A developer following it can implement a shaft state outside RK4 after the roadmap has already selected RK4 coupling. That would invalidate the error argument that motivated H8, and could make the same model differ between its toy benchmark and production implementation.

**Recommended action:** Amend research 05's status and recommendation to explicitly mark option C superseded by the measured split-error result and the roadmap resolution. Preserve the comparison as historical evidence. Add a test of the chosen G2 formulation against the same coupled throttle-step reference and h/h₂ convergence used in research 01.

**Counterevidence / limit:** The roadmap and index already select the coupled RK4 design, so an implementer reading them together can resolve the conflict. The fix is low-cost documentation maintenance, but it should happen before G2 is spread to all aircraft.

### R6 — The VLM / AVL toolchain is on the aerodynamic critical path without a decision gate that proves it is needed

**Importance:** Medium-high · **Disposition:** Narrow the tool spike now; retain it only if the simplest model cannot meet a predeclared aerodynamic target.

**Inspected:** D11c–e in `ROADMAP.md`; research 02's L1 fidelity proposal, X-aero-3/4/5, and “Decisions to take now”; DATA-13; the existing Extra/P-51 derivation scripts and generated geometry.

**Found:** The proposed first consistency repair makes an in-repository VLM and a pinned external AVL command/parser part of the D11 sequence. Their numerical targets are useful known-answer checks (elliptic wing slope, AR 5 roll damping) and the comparator is a valuable cross-check. However, research 02 also acknowledges the sources are inviscid/small-angle and that a VLM/AVL agreement is not independent flight validation. The roadmap currently makes a multi-aircraft aerodynamic toolchain a dependency for D11d, while the immediate simulator already has four aircraft entries but Gate 2 remains open. There is no intermediate “if the analytical strip model fails this target, build VLM/AVL” gate.

**Evidence:** `ROADMAP.md` D11c depends on no prior measured need and D11d depends on it; DATA-13 later adds AVL again; research 02 says VLM/AVL do not model post-stall or viscous/reynolds effects and proposes them for attached-flow derivatives only. DATA-9 reports two copied derivation scripts and a shared tool proposal, but this is tooling debt, not proof the runtime needs VLM.

**Why it matters:** A solver and its geometry conversion become a second model to maintain, with pinned binaries, GPL boundary and frame/sign conversions. If it cannot materially improve a measured behavior, it delays the flight-model correction while creating a false impression of realism. Conversely, the induced-flow map may be technically justified for strip loading and roll damping, so removing it outright would also be premature.

**Recommended action:** First make the cheapest known-answer wing model (elliptic distribution and rectangular/tapered analytical or Schrenk baseline) pass an explicit oracle-consistency test. Compare its Clp and section loading against the flight-identified reference and a single independently checked AVL run. Keep a maintained VLM implementation only if the simpler model misses the declared band or a real aircraft variant needs its map. Keep AVL an offline validation tool, never a runtime or package dependency. Avoid a reusable general multi-aircraft backend until at least two live use cases need it.

**Counterevidence / limit:** D11's measured Clp discrepancy is real, and the research argues a wing-alone induced-flow map is physically preferable to a whole-aircraft slope copied onto every strip. The recommendation preserves lifting-line/VLM as a cross-check while making the maintained solver conditional on evidence of need.

### R7 — The contributor interface and aircraft v2 proposal solve anticipated scale before current variant pressure is demonstrated

**Importance:** Medium-high · **Disposition:** Keep the data contract and state semantics; defer generic frameworks until a second concrete consumer forces them.

**Inspected:** H8 and H10; DATA-5–16; research 01's architecture proposal and research 09's v2 sketch; current aircraft loader/catalog and the four aircraft data files.

**Found:** The research correctly identifies the current v1 limitations: one main wing/tail pair, three controls, and one power plant. But the proposed v2 simultaneously adds arbitrary component IDs, multi-panel surfaces, mixers, many actuators, multiple power units, shape masses, overlays/variants, user aircraft packages, licensing manifests and JSON Schema. H10 likewise creates a generic `prepare(model) → pack`, `add_loads(state, ctx, out)` contributor framework for current and hypothetical aero, propulsion, slipstream, gear, wind and hull. The present call graph explicitly composes aero, propulsion, optional slipstream and ground loads; wind and hull are future contributors. Many data cases (biplanes, gliders, twins, mods) do not yet exist. H8's need to include coupled states is immediate, but an arbitrary run-time state registry is not required to establish their integration semantics.

**Evidence:** ROADMAP H8/H10 and DATA-8–16; research 09 fidelity ladder and v2 sketch; current `aircraft_data.gd` fixed typed validation and `app/data/aircraft/*.json`. Catalog is a fixed list of four IDs; no user-aircraft package consumer exists.

**Why it matters:** Broad schema migration and generic dispatch can consume time and create compatibility/performance contracts before the simulator knows which variant model it needs. It also makes behavior-preserving migration across all aircraft a hard gate for individual improvements, and “50 aircraft listed in <50 ms” optimizes a product scale not yet evidenced. At the same time, schema growth by undocumented optional keys can become real debt, and coupled RK4 states do need a stable contract.

**Recommended action:** Make H8 the smallest fixed, typed state extension that supports the next required continuous state (rotor speed) and discrete per-tick modes, with named units and trace/reset rules; add another state only for a feature that consumes it. Keep the present explicit typed calls in Dynamics and FlightSession. Make H10 optional unless upcoming contributors create repeated orchestration or duplication across call sites; if introduced, benchmark allocations and dispatch against this direct path. For aircraft data, first document/freeze v1, add generated-file `--check`/hash and shared helper code where duplication already exists, and add only the next proven capability (e.g. P-51/Avanti flap and retract actuators). Trigger a bounded v2 migration when a named near-term capability cannot be represented safely and clearly with additive v1 fields and at least two active aircraft/workflows benefit from the same new structure; migrate behind a converter then. Keep user mods, licensing UI, package discovery, arbitrary mixers and future aircraft class support out of that migration unless the owner chooses them.

**Counterevidence / limit:** Four real aircraft have already exposed format growth, and P-51/Avanti work needs overlapping flap/retract/power features; moving a shallow capability at a time may cost more than a bounded v2 migration. However, the proposed v2 scope mixes those near-term needs with packages, gliders, twins and variants. Split the core schema decision from those optional features, and define the actual missing cases before setting migration proof to “every golden bit-for-bit.”

### R8 — The knowledge base marks itself researched but still contains unresolved-source and “search-result-only” claims that must remain hypotheses

**Importance:** Medium · **Disposition:** Preserve the caveats; verify a source before converting its values into production data or acceptance limits.

**Inspected:** review #4 summary and research README; research 01, 02, 03, 04, 05, 07; field-kit and data-v2 proposals.

**Found:** Plan review #4 reports around 350 sources and describes research “before M2 grows,” while its own knowledge-base index says the search budget ran out and lists several still-unverified items. Examples that affect proposed future acceptance include grass rolling resistance for small wheels, the Phillips–Hunsaker ground-effect formulas, RC community static thrust/taxi authority, the measured propwash tail-decay range, real simulator tick rates and controlled RC orientation studies. Specific records also say a cited Hunt–Crossley text was not read, and source PDFs/hosts returned 403/timeouts. These are openly labeled, which is good; the risk is treating synthesized numbers as established because the document is long and well organized.

**Evidence:** `docs/research/roadmap-investigations/README.md` “Limits of this research”; reports 01–08 source status; M2 E2/E3b, E0b4 and M5-GE rows use these parameters as targets or bands.

**Why it matters:** A sourced calculation can be internally correct while the input is wrong for small RC wheels, this airframe, or the stated test condition. Turning an unverified literature estimate into a strict CI threshold would freeze the assumption and make later pilot data look like a regression.

**Recommended action:** Treat these as ranges and sensitivity inputs until a primary source is fetched or the owner measures the Stik. Put uncertainty bands on the test before choosing a single point target. Give each high-impact, still-open claim an explicit evidence owner and step (e.g. surface pull tests before E3b3, propwash field checks before global adoption, human blind study before camera changes).

**Counterevidence / limit:** The documents repeatedly distinguish estimated/borrowed/measured evidence, call out source access failures, and leave propwash opt-in. This is responsible research hygiene; no report should imply the research is useless or that every fact needs flight data before exploratory implementation.

### R9 — The new crash track is absent from the track registry and has a missing research dependency

**Importance:** High · **Disposition:** Register and repair before CR-01 begins.

**Inspected:** CRASH-DAMAGE-PLAN, docs/README track and step-ID tables, crash-damage research index and files.

**Found:** The plan declares CR- as a new step prefix, Gate CR, ownership split across physics/model/menu teams and says CR-A starts “Now, beside M2.” The documentation map has no crash track row, no CR- namespace and no Gate CR entry; the research index has no crash entry. The plan also links to a crash research README that is absent and claims reports 01–05, but report 03 (RC construction crash physics) is absent; the directory contains 01, 02, 04 and 05 only. CR-07 explicitly depends on the missing 03 for structural energy thresholds. Meanwhile ROADMAP’s current next action remains E3b1, with no stated scheduling relationship to CR-01.

**Evidence:** CRASH-DAMAGE-PLAN header, §3 and CR-07; docs/README “Tracks, plans and step IDs,” “Step-ID namespaces,” and “Gates”; ROADMAP “Where we are”; docs/research/README entry points; file listing for docs/research/crash-damage-investigations and the linked README target.

**Why it matters:** Parallel ownership and step IDs are project contracts. Without registration, other tracks cannot see the CR paths or avoid conflicting edits, and Gate CR has no place in the canonical gate table. The master roadmap also gives no priority order between E3b1 and CR-01. More materially, CR-B's resolver cannot be implemented from its stated threshold source because the source report is not in the repository.

**Recommended action:** Before implementation, add the crash track/prefix/gate to docs/README and AGENTS ownership registry (or explicitly put it under existing physics/UI/model ownership without a new parallel track). Restore or replace the missing CR-03 research with fetched, traceable construction/impact sources, or re-scope CR-B to an explicitly measured/estimated early prototype whose thresholds do not claim structural validation. Run the relative-link check on the plan and its index.

**Counterevidence / limit:** The crash plan states the cross-team owners and labels CR-B's thresholds estimated. Those are useful safeguards, but do not replace the central registry or the absent source it names as a prerequisite.

### R10 — CR-A is a broad presentation feature set before the reference pilot gate; its physics evidence only supports impact ranking so far

**Importance:** Medium-high · **Disposition:** Defer the full CR-A bundle until Gate 2 prioritizes it; if a minimum crash repair proceeds, keep it to impact snapshot and readable report.

**Inspected:** CRASH-DAMAGE-PLAN §§1–4; crash research 05; CR-00 effective-mass output; ROADMAP Gate 2 and current milestones.

**Found:** CR-A is labeled “Now” and bundles sub-tick impact event detection, delayed crash audio, engine rundown, dust, ground marks, a Godot rigid-body wreck, captures, an explanatory report and owner listening notes. Yet the highest-priority baseline Gate 2 session (flight feel, radio compatibility, readability and real-machine behavior) remains open. The impact study correctly says its effective mass is a useful ranking across hit locations, and that absolute break thresholds need separate evidence; it does not validate structural energy thresholds or the estimated restitution/friction impulse used for the wreck handoff. CR-B's five-scenario outcomes and 80% video-class target therefore must not be read as validated material strength merely because m_eff and impulse equations pass unit checks.

**Evidence:** CR-A objective/step table; CR-00 results report only computed effective-mass values from the current model inventories; research 05 states “m_eff is the right ranking” and “absolute thresholds need doc 03 numbers and the owner's judgement”; its post-impact restitution is estimated (e ≈ 0.1); ROADMAP Gate 2 is still pending. CRASH-DAMAGE-PLAN §1 and research 05 also retain the obsolete “501 µs of 500 µs” cost statement although ROADMAP now records H2/H3 at 400 µs trimmed and 380 µs stalled on the loaded VM.

**Why it matters:** Crash presentation can be a strong product feature, but its cost spans multiple shared tracks and can displace the first real pilot evaluation that would tell the team whether crash feedback is a current user priority. Mathematical consistency of effective mass proves the calculation for the chosen inertia; it does not establish how a balsa/foam/composite joint actually fails, nor validate an estimated restitution coefficient or a video-derived impact speed.

**Recommended action:** Move the full CR-A package behind Gate 2 or make it an explicit, time-boxed parallel presentation experiment. If a small repair proceeds, capture the first contact, freeze the airplane at the crossing pose, report component and measured/estimated kinematics, and preserve existing reset behavior; defer audio/particles/marks/wreck/replay until the owner rates the need. Keep m_eff/e_normal described as rigid-body normal-impact energy/ranking. Require a separately labeled threshold dataset and uncertainty band before CR-B claims structural realism; update the crash research cost baseline to the post-H3 measurement.

**Counterevidence / limit:** The current buried-airplane freeze and mid-sample engine cut are genuine visible defects, so a limited impact-time snapshot/report could improve comprehension now. The plan explicitly labels structural thresholds estimated and reserves Gate CR for owner review; the concern is the breadth of the first delivery and the strength of its validation claims; better crash feedback remains useful.

### R11 — Review #4's knowledge base and roadmap retain same-day findings that D11a has already superseded

**Importance:** Medium-high · **Disposition:** Reconcile the snapshot now, before review #4 becomes the default implementation reference.

**Inspected:** Plan review #4 in ROADMAP; roadmap-investigations index and documents 05 and 08; D8b/D10/D11a entries; the generated sensitivity results.

**Found:** Research 08 and its index row still tell the reader that sensitivity results are stale, the sweep refuses its Cnβ/mass/CG rows, there is no 25e comparison, and Dorobantu's data are future work. But the generated results file is now marked as generated by D11a, contains the US120 and 25e comparisons, and reports the repaired D10 sweep with no refused rows. ROADMAP D11a also records these completions and the current 2.07×/2.37× roll-pole gaps. Earlier D8b and D10 entries still present the pre-repair 1.45× short-period gap, 1.9× roll gap, 63° sideslip, and old sensitivity ranking as current; ROADMAP review #4's unresolved-issue list repeats some stale claims. The knowledge-base index acknowledges code was committed in 480cddd, yet document 03 still labels that implementation uncommitted and document 05 still describes a shaft slice as uncommitted and proposes it as future G2a work. These are snapshot notes that were not reconciled with later same-day code and data.

**Evidence:** `docs/research/roadmap-investigations/08-validation-flight-testing.md`, “Summary,” “Where the code stands,” and its recommendations; `docs/research/roadmap-investigations/README.md` rows 05/08 and “Other tracks' code”; `research/sensitivity/results.md` header and D8b/D11a tables; ROADMAP M1 D8b/D10/D11a rows and plan review #4 unresolved items 4/5/13; the committed `480cddd` in git history. The chronology is visible within the documents: all carry the same date, but D11a and `480cddd` are later states than the review snapshots.

**Why it matters:** Readers following the research index can redo completed work, reject a valid parameter path, or report stale validation numbers. Stale present-tense claims also undermine trust in otherwise valuable evidence and make the phase ordering appear unresolved when the data work was already done. A same-day status snapshot can still be useful if it declares its observation point and points to the authoritative updated result.

**Recommended action:** Edit only the stale statements: mark document 08's initial diagnosis and refusals as the pre-D11a snapshot, update its “Where the code stands” and recommendations to the D11a output, mark 25e as available and incorporated, and update the index row. Refresh the corresponding D8b/D10 summary and unresolved-issue list in ROADMAP while preserving the history of the original discrepancy. In docs 03/05, change present-tense “uncommitted”/“next” descriptions to a dated historical observation and link the current code/roadmap resolution; keep the numerical omissions and R5 integrator contradiction visible until corrected.

**Counterevidence / limit:** ROADMAP D11a already states the corrected numbers and completed work, and the index warns about the historical observation point. Therefore a careful reader can reconstruct current status. The problem is inconsistency across entry points, not a lack of evidence or a need to repeat the sensitivity run.

## Recommended critical path and scope boundary

This order protects the reference-aircraft learning loop while still allowing small, reversible engineering work to proceed in parallel. Existing experimental aircraft and small reversible parallel work can remain while the baseline stays the release bar.

1. **Close M1 Gate 2 on the Ugly Stik.** The owner flies the current exported build with the intended radio and reports control feel, setup friction, readability and real-machine pacing. Capture the current known defects and distinguish pilot observations from trace measurements.
2. **Correct only the baseline defects that affect the next task.** Reconcile the roll-inertia discrepancy with the available swing test or keep it explicitly estimated; close each D11 derivative defect with a named physical cause; establish servo/linkage behavior and low-speed tail authority before using the model for landings. Retain model changes behind the existing oracle and flight checks.
3. **Collect the cheap ground / propulsion measurements before takeoff claims.** Use the field kit for wheel pull/coast-down, idle creep, static rpm/thrust and the control inputs needed for a takeoff. If there is no matching Stik, use the nearest documented airplane and label that limit.
4. **Settle only the state representation the next feature needs.** Before E3b wheel anchors or G2 shaft coupling, define their continuous-vs-discrete update timing, reset/replay semantics and trace names. Keep this typed and bounded; do not turn it into an arbitrary state/plugin framework yet. Add the shared load-contributor interface only if measured code duplication or a third independent contributor justifies it.
5. **Finish one reference-aircraft ground vertical slice.** Taxi and stiction, takeoff with the correctly modeled propwash and control authority, approach and landing, crash classification at the interface. Hand estimates are useful verification, but the owner/field measurements and pilot session close validation. Recompute provisional takeoff targets after propwash and actuator response land; do not freeze a no-propwash takeoff result.
6. **Then expand propulsion and one contrast aircraft based on the pilot's needs.** Close the shaft/propeller model and stopped/windmilling behavior for the chosen reference engine; decide whether the next valuable comparison is electric, gas, turbine or an aerobatic/scale variant. Do not front-load fuel chemistry, fire, advanced audio, packages or arbitrary mixers.
7. **Use later roadmap phases as opt-in branches.** Wind/weather, smoke, damage, gliders, twins, VR and user aircraft packages each need a user need, a bounded slice and an independent acceptance method. Runway realism and the reference aircraft remain the release bar while these branches are exploratory.

**Architecture triggers:** preserve the provenance-bearing JSON contract and the current local-load physics. Freeze v1's current behavior with loader tests and generated-output checks. Build the narrow H8 state extension needed by actual coupled dynamics. Create v2 only after concrete P-51/Avanti or another aircraft requirements cannot be expressed safely and clearly as a small additive v1 change; scope the migration to those requirements. Build/maintain VLM only if the simple strip model fails a declared attached-flow target or repeated aircraft work consumes the same induced-flow map. Keep any solver offline.

**Near-term scope that should not block the critical path:** crash work may fix the tick-end buried image with an impact-pose snapshot and a concise report. Delay the full CR-A bundle, CR-B strength thresholds, advanced sound and replay until Gate 2 or a later pilot session establishes priority and CR-03 threshold evidence exists. Landscape, menus and aircraft polish may continue only as reversible, measured parallel work that does not change the baseline flight contract before Gate 2.
