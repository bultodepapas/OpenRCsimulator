# PT1 — rc9 candidate verification

2026-10-13 (America/Bogota). Status: preparation in progress; not qualified or published.

## Frozen scope

The local Linux preflight starts from `5a1fe87bd8b1b201274df3e3cc362a11a3fd842a`, with only the release fixes described below overlaid. The shared Windows checkout continues to change. Subsequent commits and uncommitted work are not automatically covered by these results. [Release notes](../../../releases/v0.1.0-rc9.md) describe the proposed integration scope.

The isolated checkout is `/home/bulto/openrc-rc9-check` in WSL Ubuntu, created with `core.autocrlf=false`; repository attributes still control explicitly pinned files. Engine: official pinned Godot `4.7.2.stable.ed1daf0bf`. Schema dependencies use `research/aircraft-data/schema/requirements.txt` in a separate virtual environment.

## Release repairs

- The schema/loader agreement runner still expected eight aircraft JSON files. The candidate has thirteen: four original aircraft, four synthetic electric fixtures, four glow installations and Turbo Lumber. The explicit inventory now covers all thirteen; the existing negative cases and loader refusal checks remain enabled. This fixes the failure in [CI 38488470601](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38488470601).
- The generated-model and Workshop checkout regressions invoked a literal `python` command, absent in this Linux environment. They now use `sys.executable`, preserving the active interpreter and environment. All fourteen model tests and the LF/CRLF checkout regression pass.
- Timber's source manifest depended on platform-specific `Path` ordering. Its generator now sorts relative path components explicitly, matching the frozen Windows ordering on both platforms. All 144 delivery files (19,438,463 bytes), hashes and the visual revision `r2-d75ae605aa3a` were already identical; the manifest and delivery were not rewritten.
- Python 3.12's changed floating-point `sum()` caused four last-bit differences in Timber's generated balance/CG data. Three generator reductions now accumulate explicitly from left to right, preserving the checked-in physical values across Python versions. The physics data and sensitivity outputs were not rewritten. Five authoring tests, sensitivity freshness and Windows/Linux generation checks pass.

## Checks

| Check | Result |
| --- | --- |
| Aircraft structural preflight | 13 files, zero failures |
| Schema/loader contract | 1,991 cases; four tests pass; 147 valid controls and 21 runtime-only checks |
| V2 agreement after inventory repair | 67 cases, zero failures; 13 positive fleet entries, 65 schema/loader agreements and two runtime-only coupled cases |
| Offline tools (`research/test-tools.sh`) | Pass |
| Generated model regression | 14 tests pass after interpreter repair |
| Workshop checkout bindings | LF and CRLF disposable checkouts pass after interpreter repair |
| Full app suite | In progress; initial attempt stopped at the missing `python` executable |
| CI geometry/physics generators | All twelve commands pass after the Timber reproducibility repairs |
| Timber authoring | Five tests and sensitivity freshness pass; Windows and Linux preserve existing generated data |
| Rendered captures, exports and downloaded packages | Not yet qualified |

Logs: [schema/loader](schema.log), [CI generators](generators.log), [offline tools](offline-tools.log), [models](models.log), [LF/CRLF checkouts](checkout.log), [Timber authoring](timber.log).

No physics tolerances, golden flights or rejection gates were relaxed. Software verification does not close native GUI, physical-radio, target-GPU, pilot or physical-model acceptance.
