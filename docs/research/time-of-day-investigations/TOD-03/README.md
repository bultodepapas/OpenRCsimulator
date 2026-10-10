# TOD-03 — Scene-local lighting

Status: implemented; focused and rendered checks pass, 2026-10-10. Parent: [time-of-day plan](../../../TIME-OF-DAY-PLAN.md).

`render/time_of_day_lighting.gd` maps validated civil time and solar geometry to one scene-local dictionary. `Atmosphere` accepts that dictionary when creating the sky, fog, sun and ground. An omitted dictionary preserves `Spec.ATMOSPHERE` exactly. Home and flight create independent resources; time is fixed throughout each flight. Cloud animation retains the existing simulation clock and one-second update cadence.

## Appearance estimates

All colours and energies below are **estimated SDR appearance**, not measured irradiance, calibrated sky luminance or physical weather. Exposure stays at the existing 0.6. Twilight angles use the [USNO definitions recorded in TOD-00](../TOD-00/primary-sources.md); they do not establish the colours. The daylight anchor reuses the existing project's visual calibration. Interpolation uses smoothstep in linear light.

| Geometric solar elevation | Zenith sRGB | Horizon sRGB | Cloud sRGB |
| --- | --- | --- | --- |
| ≤ −18° | `#010205` | `#020305` | `#010203` |
| −12° | `#071024` | `#263247` | `#111b2c` |
| −6° | `#1d3255` | `#706d7b` | `#4e4c5c` |
| −0.8333° | `#344e7c` | `#cf9f85` | `#d5ac96` |
| 6° | `#416294` | `#cbd7dc` | `#eee2d3` |
| 45° | `#4e6893` | `#c9e3ed` | `#f2f4f7` |
| 90° | `#43668f` | `#c9e3ed` | `#f2f4f7` |

Direct energy fades from zero at −0.8333° to 0.7 at 6°, then rises smoothly toward 1.15 at 80°. Sun colour blends from `#ff975a` to the existing daylight colour by 25°. Cloud silver lining uses the same sunrise fade. These bounded curves require pilot/display review; no photographic reference set or absolute night-vision validation is claimed.

The visible disc uses a bounded mean-refraction approximation: add 34 arcminutes at/below the horizon, tapering to zero at 5°. Its direction is separate from the direct light, whose altitude is clamped to 0.05° while the partially visible disc contributes light. Below the modelled disc-set threshold its energy is zero. The visible solar term is clipped to the natural horizon and attenuated by `exp(-8 × cloud_density)` using the existing cloud field; optical thickness 8 is estimated. Geometry occludes the background as before; terrain-cast sunlight shadows are not modelled.

The initial night has no Moon, stars or lamps. Sky radiance is very weak, and an unlit aircraft may become indistinguishable from its background. No aircraft material emission, visibility toggle, outline or tracking fill is added.

## Compatibility and ownership

Keep `Sky.PROCESS_MODE_QUALITY`: [TOD-01](../TOD-01/README.md) checks the actual Compatibility renderer. Initialise all parameters before scene entry. This avoids partial daytime resources appearing during Home/flight creation; static selection needs no frame-by-frame sky rebuild.

Ground, runway/mown copies, and near-grass receive the same haze and sunlight. Haze extinction remains the existing visibility setting. Physical air density, temperature, humidity, wind and weather RNG do not consume lighting configuration. Numeric astronomical calculations live in `environment/`; renderer colours and Godot vectors stay in `render/`.

Verification and rendered evidence: [TOD-07](../TOD-07/README.md). New tests cover 24 hourly snapshots, fog/material agreement, finite zenith transforms, resource isolation and unchanged legacy defaults.
