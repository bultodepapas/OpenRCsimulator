# Third-investigation verification and reproduction

**Date:** 18 November 2026, America/Bogota.
**Scope:** evidence for [CR-AUD-21 through CR-AUD-24](edge-cases-2026-11-18.md), not a repeat of the first or second suite campaign.

## Source and execution identity

| Item | Value |
|---|---|
| Application baseline | `a7de9b35676d891bc2034cc344b910d9e1ef9c61` |
| Starting audit commit | `82e715cbe9c8254888c3bc1f7edad739ba4355c9` |
| Branch | `audit/collision-damage-2026-11-17` |
| Application tree | `f72e113b9f0cc068579c6c5d7cf5a216a3e67fac` |
| Asset tree | `3ed558d2a5f37ae24e784436c9def5841d7382ad` |
| Tools tree | `95d35ed671a2a32919ffadc13036c66e240ab2ec` |
| Engine | `4.8.beta2.official.cafc17a19`, Linux x86_64 |
| Runner | `tools/godot/run_checked.py`, headless, Dummy audio |
| Isolation | Sequential engine processes; separate XDG config/data/cache directories |
| Imported resources | Retained from the second investigation; no new import campaign |

The pinned executable's SHA-512 was rechecked:

```text
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

The [setup record](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/setup.json) records the source and local availability checks. Graph and `sim_test` MCP facilities were not available, and `/tmp/OpenRC/testpool/config.json` was absent. The existing local checked-runner route was used with one engine job at a time. No external shared-host session was assumed. Helpers supplied bounded drafts and source review; the lead inspected the drafts, ran every engine job, reviewed the measurements and integrated the documents. Requested helper model settings are not evidence of an independently observed runtime configuration.

The [provenance record](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/provenance.json) and [manifest](evidence/round3/manifest.json) identify exact retained files and hashes. Raw checked reports preserve their original temporary command/log paths. The durable evidence copies keep those bytes unchanged; the manifest supplies their delivered locations. This intentional path difference does not mean the final evidence was regenerated.

## Final product probes

| Probe | Checks | Pass | Desired failures | Checked errors/warnings | Result |
|---|---:|---:|---:|---:|---|
| [Quad prop-strike energy](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/probes/quad-prop-strike-energy/report.json) | 16 | 15 | 1 | 0 / 0 | Positive coupled energy change in one prescribed tangent direction |
| [Airship collision recording](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/probes/airship-collision-recording/report.json) | 29 | 27 | 2 | 0 / 0 | Changed world accepted without recording boundary; complete file fails exact terminal replay |
| [Slow hard-capsule entry](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/probes/slow-capsule-entry/report.json) | 12 | 10 | 2 | 0 / 0 | Direct and accepted-tick slow entry missed; subsequent reference trajectory crosses the trunk |
| [Propeller bank rim](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/probes/prop-bank-rim/report.json) | 16 | 15 | 1 | 0 / 0 | Positive dry-bank disc witness while the selected point reports clear and no strike is latched |
| **Total** | **73** | **67** | **6** | **0 / 0** | **Four scoped findings** |

All four final jobs completed, produced their required completion markers and returned nonzero because their desired-behavior assertions failed. They are not green tests. The engine/parser diagnostic counts are independent of these assertions. Some logs contain ordinary aircraft-data notices; zero checked warnings does not mean every log is devoid of text containing “warning.”

No existing broad suite was re-run merely to increase the count. The first investigation's 53-suite result and the second investigation's five probes/163 checks plus the 33-check helicopter control remain separately dated evidence. They are not added to this pass's 73 checks.

### What each probe actually executes

**Quad energy.** The real stock quad prepares; five prescribed frames satisfy the model validator and reset-frame preparation. The probe calls `_graded_impacts` directly with the same previous/current body. No reset candidate is committed and no integration tick is accepted in this probe. It includes the locked-inertia body energy, relative rotor energy and body–shaft cross term. It checks one selected prop disc against a synthetic stationary plane, normal bounce, input-state validity and stopped/no-wall controls. It does not measure real material energy or flight frequency.

**Airship recording.** Real stock field geometry, real session ticks and real production `.orfl` writing, inspection and verification are used. The release deliberately overlaps a stock flagpole when that world is enabled. Three retained files distinguish unchanged-world behavior, a world installed before recording, and an accepted paused change during recording. The current activity's world installation remains a startup path; no UI switch was exercised.

**Hard capsule.** Real fixed-wing reference integration and accepted session publication are used, with a single datum probe and a production trunk capsule. The body-only fixture suppresses aero, gravity, gear, prop and foliage to isolate the swept geometry. A finite force begins only after the first accepted tick. Full 120-tick body/mode/contact histories are recorded and compared, rather than inspecting only the final contact field. The initial 0.1 µm clearance and 0.1 mm/s speed are extreme and intentional.

**Bank rim.** The stock default fixed-wing model, authored lake, existing split shaft route, ordinary stage loads and normal soft-contact owner guard execute. Only the start pose/position/velocity and soft-contact mode are prescribed. The final script records yaw/pitch/roll accurately. The same named disc-model witness crosses from sampled clearance to penetration at accepted tick 2. Positive finite sampling proves overlap; it does not prove global initial clearance, a maximum over the continuous disc, or material blade phase. Flat and deeper-bank controls detect and cut the engine.

## Earlier attempts kept outside the final totals

| Retained attempt | Outcome | Why it is not an additional product failure |
|---|---|---|
| [Airship invalid constant](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/earlier-attempts/airship-parse/report.json) | Parse failure; two checked error diagnostics; no completion marker | The draft declared a constructed `PackedFloat64Array` as a constant. The lead changed it to a variable before execution. |
| [Bank legacy hard guard](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/earlier-attempts/prop-bank-legacy-guard/report.json) | 15 checks, four failures, zero checked diagnostics | Soft contacts were not enabled; a hull crash occurred before the intended rim witness. Inconclusive fixture. |
| [Bank initial overlap](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/earlier-attempts/prop-bank-initial-overlap/report.json) | 16 checks, one failure, zero checked diagnostics | The sampled rim already overlapped at tick zero. A later detected strike did not prove the intended clear-to-contact transition. |
| [Bank mislabeled roll](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/earlier-attempts/prop-bank-mislabeled-roll/report.json) | 16 checks, one failed desired predicate, zero checked diagnostics | The geometry supplied roll in `q_from_euler`'s third argument, but the metadata called it heading. Final revision corrects the naming/comments and preserves the exact pose. |

Exact [probe revisions](evidence/round3/probe-revisions/) accompany these reports. The corrected bank final run retains the numerical samples of the mislabeled-roll run; its orientation labels and guard descriptions are corrected. That repeated run resolves an actual evidence-description defect and is counted once. None of these errors is assigned to application developers.

The car simultaneous wall/ground-energy lead was not promoted: inspection did not isolate separately attributable work, and the wall-priority behavior is an intentional double-count guard. The report also preserves the distinction between the prior soft-box policy lead and this pass's hard-capsule numerical counterexample.

## Reproduction

Use a checkout containing this audit evidence and the audited application tree. Hydrate its real assets and import the application using the repository's normal tooling before launching headless scripts. The recorded runs used already imported resources. A different source or engine revision is a new experiment and must retain its own identity.

The [launcher](evidence/round3/run_probes.py) uses the repository checked runner, verifies the pinned engine SHA-512, requires a fresh output directory, gives each probe isolated XDG state, and runs selected jobs sequentially. It never overwrites the committed evidence or converts known failing exits into passes. From the repository root:

```bash
python3 docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/run_probes.py --list
```

Run all four probes into a new directory:

```bash
python3 docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/run_probes.py \
  --out tmp/collision-audit-round3/reproduction-new
```

Select one probe when validating a focused change:

```bash
python3 docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/run_probes.py \
  quad-prop-strike-energy \
  --out tmp/collision-audit-round3/reproduction-energy-new
```

The remaining selector names are `airship-collision-recording`, `slow-capsule-entry`, and `prop-bank-rim`. Supply `--engine` only for the same verified Linux binary at another local path. Follow the repository's shared-host admission requirements if reproducing on an enrolled host; this wrapper does not grant shared-host ownership.

The original evidence jobs ran through explicit checked-runner commands against the temporary drafts. Their final draft bytes match the delivered probes. The wrapper was subsequently checked for Python syntax, selector listing, repository-path resolution, and source/marker presence. The four final probes were **not** all re-executed through this packaging wrapper; that would duplicate already conclusive numerical runs. The retained checked reports remain the authority for what actually executed.

## Evidence review and publication checks

Packaging validation checks the following concrete properties:

- Every retained raw log's SHA-256 matches the corresponding checked report.
- Final completion markers, assertion counts and failed labels agree with the machine-readable observations and the 73/67/6 summary.
- The four delivered final scripts and four retained revisions match their executed draft bytes.
- The three airship files match their original bytes; the production verifier outcomes are retained with the probe output.
- Pinned source links resolve to actual baseline files and valid line bounds; local document links resolve within the repository.
- Application, asset and tools tree identities equal the audited baseline; staged changes stay inside the audit package.
- Remote publication must use the existing audit branch with an expected-head check and no forced update, and its resulting tree must match the local reviewed tree. The historical interruption recorded below does not substitute for that publication gate.

The [manifest](evidence/round3/manifest.json) covers the retained evidence bytes, and [provenance](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/provenance.json) records the campaign classifications and document hashes. The reviewed Git commit supplies the package identity; it is not embedded into its own files as a circular hash.


## Historical publication interruption

The core third-pass package was committed locally as `b56640c8e93e1086c3ef2964bb8c5389ca1986b3`. The GitHub tree-upload operations were interrupted. A subsequent read of the remote audit branch confirmed that it still points to `82e715cbe9c8254888c3bc1f7edad739ba4355c9`, the completed second-pass audit. At the close of that prior session, **the third-pass package had not been published to the remote branch**. Unreferenced Git objects may exist remotely, but they do not establish publication.

A verified incremental Git bundle preserved the local audit branch and its evidence at that boundary. It requires the existing `82e715cbe9c8254888c3bc1f7edad739ba4355c9` ancestor. No runtime file changed, and no probe outcome is altered by this publication status. Any later upload must first re-read the remote head and retain the expected-head and tree-identity gates above.

## Limits that remain open

These checks establish software counterexamples within their declared fixtures. They do not establish physical accuracy of fracture, restitution, propeller material behavior or proxy shapes. No new native-backend parity campaign, target-hardware timing, GPU capture, 1080p presentation qualification, cumulative energy-instability experiment, full damaged-flight validation or 300 km/h impact certification was performed.

The package adds no runtime fix and does not claim the six desired failures have been resolved. The [implementation slices](edge-case-plan-2026-11-18.md) state what would close each finding and which integrated checks remain necessary.
