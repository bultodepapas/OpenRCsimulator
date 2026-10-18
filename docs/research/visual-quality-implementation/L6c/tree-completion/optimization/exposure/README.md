# FW-23 / VQ-01c: skip disabled daylight light queries

2026-10-18. `World.view_exposure` previously evaluated every field floodlight and the ground-light term before multiplying their contribution by the daylight factor, which is exactly zero at solar elevations of 3° and above. The candidate checks that factor first and omits the query only when both inputs are finite. Nonfinite inputs retain the original evaluation path. Dusk/night keep the original point-plus-ground arithmetic; the landscape-off route keeps its unscaled illumination.

This is the field-world eye-adaptation route. Fixed-sun worlds and the separate explicit SDR lighting route do not gain this work reduction. No tree placement, geometry, material, visibility distance, physics or lighting calibration changes. There is no new cache or retained scene resource.

## Measured CPU cost

Native Windows Godot 4.7.2, headless component measurement. Three fresh processes, seven alternating reference/candidate blocks per case in each process, 2,000 calls per side/block; all raw timings and checksums are in `report-1.json` through `report-3.json`. Desktop background activity was not controlled. The first exploratory prototype is excluded from this final-source campaign.

| Landscape enabled, preset | Reference median, µs/call | Candidate median, µs/call | Median paired difference, µs/call |
| --- | ---: | ---: | ---: |
| Noon | 35.767 | 8.842 | −27.455 |
| Golden hour | 35.165 | 8.679 | −26.392 |
| Sunset | 36.476 | 36.398 | −0.281 |
| Blue hour | 35.102 | 36.091 | +0.672 |
| Night | 35.691 | 36.714 | +0.765 |
| Fixed-sun legacy | 0.465 | 0.467 | +0.020 |

Daylight component cost falls about 75%, consistently across the three process medians. The small nighttime increases remain visible; no nighttime improvement is claimed. Landscape-off cases have mixed small differences, recorded in [summary.json](summary.json). This measurement does not establish an FPS increase, reduced frame hitches or GPU savings. The method follows Godot's recommendation to [time the affected CPU work before and after a change](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html).

## Preservation and regression checks

The three processes each preserve 720 exact exposure values across six sky modes, both landscape selectors, three night profiles, four targets and five ground shares. A separate production-source comparison preserves 1,680 boundary/nonfinite-input cases and 360 adaptation transitions, including pause, rewind, large clock jumps and light-profile changes. Finite outputs, adaptation state and shader exposure pushes compare exactly; NaN inputs compare NaN outcomes explicitly. [Transition receipt](transitions.json).

Focused current-source tests pass with zero engine errors: field lights 86 checks with landscape enabled / 84 disabled; landscape lighting 54; world flow 26; presentation-context restoration 17. Five permanent assertions cover daylight lighting independence, resumption at night and profile-off behavior. Known oak material fallback and deliberately invalid time-scale warnings are retained in logs. These checks do not substitute for the full application suite or hardware qualification; neither was rerun for this bounded presentation change.

## Reproduction and identity

[sha256.json](sha256.json) pins the exact source copies, benchmark, transition probe, raw reports, reduction and logs. `world_reference.gd` is the pre-change source normalized to LF; `world_candidate.gd` is the measured candidate and matches production after newline normalization. The reference was captured at `21038122`; unrelated simulation/documentation commits advanced HEAD to `74945825` during the round. The intervening diff contains no exposure, sky, field-light, landscape-option or woodland source/data changes. Both revision observations and the raw production-file hash are recorded in `summary.json`. All 252 timed-block checksum pairs match.

Run copied fixtures from a new scratch directory so retained evidence stays immutable. Keep both source copies beside the probes:

```powershell
python -c "import subprocess; subprocess.run([r'.tools/Godot_v4.7.2-stable_win64.exe', '--headless', '--path', 'app', '--script', r'C:/absolute/scratch/probe.gd'], check=True)"
```

The timing fixture writes `report.json` beside itself. `transitions.gd` reads that directory's reference and compares against the current `res://render/world/world.gd`, writing `transitions.json`; inspect the engine logs as well as exit status. Running on a changed application creates a new comparison, not a reproduction of the recorded source identity.
