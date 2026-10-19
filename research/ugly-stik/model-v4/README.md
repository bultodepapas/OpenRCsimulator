# Jensen Ugly Stik .61 — visual evidence v4

2026-10-05 delivery snapshot. Current authoring/check/capture commands live in the [asset guide](../../../assets/aircraft/ugly-stik-60/README.md). [Later focused verification](../../../docs/research/ugly-stik-finish-v6.md#2026-10-19-documentation-recheck) is separate from these results.

[Offline gallery](review.html) · [Blind orientation form](readability36/review.html) · [Delivery report](../../../docs/research/ugly-stik-model-v4.md) · [Validation](validation.json).

The original five manifests contain 95 captures: inspection 9, orientation 36, details 12, movement 36 and presentation 2. Each records source hashes, camera, pose, lighting, renderer, mesh counts and crop policy. `comparison.json` records diagnostic differences against v3 and an independent 36/36 PNG repeat. Human responses and hardware GPU acceptance remain pending.

Use the [capture workflow](../../../assets/aircraft/ugly-stik-60/README.md#captures) with a fresh output destination and its declared dependencies. The gallery generator reuses the historical orientation-form renderer without altering historical evidence. Closing the movement viewer stops the slideshow; its presentation interval is not simulation time.

`atlas-fixture/` contains only the reproducible SVG import setup. The checker supplies current generated artwork in a temporary project and verifies imported/runtime pixel equality. Mutations run in disposable copies, never in the shared app. `validation-logs/` retains the final passing application run and the earlier parallel-development failures separately. No third-party photographs, cached Godot imports or downloaded binaries are needed by the visual model.
