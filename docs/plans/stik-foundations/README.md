# Five foundations for the Ugly Stik

**Date:** 2026-11-15. **Status:** five proposed engineering plans, ready for bounded implementation; the planned runtime improvements are not delivered by these documents. **Planning baseline:** `6616ec37350bf217b58f598c32ea86c58f611586` on `audit/ugly-stik-flight-physics-2026-11-15`. The audited application tree is `565e4a839e63c1b65064d0da4e6e1366b13ebbc7`. Later work on `main` is not implicitly audited; reconcile the intended integration base before starting a slice.

This program selects five significant improvements from the [24 investigations and two follow-ups](../../research/ugly-stik-flight-physics-2026-11-15/research-round-02/README.md). It turns their findings into implementation boundaries, research decisions, small PRs and explicit acceptance. It does not create five new aircraft variants or five permanent development branches.

The [ownership registry](../../README.md#tracks-plans-and-step-ids), [ROADMAP](../../../ROADMAP.md), [aircraft contract](../../AIRCRAFT_CONTRACT.md) and linked owner plans keep authority over runtime behavior, step IDs and release gates. **P1–P5 and local slice numbers are navigation labels only.** Allocate implementation IDs in the existing owner's namespace when work begins. This is the authoritative home for the five-plan selection and sequencing; each linked plan owns its scoped proposal, and accepted behavior belongs in its existing operating guide.

## The five selected improvements

| Plan | Meaningful outcome | Why it earns a place | First bounded delivery |
| --- | --- | --- | --- |
| **[P1 — Controls and feel](01-controls-and-feel.md)** | The player's command, calibrated range, actuator response and aircraft response can be distinguished and measured. | Input and actuator errors can look like bad aerodynamics; the retained endpoint counterexample is concrete. | Characterize existing input observations and calibration traces, then fix one demonstrated policy gap with focused device/profile coverage. |
| **[P2 — Aircraft identity and provenance](02-aircraft-identity-and-provenance.md)** | Two clear stock Stiks, stable technical identities and one traceable authoring path for every accepted installation. | Future work otherwise risks duplicate variants, mislabeled pack/ideal results, broken saves and independently drifting generated files. | Close the route/accepted-source map using the existing catalog and `trace_meta()`; add only missing propagation or conformance. |
| **[P3 — Validated flight model](03-validated-flight-model.md)** | Better-supported power-off glide and powered tail authority, followed by bounded aero improvements. | Stopped-propeller and wash gaps have concrete code evidence and meaningful control/energy consequences to investigate. | Independent sign/energy/breakaway fixtures and identity-pinned baseline; opt-in physical candidates follow. |
| **[P4 — Experiment and product evidence](04-experiment-and-product-evidence.md)** | Flight cards, captures and landing statistics express what was actually observed and which aircraft/source produced it. | Misleading durations, solver labels or incomplete captures can produce false confidence in every later tuning decision. | Version maneuver horizons and metric availability, carrying early termination through serialized reports and comparisons. |
| **[P5 — Deterministic performance](05-deterministic-performance.md)** | Smoother complete flight on a declared 1080p target, with protected numerics and a repeatable regression comparison. | Performance must remain predictable as physics and presentation grow; current cost candidates need attribution. | One matched workload using existing GOD/debug/trace tools, then one attributed optimization or a documented no-change result. |

Selection is based on player impact, strength of existing evidence, dependency value, reuse and a bounded first step. It is an engineering judgment, not a measured ROI ranking. These five cover the whole route from physical control motion to accepted command, admitted aircraft model, simulated response, presentation and evidence.

## Why this sequence

**Start implementation with P4 slice 1.** It is a contained evidence repair: a requested future sample must not silently become the final available sample after early termination. It can proceed using the current accepted metadata and existing runner/comparator improvements. It does not require new aircraft measurements or completion of the other four plans.

In parallel, P1's initial characterization and P2's route/source map can proceed with distinct file ownership. P3 can build independent analytical fixtures and organize available measurement inputs; lack of hardware does not block numerical contract work. P5 can characterize the current target before new physics is added. Shared session edits and rendered/hardware campaigns must be serialized.

| Milestone | Work that can proceed | Exit evidence and consequence |
| --- | --- | --- |
| **A — Trust the baseline** | P4 horizons; P1 observation/calibration characterization; P2 accepted identity map; P3 analytic fixtures; P5 baseline workload. | Explicit completeness and source identity, preserved baseline/replay, known versus missing observations, and attributed costs. No physical realism claim yet. |
| **B — Close bounded software gaps** | P1 justified calibration/recovery repair; P2 metadata propagation/conformance; P4 trim/modes, capture producer and Electric statistics; P5 missing matched-tape comparison support. | Focused behavior and compatibility checks, native qualification only for actual exercised paths. The real hardware/measurement campaign has an unambiguous configuration. |
| **C — Evaluate meaningful physics candidates** | P3 signed propeller/breakaway and optional tail wash as separate candidates; isolated induced-flow research; P1 loaded-servo and pilot protocol. | Numerical conservation/refinement, held-out component/flight evidence, command identity and uncertainty. Each candidate has a separately recorded disposition. |
| **D — Qualify and promote** | P5 complete-workload cost; P4 truthful final reports; P2 compatibility and generated proof; physical/pilot/native gates with owners. | Promote only the specific configuration and claim supported by evidence. An unresolved gate leaves that claim open; an isolated candidate can remain experimental. |

These are coordination milestones, not global barriers or calendar promises. Only the evidence dependencies stated for a specific change or promotion gate that change. P4 card and capture-producer work using existing accepted metadata does not wait for P2/P5 completion, cost attribution or target hardware; native capture, physical and performance claims still require their respective observations. Re-estimate a slice after its baseline experiment; do not estimate a whole physics rewrite from a small tool change. Use one writer per shared path and one owner for each live app/controller/hardware session, following [the collaboration guide](../../SUBAGENTS.md).

## Interface ownership: avoid five competing solutions

| Boundary | Producer / decision owner | Consumers and rule |
| --- | --- | --- |
| Physical input observations and command shaping | P1 with existing D6/F/UI owners | P3 uses accepted commands; P4/P5 retain input/profile/tape identity. Cached samples never become fabricated independent device reports. |
| Accepted aircraft, source and installation identity | P2 with AS/DATA/session/AE owners | P4 cards/captures and P5 manifests consume existing accepted metadata. They do not create parallel catalogs or reconstruct old identity from current files. |
| Numerical and physical laws | P3 with D/G/EL/BAT/GP/VAL owners | P1 does not compensate unmeasured aerodynamic defects with expo; P5 distinguishes exact optimizations from changed-law candidates. |
| Completion, comparison and product evidence | P4 with FT/FL/SC/UI-FS owners | Other plans use one documented meaning for complete/partial/unknown evidence. Existing format-specific readers remain; no universal evidence platform is required. |
| Cost, workload and target qualification | P5 with VQ/DT/GOD/H/NK owners | Other plans supply representative cases. Graphics scaling leaves the simulation unchanged; performance is measured at the complete affected workload. |

Producer semantics and consumer rollout can share a small coordinated PR when required. These boundaries do not imply waiting for an entire plan before using a field or workflow that already exists.

## Research-to-plan traceability

| Plan | Main retained investigations | Earlier backlog relationship |
| --- | --- | --- |
| P1 | R01–R04, R16, R18 and pinned-engine S2-01 | I01/I02 and the controls/actuator portion of I06 |
| P2 | Variant/route audit; R08–R10, R21, R23 | Accepted-source producer seam for I04; authoring/provenance support for I06–I10 |
| P3 | R05–R12, R16–R18 and physics contracts S2-02 | I06–I10 |
| P4 | R13/R14/R17/R19–R21 and retained early-floor/statistics evidence | I03–I05; preserves already delivered E01–E03 |
| P5 | R15/R16/R22–R24 | I11/I12; reuse decisions support other plans where needed |

The [research integration backlog](../../research/ugly-stik-flight-physics-2026-11-15/research-round-02/integration-backlog.md) remains the dated research handoff. These five plans refine its implementation sequence without declaring those open items complete. No new literature campaign was needed to select them; applicable primary sources and limitations remain in the linked investigations.

## Promotion and change control

Every implementation PR should name the owning step, exact baseline, falsifiable change hypothesis, affected consumers, smallest useful proof, compatibility behavior and rollback. The proof must correspond to the claim:

- A mathematical fixture verifies a stated computation; it does not establish real Stik coefficients.
- Complete exact replay establishes the promised same-identity behavior. Candidate replay and recovered prefixes have different meanings, as defined in [flight logging](../../FLIGHT-LOGGING.md).
- Native controller/render/package results qualify only the recorded device, platform and route.
- Independent installed measurements and held-out maneuvers support physical accuracy within their domain.
- Pilot assessments support perceived handling under a declared, preferably counterbalanced protocol; they do not replace the numerical or measurement evidence.
- Repeated matched target-host comparisons support performance claims. An isolated helper or historical host result does not establish current whole-flight improvement.

Keep physical uncertainties visible, use one authoring source and preserve old artifacts at their original identity. Avoid default promotion of several changed mechanisms together; that would obscure which change caused a result. Compare one explicit candidate first, then qualify the combined configuration deliberately. Each plan contains its relevant rollback and legacy-data treatment.

The initial work excludes aircraft-ID deletion, wholesale schema/framework replacement, a new renderer or kernel port, lower physical tick rate, unmeasured coefficient retuning, and automatic import of external dependencies. These are scope decisions for the proposed slices, not permanent prohibitions. A later identified requirement needs its own evidence and owner decision.

## Completion of the planning task

The five detailed plans identify current evidence, open questions, alternatives, implementation slices, source boundaries, acceptance cases and rollback. The runtime work they describe remains proposed. Documentation review and link/whitespace checks qualify this delivery; previously recorded flight-tool tests remain historical and are not represented as new execution.

**Planning verification:** an independent Good Enemy architecture/source review found no remaining high- or medium-severity blocker within these six documents after two corrections: the wind-driven breakaway fixture explicitly uses motor-off aerodynamic torque, and coordination milestones do not block independent producer/report work on unavailable target hardware. The repository's existing Markdown parser and Git-object target/anchor checker validated **132 local links** across all six new documents and the added links in four existing guides. The staged whitespace check passed. This is documentation/source review, not new simulation, physical, native or pilot execution.

When a slice is implemented, update the owning track's status and operating guide, attach dated proof there and link it from this proposal while it remains active. When the program is complete or superseded, consolidate the useful decisions into the canonical guides and remove the superseded active plan pages according to the [documentation conventions](../../README.md#conventions-for-documents).
