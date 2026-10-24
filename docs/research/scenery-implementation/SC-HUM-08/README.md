# SC-HUM-08 — Shirts move in the wind; faces read better

Status: **implemented and software-verified, 2026-10-24.** Owner: Scenery and field life. Plan: [field people plan](../../../plans/field-people.md). This also closes the face and skin part of [SC-HUM-07](../SC-HUM-07/README.md).

All changes are in [population_person.gdshader](../../../../app/scenery/population_person.gdshader). There are no new draws, assets or CPU work.

## Cloth flutter (SC-HUM-08)

The lower front of tintable shirts (the fabric class) moves with the field wind (`wind_vec`):
- **Mask:** the shirt weight times a hem fade, so shoulders and collars stay pinned.
- **Direction:** the wind converted into each instance's local frame.
- **Amplitude:** 1.5 mm per m/s, capped at 8 m/s (12 mm).
- **Gust:** a 2.25 Hz modulation on whole cycles of the 1024 s simulation clock, with per-person phase.

Zero wind adds exactly zero, so scripted captures (wind forced to zero) and calm flights keep the exact rest geometry. The mechanic's work overalls are not in the fabric class and do not move. The default 4 mph field breeze gives about 3 mm, which is deliberately subtle; the constant is open to the owner's review (SC-HUM-09).

## Faces and skin (SC-HUM-07 remainder)

| Change | Why | Evidence |
| --- | --- | --- |
| Warm `BACKLIGHT` on skin (albedo × 0.42, 0.20, 0.14) | Compatibility has no subsurface scattering; the shadow side of faces read grey and plastic | A/B close-up: shadowed cheeks and ears turn warm skin tone |
| Merged outfits vary skin only ±8 % per person (LU-21 darkened its single skin up to ×0.32) | Each outfit now carries its own African, Asian or Caucasian skin; the old tint would over-darken them | Shader branch on `merged` |
| Alpha cut 0.5 → 0.3 | Thin eyebrow and hair strands were cut away (brows nearly invisible, worse in mips) | A/B: brows appear on every face; hair edges slightly fuller |
| Eyes: roughness 0.18, specular 0.6 | Eyes read as dark holes; a small wet highlight | A/B: subtle highlight |

The settings are uniforms (`skin_backlight`, `alpha_cut`, `eye_specular`, `eye_roughness`), so the owner can tune them without code changes.

## Verification

| Check | Result |
| --- | --- |
| Scratch native render, 1920×1080, four outfits | Calm frames identical before and after wind; wind changes 0.34 % of pixels, all in the shirt-hem rows; the flutter moves over time; the same instant with wind repeats exactly |
| `capture_population_assets` (native), now with wind instants | All 11 variants: motion, pause, reset and wrap pass; `wind_changes`, `wind_repeatable` and `calm_restored` pass, except that `wind_changes` is false for the two overalls variants, as designed |
| `test_field_people_gaze`, `test_landscape_population_assets`, `test_field_projected_shadows` (native) | Pass |

## Limits

- No pants, sleeve or hair motion; flutter is a vertex offset, not cloth simulation.
- Projected contact shadows do not follow the flutter (millimetres).
- Eye improvement is modest; faces remain low-poly proxies (about 1,300–2,000 body triangles).
