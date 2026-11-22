# VRC plan verification

This directory supports the [vehicle runtime consolidation plan](../../docs/plans/vehicle-runtime-consolidation.md) and its [adversarial review](../../docs/research/vehicle-runtime-consolidation-2026-11-21/EXTERNAL-AUDIT.md). It contains no gameplay implementation or engine test.

`verify_plan.py` checks the pinned inventory, proposed case/finding references, pinned test paths and their `extends SceneTree` declarations, generated matrix, local/pinned-source links and anchors, source line ranges, unchanged tracked `app/` in index and worktree, absence of nonignored untracked app files, historical 22/27 result and tracked Git whitespace. It does not parse or execute GDScript. Ignored generated app/cache state is outside that unchanged-source claim. Stage all owned new deliverables before final whitespace verification. The checker does not evaluate gameplay oracles. All dated cases are UNRUN; later runtime receipts belong in a new evidence record linked from the owning VRC step. Invalid case/status data blocks matrix regeneration before a write.

The organization refinement also checks [organization-map.json](../../docs/research/vehicle-runtime-consolidation-2026-11-21/organization-map.json) against the pinned file bytes, Git blobs, line counts and exact symbol declarations/URLs, plus route/case/step references and existing test launcher declarations. It compares every semantic action ID/label/context/mode and AUX name in [action-consumers.json](../../docs/research/vehicle-runtime-consolidation-2026-11-21/action-consumers.json) with the literal pinned catalog. Examples remain UNRUN and uncharacterized coverage cannot become a support claim. These checks verify reference/data consistency, not whether a proposed design is semantically correct. The initial receipt must remain byte-identical to the one at `8d61ca900a30686bc00eaf5ce80bee664e592a46`; use a new receipt for this revision.

From repository root, regenerate the human-readable matrix after editing its canonical JSON:

```sh
python3 research/vehicle-runtime-consolidation/verify_plan.py --write-matrix
```

Check without modifying the matrix, optionally writing a new ignored receipt:

```sh
python3 research/vehicle-runtime-consolidation/verify_plan.py \
  --output tmp/vrc-plan-review-check/report.json
```

The output path must be new. The checker requires the pinned source/proposal/prior-audit/refinement-base commits locally; fetch the final `audit/game-controls-2026-11-21` branch with its history if absent. Its merge ancestry retains all required commits. It reads Git objects for files omitted by sparse checkout. The receipt hashes reviewed artifacts, excluding its own output to avoid a circular hash. The preserved [initial receipt](../../docs/research/vehicle-runtime-consolidation-2026-11-21/verification.json) and [organization receipt](../../docs/research/vehicle-runtime-consolidation-2026-11-21/organization-verification.json) describe their historical snapshots. The [combined-branch receipt](../../docs/research/vehicle-runtime-consolidation-2026-11-21/consolidated-plan-verification.json) checks the consolidated plan artifacts; its scope does not include validating every original controls-audit artifact. All three are dated static results, not live status badges or CI receipts. The checker records external URLs but does not fetch them; [primary research](../../docs/research/vehicle-runtime-consolidation-2026-11-21/PRIMARY-SOURCES.md) documents the separate web investigation and its version limits.
