# UI-15-JETI-05 — cross-menu scroll and focus audit

2026-10-26. Follow-up to the [JETI capture repair](../radio-input/D6-JETI-01/scroll-repair-2026-10-26.md).
The owner requested a search for the same interaction failure elsewhere in menus.

## Findings and changes

| Area | Reproduced trigger | Result and repair |
| --- | --- | --- |
| Workshop → Lighting | Edit a palette color while effects are pending, or an effect while a zone color is pending. | Rejection rebuilt the active input and removed keyboard focus. Scroll itself stayed at its previous offset in the live reproduction. Restore the rejected value in the existing input; retain the other pending draft, popup/control identity and scroll. |
| Controller settings | Focus an axis input or section tab, then cross a responsive layout breakpoint. | Reparenting removed focus; moving navigation also reset the body to the top. Retain the active control and reveal it after layout settles. Explicit section navigation still resets the body; manual wheel/touch/scrollbar input still cancels pending follow. |
| Statistics → History | A background statistics write completes while a history row is expanded/focused. | The service emits `changed` even when history is unchanged. Rebuilding rows discarded expansion and focus. Reuse unchanged history; on changed content, retain expansion/focus by record identity and use the History control if that record disappears or moves off-page. |

These are related focus/reading-position failures, not three copies of the original same-section capture reset.

Source review also covered Home, Pause, Settings, Help/Controls Guide, radio calibration,
Overlays, Weather, Time of day, Companions, Natural Random, failures, livery selection and
Workshop appearance/setup. No further edit callback selecting its current page or unconditionally
resetting its scroll was found. Their deliberate page/tab changes, initial focus and replacement
briefings remain distinct from in-place edits. Live Settings Graphics and Weather edits retained
their focus and scroll. This is an audit of these paths, not proof against every future menu update.

## Verification

Native Windows Godot `4.8.beta1.official.4d10419ca`, headless Control layout/input checks.
Primary geometry is 1920×1080; targeted regressions also use 2560×1440, 3840×2160 and
1280×720, English/Spanish and 100%/200% text. No physical-radio or rendering-performance
qualification is inferred from these tests.

- `test_workshop_lighting.gd`: 266 assertions passed. The new cross-editor cases produced
  96 failures before the repair and zero afterward. Coverage includes hex and picker rejection,
  all four effect inputs, accepted values, pending drafts, focus/control identity and scroll.
- `test_controller_responsive.gd`: 17,579/17,579 checks passed. The added live reflow cases
  failed 36 assertions before repair, without reselecting a section to mask lost focus.
- `test_controller_capture_scroll.gd`: 1,344 checks passed, retaining the original JETI capture
  and manual-scroll regression coverage.
- `test_ui_statistics.gd`: service-signal regressions cover unchanged history, reordered/removed/
  off-page records, expansion, filters, units and locale. See the retained checked-runner report.
- Focused Settings, Settings integration, Pause, Companions, Weather, Weather sliders,
  Time of day and Overlay manager checks passed; Overlay manager reports 204 checks.
- The reusable [debug bridge scenario](../../../tools/debug/scenarios/menu_focus_retention.txt)
  exercises both Workshop rejection directions and axis reflow in the application with unsaved drafts.

Local logs and checked-runner JSON are retained under ignored `tmp/menu-scroll-audit/`.
The baseline copies of the two edited panels were taken before this audit's runtime changes.

## Wider checks still failing

The broad Home test reports 45 layout assertions, principally short-height rail/content fit.
The modal responsive matrix reports 3/672 failing cases: Workshop in Spanish at 200% text,
at 960×540, 1024×576 and 1024×768. Both failures reproduce with the pre-repair panel sources;
the Home failure lines match exactly. They are existing layout issues, outside this focus repair.
The modal matrix's 1080p and higher-resolution cases pass.

The first disposable baseline Home run lacked the authoring-assets path and timed out; it is
not comparison evidence. Restoring that source path allowed the complete matching baseline run.
This audit does not claim a green full-project suite or resolution-wide product qualification.
