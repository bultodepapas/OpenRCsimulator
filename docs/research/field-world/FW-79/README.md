# FW-79 visual capture record

This folder contains native renderer captures of the sky/weather appearance presets and electrical-storm night cases. They document rendered appearance only; they do not establish meteorological accuracy, flight physics, performance, or night-flight acceptance.

## Capture setup

- Pinned Godot 4.7.2, Compatibility renderer, NVIDIA GeForce RTX 3090.
- Production `World.build`, `Atmosphere.configure_appearance`, field, environment, and lighting paths.
- 1280 × 720 `SubViewport`, 4× MSAA, eight manually forced draw frames after each scene change.
- Fixed camera: 70° FOV, azimuth 315°, elevation 25°, default field pilot eye position.
- Day: 2026-06-21 13:00 local at the synthetic Bogota field (4.7° N, 74.1° W, UTC−5), astronomical lighting snapshot.
- Night: 2026-06-29 full Moon and 2026-06-15 new Moon, both at 00:00 local, resolved by the runtime ephemeris. Each uses the same deterministic electrical-storm event seed and records a peak and a quiet time.

`captures/manifest.json` records the engine build, adapter, camera, resolution, lighting, phase, and deterministic event ID for each image. The nine daytime thumbnail assets in `app/assets/sky/weather/previews/` are Lanczos-downsampled to 384 × 216 from the corresponding full-size daytime captures; night images do not generate previews. `captures/gallery.engine.log` contains the final combined engine/script output.

## Reproduction

From the repository root, run the pinned console executable without `--headless`:

```powershell
$galleryArgs = @('--path','app','--rendering-method','gl_compatibility','--rendering-driver','opengl3','--audio-driver','Dummy','--script',(Resolve-Path 'tools/atmosphere/sky_gallery.gd').Path,'--','--out=C:/tmp/fw79-captures','--mode=all','--write-previews=on','--overwrite-previews=on','--horizon=off','--frames=8')
& (Resolve-Path '.tools/Godot_v4.7.2-stable_win64_console.exe') @galleryArgs
```

Use a new output directory, or pass `--overwrite=on --overwrite-previews=on` to replace captures and previews deliberately. `--mode=day` and `--mode=night` select subsets. The optional `--horizon=on` writes a second low-elevation view for each case.

## Visual review

The final gallery contains nine daytime profiles and four deterministic storm-night states. Clear is cloud-free; cirrus streaks and fair-weather cumulus cells are distinct at the fixed camera; broken and overcast layers have broader tonal structure; prestorm and distant-storm profiles form darker, larger masses. The electrical-storm captures show a dark daytime deck, a visible event-peak bolt under both full- and new-Moon conditions, and quiet frames without a bolt. These are stylized, deterministic render tests; they do not validate meteorological accuracy, aircraft response, or storm hazards.

The art gate remains open. Overcast shows stylized horizontal tonal bands rather than volumetric rolls; cirrus has strong projected streaks. The distant-storm profile has no world-anchored vertical thunderhead or rain curtain. A fixed sky-facing camera cannot qualify pilot/chase/onboard traversal, horizon behavior, small-aircraft contrast or a complete storm flight. These limits remain in FW-79/80/83/84; the gallery is not a claim that every preset has reached the requested final visual quality.

The calibrated classic field/sky path also has a separate [12-view pixel comparison](classic-parity/comparison.json), with retained sun/ground pairs. Its scope and frozen-baseline limitation are described in [FW-78](../FW-78/README.md#visual-evidence-and-package-inventory).
