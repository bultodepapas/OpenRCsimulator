# UI-31 — recovery dead ends

2026-10-20. This step repairs [UI-30](../UI-30/README.md) findings PS-1–PS-4, PS-7 and PS-10–PS-12. It follows the [redesign plan §11](../../../plans/menu-redesign.md#11-ui-30-audit-repairs). The rule it enforces: no reachable flight state may hold the simulation without a visible next action.

## Successful controller recovery focus (UI-31-R1, 2026-11-06)

External audit A11 F02 reproduces at `077b8be1d`: recovery hides the Controls
opener before or after the setup dialog closes, leaving Pause without keyboard
or gamepad focus. The initial production-route regression failed 16 of 39 checks
with no engine errors, for both Keyboard and replacement-controller recovery.

`Screen` now accepts an optional focus fallback. `ScreenStack` restores a usable
opener first, then asks the exposed active screen to recover missing focus.
Pause supplies its primary action and also repairs focus when its focused
recovery shortcut disappears. Hidden, disabled, nonfocusable, freed and queued
targets are rejected. A newer valid selection is preserved, including against
Pause's queued initial-focus callback. Explicit no-restore pops remain unchanged.
Standalone dialogs return their own outgoing focus to the opener; focus outside
the closing dialog is preserved. Focusing Resume never activates it.

[Source identities and checked receipts](recovery-focus-20261106/verification.json)
retain **72 new passing checks** and **2,275 existing checks** across eight UI and
controller suites. The new test runs the real AppRoot → Pause → Controls → Save
route at a 1920×1080 viewport with synthetic devices. It checks both visibility
timings, a separate menu pad, Keyboard/replacement recovery, continued navigation
and Accept, device isolation, unchanged paused state, shared-stack edge cases and
standalone Help. Existing coverage includes Pause, screen-stack cycles, controller
recovery, calibration, responsive layouts, Settings and quit transactions.

Final tests used pinned Godot 4.8-beta2 on Windows headless in a frozen checkout
with isolated preferences. All final receipts are complete with zero engine
errors; calibration retains its expected AUX-overlap warning. Two earlier
shared-tree suites failed during concurrent fuel-widget edits: parse errors
caused downstream missing-frame accesses despite passing assertions. Those failed
receipts remain retained. The final snapshot includes the corrected shared fuel
code, with no feature exclusion; the integrated focus source and test match it.
The [snapshot patch](recovery-focus-20261106/tested-snapshot.patch) and manifest
identify that scope separately from later unrelated edits.

These are software and headless layout checks, not physical-controller, native
visual or screen-reader qualification. Required CI remains separate.

## Coordinated departures (UI-31-R2, 2026-11-06)

External audits A13 UI2-01/UI2-05 and A14 F14 identify three parts of one failure:
garage recordings could bypass root quit, Workshop recovery was deleted before a
later cancellation, and trace-to-statistics recovery released the departure guard.

AppRoot now retains the destination, original session holds, input ownership and
recording decisions until commit or cancellation. Airplane, helicopter and ground
recordings have generation identities; an earlier discard cannot authorize losing
a later recording. Ground keeps its own explicit neutral/Resume policy. Failed
statistics closure also restores an idle session's open state. Workshop authorizes
Discard separately from terminal recovery cleanup, preserving its existing identity
check against newer writers.

Dialog callbacks are bound to their owner and request generation. Retired windows
hide before successors open; an incumbent exclusive decision is cancelled before a
new quit request. The underlying activity cannot start a recording or navigate in
the frame between dialogs. Controller edge tracking, ground physical-button
reconciliation and deferred Garage focus preserve usable controls after Stay.
The independent Good Enemy review found these input/focus cases during integration;
the final bounded source review reported no additional concrete blocker.

[Verification manifest](exit-transaction-20261106/verification.json) and
[reproducible snapshot patch](exit-transaction-20261106/tested-snapshot.patch) retain
**910 passing checks across 18 focused suites**, including **115 checks in four new
regressions**. The final receipts are complete with zero engine errors or warnings:

| New regression | Checks | Boundary |
| --- | ---: | --- |
| `test_exit_transaction` | 41 | Real Recorder/Trace and statistics store write failures; Quit and End; Retry, Discard, Stay, Cancel and Leave; Workshop snapshot bytes; stale/duplicate events; input gaps; incumbent Statistics dialog. |
| `test_ground_exit_transaction` | 22 | Both root and ground close owners, active/stopped recordings, repeated close, retained samples, manual save/Home, Retry/Discard, pad edges and Garage focus. |
| `test_ground_departure` | 25 | Real session generation/discard contract, unchanged state/tapes/damage, managed/standalone ownership and weak adapter lifetime. |
| `test_trace_departure_generations` | 27 | Replacement recordings, stale decisions, manual-save reconciliation, refused adapter discard, weak ownership and both flight recorders. |

Affected existing suites cover Pause/Quit/Restart recovery, loading, audio retirement,
Workshop navigation/recovery, statistics lifecycle, controller routing, ground sessions
and activity, and all translation catalogs. The controller/statistics suites include
eight additional assertions. No physics law, aircraft data or golden flight changed.

Runs used pinned Godot `4.8.beta2.official.cafc17a19`, Windows headless and isolated
preferences in a frozen checkout derived from `5460013fd3`. New integration fixtures
use a 1920×1080 logical viewport. The ground close fixture visits both production
handlers while excluding nested Windows, matching the pinned engine's
[window-notification boundary](https://github.com/godotengine/godot/blob/cafc17a19/scene/main/window.cpp#L828).
Earlier failed checks and fixture corrections remain in the manifest. Ground export
outcomes use an injected adapter; flight trace/statistics failures use real filesystem
operations. The RCV session suite explicitly skips its unstaged native-backend case.
Native OS-window interaction, physical controllers, rendered/assistive-technology
acceptance and required full CI remain separate qualification gates.

## Behaviour

| Finding | Change |
| --- | --- |
| PS-1 | `app/ui/calibration_card.gd` shows the radio calibration wizard whatever overlay preset is active. It sits on CanvasLayer 9, below Pause, and never takes focus. It shows the step, the translated prompt, the wizard error and the live radio axes. Keyboard Enter that completes the wizard, and Esc that cancels it, now open Pause on both airplane and helicopter routes, matching the existing controller path. Pause then states the result: saved, not saved, or cancelled. |
| PS-2 | When the selected controller is lost, or a radio is connected but not armed, Pause shows a top-level **Controls** action above Resume. A lost device puts the focus on it. A connected gamepad only gets it after 1 s unready, because it re-checks readiness briefly after every pause. A refused Resume moves the focus to it. |
| PS-3 | With a controller selected, a Workshop trial now runs the same launch step as a Home flight. Before, attaching the controller paused the trial and no menu appeared. |
| PS-4 | Opening Pause cancels an open smoke-AUX assignment, the same way it already cancelled a running calibration. Resume is refused, with a note, while any hold other than Pause's own remains. |
| PS-7 | Helicopter R emits `restart_requested` and goes through the shell's shared restart. The helicopter crash reason no longer embeds "R: restart", which Pause swallows; the helicopter HUD keeps its own key hint. |
| PS-10 | The flight-log label (CanvasLayer 25) hides and shows with the other overlays. |
| PS-11 | Restart first runs the End-flight trace transaction. A failed save offers the existing Stay / Retry / Discard decision. Trace recovery now recognises the rotorcraft recorder's note. |
| PS-12 | An OS window focus loss while flying opens Pause at once. On X11 this arrives about 250 ms before the application focus loss. Embedded dialogs also take focus from the root viewport, so `app_root.window_focus_probe` must confirm that the OS window really lost focus. |

**Deviations from the plan:**
- **Smoke AUX.** The assignment is cancelled when Pause opens instead of moving onto the screen stack. The guarantee is the same: no stray hold under Pause.
- **Stay after a failed window-close save.** It still resumes the flight. `test_ui_quit.gd` deliberately asserts that cancelling a quit keeps a running trial flying, so changing this is an owner decision.

## Proof

[`test_ui_recovery_dead_ends.gd`](../../../../app/tests/test_ui_recovery_dead_ends.gd) is new.
- On `9a55ea7a` it reported 12 failures, then stopped at a script error (the recovery action did not exist).
- On the repaired source all 26 checks pass. They cover the card, Esc and the completing Enter, the other-hold refusal, the flight-log layer, the Restart trace decision, OS versus embedded focus loss, helicopter R, controller loss and focus, and a trial with a controller.

[`test_ui_pause.gd`](../../../../app/tests/test_ui_pause.gd) changed one expectation: Esc in the wizard now opens Pause. The former second Esc press left a frozen flight without a menu.

A first version of the focus-out repair opened Pause under the quit-guard dialog. Bisecting in a disposable copy of HEAD isolated the cause: an embedded dialog sends `WM_WINDOW_FOCUS_OUT` to the root. That is why the OS-focus probe exists.

Headless regression runs, Godot 4.7.2, on the integrated source, all passing:

| Suite | Result |
| --- | --- |
| `test_ui_pause` | 73 ok |
| `test_ui_pause_responsive` | 422 ok |
| `test_controller_pause_recovery` | 59/59 |
| `test_controller_menu` | pass |
| `test_ui_screen_stack` | 38 ok |
| `test_ui_quit` | 47 ok |
| `test_ui_language` | 26 ok |
| `test_ui_home` | 242 ok |
| `test_ui_aircraft` | 65 ok |
| `test_failure_routes` | 58 ok |
| `test_ui_field_world_time_of_day` | 37 ok |
| `test_ui_settings_integration` | 27 ok |
| `test_ui_help` | 38 ok |
| `test_ui_runway` | 137 ok |
| `test_workshop_integration` | 36 ok |
| `test_e2e_radio` | pass |
| `test_ui_time_of_day_pause` | 44 ok |

**Limits.** These are synthetic-device and headless checks. Calibration with a physical radio, Windows focus behaviour and native captures of the card remain to be verified with hardware.

## Manual CSV generations and controller continuity (UI-31-R3, 2026-11-07)

A30 N01/N02: both manual recorders reserve each automatic destination with atomic directory creation, write a staged complete CSV and then publish within that owned directory. Existing saves and clock rollback cannot select a previously published automatic path. Explicit-path overwrite remains deliberate. Failed generations retain their rows; T must save them successfully before replacement, or recovery must discard the matching generation. The operational export GUI smoke/card now recognize nested saves as well as legacy flat CSVs.

A30 N03 keeps restart/rate latch history for unchanged device generation and binding. New selections, remaps, reconnects and focus-loss recovery require an OFF observation before arming. Nonfinite axis samples cannot manufacture a release. A11 F05 gives editors and binding capture their ordinary keys before Back/Pause shortcuts, including generated native ui_cancel mappings and deferred remap races. Default Escape, popup handling and controller Back remain separate navigation paths. Shared focus eligibility now honors recursive disablement during departure guards; Stay restores a usable Pause target even when restart began before its first focus callback.

Recorder checks cover concurrent reservations, fixed/rolled-back clocks, staged write/publication failure, retries, stale generations, both production T handlers and the real fixed-wing Quit → Stay → Resume → T route. The dedicated controller test uses production Controls/ScreenStack and saved mappings. Exact results and source identities are in the [checked evidence index](../UI-32/audit-20261107-checks.json). The helicopter exit dialog, physical controllers and macOS/Linux filesystem concurrency remain separate acceptance work. The [companion rebind](../../ai-companions/AFC-02/rebinds/2026-11-07-84cac259-to-fccb428e.json) compares nine retained 2,881-row tapes; it is not physical validation or exact-replay qualification.
