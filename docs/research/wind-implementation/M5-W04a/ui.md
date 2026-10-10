# M5-W04a: turbulence UI and rendered evidence

2026-10-09 · **Status: implemented and software verified.** Captures validate layout and localization, not GPU quality, atmospheric realism or pilot acceptance.

The [weather dialog](../../../../app/ui/weather_dialog.gd) keeps the six original wind/gust inputs on **Wind & Gusts** and puts RMS N/E/Up, correlation time and seed on **Turbulence**. Readable decimals avoid binary tails such as `0.59999999999999998`; very small values use scientific notation. Unchanged text retains the original float64 value in the draft on Apply. Decimal display strings are not the binary replay contract. The tab bar and action buttons stay visible while the tab body scrolls and follows keyboard focus. A deferred layout update measures the panel's actual minimum height and gives the tab body the remaining viewport space; it recalculates on viewport, locale, error and tab changes. [Home](../../../../app/ui/home.gd) shows a localized turbulence summary, and [Help](../../../../app/ui/help_screen.gd) describes the updated conditions.

V1 weather still writes the outer preferences schema as version 1. V2 turbulence writes schema 2 so older builds treat the file as newer and cannot overwrite its unknown turbulence fields; see [preferences](../../../../app/app_state/preferences.gd).

Pinned Godot 4.7.2 software-rendered captures ran through the [capture helper](../../../../app/tests/capture_ui.gd). The Home route shows the remembered turbulent practice preset and starts with focus on `Fly`. At 1024×720, both tabs fit; the dialog panel is `[132, 28, 760, 664]`. Wind starts on focus `WeatherPreset` at `/root/AppRoot/WeatherDialog/Modal/@CenterContainer@72/WeatherPanel/@VBoxContainer@73/@HBoxContainer@88/WeatherPreset`. Turbulence starts on focus `EnableTurbulence` at `/root/AppRoot/WeatherDialog/Modal/@CenterContainer@72/WeatherPanel/@VBoxContainer@73/WeatherBodyScroll/WeatherPages/TurbulencePage/EnableTurbulence`.

At 800×600, the English and Spanish Turbulence dialogs fit at `[20, 16, 760, 568]`. The Spanish invalid-seed view keeps the wrapped error and both actions visible. Focused captures verify that keyboard navigation scrolls the seed field into view at 800×600 (`scroll_vertical=100`) and 800×700 (`scroll_vertical=4`); in both, the field is fully inside the tab body's scroll viewport. The UI regression also moves focus to the final field and verifies that scrolling follows it.

PNG files and capture sidecars are local, gitignored outputs in `app/captures/turbulence/`; they are recorded here by basename and SHA-256 instead of linked.

| Capture | Size | SHA-256 |
| --- | ---: | --- |
| `en-home-1024x720.png` | 1024×720 | `68913c312375f208660eccb18f95cf7aa35214e1811a63caddab037d8ecb5c98` |
| `es-home-1024x720.png` | 1024×720 | `df3a396a4587c0fcef8a07de7bc157bfa64b2f67a40025e353ebceab13858bd6` |
| `en-wind-1024x720.png` | 1024×720 | `c97289f22e4bd1b79085cb7a49a080f457878b17f005aca254133a66332c8301` |
| `en-turbulence-1024x720.png` | 1024×720 | `aecd19e54f8cbf7a06e296d660e272415d0c1431b2c1cd7e6500f084adde5a9a` |
| `es-wind-1024x720.png` | 1024×720 | `0d888df492667f32de48dd07d326bbdc20d348ea0fd444e975404ae0eab5404d` |
| `es-turbulence-1024x720.png` | 1024×720 | `27953987207550c4fc525c60d81c2eedb7832a5a59da8d0644d86c272bae4a86` |
| `en-turbulence-800x600.png` | 800×600 | `f7004e6efe21ebd154abcc17d0ab9c52bf735b4705a47c507e93acef58efe4c0` |
| `es-error-turbulence-800x600.png` | 800×600 | `6adee4a24c3c81e906e6623eccc312b25f48d8cb770e22d78281ee0289c23040` |
| `en-seed-focus-800x600.png` | 800×600 | `af40a303fa65960dcc0dfad19b4fb1dce388059be67bb378343de5f5c7f2b02c` |
| `en-seed-focus-800x700.png` | 800×700 | `20786287534d631c0af2b7496063ec7a328c7c01c5e75e263700ff30967b01cb` |

The [turbulence UI regression](../../../../app/tests/test_ui_turbulence.gd) passes, including legacy v1 preservation, exact turbulence values and uint32 entry, tab focus, keyboard-follow scrolling, preset text (`0.6`/`0.4`), unchanged high-precision v2 Apply, future-schema protection and Home→Fly handoff. The existing [weather UI regression](../../../../app/tests/test_ui_weather.gd) and [Help regression](../../../../app/tests/test_ui_help.gd) pass. The existing weather test has a single `AudioStreamGeneratorPlayback` shutdown leak reproduced on the frozen baseline; the new turbulence UI test exits without that leak.
