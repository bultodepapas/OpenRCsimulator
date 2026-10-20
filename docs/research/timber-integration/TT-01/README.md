# TT-01 — freeze the r1 source and its identity

2026-10-12 · **Status: complete.** Owning plan: [Timber integration](../../../TIMBER-INTEGRATION-PLAN.md). Asset guide: [assets/aircraft/turbo-lumber-evolution/README.md](../../../../assets/aircraft/turbo-lumber-evolution/README.md).

## What was done

- `research/timber/tt01/manifest.py` hashes every file of the tracked delivery `assets/source-deliveries/turbo-timber-evolution-original/turbo_timber_evolution/r1/` and writes `assets/aircraft/turbo-lumber-evolution/source-manifest.json`: 38 files, 12,301,268 bytes, key files by role (GLB, demo GLB, metadata, export map, verification, Blender scene, licence, readme, changelog), the visual revision `r1-fb7586f19029` and the informational git commit `28cd5c6`.
- The 38 hashes are identical to the independent [TT-00-R1 binary audit](../TT-00-R1/glb-audit.json) (checked with a one-off Python comparison of both tables).
- The asset README records origin, author, hardware revision, loadout, catalog ID and source alias, the terms status and the r2 request list.

## Command and result

```bash
python3 research/timber/tt01/manifest.py            # wrote assets/aircraft/turbo-lumber-evolution/source-manifest.json (38 files, 12301268 bytes, visual revision r1-fb7586f19029)
python3 research/timber/tt01/manifest.py --check    # Timber r1 delivery: 38 files, 12301268 bytes, visual revision r1-fb7586f19029: identical to the manifest
```

`--check` compares file paths, sizes and SHA-256 only, so shallow clones verify the bytes without git history. It runs in `app/test.sh` and in the CI generator step.

## Terms (decision D1)

The delivery `LICENSE.txt` limits the package to internal evaluation with terms "not yet set". The owner stated on 2026-10-12 that the model is inspired by the aircraft, built from photographs without manufacturer plans or artwork, and that the in-game name will be chosen later; the terms text is therefore a later naming decision, not a development blocker. The packaged release step (TT-17) still needs the chosen text in the copied `LICENSE.txt`.

## Limits

No app change. The manifest proves identity, not quality: the r2 requests (reproducible rebuild, failing verifier, nose length, mass ledger) are listed in the asset README and remain open.
