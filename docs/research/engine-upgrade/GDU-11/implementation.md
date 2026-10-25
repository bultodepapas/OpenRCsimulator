# Incremental implementation of further 4.8 features

Official engine: `4.8.beta1.official.4d10419ca`. Work began 2026-10-25. Feature/API rationale and primary references remain in [opportunities](opportunities.md). Raw logs and captures are outside Git at `D:/OpenRCsimulator-experiments/gdu11-implementation/`.

## GDU-11e — Workshop search

Implemented through `workshop/library_search.gd`. Exact substring matches remain first in library order, followed by score-ranked fuzzy matches; ties use original indices. Duplicate names never serve as identity keys. Empty queries preserve ordering. Spanish composed/decomposed accents normalize only for matching. The result cap follows the eligible library size rather than Godot's default 100. Favorites are filtered before ranking; unavailable favorites retain their disabled load/copy actions and removable metadata.

Verification: `test_workshop_search.gd` passed 12 cases (including duplicate names, reordered words, typos, accents, no matches, short queries and 150 exact/fuzzy matches). `test_workshop_reuse.gd` passed the actual save/favorite/search/selection/profile-copy/deletion flow, including three approximate queries without draft mutation. `test_workshop_ui.gd` passed its full existing UI flow before the next change. These are software behavior checks, not loading-time benchmarks.

## GDU-11f — Bounded title fitting

Implemented for the Workshop heading and current build identity. Home retains its existing wrapping policy. Bounds use scaled theme tokens explicitly: Control theme lookup prioritizes the control's variation even when requesting the base type, which would otherwise make the bounds equal. A fixed preferred line height prevents a VBox from forcing every short title down to the minimum. The build identity retains its full-name tooltip and ellipsis fallback.

Verification: `test_ui_title_fit.gd` passed short, intermediate and overlong text at 100%/200%, bounded overflow and layout convergence; `test_ui_scale.gd` and the complete `test_workshop_ui.gd` passed. Native RTX 3090/Compatibility bridge session `20261025-161637-49185` captured actual 1920×1080 English and Spanish Workshop screens, including a maximum-length build name and 200% text. The enlarged build identity rendered at its 44-pixel minimum within its 44–56 range; the normal heading/build identity remained 28 pixels where space allowed. Captures were inspected for readable text, visible actions and bounded overflow. This is layout evidence on this host, not broad accessibility/hardware qualification.
