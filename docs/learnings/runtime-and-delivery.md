# Runtime, input and delivery lessons

**Status:** curated reference. Evidence comes from the 2026-10-05–08 work on Godot 4.7.2; platform observations are scoped to those experiments. Start with [LEARNINGS](../../LEARNINGS.md) for shared engineering lessons.

## Godot execution and test isolation

- **Exit status alone misses engine failures.** A runtime format error printed `ERROR:` while a test exited zero; a scene parse failure left headless Godot running without anyone reaching `quit()`. Parse scripts before integration, inspect engine/script/shader error logs, and bound process lifetime. Avoid built-in class names for constants, infer no type from an untyped Dictionary, and use `String.num_scientific()` instead of unsupported `%e`/`%g`. [Runner](../../app/test.sh), [C7-R1](../research/trace-integrity/C7-R1/README.md).

- **Wait for completed work, not elapsed wall time.** A short timer expired before a radio test's first physics update. `physics_frame` fires before the tick, and UI presentation follows separately; wait for the required completed ticks and a rendered/process frame before asserting. Inject real events through `Input.parse_input_event` to test routing. [Input tests](../../app/tests/test_e2e_input.gd), [radio tests](../../app/tests/test_e2e_radio.gd).

- **Concurrent Godot runs share preferences unless isolated.** Two suites raced through the same `user://` settings because the directory follows the project name. Give concurrent suites separate `XDG_DATA_HOME` directories and UI tests their own preference paths. Freeze source for long runs: later stages can load scripts edited after the run began. [H13/H14](../research/simulation-state/H13/README.md), [language tests](../../app/tests/test_ui_language.gd).

- **A smaller probe must retain the contract it tests.** A radio-menu probe without the project's InputMap passed because the unwanted bindings were absent. A minimal physics project at Godot's default 60 Hz rejected aircraft gear before reaching the intended mutation. Preserve relevant project settings, including the app's 240 Hz rate, and establish a valid positive control. [Menu investigations](../research/menu-investigations/README.md), [E0b1](../research/propwash/E0b1/README.md).

## Radio input and menus

- **Default UI bindings include joystick axes.** Loading no explicit radio navigation does not isolate RC sticks from menus. Load the real project InputMap, demonstrate that a stick can move focus before isolation, then verify that removing joypad UI bindings preserves flight-axis reads. [UI-00/01 input tests](../../app/tests/test_ui_input.gd).

- **Startup zero is not a reported throttle position.** Raw zero maps to half throttle before any motion event, so require a fresh low-throttle event to arm. Disconnect must pause flight, idle the engine and center commands; reconnecting with retained high throttle must remain safe. Keep collecting axes after arming because calibration and diagnostics still need late/raw updates. [Radio tests](../../app/tests/test_e2e_radio.gd), [F3b1](../research/radio-input/F3b1/README.md).

- **Pause spans simulation, presentation and input.** Freezing ticks originally left the propeller turning and the engine audible. Disabling the entire session would also lose radio events needed for arming. Coordinate pause explicitly, including audio playback readiness, while retaining the required input path. [UI-02/03 tests](../../app/tests/test_ui_pause.gd), [menu investigations](../research/menu-investigations/README.md).

- **GUI focus does not guarantee event consumption.** Enter/Space on a focused button reached flight `_unhandled_input`, and opening a pause menu during a focus notification hit a locked scene tree. Consume leftover menu keys and defer tree changes. Test focus loss through `SceneTree.notification()`: propagating only from the root does not reproduce key release. [UI-02/03 tests](../../app/tests/test_ui_pause.gd).

- **Validate saved calibration independently of the wizard.** Old or edited profiles bypass wizard checks. Require unique integer axes, finite endpoints, ordered centers and typed device identity before changing live state; rejected writes must preserve existing profiles. A throttle center may equal an endpoint because its normalization does not use the center. [D6b-R1](../research/radio-input/D6b-R1/README.md).

- **Input latency claims need an observation point.** Godot callback spacing measures dispatch, not USB reports or RF latency; queued axes arrive in batches without hardware timestamps. Keep unseen/single-sample intervals unknown and reconnects separate. A visual marker must sample after the flight polls the same buffer, and its no-effect claim needs a simultaneous control flight. Hardware latency still requires a physical trial. [F1](../research/radio-input/F1/README.md), [F6a](../research/radio-input/F6a/README.md).

## Preferences and localization

- **Translation occurs at draw time.** `Label.text` retains the source string; inspect `atr(text)` for the displayed translation. Rebuild dynamic phrases on translation changes and test actual layout in both languages. Set the default locale explicitly: the OS locale otherwise changes a fresh launch. [UI-01d tests](../../app/tests/test_ui_language.gd), [UI-05 tests](../../app/tests/test_ui_aircraft.gd).

- **Widgets can change values without emitting signals.** `SpinBox.set_value_no_signal()` still quantizes to its step, and pending editor text may differ from `value` until applied. Keep a precise draft model and commit editors explicitly. Reading an absent ConfigFile key needs a default sentinel to avoid an engine error. [Wind UI investigations](../research/wind-investigations/README.md), [language tests](../../app/tests/test_ui_language.gd).

- **Atomic replacement does not prevent lost updates.** A stale aircraft-preference writer restored an old language after another writer changed it. Reconcile writers through one settings owner and preserve unknown future schemas; test alternating writes, not only individual save/load pairs. [DT-00-R1](../research/desktop-delivery-investigations/DT-00-R1/README.md).

- **Test hooks can have engine lifetime side effects.** A lambda stored in a static script variable caused repeatable exit aborts in the UI-04 probe. Passing the mapping as a parameter avoided that lifetime. Physical-key-label APIs also emit errors under the headless display server; exercise the supported fallback. [UI-04 record](../MENU-PLAN.md), [controls tests](../../app/tests/test_controls_reference.gd).

## Clean builds and desktop evidence

- **Local CI is not a fresh checkout.** `act` copied ignored/untracked folders, hiding a missing capture directory that failed on GitHub. System Pillow also masked a missing CI dependency. Create output directories explicitly, use the pinned isolated visual environment, and verify generated/imported assets from a fresh checkout. [VQ-01a](../research/visual-quality-implementation/VQ-01a/README.md), [capture runner](../../app/capture.sh).

- **Generated media can silently become imported assets.** Capture PNGs accumulated a second copy under `.godot/`. Create `.gdignore` in output directories before import, keep manifests and compact comparisons, and bound full-frame/log retention. A local clone can also retain Git alternates despite `--no-hardlinks`; use `--dissociate` if its parent snapshot will be removed. [L4b](../research/visual-quality-implementation/L4b/README.md), [SC-25](../research/scenery-implementation/SC-25/README.md).

- **Run the exported program to test resource packaging.** The early claim that JSON required an include filter was contradicted by a real 4.7.2 `all_resources` export. Verify the final binary with its data, and use a deliberate exclusion to prove the missing-data check. First-import and standalone-builder tests must also recreate globals and resources normally supplied by the app shell. [Export runner](../../app/export.sh), [L15b](../research/visual-quality-implementation/L15b/README.md).

- **Artifact inspection and native acceptance answer different questions.** A universal Mach-O and an ad-hoc signature flag prove package structure, not native launch, signing trust, fullscreen, DPI, radio or sustained performance. Record actual renderer, backing pixels, OS floor and executable identity on each target. Process-loop percentiles are not display-presentation latency. [DT-00](../research/desktop-delivery-investigations/DT-00/README.md), [DT-00-R2](../research/desktop-delivery-investigations/DT-00-R2/README.md).

- **Build names do not identify all release inputs.** `git describe --dirty` ignores new untracked files, and different prereleases may share a numeric Windows version. Inventory build inputs and verify the tested artifact's bytes and actual replacement during upgrades; promote those bytes without rebuilding. [DT-00-R1](../research/desktop-delivery-investigations/DT-00-R1/README.md).
