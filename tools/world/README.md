# tools/world

Field world tools ([FIELD-WORLD-PLAN](../../docs/FIELD-WORLD-PLAN.md)). Python tools use the standard library only.

| Tool | Step | What it does |
| --- | --- | --- |
| `parity.sh <out> [--compare <manifest>]` | FW-01 | Renders 89 fixed views through every world-assembly site (flight, atmosphere fixture, Home, scenery views, runway scenario) plus a headless trace, and writes SHA-256 per output. FW-A steps must leave it unchanged on the same machine. Needs `xvfb-run` or a `$DISPLAY`; forces llvmpipe, one thread |
| `sky_table.py [--check]` | FW-21 | Physical sky per sun elevation → `app/data/sky/sky_table.json` (~30 s). `app/test.sh` runs `--check` |
| `stars.py [--check]` | FW-24 | Naked-eye stars from `assets/sky/bsc5.dat.gz` (SHA-256 checked) → `app/data/sky/stars.json`. `app/test.sh` runs `--check` |
| `moon_texture.py [--check]` | FW-MOON-04 | Moon albedo and LOLA normal map from `assets/sky/moon/source/` (SHA-256 checked) → `app/assets/sky/moon/`. **Exception to stdlib-only:** needs numpy and Pillow, run with `"$(app/tests/visual-env.sh)"` (pinned, hashed). See [Moon textures](#moon-textures-fw-moon-04) |
| `moon_fixtures.py [--svs <mooninfo_2026.json>]` | FW-MOON-02 | Reference data for `test_world_moon_lunar.gd` → `app/tests/fixtures/moon_reference_v1.json`: a 120-row subset of NASA SVS 5587 (local file, SHA-256 checked), JPL Horizons topocentric positions and rise/transit/set queried at run time (network), and Espenak's eclipses and phases. Stdlib only |
| `godot --path app --script "$PWD/tools/world/moon_capture.gd" -- --out=<absolute folder> [--cases=a,b] [--close-fov=1.2]` | FW-MOON-03/05 | Production-rendered moon: a close-up aimed at the disc and a wide pilot view per case (full, crescent, quarter, Harvest Moon rise, southern hemisphere), plus `manifest.json` with the Lunar state. Needs a renderer (`xvfb-run` here) |
| `capture_times.sh [out] [preset ...]` | FW-22…35 | Five views per time-of-day preset and a contact sheet (`index.html`) |
| `godot --path app --script res://tests/capture_aircraft_lights.gd -- --out=<absolute folder>` | FW-62-R1 | Real-renderer checks for dark wing blocks, underside visibility, zoom/resolution sizing and opaque foreground occlusion; writes PNGs and `summary.json`, exits nonzero on failure. Use the pinned engine; `app/capture.sh` also runs it under Xvfb. |

On WSL without root, `xvfb-run` is usually missing: WSLg's `$DISPLAY` works, and software GL is forced by the scripts (`LIBGL_ALWAYS_SOFTWARE=1`), so results compare only with runs on the same machine.

## Moon textures (FW-MOON-04)

`moon_texture.py` turns the NASA SVS CGI Moon Kit downloads in `assets/sky/moon/source/` into the runtime textures in `app/assets/sky/moon/`. It checks each source against [PROVENANCE.json](../../assets/sky/moon/PROVENANCE.json), has no network access and never hand-edits outputs:

```bash
"$(app/tests/visual-env.sh)" tools/world/moon_texture.py           # write
"$(app/tests/visual-env.sh)" tools/world/moon_texture.py --check   # exit 1 unless byte-identical
```

- `moon_albedo_2k.jpg`: the SVS 2025 colour map, copied byte for byte (2048×1024, sRGB).
- `moon_normal_1k.png`: 1024×512 RGB8 normals in the local (east, north, up) frame, encoded as 0.5 + 0.5·n in linear data. It is built from LOLA `ldem_4_uint.tif` on the 1737.4 km sphere with physical relief, faded to straight up between 86° and 88° latitude.
- `LICENSE.md`: credit ("NASA's Scientific Visualization Studio"), NASA media terms and hashes.

Both textures map u = (east longitude + 180°) / 360° and v = (90° − latitude) / 180°: the left edge is 180° W and north is at the top. Shaders sample the albedo as `source_color` and decode the normal map as n = 2·rgb − 1, then renormalise. The `.import` files keep both textures lossless with mipmaps, `normal_map` disabled and `detect_3d` off. Method, hashes, sizes and the visual check are in [FW-MOON-04](../../docs/research/field-world/FW-MOON-04/README.md).

The PNG is deflated with the standard-library `zlib`. A different zlib build (for example zlib-ng) yields identical pixels in other bytes; `--check` then fails and says so.
