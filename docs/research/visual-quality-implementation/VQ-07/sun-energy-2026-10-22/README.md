# VQ-07: preserve sunlight when High enables shadows

2026-10-22. Adopted renderer correction, Godot 4.7.2-stable, native Windows,
RTX 3090, Vulkan Forward+. Standard remains the normal launch; High remains
experimental under the [advanced plan](../../../../plans/advanced-graphics.md).

## Defect and repair

`Atmosphere.shadow_compensation()` applied the Compatibility renderer's measured
0.85 sunlight factor whenever engine shadows were enabled. Forward+ inherited
that factor even though its shadowed lights do not need the Compatibility
correction. Enabling shadow maps therefore dimmed surfaces that were not in shadow.

The repair restricts that factor to the actual `gl_compatibility` renderer.
Forward+ keeps the configured direct-light energy whether shadows are enabled
or disabled. Renderer identity, rather than the requested profile name, governs
the correction. The same adapter serves snapshot and flowing worlds. No exposure,
material, shadow-map, geometry, physics or aircraft-data settings were retuned.

## Reproduction and numerical proof

The new [native regression](../../../../../tools/graphics/test_shadow_energy.gd)
renders three matte, unoccluded material panels using the production sun adapter.
Ambient light, reflections and fog are disabled to isolate direct lighting. It
checks that the panels are visible and unsaturated and that the shadow setting
actually toggles. Headless execution is refused.

| Forward+ result | Before | After |
| --- | ---: | ---: |
| Light energy, shadows off / on | 1.0 / 0.85 | 1.0 / 1.0 |
| Maximum sampled RGB change when enabling shadows | 11/255 | 0/255 |
| Required tolerance | 2/255 | 2/255 |
| GPU regression | Fails | Passes |

The before run deliberately used `--capture-only`: its process completed, but
[`passed=false`](shadow-before/report.json) records the failed invariant. The
[after report](shadow-after/report.json) passes without that option. Both panel
images are retained losslessly for pixel inspection.

```powershell
python tools/graphics/launch.py --profile high --script ../tools/graphics/test_shadow_energy.gd -- --out=C:/new/shadow-energy
```

Use a new absolute output directory. Checked commands, engine logs and completion
verdicts are retained in `checks/`. [Identity](identity.json) records the baseline
commit/blob, candidate hashes and engine executable hash. The baseline checkout
was clean; unrelated F4U research edits arrived during verification and were preserved.

## Real-scene checks

The existing `capture.gd` produced six matched views per renderer at 1280×720,
4× MSAA, 15:00, P-51, with engine shadows enabled. It freezes the scene clock;
these are scene comparisons, not moving flight/readability acceptance.

- Standard: five views are pixel-exact. The lake differs on 567 of 921,600
  pixels by at most one 8-bit channel level; its clipped-pixel count is unchanged.
  Do not call all six views pixel-exact.
- High: direct-lit aircraft and field surfaces become modestly brighter.
  Retained pairs: [aircraft before](high-before/aircraftground.png) /
  [after](high-after/aircraftground.png), [pilot before](high-before/pilot.png) /
  [after](high-after/pilot.png), [lake before](high-before/lake.png) /
  [after](high-after/lake.png). Visual inspection found no new silhouette,
  shoreline or reflection discontinuity in these views.
- Pixels with any channel at 255 rise from 12 to 18 in the aircraft view,
  1 to 6 at the flight line and 7 to 12 in the pavilion view. Pilot, lake and
  windsock remain at zero. This is not globally clipping-free lighting.
- Existing `flow_probe.gd`: both High runs completed 481 advancing and 120
  paused draws per moon/twilight case at 1920×1080, 4× MSAA and 20× time.
  Six moon stills are exact; six twilight stills differ by at most one channel
  level on 548–602 pixels. The moon view mainly covers the sky and the twilight
  ground is dark; these do not establish night aircraft readability.

[Pixel comparisons and image hashes](comparison.json) cover all 24 paired
stills. Selected PNGs are retained because pixel values are evidence; the others
can be regenerated using the recorded `capture.gd` / `flow_probe.gd` commands.
Flow timing fields are diagnostic samples, not a paired performance campaign.

## Regression and limits

Seven focused headless suites pass: atmosphere (149), High profile (67), sun
optics (112), world flow (26), moon flow (33), moon glare (20), and time-of-day
render updates (94): **501 checks**. The High profile suite also passes **78
checks on native Forward+**, exercising the active branch. Production-path
checks cover shadows off/on, renderer-specific energy and the unchanged
light-energy × fog-scatter product. The aureole and glare consumers divide out
the compensation, preserving their source-light meaning. An independent code
review found no significant regression in those consumers.

The native Green paradise flight smoke completed its 1 s warmup + 5 s sample
with physics enabled, no simulation fault, no pause and 1,198 measured ticks.
Two Club field attempts completed the collector but were paused (36 and zero
measured ticks); they are retained as rejected active-flight checks. No circuit,
latency or frame-pacing qualification is claimed from these short runs.

Known diagnostics remain: High full-field/flow captures report seven Texture
RIDs at shutdown on both sides. The Green paradise smoke reports two ObjectDB
instances at exit; the separate verbose Club retry retains its full shutdown
log, but does not attribute that Green paradise warning. No new engine/script/
shader errors were reported. Existing driver `OpVectorExtractDynamic` messages
also remain. This change does not repair shutdown ownership.

The full app suite, exported packages, other GPUs/platforms, ordinary continuous
pilot motion and owner readability acceptance were not qualified by this slice.
It adds no render pass or asset and claims no FPS gain. Next work remains the
advanced plan's motion/reflection review and repeated native qualification.
