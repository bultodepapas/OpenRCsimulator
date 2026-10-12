# LU-03 · Airfield lighting

Written **2026-10-11**. Step: **LU-03**. **Status: implemented; FW night visual check recorded.**

## Change

The scene-local `AirfieldLighting` helper adds visible hardware to the existing runway floods and edge markers, shallow window inserts and wall lamps only where validated scenery places a pavilion, and two veranda OmniLights. The existing three `FieldLights` SpotLights remain authoritative; the helper does not add runway marker lights or alter fixture positions. Hardware stays visible in daylight while the lamps and emissive sprites fade continuously from sun elevation 3° to −4°.

FW uses local-light gain 1. Explicit fixed-exposure SDR snapshots can pass a larger local-light gain (currently 1000); each spotlight, OmniLight, and sprite applies its authored display cap after the gain, then the dusk factor. The caps and gain are visual controls, not measured lux. The 0.16 m window inserts follow the prefab pane centres and use a shared MultiMesh for six panes and two lamps.

## Verification

- `\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_landscape_lighting.gd`: **45 checks, 0 failed**, on pinned Godot 4.7.2. It checks source counts, placement, dusk continuity, original-light restoration, high-exposure output caps, and the static-SDR gain path.
- Native command: `\.tools\Godot_v4.7.2-stable_win64_console.exe --path app --script res://tests/capture_landscape_upgrade.gd -- --time_of_day=night --cases=postcard_club,pilot_north --out=<output> --frames=4`.
- Capture device: NVIDIA GeForce RTX 3090, OpenGL 3.3 Compatibility renderer, 1280×720. `World.update()` warmed each view for 60 frames, then the script recorded four frames per view. The retained JSON includes raw timings and renderer metadata.

| View | Draws | Primitives | Median / p95 frame time | Adapted exposure |
| --- | ---: | ---: | ---: | ---: |
| `postcard_club` | 74 | 406,802 | 1.76 / 1.79 ms | 1,987.79 |
| `pilot_north` | 64 | 361,575 | 1.66 / 1.77 ms | 1,987.79 |

At this camera, the capped runway pools are visible across the near field and runway markers remain legible. The edge between lit pools and the dark field remains distinct, and the clubhouse reads small in the wide postcard view. This single high-end GPU capture is not target-hardware or pilot acceptance; the four timing samples are descriptive only.

The retained [clubhouse view](postcard_club.png), [pilot-threshold view](pilot_north.png), and [raw capture report](capture-report.json) are beside this report. These captures predate the final one-per-pane mullion detail; that geometry remains in the merged pavilion mesh and adds no draw call. Final 1080p captures of both FW and explicit static TOD night, with 600 timing samples per view, are retained in [LU-06](../LU-06/README.md).
