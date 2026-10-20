# UI-32 — preserve choices

2026-10-20. This step repairs [UI-30](../UI-30/README.md) findings AS-3, AS-4, AS-7 and F8. It follows the [redesign plan §11](../../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs). The rule it enforces: browsing never overwrites a saved choice as a side effect.

## Behaviour

| Finding | Change |
| --- | --- |
| AS-3 | Selecting the helicopter no longer rewrites the saved weather. Home and the Conditions dialog show it without turbulence (`app_root.weather_for_aircraft`), and the helicopter flight is launched without it. The saved airplane turbulence survives selection, Home rebuilds, helicopter flights and wind edits made while the helicopter is selected (`_weather_keeping_saved_turbulence`). |
| AS-4 | Battery mode and fuel fill are saved after a successful Fly. They survive End flight and an application restart. |
| AS-7 | Home keeps one start per vehicle class. The airplane start is the existing `start_choice`; the rotorcraft pad or hover start is new. Browsing the helicopter or a runway-less landscape only limits what is shown and launched; returning restores the remembered start. |
| F8 | Selecting an aircraft or landscape keeps Home's note (a failure debrief or a launch rejection). Only a failed save writes a note, and a later successful save clears only that note. |

**Preferences.** The new `[flight]` keys are additive and need no schema change, like `landscape`: `rotorcraft_start_choice` (`runway`/`airborne`), `battery_mode` (`ideal`/`pack`) and `fuel_fill` (one of `Preferences.FUEL_FILLS`; Home now reads that constant). Older files load with the defaults. Saving refuses invalid values.

## Proof

[`test_ui_preserved_choices.gd`](../../../../app/tests/test_ui_preserved_choices.gd) is new.
- Before the change it reported 7 failures, then stopped at a script error (the preference did not exist).
- After the change all 18 checks pass. They cover turbulence round trips, starts per class, landscape round trips, the note, and battery/fuel across End flight and an application restart.

Three [`test_ui_home.gd`](../../../../app/tests/test_ui_home.gd) checks encoded the lossy contract (saved weather equal to the stripped helicopter weather). They now assert the opposite: the display is stripped and the saved turbulence is kept.

Regression runs:

| Suite | Result |
| --- | --- |
| `test_ui_home` | 242 ok |
| `test_ui_aircraft` | 65 ok |
| `test_ui_battery_mode` | pass |
| `test_ui_home_start_layout` | pass |
| `test_ui_language` | 26 ok |
| `test_ui_weather` | pass |
| `test_landscapes` | pass |
| `test_ui_natural_random` | pass |
| `test_settings_ui` | pass |
| `test_ui_home_layout` | pass |

**Limits.** Only the Home route is covered. Direct technical routes still use defaults and never read preferences.
