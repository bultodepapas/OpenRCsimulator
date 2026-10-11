# UI-20 · Shell audit: code and captures (2026-10-11)

**Step:** UI-20 of [MENU-REDESIGN-PLAN](../../../MENU-REDESIGN-PLAN.md). **Base:** `7267b26` (branch `work/pt2-trial-preparation`, clean tree). **Question:** what in the current menus reads as unfinished, what limits growth, and what is already sound and must be kept.

## What was done

1. Read every shell script: `app/app_root.gd`, `app/ui/*.gd`, `app/app_state/*.gd`, `app/project.godot`, the UI tests and `tests/capture_ui.gd`; the current [MENU-PLAN](../../../MENU-PLAN.md) (revision 3, legacy Spanish) and its 25 investigations.
2. Captured the real screens under Xvfb with the pinned Godot 4.7.2 (`--rendering-driver opengl3 --audio-driver Dummy`, `tests/capture_ui.gd` and `tests/capture_time_of_day_dialog.gd`): Home EN/ES at 1280×720 and EN at 1920×1080, pause, Help, first-flight hint, Flight conditions (wind and atmosphere tabs) and the pause Time of day dialog. The PNGs are stored here as JPEG (quality 85) to keep the repository light; [captures.sha256](captures.sha256) lists the hashes of the original PNGs.
3. Asked an independent reviewer (a second model instance, given only the captures and the constraints) for a non-anchored UX critique; its points were merged into the findings below where they held up against the code.

Reproduce (from the repository root, needs `xvfb-run`):

```sh
G=$(app/get-godot.sh)
for s in home pause help hint; do
  xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path app --rendering-driver opengl3 --audio-driver Dummy \
    --script res://tests/capture_ui.gd -- --out=/tmp/ui-$s-en.png --lang=en --screen=$s
done
xvfb-run -a -s "-screen 0 1920x1080x24" "$G" --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script res://tests/capture_ui.gd -- --out=/tmp/ui-home-en-1080.png --lang=en --screen=home --size=1920x1080
```

## Captures

| Screen | File | What it shows |
| --- | --- | --- |
| Home, English | [ui-home-en.jpg](ui-home-en.jpg) | One 440 px column over the live Ugly Stik render |
| Home, Spanish | [ui-home-es.jpg](ui-home-es.jpg) | Longer strings wrap inside the card; the column holds |
| Home at 1920×1080 | [ui-home-en-1080.jpg](ui-home-en-1080.jpg) | Same pixel sizes: the column is 23 % of the width, text is unchanged, a large empty gap opens between the title and the card |
| Pause | [ui-pause-en.jpg](ui-pause-en.jpg) | Six equal buttons; the frozen flight shows the airplane as a few pixels |
| Help | [ui-help-en.jpg](ui-help-en.jpg) | A 1120×600 modal with two key tables, radio text and the about line |
| First flight | [ui-hint-en.jpg](ui-hint-en.jpg) | Monospace diagnostics panel (top left), monospace HUD with fps (bottom left), hint card (top right) |
| Flight conditions | [ui-weather-wind-en.jpg](ui-weather-wind-en.jpg), [ui-weather-atmosphere-en.jpg](ui-weather-atmosphere-en.jpg) | Preset dropdown, four tabs, slider + number rows, Cancel/Apply |
| Time of day (pause) | [ui-tod-en.jpg](ui-tod-en.jpg) | Dropdowns, slider, toggle, text fields; a red primary Apply |

## Findings: what reads as unfinished

Ordered by how much each one costs the first impression.

1. **Fixed 1280×720 canvas, no stretch, no fullscreen.** `project.godot` sets only the viewport size; there is no `window/stretch/mode`, no `content_scale_factor`, no display mode. On a 1080p or 4K monitor the UI keeps its 720p pixel sizes and the window opens small. UI-09a/09b and DT-04 exist as plans only.
2. **The flight itself opens on developer overlays.** `render/panel.gd` (channel/raw/command/surface table, trims, `[T] record trace`) and `render/hud.gd` (airspeed line plus fps and µs/tick) are monospace debug text, visible from the first second of every flight. Nothing in the shell looks less finished than this, and it is the screen the player spends the most time on. Owned by the main line; a shell change needs its agreement.
3. **No type system, no icons, no motion.** The engine's default Open Sans SemiBold is the only font (one weight; hierarchy by size only). There are no icons: arrows are drawn triangles, every action is a grey text box. Screens appear and disappear in one frame. These three together are what makes the shell read as a prototype rather than a product.
4. **Theme coverage stops at buttons and panels.** `ui_theme.gd` styles Button, PrimaryButton, PanelContainer and five variations (Sidebar, Card, Badge, KeyCap, labels). TabBar, OptionButton, HSlider, LineEdit, CheckBox and CheckButton fall back to Godot's default dark theme: the black dropdowns and tab strip in the Flight conditions captures. Screens patch the gaps with 49 `add_theme_*_override` calls (15 in `weather_dialog.gd`, 12 in `home.gd`).
5. **Home mixes levels.** The dynamic Weather button sits beside FLY at the same height, with jargon in its summary ("Legacy daylight"); the start-choice toggle looks like a label inside the card; Language cycles through a button (does not scale past two or three languages); "development build" is a sentence where a version belongs; the controls legend takes the bottom third of the column. The aircraft chooser is a pager ("Aircraft 1 of 4") with no overview of the other three. The vertical rhythm depends on text height: the Spanish card is taller, so the NEXT FLIGHT row sits 26 px higher than in English.
6. **Pause is a flat list.** Continue, Restart, Time of day, Help, End flight and Quit have equal weight. "Time of day" is a setting placed among flight actions, and it is the only setting reachable in pause (weather is Home-only), so the two entry points disagree. The frozen pilot-view backdrop shows the airplane as a few pixels: the pause screen has no subject. The pause column is 400 px against Home's 440, and the first-flight hint stays visible above the dim, still reading "Esc Pause" while paused.
7. **Help is a document in a box.** One wide modal, Close only at the top right, the about text as a last paragraph. Two sections are both about flying ("WHILE FLYING", "FLY"), a heading is called "RIGHT NOW", Home's text ghosts through the dim around the sheet, and the repository URL breaks across two lines. There is no place for release notes, licences of future assets, a radio guide with pictures or links.
8. **Inconsistent dialog conventions.** Flight conditions gives Apply a secondary style; Time of day gives it the red primary. One dialog is a tabbed editor on Home, the other a single page in pause, both built separately. In Flight conditions the tabs look like a row of buttons, a fixed subtitle repeats each tab's own description, the ranges inside the labels widen the label column, the Seed field has a different width, the Turbulence page clips under the footer and the disabled Atmosphere fields look almost enabled (independent review).
9. **Error and status copy is technical.** "Could not save settings (error 7)", "Reference field (synthetic)", "Legacy daylight", "Lower the throttle to arm the engine" are correct and terse but written for the developer.

## Findings: what limits growth

- **Every screen re-implements the modal chrome.** Dim rect, panel, fade strip, swallowing of unused keys, Esc handling (8 `KEY_ESCAPE` sites across `ui/`) and focus return are copied into pause, Help, Flight conditions and Time of day. A fifth screen (radio setup, settings, hangar) would be a fifth copy.
- **`app_root.gd` is the navigation state machine by hand.** 16 member variables, one per possible screen, and five guard conditions of the form `if help != null or time_of_day_dialog != null`. Each new screen adds a variable and touches every guard. The holds (`session.hold("menu")`) and focus-return logic are right and must be kept; what is missing is a stack that owns "which screen is on top".
- **No settings model.** `preferences.gd` is a validated, versioned file (schema 4), which is good, but every preference is read, validated and written by hand in `app_root.gd`. Display mode, UI scale, volume, key remap and HUD options (UI-07/08/09/15) would each add bespoke code. A declarative registry (key, type, range, default, label, section) could drive both the file and the Settings screen.
- **Screens are built imperatively in `_init`.** `home.gd` 475 lines, `weather_dialog.gd` 877, `time_of_day_controls.gd` 439. The choice of code over `.tscn` is deliberate and right for diffs and tests; what is missing are small reusable builders (a labelled slider row, a section header, a button row, a toast) so that screens are short.
- **Capture coverage is 720p only** and visual comparison runs only for landscape captures; a UI change is checked by eye.

## What is sound and must be kept

- Theme in code with a tested palette (contrast ≥ 4.5:1 on the resolved Theme, amber focus ring ≥ 3:1), visible keyboard focus, `follow_focus` on scrolls, no joypad events in `ui_*`, named session holds for pause, focus return on close, one controls table feeding Home, Help and the hint, English source strings with a gettext catalogue, build identity from the export, versioned preferences with `.bad` backups and never overwriting a newer schema, and the live render of the selected airplane behind Home.
- The UI driver (`tests/ui_driver.gd`) and the EN/ES capture routes: every step below must extend them, not bypass them.

## What this audit does not prove

Xvfb with the OpenGL 3 driver in software: no real GPU, no HiDPI, no real monitor, no sound, no radio. Readability and the cost of any animation must be judged by the owner on the target machine. The independent reviewer saw captures, not the running app: hover, motion and latency were not reviewed.
