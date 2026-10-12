# LU-13 — bounded diffuse twilight palette

Status: integrated and checked on native Godot 4.7.2 Compatibility, 2026-10-12.

The existing FW sky table approximates direct and diffuse light with saturated orange near sunset. The baseline club image shows that hue across the entire sky and shaded materials. Primary atmospheric references in [resources](resources.md) support a blue upper sky and spatially varying twilight; they do not numerically calibrate this change.

[`twilight_palette.gd`](../../../../app/render/landscape_upgrade/twilight_palette.gd) applies a smooth chromaticity blend to the existing `SkyState.state` zenith, haze and cloud colors. Its weight is `smoothstep(-10,-4,elevation) × (1-smoothstep(4,12,elevation))`; RGB targets and strengths are explicit art estimates. Each target is normalized to the source's linear Rec. 709 luminance before blending. Ambient color follows the corrected diffuse colors. Direct sun/moon colors and directions, solar-disc visibility, sunward lobe, source metadata, scalar brightness, ephemeris and deterministic world clock remain unchanged. Outside the band the function returns its input exactly.

The baseline fixture was generated on the installed engine **before** changing `sky_state.gd`, from commit `8b2020f`. It preserves 13 complete states from −25° to +73°, source hash and engine metadata. Vector bytes are retained in little-endian float32 form because the engine's decimal JSON round trip changed some tiny values. The regression checks exact unaffected vectors, scalar/exposure and affected-luminance agreement within 2 ppm, repeated-state determinism, a cooler sunset zenith with warm direct sunlight, and continuity over 2,203 samples. **394 checks pass**; [raw log](checks/root-test_landscape_twilight.log).

Native views cover dawn, golden hour, sunset, blue hour, deep night, fixed daylight, shadows and explicit static TOD. The final controlled aircraft image uses the same real model, position, camera, bank/yaw and matched exposure as its baseline, with a separately rendered background in each state. The contrast screen passes with a 1.1607 after/before ratio; [metric definition and limits](materials.md). Native source-independent glare and marker checks also pass. The static TOD lighting path does not use this FW palette and remains a separate regression case.

This is a diffuse-light palette correction, not a replacement spectral atmosphere, aerosol model, photometric calibration or guarantee of pilot readability in every view.
