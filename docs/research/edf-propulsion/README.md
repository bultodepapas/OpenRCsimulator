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
| [Implementation plan](../../plans/edf-propulsion.md) | Authoritative EDF-00…15 steps, substeps, owners, interfaces and completion gates. |
| [Physics and primary sources](physics-and-sources.md) | Twenty-four primary references, fan candidates, force/torque/energy equations, sizing and unresolved identification. |
| [Repository audit](repository-audit.md) | Eleven classified findings with current source paths and bounded repair/integration proposals. |
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
- Define bounded estimated continuation and unsupported reverse-breakaway
  refusal. The domain-quality transport must be prototyped before all-stage
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

## Verification and delivery

Local verification on **2026-11-21** passed for the final research candidate:

| Check | Result / scope |
| --- | --- |
| Existing documentation link/anchor routines | Passed: nine Markdown files, 100 newly introduced link occurrences, including 75 local targets/anchors; zero errors. |
| Named existing test entry points | Every named existing test file in the matrix resolves in the baseline Git tree; proposed EDF tests are explicitly separate. |
| `calculations.py --check` | Passed in the worktree and a fresh shared Git checkout: regenerated JSON agrees within the declared numeric comparison. |
| Python AST parse | Passed for the calculation script. |
| `git diff --cached --check` | Passed for the staged delivery. |
| Specialist / Good Enemy review | No remaining blocking research-plan findings after the recorded corrections; implementation gates remain open. |

The check scope is the new research/plan/tool documents and newly introduced
links in the shared documentation indexes and decision record. It uses the
repository's `tools/ci/check_docs.py` link/anchor routines against the Git tree,
so sparse materialization cannot conceal a missing tracked target.

The calculation freshness check reproduces the committed JSON. These are research-artifact checks, not
Godot, native, aircraft, physical or performance qualification. No local runtime
suite is claimed for this documentation-only investigation.

The branch is intended for a draft PR against `main`. The PR's checks own the
current remote CI status; this snapshot does not claim a completed CI run.
Existing required CI and shadow policy remain unchanged. EDF-01…15 and all T/V
implementation/physical gates remain pending regardless of documentation CI.

## First implementation change

Complete EDF-01's force/torque/energy/data and diagnostic-transport specification,
then build a small analytic propulsion stand with a pure fan-map evaluator and
separate torque/wrench outputs. Prove the signs, zero-speed behavior, power
accounting and rejection paths before connecting the A200 session. The plan
defines the subsequent electric, native, aircraft, product and flight changes.
