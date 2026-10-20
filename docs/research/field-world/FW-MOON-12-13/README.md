# FW-MOON-12/13: moon choices and their controls

**Status:** engineering-verified 2026-10-19. The code was delivered earlier on 2026-10-19, without this record. This record was written afterwards from the code and the tests; it adds the missing preference round-trip checks. Plan: [moon plan](../../../plans/moon.md) §5.

## FW-MOON-12: `openrc-moon-config v1`

[moon_config.gd](../../../../app/environment/moon_config.gd) validates and resolves the choices; nothing unvalidated reaches the renderer.

- **Keys:** `format`, `moon` (`real` · `phase` · `off`), `phase` (8 names), `night_look` (`eye` · `cinematic` · `camera`), `size` (`real` · `large`), `moonlight` (`real` · `bright`), `halo` (`auto` · `off`). A configuration must contain exactly these keys with known values.
- **Precedence:** command line > environment > interactive session > defaults. Direct technical launches never read preferences (`app_root.gd` clears the session choice for them).
  - CLI: `--moon=real|off|phase:<name>`, `--night-look=`, `--moon-size=`, `--moonlight=`, `--moon-halo=`.
  - Environment: `OPENRC_MOON*` twins.
  - A bad value keeps the previous layer, with a warning.
- **Phase choice:** `apply_phase` moves the date to the nearest local date within ±15 days, at the same clock time, whose moon age is closest to the named phase (±6°). The renderer then shows that real sky: the terminator is never faked.
- **Rendering effects** (`SkyState.state`):
  - `off` removes the disc, the moonlight and the moon's sky glow;
  - `large` doubles the disc (cinematic, labelled "not real");
  - `bright` triples the moonlight (assist, labelled).
  - The state records the choices.
- **Not yet used:** `night_look` is validated and stored but changes nothing until FW-MOON-07. The controls keep their current values.
- **`halo`** (FW-MOON-08, 2026-10-19): `off` removes the moon's aureole (`SkyState`) and its glare (`MoonGlare`); `auto` keeps both. It has no control yet (FW-MOON-13).
- **Preferences:** `[moon] config` is an additive section (no schema bump, the `[hud]` precedent). An older file without it loads the real moon. A broken section loads the real moon with a note. `save_to` refuses an invalid choice.
- **Visual only:** the choices never enter physical weather, aircraft state, flight-model checkpoints or traces.

## FW-MOON-13: controls (partial)

- The Moon group lives in [time_of_day_controls.gd](../../../../app/ui/time_of_day_controls.gd), not in a separate `moon_controls.gd` as the plan proposed. It appears in Conditions → Time of day and in pause → Sky and lighting ([weather_dialog.gd](../../../../app/ui/weather_dialog.gd)).
- **Choices:** Real sky · Choose a phase · No moon; phase; size; moonlight. Non-physical labels say "not real".
- **Live summary:** phase, % lit, rise/set and any moved date. The phase picker is enabled, and in the focus order, only for "Choose a phase".
- **Applying:** `app_root._apply_moon_config` validates, sets the session choice, applies it in place to the live flight or Home world (`World.set_moon_config`, also while paused) and saves it when it changed.
- Spanish labels are in [es.po](../../../../app/i18n/es.po).
- **Open:** the preview disc (the real `moon_disc.gdshaderinc` in a canvas item), the Moonrise / Moon high / Moonset jump buttons, the Home label and brief, "Tonight", and controls for night look and halo once they do something.

## Verification

| Check | Result |
| --- | --- |
| [test_world_moon_config.gd](../../../../app/tests/test_world_moon_config.gd) | 53/53. Validation refuses missing, extra, unknown and wrong-format values. Precedence, and an invalid session ignored as a whole. Eight phases within 7° of age, within 15 days at the same clock. `off` / `large` / `bright` effects; empty config equals defaults. Preference round trip, missing section, broken section with note, invalid never written (six checks added 2026-10-19). |
| [test_ui_moon_controls.gd](../../../../app/tests/test_ui_moon_controls.gd) | 13/13. Starts from the saved choice and reads it back; phase picker enabling and focus order; summary content for phase, real sky and no moon; "not real" labels; Spanish catalog. |
| [test_world_moon_flow.gd](../../../../app/tests/test_world_moon_flow.gd) | Covers applying "no moon" in place during flowing time (FW-MOON-03b). |
