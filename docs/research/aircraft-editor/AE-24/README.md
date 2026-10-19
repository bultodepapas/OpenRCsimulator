# AE-24 — presentation, portable builds and bounded analysis

**Date:** 2026-10-19. **Status:** implemented software baseline; broader AE acceptance remains open. The [Workshop guide](../../../AIRCRAFT-WORKSHOP.md) owns current behavior and the [consolidated plan](../../../plans/aircraft-editor.md) owns remaining work.

## Delivered

- Appearance and Smoke inspectors use the physical editor's shared history, dirty baseline and immutable revision. Solid authored regions, fixed EN/ES registration, per-emitter colors, timed palettes, fan/cloud/ribbon, bursts/pulses and six presets are available where registered. Invalid or unapplied text blocks Save/Test fly; Review issues focuses it and Back cancels it.
- Stationary preview playback owns a separate World3D and 240 Hz visual clock. Play/Pause/Restart and preview wind do not advance a flight. Hiding the preview pauses playback. Source preview is explicitly illustrative.
- Saved record v2 carries profile v1. Companion v2 pins seven presentation sources and Godot 4.7.2; separate exported presentation proofs preserve physical model-manifest identity. Materials and labels are instance-owned. Cosmetics preserve the physical trial identity and resolved bytes; trace presentation identity is separate.
- Strict bounded JSON bundles export exact data/pins and import a new local copy. `--aircraft-variant` freezes a detached bundle without importing it. Missing/stale dependencies refuse before activation. Existing trial rollback/return behavior is retained.
- Runway starts use the actual frozen candidate, field, weather and accepted session route. Eight catalog defaults qualify; Stik 150%/200% runway requests refuse while airborne remains available. No solver formula or golden flight was changed.
- Shared parameter metadata supplies bounds/units/capabilities. Source-only static reports, fixed input tapes and bounded grid/seeded sweeps use the existing compiler/session. They report software estimates/results, not physical performance validation.

- Library search filters small cached summaries. Favorites use separate bounded UUID metadata; missing favorites remain removable. Compatible copy lists applied/skipped settings, rejects stale review and preserves physical recipes/source records through one Undo action.

## Verification

Native runtime: Windows Godot **4.7.2 `ed1daf0bf`**, Compatibility/OpenGL, RTX 3090 driver 617.42. Commands are in [TOOLS](../../../TOOLS.md#aircraft-workshop); selected inputs are identified by [source hashes](sources.json).

The [final check summary](checks/final-summary.json) records 39 passing suites, 1,089 parsed scripts, nine native captures and matching hashes for all 55 selected source files.

| Proof | Result and boundary |
| --- | --- |
| [Workshop/menu results](checks/workshop/results.json) | 18 Workshop and 11 menu suites passed, including full saved payload, palette/inscription buffers, detached CLI, trial/return, immutable storage and responsive dialogs. Favorites pass 67 checks, transfer 18, and reuse UI covers Cancel/apply/stale review, source preservation, shared Undo and missing-favorite removal. |
| [Rendering/start results](checks/render-start/results.json) | Customization, source/package proofs, legacy/profile smoke and runway/prop-strike regression suites. Mutation diagnostics are expected inside refusal tests; the result manifest records failures separately. |
| [App parse manifest](checks/parse-results.json) | 1,089 app scripts parsed; zero failures. Subsequent changed scripts were parsed through their focused suites. |
| [Working-tree links](checks/doc-qa-working.json), [local-clone path check](checks/doc-qa-clone.json) | Links/anchors and command paths checked (exact counts in the manifests); zero issues. The local no-checkout clone uses HEAD's path inventory with current working files overlaid. This verifies documentation paths, not a clean platform build. |
| Generators | Physical model manifests (five families), Workshop descriptors (eight configurations), and customization companion passed `--check`; customization generator tests passed 8/8. Physical manifests were not regenerated for cosmetic changes. |
| [Native captures](#native-captures) | Nine EN/ES captures at 720p/1080p and 100/150/200% text; key actions/dialogs stayed inside the canvas. Visual inspection supplements geometry checks. |
| [GPU lifecycle/rates](gpu/metrics.json) | Actual particles at 30/60/144 presented FPS; color event tick 96 at every rate, both old/new colors visible, pause image stable after settling, reset empty, stop retains fading puffs, 8.9 s offscreen aging empty, history at most 42/44 samples, allocation stays 768. This is one renderer/device, not a performance qualification. |
| [CLI build](analysis/cli-build.json), [flight trace](analysis/cli-build.csv) | Real direct-route launch accepted the complete saved build and wrote 61 rows through tick 60. Physical and presentation identities are distinct. |
| [Static](analysis/experiment-static.json), [glide](analysis/experiment-glide.json), [sweep](analysis/experiment-sweep.json) | Documented runner commands succeeded. The glide completed 60 ticks with engine/source off. Unit coverage also runs level/glide for all eight airplane defaults, asserting actual start/input/environment pins. |

The full `app/test.sh` physics/offline battery was not run. Its descriptor checkout helper creates disposable Git commits and was excluded under the no-commit instruction. Generator checks, focused runtime tests and app parsing were run directly. No physical/device/pilot acceptance is inferred from these software checks.

The shared tree received external work and commits during the task. This evidence identifies selected source files and bounded runs; it is not a frozen whole-repository release audit. This agent team did not stage, commit, push or alter Git history.

## Native captures

- [EN appearance, 1080p/100%](native/appearance-en-1080.png): actual fixed registration on the fuselage; stock materials are identified as Stock.
- [ES appearance, 720p/200%](native/appearance-es-720-200.png): scrolling compact inspector, persistent Save/Test fly and View/Edit.
- [ES smoke, 1080p/150%](native/smoke-es-1080-150.png): localized compact controls and timed palette selection.
- [EN Twin Ribbons, 1080p/100%](native/smoke-en-1080.png): separate red/blue wingtip trails at the 2 s preview clock.
- [ES Rainbow Burst inspection, 720p/200%](native/smoke-preview-es-720-200.png): fan/palette playback with compact camera menu.
- [ES bundle file picker, 720p/200%](native/bundle-import-es-720-200.png): localized filename list, nested modal and retained editor. Native review exposed clipped thumbnail names; the final list layout corrects them.
- [EN source preview, 1080p/100%](native/source-preview-en-1080.png): authored exhaust outlet with an explicitly illustrative running-engine sample.

- [ES saved-library actions, 720p/200%](native/library-reuse-es-720-200.png): selected favorite, bounded name clipping and scrolling actions.
- [ES copy review, 720p/200%](native/profile-copy-es-720-200.png): compatible smoke and explicitly skipped material mismatch; Cancel has initial focus.

Each PNG has an adjacent geometry JSON. Captures use a separate empty library and save no player variants. GPU probe images are synthetic renderer fixtures with an unlit black background; editor captures exercise the lit model. Neither qualifies dense overlapping smoke during a real flight.

## Remaining acceptance

Patterns/decals and spinner/prop accents, rotorcraft editing, moving preview passes/scrub, bounded thumbnails and explicit migrations remain planned. Thumbnail production needs a separate cancellable renderer; reusing the interactive preview would replace the active draft/camera. Native dense overlap/frame/GPU cost, platform/export journeys, hardware/accessibility/playtests, wider scale/refinement, twenty-airframe onboarding and source-backed mass/CG/hardware editing remain open.

The final [CLI teardown log](analysis/cli-final.log) reports four retained audio stream/playback objects (MP3/WAV), including with `--soundscape=off` and the Dummy driver. Empty-profile controls also reproduced audio retention. This is an unresolved audio teardown gap, separate from the passing GPU particle lifecycle probes. Accepted-source gating and the global smoke-off route have focused follow-up coverage.

An initial scale probe was rejected as evidence because it checked flyability after a fallback instead of the committed requested start. Only the authentic `WorkshopStartQualification` suite and its explicit accepted-route assertions support the runway statements above.
