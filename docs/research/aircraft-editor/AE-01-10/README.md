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

## Limits of this evidence

The six-size real-tick matrix uses constant wing loading and default weight/power. Geometric policy and other factors have algebra/validator tests, not an exhaustive combined flight envelope. A 240-tick run proves startup and bounded immediate numerical behavior, not sustained flight performance. No goldens were re-recorded.

The compiler's 20 synthetic identities prove that names do not dispatch transformations; they are not 20 distinct aircraft assets or a fresh exported application. The dependency store currently detects changed external resources instead of supplying a historical resource bundle. Full engine-family editing, runway starts, CG/components, rich authoring bindings, crash/replay/recording matrix, long flight/refinement tests and physical/pilot validation remain open in the AE plan.
