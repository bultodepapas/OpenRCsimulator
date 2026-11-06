# UI-32 — preserve choices

2026-10-20. This step repairs [UI-30](../UI-30/README.md) findings AS-3, AS-4, AS-7 and F8. It follows the [redesign plan §11](../../../plans/menu-redesign.md#11-ui-30-audit-repairs). The rule it enforces: browsing never overwrites a saved choice as a side effect.

## Behaviour

| Finding | Change |
| --- | --- |
| AS-3 | Selecting the helicopter no longer rewrites the saved weather. Home and the Conditions dialog show it without turbulence (`app_root.weather_for_aircraft`), and the helicopter flight is launched without it. The saved airplane turbulence survives selection, Home rebuilds, helicopter flights and wind edits made while the helicopter is selected (`_weather_keeping_saved_turbulence`). |
| AS-4 | Battery mode and fuel fill are saved after a successful Fly. They survive End flight and an application restart. |
| AS-7 | Home keeps one start per vehicle class. The airplane start is the existing `start_choice`; the rotorcraft pad or hover start is new. Browsing the helicopter or a runway-less landscape only limits what is shown and launched; returning restores the remembered start. |
| F8 | Selecting an aircraft or landscape keeps Home's note (a failure debrief or a launch rejection). Only a failed save writes a note, and a later successful save clears only that note. |

**Preferences.** The new `[flight]` keys are additive and need no schema change, like `landscape`: `rotorcraft_start_choice` (`runway`/`airborne`), `battery_mode` (`ideal`/`pack`) and `fuel_fill` (one of `Preferences.FUEL_FILLS`; Home now reads that constant). Older files load with the defaults. Saving refuses invalid values.

## Proof

[`test_ui_preserved_choices.gd`](../../../../app/tests/test_ui_preserved_choices.gd) is new.
- Before the change it reported 7 failures, then stopped at a script error (the preference did not exist).
- After the change all 18 checks pass. They cover turbulence round trips, starts per class, landscape round trips, the note, and battery/fuel across End flight and an application restart.

Three [`test_ui_home.gd`](../../../../app/tests/test_ui_home.gd) checks encoded the lossy contract (saved weather equal to the stripped helicopter weather). They now assert the opposite: the display is stripped and the saved turbulence is kept.

Regression runs:

| Suite | Result |
| --- | --- |
| `test_ui_home` | 242 ok |
| `test_ui_aircraft` | 65 ok |
| `test_ui_battery_mode` | pass |
| `test_ui_home_start_layout` | pass |
| `test_ui_language` | 26 ok |
| `test_ui_weather` | pass |
| `test_landscapes` | pass |
| `test_ui_natural_random` | pass |
| `test_settings_ui` | pass |
| `test_ui_home_layout` | pass |

**Limits.** Only the Home route is covered. Direct technical routes still use defaults and never read preferences.

## Wind preset scope (UI-32-R1, 2026-11-06)

External audit **A11 R01** reproduced a wind preset replacing custom air at
1,500 m / 35 °C with reference air. Wind-only selections now replace wind,
gusts and turbulence while retaining the atmosphere source values, mode,
pending text and edit baselines. Invalid air remains visible and blocks Apply.
This includes spatial wind transitions and the altitude-dependent standard
column; untouched atmosphere values retain their source float64 precision.

The catalog explicitly marks **Hot and high**, **Cool dense air** and
**Standard dry ISA column** as composite presets. Their picker captions disclose
**Wind + Atmosphere**, using existing translations. They replace both domains,
including an unfinished atmosphere draft. The picker is labeled **Conditions**;
a combination that differs from every complete authored preset reopens as
**Custom**. CLI/scenario preset configurations and physics equations are unchanged.

The production regression drives actual popup selection, text entry and
Apply/Cancel controls. It covers every wind-only preset against custom and
standard-column air, pending mode/value changes, invalid text, legacy schema
preservation, spatial transitions, composite replacement and Home persistence.
Both atmosphere modes survive Apply, preference reload and reopening; Cancel
preserves the accepted in-memory configuration and exact preference-file bytes.
Persistence checks compare against the serialized input actually loaded by Home.

[Source identities and checked receipts](preset-scope-20261106/verification.json)
retain the identical regression before (**98 failures / 258 checks**) and after
(**258 passing checks**), with zero engine errors or warnings. The final focused
selection passes **664 checks across seven suites**:

| Suite | Passing checks |
| --- | ---: |
| `test_weather_preset_scope` | 258 |
| `test_ui_weather` | 67 |
| `test_ui_atmosphere` | 47 |
| `test_ui_spatial_weather` | 64 |
| `test_ui_preserved_choices` | 19 |
| `test_spatial_wind_contract` | 176 |
| `test_ui_weather_sliders` | 33 |

The [tested snapshot](preset-scope-20261106/tested-snapshot.patch) reconstructs on
`a9720f5a5ebb24dd37b3909c87f6741dae7a61f3`; the five integrated source/test/UID files
match its recorded hashes. Three retained texture import-metadata differences
belong only to the isolated test workspace. Earlier incomplete fixtures and
failed attempts remain in the receipts, including the corrected popup-window
input route, text replacement and persisted-value oracle. The CI unit roster
discovers the new test. Independent Good Enemy source review prompted the column
round-trip coverage and clearer composite scope.

Windows Godot `4.8.beta2.official.cafc17a19`, headless; the new regression uses a
1920×1080 logical viewport. This establishes software behavior, not native visual,
hardware, physical or release qualification. Required full CI remains pending.
