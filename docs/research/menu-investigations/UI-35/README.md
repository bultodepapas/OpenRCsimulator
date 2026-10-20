# UI-35 — shared dialog states (first slice)

2026-10-20. This slice repairs [UI-30](../UI-30/README.md) findings VC-3, VC-5, SP-3 (Conditions), SC-5 (Escape), AL-3 (error colour) and AL-4 (Settings focus), plus the Conditions part of VC-1. It follows the [redesign plan §11](../../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs). The rail fade (AL-3) and the ultrawide span (SP-5, UI-35c) are delivered by the parallel UI-34 session in its own files.

## Behaviour

| Finding | Change |
| --- | --- |
| VC-3 | `ui_theme.gd` now themes the remaining control states. Sliders use the shared inside focus outline. Every CheckButton uses the Settings pill and every CheckBox a matching square check, each with disabled variants. Vertical and horizontal scrollbars use theme colours. The icons are inline SVG, rasterized once per text scale. |
| VC-1 (Conditions) | Conditions' Apply is the primary action, as in Time and Failures. |
| VC-5, AL-3 | One error colour. Conditions, Time and Natural Random use the `ErrorLabel` variation. The Controls status uses the `ERROR` token and starts with "Problem:", so an error never relies on colour alone. |
| SP-3 (Conditions) | The Conditions body takes the height its page needs, up to 88% of the canvas, instead of a fixed 340 px. The wind page fits at 1080p without scrolling. |
| SC-5 | On a screen that handles Escape before its controls (Conditions, Pause, Workshop), Escape inside an editing `LineEdit` ends the edit first. The next Escape cancels the screen, so one Escape while typing no longer discards the whole draft. |
| AL-4 | Settings opens on its first category instead of Close. |

**Kept as designed:**
- Failures still opens with Apply focused. `test_failure_availability_ui` and `test_failure_routes` pin that as the failure track's decision.
- Help keeps Close focused; it is its only action.

**Not in this slice:**
- The shared modal frame across all dialogs, meaning one dismiss control and one action row (the rest of VC-1).
- Shared tab, title and panel variations (VC-2).
- Disabled-state tokens (VC-9).
- Workshop small text (VC-10).
- Confirmation before discarding a dirty draft.

Captures (llvmpipe, 3D at half scale):
- [Conditions](captures/en-1920x1080-100-weather.webp)
- [Failures check boxes](captures/en-1920x1080-100-failures.webp)
- [Controls](captures/en-1920x1080-100-controls.webp)
- [Settings](captures/en-1920x1080-100-settings-display.webp)

## Proof

[`test_ui_modal_consistency.gd`](../../../../app/tests/test_ui_modal_consistency.gd) is new and passes 17 checks, including the UI-36 ones. It covers:
- theme icons, slider focus and scrollbars;
- error variations;
- Settings' first focus;
- the Conditions primary Apply, error style and 1080p fit;
- the two-step Escape in an editing field.

Without the Screen change, the first Escape closes the dialog and the editing-field check fails.

[`test_ui_turbulence.gd`](../../../../app/tests/test_ui_turbulence.gd) now expects the two-step Escape when its focused seed field is editing; `grab_focus()` on a Godot 4.7.2 `LineEdit` enters editing.

Regression batch, headless Godot 4.7.2: 24 of 26 suites passed first time, covering modal consistency and responsiveness, Conditions (weather, sliders, atmosphere, sky, standard column), time of day (Home and Pause), Settings, controller setup (including safety and JETI), controller menu, Natural Random, the screen stack, Pause, Quit, language, overlays, failure routes and Workshop UI.
- **test_ui_turbulence** failed on the old one-Escape expectation and passes after the update.
- **test_ui_home**'s four failures are helicopter night-option checks. Commits 65ed2ec4 (LU-29) and 2508c776 added `field_activation` to the world's night options, so the test's exact `{field_lighting, campfire}` comparisons fail. They reproduce in the live tree, are outside this slice and are reported to the landscape and field-world owners.
