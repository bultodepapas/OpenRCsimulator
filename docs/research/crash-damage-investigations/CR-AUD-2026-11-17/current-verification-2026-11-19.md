# Current-main collision audit: verification record

**Date:** 19 November 2026, America/Bogota.

**Report:** [current review](current-review-2026-11-19.md).

**Machine-readable evidence:** [round-five manifest](evidence/round5/manifest.json).

## Identity and method

| Item | Recorded identity |
|---|---|
| Application source | `372053ac9448942e154801e3299cf77669161d08`, a separate detached main checkout |
| Existing audit branch | `audit/collision-damage-2026-11-17`, parent `6029eb63d021d70096c89b7a8adc2d4ef6d02efb` |
| Historical application baseline | `a7de9b35676d891bc2034cc344b910d9e1ef9c61` |
| Engine | Pinned Linux x86_64 `4.8.beta2.official.cafc17a19`, downloaded by the repository's `app/get-godot.sh` |
| Runner | Current source `tools/godot/run_checked.py`; completion markers, exit, bounded logs, errors and warnings inspected |
| Project | Isolated exact-source component fixture, 240 Hz, maximum 12 catch-up steps, jitter fix 0, Compatibility renderer |
| Scope of runtime evidence | Selected component/session checks; not a production application launch or platform release campaign |

Engine SHA-512:

```text
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

The installed system engine was not substituted. A local test-pool discovery attempt found no configured `/tmp/OpenRC/testpool/config.json`, and no callable pool service was exposed. The existing checked local runner was used. The engine ran with a dummy audio driver and isolated data/config/cache profiles for each job. No sound quality, screenshot, hardware frame time or native-backend parity claim follows.

The fixture copies application scripts, accepted data and required resources without modifying the production files. It omits production autoloads, UI launch, native package receipts and unrelated assets. The final [source manifest](evidence/round5/source-manifest.json) lists **1,678 exact source/resource copies**, SHA-256 hashes and the complete minimal project settings. All 1,678 source copies were independently hash-checked before delivery. The portable runner also verifies non-`.import` fixture files; editor-generated import descriptors/cache are allowed to change.

That final manifest is a reproducible resource superset, not a claim that every early run already had every resource. Hydration progressed during preparation: parked-aircraft metadata was added before its successful rerun, and paint textures were added before the successful helicopter delayed-frame rerun. The earlier incomplete attempts remain retained. Core scripts and accepted input data used by the qualifying checks were not patched. The missing optional generated-package paths in the manifest are disclosed rather than fabricated.

The [static comparison](evidence/round5/source-status.json) records all 27 historical findings and 31 unique source paths. The lead independently checked all baseline/current Git blob pairs. Its per-record runtime flags describe the earlier static-review phase only; the execution manifest and this document provide the subsequent current runtime evidence.

## Final selected results

| Category | Executions | Checks | Passing assertions | Desired-behavior failures | Checked engine errors / warnings |
|---|---:|---:|---:|---:|---:|
| Focused audit probes | 23 | 484 | 428 | 56 | 0 / 0 |
| Existing control suites | 3 | 122 | 122 | 0 | 0 / 0 |
| **Qualifying selected total** | **26** | **606** | **550** | **56** | **0 / 0** |

These are selected checks designed to investigate specific boundaries. Their pass fraction is not a product-quality score. Several assertions are correlated or verify fixture admission, controls and provenance. One finding can have many failed assertions; one passing observation probe can establish a missing capability. Desired failures preserve nonzero exits and are not converted to passes. This is not a green full-suite or CI claim.

| Probe / suite | Checks | Desired failures | Meaning of the result |
|---|---:|---:|---|
| `prop-source-off` | 23 | 1 | Coasting source-off prop misses the ground-strike guard; spinning/stopped controls retained |
| `staggered-crossing` | 7 | 1 | Selected point and flattened crossing fraction refer to different probes |
| `wreck-adversarial` | 18 | 12 | Prescribed property/callback/update fixtures for datum, COM, split, membership, scenery and time |
| `lake-session` | 13 | 0 | Observation assertions confirm quad/blimp lake omission and controls; not a lake-support pass |
| `heli-soft-contact` | 8 | 0 | Observation assertions confirm discarded nonterminal scenery candidate and viable response control |
| `scenario-fuel` | 61 | 1 | All 11 fixed-wing data routes admitted; one report-versus-internal-effect duration mismatch |
| `ground-scenery` | 19 | 0 | Both cars lack tested general scenery in their road context; injected-box positive controls respond |
| `engine-com` | 1 | 0 | Small engine COM convention control |
| `heli-delayed-frames` | 90 | 16 | Prescribed moving core/release frames, main and tail blades; clean hydrated rerun |
| `quad-crash-checkpoint` | 15 | 2 | Accepted crash observer and restored boundary consistency |
| `contact-order` | 11 | 1 | Accepted mixed ground/scenery ordering with matched isolated and smaller-step controls |
| `crash-pause-log` | 15 | 3 | Accepted contact and real persisted pause metadata |
| `quad-obstacle-aftermath` | 32 | 1 | Terminal accepted obstacle state and continued aftermath boundary |
| `quad-prop-strike-energy` | 16 | 1 | Controlled rotor/contact energy and accepted-tick evidence; retain original scope |
| `airship-collision-recording` | 29 | 2 | World mutation/identity and three real recording controls |
| `slow-capsule-entry` | 12 | 2 | Direct and accepted slow hard-capsule entry, with faster/clear controls |
| `prop-bank-rim` | 16 | 1 | Powered prop rim witness on a dry bank; bounded tiny penetration, not fleet-wide prop CCD |
| `quad-disc-box-separation` | 29 | 2 | Finite-disc/box separation and contact masking |
| `car-damage-region` | 22 | 4 | Accepted front-only contacts with opposite lateral drifts in both cars |
| `fixedwing-gear-scenery` | 14 | 1 | Deployed-wheel-only obstacle capability gap with accepted hull-contact control |
| `slope-severity` | 8 | 3 | New CR-AUD-28: prescribed valid snapshots through real director, independent normal/effective-mass oracle |
| `quad-severity` | 16 | 1 | New CR-AUD-29: two accepted terminal runs and two nonintegrated controls; only the direct monotonicity assertion fails |
| `person-attribution` | 9 | 1 | New CR-AUD-30: prescribed ground-crash presentation with separated spectator and near/far controls |
| `test_crash_severity` | 44 | 0 | Existing estimator control |
| `test_parked_aircraft_collision` | 45 | 0 | Existing suite confirms CR-AUD-15 repaired; correct shelter counts and clearance |
| `test_heli_crash_visual` | 33 | 0 | Existing headless visual-structure control; not a rendered image review |

The old 17–18 November execution totals are historical and are not added to these numbers. CR-AUD-11's current disposition also uses source inspection; this campaign does not supply a new end-to-end ground-first wreck/scenery trajectory.

### New probes and exact evidence

| Finding | Frozen executed source | Raw current log |
|---|---|---|
| CR-AUD-28 | [Slope probe](evidence/round5/probes/probe_slope_severity.gd) | [Eight-check result](evidence/round5/runs/core-current/slope-severity/slope-severity-8sksyg4x/engine.log) |
| CR-AUD-29 | [Quad probe](evidence/round5/probes/probe_quad_severity.gd) | [Accepted and direct cases](evidence/round5/runs/current-contact/quad-severity/quad-severity-kqr0i6ev/engine.log) |
| CR-AUD-30 | [Person-attribution probe](evidence/round5/probes/probe_person_attribution.gd) | [Near/far and overlap cases](evidence/round5/runs/core-current/person-attribution/person-attribution-ng23pmut/engine.log) |

The manifest records every script hash and exact relative report/log path. The three new sources are frozen byte-for-byte from their checked runs; historical “draft” or “not yet executed” comments are intentionally not rewritten after execution. This verification record establishes their final execution status.

CR-AUD-28's prescribed slope case is **not** a stock-track producer reproduction. CR-AUD-29's accepted runs use real stock session transitions from admitted prescribed frames, but the reported incoming values are previous-boundary candidate-point maxima, not exact contact-time speeds. The two accepted emitted powers differ; only the direct controls both equal zero. CR-AUD-30 reaches the real detached presentation route with a supplied crash dictionary; it does not integrate a helicopter trajectory.

### Real recording evidence

The retained recordings are generated by the production logger/recorder paths used in their probes:

- [Fixed-wing crash/pause recording](evidence/round5/runs/current-edge-cases/crash-pause-log/recording/fixedwing-crash-pause.orfl).
- Airship [unchanged world](evidence/round5/runs/current-edge-cases/airship-collision-recording/recording/unchanged-world.orfl), [world installed before recording](evidence/round5/runs/current-edge-cases/airship-collision-recording/recording/pre-record-world.orfl), and [changed world during recording](evidence/round5/runs/current-edge-cases/airship-collision-recording/recording/changed-world.orfl).

Their retained logs distinguish the valid controls from the failing contract; file existence is not itself a correctness claim.

## Excluded attempts and preparation

All six excluded script attempts are present in the manifest and raw runs. They are not included in the 606-check total or the 56 desired-behavior failures.

| Attempt | Observed result | Disposition |
|---|---|---|
| First parked-aircraft run | 15 checks, nine failures; dynamically loaded aircraft metadata omitted from fixture | Fixture preparation error. Metadata hydrated; clean 45-check run is authoritative. |
| First delayed-helicopter run | 90 checks, 16 desired failures, four missing paint-texture errors | Nonqualifying execution. Clean rerun preserves 90/16 with zero diagnostics. |
| Stock-slope producer draft, first revision | GDScript cannot infer `half_drop`; two checked engine errors | Scratch probe error. [Exact failed source](evidence/round5/attempts/probe_stock_slope_producer_parse_error.gd) retained; explicit float type used in later attempt. |
| Stock-slope producer, corrected revision | Five assertions, one fixture failure, zero diagnostics; all five stock-site queries refused | [Inconclusive source](evidence/round5/attempts/probe_stock_slope_producer.gd). No contact snapshot produced; no claimed stock-slope reproduction or new product bug. |
| Existing `test_crash_wreck` | Process exit zero, 30 asserted passes, **22 engine errors** from incomplete dynamic model-contract resources | Not a passing suite. Full fleet mesh/wreck integration remains unqualified in this fixture. |
| Existing `test_crash_wreck_surface` | Model-contract errors before intended slide/rebound execution; no completion marker; killed at 90 s | Inconclusive environment attempt. No friction, bounce, sleep or frame-time result is claimed. |

Preparation also retains four editor-import reports. The first import failed on an omitted GLB external texture dependency (one error, one warning); later dependency, metadata and paint imports completed cleanly. Import failures are setup evidence, not simulation defects. The final fixture is still intentionally a component project, so successful import does not imply complete production model-contract hydration.

The portable launcher's additional one-check `engine-com` smoke run is verification of the delivered reproduction tooling and is kept separately; it is not double-counted in the selected physics totals.

## Reproduction

Use two checkouts: this audit branch for retained probes, and a hydrated application checkout at the recorded main SHA. Do not run against the application code still on the older audit branch and call that a current-main reproduction. The portable scripts enforce the source commit, engine hash and fixture contents. They use argument arrays rather than shell interpolation for process execution.

Set paths for your local machine; the fixture and output directories must be fresh:

```bash
AUDIT_REPO=/path/to/audit-checkout
SOURCE_REPO=/path/to/main-at-372053ac
FIXTURE_ROOT=/path/to/new-collision-fixture
RUN_ROOT=/path/to/new-collision-results
GODOT_BIN=/path/to/Godot_v4.8-beta2_linux.x86_64
EVIDENCE_HOME="$AUDIT_REPO/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round5"

python3 "$EVIDENCE_HOME/build_fixture.py" --source-repo "$SOURCE_REPO" --out "$FIXTURE_ROOT"
python3 "$SOURCE_REPO/tools/godot/run_checked.py" --label collision-import --timeout 180 \
  --out-dir "$RUN_ROOT/import" -- "$GODOT_BIN" --headless --editor \
  --path "$FIXTURE_ROOT/app" --audio-driver Dummy --import

python3 "$EVIDENCE_HOME/run_probes.py" --list
python3 "$EVIDENCE_HOME/run_probes.py" \
  --source-repo "$SOURCE_REPO" --project "$FIXTURE_ROOT/app" \
  --engine "$GODOT_BIN" --out "$RUN_ROOT/new-findings" \
  slope-severity quad-severity person-attribution
```

The three new probes are expected to retain their desired-behavior failures at this revision. Use a new output directory for each rerun. Omitting probe names runs the 23 audit probes and three successful existing controls; the inconclusive stock-slope attempt requires its explicit name and is not included by default. The two incomplete broader wreck suites are intentionally not advertised as supported fixture reproductions.

The build helper's `--check-source` validated all 1,678 recorded source hashes; `--list` and one real `engine-com` run verified the portable runner. Full reexecution after publishing is not claimed. Future fixes should bring relevant desired checks into the normal test suite with updated source identity and realistic acceptance bounds; this historical launcher intentionally pins its original evidence.

## Qualification boundaries

No authoritative application code changed. No full-app or rendered crash session, physical material-strength validation, human-injury model, native/reference parity, hardware CPU/GPU benchmark, all-fleet impact matrix or newly implemented moving-aircraft collision is claimed. The user-observed play session was not available for exact reproduction. The report uses the executed counterexamples and current source to explain plausible mechanisms and define repair/qualification work.

Exit zero alone did not qualify a run: the existing wreck suite demonstrates why. Desired failures were not hidden, setup errors were not relabeled as product defects, and a bounded search that found no stock slope witness remained inconclusive.
