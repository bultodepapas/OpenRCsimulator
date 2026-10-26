# GP-11 broad regression evidence

**2026-10-26 — overall FAILED.** All 1,374 app scripts parsed. All 751 unit scripts ran exactly once: **734 passed, 17 failed**. The original offline/integration gates completed as a disclosed composite after isolated checkout/import metadata repairs. This is not an uninterrupted `app/test.sh` pass.

The runtime cohort is base `b85ce1047a3e7798ab22b330675fc0c9e4bce912`, the [GP-10 final nine snapshots](../../GP-10/evidence/manifest.json), and the [original GP-11 36-source cohort](../evidence/manifest.json), plus the recorded repairs below. FlightSession remains the GP-10 version. Later GP-12 electric/source, step, admission, traction-row and reset changes are excluded. The separate current-main register receipt mentioned in the raw report is bookkeeping only; no current-main source snapshots are included or qualified here.

Start with the [sealed report](report.json), [exact unit coverage](R6/unit-coverage.json), [failure attribution index](R6/failure-attribution-index.json), and [source bindings](source-bindings.json). Original reports/logs are retained byte for byte; [origins](origins.json) records their temporary source paths. Absolute process paths inside raw reports are historical.

| Gate | Actual result | Receipt |
| --- | --- | --- |
| Complete script parse | 1,374 passed, zero failed | [parse](R2-parse/result.json) |
| All unit scripts | 734 passed, 17 failed; exact 751-file coverage | [units](R6/unit-coverage.json) |
| Original offline and early integration gates | Passed through H7, invalid-field startup, and aircraft model checks; stopped at F4U byte freshness | [R6 integration](R6/integration/result.json) |
| F4U and trace acceptance continuation | F4U checks and all 19 trace-acceptance tests passed; stopped at synthetic candidate byte freshness | [R7](R7/result.json) |
| Remaining original integration commands | Exit 0; 19 positive checked invocations and seven separately validated expected failures | [R8](R8/result.json) |

## Unresolved failures

Eight companion scripts refuse admission through stale aircraft/solver qualification pins. The existing GP-10 baseline reproduces the profile gate; seven downstream companion suites were not independently replayed. No qualification rebind was performed.

The other nine failed scripts were independently replayed on a copied GP-10 app with all 1,354 baseline GDScripts byte-identical, using the same neutral import metadata repairs. Their failure messages match: aircraft paint reachability, player-widget defaults, training-widget layout, helicopter Flight-page fit, Help focus/null-node timeout, Home layout, language-history strings, presentation smoke-profile migration, and the lake bake source stamp. The lake's fresh procedural basin/water arrays still match the packaged arrays byte for byte. Every failed script remains a failure; see the [per-script attribution](R6/failure-attribution-index.json).

The two original physical exceptions (`test_rudder_authority.gd` and `test_yaw_damping.gd`) retain their original explicit pending flags. Headless software checks do not establish physical validation, rendered visual acceptance, or CPU/GPU performance qualification. The 720p fixtures do not qualify the product's primary 1080p target; inherited 1080p UI failures are also retained.

## Isolated repairs and source identity

The original cold import timeout and every stopped attempt remain recorded. Repairs changed no physical coefficients and re-recorded no flight goldens:

- [R1](R1/source-before.json): route two dormant helper math paths through the existing float64 math wrapper.
- [R2](R2/parameter-register.json): classify the original 18 ground quantity consumers; generate the register against the frozen schema.
- [R3](R3/parse-reuse.json) and [R4](R4/pin-propagation.json): update only model/Workshop/customization source hash strings.
- [R5](R5/eol-normalization.json): canonical LF for the audio resource, preserving UID and every setting.
- [R6](R6/population-normalization.json): update 13 population import byte/hash records; geometry, textures and authored import values are unchanged.
- [R7](R7/normalization.json): canonical LF for three outside-app F4U authoring JSONs; generated geometry is unchanged.
- [R8](R8/normalization.json): canonical LF for five outside-app synthetic candidate JSONs; no candidate was regenerated and all coefficients are unchanged.

The [final source receipt](R8/source-after.json) verifies 170 selected paths. All 4,034 authored app/dependency files match their frozen before/after hashes. Godot caches, capture outputs and generated Python bytecode are excluded. The full app/assets checkout is deliberately absent; the base commit, existing frozen manifests, small overlay snapshots and source hashes define the cohort.

## Verification and reproduction

Use the pinned `4.8.beta1.official.4d10419ca` engine and the existing repository tools. Reconstruct a disposable checkout from the base and apply the overlay order in [source bindings](source-bindings.json). Import once. The retained shell files preserve the exact historical commands and local absolute `HERE`; adjust only that path and output/profile environment variables when replaying elsewhere.

```sh
python tools/godot/summarize.py docs/research/ground-physics/GP-11/broad-suite/R2-parse/positive
python tools/godot/summarize.py docs/research/ground-physics/GP-11/broad-suite/R6/units/positive
python tools/godot/summarize.py docs/research/ground-physics/GP-11/broad-suite/R6/remaining-units/positive
python tools/godot/summarize.py docs/research/ground-physics/GP-11/broad-suite/R8/positive
```

The two unit summaries intentionally return nonzero. Expected CLI failures are kept in a disjoint collection and were validated by the original `check_expected_cli_failure.py` contract. [Manifest](manifest.json) binds every payload. The [byte-preservation roundtrip receipt](attribute-roundtrip.json) records a disposable `core.autocrlf=true` commit/fresh clone; no actual-repository staging or commits were performed.
