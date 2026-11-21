# VRC plan verification

This directory supports the [vehicle runtime consolidation plan](../../docs/plans/vehicle-runtime-consolidation.md) and its [adversarial review](../../docs/research/vehicle-runtime-consolidation-2026-11-21/EXTERNAL-AUDIT.md). It contains no gameplay implementation or engine test.

`verify_plan.py` checks the pinned inventory, proposed case/finding references, pinned test paths and their `extends SceneTree` declarations, generated matrix, local/pinned-source links and anchors, source line ranges, unchanged tracked `app/` in index and worktree, absence of nonignored untracked app files, historical 22/27 result and tracked Git whitespace. It does not parse or execute GDScript. Ignored generated app/cache state is outside that unchanged-source claim. Stage all owned new deliverables before final whitespace verification. The checker does not evaluate gameplay oracles. All dated cases are UNRUN; later runtime receipts belong in a new evidence record linked from the owning VRC step. Invalid case/status data blocks matrix regeneration before a write.

From repository root, regenerate the human-readable matrix after editing its canonical JSON:

```sh
python3 research/vehicle-runtime-consolidation/verify_plan.py --write-matrix
```

Check without modifying the matrix, optionally writing a new ignored receipt:

```sh
python3 research/vehicle-runtime-consolidation/verify_plan.py \
  --output tmp/vrc-plan-review-check/report.json
```

The output path must be new. The checker requires the pinned source/proposal/prior-audit commits locally; obtain the named branches through ordinary repository access if absent. It reads Git objects for files omitted by sparse checkout. The receipt records hashes of reviewed artifacts, excluding itself to avoid a circular hash. The checked-in [verification receipt](../../docs/research/vehicle-runtime-consolidation-2026-11-21/verification.json) is the dated static result, not a live status badge or CI receipt.
