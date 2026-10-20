# L21–L24: selectable landscapes

2026-10-19. Native Windows, pinned Godot 4.7.2 (`ed1daf0bf`), Compatibility renderer,
NVIDIA RTX 3090. The [contributor guide](../../../LANDSCAPES.md) owns the interface;
the [implementation plan](../../../plans/landscape-selection.md) owns remaining gates.

| Check | Result |
| --- | --- |
| Native `test_landscapes.gd` | 54 checks, zero failures; keyboard Club → Green → Club, saved relaunch, independent resources, night isolation, advancing fixed-wing/helicopter flights and restart. |
| Headless `test_landscapes.gd` | 49 checks, zero failures; includes the Natural Random availability guard. |
| `test_field_integration.gd` | Passed; customized-field injection and original default data preserved. |
| `test_world_flow.gd`, `test_ui_time_of_day.gd` | Passed; existing world flow and lighting UI retained. |
| Direct launches | Club and Green produce 61-row traces; unknown landscape exits 31 without a trace. Default and explicit Club traces match except `created_utc`, including identical simulation rows. |
| Exported Windows resource pack | Both landscapes fly from a pack mounted in an empty host project, producing 25-row traces. `check_field_pack.gd` validates both registered fields and existing field resources with zero engine errors. |
| Full fleet `test_ui_runway.gd` | The original run had one failed assertion: Timber launch was refused because its battery-template bytes did not match the pack's pinned hash. The release follow-up [passes the full suite in Linux CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/39370568586/job/118457276997), including Timber, P-51 and jet Home launches at idle with supported gear. |

The native captures are unedited test output. Home views verify selection presentation;
flight overviews use a temporary camera at render (0, 85, 120) looking at (0, 0, −90).

2026-10-19 export-gate follow-up: the release check's earlier `Pack missing L10a windsock data, mesh builder or material` message came from an outdated expectation of the packed field cue. `check_field_pack.gd` now validates the authored three-part `Fabric`/`Support`/`Basket` assembly, each mesh and shader material, and the required texture maps. A later Linux export attempt reached that validation but still exited on a typed-array script error; the checker now uses `PackedStringArray` for its texture-channel list. The corrected [CI export job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/39370568586/job/118457913934) passed all three platform exports and packed-field checks at source commit `4b5d46a974b48fd8cf8d91b927a5b1a00943b1f6`. Downloaded Windows and Linux candidate executables each completed a checked 721-row, three-second trimmed-flight smoke; all three archive checksums and embedded clean-source identities matched.

| Club field | Green paradise |
| --- | --- |
| [Home](club-home.png) | [Home](green-home.png) |
| [Flight overview](club_field-flight.png) | [Flight overview](green_paradise-flight.png) |

[Logs](logs/) and [capture identities](captures.json) retain the checks and source hashes.
Existing tree-wind and aircraft-inertia warnings are not landscape failures.
This is software/resource verification, not physical ground validation or a performance
claim. The export follow-up verifies package construction and the stated Windows/Linux smoke only; native macOS gameplay and target-hardware acceptance remain open.
