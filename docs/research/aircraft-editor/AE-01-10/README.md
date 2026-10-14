# AE-01–10 initial Workshop implementation evidence

**Date:** 2026-10-13. **Runtime:** Godot 4.7.2 stable, Windows; native UI captures use OpenGL compatibility on an NVIDIA RTX 3090. This records the initial operational slice, not completion of every AE-01–10 requirement. [Current behavior and commands](../../../AIRCRAFT-WORKSHOP.md); [acceptance reconciliation](../../../plans/aircraft-editor.md#0-implemented-slice-and-remaining-acceptance).

## Recorded checks

| Check | Result | Scope |
| --- | --- | --- |
| [Compiler](compiler.log) | 379 checks, 0 failures | Detached inputs, quantities/geometry/mass/inertia, control/power changes, wheel attachments, capability refusals, 20 unfamiliar IDs, catalog discovery; Stik/Extra 50/75/100/125/150/200% each trim and complete 240 real ticks without a fault; exact no-op trajectory parity |
| [Store](store.log) | 68 checks, 0 failures | Revision persistence, exact snapshots, compiler/dependency pins, malformed input, interrupted index recovery, trash and restore |
| [Descriptors](descriptor.log) | 45 checks, 0 failures | All seven generated bindings, stale hashes/component bindings, unknown identity fixture and schema refusals |
| [Trial identity](trial.log) | 11 checks, 0 failures | Default normalization, cosmetic rename invariance, physical edit fingerprints, frozen drafts, ancestry and incompatible dependency/compiler/descriptor refusal |
| [Workshop UI](ui.log) | 0 failed assertions | Catalog-discovered capability gating, all presets, undo/reset, same-ID revisions, exact saved trial payload, delete/restore/save-after-delete, keyboard, translation and viewport/footer bounds |
| [Real app integration](integration.log) | 0 failed assertions | Home/Pause routes; Stik and Extra trials; frozen F5; world CG/scale/camera; same-phase wreck bounds at 50/200%; return to the exact draft; invalid and post-instantiation startup rollback preserve old flight/recorder/camera/state |
| [Descriptor generation and checkout](checkout.log) | Pass | Generator `--check`; disposable committed fixture cloned with `core.autocrlf=false` and `true`, descriptor SHA checks and wheel bytes identical |
| [Resource import](import.log) | No script/import errors | Native headless project import, including the new scripts/translations |
| [Checkpoint regression](checkpoint.log) | 92 checks, 0 failures | Existing checkpoint suite |
| [Crash masses regression](crash-masses.log) | 27 checks, 0 failures | Existing crash inventory/mass suite |
| [Home](home.log), [Home layout](home-layout.log), [Pause](pause.log), [Help](help.log) | Pass | Existing menu paths adjusted for the new entry, translations, keyboard and repeated open/close cycles |

The compiler retains the aircraft's existing inertia/reference warnings; these are printed in the flight logs and are not hidden. A previous integration harness run reported two ObjectDB objects during immediate teardown; the final harness lets queued UI cleanup settle before quitting. The existing crash-masses regression still reports two ObjectDB instances at exit despite passing its assertions; this evidence does not claim that leak is resolved. The final logs are retained rather than claiming that the complete repository test suite or all physical acceptance gates ran.

## Native captures

The capture script constructs the actual Workshop with an isolated empty library and a 200% Stik recipe. The preview is a still render, not a simulation or mockup.

- [Spanish, 1280×720](workshop-es-720.png): title and trial footer remain visible; the body scrolls to library, presets and comparison.
- [English, 1920×1080](workshop-en-1080.png): recipe, source/variant comparison and save controls. Presets remain accessible by scrolling.
- Native capture logs: [Spanish](capture-es.log), [English](capture-en.log).

## AE-02/03/09/10 robustness follow-up — 2026-10-13

The [initial reproduction](hardening-ui-before.log) failed two new assertions: loading scale 1.33 silently selected 1.25, and a 0.731 multiplier displayed as the slider's rounded value. The editor now retains the physical recipe exactly, shows its intermediate scale and displays the exact slider value without changing the normal interaction step.

Other fixes cover bounded per-source Undo/Redo, whole-drag undo, rejected-load preservation, visible backup recovery and saving a stale draft as a new copy. Updates require the expected revision. Atomic per-variant reservations serialize saves/deletes/restores, and unique temporary filenames avoid temporary-file collisions. Corrupt current manifests or invalid referenced records can recover through a valid backup. Missing historical descriptor pins stay missing, rather than silently binding to a current file.

Trial preparation now rejects coerced metadata, invalid ancestor/revision pairing, missing saved descriptor pins and oversized snapshots. New trial IDs bind the resolved visual family and model-manifest SHA, including legacy descriptors; existing variant revisions are not rewritten. No aerodynamic law or aircraft source was retuned.

| Follow-up check | Result |
| --- | --- |
| [Store](hardening-store.log) | 101 checks, 0 failures; recovery, expected revisions, exclusive reservation/cleanup and blocked overlapping mutations |
| [Trial](hardening-trial.log) | 27 checks, 0 failures; strict metadata, size limit, provenance and resolved presentation binding |
| [UI](hardening-ui.log) | 0 failed assertions; exact-value round trip, bounded history, drag grouping, branch invalidation, stale save/copy, unavailable source refusal and visible recovery/resave |
| [Integration](hardening-integration.log) | 0 failed assertions; existing real app journey plus frozen restart and draft/history preservation |
| [Compiler](hardening-compiler.log) | 379 checks, 0 failures |
| [Descriptor](hardening-descriptor.log) | 54 checks, 0 failures with the current v2 model bindings |
| [Checkout](hardening-checkout.log) | Fresh disposable fixture checkouts pass in both line-ending modes |
| [Import](hardening-import.log) | No script/import errors |
| [Audio lifecycle](hardening-audio.log) | 124 checks, 0 failures; detach/reattach restores dedicated buses and continuous voices across combustion/electric/turbine, plus both finite-glow generators; bus cleanup preserves ownership |
| [Crash regression after audio cleanup](hardening-crash-masses.log) | 27 checks, 0 failures; no ObjectDB-leak warning at shutdown |

The [audio reproduction](hardening-audio-before.log) exposed another lifecycle defect: detaching the old flight removed its buses and stopped its loops, but reattachment did not recreate them. `Soundscape._enter_tree()` now rebuilds its owned buses, schedules continuous loops only after positioning and fades back in. Transient wildlife events are not replayed. The same reentry restarts the finite-glow generator without changing the simulation.

Verbose integration diagnostics identified the two shutdown objects as `AudioStreamMP3` and `AudioStreamPlaybackMP3` for lake ambience. The soundscape now signals before releasing its buses, and the flight stops the external lake player at that boundary. The final [verbose integration log](hardening-integration.log) has no ObjectDB-leak or script-error warning. The historical warning above remains part of the earlier evidence, not a claim that the final lifecycle still leaks.

Updated native captures: [Spanish 720p, 133.5%](hardening-es-720.png) and [English 1080p](hardening-en-1080.png), with [Spanish](hardening-capture-es.log) and [English](hardening-capture-en.log) renderer logs. Use `--scale=1.335` with the capture command below for the intermediate-size example.

The reservation tests hold a competing reservation and verify that no update/delete/restore can pass it; they do not constitute a power-loss or distributed-filesystem stress test. An abruptly terminated writer may leave an orphan reservation; the current behavior remains fail-closed, with loading and Save a copy available. The stale-model renderer warning in the trial log is an intentional negative fixture.

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_workshop_compiler.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_workshop_store.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_workshop_descriptor.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_workshop_trial.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_workshop_ui.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_workshop_integration.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script ../research/aircraft-editor/capture_workshop.gd -- --language=es --out=C:/absolute/output/workshop-es-720.png
# Add --1080p and --language=en for the second capture.
```

## AE-02/03/09 audit follow-up — 2026-10-13

This follow-up challenged the earlier green suites with different representations of the same recipe and historical optional metadata. Work began on the shared working tree; `0a07a3a8` was HEAD during final verification. Other tracks committed and edited aircraft assets/session code concurrently. No physics equations or golden flights were changed by this follow-up.

### Reproduced defects and corrections

- [Store reproduction](audit-store-before.log): a valid recipe with integer values was committed, then rejected by its own readback because JSON parsed those numbers as floats and the recomputed recipe hash differed. Saves now hash a detached recipe whose numeric values have the same representation as the JSON readback. Historical ranges and metadata remain supported; caller dictionaries and prior revisions are untouched. This prevents new malformed saves, but does not automatically recover directories created by a previous failed first save.
- [Trial reproduction](audit-trial-before.log): four failures covered integer/float identity drift, invalid cosmetic metadata, conflicting recipe/payload ancestry, and explicit empty ancestry masking a recipe ID. Trial preparation validates first and hashes the normalized compiler inputs. Equivalent numeric recipes and their JSON round trips now share the full identity and resolved bytes; a 1e-12 scale change still changes identity. Conflicting ancestry is rejected before compilation.
- [UI reproduction](audit-ui-before.log): historical recipes containing optional record ID/name fields could load, but blocked renaming and Save a copy. The editor now keeps these record fields separate from its physical recipe. Tests verify rename, a distinct copy UUID, and untouched source history.

### Final verification

| Check | Result |
| --- | --- |
| [Store](audit-store.log) | 105 checks, 0 failures; integer and mixed-numeric saves/updates/readback, caller isolation and existing persistence regressions |
| [Trial](audit-trial.log) | 33 checks, 0 failures; normalized identity and strict provenance; intentional stale-renderer warning only |
| [UI](audit-ui.log) | 78 passing assertions, 0 failures, no runtime errors |
| [Compiler](audit-compiler.log) | 379 checks, 0 failures; existing numerical/trajectory regressions |
| [Descriptor](audit-descriptor.log) | 54 checks, 0 failures |
| [Integration](audit-integration.log) | 0 failures; real Home/Pause, Stik/Extra scaled flights, frozen restart, rollback and retained original flight |

The first integration attempt overlapped an unfinished `flight_session.gd` edit and failed to compile because `_restore_contact_history` was not yet defined. That process was stopped; the final log above is a fresh completed execution after the helper appeared. UI verification initially exposed stale generated model dependencies; the normal model/Workshop generators were run, never hand-edited. A subsequent `build_models.py --check` found a changing Timber imported-asset hash during that track's delivery. Consequently this audit does not claim a stable whole-repository generator/release gate. The focused Workshop checks above passed; no fresh visual capture or full repository suite is claimed.

### Remaining source-audit findings

AE-03 remains partial. These paths were identified by code review, not by a completed power-loss campaign:

- A first save interrupted before the manifest commit can leave an unreadable live directory, with no earlier backup to recover. Same-ID save/delete cannot repair it. Recovery must distinguish an uncommitted transaction from a damaged committed record without promoting an uncommitted revision silently.
- The low-level API permits explicit UUID reuse after deletion. Multiple generations in trash are sorted by wall-clock seconds and a random suffix; restoring the intended generation is ambiguous for same-second deletions or clock rollback. The UI normally generates a new UUID, but the storage contract needs an explicit generation/restore token or a UUID-reuse prohibition.
- Delete reserves the ID but does not check an expected revision. A stale caller can move a newer revision to trash; its data remains recoverable. Add expected-revision semantics together with a captured confirmation target.

These findings do not invalidate the reproduced fixes or close the remaining persistence gate. Orphan locks after process termination remain subject to the existing documented manual recovery policy.

## Limits of this evidence

The six-size real-tick matrix uses constant wing loading and default weight/power. Geometric policy and other factors have algebra/validator tests, not an exhaustive combined flight envelope. A 240-tick run proves startup and bounded immediate numerical behavior, not sustained flight performance. No goldens were re-recorded.

The compiler's 20 synthetic identities prove that names do not dispatch transformations; they are not 20 distinct aircraft assets or a fresh exported application. The dependency store currently detects changed external resources instead of supplying a historical resource bundle. Full engine-family editing, runway starts, CG/components, rich authoring bindings, crash/replay/recording matrix, long flight/refinement tests and physical/pilot validation remain open in the AE plan.
