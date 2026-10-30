# Skywalker X8 r4: sources and pipeline

`skywalker-x8` is the stable visual-family ID of the MoonRunner X99 flying wing ([X8 plan](../../../docs/X8-PLAN.md)): the author's parametric r4 game model of a 2.12 m EPO flying wing with two elevons, winglets, an electric pusher and no landing gear. The delivery is frozen in `assets/source-deliveries/skywalker-x8-r4/` without its images (owner rule) and identified by [source-manifest.json](source-manifest.json). The family builds through the shared imported-scene builder and has experimental physics data and a catalog entry (X8-06, X8-09).

## Sources

| File | Content |
| --- | --- |
| [source-manifest.json](source-manifest.json) | Generated (X8-00): SHA-256 and size of every frozen delivery file, the author's hashes of the omitted images, key files by role, both skin GLBs, visual revision `r4-3e14a512fac3` |
| [model-geometry.json](model-geometry.json) | Generated (X8-02): rest transforms read from the GLB and checked against the delivered metadata; elevon ranges, clearance and app sign; thrust frame and propeller diameter; static camera-door pivots; sections, landmarks, datum notes; both skins. Mirrored as `app/aircraft/skywalker_x8_geometry.gd` |
| `app/assets/aircraft/skywalker-x8/` | `skywalker_x8.glb` (`abisal`, default) and `skywalker_x8_bolido.glb`, byte-identical to `export/aircraft.glb` and `export/bolido.glb`, with the Avanti/F4U import settings; `LICENSE.txt` is the delivery's own |

Never edit generated files by hand.

## Frames and datum

Model frame: metres, +X right, +Y up, −Z nose. The root `SkywalkerX8` is the identity at **D0**: symmetry plane, wing leading edge at the orange root-rib station (s = 236 mm, 299.581 mm behind the nose) and thrust-axis height (delivery README §6). The model datum selectors are `(0, 0)`: a physics file that uses D0 as its LE datum (`[x_aft, y_right, z_up] = [z, x, y]`) needs no offset. The physical root-rib leading edge (landmarks `wing_root_leading_edge_left/right`) lies 0.8 mm aft of and 7.0 mm above D0 at y = ±0.2376 m. D0 is not the CG; the manufacturer's CG reference is 430–440 mm from the nose (z = +0.130…+0.140 m).

## Controls and mechanisms

| Node | Binding | Notes |
| --- | --- | --- |
| `elevon_left_hinge`, `elevon_right_hinge` | Roles `elevon_left`, `elevon_right` | Local +X hinge axis; delivery + = trailing edge down; range −26.76…+26.85° (full servo travel), clearance −40…+31°; `app_sign` −1. The renderer draws elevon = elevator + that side's aileron (app degrees, trailing edge up) |
| `thrust_frame` → `propeller_spin` | Rotor, axis +X | Pusher hub 0.546 m aft of D0; local +X points at the nose; measured diameter 0.3049 m (12 in) |
| `camera_door_left_hinge`, `camera_door_right_hinge` | None | Not a supported mechanism role (canopy, tailhook, cowl flaps): the doors stay closed at rest |
| `canopy_hatch` | Crash section `canopy` | Detachable magnetic hatch; no opening mechanism |

Crash sections come from the GLB's `openrc_section` extras (`core`, `canopy`, `wing_left`, `wing_right`, `engine`, `propeller`). Workshop paint slots (`body`, `wing`) target the default skin's `x8_livery` surfaces only; the delivery declares no lamps.

## Regenerate and verify

```sh
python3 research/skywalker-x8/X8-00/manifest.py --check
python3 research/skywalker-x8/X8-02/install_assets.py          # copies GLBs, licence and new sidecars
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --import
python3 research/skywalker-x8/X8-02/install_assets.py --check
python3 research/skywalker-x8/X8-02/compile_model.py           # then --check
python3 research/aircraft-standardization/build_models.py      # then --check
python3 tools/godot/run_checked.py --timeout 180 -- "$(app/get-godot.sh)" --headless --path app --script res://aircraft/verify_moonrunner_x99.gd
```

After a binding or model change, also run `build_customization.py`, `build_descriptors.py` and the parked-aircraft bake in the order of the [Avanti guide](../avanti-s-a200/README.md#regenerate-and-verify). Evidence: [X8-02](../../../docs/research/skywalker-x8/X8-02/README.md).

## Open items

- Camera doors: a mechanism role and its flight trigger are undecided; until then they are static.
- Asset licence terms are **not set** by the owner (`LICENSE.txt`); no redistribution terms are implied ([X8 plan D2](../../../docs/X8-PLAN.md#4-owner-decisions)).
- Runtime textures are 2048² per skin; the closest Workshop view magnifies them about 2.5× at 1080p (3.4× at 1440p). The 4096 sources were not copied; choosing them is open.
- Godot import memory and rendered frame cost are not measured yet. The display name is a working name pending the owner's decision.
