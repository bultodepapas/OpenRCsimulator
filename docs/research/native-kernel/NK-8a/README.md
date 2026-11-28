# NK-8a — the projected shadow's part walk in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

In the live app, in daylight, `main.gd` `_update_aircraft_shadow` costs about 150 µs per frame on the Corsair:
- `Shadow.receiving_ground`'s seven terrain samples through `main.gd` `_ground_height`, 55–66 µs;
- `Shadow.update`, 87–104 µs, of which `ProjectedShadow.refresh` is 70–78 µs.

Most of `refresh` is one GDScript loop, 57–60 µs. For each of the aircraft's 33 parts it climbs the scene tree to
the shadow's source:
- `_part_pose` composes the `Node3D` transforms;
- `_part_visible` checks every level's visibility.

## Change

- `nk_shadow_parts.hpp` runs both walks for every part in one call, exactly:
  - it reads each level's transform, visibility and parent by method bind;
  - it composes transforms with the engine's own `Transform3D * Transform3D` operator evaluator, the function
    GDScript calls, so the result is the engine's on every platform;
  - a part whose node is gone, or was never found, keeps its rest pose, as in GDScript. It is visible only when no
    node was found at bind.

  The kernel binds it as `shadow_parts_bind(ids, rests, bound)` and `shadow_part_poses(source_id)`. Nodes are held
  by instance id, so a freed node reads as gone, never as a dangling pointer.
- `render/projected_shadow.gd` `refresh` asks the kernel first. It rebinds when the parts change, tracked by a
  revision counter that `_parts.clear()` advances. Without the verified library, or with a library lacking these
  methods, `_part_pose` and `_part_visible` answer and stay the specification. Hook:
  `ProjectedShadow.native_part_poses_enabled`.
- Presentation only: nothing here reaches the simulation.

## Evidence

- `app/tests/test_native_shadow_parts.gd` (2 checks) builds a random 60-node hierarchy mixing `Node3D` and plain
  `Node` levels, with rotations, non-uniform scales and offsets. It binds 34 parts:
  - the source itself;
  - a node outside the source;
  - a part never found;
  - a part freed after binding;
  - 30 random nodes.

  Over 400 rounds of random transform and visibility changes, the native poses and visibility equal the GDScript
  walks bit for bit (`var_to_bytes`), hidden levels included. With the hook off, GDScript answers.
- Moving 1 % of the GDScript poses by 10⁻⁷ makes 60 of the 400 rounds differ.
- On the library and on GDScript, these pass: `test_aircraft_shadow_proxy`, `test_field_projected_shadows`,
  `test_flight_cue_shadows`, `test_projected_shadow`, `test_shadow_blur`, `test_shadow_collection`,
  `test_shadow_cue_controls`, `test_shadow_deferred`, `test_shadow_ownership`, `test_shadow_settings`,
  `test_vehicle_shadow_cue`, `test_windsock_shadow` and `test_wreck_shadow_cache`. The
  [NK-7](../NK-7f/README.md) audio parity tests pass on this binary.
- All nineteen installer gates pass for binary `0211e7305797be2cf314104f80338b6ca76e9c974887070983e88fbeb63ffa66`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T062845835040Z.json` `16ac23213065f155ecb0623f93616ca6dccd441b4671c103896b5e63a8833f03`
  - `stage_mutant-20261128T062911283810Z.json` `b2bfe1a8ead65a8d064dca22e005994c289bce983eaa51d1506431ae88517405`
  - `trajectory-20261128T062936696867Z.json` `07ae744c8deb785910efcb8af429d393fb05d0f21ee2470bcf5d4e977d79d560`
  - `legacy-ground-20261128T063310792145Z.json` `bc3b96c981117110b7c3c31999a6ae01e0a6217bfc24c512ed01ba3b7bf17a5b`

## Gain

Live Windows app, 1920×1080, native backend, Corsair airborne in daylight. Each sample is 8 interleaved blocks of 100
`refresh` calls on the current request. Over two samples, `ProjectedShadow.refresh` went from 77–79 µs to
22–24 µs per frame, with identical poses.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- `receiving_ground`'s terrain samples are unchanged; they go through `main.gd`.
