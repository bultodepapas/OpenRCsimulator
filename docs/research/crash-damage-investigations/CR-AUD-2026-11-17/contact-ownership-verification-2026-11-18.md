# Fourth-investigation verification and reproduction

**Date:** 18 November 2026, America/Bogota.

**Scope:** [CR-AUD-25 through CR-AUD-27](contact-ownership-2026-11-18.md), with [three proposed correction slices](contact-ownership-plan-2026-11-18.md). No runtime fixes are included.

## Source identity and execution route

| Item | Recorded value |
|---|---|
| Application baseline | `a7de9b35676d891bc2034cc344b910d9e1ef9c61` |
| Local audit source when the new probes ran | `3a0cd2cb4b85da0f0e4481605da672e8c559749a` |
| Published third-pass equivalent | `dc5f7029c74dc56d018c246d6bdc87ab89b8a4b1` |
| Identical whole tree for those two audit commits | `c82fd267ef740bba6a33da7dcd65a6a69293aced` |
| Application tree | `f72e113b9f0cc068579c6c5d7cf5a216a3e67fac` |
| Asset tree | `3ed558d2a5f37ae24e784436c9def5841d7382ad` |
| Tools tree | `95d35ed671a2a32919ffadc13036c66e240ab2ec` |
| Engine | `4.8.beta2.official.cafc17a19`, Linux x86_64 |
| Execution | Headless, Dummy audio, repository checked runner, sequential engine processes |
| Isolation | A distinct XDG config/data/cache profile per job |
| Imported resources | Retained from the preceding campaign |

The engine SHA-512 was rechecked before the campaign:

```text
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

The [setup record](evidence/round4/setup.json) identifies the original local source. The third-pass publication recovered the previously interrupted delivery using individual Git blobs and a SHA-only tree, then a commit and expected-head, non-forced branch update. Its [published commit](https://github.com/bultodepapas/OpenRCsimulator/commit/dc5f7029c74dc56d018c246d6bdc87ab89b8a4b1) has parent `82e715cbe9c8254888c3bc1f7edad739ba4355c9`; its tree was verified against the original local tree before aligning the local branch. This does not alter the runtime source under test. The third-pass documents' historical interruption note remains a record of the preceding session.

Graph and `sim_test` MCP facilities were unavailable, and `/tmp/OpenRC/testpool/config.json` was absent. The local `tools/godot/run_checked.py` route was used with one engine job at a time. No external shared-host ownership was assumed. Helpers supplied bounded drafts and source review with no engine launches. The lead reviewed the drafts, executed the jobs, evaluated the measurements and integrated the evidence. Requested helper model settings do not attest an independently inspected model runtime.

## Final executed probes

| Probe | Assertions | Pass | Desired-behavior failures | Checked errors / warnings | Elapsed process time |
|---|---:|---:|---:|---:|---:|
| [Quad finite-box disc contact](evidence/round4/runs/probes/quad-disc-box-separation/report.json) | 29 | 27 | 2 | 0 / 0 | 3.062134 s |
| [Car damage region](evidence/round4/runs/probes/car-damage-region/report.json) | 22 | 18 | 4 | 0 / 0 | 2.286466 s |
| [Fixed-wing gear scenery](evidence/round4/runs/probes/fixedwing-gear-scenery/report.json) | 14 | 13 | 1 | 0 / 0 | 5.036899 s |
| **Total** | **65** | **58** | **7** | **0 / 0** | Three separate jobs |

All final reports are complete, have their required completion markers, and record exit code 1 / `ok:false`. They are deliberately red reproductions. Zero checked diagnostics distinguishes them from a parser/engine failure; it does not convert failed assertions into passes. Process duration includes preparation and startup and is not a frame-time or collision-performance measurement.

No existing broad suite was repeated for this pass. Earlier counts remain separate: the original 53-suite campaign, the second pass's 163 assertions plus its selected 33-check helicopter control, and the third pass's 73 assertions. This pass adds only the 65 assertions above. It does not add the postprocessing calculation below to that total.

### Exact final probe identities

| Delivered script | SHA-256 |
|---|---|
| `probe_quad_disc_box_separation.gd` | `e05b0a81c93c8c7860e362da76486aa14db68b9f5c6aa5a6993bee95ecb6f95c` |
| `probe_car_damage_region.gd` | `7446cf73ec30f09ac22ccacf56a560b698cc479d3467e29eff784440093fa308` |
| `probe_fixedwing_gear_scenery.gd` | `6de29313d86e466760c0607e55757d77c2a0facf1bdd03d6ad3dd0009da62c7c` |

The delivered files in [probes](evidence/round4/probes/) are byte-identical to the executed temporary drafts. Their draft-header comments are retained as provenance; the lead reviewed and accepted their bounded use here. One comment in the car script generically calls stock probe 0 a front bumper. The code checks only that it is uniquely frontmost. Bisonte's inventory supports that name; Nitro's data does not independently label it. The finding and interpretation use **frontmost hull probe** for the shared claim. Keeping the exact executed bytes avoids substituting a later editorial revision for the original experiment.

### What was actually executed

**Quad:** six direct calls to the real graded transition with prescribed stock-valid input and output frames. Production world construction, collision bins and installed callbacks are used. Plant validation and kernel reset-frame preparation pass, but no reset is committed and no integration tick is accepted in this probe. The static fixture has one spinning rotor and compares separated, overlapping, remote, stopped, decoy-only and contact-plus-decoy cases. It does not prove continuous approach, swept blade phase, field prevalence or other vehicles' rotor behavior.

**Cars:** eight sessions load the two stock vehicle models. A subclass overrides the staged road and initial airborne state. Six wall cases first change body damage at tick 1 and pass the front-only geometry/telemetry admission gates; two no-wall controls remain undamaged through four ticks. Every retained shadow body endpoint matches the real accepted endpoint byte-for-byte. The active backend is `gdscript_reference`. All four RK stage samples per tested tick are retained, but they are numerical evaluation states, not a full continuous collision trajectory. The fixture's in-memory recording metadata retains the stock course identity despite the road override; the script and traces, not that metadata alone, are the reproduction authority. No saved recording/replay claim is made.

**Fixed wing:** three ordinary Avanti runway sessions retain gravity and ordinary force callbacks. The prescribed start stops the turbine, releases stiction-anchor flags, sets 3 m/s body and wheel-rim motion, and uses extended/downlocked gear. The clear and wheel-box contexts produce byte-identical 80-row accepted histories; the elevated hull control terminates on scenery at tick 22. The comparison includes recorded body, aux/continuous arrays, modes, extension/compression, contact events and scenery fields. It does not include every internal variable in the application. The wheel witness is an undeformed support reference; five sampled hull poses per interval are not a swept mesh certificate. No visual capture was made.

## Earlier failure excluded from product evidence

The first [car draft attempt](evidence/round4/runs/earlier-attempts/car-parse/report.json) fails at parse time because Godot cannot infer the local `front_after` type from a Variant expression. It records two checked errors, zero warnings and a missing completion marker. The lead changed that declaration to an explicit Boolean and ran the final version. The [original revision](evidence/round4/probe-revisions/car-region-v0-type-inference.gd) and [raw log](evidence/round4/runs/earlier-attempts/car-parse/engine.log) are retained. No simulation assertions ran in that attempt; it is an audit-fixture error, not a fourth product finding.

The final engine jobs were not rerun merely for packaging. Editorial refinements are confined to documentation. That preserves a clear distinction between the exact script that executed and the later interpretation.

## Derived gear-support calculation

The [derivation script](evidence/round4/derive_gear_support.py) reads the retained gear observations and the source's analytic runway waves. It admits the recorded point inside the constant-amplitude runway region, evaluates height/slopes, reconstructs normal compression, and transforms the point's vertical terrain projection into the recorded box frame. The [retained result](evidence/round4/derived/gear-support-projection.json) records all six relevant source hashes and the observations hash.

At tick 24, the computed compression differs from the recorded value by `2.7755575615628914e-17 m`, and the vertical terrain projection has box gap `-0.027940707145217143 m`. The source supports the selected runway amplitude and coordinate transform; the compression agreement cross-checks the admitted surface interpretation. This calculation was executed independently by the lead after source review. It does not determine the location of a physical deformed tire, prove a finite wheel solid intersects the box, or add an accepted simulation tick. Python's numeric output is retained separately from Godot's raw run.

Reproduce this calculation without launching an engine:

```bash
python3 docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round4/derive_gear_support.py
```

The script is specific to the preserved baseline fixture. A changed terrain/model or altered observation file must be treated as a new experiment with its own provenance.

## Reproduction of the three engine probes

Use a checkout containing the evidence and the audited application tree. Hydrate the real assets and import the app with the repository's normal tools before headless execution. These runs reused existing imports. Follow shared-host admission requirements on an enrolled host; the wrapper does not grant a shared session.

The [launcher](evidence/round4/run_probes.py) verifies the pinned engine hash, requires a fresh output directory, creates isolated XDG profiles, executes selected jobs sequentially through the checked runner, and preserves nonzero exits. From the repository root:

```bash
python3 docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round4/run_probes.py --list
```

Run the selected correction's probe into a fresh directory:

```bash
python3 docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round4/run_probes.py \
  quad-disc-box-separation \
  --out tmp/collision-audit-round4/reproduce-quad-new
```

The other selector names are `car-damage-region` and `fixedwing-gear-scenery`. Omitting selectors runs all three. Use `--engine` only for the same verified binary at a different path. A different engine or runtime tree creates a new verification record. The final jobs originally ran through explicit checked-runner commands against the drafts; the packaged launcher is subsequently checked for Python syntax, listing, marker presence and repository resolution. The campaign is not claimed to have been rerun through this packaging wrapper.

## Packaging and review gates

The [provenance record](evidence/round4/provenance.json) records run classifications, counts, script identities, source trees and document hashes. The [manifest](evidence/round4/manifest.json) records exact evidence bytes. Raw reports retain original temporary command/log paths; the manifest maps the preserved copies in this package. Those historical paths are not claims that the evidence was regenerated at its delivered location.

The audit index is extended in each pass. Earlier provenance files retain the index hash for their own published snapshot; the third-pass index hash is checked against `dc5f7029c74dc56d018c246d6bdc87ab89b8a4b1`, while this pass records the updated index. Earlier evidence is not rehashed to imply that the expanded index existed during a preceding campaign.

Before commit, the lead verifies log hashes against checked reports, exact equality between extracted observations and engine JSON markers, completion markers and failure labels, draft/delivered probe equality, six admitted car intervals, all exact shadow endpoints, the byte-compared gear history assertion, and the numerical derived output. Local document links and pinned source files/line bounds are checked. Python packaging utilities are syntax-checked without launching additional engines.

Independent reviewers challenged the quad and car mechanisms and the gear geometry. The review produced narrower language for the undeformed wheel reference, model-reported compression, recorded history fields and released stiction anchors. It did not replace source inspection or numerical admission. The unexecuted vertical-car-pose lead and alternative water/energy interpretations remain unpromoted.

The reviewed change set must stay inside this audit package. Application, assets and tools trees must remain identical to the baseline. GitHub publication uses the existing audit branch, a freshly inspected expected head, no forced update, and an exact local/remote tree comparison. The final Git commit provides package identity without embedding its own hash into the files it hashes. These gates protect the evidence chain; they do not qualify physical realism, target-hardware performance, native/reference parity, rendered deformation or 300 km/h operation.
