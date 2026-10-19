# AE-08b/09 — Workshop interface delivery

**Date:** 2026-10-19. **Gate:** partial; current physical-editor interface delivered, broader product/user acceptance open. The [guide](../../../AIRCRAFT-WORKSHOP.md) owns operating instructions; the [AE plan](../../../plans/aircraft-editor.md#59-menus-workflow-and-visual-design) owns remaining work.

## Delivered scope

- Flight setup/Compare pages, a large isolated Inspect/Compare preview, standard views, orbit/zoom/reset, exact size/grid labels and one-shot redraws. Front follows the renderer's −Z nose convention. Compact inspection expands the model area and retains Edit and Save/Test fly.
- On-demand scrolling library, a scrolling inspector, changed-only comparison, exact numeric alternatives to sliders and Review issues. Invalid text survives unrelated edits and blocks saving/launching. Empty names receive a correction in the save dialog.
- Full persisted-payload dirty baseline, captured source/load/close/quit decisions and safe-default Cancel. Window close first cancels an active editor modal. A detached trial editor is checked before any recorder stop. Failed save leaves the destination and draft pending.
- Resume trial plus one direct Return to Workshop. Trial return retains the editor, history, page, scroll, focus and camera; failed preparation retains the previous flight.
- Explicit stopped-manual-trace Stay/Retry/Discard recovery, independent trial/retained recorder outcomes, repeated-close coalescing and released recovery references after committed routes. Streaming `.orfl` semantics are unchanged.
- Complete validated staging before first UUID publication; captured revision checks on delete; exact UUID trash-generation restoration. First-publication boundary injection is covered; the full power-cut/update/restart matrix remains open.

No physical aircraft data, generated geometry, simulation law or golden flight was changed by this interface work. Appearance/smoke pages remain absent until their contracts are implemented.

## Verification

The [result summary](results.json), [suite manifest](logs/final/results.json), [app parse manifest](logs/parse-results.json), [native commands/results](native/results.json) and [selected source hashes](sources/after.json) retain the proof. Runtime: native Windows Godot 4.7.2 `ed1daf0bf`, Compatibility/OpenGL, RTX 3090 driver 617.42, 3840×2160 monitor at reported DPI 144.

| Check | Result / raw proof |
| --- | --- |
| Model manifests and Workshop descriptors | Both generators pass: five visual families, eight descriptors; [output](logs/generators.log) |
| Seven Workshop suites | Compiler 314, descriptor 102, store 137, trial 38, preview 42, UI 113 and integration 34 checks pass; one [log per suite](logs/final/) |
| Eleven affected menu/controller suites | Quit, Pause, responsive Pause, screen stack, input, controller menu, language, scale, responsive modals, menu audio and settings integration pass. Responsive modals covers 560 cases; responsive Pause covers 422 |
| GDScript parse | All 1,060 app scripts pass; both external capture helpers also pass `--check-only` |
| Documentation paths | 822 local links/anchors checked, including 72 incoming references; 13 required source/command paths and seven suite paths checked in the working tree and a local no-checkout clone. [Working-tree result](logs/docs-working.log), [clone result](logs/docs-clone.log); required evidence/capture paths are not ignored |
| Native Workshop matrix | 24 cases pass with empty engine stderr and no detected key-action/popup overflow; [commands/results](native/results.json). PNG and JSON share each case's basename |
| Manual-trace recovery dialog | Deterministic failed-recorder [probe](../../../../research/aircraft-editor/capture_trace_recovery.gd), Spanish 200%, 1120×440 dialog within 1280×720; [capture](native/trace-recovery-es-200.png), [stdout](native/trace-recovery-es-200.stdout.log), [stderr](native/trace-recovery-es-200.stderr.log). A background maple-tree wind/material warning remains unrelated to dialog fit |

Native cases include EN/ES at 720p/1080p and 100/150/200% text, 960×540 recovery, library/name/loss dialogs, invalid input, Compare, long names, opaque/reduced-motion, actual fullscreen 3840×2160 and a 2560×1080 window. Fullscreen reports a 1920×1080 logical canvas; the ultrawide case is a window, not a claim of an ultrawide monitor.

| Inspection case | Actual image viewport | Projected visible-mesh vertex width |
| --- | --- | --- |
| [EN 720p, 100%](native/en-720-100.png) | 710×338 | 64.1% |
| [EN 1080p, 100%](native/en-1080-100.png) | 1276×686 | 65.8% |
| [ES 720p, 200% inspection](native/es-preview-200.png) | 1180×391 | 50.8% |
| [ES 960×540, 200% recovery](native/es-small-preview-200.png) | 860×211 | 37.6%; explicitly constrained inspection |

These are projected mesh vertices, not a pixel segmentation or performance measurement. Tests additionally retain conservative model-bound margins, standard-view orientation, identical Compare framing, imported fixtures, qualified scale extremes, pointer isolation and idle redraw behavior. The smaller recovery view preserves exits/actions and reports the inspection limit; it does not meet the ordinary 55–75% width aim. [Compare at 150%](native/es-compare-150.png) puts changed rows before explanatory copy. [Library at 200%](native/es-library-200.png) scrolls its contents while retaining its exit.

Reproduce with the [Workshop commands](../../../TOOLS.md#aircraft-workshop): import dependencies; run both `--check` generators; run every `app/tests/test_workshop_*.gd` and the eleven menu scripts listed above with `--headless --path app --audio-driver Dummy --script res://tests/<name>.gd`. For each app script, run `--check-only --script res://<path>.gd`. The native manifest records exact capture arguments. Paths in those recorded commands identify the original workspace; choose a fresh local output directory when rerunning.

The full `app/test.sh` physics/offline suite was not run. Its descriptor-checkout helper creates disposable Git commits, so that helper was intentionally excluded under this task's no-commit instruction. Local no-checkout clone checks validate documentation paths without fixture commits. Software checks and native rendering are separate from human, physical-device and flight validation.

The shared tree received unrelated work and external commits. [Before](sources/before.json), [final Compare layout](sources/final-layout.json) and [after](sources/after.json) identify 48 selected inputs. The final layout-only change moved Compare explanation below the values; its parse, native capture and 113-check UI rerun pass. Those final-layout/after hashes match. This is scoped integration evidence, not a frozen whole-repository release audit. This delivery performs no staging, commit, push or history mutation.

During development, native 200% text exposed an overflowing header/library and an unusably short compact preview. The shell now reflows and the library scrolls; inspection temporarily hides editing chrome. Native dialogs also exposed an engine-managed button minimum: direct Button minimum overrides were replaced with AcceptDialog's button theme constants. A cross-owner review caught modal stacking on window close and blank-name saves without feedback; regression cases cover both. [Initial test failures](logs/initial/results.json) include a preview update mismatch, a transient PopupMenu API error and obsolete implicit-discard Pause expectations. The [first parse failure](logs/parse-tests_test_ui_quit.gd.log) was an inferred-Variant warning in a developing test. Final reruns pass; retained failures are not represented as passing runs.

## Remaining gates

- Full keyboard/directional/menu-pad journeys at every breakpoint, physical Xbox/DualSense/radio reconnect/loss testing, assistive-technology qualification, contrast measurements and the three-user formative review.
- Target-hardware warm/cold timing and resource budgets, exports/mixed-monitor DPI, broader imported/presentation anchors and long-duration trial/crash/replay acceptance.
- An explicit inherited-conditions summary, richer physical-family controls, persistent invalid/crash-recovered drafts, full write-cut/restart testing and orphan staging cleanup policy.
- Authored paint/marking slots, presentation identity, smoke profiles/mounts, multiple colors, fan/tip/tail emitters and independent burst/puff-lifetime controls under AE-24/SM. No later phase is closed by this menu delivery.

## API evidence

The implementation uses the pinned Godot 4.7.2 runtime and existing project controls. The [Godot 4.7 AcceptDialog contract](https://docs.godotengine.org/en/4.7/classes/class_acceptdialog.html) documents custom actions, safe text registration and engine-managed `buttons_min_width`/`buttons_min_height`; [Window](https://docs.godotengine.org/en/4.7/classes/class_window.html) documents clamped popups. Context7 supplied the initial ConfirmationDialog/Window review; native captures established the actual fit. These API references do not establish accessibility or performance acceptance.
