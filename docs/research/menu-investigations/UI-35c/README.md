# UI-35c — wide canvases, and opaque fades

2026-10-20. This step repairs [UI-30](../UI-30/README.md) finding SP-5 and the remaining part of AL-3. It follows the [redesign plan §11](../../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs). UI-35a/b live in [UI-35](../UI-35/README.md).

## Behaviour

| Finding | Change |
| --- | --- |
| SP-5 | `UiScale.span_margin()` returns the margin that keeps the menus inside a centred 2560-logical-pixel span once the logical canvas is wider than 2600 px; at 5120×1440 that canvas is 3840 logical px. On such canvases the Home rail and its scrim, the header, the Language/Settings actions, the aircraft details card and the Pause sidebar with its fade all move inside the span, while the scene still fills the screen. Up to 21:9 nothing changes: 3440×1440 is 2580 logical px. |
| AL-3 | `Widgets.sidebar_fade()` starts fully opaque when opaque panels are on. Pause and the Natural Random briefing use it, and the Home scrims already honoured the setting. |

## Proof

[`test_ui_home_span.gd`](../../../../app/tests/test_ui_home_span.gd) is new.
- On the previous source 7 of its 8 checks failed.
- On the change all 8 pass. They cover:
  - the 21:9 inset staying put;
  - the 32:9 rail and header inside the span;
  - the FLY caption off the Flight page ([UI-34b](../UI-34b-d/README.md#addendum-hn-3));
  - the 32:9 Pause sidebar;
  - the opaque fade.

All other affected suites pass on a clean copy of HEAD:

| Suite | Result |
| --- | --- |
| `test_ui_home` | 242 ok |
| `test_ui_home_layout` | 648 ok |
| `test_ui_home_start_layout` | pass |
| `test_ui_pause` | 73 ok |
| `test_ui_pause_responsive` | 422 ok |
| `test_ui_language` | 26 ok |
| `test_ui_aircraft` | 65 ok |
| `test_ui_aircraft_flow` | 19 ok |
| `test_ui_change_aircraft` | 8 ok |
| `test_natural_random_screen` | 40 ok |
| `test_ui_natural_random` | 27 ok |
| `test_ui_recovery_dead_ends` | 26 ok |
| `test_ui_screen_stack` | 38 ok |

**Limits.** Headless layout checks only. A super-ultrawide native capture belongs to UI-38.
