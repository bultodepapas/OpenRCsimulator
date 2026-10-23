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
disabling SSAO. Their scripts/logs remain under `engine-lifetime/prior-diagnostics/`; neither
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

## Native keyboard cost screen, 2026-10-22

Two valid probe/planar pairs now provide exploratory wall-frame measurements
with advancing physics. The [bootstrap](native-keyboard/keyboard_flight.gd) uses
the ordinary `ControllerService` keyboard selection and `Main` session, retaining
physical key input and focus-loss pause. It does not inject poses, input callbacks
or automatic resume, or write controller preferences. This is neutral half-power
Avanti flight with a fixed pilot view toward the lake, not a low pass or pilot
circuit. The preceding detailed-jet captures remain the visual evidence.

Each process used native High Forward+/Vulkan, Godot 4.7.2, RTX 3090,
1280×720, 4× MSAA, VSync on at 120 Hz, no FPS cap, 10 s warmup and 60 s collection.
The camera was at (0, 1.7, 0), azimuth 49°, elevation −1°, FOV 50°; the planar
capture was active at 640×360 at report time. Activity is an endpoint snapshot,
not continuous coverage. Collection used the normal wall-frame recorder without
GPU diagnostics or screenshot readback during timing.

| Retained run | p50 ms | p95 ms | p99 ms | Maximum ms |
| --- | ---: | ---: | ---: | ---: |
| probe-1 | 8.334 | 9.148 | 10.004 | 37.674 |
| planar-1 | 8.275 | 11.245 | 12.073 | 27.857 |
| probe-3 | 8.335 | 9.182 | 9.932 | 12.954 |
| planar-3 | 8.266 | 11.206 | 11.939 | 27.329 |

Planar p95 is 2.097 and 2.024 ms greater in these pairs. This is wall-frame
cadence, not isolated GPU cost or a speedup. All four runs pass the individual
software pacing gates and advance physics near 240 Hz without a reported fault
or nonadvancing interval. Both campaigns nevertheless have **performance_pass=false**:
two eligible runs per mode do not meet the unchanged three-run minimum.

All eight raw reports, identities and checked logs are retained in
`native-keyboard/`. [Exclusions](native-keyboard/exclusions.json) remain explicit:
`planar-2` and `probe-2` overlapped by 4.820246 s; `probe-4` and `planar-4` ended
paused at simulation times 63.9041667 and 11.8833333 s. Their reports do not record
the pause cause, so none is attributed. No retry or safety bypass converts these
into acceptance. All eight logs retain the seven Texture RID shutdown warning;
planar runs 1 and 4 also report 19 retained ObjectDB instances at exit.

The four valid processes ran serially and their identities match across 709
tracked app source files. This excludes tests, binary assets and untracked files;
it is not whole-tree or host-state equivalence. Other host activity and GPU cache
state were uncontrolled. [Retention identity](native-keyboard/identity.json)
records the bootstrap, engine and native reducer hashes separately. Independent
review checked eligibility, configuration and the limited source identity claim.

The [comparison](native-keyboard/comparison.json),
[probe summary](native-keyboard/probe-summary.json) and
[planar summary](native-keyboard/planar-summary.json) preserve the incomplete
campaign verdict. Reproduce the reduction from the retained gzip reports, from
the repository root, using a new output directory:

```powershell
python docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/native-keyboard/reduce_campaign.py tmp/planar-keyboard-reduction
```

Reproduction passed with two eligible runs per mode and both campaign verdicts
false. Original checked receipts preserve launch commands and historical paths.
No production runtime, aircraft physics or default changed in this measurement
step. Keep planar reflection default-off. A controlled foreground campaign with
the required repetitions, ordinary pilot motion, 1080p, release/platform and
shutdown/lifecycle qualification remain open.

## Engine lifetime attribution and session context, 2026-10-22

The seven Texture RID shutdown warning is now localized to the pinned engine's
reflection atlas. The minimal fixture imports no application code: it builds a
stock procedural sky, camera and box, optionally adds a `ReflectionProbe`, draws
40 frames, frees the nodes and waits another ten frames before exit. Native
Forward+/Vulkan on the same RTX 3090 produces:

| Fixture | Independent worlds | Probe | Leaked Texture RIDs |
| --- | ---: | --- | ---: |
| Root-world minimum | 1 | absent | 0 |
| Root-world minimum | 1 | present | 7 |
| Isolated SubViewport | 1 | present | 7 |
| Isolated SubViewport | 4 | present | 28 |
| Isolated SubViewport | 4 | absent | 0 |
| Explicit `UPDATE_ONCE` | 4 | present | 28 |

Each isolated world owns its own 3D world. The last case explicitly uses the
production lake's probe update mode and a 1920×1080 root window; its diagnostic
viewport stays 320×180. These are resource-lifetime checks, not resolution or
frame-pacing qualification. The growth is per independent atlas/world in this
fixture; no per-frame or real Home/Fly accumulation rate is claimed.

In [Godot 4.7.2's atlas cleanup](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/storage_rd/light_storage.cpp#L1549-L1603),
`color_buffer` is not released. Its allocation creates six dependent texture
views. [Upstream PR #124743](https://github.com/godotengine/godot/pull/124743), merged
October 21, frees and resets that buffer; the RenderingDevice releases its
dependencies. This source defect matches the controlled native result. Neither
the lake shader, planar camera nor SSAO is required. The earlier drain/SSAO
negative diagnostics are retained under `engine-lifetime/prior-diagnostics/`.

No application teardown workaround or engine upgrade is adopted. The upstream
fix must be present in an explicitly pinned candidate engine and pass these
controls, repeated application lifecycle checks, rendering comparisons and export
checks before replacing the current binary. This attribution does not resolve
the separate intermittent ObjectDB warnings or qualify High's lifecycle.

The preceding native campaign also exposed missing diagnostic context: its final
pair was paused without a recorded session reason. `Main` now adds
`session_at_report` once after collection, retaining display reason, active holds,
crash presence and window focus. Holds and reasons are independent. Direct
simulation focus pauses may leave both empty; focus regained before reporting
cannot reconstruct an earlier event. This is endpoint context, never a cause enum
or pause history. Historical reports remain unknown. No input, pause/resume,
physics or eligibility behavior changes.

Three native High **1920×1080** producer checks use the real Main collector with
a deliberate hold, a deliberate failsafe and explicit release/resume. Their
reports preserve an empty reason with the hold, the failsafe text with no hold,
and empty context after resume. All three checked processes exit without engine
errors or leak warnings. They use zero warmup and one-second collection with the
lake disabled: synthetic metadata checks, not performance acceptance.

The performance-tool suite passes **107 tests**, including malformed optional
context, historical compatibility and unchanged eligibility. The frame collector
passes **86 checks**. The UI pause integration suite also passes, including five
Home/flight cycles with stable node counts. Its first checked invocation used the
wrong completion marker; that rejected receipt is retained alongside the passing
rerun with the suite's actual marker. Independent review found no significant defect in the
producer/reducer change. Scripts, gzip reports, checked logs, retention identity
and patch are under `engine-lifetime/`. From the repository root, reproduce the
offline verification with:

```powershell
python docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/engine-lifetime/verify.py
```

Checked receipts retain native invocations; use fresh report paths when rerunning.
The graphics profile, planar default and engine version remain unchanged. Primary
1080p performance, ordinary pilot motion, shutdown and platform gates remain open.

## Controlled engine backport, 2026-10-22

A locally compiled Godot 4.7.2 baseline reproduces the reflection-atlas leak;
applying only [upstream PR #124743](https://github.com/godotengine/godot/pull/124743)
removes it in the matched controls below. The production engine pin is unchanged.
This is a diagnostic Windows editor candidate, not a shipping engine replacement.

The source is `ed1daf0bf001b61586d9930840f2f1394092c079` plus upstream commit
`29d351f9eb0dd7582469ad38e215e9902204df12`: two cleanup statements in
`LightStorage::_reflection_atlas_clear`. Both builds use Python 3.11.9,
SCons 4.10.1, MSVC 14.51.36231, Windows SDK 10.0.26100.0 and:

```text
platform=windows target=editor arch=x86_64 d3d12=no accesskit=no angle=no debug_symbols=no optimize=speed lto=none -j16
```

The initial baseline build auto-disabled unavailable AccessKit/ANGLE and emitted
a dependency diagnostic. An explicit baseline confirmation with the options above
completed cleanly, up to date; the patched rebuild used exactly those options.
[Source identity](engine-backport/source-identity.json) retains the complete source
diff, patch hash, both executable hashes, toolchain, build exits and caveats.
The two engines have the same version string; executable hashes distinguish them.

All native launches were serial on RTX 3090 with a 1920×1080 root window.
The project was frozen at `2830d895cba7d90e0636dffb46a8a7dfffd424d5`;
SHA-256 snapshots of all 3,585 tracked `app/` files match before/after each phase
and across engines. Ignored import caches and host state are outside that claim.

| Native case | Baseline leaked Texture RIDs | Patched |
| --- | ---: | ---: |
| No probe | 0 | 0 |
| One captured probe | 7 | 0 |
| Four independent probe worlds | 28 | 0 |
| Production lake, High probe | 7 | 0 |
| Production lake, High planar | 7 | 0 |
| Standard, planar requested but inactive | 0 | 0 |

Every patched checked process exits without engine errors or warnings. The world
fixtures use the detailed Avanti at low altitude over the lake, with low, rolled
and high cameras, fixed sky time and a 1920×1080 capture viewport. All **six High
RGB comparisons are pixel-identical**, including the
[low jet and planar reflection](engine-backport/runs/patched/high-planar/low.png).
These are rendered fixtures, not flight or frame-pacing measurements.

The initial strict nine-image comparison failed in Standard. Its three images
change 418, 148 and 2 pixels, with maximum channel delta 1/255. Repeating the same
build also changes pixels: baseline 143/253/1; patched 341/160/5, all at most 1/255.
[Comparison](engine-backport/comparison.json) preserves exact Standard parity as
**false**. The controls do not uniquely attribute these differences to the patch;
no tolerance-based acceptance or root cause is inferred.

The patched engine passes 61 planar-contract checks, 11 simulation checks and
78 native High-profile checks, with no failures or engine warnings. Independent
read-only review confirmed the bounded resource and visual conclusions. This
software evidence does not establish physical validation. The separate intermittent
ObjectDB warnings, full Home/Fly lifecycle, performance and platform gates stay open.

The [evidence manifest](engine-backport/manifest.json) covers the retained scripts,
logs, checked receipts, images and identities. The parent manifest remains the
preceding historical snapshot. Reproduce the offline comparison with Python and
Pillow from the repository root:

```powershell
python docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/engine-backport/verify.py docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/engine-backport
```

Native commands retain their original local paths. Build sources, frozen worktree
and paired executables remain at `D:/OpenRC-builds/godot-vq07-20261022/`; binaries
are excluded from the evidence bundle. `run_cases.py` requires fresh phase output
directories and that frozen project. Script hashes were recorded at retention,
not independently at each launch. The next adoption gate is a full-feature engine
with matching export templates, packaged lifecycle/render checks and platform
qualification. Planar reflection remains default-off.

## Retained-world reflection restoration, 2026-10-22

The optional planar path now restores its water texture when a retained flight
world re-enters the scene tree. Workshop trial launch suspends the previous
flight with `remove_child`; returning or rolling back a failed trial reattaches
that same tree. Previously, exit cleared `reflection_texture`, while the surviving
helper remained initialized. Its next update enabled planar radiance without
rebinding the texture. Three headless detach/restore cycles reproduced the failure.

The local adapter now rebinds the existing viewport texture in `_enter_tree`.
It allocates no new viewport and preserves exit cleanup. The downloaded component,
physics, shaders and default-off setting are unchanged. Independent read-only
review checked the parent-before-child entry ordering against the pinned engine's
stored viewport texture lifetime.

Verification on the pinned Windows Godot 4.7.2 engine:

- Planar contract: **67 checks, 0 failed**, including three repeated restoration
  cycles and final teardown; the pre-fix run failed all three restoration checks.
- Lake world: **27 checks**; presentation context: **26 checks**; Workshop trial:
  **44 checks**, all passing. The Workshop test intentionally rejects a stale
  presentation and emits its expected warning. An initial strict-warning receipt
  and an incorrect context completion-marker receipt remain retained as rejected.
- Native Forward+ on RTX 3090: four **1920×1080** production-world captures
  (initial plus three restores) are pixel-identical in RGB. Every restored
  frame uses the same viewport and a live texture binding. The reflected jet
  remains visible in the [restored image](world-restore/restored.png).
- The native run still emits the previously attributed **seven Texture RID**
  shutdown warning; this change does not resolve the pinned-engine leak.

[Source identities](world-restore/identity.json), [comparison and PNG hashes](world-restore/comparison.json),
[native metadata](world-restore/native-report.json), [fixture](world-restore/capture.gd)
and [checked logs](world-restore/checks/) retain the bounded result. The initial
fixture parse failure is retained separately from the completed native run.
Identical duplicate captures stay in ignored scratch storage; regenerate them with:

```powershell
python tools/graphics/launch.py --profile high --resolution 1920x1080 --audio-driver Dummy --script ../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/world-restore/capture.gd -- --out=C:/captures/openrc-world-restore
```

Use a new output directory. Compare each `cycle-1.png` through `cycle-3.png`
against `cycle-0.png` as RGB pixels. This fixture exercises the production world
and retained-tree lifecycle; it is not an automated Workshop menu journey,
ordinary pilot-motion assessment or performance campaign. Full High qualification
and the engine/template/platform gates remain open.

## Receiver-depth culling, 2026-10-22

The optional planar camera previously rendered even when the main camera clipped
all water before its near plane or beyond its far plane. The downloaded component
checks side planes only. Two added contract cases reproduced the unnecessary
`UPDATE_ALWAYS` state before the repair.

The local adapter now tests the receiver's camera-space depth bounds before
allocating or updating its mirror. It uses the effective camera transform, the
water's custom AABB (including production wave expansion), and extra cull margin.
It rejects only a box entirely outside the source near/far interval. Overlapping
bounds remain eligible, including boxes spanning both planes. The vendor source,
reflection clipping algorithm, shader, physics and default-off setting are unchanged.
This removes a demonstrated unused render pass; it does not establish a gameplay
FPS gain, and ordinary flight cameras may not encounter these clipping cases.

Verification:

- **74 planar contract checks** pass, including first-use allocation avoidance,
  near/far rejection, custom bounds, extra margin, partial depth overlap,
  reactivation and the previous camera/lifecycle checks.
- **27 lake-world checks** and **67 headless graphics-profile checks** pass.
  The latter explicitly skips native High values; the native fixture below
  confirms High/Forward+ separately. No full app-suite result is claimed.
- **Five paired native 1920×1080 views** on Windows, pinned Godot 4.7.2 and RTX 3090
  are exactly equal in RGB. Baseline mirrors update in all five cases; the repair
  changes the fully near/far-clipped cases to `UPDATE_DISABLED`, while visible,
  partially clipped and restored cases remain active. [Comparison](depth-culling/comparison.json),
  [baseline metadata](depth-culling/before/report.json), [candidate metadata](depth-culling/after/report.json).
- Both native runs retain the known seven-Texture-RID engine shutdown warning.
  Independent Luna Max review found no false-negative path in the conservative
  depth test; partial clipping is also exercised in the native comparison.

The [fixture](depth-culling/capture.gd) replaces only the scene's planar helper
with either the immutable [baseline adapter](depth-culling/baseline_adapter.gd)
from `e8cae7d0` or the current production adapter, before capture initialization.
This keeps the rest of the production world identical without modifying runtime
source for the control. [Identities](depth-culling/identity.json), paired PNGs and
[checked logs](depth-culling/checks/) retain source and result scope. The pre-fix
contract failure is intentionally retained alongside the passing checks.

Reproduce the candidate with a new absolute output directory:

```powershell
python tools/graphics/launch.py --profile high --resolution 1920x1080 --audio-driver Dummy --script ../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/depth-culling/capture.gd -- --out=C:/captures/openrc-depth-after
```

For the baseline, set `OPENRC_PLANAR_ADAPTER` to
`res://../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/depth-culling/baseline_adapter.gd`
for that process and use a separate output directory. Unset it for the candidate.
The fixture selects planar mode itself. Compare same-named PNGs as RGB pixels
and inspect `active` and `update_mode` in each report; image equality alone cannot
prove that the unused viewport stopped rendering.

Before this repair, an attempted 1080p live-flight cost collection ended paused
at simulation time 47.754 s, with no fault and no window focus at report time.
Its initial keyboard/focus checks passed, but endpoint context cannot reconstruct
pause history. The [excluded report and receipt](depth-culling/excluded-flight/)
are retained; no subsequent pairs or performance verdict were produced. Driver
617.42 and Windows Balanced power plan were observed. Focus safety remains intact.

Full active-flight cost, ordinary pilot motion, the pinned-engine leak and
release/platform qualification remain open. Planar reflection stays default-off.
