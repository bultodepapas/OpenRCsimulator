# VQ-07: explicit lake refresh and low jet pass

2026-10-22. Native Windows, Godot 4.7.2-stable, RTX 3090, 1280×720,
4× MSAA. Adopt the sky-edit invalidation repair. Dynamic aircraft reflections
remain open; neither experimental reflection toggle below is enabled in runtime.

## Adopted repair

Changing only a paused sky's cloud seed updated the visible sky but left the
lake cubemap stale. Its signature contained lighting values, which did not change.
`Atmosphere.update_cloud_appearance(field)` now requests a refresh from the
field's scripted reflection probes. `LakeReflection` coalesces these requests
with its next lighting update. Checkpoint and Workshop restoration use the same
path. Continuous cloud drift retains the existing bounded capture policy.

[sky_probe.gd](sky_probe.gd) uses the production World, freezes the cloud pattern,
changes seed 1253→918273 through the production sky-refresh sequence, then forces
an independent probe transform update. The software refresh counter remains 1
before the repair and becomes 2 after it. The final forced transform bypasses
that counter; it is an image reference, not a third script invalidation.

| Edited image versus forced recapture | Changed pixels / 921,600 | Maximum channel difference | Pixels exceeding 2/255 |
| --- | ---: | ---: | ---: |
| High before | 274,749 | 12/255 | 118,126 |
| High after | 57 | 1/255 | 0 |
| Standard before | 262,610 | 17/255 | 35,945 |
| Standard after | 1,095 | 5/255 | 18 |

The reference moves the probe by another millimetre, so it is not an identical
capture position. Standard retains small local residuals; do not claim exact
pixel equality or a universal 2/255 pass. The full-frame stale cloud difference
is removed, and the explicit invalidation contract passes independently.
Run `python <this-directory>/compare.py` to reproduce these reductions.

## Requested detailed jet case

The fixture uses the accepted **Ventage Jet** imported model
(`sebart-avanti-s-a200-p100rx`, 38 geometry instances), built through the production
aircraft adapter. Its visual origin is 1.95 m above mean water. A fixed close camera
records 61 consecutive draws along an 18 m northbound pass with prescribed
1/60-second pose spacing.
The pose is prescribed for visual repeatability: this is not a physics-integrated
flight, flight-feel validation, or measured real-time 60 FPS result. Clouds stay
still; the simulation-owned shader clock advances the water during the pass.

- High: [close still](high-jet/edited.png), [pass clip](high-jet/pass.mp4).
- Standard: [close still](standard-jet/edited.png), [pass clip](standard-jet/pass.mp4).
- Each folder retains an aircraft-hidden control, five JPEG motion samples,
  and the actual model identity and capture masks in `report.json`.

**Finding:** the current lake does not show a recognizable reflected jet. The
field-only probe capture mask is 8; all 38 aircraft meshes fail that mask. The jet
is a sibling of the field, so the field's static-layer pass never tags it. A
surface shadow or changed water pixel does not demonstrate an aircraft reflection.

Two fixture-only screens investigate simple alternatives:

1. **Stock SSR enabled, High:** [still](ssr-screen/edited.png). No recognizable
   reflected aircraft appears. This static screen is not SSR quality acceptance.
2. **Mask 9 and UPDATE_ALWAYS, High:** [still](dynamic-screen/edited.png),
   [pass clip](dynamic-screen/pass.mp4). All 38 jet meshes pass the capture mask,
   but this establishes eligibility, not observed cubemap rendering. The retained
   report's `jet_meshes_captured_by_probe` field is a mask-eligibility count.
   The inspected stills and motion samples do not show a coherent reflected
   silhouette beneath the aircraft. Much of the water changes; mask inclusion
   alone does not fix the viewpoint/parallax problem. Reject this simple toggle
   as a production solution. Its recorded `refreshes` counts script invalidations,
   not renderer cubemap updates in UPDATE_ALWAYS mode. No performance comparison
   was measured or inferred from the capture duration.

The next bounded reflection investigation must establish a correctly placed,
moving silhouette, including screen-edge/off-screen behavior, before measuring
its cost or enabling it. This one-second close pass does not close ordinary pilot
motion, full lake motion, performance, readability, or High qualification gates.

## Reproduce and verify

Use a new absolute output directory. Paths below are relative to the Godot `app/`
project, as accepted by the existing launcher:

```powershell
python tools/graphics/launch.py --profile high --script ../docs/research/visual-quality-implementation/VQ-07/lake-refresh-2026-10-22/sky_probe.gd -- --out=C:/new/lake-sky
python tools/graphics/launch.py --profile high --script ../docs/research/visual-quality-implementation/VQ-07/lake-refresh-2026-10-22/jet_probe.gd -- --out=C:/new/lake-jet
```

Repeat with `--profile standard`. For the isolated dynamic screen, set
`OPENRC_LAKE_PROBE_DYNAMIC=on` only in that invocation's environment. The jet
fixture also accepts `OPENRC_LAKE_PROBE_SSR=on`; the retained static SSR screen
used [ssr_probe.gd](ssr_probe.gd), which unconditionally enables SSR. That older
static report omits the toggle and does not check PNG-write status; the retained
PNGs exist and were inspected, so use the script and images together, not the
report alone. Neither switch is a game setting. Clear them
for production controls. The scripts use the existing capture argument parser;
only `--out` is relevant here. Native rendering is required. Clips are H.264
viewing derivatives; retained sky/control PNGs are the lossless evidence. Motion JPEGs are viewing samples; all 61 original PNGs per pass are reproducible with the fixture.

Five focused headless suites pass: sky render **46**, sky routes **16**, sky
checkpoint **45**, lake world **27**, world flow **26**: **160 checks, zero failures**.
Coverage includes coalescing, unchanged lighting, restoration, field isolation,
generic probes, and no refresh from continuous cloud drift. An independent
read-only review found no runtime lifecycle or recurring per-frame work issue.

Checked logs retain zero engine/script/shader errors. High still reports the
previously observed seven Texture RID shutdown warning and Vulkan shader compiler
informational messages; no clean-shutdown claim is made. The world-flow test
deliberately emits its invalid-time-scale warning; route tests print the existing
aircraft inertia advisory. Full suite, export, and multi-platform runs were not
performed for this bounded repair.

[Identity](identity.json) and [runtime patch](runtime.patch) record the candidate.
The shared tree advanced through unrelated commits during work; the earlier
baseline included the previous sunlight repair, and its complete dirty-tree
identity was not retained. Historical command paths in `checks/` remain intact.
This evidence supports the specific reproduced refresh defect, not exact
whole-repository equivalence or a frame-time improvement.
