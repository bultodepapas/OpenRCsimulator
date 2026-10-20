# UI-31 — recovery dead ends

2026-10-20. This step repairs [UI-30](../UI-30/README.md) findings PS-1–PS-4, PS-7 and PS-10–PS-12. It follows the [redesign plan §11](../../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs). The rule it enforces: no reachable flight state may hold the simulation without a visible next action.

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
