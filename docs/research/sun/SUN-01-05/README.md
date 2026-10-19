# SUN-01…05: sun disc, eye glare, bleaching and lens optics: results

2026-10-19. Plan: [sun.md](../../../plans/sun.md); physics and sources: [SUN-00](../SUN-00/README.md).

Environment: Linux, Xvfb, Mesa llvmpipe (no GPU), Godot 4.7.2 Compatibility, 1280×720, `app/tests/capture_landscape_upgrade.gd` with 60 warm-up frames and 3 timed frames per case. These are pixel and behaviour checks, not performance numbers.

## 1. What changed for the pilot

| | Before (HEAD 8b52fc28, LU-04) | After |
| --- | --- | --- |
| Model 3° from the sun (Day) | keeps 85 % of its contrast | {{OFFSET3}} |
| 0.67 s after the model crossed the sun | keeps 88 % | {{CROSSING}} |
| 5 s later | keeps 88 % | {{LATE}} |
| Sun disc | flat white dot, faint halo | limb-darkened, refraction-flattened near the horizon, inside a KS91 aureole |
| Chase/orbit/close-up | same eye glare | lens flare: starburst and ghosts |
| Glare under a layered weather deck | still drawn | hidden like the disc |

![Before and after, Day](sun-day.png)

![Crossing the sun](sun-crossing.png)

## 2. Software checks

`app/tests/test_sun_optics.gd`: **83 checks, 0 failed**. Covered:

- CIE values: Ψ(1°) = 15.9 and Ψ(10°) = 0.0755 at age 40.
- The display mapping is exact: alpha q/(1+q) lowers Weber contrast by 1/(1 + r).
- Calibrated-day E/B is 7–16.
- Veil bands: 15–45 % of contrast kept at 1°, 30–70 % at 5°, 40–85 % at 10°.
- E/B falls toward sunset and drops below 1 near the horizon.
- Bleaching: a 0.15 s glance marks the eye (α > 0.25); a 1 s crossing masks it (α > 0.75); 30 s restores it.
- Exact integration: identical at 45, 90 and 216 steps; pause and backward steps hold the state.
- Patch merge and split.
- Limb mean and I(0.5) ≈ 0.70.
- Flattening 0.80–0.90 on the horizon; the moon's law is matched.
- Aureole shape: continuous, 45° cut.
- Cloud mirror: 32-bit hash arithmetic; overcast and the layered stratus (the LU-04 gap) both hide the disc.

Affected existing suites, run on the working tree: {{SUITES}}

## 3. Native captures

{{CAPTURES}}

## 4. Limits

- llvmpipe only: no frame-time claim. The overlay keeps LU-04's single draw while the sun is in view; the second pass draws only while an afterimage is visible or in lens views. The CPU cloud mirror costs 66 µs per evaluation (330 µs with eight weather layers) and is cached until its inputs change.
- Constants marked estimate in `app/render/sun/sun_optics.gd` (bleach 0.25 s, recovery 8 s, masking 0.85, age 40, skyline 3°) wait for SUN-08's owner flights.
- One aircraft, attitude and distance; display contrast is not a detection threshold.

## 5. Reproduce

```sh
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_sun_optics.gd
xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --audio-driver Dummy --rendering-driver opengl3 \
  --script res://tests/capture_landscape_upgrade.gd -- --out=<absolute-dir> --frames=3 --width=1280 --height=720 \
  --cases=glare_offset_3,glare_offset_3_off,glare_offset_3_hidden,glare_offset_3_hidden_off,glare_crossing,glare_crossing_off,glare_crossing_hidden,glare_crossing_hidden_off
"$(app/tests/visual-env.sh)" tools/landscape/glare_contrast.py <absolute-dir>
python3 tools/landscape/verify_glare.py <absolute-dir>   # with the LU case list, tools/landscape/README.md
"$(app/tests/visual-env.sh)" research/sun/sun-05/sheets.py --captures <sets-dir> --out <dir>
```

Add `--time_of_day=golden_hour` or `--time_of_day=sunset` after `--` for the field-world sky.
