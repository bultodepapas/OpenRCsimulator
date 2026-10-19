# L21–L24: selectable landscapes

2026-10-19. Native Windows, pinned Godot 4.7.2 (`ed1daf0bf`), Compatibility renderer,
NVIDIA RTX 3090. The [contributor guide](../../../LANDSCAPES.md) owns the interface;
the [implementation plan](../../../plans/landscape-selection.md) owns remaining gates.

| Check | Result |
| --- | --- |
| Native `test_landscapes.gd` | 54 checks, zero failures; keyboard Club → Green → Club, saved relaunch, independent resources, night isolation, advancing fixed-wing/helicopter flights and restart. |
| `test_field_integration.gd` | Passed; customized-field injection and original default data preserved. |
| `test_world_flow.gd`, `test_ui_time_of_day.gd` | Passed; existing world flow and lighting UI retained. |
| Direct launches | Club and Green produce 61-row traces; unknown landscape exits 31 without a trace. Default and explicit Club traces match except `created_utc`, including identical simulation rows. |
| Exported Windows resource pack | Both landscapes fly from a pack mounted in an empty host project, producing 25-row traces. `check_field_pack.gd` validates both registered fields and existing field resources with zero engine errors. |
| Full fleet `test_ui_runway.gd` | Recheck pending after concurrent fuel/schema edits; the initial run refused P-51/jet energy capability values and a Timber battery-template hash. These paths were not changed by landscape work. |

The native captures are unedited test output. Home views verify selection presentation;
flight overviews use a temporary camera at render (0, 85, 120) looking at (0, 0, −90).

| Club field | Green paradise |
| --- | --- |
| [Home](club-home.png) | [Home](green-home.png) |
| [Flight overview](club_field-flight.png) | [Flight overview](green_paradise-flight.png) |

[Logs](logs/) and [capture identities](captures.json) retain the checks and source hashes.
Existing tree-wind and aircraft-inertia warnings are not landscape failures.
This is software/resource verification, not physical ground validation or a performance
claim. Full Linux/macOS/native Windows release exports and target-hardware acceptance remain open.
