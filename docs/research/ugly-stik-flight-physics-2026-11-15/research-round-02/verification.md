# Verification of research round 02

## Identity and scope

The plan was published as `973ac3b42708102a6ebc95b64b3e42e688aae573` before external research. Tests below ran on the subsequent **working-tree candidate**; the recorded HEAD is the plan commit, not a claim that HEAD alone contained the tested changes. [Compatibility and identities](evidence/compatibility-and-identities.json) contains the exact SHA-256 of all four tool sources and three test files. The four tool hashes match the [independent implementation review](implementation-review.md). Publication must preserve those bytes.

The application tree is unchanged at `565e4a839e63c1b65064d0da4e6e1366b13ebbc7` and there is no `app/` working-tree diff. The selected runtime code derives from the original `ad21070798bfb9658785576a9c0b8bfc9a71fc7f` baseline; earlier audit reports are dated evidence, not assertions about every later main-branch change. This round modifies research/report tools and documentation, not the flight kernel, aircraft data, input policy or rendering fixture.

The publication preflight observed `main` at `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc` and the audit branch at the plan commit. The research is deliberately pinned to its stated audit baseline; it is not a claim that main's entire application tree is identical.

Execution used Python **3.12.14**, NumPy **2.3.5**, Pillow **13.0.0** in the available Linux analysis runtime. No dependency was added to the repository. The report tests use those actual libraries, not a mock image-diff operation; they do not establish qualification under every supported visual environment.

## Executed checks

| Check | Actual result | Retained evidence | Meaning |
| --- | --- | --- | --- |
| Runner and comparator unit/CLI contracts | **36 tests passed** | [Log](evidence/flight-tools.log), [execution receipt](evidence/flight-tools.json) | Includes prior 14 runner regressions, new failure capture, catalog discovery, profile/receipt identities, coverage and comparison contracts. |
| Scenery report contracts | **12 tests passed** | [Log](evidence/scenery-report.log), [execution receipt](evidence/scenery-report.json) | Uses tiny temporary PNGs and synthetic states; exercises actual byte hashing, image loading/difference/heatmap output and HTML/history behavior. |
| Original failure observer rerun unchanged | Four wrapper and five comparison outcomes retained | [Observer log](evidence/before-after-observer.log), [receipt](evidence/before-after-observer.json), [raw results](evidence/tool-evidence-after.json) | Shows the old counterexamples against the changed tools; the observer itself does not assert a new expected outcome. |
| Generic structure compatibility | **18/18 original audit profiles accepted; 820 table rows** | [Profile identities/results](evidence/compatibility-and-identities.json) | A bounded sample of retained evidence, including scientifically invalid/unavailable results; not a physical-validity gate. |
| Static fleet exact self-comparison | Exit **0** at zero tolerance | [Report](evidence/fleet-static-self-comparison.md) | Same retained profiles and successful receipts compared with themselves. |
| Dynamic campaign exact self-comparison | Exit **0** at zero tolerance | [Report](evidence/dynamic-self-comparison.md) | Preserves the intended comparison workflow on that retained campaign. |
| Finite-pack Electric exact self-comparison | Exit **0** at zero tolerance | [Report](evidence/electric-pack-self-comparison.md) | Retains source-specific evidence; not a new electric flight. |
| Independent review/source identity | Four tool hashes match | [Review](implementation-review.md), [identity record](evidence/compatibility-and-identities.json) | Reviewer exercised separate synthetic counterexamples and reviewed the focused changes. |
| Research index/schema/local links | No errors found | [Document check](evidence/document-check.json) | All 24 first-round and two follow-up reports, five source registers and the final index are included; scientific correctness is not inferred from link consistency. |

No benchmark timing in these test logs is a product performance result.

## Before and after the retained counterexamples

The old [follow-up evidence](../follow-up-01/evidence/tool-evidence.json) remains unchanged. The rerun uses the same observer source against the candidate tools:

| Case | Earlier outcome | Candidate outcome |
| --- | --- | --- |
| Complete synthetic control | Exit 0, manifest and summary | Exit 0, manifest and summary retained |
| Actual Python timeout child with stdout/stderr | Exit 1 but captured diagnostics lost from the log | Exit 1; both separately captured streams retained; timeout/capture status recorded |
| Malformed profile JSON | Uncaught exception before log/manifest | Exit 1; raw child log, per-job receipt and aggregate manifest retained; actual child exit preserved |
| Missing results container | Uncaught exception before manifest | Exit 1; profile error recorded and manifest retained |
| Empty comparison directories | Exit 0, zero changes | Exit 2, no shared aircraft evidence |
| Disjoint `--shared-tests` | Exit 0, zero changes | Exit 2, no shared test coverage |
| Duplicate case hides an earlier changed row | Exit 0 | Exit 2, ambiguous case identity |
| Candidate-only aircraft | Ignored, exit 0 | Reported addition, exit 1 with `--fail-on-change` |
| Ordinary numeric-change control | Exit 1 | Exit 1 retained |

The new runner tests additionally prove the narrower good-peer case: a profile rejected by the input validation boundary does not erase the other aircraft's receipt or summary. An error later inside the aggregate summary reducer instead retains all receipts, records `summary_error`, returns failure and withholds the whole partial summary. This limitation is explicitly reproduced/discussed by the reviewer; no promise is made that every successful peer receives a summary under every reducer error.

The historical runway observer was **not rewritten into a pass**: it encodes the old metadata-only behavior and creates no actual image bytes. New acceptance tests intentionally verify actual PNG bytes and new verdicts. Missing/empty/partial/duplicate/nonboolean/malformed sync receipts are UNKNOWN. New zero-observation checks are UNKNOWN; an observed failed sync check takes precedence. A complete legacy receipt without observation counts retains its declared outcome, visibly marked as observation coverage unverified. Equal source IDs or two missing hashes do not prove accepted-input identity.

## Reproduction

From the repository root, with Python 3.12 and the documented NumPy/Pillow environment for the scenery report:

```bash
python -m unittest discover -s research/flight-test -p 'test_*.py' -v
python -m unittest discover -s tools/scenery -p 'test_scenario_report.py' -v
python research/ugly-stik-audit-2026-11-15/follow-up-01/tool_evidence_probe.py --out tmp/round02-new-tool-evidence.json
python research/flight-test/compare.py docs/research/ugly-stik-flight-physics-2026-11-15/evidence/fleet-static docs/research/ugly-stik-flight-physics-2026-11-15/evidence/fleet-static --rel 0 --abs 0 --fail-on-change
```

Use a fresh output path for a new observer run; retained evidence here is historical. Unit fixtures live in separate temporary directories under the repository's ignored `tmp/` and do not change user profiles or aircraft data. The timeout check executes a real short-lived Python child; all other runner child outcomes are substituted. Source structure validation uses `profile_io.read_profile` against the 18 recorded paths listed in the compatibility receipt.

## Research verification and remaining gates

The [research review](research-review.md) checked source IDs/links and challenged substantive claims. Its fixes include qualifying real/complex modal periods and correctly identifying the NASA Harrier example. The exact pinned Godot/SDL files were inspected through GitHub after public-page retrieval failed; the source register retains blob identities and distinguishes source metadata from a measured binary version. S2-02's arithmetic is synthetic algebra, not simulator acceptance. Five registers contain 107 unique source IDs and 105 distinct URLs; each investigation cites its applicable records and limits.

The completed tests do **not** qualify native capture, actual controllers, a new renderer/engine combination, target-hardware frame pacing, physical aircraft behavior, complete flight-card horizon semantics or the full product lifecycle. In particular, producer-side accepted source hashes, expected capture schedule completion, the Electric statistics adapter/lifecycle and runtime input/physics proposals remain in the [integration backlog](integration-backlog.md). No measured speedup, real-flight coefficient, new physical maximum speed or pilot-rated feel improvement is claimed by this round.
