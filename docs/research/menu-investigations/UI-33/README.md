# UI-33 — interaction and words

2026-10-20. This step repairs [UI-30](../UI-30/README.md) findings HN-1, HN-2 (navigation part), HN-5, HN-6, VC-4, VC-8, PS-5, SC-3, AL-1 and AL-5 (landscape names). It follows the [redesign plan §11](../../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs).

## Behaviour

| Finding | Change |
| --- | --- |
| HN-1 | Home rows show what pressing them does, using a glyph drawn by `Widgets.RowGlyph` (no icon asset). Start, Landscape, Time of day, Battery and Fuel cycle in place (‹ ›). Conditions opens a dialog (›). The `HomeChoice` theme variation reserves 24 logical px on the right so text never runs under the glyph. |
| HN-2 | The four page destinations come first; Workshop, which opens its own editor, is last and marked ›. The garage backdrop remains with RCV. |
| HN-5, SC-3, AL-1 | One EN/ES glossary, as in MENU-REDESIGN-PLAN §6. **Resume** replaces Continue in Pause, including status and recovery text. **Return to Home** replaces End flight. **Quit to desktop** replaces Pause's Quit. **Controls** is the single name for input setup: Home, Pause, the dialog title, Help, the control-guide overlay and every status line. **Workshop** replaces Aircraft Workshop in Pause. **Conditions / Condiciones** names the Home row, the dialog title and the Natural Random heading. Settings reads **Language** and **Help**. Edited messages keep their existing Spanish wording, with "Controles" substituted. |
| HN-6 | Natural Random and Failure practice are left-aligned rows marked ›. |
| VC-4 | Pause disclosure buttons carry a drawn chevron (right when closed, down when open), and their items are indented. Session options lists this flight's tools first (Sky and lighting, Flight overlays), then Controls, then next-flight failures and Workshop. |
| PS-5 | "Next flight failures" appears only when this Pause offers the failure settings, so not for helicopter, trial or direct flights. |
| VC-8 | Home shows the short version beside ALPHA only in exported builds. A development run keeps its full identity in Help → About. |
| AL-5 | Landscape names are translated: "Club field / Campo del club", "Green paradise / Paraíso verde". |

**Deferred:**
- **HN-3** (an object-labelled FLY) moves to UI-34b, which introduces catalog short names.
- **HN-4** (a separated Quit) needs rail width that the compact 304 px bound does not have; a 16 px gap pushed the Spanish rail to 316 px. It returns with the UI-34b rail work.

Captures (llvmpipe, 3D at half scale, interface at native resolution):
- [Home](captures/en-1920x1080-100-home.webp)
- [Aircraft](captures/en-1920x1080-100-aircraft.webp)
- [Practice](captures/en-1920x1080-100-practice.webp)
- [Pause · Session options](captures/en-1920x1080-100-pause-session.webp)
- [Pause · Exit options](captures/en-1920x1080-100-pause-exit.webp)
- [Conditions](captures/en-1920x1080-100-weather.webp)
- [Settings](captures/en-1920x1080-100-settings-display.webp)

## Proof

Headless Godot 4.7.2 on the integrated source, all passing:

- **Changed for the rename:** `test_ui_home` 242, `test_ui_home_layout`, `test_ui_home_start_layout`, `test_ui_language` 26, `test_landscapes`, `test_controller_actions`, `test_controller_pause_recovery`, `test_overlay_manager`, `test_natural_random_screen`, `test_ui_weather`, `test_ui_turbulence`, `test_ui_sky`, `test_ui_atmosphere`, `test_ui_standard_column`, `test_ui_field_world_time_of_day`.
- **Run unchanged:** `test_ui_pause`, `test_ui_pause_responsive`, `test_controller_menu`, `test_controller_setup`, `test_ui_screen_stack`, `test_ui_quit`, `test_ui_aircraft`, `test_ui_natural_random`, `test_settings_ui`, `test_ui_help`, `test_failure_routes`, `test_ui_time_of_day_pause`, `test_ui_runway`, `test_ui_settings_integration`, `test_workshop_integration`, `test_ui_recovery_dead_ends`, `test_ui_preserved_choices`, `test_ui_change_aircraft`.

Test edits replace retired labels with the glossary terms, or follow the new Session options order; no check was weakened.

**Layout regression caught and corrected.** The first version made the Spanish compact rail 316 px against the 304 px bound. The causes were the unwrapped development label, the 16 px Quit gap and a 36 px glyph reservation. A probe of minimum widths located them; the fixes above bring the rail back to 304 px.
