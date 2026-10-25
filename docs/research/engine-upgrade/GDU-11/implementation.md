# Incremental implementation of further 4.8 features

Official engine: `4.8.beta1.official.4d10419ca`. Work began 2026-10-25. Feature/API rationale and primary references remain in [opportunities](opportunities.md). Raw logs and captures are outside Git at `D:/OpenRCsimulator-experiments/gdu11-implementation/`.

## GDU-11e — Workshop search

Implemented through `workshop/library_search.gd`. Exact substring matches remain first in library order, followed by score-ranked fuzzy matches; ties use original indices. Duplicate names never serve as identity keys. Empty queries preserve ordering. Spanish composed/decomposed accents normalize only for matching. The result cap follows the eligible library size rather than Godot's default 100. Favorites are filtered before ranking; unavailable favorites retain their disabled load/copy actions and removable metadata.

Verification: `test_workshop_search.gd` passed 12 cases (including duplicate names, reordered words, typos, accents, no matches, short queries and 150 exact/fuzzy matches). `test_workshop_reuse.gd` passed the actual save/favorite/search/selection/profile-copy/deletion flow, including three approximate queries without draft mutation. `test_workshop_ui.gd` passed its full existing UI flow before the next change. These are software behavior checks, not loading-time benchmarks.

## GDU-11f — Bounded title fitting

Implemented for the Workshop heading and current build identity. Home retains its existing wrapping policy. Bounds use scaled theme tokens explicitly: Control theme lookup prioritizes the control's variation even when requesting the base type, which would otherwise make the bounds equal. A fixed preferred line height prevents a VBox from forcing every short title down to the minimum. The build identity retains its full-name tooltip and ellipsis fallback.

Verification: `test_ui_title_fit.gd` passed short, intermediate and overlong text at 100%/200%, bounded overflow and layout convergence; `test_ui_scale.gd` and the complete `test_workshop_ui.gd` passed. Native RTX 3090/Compatibility bridge session `20261025-161637-49185` captured actual 1920×1080 English and Spanish Workshop screens, including a maximum-length build name and 200% text. The enlarged build identity rendered at its 44-pixel minimum within its 44–56 range; the normal heading/build identity remained 28 pixels where space allowed. Captures were inspected for readable text, visible actions and bounded overflow. This is layout evidence on this host, not broad accessibility/hardware qualification.

## GDU-11b — Terrain crash marks

Implemented eight native decals plus eight retained plane slots, with a world-wide eight-decal reservation for crash owners. Headless/older engines and exhausted pools retain planes; an invalid terrain sample also selects the finite legacy plane. Slot zero remains the primary scorch throughout recycling. The fixed-wing director provides the accepted terrain sampler read-only; both representations align to its normal. Ground and lake basin join render bit 17; aircraft/wreck geometry does not. No physical contact, damage, fuel or simulation state is changed. The existing smoke texture supplies the mark mask; no new asset was generated.

The optional lake mirror excludes the new receiver bit as well as the original basin bits, while ordinary terrain remains visible through layer 1. Its regression uses a full-mask main camera and checks that the basin still receives decals without entering the mirror. Crash shader warmup draws a disposable decal against the production ground material in its own world, preserving live pools/seeds.

Verification: `test_ground_marks.gd` passed headless and native RTX 3090/Compatibility controls at actual 1920×1080. All sixteen marks visibly reach a single tilted receiver, including a run with the production ground shader; layer-mask negative controls remove all eight projected marks, and camera motion retains all sixteen. Tests cover ninth-mark fallback, two-owner budget, primary persistence, invalid samples and reset. `test_crash_effects.gd` passed 66 checks, `test_crash_energy.gd` 225, native warmup 18, and `test_crash_integration.gd` 202 each headless/native across the fixed-wing fleet. `test_lake_planar_reflection.gd` passed 75 checks after the layer correction. Native fleet audio used Dummy; this does not establish playback quality. Captures: external `decals/slope/` and `decals/production-material/`.

## GDU-11g — High contact shadows

Implemented behind the existing native Forward+ High gate. The renderer's version-cached contact setting is enabled during configuration; the sun explicitly allows its default filtered contact contribution. Atlas size, cascades, light energy, opacity, projected shadows and SSAO remain unchanged. Standard never enables this setting. This supplements ordinary shadow maps; only visible depth contributes to the additional screen-space term.

Verification: profile tests passed 68 headless and 81 native Forward+ checks. Six production views were captured with contact shadows off/on at actual 1920×1080, plus a low-sun flightline pair. The native `contact_shadow_probe.gd` detects added contact darkening, confirms a caster outside the viewport still produces its ordinary shadow (sample luminance 0.196 both off/on, versus 0.604 without shadows), and checks unchanged clear sunlight. The existing shadow-energy oracle also passed with zero sampled channel difference. Capture logs retain the pre-existing seven-Texture-RID ReflectionProbe warning in both full-scene treatments; it is not fixed by this feature.

Eight alternating static flightline timing runs used 10 s warmup and 5 s sampling each. Median GPU times per run: 1080p off 2.170/2.276 ms, on 2.305/2.311 ms; 1440p off 3.193/3.227 ms, on 3.398/3.237 ms. The small increase varies between runs; this is an RTX 3090 offscreen diagnostic, not a flight FPS guarantee or hardware qualification. Raw samples and controls: external `contact/`.
