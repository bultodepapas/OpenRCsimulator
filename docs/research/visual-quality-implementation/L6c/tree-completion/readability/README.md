# Native static aircraft readability matrix

2026-10-18 · Godot 4.7.2 · Windows · NVIDIA GeForce RTX 3090 · Compatibility renderer. This is a native, static inspection of the frozen candidate and its paired frozen baseline. It measures aircraft pixels and local image contrast; it does not supply a human recognition score, flight-quality result, or performance acceptance.

Each application has 80 captures per light/resolution configuration: two aircraft, 20/50/100 m, sky and tree backgrounds, normal and autozoom views, level/inverted poses at 20 and 50 m, and six attitudes at 100 m. Four lighting presets and 1280×720 / 1920×1080 produce 640 captures for candidate and 640 for baseline. The fixture uses normal aircraft materials without the optional night kit. The measured FOV and camera transform are retained per image; autozoom does not widen the 50° base FOV when the aircraft already projects larger than its target.

The reducer requires at least 60% tree pixels around a requested tree case and 90% sky pixels around a sky case. These are case-identity checks, not readability thresholds. The 20/50/100 m probes stop at the existing evidence range: the older L1b controls cover 3 and 30 m, while the L6c owner kit covers 100 m. The L6c kit remains the separate human review, and there is no accepted aircraft visibility evidence beyond 100 m.

## Paired results

The same capture fixture, reducer, and Godot engine hashes were used for both frozen applications. Their source identity differs in nine field/tree/import files, listed in [paired-metrics.json](paired-metrics.json). Source identity excludes `.uid` files. All 640 capture keys and camera/projection values pair exactly.

| Light | Resolution | Candidate zero-pixel cases | Baseline zero-pixel cases | Candidate background mismatches | Baseline background mismatches |
| --- | ---: | ---: | ---: | ---: | ---: |
| Noon | 720p | 0 | 0 | 12 | 12 |
| Low sun | 720p | 0 | 0 | 12 | 14 |
| Sunset | 720p | 0 | 0 | 12 | 12 |
| Night | 720p | 64 | 64 | 72 | 72 |
| Noon | 1080p | 0 | 0 | 10 | 10 |
| Low sun | 1080p | 0 | 0 | 12 | 14 |
| Sunset | 1080p | 0 | 0 | 10 | 10 |
| Night | 1080p | 64 | 64 | 72 | 72 |

At each resolution, the exact same 64 of 80 night cases have zero aircraft pixels in candidate and baseline. They are all 50 m and 100 m; the 16 positive 20 m cases have identical measured metrics across the pair. This confirms no new night invisibility from the tree change. It does not make the night cases pass: the aircraft is visibly absent at the longer distances under this fixture.

Night also has 72 background-screen failures at each resolution: 64 are the zero-pixel rows above; the other eight are visible 20 m tree requests classified as 0% trees and 100% sky in both apps. Near-black frames do not verify whether the requested tree background is present, so these are not canopy-coverage evidence.

There are no zero-pixel cases in noon, low-sun, or sunset. Daylight tree-background mismatches are mixed tree/sky regions; some low-sun rows also include ground. All fail the 60% tree-identity screen and remain counted as failures. In low-sun 1080p, the candidate adds one Stik 50 m tree-background mismatch (49.8% trees, 16.6% sky, 33.6% ground); the paired baseline row has 75.1% trees and no ground. The candidate also removes three baseline-only low-sun 1080p mismatches where the baseline image includes ground. The exact per-case lists and metrics remain in the paired report. These controls do not justify changing field placement or relaxing the screen.

The first candidate attempt, `readability-final`, is an invalid diagnostic because aircraft ground shadows leaked into the background reference; it is not acceptance evidence. Its complete 720p configs recorded 38/80 noon, 21/80 low-sun, 12/80 sunset, and 72/80 night background mismatches, with zero-pixel counts 0, 0, 0, and 64. The `noon-1080` folder is partial and has no metrics. Hashes and exact source paths are in the `invalid_diagnostics` record in [paired-metrics.json](paired-metrics.json). R2 disables shadow casting on inspection aircraft while leaving scenery shadow casting unchanged; both R2 candidate and baseline manifests record this correction.

## Evidence files

- [Paired metrics and source identity summary](paired-metrics.json) contains the exact matched zero-pixel sets, background mismatch deltas, artifact hashes, and reproduction commands.
- `candidate/` and `baseline/` retain each run's metrics, capture manifests, source identity, and reducer summary. Full capture PNGs remain under `tmp/tree-completion/readability-final-r2` and `tmp/tree-completion/readability-baseline-r2`.
- `representative/` holds candidate 720p tree-background captures at 100 m across all four lights, plus two mixed-canopy controls. Night examples visibly lack the aircraft.

Reproduce each matrix from the repository root:

```powershell
python tools/trees/readability_compare.py --godot .tools/Godot_v4.7.2-stable_win64.exe --app tmp/tree-completion/frozen/candidate/app --out tmp/tree-completion/readability-final-r2
python tools/trees/readability_compare.py --godot .tools/Godot_v4.7.2-stable_win64.exe --app tmp/tree-completion/frozen/baseline/app --out tmp/tree-completion/readability-baseline-r2
```

The comparison is a static screen for this specific 20/50/100 m matrix. It does not replace the pending owner kit or extend its acceptance range.
