# UI-06d-R1 · Home's column stays inside its panel

**Date:** 2026-10-12. **Status:** implemented and software-verified (headless layout test, Xvfb captures); pilot readability on the owner's monitor remains with UI-23/UI-25. **Plan:** [MENU-PLAN](../../../MENU-PLAN.md#delivery-evidence). **Trigger:** the UI-16 audit pictures showed the column wider than its 440 px panel with the UI-06d default conditions, and the keyboard legend pushed below a 720p window with the P-51 and the Avanti. The owner asked to fix it.

## Measured cause (1280×720, before)

A headless probe builds Home inside a window-sized frame for every catalog aircraft, both languages, with and without the UI-06d defaults, and reads the layout after six frames.

| Case | Sidebar width | Legend bottom (limit 696) | Why |
| --- | --- | --- | --- |
| EN, any aircraft, calm | 455 | — | `Language: English` + Help + Quit (92 px each) need 375 px of 360 |
| EN, defaults (gentle wind, evening) | 641 | — | the Weather button's one-line summary `1.5 m/s · 090° +0.6 + Turbulence · Evening, time passing` is 478 px wide; a Button's minimum width follows its text |
| ES, defaults | 721 | — | the same line in Spanish is 516 px; `Hora del día: Atardecer, el tiempo pasa` is 385 px |
| EN Stik, calm | 455 | 696 | fits exactly: the layout was tuned to the Stik's one-line note |
| EN P-51 / Avanti, calm | 455 | 767 / 741 | three-line status notes |
| ES Stik / Extra / P-51 / Avanti, calm | 440 | 741 / 767 / 793 / 819 | Spanish wraps more lines |

The sidebar's 440 px is a minimum size, so an oversized row widened the whole panel under the fade drawn at 440 px; the column has no scroll, so an oversized column pushed the legend off the window.

## Change (`app/ui/home.gd`)

- The column sits in a `ScrollContainer` (`Sidebar/Scroll/Column`): vertical only, no bar drawn, mouse wheel and keyboard focus scroll it. With room to spare the column fills the panel and its spacers work as before. It opens at the top: following the focus during the first three frames, before wrapped labels settle, scrolled the title away, so `follow_focus` is enabled only after them.
- The Weather button wraps its summary inside the Fly row (14 px, three lines: title, wind, turbulence) instead of widening the column; the legacy lighting brief is no longer repeated there, since the Time of day button right below says it; the tooltip keeps the complete conditions. The Language button clips with an ellipsis and takes what Help and Quit (80 px each) leave; the Time of day button uses 17 px and clips as a safety net.
- Vertical budget: panel margins 24/16 (were 36/24), title 32 px on Home only, card line separation 2, gaps 12/10/10/6/6, legend row separation 6, arrow buttons 36 px tall.

## Proof

| Check | Result |
| --- | --- |
| [tests/test_ui_home_layout.gd](../../../../app/tests/test_ui_home_layout.gd): every catalog aircraft × EN/ES × calm/defaults × 720p/1080p: the sidebar is exactly 440 px, Fly is visible with the focus (the arrow for a preview), the column opens at the top with the title visible, the first-run Home (Stik, defaults) fits 720p completely, everything fits 1080p, and at 720p the legend is reachable by scrolling | 202 checks pass; worst 720p overflow 74 px (ES Avanti with defaults), scrolled |
| First-run Home at 720p, after | EN 649 px of 680 available; ES 675 of 680 (bundled font, deterministic) |
| Existing menu, weather, time-of-day and update tests | see the line at the end |
| Captures under Xvfb, before/after | [before: exported build with defaults](before-home-stik-defaults-en.jpg), [before: P-51 EN](before-home-p51-en.jpg), [before: Avanti ES](before-home-avanti-es.jpg); [after: Stik defaults EN](after-home-stik-defaults-en.jpg), [ES](after-home-stik-defaults-es.jpg), [after: P-51 EN](after-home-p51-en.jpg), [after: Avanti ES](after-home-avanti-es.jpg); SHA-256 in [captures.sha256](captures.sha256) |

## Limits

- At exactly 720p a long status note (P-51, Avanti; more so in Spanish) still needs scrolling to read the second legend row; the keys are also in Help. UI-23 (scaling/fullscreen) and UI-25 (Home rows) own the real estate.
- Software rendering proves layout, not legibility on the pilot's monitor.
