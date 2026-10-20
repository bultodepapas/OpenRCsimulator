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
