# DATA-1 — P-51 generated-output freshness in CI

2026-10-06 · **Status: implemented and verified locally.** Scope: [DATA-1](../../../../ROADMAP.md).

## Inspected and changed

The existing CI freshness step checked Stik/Extra/Avanti generation but omitted
the P-51 chain. All three P-51 generators already support read-only `--check`:

| Generator | Checks |
| --- | --- |
| `assets/aircraft/p51d-mustang-120/build_geometry.py` | `source.json` → `geometry.json` |
| `assets/aircraft/p51d-mustang-120/compile_geometry.py` | `geometry.json` → `app/aircraft/p51d_geometry.gd` |
| `research/p51/p51-05/derive_physics.py` | Aircraft/research inputs → `app/data/aircraft/p51d_mustang_120.json` **and** `research/p51/p51-05/derivation.md` |

Added their existing checks to the same CI step, before `app/test.sh`, preserving
the geometry build/compile order. CI reports stale outputs and stops; it does not
regenerate or silently repair them. The existing `app` → `export` → `release`
dependency also keeps a failed freshness check from publishing a tag's release.
No generator, generated file or simulation behavior changes.

## Proof

`actionlint` passes before and after the change. The [reproducible probe](verify.py)
extracts the actual workflow shell block and executes it with Bash fail-fast in
a fresh disposable clone. [Results](verification.json):

| Case | Previous freshness block | Updated block |
| --- | --- | --- |
| Fresh checkout | Pass | Pass (all eight commands) |
| Stale geometry JSON | Pass | Fail at geometry build |
| Stale runtime geometry | Pass | Fail at geometry compile |
| Stale physics JSON | Pass | Fail at physics derivation |
| Stale derivation report | Pass | Fail at physics derivation |
| Changed source span without regeneration | Pass | Fail at geometry build |
| Restored checkout | — | Pass |

Output mutations are valid whitespace/comments; their failure proves freshness
enforcement rather than a syntax error. Each check leaves the mutation intact.
Only the disposable clone is mutated. The previous **freshness step** is the
comparison target, not a claim that the entire old workflow passed every mutation.

No hosted Actions run, simulator rerun or export was performed for this three-line
workflow change. The probe verifies the changed CI step; simulation and generated
inputs/outputs remain unchanged.

This establishes reproducibility enforcement, not physical accuracy. A source
and its consistently regenerated outputs can agree while containing a bad model.

## Reproduce

From the repository root:

```bash
actionlint .github/workflows/ci.yml
python3 docs/research/aircraft-validation/DATA-1/verify.py --output /tmp/data1-verification.json
```

The probe uses Python's standard library, Git and Bash. Its default baseline
`baf5f86` precedes this CI repair; `--baseline-ref` can select another old workflow.

Suggested commit message:

```text
ci: check the P-51 geometry and physics generation chain (DATA-1)

Proof: actionlint; actual CI freshness block passes in a clean clone, rejects
five independent stale copies without rewriting, and passes after restoration.
```
