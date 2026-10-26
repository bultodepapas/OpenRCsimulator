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


## AE-09b/d refinement — 2026-10-26

The UI review covered all six current pages, preview controls and the library/save/loss-guard flow. It found mixed document/page navigation, history below long forms, unlabeled choices, incomplete Spanish lighting copy, an unsafe reset on Compare, and missing lighting/audio/control-travel changes in Compare. No new aircraft adjustment or simulation capability was added.

The implementation separates Library/Back from page tabs, gives the inspector 620 logical pixels at 1080p, groups existing setup/audio controls, labels appearance/smoke/lighting choices, and pins shared history below the inspector. Enlarged text at fallback heights moves history/status into the scroll. Compare is read-only and includes existing recipe/presentation changes. The library separates selected saved records from the current draft and import. A 165° yaw / 15° pitch default exposes more of the aircraft while retaining the established model-width gate; Front/Side/Top remain unchanged. Smoke numeric fields expand to show values and units. Navigation repairs hidden focus and routes the active page to its first enabled setting.

Research informed grouping and disclosure, rather than adding another UI framework: [NN/G progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/), [recognition rather than recall](https://www.nngroup.com/articles/recognition-and-recall/), [user control and freedom](https://www.nngroup.com/articles/user-control-and-freedom/), [Godot focus navigation](https://docs.godotengine.org/en/latest/tutorials/ui/gui_navigation.html), and [Godot containers](https://docs.godotengine.org/en/latest/tutorials/ui/gui_containers.html), consulted 2026-10-26. These sources support the design choices; they do not substitute for user testing.

Validation used Linux, pinned Godot `4.8.beta1.official.4d10419ca`, Xvfb/OpenGL Compatibility and Mesa llvmpipe. Concurrent commits/source generation in the shared tree required a copied `app/` snapshot; final UI sources matched it byte-for-byte. The [compact result record](2026-10-26-ui-results.json) retains source hashes and the selected results. Local raw logs/captures remain under ignored `tmp/workshop-ui-20261026/`; no new image is committed.

- Twelve focused suites cover Workshop UI, preview, customization, smoke controls, lighting, recovery, measured mass, library reuse, trial integration, sequence UI, mechanical configuration and localization. The smoke test's old fixture was corrected to omit post-v1 fields and assert the explicit v1→v2 migration target; migration/runtime behavior was not changed.
- Seventeen capture cases cover all six pages and library/save/guard/invalid states at 1080p, 150%/200% text, 1440p, 4K and 720p fallback. All report empty key-action/popup overflow. Visible ordinary 1080p aircraft width is 63.4% of its preview; enlarged compact Edit hides the model, so hidden-preview projected geometry is not an inspection result.
- The debug-bridge smoke pass completed 30 steps, a 50-action seeded walk and two fly/Home soak cycles, with no reported failures or leaked exit objects. A final keyboard journey and the extended Workshop discard/Compare/Undo scenario pass with no engine errors and zero exit leaks.
- Engine compilation reports zero errors. Seventeen warning sites in Workshop-related files match pre-existing source at `3c1a8b78`; the generic linter reports no findings in the changed UI/test paths. Its repository-wide pre-existing findings are not represented as a clean global lint result.

Development failures are retained locally: the first new test used a legacy profile as if it had modern lighting fields; a concurrent registry write invalidated an earlier run; a wider camera angle failed the existing width gate and was adjusted. Initial smoke migration tests exposed stale fixture/schema-version assumptions, corrected without weakening production validation. The initial missing-aircraft capture came from an already stale `lighting_vfx.gd` presentation hash; the existing customization generator refreshed its registry. Subsequent unrelated renderer changes remain owned by their parallel track.

The full `app/test.sh`, native GPU performance, physical controller testing and formative human acceptance were not run. This refinement does not close those AE-09e/f gates.

### Final visual review — 2026-10-26

The follow-up inspected all six pages, Library, preset menus, expanded lighting zones/effects/sequences, color pickers and night playback in the running Spanish interface at 1080p. Palette hex values now use the shared body font; adding/removing a color retains keyboard focus. Secondary hints, effect separators and emphasized Apply actions improve the advanced editor hierarchy. Numeric fields expand for their values/units, action rows can wrap, and the existing empty-effects explanation is visible.

Native color-picker panels have an opaque background and fit their existing contents using [Window content scaling](https://docs.godotengine.org/en/stable/classes/class_window.html#class-window-property-content-scale-factor). This preserves every picker control while reducing only the popup's scale when its requested size exceeds the viewport. The smoke picker fits at 468×1048 with 200% text on a native 1920×1080 viewport, and 313×688 on a separately launched native 1280×720 viewport. The [native PopupPanel](https://docs.godotengine.org/en/stable/classes/class_popuppanel.html) and ColorPicker controls remain in use. No aircraft or simulation behavior changed.

Six focused suites pass on the final snapshot: Workshop UI, lighting, sequence UI, customization, smoke controls and UI scale. The new `workshop_lighting_palette_focus.txt` debug scenario passes; rendered and headless sessions exit without engine errors or leaked objects. Fourteen selected captures, source identities and log hashes are appended to the [result record](2026-10-26-ui-results.json); raw artifacts remain in ignored `tmp/workshop-ui-20261026/final-review/`. A 64×64 headless viewport and an Xvfb resize that retained the old logical viewport were excluded from geometry qualification. This is interface evidence, not GPU performance or physical-controller qualification.

### AE-09d operation audit — 2026-10-26

The audit traced accepted edits through preview configuration, lighting controls and pending-field recovery. Following Godot's [measurement guidance](https://docs.godotengine.org/en/latest/tutorials/performance/cpu_optimization.html), the evidence measures allocation and refresh counts rather than inferring FPS from a debug session. Idle preview processing and [one-shot viewport updates](https://docs.godotengine.org/en/stable/classes/class_subviewport.html) were already bounded and remain so. Sources were consulted on 2026-10-26.

| Reproduction | Before | After |
| --- | --- | --- |
| Edit audio, smoke density, lighting or visual seed with four smoke emitters | 8 particle pools created per edit | 4; the discarded generation is removed |
| Audio edit with unchanged lighting and bindings | Lighting resources and editor rows replaced | Existing resources and rows retained |
| 13 external-pending notifications, including two transitions | 13 sequence-control scans | 2 scans |
| Four-emitter feedback label in the 1280×720 layout fixture | 1×2537 label, zero image height | 1071×17 label, 646-pixel image height |

Accepted edits still reset playback and residual smoke. Changes to smoke version, bindings, seed or scheduling still reconfigure smoke; an explicit historical-profile migration is not an unchanged-input case. Paint changes remove old lighting skins before applying the finish and rebuilding its dependent lighting. Scale changes preserve registration and lighting resources. Lighting controls reuse only accepted, unchanged inputs without pending edits; authoritative resets, full presentation snapshots and owner-driven pending-text restoration remain intact. The flow label now has a readable minimum width and fills available space. Native 1920×1080 day/night captures confirm that smoke controls no longer obscure the aircraft image.

Nine focused suites pass, including the new allocation, skin/registration, control-identity, pending-reset and layout regressions. The general debug-bridge smoke pass completes 34 steps, a 30-action seeded walk and two fly/Home soak cycles, with no failures, growing counters or exit leaks. Compilation reports zero errors and ten existing name/shadowing warnings; three new draft-test warnings were removed. Raw artifacts remain in ignored `tmp/workshop-operation-20261026/`; hashes and results are appended to the [result record](2026-10-26-ui-results.json). Baseline assertion failures are retained as reproduction evidence. Initial draft parse errors, a profile-migration assertion and a debug-script log-command syntax error were corrected; these runs are not counted as successful validation.

Validation used the pinned Godot 4.8 beta 1, an isolated source snapshot, headless correctness tests and Xvfb/llvmpipe captures. Concurrent work on the host and software rendering exclude latency/FPS or target-GPU qualification. The smoke pass records loading hitches; it is a functional regression result. No simulation, aircraft-data or new product capability changed.

### AE-09d critical follow-up — 2026-10-26

Six independent Luna Max reviewers inspected preview lifetime, numeric/history state, customization signals, lighting state, library I/O and evidence quality. All six reports were received before selecting changes. Follow-up review caught an approximate-equality shortcut that dropped nearby valid decimals; an exact-value regression now covers `1.237` → `1.237001`, as well as equivalent spelling `1.2370`.

| Reproduction | Before | After |
| --- | --- | --- |
| Changed numeric commit | 2 compiler calls | 1 |
| Equivalent numeric spelling | 1 compiler call | 0; pending state refreshed |
| Appearance configure with pending inscription | Validity events `[true, false, true]` | `[true]`; raw text retained |
| Clean smoke configure | Validity events `[false, false]` | `[false]` |
| Replace a playing four-emitter aircraft | 4 pools allocated under the discarded renderer | 0 |
| Failed model build followed by Play | Freed-object script error | Empty model/effect state; playback disabled; valid retry succeeds |

Panel synchronization emits its completed validity state once; ordinary user text events still notify individually. Aircraft replacement disposes old smoke before resetting playback. A failed build clears stale model references and hides the size badge; retry retains the presentation. Closing an actively playing preview is covered. These changes preserve the existing controls and simulation behavior.

The review also identified bounded library/favorites reads and draft-buffer behavior during Undo as follow-up candidates. Neither was changed: library caching needs measured I/O and freshness/memory evidence, while changing Undo's accepted-snapshot semantics needs a separate behavior decision.

Reproductions and final evidence are recorded in the [result record](2026-10-26-ui-results.json), with raw artifacts in ignored `tmp/workshop-inquisition-20261026/`. The failed-build suite suppresses the deliberate unknown-ID rejection only during that call; a separate run with diagnostics enabled records exactly that expected error, 143 passing assertions and no additional error. This witness is retained as an expected-error run, not a clean checked-run pass. No frame-time or FPS improvement is claimed from these deterministic operation counts.
