# Scenery tools

Offline tools of the scenery track ([SCENERY-PLAN](../../docs/SCENERY-PLAN.md)). Each writes committed files that it can also check with `--check`. No RNG anywhere: same input, same bytes.

| Tool | What it does | Command |
| --- | --- | --- |
| `place.py` | Lays out the default field's scenery and writes `app/data/scenery/default.json` (`openrc-scenery v1`). Stdlib Python, integer hashes. It rebuilds the L6b treeline's tree heights and skyline so that landmarks go where the pilot can see them (`--report` prints the visibility table) | `python3 tools/scenery/place.py [--check] [--report]` |
| `bake_models.gd` | Converts the third-party CC0 models (Quaternius cars, cow, sheep) into `openrc-scenery-model v1` JSON in `app/data/scenery/models/`. Checks each download's SHA-256, poses skinned meshes at their rest, puts the front to −Z, scales to the catalog size, reduces with meshoptimizer, and marks the car paint | `godot --headless --path app --script $PWD/tools/scenery/bake_models.gd -- --src=<downloads> [--check]` |
| `bake_fleet.gd` | Snapshots the four catalog aircraft through the model teams' builder (read-only), reduces each to about 2,200–3,800 triangles and bakes triangle colours. Re-run after a model team changes an aircraft | `godot --headless --path app --script $PWD/tools/scenery/bake_fleet.gd [-- --check]` |
| `capture.sh` | Renders every view of `app/scenery/postcards.gd` with scenery off and twice on, then `check_views.py` checks per-view budgets (pilot views: ≤ +40 draws, ≤ +150 k primitives; 0 shadow-pass draws) and byte repeats | `tools/scenery/capture.sh [out-dir]` (needs `xvfb-run`) |

**Downloads for `bake_models.gd`.** They are listed with their URLs in [assets/scenery/PROVENANCE.json](../../assets/scenery/PROVENANCE.json), and their SHA-256 values are in `app/scenery/models.gd`. They are never committed: only the baked derivatives are.

**The rest of the scenery is procedural:** buildings, people, trees, hedges, flowers and landmarks are built in `app/scenery/prefabs.gd` and `ground_features.gd`.

**How to see it:** `OPENRC_SCENERY=on $(app/get-godot.sh) --path app` (Home and flight), or `-- --scenery=on` on the direct route.

**Options:**
- `--scenery_theme=temperate|summer|autumn`
- `--scenery_quality=low|balanced|high`
- `--scenery_audio=off`
- `--scenery_birds=on`

Each option has an `OPENRC_SCENERY_*` environment-variable twin.
