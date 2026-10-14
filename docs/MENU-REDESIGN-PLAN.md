# OpenRC Simulator — menu and shell redesign

**Date:** 2026-10-11. **Revision:** 2. **Status: UI-20/21 done; UI-22…29 proposed. Next: theme v2 and display/scaling. Implementation uses the defaults in §7.** **Step IDs:** UI-20…UI-29 (a reserved range of the UI- prefix; [MENU-PLAN](MENU-PLAN.md) keeps UI-00…15). **Owns:** the menu track's paths (`app/app_root.*`, `app/ui/`, `app/app_state/`, `app/i18n/`, `app/tests/ui_driver.gd`, `app/tests/test_ui_*.gd`, `app/tests/capture_ui.gd`), the proposed `app/assets/ui/` (font, icons, licences) and `docs/research/menu-investigations/UI-2x/`. **Coordinated, not owned:** `app/render/panel.gd` and `hud.gd` (main line), the `[display]` settings of `project.godot` (desktop delivery, export maintainer), `app/ui/weather_dialog.gd` (wind, M5-W), `app/ui/time_of_day_*` (TOD). **Research:** [UI-20 audit](research/menu-investigations/UI-20/README.md), [UI-21 implementation](research/menu-investigations/UI-21/README.md) and the 25 [menu investigations](research/menu-investigations/README.md).

This plan is a scoped revision of [MENU-PLAN](MENU-PLAN.md): it keeps its principles and its delivered steps (UI-00…06c) and replaces the undelivered UI-07/08/09a/09b/09c rows with the steps below, which absorb them. The desktop track's fullscreen acceptance (DT-03…05) stays where it is; UI-23 is the implementation it accepts.

2026-10-14 maintenance follow-ups: [UI-05-R1](research/menu-investigations/UI-05-R1/README.md) removes redundant Home legend reconstruction with native timing and visual parity evidence. [UI-06d-R2](research/menu-investigations/UI-06d-R2/README.md) closes the Spanish launch-caption overflow and stale live-language text, and records refreshed route checks. These repairs do not advance UI-22…29 or establish complete menu/release acceptance.

## 1. What "modern, mature, professional, useful and ready for the future" means here

Responsiveness follow-up (2026-10-14): [UI-05-R2](research/menu-investigations/UI-05-R2/README.md) bounds recent aircraft-preview reuse to three models and measures the complete selector. First-visit construction and rapid fleet traversal remain the next performance probes; theme/display delivery status is unchanged.

Measurable targets, so that "done" is not a matter of taste:

| Quality | Target | Checked by |
| --- | --- | --- |
| Modern | One visual system on every screen: a bundled typeface with two weights, a type scale, an 8 px spacing grid, an icon set, hover/pressed/disabled/focus states on every control, transitions of 120–180 ms | Theme contrast test over every styled control; capture matrix compared automatically |
| Mature | Nothing on screen is developer text by default; every status is a sentence a pilot understands; every dialog shares one chrome, one Apply/Cancel convention and one Esc behaviour; settings exist and persist | UI tests; EN/ES captures; owner read-through of all strings |
| Professional | The UI scales with the window (100–200 %) and opens fullscreen on the first interactive launch; version, licences and credits in About; EN/ES complete; export smoke of the menus on three platforms | Resolution × scale × language matrix; export smoke (DT-02) |
| Useful | One key from Home to the flight stays; aircraft, start, conditions and control device are visible before flying; Help answers "how do I connect my radio" | `test_ui_home` one-key route; owner playtest script |
| Ready for the future | A new screen costs one file; a new setting costs one registry row; the catalogue drives the hangar; the stack has hooks for radio setup, scenarios, training modes, crash report, replay and gamepad navigation | Code review of UI-21/24 against §6 |

Kept from MENU-PLAN and its research, unchanged: Fly as the single primary action; the radio never navigates; keyboard navigation complete with visible focus; contrast tested on the resolved Theme; Theme in code; no templates, addons or test frameworks; English source strings; captures and tests as proof; measured cost on the owner's machine before any animation ships.

## 2. What the audit found

Full report: [UI-20](research/menu-investigations/UI-20/README.md). In short:

1. The canvas is a fixed 1280×720 with no stretch mode and no fullscreen: on any other monitor the UI keeps 720p pixel sizes in a small window.
2. Every flight opens on monospace diagnostics (input panel, HUD with fps and µs/tick): the least finished picture in the product is the one the player looks at longest.
3. One default font in one weight, no icons, no motion.
4. The Theme covers buttons and panels only; dropdowns, tabs, sliders and text fields show Godot's default theme, patched by 49 per-screen overrides.
5. Home mixes levels (Weather beside FLY, a start toggle that looks like a label, a cycling language button, a legend taking a third of the column); pause is a flat list with a setting among flight actions; Help is a document in a box; the two dialogs disagree on Apply.
6. Growth is expensive: the modal chrome is copied into four screens, `app_root.gd` holds one variable and guard per screen, preferences are hand-written per key.
7. Details the independent review added: the vertical rhythm of Home depends on text height (the Spanish card moves the rows 26 px); the pause column is narrower than Home's; the first-flight hint stays visible in pause and says "Esc Pause"; Help has two sections about flying and a heading called "Right now"; in Flight conditions the tabs look like buttons, ranges inflate the labels and the Turbulence page clips under the footer.

What is sound and stays: the palette and its contrast tests, keyboard focus and `follow_focus`, joypad isolation, named session holds, focus return, one controls table, gettext, build identity, versioned preferences, the live airplane behind Home, the UI driver and the capture routes.

## 3. Visual direction v2: "quiet field, pro pilot"

The identity stays: dark reading surfaces, cream text, the Ugly Stik red as the one accent, the real field and airplane behind. What changes is the system around it.

- **Typeface.** Atkinson Hyperlegible Next (OFL), weights 400 and 700, bundled with its `OFL.txt`, `allow_system_fallback = false`, a test that `has_char()` covers every translatable string and the symbols in use (`° % ± · ³`; the HUD's `µ` becomes `μ` or `us`). Chosen by [investigation 16](research/menu-investigations/16-tipografia-fuentes.md); Inter is the fallback choice if the owner prefers its look (§7).
- **Type scale** at 720p: display 40, title 28, section 22, body 18, small 15, caption 13 (uppercase, tracked). Hierarchy by size and weight, not by colour alone. Body text ≥ 17 px ascender-to-descender at 720p stays the floor; the independent review proposes a tighter scale (32/20/16/12), and the UI-22 captures decide between the two within that floor.
- **Tokens** in `ui_theme.gd`: surfaces (background, panel, card, raised), text (primary, secondary, muted, disabled), accent (normal, hover, pressed), focus, semantic (info, warning, error: each with a text colour that passes 4.5:1), spacing 4/8/12/16/24/32/48, radius 6/10, border 1/3. Every pair that appears in the UI is in the contrast test.
- **Icons.** The drawn key caps stay the primary visual system (the review's strongest point: do not trade them for icons). A small subset of at most twelve Lucide icons (ISC licence) as SVG imported at 2× is used only where a label alone is weak: Settings sections, the Home secondary row, status pills and toasts (settings, help, radio, keyboard, display, audio, language, warning, check, chevrons). Each file registered in `app/assets/ui/THIRD_PARTY.md` with source commit, licence and SHA-256, as the repository requires for external assets. Icons always carry a text label; they never replace one.
- **Controls.** Full coverage of Button, OptionButton and its PopupMenu, TabContainer/TabBar, HSlider, SpinBox, LineEdit, CheckBox, CheckButton, ScrollBar, Tooltip and Toast, in the same vocabulary (flat surface, 1 px quiet edge, 3 px amber focus outside the control, red only for the primary action and for destructive confirmation text).
- **Motion.** Screens fade and slide 8 px in 120–180 ms; buttons darken in 80 ms; toasts slide in and leave after 4 s. One `UiMotion.enabled` flag, false under tests and captures, keeps every proof deterministic. No idle animation of the Home camera in this plan (§8).
- **Layout.** 8 px grid, 24 px gutters at 720p. Home and pause share one left column (440 px, capped by `custom_maximum_size` on wide screens) with three anchored groups (brand top, flight setup centre, controls bottom) whose positions do not depend on the language; modals centre at 720–960 px; the pause card sits left-centred so the airplane stays in view.
- **Copy.** Product strings are written for a pilot: "Legacy daylight" → "Default daylight", "Right now" → "Known limits", "Reference air keeps the modeled density at 1.225 kg/m³" → "Standard air (1.225 kg/m³)", "Correlation time tau" → "Change rate", "Could not save settings (error 7)" → "Settings could not be saved" with the code in a tooltip. Ranges leave the labels and become muted helper text. Technical pause reasons stay verbatim: they are diagnostics.

## 4. Screens v2

**Home.** Top left: wordmark ("OpenRC" large, "Simulator" small), ALPHA pill, version chip (the export's `git describe`, or "dev"). The **Next flight** block is a list of identical rows, label left and value right with a chevron, Enter opening a dialog or cycling the value: **Aircraft** (name, ‹ › arrows, position dots, a status pill Flyable / Experimental / Preview and a one-line spec), **Field** (the test field; scenarios later), **Conditions** (wind · air · time of day), **Start** (In the air · Runway) and **Control** (Keyboard, or the radio's name and arming state; Set up when UI-10b exists). This row pattern is what later absorbs training modes, radio setup and replays without a new layout. **FLY** full width with an Enter key cap. One secondary row: Settings, Help, Quit. The language selector moves to Settings (a small language chip stays at the top right of Home). The key legend collapses to one line ("Arrows fly · W/S throttle · Esc pause") with All keys opening Help. ←/→ on Fly still switch aircraft.

**Hangar.** What the Aircraft row opens: the catalogue's aircraft as cards (name, class, span, power, status pill, one-line status note); selecting one updates the backdrop and returns to Home. Driven only by `aircraft_catalog.gd`. Thumbnails are a later measured step (a SubViewport render at first open).

**Pause.** The same column as Home, with "Paused", the flight summary (aircraft · time flown · start · conditions · device) and three groups separated by dividers: **Continue** as primary (Esc) with Restart (R); Flight conditions, Settings, Help; End flight and Quit with the existing trace-save policy. The first-flight hint is hidden while any menu is open (today it stays visible and reads "Esc Pause").

**Flight conditions.** One dialog, opened from Home and from pause, with the existing tabs (Wind & gusts, Turbulence, Atmosphere, Time of day). In pause, time of day applies at once (TOD-08b); wind and atmosphere apply at the next restart and the dialog says so (owner decision in §7). Apply is primary, Cancel secondary, in both places. Polish from the review: tabs as an underlined strip, no fixed subtitle, ranges as helper text so sliders start further left, one field width, scroll padding above the footer, disabled rows at reduced opacity, and the preset turning to "Custom" on edit with Reset to preset.

**Settings.** Sections: Display (window or fullscreen, UI scale 100–200 %, VSync), Audio (master volume with the 60 dB curve and mute), Interface (language, first-flight hint again, HUD style), Controls (the key table; remap arrives with UI-15; radio setup with UI-10b), About (version, engine, licences including the font and icons, credits, repository). Display changes ask Keep/Revert with a 15 s timeout, as researched.

**Help.** A 960 px sheet over a darker dim (nothing ghosts through), a header bar with the title and Close, sections Keyboard · Radio · Known limits · About, one keyboard table, About as label/value lines with the URL on its own line, Close at the bottom as well as Esc. Space for What's new from a bundled changelog later.

**Flight HUD** (coordinated with the main line). A pilot HUD by default: one slim bar with airspeed, altitude, throttle and the control-device state, in the UI typeface. The diagnostics panel and the performance line move behind F3 (one press: performance line; two: full panel). Captures and traces must not change.

## 5. Architecture v2

| Piece | What it does | Replaces |
| --- | --- | --- |
| `ui/screen.gd` | Base for every screen: chrome (dim, panel, fade), swallows unused keys, Esc → `close_requested`, stores and returns focus, `open()/close()` with motion, a `kind` (sidebar, modal, toast) | Four copies of dim/fade/Esc/focus-return |
| `ui/screen_stack.gd` (owned by `app_root`) | `push`, `pop`, `top`; disables focus and mouse below the top; holds the session ("menu") while non-empty; refuses duplicates | 16 variables and 5 enumerating guards in `app_root.gd` |
| `ui/widgets.gd` | Builders: section header, labelled slider row (slider + spin + unit), option row, toggle row, segmented control, button row, status pill, icon button, toast | Per-screen layout code and 49 theme overrides |
| `ui/ui_theme.gd` v2 | Tokens and full control coverage | Partial Theme |
| `ui/ui_motion.gd` | Tween helpers behind one flag | — |
| `app_state/settings_schema.gd` | Declarative registry: key, type, range, default, section, label; `preferences.gd` reads, validates and writes through it (schema 5, migration from 4, never destructive) | Hand-written per-key code |
| `app/assets/ui/` | Font, icons, `OFL.txt`, `THIRD_PARTY.md` | — |

The session holds, the trace-save policy on End/Quit, the first-flight hint, the one-frame Home → flight hand-over and the direct CLI route keep their current behaviour and tests.

## 6. Steps

Each step leaves a usable app, passes `app/test.sh`, states its proof in the commit and adds its lesson to LEARNINGS when there is one. Sizes: S ≤ 1 day, M 2–3 days, L a week.

| ID | Step | Depends on | Proof | Status |
| --- | --- | --- | --- | --- |
| UI-20 | Audit the shell in code and captures; record what to keep | — | [Report](research/menu-investigations/UI-20/README.md): nine captures at 720p/1080p EN/ES, code measurements, independent review | Done 2026-10-11 |
| UI-21 (M) | Screen base, screen stack, widget builders; move Home, pause, Help, Flight conditions and Time of day onto them with **no visual change** | UI-20 | [Report](research/menu-investigations/UI-21/README.md): full app checks; existing UI tests unchanged and passing on Linux/Windows; 16/16 exact paired captures (same-host baseline, controlled lighting-editor pose); 721 identical flight samples; five cycles return to 234 nodes; only compatibility getters remain for per-screen access | Done 2026-10-11 |
| UI-22 (M) | Theme v2: typeface with OFL, tokens, icon subset with licences, full control coverage; contrast test over every styled control and state | UI-21 | `has_char()` over all translatable strings; contrast ≥ 4.5:1 text and ≥ 3:1 focus on every pair; captures at 100/150/200 % reviewed by the owner; `THIRD_PARTY.md` with hashes; export carries `OFL.txt` | Proposed (absorbs UI-09c) |
| UI-23 (M) | Scaling and display: `canvas_items` stretch with `expand` aspect, `content_scale_factor` 1.0–2.0, fullscreen (non-exclusive) on the first interactive launch with Keep/Revert and `--windowed` recovery; automation routes keep explicit sizes and never touch preferences | UI-21; DT-03 acceptance table | Matrix 1024×576 · 1280×720 · 1920×1080 · 2560×1080 × 100/150/200 % × EN/ES; ≥ 17 px body text at 720p; arrows reach the last control at 200 %; flight captures and traces byte-identical; DT-04 cases | Proposed (absorbs UI-09a/09b) |
| UI-24 (M) | Settings screen and settings registry: Display, Audio, Interface, Controls, About; schema 5 migration | UI-22, UI-23 | Change in pause → effect on continue → persists after relaunch; unreadable/newer/unwritable file → toast, app usable, calibration intact; headless and `--trace` runs never create the file | Proposed (absorbs UI-07/08) |
| UI-25 (M) | Home v2 (next-flight rows) and Hangar | UI-22, UI-24 | One key from Home to flight; ←/→ switch aircraft; `test_ui_home`/`test_ui_aircraft` updated; EN/ES captures with the same row positions in both languages; 30 % pseudo-locale expansion without lost actions or focus | Proposed |
| UI-26 (M) | Pause v2, Flight conditions from pause with its polish, Help sections | UI-25; wind and TOD owners | `test_ui_pause`, `test_ui_time_of_day_pause`, `test_ui_weather` pass; the hint is hidden under every menu; wind edited in pause applies only at restart and the trace header says so; the Turbulence page no longer clips; captures | Proposed |
| UI-27 (M) | Pilot HUD by default, diagnostics behind F3 | UI-22; main line | Superseded by the [flight overlays plan](plans/flight-overlays.md) (HUD-00…12) | Superseded 2026-10-13 |
| UI-28 (S) | Motion, toasts and optional UI sounds, all behind `UiMotion.enabled` | UI-21, UI-24 | Tests and captures unchanged with motion off; p95 frame time in menus unchanged on the owner's machine with motion on; no sound while a flight is paused | Proposed |
| UI-29 (S) | Proof and hand-over: capture matrix compared with `compare_captures.py`, export smoke of Home/Settings on the three platforms, owner playtest script, FIRST-LAUNCH and README screenshots, MENU-PLAN rows marked superseded | UI-22…28 | All of the above green in a clean clone; playtest confusions recorded | Proposed |

UI-16 (delivered 2026-10-12, [MENU-PLAN](MENU-PLAN.md#delivery-evidence)) added the update-notice card outside this order, and UI-06d-R1 made Home's column scroll inside its panel with wrapped button texts; UI-25 still owns the final Home rows and real estate. UI-24 exposes its `[updates] check` preference under About; UI-28 restyles the card with the toast vocabulary and motion. The daily GitHub check, the version rules and the manual download stay as delivered.

Order: UI-21 first (no visible change, removes the growth cost), then UI-22 and UI-23 in parallel (theme and display are independent), then UI-24 → 25 → 26 → 27 → 28 → 29. The visible result arrives with UI-22/23; the product feel with UI-25/27.

Future screens the architecture must take without rework: radio setup (UI-10a/10b, F5) and device choice (UI-12) as Screens under Settings › Controls; scenarios and fields (UI-06) as a Hangar-like picker; training modes ([investigation 06](research/menu-investigations/06-training-modes-progression.md)) as a flight-type choice on the Next flight card; the crash report (CR-) as a modal over the frozen flight; replay (H8) as a pause action; gamepad navigation (UI-12) as an input adapter in the stack; key remap (UI-15) as a Settings page driven by the controls table.

## 7. Decisions for the owner

None blocks UI-21. Defaults apply if there is no answer.

| Decision | Default | Alternative |
| --- | --- | --- |
| Typeface | Atkinson Hyperlegible Next 400/700 | Inter (larger file, more weights) |
| Icons | Lucide subset (ISC), registered per file | Own SVGs drawn in the key-cap style |
| First interactive launch | Fullscreen, non-exclusive (desktop track's direction) | Windowed 1280×720, as today |
| Wind edited in pause | Applies at the next restart, dialog says so | Not editable in pause (time of day only) |
| Pause backdrop | The frozen pilot view, as now | Switch to the close-up camera while paused (render owner) |
| HUD default | Slim pilot bar; diagnostics behind F3 | Keep today's panel until Gate 2 |
| Name of the conditions dialog | "Flight conditions" | "Weather" |

## 8. Non-goals and limits

No 3D hangar or animated Home camera (a slow drift is possible later as a measured, optional step); no addons, templates or test frameworks; no gamepad menu navigation here (UI-12); no web or mobile; no new aircraft, field or physics content; no change to trace, checkpoint or weather file formats; no claim of screen-reader support until tested with Orca or NVDA. The audit ran under Xvfb without a GPU: readability, motion cost and fullscreen behaviour need the owner's machine.
