# PT1 — first official release qualification

The published `v0.1.0` tag is frozen at `0a631b52242cdc5c243668865d4bed3d1e22aa98`, prepared on `release/v0.1.0` in an isolated checkout from `920a6a90`. [Release notes](../../../releases/v0.1.0.md) define the early-development scope and remaining physical, native-platform and hardware qualifications. Publication requires the complete tagged CI and three-platform export gates; local continuation logs alone do not qualify the release.

## Integration corrections

The preflight exposed incompatible airplane/rotorcraft proof boundaries, missing generated rotor coverage inputs, an aircraft-contact parse error and strict v2/v1 compatibility issues. Rotorcraft configuration now has its own data directory; airplane-only qualification remains strict, while exported rotorcraft has a separate resource/load smoke. Generated HX-700 profiles are bound to the reviewed GLB, algorithm and byte hash in the [source manifest](../../../../assets/aircraft/hx-700/source-manifest.json). Geometry and physics sources remain authoritative.

Several tests retained earlier contracts: procedural grass batches, gravel layout, Timber hinge names, marker projection, default control rates, provenance fixtures and weighted Natural Random recipe selection. Their corrected checks exercise the accepted runtime/source contracts. Natural Random identity serialization used unsupported Godot `%g`; the supported formatter retains 12-significant-digit canonical identity and tests tiny/large magnitudes, rounding boundaries, uint32 normalization, parsed-value preservation and 10,000 weighted samples.

The vehicle dynamics fixture used north-position index 0 as forward velocity; index 3 now produces measured braking from 2.695 to 0.386 m/s and 0.0086 m bump-induced suspension travel. Its steering-sign check samples the initial response before the aggressive synthetic maneuver rolls over. This does not establish vehicle physical validation.

Finite-fuel glow models balance at launch within approximately 5e-12 m and 1e-10 m/s at the first 1/240 s tick. Their modeled fuel/thermal evolution produces approximately 0.089 m altitude change over ten seconds. The pilot-trim test now verifies initial balance, finite fault-free advancement, engine-running state and consumed fuel for that explicit capability; other models retain the exact ten-second equilibrium check. No physics or flight golden files were changed.

Unchanged landing-variation and thirteen-launch CLI checks passed in 60.62 s and 72.86 s respectively on Linux. Each now has a bounded 180-second deadline, retaining every assertion.

Fresh Timber imports exposed a cache-dependent measurement mismatch. Default mesh compression changes 2,772 measurement leaves and would alter 337 derived geometry and 58 physics leaves. Explicitly disabling mesh attribute compression reproduces the accepted r2 measurement report exactly on a clean Godot 4.7.2 import. The release pins that option, regenerates only its model-manifest and Workshop dependency hashes, and preserves the GLB, canonical metrology, geometry and physics bytes. The [aircraft guide](../../../../assets/aircraft/turbo-lumber-evolution/README.md) owns this import policy.

## Daylight readability

The reviewed source palette keeps hue, saturation, layout, geometry, normal maps and gloss. Display calibration changes red from `#c8102e` to `#b00e28` and white from `#f7f6f1` to `#b8b7b3`; black is unchanged. This is a display calibration, not measured paint reflectance. Appearance, model and Workshop descriptor outputs were regenerated through their source pipelines.

The actual 30 m capture improves Weber contrast from -0.279 to -0.416 with 11.94% low-contrast pixels; the low 3 m capture improves from -0.415 to -0.486 with the low-contrast share reduced from 24% to 12%. Existing limits remain Weber <= -0.40 and low-contrast share <= 15%. Repeated candidate captures are byte-identical and their no-airplane baselines match. The complete rendered inventory remains a publication gate.

## Completed local preflight

Local qualification covered all 340 GDScript test scripts through continuations and focused reruns, plus the original shell-tail checks. Four golden replays, one-ULP signatures, deliberate branch mutation detection and 30/60/144 FPS complete-state checks pass. E5a/E5b contact checks pass. No golden flight was replaced.

The trace recorder now accepts at most one float64 ULP between the first live shaft RPM and its JSON metadata; the hot-high fixture's 3618.158384960468 RPM decoded one ULP lower. The regression rejects two-ULP mismatches, and all ten shaft CLI tests pass. Turbine weather readers accept only the documented RK4 timing; negative timing and incomplete v6 wheel-metadata controls remain enforced. Turbulence, atmosphere and trace acceptance suites pass 10, 6 and 16 tests. The input test explicitly drains all audio player types before freeing each scene; two fresh verbose runs pass 22 assertions without leaked objects or outstanding resources.

Render qualification covered 46 base images, 66 VQ cases, 64 distant-aircraft views, repeated atmosphere/horizon/cloud/surface/cue checks, grass and tree-wind checks, and the runway scenario. These component runs resumed after correcting the obsolete grass checker; they are not a single uninterrupted final-candidate capture run. [Preflight inventory and review hashes](preflight-capture-manifest.json) retain their outputs; tagged CI must rerun the full sequence from the final commit.

The grass checker preserves the procedural fallback's wind tests and adds the current imported-source contract. Two independent processes repeat 28 fallback and two imported-scenery images exactly. Imported grass changes 2,015 pixels inside the placement mask, adds three draws and preserves its three textured source batches and current botanical flower inventory. The seam test passes (FLIP p99 0.06581) and rejects its dark-seam mutation. Tree wind repeats 104 images per process. The runway software scenario holds idle speed below 1.80e-14 m/s, heading error below 1.07 degrees and reaches 42.3 m at 12 s; this is not physical takeoff validation.

Three-platform provisional export passed Linux execution, resource-pack and platform identity checks. The official tag requires fresh packages with its own identity and checksums; provisional archive hashes do not identify published downloads.

## Published qualification — 2026-10-14

[Tagged CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38515832752) passed the complete app test and capture sequences, archived prototype checks, three-platform export and publication. The capture sequence reports 46 fresh base images with manifests and 66 VQ captures; the original daylight thresholds pass. The [official release](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0) is published, not a draft or prerelease, and is GitHub’s latest release.

All three downloaded archives pass the published `SHA256SUMS`; every asset, including that checksum file, also matches GitHub’s SHA-256 digest. These identify the published CI packages rather than the provisional local exports.

| Archive | Published SHA-256 |
| --- | --- |
| `openrc-simulator-v0.1.0-linux-x86_64.zip` | `589508b63dcf35fada4b83219aca2d7b06f6e509f5f1bcb03f282b03f2c6c55b` |
| `openrc-simulator-v0.1.0-macos-universal.zip` | `ba8dcd86757dfeeee42e43f31ad2e12e806289137f09ff2b9dfd12dd5bef043e` |
| `openrc-simulator-v0.1.0-windows-x86_64.zip` | `4e57ab85114bda7abea9cb8651f51a21c194adb16103d4cef726761d66ff1e48` |

The downloaded Linux executable reports `v0.1.0` and passes trimmed flight for 720 ticks / 3 seconds, holding 30 m altitude and 15 m/s with finite samples. Its P-51 coupled-RK4 hot-high regression writes all 61 rows through tick 60 and passes the atmosphere checker. Both launches use isolated user-data directories and exit without engine errors. Native-platform and physical qualifications remain as stated in the release notes.
