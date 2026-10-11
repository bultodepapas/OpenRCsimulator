# AUD-03 — Living field soundscape

2026-10-11 · **Status: implemented; qualification in [AUD-04](../AUD-04/README.md).**

The default physics flight now has a scene-local soundscape. The aircraft remains the foreground cue on stereo speakers. Its actual motion produces flybys; no unrelated aircraft pass recordings are triggered. Existing simulation, model, scenery and lighting algorithms are unchanged.

## Signal path

`FlightAudio` runs after the aircraft pose and camera update, reads accepted RPM, shaft load, throttle, airspeed, wind, sun elevation and source/listener positions, then supplies detached values to `Soundscape`. Propeller load comes from the existing pure thrust/torque functions normalized to static torque at the accepted RPM. Turbine load uses throttle. These timbre mappings are authored estimates, not acoustic measurements.

Twelve bounded `AudioStreamPlayer3D` voices feed Aircraft and Environment buses, then one scene bus with a -1 dBFS hard limiter. Godot supplies inverse-distance attenuation, speaker panning and distance filtering. Explicit geometric Doppler accounts for both moving endpoints; built-in Doppler is disabled to avoid applying it twice. The ratio is bounded and its observer resets across pauses, camera cuts and restarts. Dry-air temperature determines an approximate sound speed.

| Layer | Behaviour |
| --- | --- |
| Motor | Separate combustion, electric and turbine sources; accepted RPM controls pitch, throttle/load controls gain |
| Propeller | Blade-passing pitch, including the Mustang's four blades; load-dependent gain; windmilling remains audible when combustion stops; silent for turbines |
| Airframe | Speed-dependent broadband layer, spatially attached to the aircraft |
| Wind | Independent 29/31-second sources; actual wind/gust strength and horizontal direction place two broad nearby emitters |
| Foliage | Four independently phased sources at field treelines, wind-driven gain and slow unequal modulation |
| Birds | Six synthetic phrases, three bounded slots, no consecutive phrase repeat, varied timing/pitch/tree position; suppressed by night and strong wind |

Birds and foliage use actual decoded field treeline coordinates, including the pilot-relative offset. Vegetation screening samples at 10 Hz against at most 128 coarse canopy cells, then smooths attenuation and filtering over 250 ms. It is an estimated canopy treatment, not building collision or diffraction. Four foliage voices and eight directional tree anchors bound work.

Gain and pitch smooth over 90/40 ms. Pause fades in 80 ms before suspending streams; resume fades in 350 ms. Restart silences prior bird calls and resets the Doppler observer. A private scene RNG creates variation without consuming simulation/global random state; `--audio-seed=4102026` pins it for review. Scene disposal removes its unique buses.

## Integration and compatibility

The lead's `main.gd` changes attach the adapter only to normal physics gameplay, leaving scripted/capture and trace routes unchanged. `--soundscape=off` silences this flight's soundscape and the optional legacy scenery bed. `--soundscape=legacy` retains the original engine generator for G3b comparisons. When new audio is enabled, its adapter stops the old optional scenery ambience to avoid doubled wind/birds.

The legacy `_engine_audio` inspection alias points to the combustion/turbine motor only; electric retains its existing null contract. The time-of-day edit test's cleanup now releases the whole adapter before freeing the flight. No menu, physics, aircraft, scenery or world-renderer implementation was edited by this track. Concurrent shadow integration in `main.gd` was preserved.

WAV import sidecars explicitly select uncompressed 16-bit PCM. Godot's default QOA import was detected by the export check: compressed byte count cannot define a sample-frame loop endpoint. Endpoints now derive from duration × sample rate, and tests also require the intended PCM format. All 14 imported sources and notices are checked in an exported pack mounted from an empty project.

## Boundaries

This delivers authored immersion, not calibrated recordings or physical sound propagation. There is no propagation travel delay, terrain/building diffraction, frequency-dependent atmospheric absorption, species-specific birdsong, or acoustic cockpit model. The small synthetic source library is original and reproducible; [AUD-01](../AUD-01/sources.md) preserves licensed recording candidates for a future acoustic reference pass. This work does not close the separate roadmap's field-calibration gates.
