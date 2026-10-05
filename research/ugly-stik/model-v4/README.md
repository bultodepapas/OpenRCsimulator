# Jensen Ugly Stik .61 — visual evidence v4

[Offline gallery](review.html) · [Blind orientation form](readability36/review.html) · [Delivery report](../../../docs/research/ugly-stik-model-v4.md) · [Validation](validation.json).

The five manifests contain 95 captures: inspection 9, orientation 36, details 12, movement 36 and presentation 2. Each records source hashes, camera, pose, lighting, renderer, mesh counts and crop policy. `comparison.json` records diagnostic differences against v3 and an independent 36/36 PNG repeat. Human responses and hardware GPU acceptance remain pending.

From the repository root, choose a new output directory:

```bash
research/ugly-stik/model-v4/capture.sh --output-dir /tmp/ugly-stik-v4-new
python3 research/ugly-stik/model-v4/check_atlas.py --log /tmp/atlas-check.log
python3 research/ugly-stik/model-v4/check_mutations.py
```

Capture requires the pinned Godot, `xvfb-run` and Pillow 11.3.0 from `requirements.txt`. It refuses existing outputs and v1/v2/v3 destinations. The gallery generator reuses the historical orientation-form renderer without altering historical evidence. Closing the movement viewer stops the slideshow; its presentation interval is not simulation time.

`atlas-fixture/` contains only the reproducible SVG import setup. The checker supplies current generated artwork in a temporary project and verifies imported/runtime pixel equality. Mutations run in disposable copies, never in the shared app. `validation-logs/` retains the final passing application run and the earlier parallel-development failures separately. No third-party photographs, cached Godot imports or downloaded binaries are needed by the visual model.
