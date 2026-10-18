# Diagnostic understory comparison snapshots

These snapshots extend the original frozen tree comparison for the first forest-edge understory layout. They are a diagnostic stage only and are not eligible for final timing. No timed performance runs have been made on them.

The parent pair is `tmp/tree-completion/frozen/{baseline,candidate}/app`, frozen from commit `090bbf2e303b2edbd961a786048b24dea18439de`. The parent's reconstructed baseline retains its pre-plan card shaders, field recipe, imported-tree aliases, and mip settings; those baseline/candidate differences remain unchanged here. Parent source fingerprints and receipt hashes are in [`freeze-understory.json`](freeze-understory.json). This comparison is therefore a continuation of the existing tree comparison, not a newly reconstructed historical build.

Both apps were copied from their respective parent snapshots without `.godot`, `captures`, `__pycache__`, or `tmp`. The external `assets/` and `tools/audio/` directories were copied from the same parent label and verified identical. The only pre-import overlays are:

- Both labels add `app/scenery/woodland_edge_habitat.gd` and `app/data/woodland_edges.json`.
- Candidate only replaces `app/scenery/scenery.gd` with the current source that builds and attaches the woodland-edge habitat and records its counts and build time.
- The baseline editor import generated `app/scenery/woodland_edge_habitat.gd.uid`; those exact bytes were copied to the working app and candidate before its import.

No current `app/main.gd`, `app/render/frame_samples.gd`, `app/scenery/imported_near_grass.gd`, or test files were overlaid. The inherited physics, audio, flight input, and grass sources are unchanged from the parent snapshots. [`file-map.json`](file-map.json) lists the parent, pre-import, and post-import SHA-256 and sizes for every overlay, plus the parent receipt identities and preserved external directory hashes.

Both native Godot 4.7.2 headless editor imports passed with exit code 0 and no `ERROR` markers. Baseline source SHA-256 changed from `7779dc69800cddd1e73547626dfd4dc4903213df5617b32865594509f4a7db3b` to `c68f596064dd2b35a5bc2443278204c720ca5d70d96935ca2f38417fb9722083`, solely from the generated UID sidecar. Candidate was imported after the same UID was propagated: its pre-import and post-import source SHA-256 are both `2bfe3bd15659c9b88f2a5ef5a8307fa0ecd99696885ec01832d3ed028a8ce20e`. The original parents remain unchanged. [`import-report.json`](import-report.json) and [`logs/`](logs/) retain the commands, results, and native logs. Source fingerprints exclude generated `.godot` and `.git` content.

Root's native visual review found that the first layout's two straight shrub rows per patch read as garden rows. The habitat data is being revised to use an irregular cluster pattern under the same triangle budget and masks; runtime code is unchanged. This frozen pair preserves the pre-revision data as diagnostic evidence. Do not edit or reuse it for final timing. After the revised layout passes visual review, prepare a new versioned pair or small data-only overlay and point the five alternating baseline/candidate pairs at that new source. The planned campaign remains 10 seconds of warmup and 60 seconds of measurement per run, with baseline `OPENRC_TREE_WIND=off`, candidate `OPENRC_TREE_WIND=on`, and default grass quality. General runner and clock definitions are in [`flight-quality-harness.md`](../flight-quality-harness.md).

The sibling [temporal clip set](../temporal/README.md) predates this pair and uses the original oak-era candidate without understory; it is not footage from these snapshots. This folder records comparison identity and native import evidence, not a human readability decision or final owner acceptance.
