# EL2a-P2 — main integration check

2026-10-11 · Step prefix: **EL** · **Status: verified integration checkpoint.**

The repository owner requested consolidation into `main`. The menu audit commit `2006c855` was merged through `852e34cc`; the release branch tip `d9d9a3bf` and detached checkout tip `28cd5c6a` were already ancestors of `main`. Their commit history and release tags are retained. Both local and remote branch inventories now contain only `main`; auxiliary checkout folders are retained with detached HEADs.

The pending EL2a-P2 implementation and tools are preserved in `4f8a75a`; the finalized documentation and qualification evidence are preserved in `3ef85cc`.

## Proof

- [Complete qualification](verification.json): candidate `app/test.sh` exit 0, 179 GDScript test programs, 72 Python unittest cases and zero engine error lines; offline tool suite exit 0 with 230 tests.
- All ten SHA-256 hashes in that verification report match their retained evidence files.
- The current app matches all 446 non-UID candidate files in the [source manifest](performance/source-manifest.json). Text comparisons normalize CRLF/LF; binary comparisons use exact bytes. The five changed runtime/test files and all five qualification tools also match the [source audit](source-audit.json).
- The consolidation reran 3,046 localization/stop/battery checks, five actual defect controls and eight event-tool regression tests successfully. A supplemental full-suite run passed through the unit, golden, model and several CLI checks before being stopped after the complete, matching qualification report became available; it is not counted as another completed full-suite pass.
- `git diff --check` and ancestry checks passed. A verified Git bundle and copies of pending work are retained locally under `.tools/git-consolidation-20261011/`.

The electric plan remains authoritative for physical and performance acceptance.
