# AS-06–14 authoring foundation

**Date:** 2026-10-13. **Scope:** shared interfaces for the current seven physical configurations and five visual families. This is a software compatibility delivery, not completion of every AS-06–14 acceptance gate. The [active plan](../../../plans/aircraft-standardization.md#implementation-sequence) lists remaining work; the [aircraft contract](../../../AIRCRAFT_CONTRACT.md) is the operating guide.

## Implemented

- One versioned module registry drives Python and GDScript classification and Workshop assertions. Unsupported combinations remain rejected by the physical contract and loader.
- Generated visual manifests connect catalog families to authoring sources, datum, hinges, rotor, gear and existing crash metadata. Shared rendering consumes the manifest; the three Stik configurations reuse one visual family. Conventional command/hinge/aerodynamic sign conversion has one implementation.
- Workshop v2 pins the exact model manifest. The explicit v1 reader retains older saved variants. Dependency resolution is a launch check, so a missing visual does not hide its saved variant; a frozen trial cannot silently substitute another visual revision.
- Single-installation propulsion preparation selects the existing callbacks before state initialization. Read-only observations expose family, law, actual RPM and state layout. Contact preparation validates supports, probes and rotor geometry and exposes the existing soft/terminal/strike and wheel-profile policy.
- A catalog-discovered preflight checks actual model instances, rest/full-travel controls and source dependencies. Exported packages carry verified exporter-input proof bytes and require actual compiled/imported resources to resolve. Missing or malformed package proofs cannot use adjacent source files as a fallback.

## Verification

Native Windows, Godot `4.7.2.stable.official.ed1daf0bf`. The retained baseline and candidate use the same binary. This was a shared working tree with concurrent nitro, scenery and vehicle work; source identities are retained rather than treating HEAD alone as the tested snapshot.

| Check | Result and evidence |
| --- | --- |
| Whole-app parsing | 611 GDScripts passed in the integration snapshot; [parse report](parse-report.json). Later changed/new contract scripts also loaded in their final executed suites |
| Fleet compatibility | Seven catalog entries × terminal/soft policies, 240 ticks each; every-tick complete state/load hash and checkpoint replay from tick 120. Exact comparison of [baseline](baseline/fleet.json) and [isolated candidate](compatibility/fleet.json); [verification and source identity](compatibility/verification.json) |
| Model and authoring | Five generated manifests current; Python module/manifest and LF/CRLF fresh Git checkout checks, runtime module 67, manifest 36, rendered contract 291, contact 640, propulsion adapter 198 and conventional-control 26 checks. Detailed commands/results in [integration verification](integration/verification.json) |
| Propulsion and lifecycle | Existing fixed/finite electric, event localization, glow session/lifecycle/trace, coupled shaft, continuous turbine, wheel, checkpoint and contact/strike suites executed through the common harness |
| Workshop | Generated descriptors, compiler, store, v1/v2 readers, frozen binding and actual app/menu/trial integration checked; no new claim of full AE-19 acceptance |
| Packaged models | [Package verification](package/verification.json), [source preflight](package/preflight.json) and [package preflight](package/package-preflight.json): seven configurations pass. Twenty-nine proof mutation checks cover malformed JSON/table/path/hash destinations, missing proof bytes and a package with no proof marker |

Raw focused logs are retained beside each verification report. [Baseline capture](baseline/capture.json) records the original command/source hashes. [Delivery identity](delivery.json) records the engine and final relevant source hashes. The preflight's mesh counts are observations, not performance or polygon-budget acceptance. The package proof establishes source provenance, not a byte hash of platform-specific compiled output.

One final `aircraft_data` execution encountered a concurrently edited `physics/glow/propeller.gd`, could not preload it and was terminated after it stalled. Its [original failure](integration/aircraft_data.log) is retained. The [explicit rerun](integration/aircraft_data-rerun.json) passed all 87 checks. The later live-tree fleet comparison also differs in four cases (the two finite-glow configurations under both contact policies); ten cases still match, every replay passes, and no sources changed during that probe. Eleven physical/profile/trace source files changed since the earlier exact run. The original final report remains failed rather than rewritten green.

To separate these changes, a disposable full app copy retained the final standardization code and restored those eleven files from Git only after each file matched its previously recorded SHA-256 (including its actual line endings). The shared tree was untouched. All previously recorded physics/simulation/input/data sources then matched the first accepted integration snapshot, and all fourteen fleet cases matched the original baseline exactly. [Isolation report](compatibility/verification.json) records every restored path/hash and command. The [earlier integration summary](initial-integration.json) was green; final disposition and explicit live-tree limitations are in `delivery.json`. No new golden flight was recorded.

The existing [controls-reference check](integration/controls_reference.log) still reports missing F6/F7/F8/F9 Help entries. It was observed before and after the control adapter extraction; the control mapping tests and byte comparison passed. That unrelated UI documentation defect is not changed here. This delivery does not claim a green complete `app/test.sh`, new visual/pilot acceptance or target-machine 500 µs performance qualification.

## Reproduce

Run from the repository root with the pinned Godot executable and a fresh evidence directory:

```text
python research/aircraft-standardization/conformance.py --godot <pinned-godot> --out <output> --parse-all --package
```

Add `--baseline docs/research/aircraft-standardization/AS-06-14/baseline/fleet.json` only on the same platform/engine and matching physical source snapshot. Concurrent physical changes may intentionally require a new, independently justified baseline; never rerecord one merely to hide drift. Use `--models-only --package` for focused model/package work. The historical AS-04 `verify.py` remains unchanged; the new conformance entrypoint was given its own name after the recorded runs to preserve those older commands.

## Remaining boundaries

The accepted physical v2 topology is unchanged: conventional controls, one supported propulsion installation, neutral visual-only flaps. A new imported family still supplies a model-side builder; universal data-only Blender import has not been demonstrated. Durable inventory/contact/section IDs, complete landmark/clearance coverage, asset budgets, accepted-tick unified contact events, probe-to-detachable-section binding and a second distinct Blender delivery remain open. Flaps, multiple propulsion installations and selectable new contact laws retain their separate AS-15–18 and owning-track gates.

**Later continuation, 2026-10-13:** [AS-13](../AS-13/README.md) delivers the accepted-tick contact observation, rollback and checkpoint slice listed above. The other boundaries remain in the active plan.


## Shared flight admission (AS-07/14-R1, 2026-10-26)

The physical v2 loader now uses the existing `AircraftModules` classifier after
structural validation. Registry-owned layout, energy, damage-module presence and
gear-module presence checks replace duplicated selection logic. Coupled fuel,
tailless, gear topology, inertia, wake and numerical checks remain in their physical
validators. Inconsistent simulated/inactive flap declarations now fail before a
model can fly. No authored aircraft bytes, physical coefficients, force laws,
normalized model fields, calculation order, checkpoint layout or goldens changed.
The [current contract](../../../AIRCRAFT_CONTRACT.md) owns authoring and maintenance.

The original runtime baseline is `8f60b3964e767c5727524c06c24597843372d051`, on Linux
with Godot `4.8.beta1.official.4d10419ca`. Another session committed the shared tree
during this work; source hashes, rather than HEAD alone, identify the comparison.
[Source comparison](admission-20261026/source-comparison.json) inventories the final
sources and the disposable original-runtime copy: only
`app/physics/aircraft_contract.gd` differs in the covered runtime. Its original bytes
were restored only in that copy, never by swapping the live application.

| Check | Retained result |
| --- | --- |
| Fleet admission and checkpoint replay | [Before](admission-20261026/baseline-fleet.json) and [after](admission-20261026/candidate-fleet.json) are identical: ten catalog airplanes, all offered battery modes, both hull policies; 24 complete cases × 240 ticks and 120 per-tick checkpoint replay checks. [Baseline capture](admission-20261026/baseline-capture.json) records no source drift and unchanged original ideal-mode fingerprints |
| Maneuvers and source cutoff | [Before](admission-20261026/baseline-power-cut.json) and [after](admission-20261026/candidate-power-cut.json): 32 identical, fault-free 960-tick runs, including both finite packs and four synthetic electric configurations. [Comparison](admission-20261026/power-cut-comparison.json). Completion and faults were checked explicitly because this existing probe does not fail its process on a faulted row |
| Contact policies | Seven [original-runtime](admission-20261026/baseline-contacts.json) and [candidate](admission-20261026/candidate-contacts.json) fixtures match byte for byte. The same repaired harness uses `VehicleModel` callbacks in both runs; [identity/comparison](admission-20261026/contact-comparison.json) |
| Contract and shared classification | Expanded production-loader suite: 4,023 checks; runtime classifier: 87; Python/GDScript classifier suite: seven tests. Finite-pack sources and malformed module/coupled-physics cases are covered |
| Schema/loader agreement | [Five tests](admission-20261026/schema-summary.json): 2,070 cases, including 142 valid controls and 23 intentional runtime-only checks; structural preflight accepts all 16 root fixed-wing sources |
| Model and control presentation | Corrected [preflight](admission-20261026/preflight.json): all ten airplanes; independent render-contract suite: 403 checks. Checked logs/reports are retained in `preflight-check/` and `render-contract-check/` |
| Integrated suites | [Initial conformance](admission-20261026/initial-conformance/verification.json): 55 of 57 commands passed, including schema/generators, model manifests, Workshop, controls, propulsion, contacts, checkpoints and exact fleet/contact comparisons. The failed preflight is superseded by the corrected run above; the checkout failure below remains open |

The fleet probe is now explicitly v2: it includes finite-pack configurations and
rejects incomplete forward/replay prefixes. Its Python acceptance tests reject
malformed or duplicate rows, and source inventory includes nested data, command
defaults and collision geometry helpers. Final source-inventory extensions were
checked separately after the initial integration run. The contact harness had
retired callback names; the preflight misclassified elevons as flaps and needed to
retain materials during dummy-renderer teardown. These are tool repairs, not
changes to flight or rendering behavior. Commands and limits live in the
[tool guide](../../../tools/physics.md#aircraft-conformance-and-unchanged-behavior).

Two inherited gates remain open. The [fresh-checkout proof](admission-20261026/checkout-blocker.json)
shows all 43 fixture inputs unchanged from the original revision: F4U physical JSON
has LF bytes while its Git rule requires CRLF, so its exact-source Workshop pin
becomes stale after checkout. Correcting it needs a deliberate generator/source
identity migration; this delivery preserves the existing bytes. The attempted full
`app/test.sh` stops earlier on stale economics `worked-examples.json`; its
[log](admission-20261026/full-suite.log) is retained. The additional unit partition
was stopped after the aircraft-focused suites; it is not a full-suite pass.
[Final verification summary](admission-20261026/summary.json) records syntax,
focused reruns and these limits. No fresh-checkout, package, physical/pilot or
performance qualification is claimed. Exact equality applies to the tested
trajectories on this engine/platform, not every possible flight input.
