# VQ-06b / VQ-01c geometry-audit follow-up

2026-11-09. The supplied triangle-budget audit of `f47d1dc6` was checked against
`1094aded3b7a339a99ca27299d765217caa3ba7e` plus the existing dirty working tree.
Tree, Timber and Workshop work already present in that tree is outside this change.

## Implemented scope

- Automatic starts unrecognized or unreported GPUs at Medium. Explicit choices and
  the no-preference tool default retain their existing precedence. This intentionally
  selects the existing Balanced ornament/collision world on the next flight; no
  live automatic changes or collision redesign are introduced.
- Frame reports separate requested detail and live LOD from the installed scenery
  tier, collision identity, detailed-tree count and meadow inventory. Source hashing
  now includes runtime scenery and landscape code. These are endpoint observations
  and partial source provenance, not complete asset or settings-history evidence.
- The native reducer rejects mixed recorded configurations/sources. Its optional
  `--require-1080p` gate uses the window size and scoped render-target estimate,
  retaining the distinction from logical canvas size and physical presentation.
- The existing [scenery diagnostic](../../../../tools/scenery/README.md) retains its
  separate world-only 720p scope and numerical caps. Engine/renderer identity and raw
  shadow-counter semantics are explicit. Report-only collection permits rebaselining
  with the current engine without accepting old hardware assumptions.

## Software checks

Native Windows, Godot `4.8.beta2.official.cafc17a19`:

- `test_scene_detail.gd`: passed, including unknown/no-GPU Automatic, explicit High
  and the no-preference High fallback.
- `test_landscape_collision_setup.gd`: 25 checks, zero failures, including independent
  Balanced visible-placement/proxy identity checks.
- Main and visual-evidence GDScript parse checks passed.

Checked logs and raw measurements are retained outside tracked source under
`tmp/geometry-audit-20261109/`. [Collector/reducer contract](../../../../research/performance/README.md#geometry-audit-follow-up-vq-01c--vq-06b-2026-11-09).

## Native measurement limits

The first full-session circuit sample used an RTX 3090, NVIDIA OpenGL 3.3 driver
617.42, Compatibility, Stik, Club, High detail, native scale, 4× MSAA and a requested
1920×1080 window. The output estimate and logical canvas both recorded 1920×1080.
The existing sustained-flight fixture used the normal 240 Hz simulation and its
bounded circuit pilot; controls were not manually stepped.

Requested warm-up/sample: 10/60 seconds, 60 FPS cap, VSync disabled. It stopped at
10,471 accepted ticks after focus loss: `complete=false`, `timing_eligible=false`,
two focus-loss observations and one pause. Its 2,037-frame recovered sample is
diagnostic only; it cannot establish frame-time acceptance, a GPU ceiling or a
before/after speedup. Raw report, health/source receipt and checked log remain in
`tmp/geometry-audit-20261109/baseline/`.

Aircraft budgets and generated geometry are unchanged. Avanti material batching,
new LOD/HLOD assets, the full aircraft/view/lighting matrix, measured device
profiles and minimum-hardware qualification require their own matched evidence.
The [Godot LOD guide](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html)
supports checking both view resolution and camera FOV when comparing submitted geometry.
