# UI-36 — Settings and content (first slice)

2026-10-20. This slice repairs [UI-30](../UI-30/README.md) findings SC-1, SC-4, SC-6 and SC-8. It follows the [redesign plan §11](../../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs).

## Behaviour

| Finding | Change |
| --- | --- |
| SC-1 | Settings states its one transaction and whether anything is pending. When clean: "Changes preview at once. Keep changes saves them; Close discards them." When a change is waiting: "Unsaved preview: Keep changes saves it, Close discards it." Keep and Revert stay disabled while nothing has changed. Language still saves immediately and says so. |
| SC-4 | Help names the stick column **STICKS**, which can no longer be confused with WHILE FLYING. Trace recording, the flight log and the data reload move under **RECORDING AND DEVELOPER**, after what a pilot needs. The same keys stay listed, so the reference coverage checks are unchanged. |
| SC-6 | Conditions opens on the stock preset that matches the saved weather; for example, the default reads "Gentle breeze" instead of "Custom". |
| SC-8 | The wind intro ("Uniform wind and repeating gusts…") shows only on the Wind & Gusts page. |

**Not in this slice:**
- **Renderer options (SC-2).** The DT, VQ and CAM owners must expose them first.
- **One Units setting (SC-7).** It touches HUD overlay settings and the preferences/shell files.
- **First-flight onboarding (SC-9).** The HUD owner owns that surface.
- **Staged Conditions in Pause (PS-6).** It needs the shell route in `app_root.gd`.

Captures:
- [Settings](captures/en-1920x1080-100-settings-display.webp)
- [Conditions on its preset](captures/en-1920x1080-100-weather.webp)
- [Help](captures/en-1920x1080-100-help.webp)

## Proof

[`test_ui_modal_consistency.gd`](../../../../app/tests/test_ui_modal_consistency.gd) covers:
- the clean and pending Settings status lines;
- the Gentle breeze preset on open;
- the wind intro hidden on Turbulence and shown on Wind;
- Help's STICKS and RECORDING AND DEVELOPER headings, with no "FLY" heading.

[`test_ui_turbulence.gd`](../../../../app/tests/test_ui_turbulence.gd) now expects its calm fixture to open on the Calm preset (index 1) rather than Custom.

Passing suites: `test_ui_turbulence`, `test_ui_weather`, `test_conditions_responsive`, `test_settings_ui`, `test_ui_settings_integration`, `test_ui_help`, `test_ui_modal_consistency`.
