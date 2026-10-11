# GP-01 terrain draft evidence

Status: integrated and reviewed on 2026-10-11; draft captures and post-merge checks retained. This is software verification, not physical validation.

The draft adds deterministic load-bearing micro-relief over the validated field rectangles. `GroundTerrain.sample(north, east, surfaces)` returns `[height_up_m, dh/dnorth, dh/deast]`; the six-float surface table uses the existing runway → mown → rough precedence and rough outside catchall. `sample_validated` is the multi-wheel fast path after callers validate a stable table once. The empty table is an explicit flat fixture; malformed tables and non-finite queries fail closed with NaNs. `max_height_validated` returns a conservative 7 mm bound for any accepted nonempty profile.

Initial values are estimates, not measurements: 1 mm runway, 4 mm mown and 7 mm rough amplitude; a 0.5 m smooth edge; three fixed weighted waves at 1.2, 0.73 and 0.41 m wavelengths. The current stride-6 table has no material ID, so amplitude temporarily follows its rolling-factor values (2.5/5/7.5). This is a data-shape proxy, not a physical link between rolling resistance and soil height; separate tuning needs an explicit surface-class field.

The ground shader uses the same category rectangles and profile, and adds a normal cue only. It does not displace the coarse field mesh. The cue fades from 20 to 80 m and with pixel footprint from 0.08 to 0.41 m; physics continues to sample the full relief at every wheel query. Blade height remains separate from load-bearing soil relief.

## Evidence

- [Terrain table, determinism, seam, finite-difference gradient and shader-mirror tests](test_ground_terrain.log): 21 checks passed, including a worst CPU mirror difference of 1.35e-10.
- [Existing field surface renderer regression](test_field_surfaces.log): 19 checks passed; fallback layouts preserve the material when consolidation returns false.
- [Native Compatibility capture log](compatibility-capture.log): Godot 4.7.2, OpenGL 3.3 on NVIDIA GeForce RTX 3090; 1280 × 720 capture, with 106,232 image channels changing when the normal cue was toggled. No shader compile error was reported.
- [Captured runway and grass preview](terrain-preview.png).

The focused checks ran against an isolated draft app copy; the terrain and field-surface checks also passed against the integrated `app/` (GP-05). No per-wheel contact/session integration or measured RC terrain calibration is claimed here.
