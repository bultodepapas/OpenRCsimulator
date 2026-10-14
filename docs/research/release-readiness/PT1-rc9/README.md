# PT1 — rc9 candidate verification

2026-10-13 (America/Bogota). Status: draft candidate; publication blocked by the existing readability gates. Not qualified or published.

## Frozen scope

The local Linux preflight starts from `5a1fe87bd8b1b201274df3e3cc362a11a3fd842a`, with the release fixes described below overlaid. It additionally takes the imported-model contract and Timber compatibility facade from `69437cc4`, their generated model/Workshop bindings, the imported-model regression from that commit, and the manifest regression correction from `7265b2e0`. Other changes in those commits are outside this candidate. The shared Windows checkout continues to change; subsequent commits and uncommitted work are not automatically covered by these results. [Release notes](../../../releases/v0.1.0-rc9.md) describe the proposed integration scope.

The isolated checkout is `/home/bulto/openrc-rc9-check` in WSL Ubuntu, created with `core.autocrlf=false`; repository attributes still control explicitly pinned files. Engine: official pinned Godot `4.7.2.stable.ed1daf0bf`. Schema dependencies use `research/aircraft-data/schema/requirements.txt` in a separate virtual environment.

## Release repairs

- The schema/loader agreement runner still expected eight aircraft JSON files. The candidate has thirteen: four original aircraft, four synthetic electric fixtures, four glow installations and Turbo Lumber. The explicit inventory now covers all thirteen; the existing negative cases and loader refusal checks remain enabled. This fixes the failure in [CI 38488470601](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38488470601).
- The generated-model and Workshop checkout regressions invoked a literal `python` command, absent in this Linux environment. They now use `sys.executable`, preserving the active interpreter and environment. All fourteen model tests and the LF/CRLF checkout regression pass.
- Timber's source manifest depended on platform-specific `Path` ordering. Its generator now sorts relative path components explicitly, matching the frozen Windows ordering on both platforms. All 144 delivery files (19,438,463 bytes), hashes and the visual revision `r2-d75ae605aa3a` were already identical; the manifest and delivery were not rewritten.
- Python 3.12's changed floating-point `sum()` caused four last-bit differences in Timber's generated balance/CG data. Three generator reductions now accumulate explicitly from left to right, preserving the checked-in physical values across Python versions. The physics data and sensitivity outputs were not rewritten. Five authoring tests, sensitivity freshness and Windows/Linux generation checks pass.
- The catalog exposed the existing imported-model version guard rejecting JSON's numeric `1` because it required `TYPE_INT`. The model owner's accepted contract/facade repairs from `69437cc4` restore Timber construction and metrology compatibility; dependent manifests were regenerated through their builders. The added regression's expected tail-wheel wrapper was corrected to the existing `tailwheel_spin` name. Catalog: 88 checks pass; imported model: 68 checks pass. The manifest negative control now rejects unsupported version 3, since version 2 is supported (`7265b2e0`).
- The crash-energy fleet test now explicitly expects `glow_fuel` for all four finite-glow data files instead of treating them as synthetic electric donors. All 46 checks pass.
- Help now lists the F6–F9 glow controls in English and Spanish. Combining the related restart/failsafe-resume shortcuts in one row preserves the layout: both languages fit in 594 of 600 available pixels at 720p. Controls-reference and Help flow tests pass without reducing fonts or layout assertions.
- The seven-aircraft crash integration passes all 133 checks in 82.90 s; wreck lifecycle checks pass 219 checks in 65.46 s. These two tests receive bounded 180-second deadlines instead of 60 seconds. Crash pose passes 149 checks in 46.54 s with its existing deadline. These are test-workload timings, not target-hardware physics benchmarks.

## Checks

| Check | Result |
| --- | --- |
| Aircraft structural preflight | 13 files, zero failures |
| Schema/loader contract | 1,991 cases; four tests pass; 147 valid controls and 21 runtime-only checks |
| V2 agreement after inventory repair | 67 cases, zero failures; 13 positive fleet entries, 65 schema/loader agreements and two runtime-only coupled cases |
| Offline tools (`research/test-tools.sh`) | Pass |
| Generated model regression | 14 tests pass after interpreter repair |
| Workshop checkout bindings | LF and CRLF disposable checkouts pass after interpreter repair |
| Full app suite | All-script parse passes; behavior checks in progress after the documented runner/model repairs |
| CI geometry/physics generators | All twelve commands pass after the Timber reproducibility repairs |
| Timber authoring | Five tests and sensitivity freshness pass; Windows and Linux preserve existing generated data |
| Rendered captures | Existing readability assertions fail; the full capture sequence stops at that gate |
| Exports and downloaded packages | Not qualified; no release tag or publication created |

Logs: [schema/loader](schema.log), [CI generators](generators.log), [offline tools](offline-tools.log), [models](models.log), [LF/CRLF checkouts](checkout.log), [Timber authoring](timber.log).

No physics tolerances, golden flights or rejection gates were relaxed. Software verification does not close native GUI, physical-radio, target-GPU, pilot or physical-model acceptance.

## Publication blocker: readability

The unchanged `app/capture.sh` producer reached its L0c/L1b readability check and exited with failure. Recomputing the same checker over the saved images reproduces both failures:

| Capture | Observed | Existing requirement |
| --- | --- | --- |
| [3 m view](capture-land-low3m.png) | 24.0% nearly invisible airplane pixels | At most 15% |
| [30 m view](capture-land-30m.png) | Weber contrast −0.279 | At most −0.40 |

The 3 m view's overall contrast (−0.416), both color-distance checks and background saturation checks pass. The two failed measures still block publication; neither thresholds nor reference images were changed. [Checker output](readability.log), capture metadata ([3 m](capture-land-low3m.json), [30 m](capture-land-30m.json)) and paired backgrounds ([3 m](capture-land-low3m-noplane.png), [30 m](capture-land-30m-noplane.png)) retain the observations. These are fixed automated views, not a pilot trial.

Resolve the visual regression against the existing gates, then complete the full app/capture sequence on one frozen commit, export all three platforms and verify package checksums/identity before creating the release tag. Later VQ/treeline/scenario capture stages did not run after the failing gate. The current main branch continues to change and must not inherit this candidate's results automatically.
