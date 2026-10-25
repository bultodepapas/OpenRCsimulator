# Incremental implementation of further 4.8 features

Official engine: `4.8.beta1.official.4d10419ca`. Work began 2026-10-25. Feature/API rationale and primary references remain in [opportunities](opportunities.md). Raw logs and captures are outside Git at `D:/OpenRCsimulator-experiments/gdu11-implementation/`.

## GDU-11e — Workshop search

Implemented through `workshop/library_search.gd`. Exact substring matches remain first in library order, followed by score-ranked fuzzy matches; ties use original indices. Duplicate names never serve as identity keys. Empty queries preserve ordering. Spanish composed/decomposed accents normalize only for matching. The result cap follows the eligible library size rather than Godot's default 100. Favorites are filtered before ranking; unavailable favorites retain their disabled load/copy actions and removable metadata.

Verification: `test_workshop_search.gd` passed 12 cases (including duplicate names, reordered words, typos, accents, no matches, short queries and 150 exact/fuzzy matches). `test_workshop_reuse.gd` passed the actual save/favorite/search/selection/profile-copy/deletion flow, including three approximate queries without draft mutation. `test_workshop_ui.gd` passed its full existing UI flow before the next change. These are software behavior checks, not loading-time benchmarks.

## GDU-11f — Bounded title fitting

Implementation in progress. Scope: Workshop heading and current build identity. Home retains its existing wrapping policy. Bounds use scaled theme tokens explicitly: Control theme lookup prioritizes the control's variation even when requesting the base type, which would otherwise make the bounds equal. A fixed preferred line height prevents a VBox from forcing every short title down to the minimum. The build identity retains its full-name tooltip and ellipsis fallback.
