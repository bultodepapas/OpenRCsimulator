# VQ-07: optional planar lake reflection

2026-10-22. Native Windows, Godot 4.7.2-stable, RTX 3090. The detailed
Ventage Jet now has a recognizable moving reflection in the lake. Adopt this
as a **default-off native High experiment**, not a qualified High default.

## Visible result and implementation

- [Low jet still](high-planar/edited.png), [one-second pass](high-planar/pass.mp4),
  [different camera angle](high-planar/orbit.png), [aircraft-hidden control](high-planar/absent.png).
- [Default High control](high-control/edited.png) retains the static cubemap.
  Its edited image is byte-for-byte pixel equal to the previous lake-refresh
  High jet image. Standard ignores the option; its matched image differs in
  364 pixels by at most 1/255 from the previous Standard jet image.
- The production aircraft adapter loads `sebart-avanti-s-a200-p100rx` (Ventage
  Jet, 38 geometry instances). The visual origin is 1.95 m above mean water.
  The 61 poses cover 18 m at prescribed 1/60 s intervals; this is repeatable
  rendering, not a physics-integrated flight or a measured 60 FPS result.

Reuse [KipJM Smart Planar Reflector](https://github.com/KipJM/smart_planar_reflector/tree/38df2bbf84c9ad1982dc7758e66f9809467ed973),
MIT, pinned to `38df2bbf84c9ad1982dc7758e66f9809467ed973`. The vendor script is
unmodified; license and upstream credits are retained and included by all
desktop export presets. No editor plugin or demo is installed. The small
OpenRC adapter owns profile gating, water bounds, camera selection, masks,
linear HDR capture, resize and cleanup. Physics and generated lake geometry
are untouched.

The mirror uses half the main viewport dimensions, capped at 1280×720, 2× MSAA.
The tested 1280×720 main view uses a 640×360 reflection. It excludes water and
the basin, includes the aircraft, and updates after the rendered camera/vehicle.
The static probe's receiver mask is disabled while the planar path is active:
otherwise Godot's probe lighting overrides the shader's `RADIANCE`. The basin
keeps its static-capture bit throughout. Inactive/underwater/non-perspective
cameras restore the original basin and probe masks. Teardown clears the
viewport-texture reference. These cases have focused contract coverage.

## Color and rejected variants

The previous simple SSR/dynamic-cube screens did not produce a coherent jet
reflection. A mirror-camera prototype did. Its first EMISSION composite added
to existing environmental lighting; that variant was rejected. Use conditional
`RADIANCE`, retaining the water's normal lighting and Fresnel behavior.

The capture must also preserve linear radiance. `use_hdr_2d=true` produces an
RGBAH linear viewport texture; a shallow Environment clone uses LINEAR tone
mapping, exposure 1, no glow/adjustments/SSR, and no camera attributes. The
source Sky remains shared and the atmosphere's live environment fields are
synchronized. The final main camera applies display exposure once. The shader
sampler therefore has no `source_color` conversion.

[hdr_probe.gd](hdr_probe.gd) reads a known unshaded linear RGB `[2, 0.5, 0.1]`:

| Capture | Exposure | Readback RGB |
| --- | ---: | --- |
| Ordinary viewport | 1 | 1, 0.73725, 0.34902 |
| Ordinary viewport | 2 | 1, 1, 0.48627 |
| HDR viewport | 1 | 2, 0.5, 0.09998 |
| HDR viewport | 2 | 4, 1, 0.19995 |

This isolates clipping, transfer function and repeated exposure. It is not a
full radiometric validation. The exact engine implementation is in the
[4.7.2 renderer](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/renderer_scene_render_rd.cpp)
and [tonemap shader](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/shaders/effects/tonemap.glsl).

## Measured scope and remaining gates

One **serialized** control/candidate pair, each 10 s warmup + 5 s sampling,
uses the production World in an offscreen viewport, after the same restored
camera case. No image readback occurs inside these timing samples.

| Mode | Samples | Draw wall p50 | p95 | p99 |
| --- | ---: | ---: | ---: | ---: |
| High default | 3,113 | 1.435 ms | 2.119 ms | 2.529 ms |
| High planar HDR | 2,098 | 1.957 ms | 4.016 ms | 5.390 ms |

Raw observations are retained in each `report.json`; run [reduce.py](reduce.py)
for this table and the control-image comparison. GPU queries cover **only the
main viewport**, excluding the mirror: they do not establish total GPU cost.
The offscreen wall samples do not measure presented gameplay FPS. The extra
render pass has a cost; repeated full-flight pairs and ordinary pilot motion
are still required before enabling the option by default.

Remaining: broad screen-edge/off-screen and submerged-object clipping cases,
roughness/distance filtering, storm/night/fog behavior, full release lifecycle,
memory/pacing, other GPUs and platforms. This is a mean-plane mirror with a
small wave-normal UV warp, not a physically exact wavy-surface reflection.
The current clip has finite sampled camera/aircraft coverage only.

## Verification and reproduction

Five focused headless suites pass **207 checks, zero failures**: planar 41,
sky render 46, lake world 27, world flow 26, High profile 67. The headless High
suite explicitly skips native values. A fresh sparse clone with the candidate
files also passes the 41 planar checks. Independent read-only review found no
remaining source-level blocker. Native Standard confirms the option is ignored;
native High captures confirm attachment, reflected motion and underwater
deactivation/recovery. An ordinary High quick-flight startup with the jet and
option enabled exits successfully after 180 frames, with no engine errors or
warnings; this is a startup smoke check, not a complete flight.

The fresh sparse clone also exports a **187,832-byte PCK** with the unchanged
production Linux preset. A `--main-pack` launch instantiates the helper/vendor
scripts and reads both license files from that pack; both checked runs have
zero errors/warnings. The preset SHA-256 is
`ea024bdd43a85bb630f261ffc6059b3cb628d6a11029ba163adccb1977d6f8a9`.
The disposable clone disables absent editor plugins and uses the retained
[minimal scene](pack-fixture/pack_fixture.tscn) and [script](pack-fixture/pack_fixture.gd).
This proves resource filtering/loadability, not full-game export, build metadata,
executable packaging, signing or release qualification. Historical commands and
checks are retained under `checks/sparse-*`.

Use new absolute output directories:

```powershell
$env:OPENRC_LAKE_REFLECTIONS = 'planar'
python tools/graphics/launch.py --profile high --script ../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/probe.gd -- --out=C:/new/planar --view=lake --seconds=5
Remove-Item Env:OPENRC_LAKE_REFLECTIONS
# Repeat with the variable absent for High control; Standard ignores it.
python tools/graphics/launch.py --profile high --script ../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/hdr_probe.gd
```

Checked native fixture logs retain the previously observed seven Texture RID
shutdown warning and Vulkan compiler informational messages. The world-flow
test deliberately emits its invalid-time-scale warning. No clean fixture
shutdown or complete-suite claim is made. Earlier scratch attempts with an
invalid Variant-to-bool conversion, parse failure, incomplete sparse clone or
incorrect required completion text are excluded. One early overlapping timing
pair is also excluded. Only the final serialized pair above supports the table.

[Identity](identity.json) and [runtime patch](runtime.patch) retain the tested
source. The HDR capture preceded the vendor's relocation from excluded
`addons/` into `render/lake/vendor/`; the final path passes fresh-clone checks.
The shared tree advanced through unrelated commits during work; no exact
whole-repository baseline equivalence is claimed. PNGs are lossless evidence;
MP4/JPEG motion derivatives are viewing aids, with all original frames
reproducible through the fixture.
