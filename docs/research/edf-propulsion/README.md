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
| [Independent audit, EDF-00-R1](external-audit-2026-11-21.md) | Fifteen findings against the original proposal, corrections, additional sources and the verified inherited CI blocker. |
| [Implementation plan](../../plans/edf-propulsion.md) | Authoritative EDF-00…15 steps, substeps, owners, interfaces and completion gates. |
| [Physics and primary sources](physics-and-sources.md) | Thirty primary references, fan candidates, force/torque/energy equations, sizing and unresolved identification. |
| [Repository audit](repository-audit.md) | Fourteen classified findings with current source paths and bounded repair/integration proposals. |
| [Validation matrix](validation-matrix.md) | Twenty-nine software/numerical cases, six physical cards, flight maneuvers and qualification policy. All future gates are pending. |
| [Reproducible calculations](calculations.json) | Generated energy, mass, area and analytic counterexample values with embedded limitations. |
| [Calculation tool](../../../research/edf-propulsion/README.md) | Standard-library regeneration and freshness check. |

## Engineering recommendation

Introduce a distinct `electric_ducted_fan` family, with final naming frozen in
EDF-01. Reuse the established battery/motor conventions, float64 mechanics,
shared RK4, atomic event transaction and replay identities. Add a pure fan and
installation law that returns **shaft load separately from the net installation
force and moment**. Stator recovery, rotor acceleration and gyroscopic reaction
must each appear exactly once. Native and reference implementations share the
same contract; production admission retains the existing qualification gates.

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

Both link-check records use the repository's `tools/ci/check_docs.py` routines
against Git objects, so sparse materialization cannot conceal a missing tracked
target. R1 checks every link in the EDF documents and newly introduced links in
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

Complete EDF-01's force/torque/energy/data and diagnostic-transport specification,
then build a small analytic propulsion stand with a pure fan-map evaluator and
separate torque/wrench outputs. Prove the signs, zero-speed behavior, power
accounting and rejection paths before connecting the A200 session. The plan
defines the subsequent electric, native, aircraft, product and flight changes.
