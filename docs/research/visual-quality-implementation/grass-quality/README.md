# Grass quality implementation

2026-10-17. Owner: landscape L, coordinated with VQ and RCV. Implementation and verification in progress. The [plan](../../../plans/grass-quality.md) owns remaining acceptance; the [44 investigations](../../grass-quality-2026-10-17.md) own external references. This report owns the experiment decisions below.

## Frozen comparison

Baseline: `9e721d479ab14f2d2da614f305012241004576c7`. Separate imported worktrees prevent unrelated work in the shared checkout from changing a comparison. Native renderer: Godot `4.7.2.stable.official.ed1daf0bf`, Windows, OpenGL Compatibility, RTX 3090, NVIDIA 617.42, 1280×720, 4× MSAA. This driver differs from the historical L9e evidence; old timing results are not reused.

`quality_capture.gd` builds the production field with high scenery and freezes node processing. Camera, lighting, wind and wrapped simulation clock are explicit. Images cover the pilot edge, a 0.55 m low view, overhead, zoom and a 12-step, 3 m camera traverse. These are renderer fixtures, not complete flight or driving sessions. GPU work runs serially. Headless checks establish resource/code contracts only.

## Decisions and implementation

| Step | Finding / disposition |
| --- | --- |
| VQ-02a | The three grass sources are opaque, double-sided, per-pixel Burley/Schlick-GGX materials with the same retained palette texture. Import→static→adapter properties agree. Source glTF contains nonwhite vertex colors, but the effective imported material disables them. Preserve that effective setting; enabling it would change the baseline. |
| VQ-02a filtering | The imported palette atlas has no mip chain despite the source sampler requesting mip filtering. It is a narrow color-ramp atlas, not a detailed blade photograph. No import setting is changed without a reproduced sampling defect and an edge-bleed comparison. The retained photographic grass maps already have mipmaps. |
| L9e-R1 | Reject the three-band Laplacian candidate after visual screening. It preserves disabled-detail and aerial pixels exactly, but gives no clear improvement to the needle-like close texture. It requires eight source-level filtered fetches instead of two. No runtime timing or performance benefit is claimed for the rejected candidate. |
| L9e-R2 | Candidate: reuse retained ambientCG Grass001 albedo/normal/roughness at the existing 1.4 m scale in shared ground. A separate grass binder enables grass without enabling RC soil. The RC binder and track coverage retain their existing route. The photograph gives more convincing close turf than the procedural blade pattern. |
| L15c | Candidate: a grass-only material adapter and opaque vertex shader. Source geometry, UVs, scalar PBR settings, vertex-color enablement and source texture are retained. Root-weighted bending follows existing world-space render wind. Trees, flowers and the scenery-off fallback keep their existing paths. |

Ground detail remains in the existing ground pass. The photographic weight attenuates the older turf detail and fades with distance/pixel footprint; it does not stack full-strength normals. Dirt requires both `rc_surface_enabled` and `rc_track_surface`. Every scene owns its material; the immutable imported textures are shared. No assets are generated or downloaded by this slice.

Wind uses `sim_clock`, not wall time. Both frequencies are integer multiples of 1/1024 Hz. Roots at the source bounds' base remain fixed; squared relative height increases bending toward tips. Horizontal displacement is capped at 12% of plant height (at most 3 cm for a 25 cm clump), including gust and flutter. The inverse-transpose of the bending shear adjusts normals. Each batch expands its cull margin by its maximum displacement. There is no per-frame CPU plant loop, collider, transparent pass or grass shadow casting.

## Material and motion evidence

The native fixture contains all three species, four yaw rotations and two supported uniform heights, translated to distinct positions: 24 plants in three source batches. It tests front light, back light, a shadow-casting occluder and a warm local light.

- Source versus adapted material with zero wind: **exact pixels in all four lighting cases**.
- Calm at times 0 and 1, wind time 0 repeated, and time 0 versus wrapped time 1024: **exact pixels in all four cases**.
- Nonzero wind changes the silhouette over time and reverses direction with reversed wind. A sample 1 ms before wrap changes only 142–154 pixels of 921,600; this is a near-boundary sample, not a proof of every animated frame.
- An earlier candidate explicitly flipped `NORMAL` for back faces and failed source parity. That extra flip was removed. The final result is established for the pinned engine and these source materials, not asserted as a universal shader rule.

Root darkening was not adopted. No emission, universal upward-normal replacement, vertex-color importer change, new alpha technique or mesh replacement is bundled with the wind change.

## Reproduction and limits

Use the same external capture script with `--path` pointing to each imported app snapshot. Output directories must be new. Inspect engine logs as well as exit status.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path <app-snapshot> --audio-driver Dummy `
  --script "$PWD/tools/grass/quality_capture.gd" -- --mode=capture --out=<new-absolute-directory>
& .tools/Godot_v4.7.2-stable_win64_console.exe --path <candidate-app> --audio-driver Dummy `
  --script "$PWD/tools/grass/material_capture.gd" -- --out=<new-absolute-directory>
```

`--ground=photo` is an explicit research probe using the existing RC binder; it is not the production grass-only binding. Add `--night` for the matched midnight fixture. `--mode=profile --variant=baseline|candidate --pair=1..5` uses 10 s warmup and 60 s measured wall time. Profiles exercise nonzero wind with a recorded clock protocol and contain no image readback during measurement. Wall interval, viewport CPU and viewport GPU metrics remain separate; unsupported zero GPU readings are unavailable.

The complete-session p95/p99 and simulation/wall-ratio gates, owner flight/readability review, both RC vehicles in actual sessions, packaging/lifecycle soak and lower-end/other-OS GPU acceptance are independent gates. Offscreen screenshots and render timings cannot close them. No physics or handling calibration is inferred from animation.
