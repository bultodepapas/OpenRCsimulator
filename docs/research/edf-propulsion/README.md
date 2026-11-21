# EDF-00: Electric ducted fan research and implementation handoff

**Date:** 2026-11-21. **Repository:** `bultodepapas/OpenRCsimulator`.
**Baseline:** `57abea025f62b20233ca281d58d2acbee4ab8b8e` on `main`.
**Branch:** `research/edf-propulsion-2026-11-21`.

This research defines an EDF version of the existing **Vantage Jet / SebArt
Avanti S A200**, plus larger fan experiments. It delivers a reviewed plan and
reproducible planning calculations. It does not implement a runtime EDF, alter
generated aircraft, certify a physical installation or claim flight validation.

## Read in this order

| Document | Purpose |
| --- | --- |
| [Fourteen scientific studies, EDF-00-R3](scientific-literature-2026-11-21.md) | Critical full-text review of thrust, electrical/shaft power, dynamics, geometry and installed behavior; corrections, measurement boundaries and concrete plan changes. |
| [Twenty investigations, EDF-00-R2](native-research-2026-11-21.md) | Physics, native architecture, games, tools, GitHub and Reddit; 43 external source entries and nine community leads, with decisions and future experiments. |
| [Native execution and product design](native-runtime-design.md) | Complete native numerical path, prepared memory, atomic world/input state, strict EDF admission, stand/preview/flight/debrief and performance scope. Proposed, not implemented. |
| [Independent audit, EDF-00-R1](external-audit-2026-11-21.md) | Fifteen findings against the original proposal, corrections, additional sources and the verified inherited CI blocker. |
| [Implementation plan](../../plans/edf-propulsion.md) | Authoritative EDF-00…15 steps, substeps, owners, interfaces and completion gates. |
| [Physics and primary sources](physics-and-sources.md) | Original thirty-reference register, fan candidates, force/torque/energy equations and the R3 performance/consumption contract; further scientific sources are in the R3 register. |
| [Repository audit](repository-audit.md) | Fifteen classified findings with current source paths and bounded repair/integration proposals. |
| [Validation matrix](validation-matrix.md) | Forty software/numerical/product cases, six physical cards, flight maneuvers and qualification policy. All future gates are pending. |
| [Reproducible calculations](calculations.json) | Generated energy, mass, area and analytic counterexample values with embedded limitations. |
| [Calculation tool](../../../research/edf-propulsion/README.md) | Standard-library regeneration and freshness check. |

## Engineering recommendation

Introduce a distinct `electric_ducted_fan` family, with final naming frozen in
EDF-01. Reuse the established battery/motor conventions, float64 mechanics,
shared RK4, atomic event transaction and replay identities. Add a pure fan and
installation law that returns **shaft load separately from the net installation
force and moment**. Stator recovery, rotor acceleration and gyroscopic reaction
must each appear exactly once. Implement new runtime behavior in C++/Godot-native
code and extend the shared kernel with a generic **complete native numerical
tick**. Current stage-only acceleration does not cover integration, stateful input,
sampled weather/RNG or all world/session effects. EDF flight admission requires
those native capabilities and refuses missing ones; the reference is an explicit
verification oracle, with existing non-EDF fallback unchanged. Retain exact
qualification gates and measure performance on actual native packages.

The first reference is a **128 mm DS-98 / DSM6036-600 class** installation. A
**152 mm DS-130** and **195 mm DS-215** are separately specified experiments, with
the 195 mm unit intentionally testing a much larger powertrain. Their model
numbers are not their diameters. Manufacturer ranges do not establish matched
operating points or A200 installed performance. The complete comparison and
citations are in [the source study](physics-and-sources.md#2-large-fan-candidates).

Keep the turbine jet's identity and sources. Generate an experimental EDF sibling
with its own inventory, pack, ducts, maps, CG, inertia and installation metadata.
A labeled simulation can use explicit estimates; physical realism requires
applicable measurements. Start the large fan cases on a stand before admitting
an airframe installation. Neither an old turbine outlet surrogate nor nominal
battery energy establishes physical fit, endurance or current capability.

## Review and finding disposition

The lead read root and scoped agent rules, `docs/SUBAGENTS.md`, the relevant
physics/data/session/native guides and current source. Three read-only specialist
assignments covered primary-source research, propulsion integration and the
repository's **Good Enemy** adversarial role. Requested model routing is not
treated as independently verified runtime metadata. Helpers made no repository
mutations or test/application launches; the lead owns the integrated documents.

The review produced concrete changes:

- Separate rotor shaft torque from whole-installation torque, preserving correct
  ideal-stator cancellation and existing coupled-body reactions.
- Distinguish aerodynamic fan-load power, motor shaft power and DC input,
  especially during spool transients; retain signed windmill work.
- Define bounded estimated physical continuation, locator-only numerical probes
  and unsupported physical reverse-breakaway refusal. The domain-quality transport must be prototyped before all-stage
  claims; endpoint-only reporting must disclose its narrower scope.
- Reuse the geometric centerline-jet layout where appropriate, explicitly author
  internal-fan contact, and prevent implicit propeller/audio/fuel fallbacks.
- Label casing-based tangential Mach arithmetic as a proxy, preserve conflicting
  manufacturer motor/cell-range and battery-mass data, and avoid unsupported fit,
  pack-current or endurance claims.

Two existing-source findings merit separate reproduction and repair: omitted
battery thermal stiffness in admission (EDF-A01) and the turbine's negative
low-RPM mass-flow extrapolation/singularity (EDF-A02). The calculator demonstrates
the algebra; it does not establish a failing shipped flight. Other findings are
contract gaps, disclosed approximations or conditional EDF integration risks.

**EDF-00-R1** independently challenged the published research candidate
`719c3cc6b8e3ac32d2f62e08b6df9b646925361f` with three fresh read-only reviewers.
Its [fifteen proposal findings](external-audit-2026-11-21.md#findings-and-dispositions)
correct the event-probe domain, existing spatial-wind integration, windmilling
and finite-pack trim, catalog/smoke/audio routes, exact coupled energy and
scoped passivity, fixed-RC storage, production-step accuracy and physical-evidence
policy. The revised plan has separate synthetic-software and measured-physical
dependencies; unavailable hardware measurements cannot silently block the
declared experimental software slice or be replaced by interpolation evidence.

**EDF-00-R2** adds twenty distinct investigations against `9d17c29e`, three
read-only specialist assignments and a fresh Good Enemy review. Its source
register and Reddit ledger distinguish inspected primary material, original
upstream reports and community hypotheses. Useful findings are integrated into
the owning EDF steps, the native design, EDF-A15 and T30–T36. The most consequential
changes are complete native capability closure; checkpointed mutable world and
raw-input/weather state; interior-map passivity; explicit averaged ESC/source-off
semantics; bounded prepared memory; separate full-callback measurement; and a
native Godot stand, installation preview and debrief. No new runtime dependency,
skill, plugin, live CFD solver or parallel tick is introduced by this research.
Closing review also made pre-/post-damage restores and input tick assignments
explicit, removed stale EDF fallback wording, and distinguished the proposed
native ordinary-tick publication guard from current reset/restore-only guards.
The opt-in event/world visibility change needs its own qualification; legacy
listener behavior remains outside that proposed change.

**EDF-00-R3** critically examines fourteen distinct scientific studies against
`e4b42d06`, with electrical-performance and installed-flow specialists plus a
fresh Good Enemy source review. Corrections and related publication versions
are not counted as independent experiments. The useful findings are integrated
into EDF-01…04/08…11, the native design, a precise metric contract, T37–T40 and
V01–V06. They distinguish electrical/shaft/flow power, static N/kW versus useful
efficiency, accepted mission Wh/Ah, geometry conventions and complete-aircraft
versus propulsor loads. Source arithmetic/unit discrepancies and unverified
geometry are recorded without inventing replacement data. No matched physical
map or endurance result for the Vantage Jet is supplied by these papers.

## Verification and delivery

The original EDF-00 delivery (`719c3cc6`) passed these local research checks on
**2026-11-21**. This is the original verification record, not the revised count:

| Check | Result / scope |
| --- | --- |
| Existing documentation link/anchor routines | Passed: nine Markdown files, 100 newly introduced link occurrences, including 75 local targets/anchors; zero errors. |
| Named existing test entry points | Every named existing test file in the matrix resolves in the baseline Git tree; proposed EDF tests are explicitly separate. |
| `calculations.py --check` | Passed in the worktree and a fresh shared Git checkout: regenerated JSON agrees within the declared numeric comparison. |
| Python AST parse | Passed for the calculation script. |
| `git diff --cached --check` | Passed for the staged delivery. |
| Specialist / Good Enemy review | No remaining blocking research-plan findings after the recorded corrections; implementation gates remain open. |

**EDF-00-R1 revised-candidate verification, 2026-11-21:**

| Check | Result / scope |
| --- | --- |
| Existing documentation link/anchor routines | Passed: all links in seven EDF Markdown files plus new links in three shared indexes/decision files; 125 link occurrences, 90 local targets/anchors, zero errors. Of these, 33 occurrences (23 local) are new against the original research commit. |
| Source/test inventory | S01–S30 are present. All 29 named existing test entry points resolve in the baseline Git tree; four named EDF tests remain proposals. |
| Independent analytic recomputation | Passed: 28 numeric assertions across the six new oracle groups, including a separate carrier-plus-absolute-rotor derivation of energy/work; no runtime implementation was invoked. |
| `calculations.py --check` and Python AST | Passed for the revised script/report in the worktree. The freshness comparison verifies reproducibility, not independent model accuracy. |
| `git diff --cached --check` and scope | Passed; twelve research/documentation files changed, no runtime, aircraft data or CI policy paths changed. |
| Fresh specialist / Good Enemy closing reviews | Physics, integration and evidence/acceptance corrections incorporated; no remaining blocking issue within the source-only review scope. Future gates remain pending. |

**EDF-00-R2 revised-candidate verification, 2026-11-21:**

| Check | Result / scope |
| --- | --- |
| Existing documentation link/anchor routines | Passed: all links in nine EDF Markdown files plus new links in three shared indexes/decision files; 265 occurrences, 125 local targets/anchors, zero errors. Of these, 143 occurrences (38 local) are new against R1. |
| Research and acceptance inventory | Exactly R2-01…20, N01…43 and nine community leads; T01…36, six physical cards, EDF-A01…15 and the original S01…30. All 29 named existing tests resolve in the baseline Git tree; four named EDF tests remain proposals. |
| Independent arithmetic | Passed: 24 assertions across six groups—ideal limiter, winding-mode RK4, tuple blending, cell interior, audio frequencies and tick budget. The limiter was independently checked by high-precision bisection and circuit closure; no simulator implementation was invoked. |
| Whitespace and change scope | `git diff --cached --check` passed; eleven Markdown documentation files changed. No runtime, generated aircraft, native source or CI policy changed. |
| Native specialist and fresh Good Enemy closing review | Concrete findings corrected; no remaining blocking issue in the source-only review. Full native execution, physical behavior, audio/visual quality, packages and performance remain unqualified. |

**EDF-00-R3 revised-candidate verification, 2026-11-21:**

| Check | Result / scope |
| --- | --- |
| Existing documentation link/anchor routines | Passed: all links in ten EDF Markdown files plus new links in three shared indexes/decision files; 295 occurrences, 136 local targets/anchors, zero errors. Of these, 37 occurrences (18 local) are new against R2. External citations are scanned as links; this is not a claim that every external URL was availability-tested. |
| Research and acceptance inventory | Exactly P01…14 and three supplementary X entries; T01…40 and six physical cards. The original S01…30, EDF-A01…15 and R2 twenty-investigation/43-source/nine-lead inventory remain intact. All 29 named existing tests resolve; four named EDF tests remain proposals. |
| Independent arithmetic | Passed: 22 assertions across coefficient conversions, reference-area normalization, source arithmetic, accepted-interval consumption and installed-force composition. No simulator implementation was invoked; the apparent paper annulus comparison does not resolve its unknown geometry conventions. |
| Calculation freshness | Existing `calculations.py --check` passed; the unchanged JSON remains reproducible planning arithmetic. |
| Whitespace and change scope | `git diff --cached --check` passed; nine Markdown documentation files changed. No runtime, generated aircraft, native implementation or CI policy changed. |
| Specialist and Good Enemy closing review | Power and installed-flow source checks completed. The material turbine-versus-EDF consumption-boundary finding was corrected and reread; no remaining material issue within the source-only review scope. All implementation and physical gates remain pending. |

These link-check records use the repository's `tools/ci/check_docs.py` routines
against Git objects, so sparse materialization cannot conceal a missing tracked
target. R1/R2/R3 check every link in their EDF documents and newly introduced links in
the shared indexes/decision record, without reclassifying unrelated legacy links.

The calculation freshness check reproduces the committed JSON. These are research-artifact checks, not
Godot, native, aircraft, physical or performance qualification. No local runtime
suite is claimed for this documentation-only investigation.

The research is published in [draft PR #18](https://github.com/bultodepapas/OpenRCsimulator/pull/18).
During EDF-00-R1, the original candidate's CI was observed to **fail release
preflight because 13 required Godot UID sidecars were missing in the underlying
baseline**. Application/native/export/visual jobs were skipped. The
[audit record](external-audit-2026-11-21.md#ci-blocker-verified-during-the-audit)
contains the run, exact paths, inheritance proof and owning-source action.
The latest PR checks own subsequent remote status; skipped jobs are not passes.
Existing required CI and shadow policy remain unchanged. EDF-01…15 and all T/V
implementation/physical gates remain pending regardless of documentation CI.

## First implementation change

Complete EDF-01's model/data and generic native-boundary prototype, then build
the small C++ analytic stand with separate torque/wrench outputs. Prove signs,
zero-speed behavior, power accounting, interpolation interiors and refusal paths.
Qualify the complete native input/weather/world transaction before connecting
the A200 product flight. The plan defines the subsequent electrical, generated
aircraft, native Godot experience, physical and package gates.
