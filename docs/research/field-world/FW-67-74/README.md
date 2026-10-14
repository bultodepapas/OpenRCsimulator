# Night landscape implementation evidence

2026-10-13. Runtime implementation delivered; this report records observed results, not pilot acceptance or a hardware performance qualification. [Research: 26 investigations](../FW-66/investigations.md), [remaining acceptance plan](../../../plans/night-landscape-lighting.md).

## Scope

One physical mast, four independently aimed downloaded heads, the existing low windsock light and marker positions. Club/Airfield/Off controls and an independent optional fire use presentation preferences. The Kenney hearth is always installed; flames, embers and their bounded local light are optional. Aircraft physics and aircraft lamp shaders are unchanged by this work.

## Assets and deterministic behavior

The [source intake](../../../../assets/landscape/night-lighting/README.md) retains downloaded originals, authors, CC0 evidence and hashes. The [build pipeline](../../../../tools/night-lighting/README.md) creates a two-surface 2,908-triangle head and packs the downloaded 80 fire frames with transparent gutters. Its byte-for-byte check passed for eight runtime outputs. The fire uses five billboard sprites and eight analytic embers; equal clock and wind reproduce the same state. The 3.6× hearth is approximately 1 m across.

## Verification record

- Godot 4.7.2, Compatibility. Native adapter: NVIDIA GeForce RTX 3090, OpenGL 3.3, driver 610.88.
- `test_landscape_lighting.gd`: 54 checks passed after fixing rebind material identity and allowing float32 light-energy storage tolerance.
- `test_campfire.gd`: 24 checks passed, including equal-time repeatability, bounded node counts, on/off behavior and high-exposure caps.
- First native fire attempt caught obsolete `Color.ONE`/`MultiMesh.COLOR_8BIT`; corrected before final validation. Custom flame material explicitly implements billboarding because a Sprite3D material override replaces its generated billboard shader.
- Initial native mast attempt exposed a too-strict mount-distance validator during active integration. That capture is invalid and is not presented as final evidence.

## Baseline and limits

An isolated pre-integration source snapshot is at `tmp/night-implementation-baseline/`, with source manifest. Native baseline images and a 30-frame report are at `tmp/night-integration/baseline-capture/`. These are visual comparison evidence only. Other Godot sessions were active on the shared machine; no uncontended timing claim is made. The final captures below use the pre-FW78 baseline renderer plus the night implementation, isolating it from unfinished sky changes. The source manifest identifies the actual capture files.


## Final geometry and controls

The 12 m mast at north −8/east 0 carries four heads at 11.75 m, with east offsets −0.9, −0.3, +0.3 and +0.9 m. Each targets north 9 m and east −38, −10, +10 or +38 m. Outer half-angles are 14°, inner 28.9°; all four remain approximately 2° below the horizon. This is an estimated club layout, not a purchased luminaire photometric file. A 1 m runway grid receives nonzero light at 1,313/1,313 samples: scene-irradiance p05 0.00000190, p50 0.00000998, p95 0.00005405. The p95/p05 ratio is 28.52, so geometric coverage does **not** imply uniform illuminance.

Production has five field spots (four mast heads plus the low windsock light), leaving room for the aircraft landing spot. The two existing veranda omnis plus the optional fire remain below the eight-omni Compatibility limit. These local lights cast no additional engine shadows. The v1 reader keeps legacy poles and hardware explicitly; v2 owns one mast collider and the permanent 1×1×0.4 m hearth proxy.

Club keeps 4000 K estimated lamp colors and warm markers; Airfield changes to cooler 5000 K floods and white runway-edge cues. Off sets field light contributions to zero while preserving physical geometry. The optional fire uses downloaded frames with one atlas-UV mapping, view-space billboarding, deterministic frame/ember placement and capped light/flicker. Five sprites replace the initial twelve overlapping cards, and their lower tips overlap the log base. No time-dependent simulation state was added.

## Reviewed images

| View | Evidence |
| --- | --- |
| Before / after composition | [Baseline](captures/baseline-postcard.png), [single mast](captures/postcard_club.png) |
| Imported hardware | [Day](captures/mast-day.png), [night](captures/night_mast.png), [orthographic](captures/night_mast_ortho.png) |
| Profile comparison | [Club](captures/night_runway_club.png), [Airfield](captures/night_runway_airfield.png), [Off](captures/night_runway_off.png) |
| Optional fire | [Final side view](captures/campfire.png), [animation](captures/campfire.webp), [motion report](fire-motion-report.json) |

Native screenshots are direct Godot outputs. The animation encodes every second captured frame at 30 fps; it adds no generated content. The fire was also reviewed from the opposite camera direction. [Native report](native-report.json) contains eight views, 60 warm-up frames and 600 measured frames each at 1920×1080; [baseline report](baseline-report.json) contains only 30 measured frames, so these are not an ABBA performance comparison. [Capture source manifest](native-source-manifest.json).

## Test and packaging outcome

- Focused v1/v2 field-light contract: passed, including invalid quantities, links and roles, unique mast proxy, permanent hearth, engine transport law and coverage.
- `test_world_field_lights.gd`: 64 checks, zero failures on the stable composition snapshot; fixed an absent-fire metadata lookup exposed by its standalone Environment case.
- `test_landscape_lighting.gd`: 54 checks, zero failures; includes profile output, daylight gating, imported heads, stable material rebinding and exposure limits.
- `test_campfire.gd`: 24 checks, zero failures after the final UV and ember-alpha corrections.
- `test_world_flow.gd`: 26 checks, zero failures. Collision-world and collision-setup checks also passed (22 setup checks).
- Isolated full `test_ui_weather.gd`, `test_ui_field_world_time_of_day.gd`, and `test_ui_time_of_day_pause.gd`: passed. Covers Home→Fly, Spanish labels, CLI override, paused Apply, unchanged simulation state and commands, saved preferences, and Restart. The pause test reacquires picker references after dialog recreation and searches the keyboard focus chain instead of assuming a fixed menu index.
- Asset generator byte check: all eight runtime outputs match. Night resources, field JSON and license/manifest files load from the generated PCK; resource-pack smoke reports zero failures.

The stable snapshot is `tmp/night-native-final/`; it combines the pre-FW78 baseline with night-owned files and the existing aircraft-light mode API needed by the current flight UI. It does not represent a fully qualified export of every concurrent track. `app/test.sh` was attempted on a separate full working-tree snapshot: the first import exceeded its 180 s bound, and the warm retry stopped on the captured incomplete `atmosphere.gd` sky changes. The export plugin also reports an aircraft visual family without a checked-in model manifest, despite writing a PCK. **Neither the entire test suite nor a releasable application export is claimed to pass.** No unrelated sky or aircraft code was reverted in the live workspace. A later live integration check found one call to `World.refresh_star_cloud_appearance()` without its required Environment; passing `_env` repaired that seam while preserving the sky work.

## Remaining acceptance

Gate FW-N remains open for owner flight/art review, an uncontended low-end-device/ABBA timing run, and integrated qualification after the concurrent sky/aircraft work is complete. The local glow path is implemented; global bloom, volumetrics, positional shadows and renderer migration remain optional and disabled. Night resource-pack loading is verified; release packaging remains subject to the aircraft manifest gate above.


### Latest shared-tree verification

After the concurrent sky APIs landed and the Environment argument was repaired, the actual shared application passed its AppRoot parse check, the 64-check field-world suite, the 54-check landscape-lighting suite, the 24-check fire suite, the v1/v2 field-light contract, and the complete Home/weather/CLI suite. The latter logs an ObjectDB cleanup warning at shutdown; it reports no script errors or failed assertions. [Live field checks](logs/live-test_world_field_lights.gd.log), [live Home/flight checks](logs/live-ui-weather-verified.log). The isolated pause/restart suite also completed without script errors: [log](logs/ui-pause-verified.log).

This supersedes the earlier live UI parser blocker, but does not turn the interrupted full-suite attempt or the aircraft export-plugin rejection into a pass. The final native capture has no stderr output; its eight-view p95 observations span 3.88–5.94 ms on this shared RTX 3090 host. These observations are not a low-end performance acceptance result.
