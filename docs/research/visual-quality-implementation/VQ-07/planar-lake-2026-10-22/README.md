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

## Camera-motion follow-up, 2026-10-22

The water-side guard now uses `Camera3D.get_camera_transform().origin` instead
of the node origin. Camera h/v offsets move the rendered eye: a node below the
water could previously disable a valid above-water reflection, and a node above
water could keep the capture active with its actual eye submerged. This was
reproduced with synthetic offset cameras; the ordinary game camera currently
does not use these offsets. No vendor, shader, physics or profile default changed.

The native raised-eye case has node Y −0.65 m and actual eye Y +0.248809 m over
water at Y −0.45 m. The jet reflection is missing [before](camera-motion/baseline/raised-eye.png)
and present [after](camera-motion/candidate/raised-eye.png). The reverse case,
with actual eye Y −1.148809 m, now disables the extra viewport and restores the
static probe. An independent reviewer reproduced both failures and found no
remaining concrete projection mismatch after the correction.

The expanded planar contract passes **51 checks, zero failures/errors/warnings**.
Before the repair, the two new water-side behavior checks failed. Five points
(center and off-axis) compare normalized main-view virtual-image coordinates
with the mirror camera across three roll/FOV/aspect/offset configurations.
These geometric checks pass alongside the offset gates and existing lifecycle
checks. The retained failing baseline used center-only projection assertions;
the final test strengthens these to five points.

Additional production-World captures:

- [Two-second camera orbit](camera-motion/candidate/orbit.mp4): 121 prescribed
  frames with changing roll, FOV and viewing angle. All remain active and all
  121 PNGs are pixel identical before/after this targeted guard repair.
  Selected frames were visually inspected; this is not human pilot acceptance
  or an actual flight. Motion PNGs remain reproducible; the clip/JPEGs are derivatives.
- [Off-screen jet reflection](camera-motion/candidate/offscreen-jet.png) and
  [hidden-aircraft control](camera-motion/candidate/offscreen-hidden.png): source
  center UV X is 1.227 (outside the main image), while the reflected center is
  at (0.923, 0.799). The bottom-right reflection ROI changes in 3,339 pixels by
  more than 2/255 when the aircraft is hidden, separate from its sun shadow.
- Looking entirely at the sky disables the mirror viewport; returning to the
  lake restores it. These checks and UV comparisons are in the retained reports.

Two ordinary native High sessions attempted the existing 10 s warmup + 60 s
flight protocol, first with the option absent and then with `planar`. Both used
the same jet, airborne-half-power start and fixed pilot lake view. With live
controller input the throttle closed, the jet crashed within the warmup, and
the simulation paused. **Both collections are ineligible for flight/performance
qualification**: zero simulation ticks advance during the measured minute.
The existing `native_summary.py` correctly rejects both. No pause behavior,
controller input or crash protection was bypassed to obtain a passing number.
The reports record a 120 Hz display, uncapped engine and VSync enabled; do not
pool them with older 60 Hz evidence or compare their paused frame times as flight.

Raw reports are losslessly compressed under `camera-motion/native-ineligible/`,
with their engine logs and unmodified reducer results. To rerun the existing
reducer, decompress one report as `run-1.json` in a new directory with its
matching log as `run-1.log`. Checked command receipts preserve the invocations.
The native fixtures retain the pre-existing seven Texture RID exit warning;
the focused headless contract has no warnings. An initial edge-fixture parse
error was fixed before capture and is excluded from accepted evidence.

Run `python <this-directory>/camera-motion/reduce.py` to verify the retained
camera cases, image parity summary, reflected-aircraft ROI and rejected native
eligibility. Reproduce captures through the existing launcher with `--profile
high`, `OPENRC_LAKE_REFLECTIONS=planar`, `--script ../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/camera-motion/motion_probe.gd`
(or `edge_probe.gd`) and `-- --out=<new absolute directory>`. These scripts are
capture diagnostics; their `complete` field alone is not a pass verdict.
[Follow-up patch](camera-motion/followup.patch) and [source identity](camera-motion/identity.json)
record this correction separately from the initial integration above.

Keep the mode default-off. Sustained active flight, broader clipping/roughness,
night/storm and full release/platform qualification remain open. The new cases
extend the bounded camera evidence; they do not close those gates.

## Reflection measurement identity, 2026-10-22

The native reducer previously accepted a synthetic campaign containing one
probe run and two planar runs, provided each passed its individual pacing gates.
Frame reports and screenshot sidecars now describe the installed lake path.
The reducer validates that descriptor and rejects mixed modes or mixed known
and missing modes. All-historical missing data remains numerically compatible
but explicitly configuration-incomplete. The [operating contract](../../../../../research/performance/README.md#native-frame-evidence)
defines the fields and their snapshot limits. No shader, physics, profile
default or per-frame observer changed.

Evidence under `measurement-identity/` includes:

- The same three **synthetic**, short-policy inputs, retained old reducer and
  before/after summaries: all three individual runs pass; the campaign changes
  from exit 0/pass to exit 1/rejected. These are reducer fixtures, not flights.
- Serialized production-app metadata checks at 1280×720: High probe, High
  planar (active 640×360 capture), and Standard with planar requested (probe).
  Each uses the existing scripted detailed-jet route, zero warmup and 0.5 s
  collection. A separate native High screenshot with `--lake=off` records
  `absent` through the screenshot-sidecar route. These are metadata smoke
  checks, not new lake appearance or performance acceptance.
- **61 planar contract checks** and **104 performance-tool Python tests** pass.
  Descriptor checks cover absent lake, initialization, resize, underwater and
  missing-camera fallback, teardown, plain values and unchanged scene state.
  Python checks cover mixed/historical modes and malformed nested metadata.
  Checked engine receipts and Python output are retained.

Run `python <this-directory>/measurement-identity/verify.py` from the repository
to recheck the retained campaign and four metadata cases. Native invocations
are preserved in `checks/*/report.json`; use new output paths when rerunning.
[Source identity](measurement-identity/identity.json) and
[patch](measurement-identity/followup.patch) identify the implementation.
Historical command/output paths in receipts and summaries are unmodified.

The seven Texture RID shutdown warning persists in both High frame collectors;
Standard and the no-lake screenshot do not emit it. Two separate World fixture
diagnostics retain the same warning after four draining draw frames and after
disabling SSAO. Their scripts/logs remain under `shutdown-diagnostics/`; neither
result identifies the owning subsystem or justifies a production workaround.
The focused headless contract has no errors or warnings. Full active-flight,
lifecycle and High qualification remain open; no FPS improvement is claimed.

## Aircraft binding recovery and low camera screen, 2026-10-22

The next native camera screen stopped before rendering the detailed jet:
`Airplane.build` rejected the changed shared `retractable_model.gd` dependency.
The failure is retained under `binding-recovery/checks/low-screen-*`. The model
generator's check isolated stale Avanti and Turbo Lumber manifests. Running
the existing model, customization and Workshop generators in dependency order
restored both families. At that point the five generated files changed only
dependency/manifest hashes and the two derived customization slot hashes;
independent review confirmed this. Aircraft quantities and sampled poses were
unchanged. The [authoring contract](../../../../AIRCRAFT_CONTRACT.md#model-and-package-contract)
now states that regeneration order explicitly.

The same native fixture then completed. At a camera height of 0.45 m above mean
water, the detailed jet and its reflection remain visible at camera rolls of
0°, 30°, 60° and 85°. A 12 m camera and a submerged-jet diagnostic complete six
prescribed poses. All six PNGs were inspected; no new clipping defect was found
in these cases. See the [low view](binding-recovery/captures/low.png),
[60° roll](binding-recovery/captures/roll60.png) and
[high view](binding-recovery/captures/high.png). No reflection algorithm change
was justified. These are production-World render poses, not an active flight,
continuous motion acceptance or performance measurement. The existing seven
Texture RID exit warning remains.

Six focused suites pass **883 checks**: Avanti model 390, wheel/contact alignment
89, model manifests 75, Workshop descriptors 102, customization 159 and imported
model 68. Logs, generation commands, fixture and images are under
`binding-recovery/`. Reproduce with native High, `OPENRC_LAKE_REFLECTIONS=planar`,
`--script ../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/binding-recovery/low_probe.gd`
and `-- --out=<new absolute directory>`.

Concurrent F4U authoring subsequently regenerated the shared registries again;
those additions remain outside this repair. The [identity record](binding-recovery/identity.json)
preserves the initial repair hashes without claiming whole-tree equivalence.
All three generator freshness checks then passed with six visual families;
the five manifest/model/Workshop/customization suites were repeated successfully
against that combined state (`binding-recovery/final-checks/`). This does not
qualify the new F4U model or its sampled compression path.
