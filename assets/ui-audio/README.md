# Menu audio asset provenance

UI-28 · Updated 2026-10-24. Runtime menu effects use wood and soft impacts from Kenney's **Impact Sounds 1.0** (2019), under CC0. The hollow, coconut-like direction uses this downloaded foley family. The package page and license are:

- Package: <https://kenney.nl/assets/impact-sounds>
- Direct archive used: <https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip>
- License: <https://creativecommons.org/publicdomain/zero/1.0/>
- Archive SHA-256: `029D734AF1582474EDF3A694D1B0CEBC97C1C152F2F39FA34D4C2BAFC5DE77F8`

The upstream `License.txt` is retained beside this file. Fourteen unmodified OGG files are copied from the archive's `Audio/` directory into `app/assets/ui/audio/`. Playback gains and small downward pitch offsets live in `app/ui/menu_audio.gd`. Navigation rotates through three actual takes without using the simulation RNG.

| Runtime file | Upstream file | SHA-256 |
| --- | --- | --- |
| `accept.ogg` | `impactWood_medium_004.ogg` | `7BA48F2F99C91C71BE420841A91F1E69C0CBC4FE887FCD7213144D67BB87B13A` |
| `back.ogg` | `impactWood_medium_000.ogg` | `1723A9FD25103ED41AF06054814E84E65F4A772BAC86AB2DC927DA93D9592FF5` |
| `exit.ogg` | `impactWood_heavy_003.ogg` | `AF07511902B309B3F6D8F0E1FAFBE93869127FB88099EBDC0AA6A00A98DC3CB0` |
| `navigation.ogg` | `impactWood_light_001.ogg` | `4B76BF3CCC8E60D19188F3165B778A7817786FAA6887C55D9049BCBEEF3B425F` |
| `navigation_2.ogg` | `impactWood_light_002.ogg` | `B183CF7A5BD783817E0E4B82AF34AC6658FA1927049089DADC8B15C2ECC771DC` |
| `navigation_3.ogg` | `impactWood_light_004.ogg` | `E10009F67DDAEB3A59A3E1129CFC1615D84BA60AB578EAE07E7092AC223F099C` |
| `open.ogg` | `impactWood_light_003.ogg` | `CDFBE8AF2FE7FF9EE28F337A0A989DEEE0F327620DA456C8413644880E9D0004` |
| `pause.ogg` | `impactSoft_medium_001.ogg` | `7642A4FD43E547AFE4F7ADFADB3DABB681C0FF512F52C1674BAE30A726841FAF` |
| `press.ogg` | `impactWood_light_000.ogg` | `EB45E35B4BED784D3F120DE4AFEC4B0D6AC09D9E143CCE8CFCB7D739E1B1F3C3` |
| `range_tick.ogg` | `impactSoft_medium_000.ogg` | `7D3BA0BB5E60A11B5D3E558C141303DCF494256675FBF753C0D252D2CF0481E3` |
| `reject.ogg` | `impactSoft_medium_003.ogg` | `5C4A1F35FDE7E14046931DA7BC3D1B23736541B7190BA107E08A379C4CA43CD6` |
| `restart.ogg` | `impactWood_medium_003.ogg` | `635C37CFCD854B187D643D450FF0397798DCC29AE94DA32192B814FAE6BD854C` |
| `resume.ogg` | `impactWood_medium_001.ogg` | `15271DBE8E2872DBB0FF1AEB7B12B2D2B92B7C1951C88532B9AB9158C36DFC73` |
| `selection.ogg` | `impactWood_medium_002.ogg` | `3F3F1917428B828F733A963167833C707BF88296FF158E1559C57C5CB813D799` |

## Interaction contract

Opening, pausing, resuming, restarting, leaving an activity and quitting have explicit cues. Successful Keep uses `saved`; Revert/Stay use `cancel`; failed launch/restart/save/trace recovery use `reject`. Outcomes suppress incidental presses and screen mounts from the same action. Two voices remain the limit; obsolete tails fade over 18 ms and navigation waits for semantic feedback to finish.

Quit sounds only after draft/trace decisions finish. Native audible output waits for its short closing tail, capped at 500 ms; this wait and the voice fades use wall time independently of simulation speed. Muted and Dummy routes close immediately. Window-close recovery preserves the open Settings draft when the user stays. Technical flight routes keep menu audio absent.

Observed menus include controls added or reparented after mounting. Eligibility reads live disabled/editable values from property names cached at registration. Signal bindings and per-control debounce entries are released when controls leave the tree. Home/End/Page keys receive the same range feedback as directional adjustments.

Reproduce the asset bank by copying the table's source files, preserving bytes, then importing with the pinned Godot editor. [Native output probe](../../tools/audio/README.md#menu-feedback) records all cues at default/maximum/muted levels and checks the production closing-tail transaction. Earlier UI-28-R3 evidence describes the superseded Interface Sounds bank.
