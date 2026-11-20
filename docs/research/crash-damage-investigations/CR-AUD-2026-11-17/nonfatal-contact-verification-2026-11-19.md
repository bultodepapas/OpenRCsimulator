# Nonfatal-contact verification — 19 November 2026

## Verdict and scope

The [review](nonfatal-contact-review-2026-11-19.md) uses **11 qualifying executions: four new probes and seven existing controls**. Together they contain **749 checks: 747 passes and two desired-behavior failures**, with **zero checked engine errors or warnings in the qualifying executions**. Both desired failures concern clear rotating points admitted by scenery padding; they are related fixtures for CR-AUD-31, not two independent production regressions. Passing characterization assertions describe the current behavior, including a capability limitation or integration approximation; they do not certify that behavior as physically correct.

Three additional script attempts are retained and **excluded** because their component fixture lacked required resources. They generated 151 checked engine errors in total. In particular, a script printing `0 failed` and exiting zero is not sufficient for qualification. Two checked editor imports passed without engine diagnostics. A preflight manifest refusal launched no Godot process and adds no test count.

This is a source/component audit and canonical-plan update. No production `.gd`, aircraft data, application project settings, goldens or native binaries were modified. No full release suite, native/reference parity campaign, GPU/frame-rate measurement, real material test, listening evaluation, full-fleet 300 km/h flight or complete recovery maneuver is claimed.

## Exact inputs

| Input | Identity |
| --- | --- |
| Application revision | `d736ee8a2eab0b59b0fa2c561a1eef07f5fae396` |
| Application checkout used | `/workspace/scratch/40820211f477/OpenRCsimulator-main` |
| Audit/document checkout | `/workspace/scratch/40820211f477/OpenRCsimulator`, branch `audit/collision-damage-2026-11-17` |
| Godot | `4.8.beta2.official.cafc17a19`, Linux x86-64 |
| Engine SHA-512 | `428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9` |
| Fixture | `/workspace/scratch/40820211f477/nonfatal-fixture/app`; isolated exact-source component project |
| Final copied resources | 1,711 files, each recorded by relative path, SHA-256 and size in [source-manifest.json](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round6/source-manifest.json) |
| Project settings | Explicit manifest text: compatibility renderer, 240 Hz physics, 12 maximum catch-up steps, zero physics jitter fix; no production autoload/native package installation |
| Runner | Reviewed source's `tools/godot/run_checked.py`; fresh per-run XDG data/config/cache directories, headless, Dummy audio, required completion markers, script runs with engine warnings treated as errors |

The audit uses the checked local runner fallback because no callable test-pool capability/configuration was available. Tests were run for correctness, not comparative timing. Existing admission messages such as estimated aircraft inertia or experimental engine data remain visible in logs; the “zero warnings” count refers specifically to the runner's checked engine diagnostics, not a claim that every aircraft parameter is calibrated.

The exact-source fixture keeps the previous broad component resource set, adds the selected tests' dependencies and retains the full source hashes. The production `project.godot` is deliberately replaced by the explicit minimal fixture text and recorded separately as `replaced_source_project`. The source checkout was verified against all 1,711 final copied-file hashes. Editor-generated imports/caches are separately produced; the runner skips regenerated `.import` descriptor hashes while verifying copied source/resource bytes and project text.

This resource set is not a complete game installation. The attempted `test_hull_scrape_session` also instantiates `Main`, which loads landscape/soundscape resources beyond this fixture. Its excluded results do not establish a defect in a fully provisioned application.

While packaging, remote main advanced to `59d4a3d5bf4d9b5656a8efead01245bfcd4024a0`. A read-only [comparison of 23 relevant source/test/plan blobs](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round6/later-main-comparison.json) found them identical to the reviewed revision. Other application/debug/creator/telemetry files changed. All execution claims remain pinned to `d736ee8a`; this limited comparison does not relabel the runs or certify whole-application equivalence at the later head.

## Qualifying executions

### New probes

| Probe | Checks / passes / desired failures | Checked result | What it establishes |
| --- | ---: | --- | --- |
| `geometry` | 18 / 17 / 1 | Exit 1, complete, engine 0/0 | Direct flat-plane clearance/tangent/shallow-penetration controls at 300 km/h; original padded-scenery witness with synthetic CG inside the box. |
| `geometry-outside` | 13 / 12 / 1 | Exit 1, complete, engine 0/0 | Stronger direct scenery witness: both CG and modeled point remain above the box, with an analytic interval-wide point-clearance bound. |
| `water-prop` | 47 / 47 / 0 | Checked pass | Accepted synthetic one-point water policy, directly invoked/injected prop guard, direct moving-wave interface-rate witness. |
| `remainder` | 19 / 19 / 0 | Checked pass | Actual accepted synthetic Simulation steps with and without scenery; current nonterminal response stops body position at contact while the full tick clock advances. |
| **New probes** | **97 / 95 / 2** | **Zero checked engine diagnostics** | Different evidence levels are retained separately. |

Every direct call is labeled in the script and review. The prop cases inject auxiliary RPM and boundary pose without a shaft step; they do not reproduce coast or known blade phase. The water and remainder cases execute the real `Simulation.step()` and session callback after deliberately replacing geometry/forces with a synthetic body. They are accepted-path tests, not full-aircraft flight dynamics. The padding witnesses call `SceneryCollision.first_hit` directly and do not prove a committed impulse, complete-aircraft clearance or stock-flight false crash.

Probe source hashes:

| File | SHA-256 |
| --- | --- |
| [probe_nonfatal_geometry.gd](evidence/round6/probes/probe_nonfatal_geometry.gd) | `e9aa4fa206e51f26240d2819ecc6a37633889f98e28be28e8bb4ebd56f270caf` |
| [probe_nonfatal_geometry_outside.gd](evidence/round6/probes/probe_nonfatal_geometry_outside.gd) | `4434f3266bed8a269b4e9def042f83d4208f3f7fdc5dac12f57df880be7aee8c` |
| [probe_nonfatal_water_prop.gd](evidence/round6/probes/probe_nonfatal_water_prop.gd) | `dc7eba09d6c743f88f03fd4b507d29e488b1786d6fe6c172452899175043e741` |
| [probe_nonfatal_remainder.gd](evidence/round6/probes/probe_nonfatal_remainder.gd) | `fd01b720ef02337d920c57aea70256e668af720d788a6612528d243f545cf052` |

The original helper drafts were copied unchanged; all hashes match their executed versions. The stronger geometry fixture was added separately instead of silently overwriting the initial witness. Its algebraic bound and source-specific body-velocity interpolation were independently reviewed before execution.

### Existing controls

| Existing script | Passing checks | Scope |
| --- | ---: | --- |
| `test_soft_contacts.gd` | 36 | Soft hull mechanics and selected continuation/clear controls. |
| `test_hull_friction_observation.gd` | 388 | Frozen force-byte reference, independent virtual work, instantaneous power, live mass and dry/covered lake observation scope. |
| `test_hull_scrape_audio.gd` | 60 | Bounded accepted-grain behavior, brief brushes, lifecycle/dedup, input validation and render cancellation. Dummy audio; no listening claim. |
| `test_prop_strike.gd` | 44 | Existing prop detection, nonterminal behavior, reset and route controls; does not qualify physical blade strength. |
| `test_lake_collision.gd` | 61 | Existing lake/ground/prop sweeps, tangency policy, normals, authored tolerance and negative controls. Counted from the 61 emitted `ok` check lines. |
| `test_collision_tie_order.gd` | 17 | Current earliest-anchored tie ordering. |
| `test_airframe_contacts.gd` | 46 | Generated Stik geometry/field friction, tail/inverted contact, 120-row exact soft-contact replay; final dependency-corrected execution only. |
| **Existing controls** | **652** | **All checked passes, zero checked engine errors/warnings.** |

The airframe control writes, reads/replays and then deletes its temporary `.orfl` recording in its existing test code. The checked log retains the 120-row exact-replay result; this package does not claim to retain a standalone recording that the test removed. Earlier audit recordings remain separate historical artifacts.

## Excluded attempts and fixture corrections

| Attempt | Observed result | Treatment |
| --- | --- | --- |
| Initial `test_hull_scrape_session` | Exit 0; summary 46 checks/0 failed; 11 engine errors | Relative ClearView preloads and the exact Stik grain resource were absent from the initial fixture. Excluded entirely. |
| Initial `test_airframe_contacts` | Exit 1; summary 43 checks/1 failed; 1 engine error | Missing bundled Stik grain prevented visual-model setup. Exact source resource added; the final 46/0 rerun qualifies. The original failure remains retained. |
| Dependency-retry `test_hull_scrape_session` | Exit 0; summary 56 checks/0 failed; 139 engine errors | `Main` requires additional vegetation, scenery, soundscape and other assets; errors invalidate its apparent passing summary. Remains excluded and opt-in in the reproducer. No modified production test was used to manufacture a pass. |

Initial and final source manifests are retained. Adding exact source dependencies changes the fixture inventory, not production script behavior. The three attempts total **151 checked engine errors** and are excluded from all 749 qualifying checks. Their reports/logs remain under [runs/initial](evidence/round6/runs/initial/summary.json) and [runs/dependency-retry](evidence/round6/runs/dependency-retry/summary.json), with explicit classification in the manifest.

The first runner preflight also found `app/project.godot` incorrectly listed among exact copies even though the component settings intentionally replace it. The manifest was corrected to separate that original source file from generated fixture text before any script launched. This was an audit harness issue, not an application failure or an assertion result.

## Reproduction

Use a hydrated checkout at the exact application SHA and the pinned engine. The builders refuse wrong revisions, hashes, missing resources and an already existing output directory. The audit scripts live on the audit branch; the application checkout is separately pinned because that branch's historical application files are not current main.

```bash
audit_dir=/path/to/audit-checkout/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round6
source_dir=/path/to/d736ee8a-checkout
fixture_dir=/tmp/openrc-nonfatal-fixture-fresh
engine_bin=/path/to/Godot_v4.8-beta2_linux.x86_64

python "$audit_dir/build_fixture.py" --source-repo "$source_dir" --out "$fixture_dir"

python "$source_dir/tools/godot/run_checked.py" \
  --out-dir /tmp/openrc-nonfatal-import-fresh --label nonfatal-import --timeout 180 \
  --warnings-as-errors -- \
  "$engine_bin" --headless --editor --path "$fixture_dir/app" --audio-driver Dummy --import --quit

python "$audit_dir/run_probes.py" \
  --source-repo "$source_dir" --project "$fixture_dir/app" --engine "$engine_bin" \
  --out /tmp/openrc-nonfatal-checks-fresh
```

The default script set is the four probes and seven qualifying existing controls. **Its expected aggregate exit is nonzero** while the two desired no-false-contact assertions remain unresolved. Inspect each checked report and the exact failing labels. A nonzero exit from a different assertion, a missing completion marker or any engine error is not equivalent evidence.

To rerun only passing existing controls, supply their seven names explicitly before the options. `--list` lists all jobs. `test_hull_scrape_session` is an explicit opt-in retained full-Main-resource check; it is not part of the default qualification set. Do not count it as passing with this incomplete resource set. A full application installation and corresponding resource manifest would be needed to qualify its entire path.

Run `calculate_contact_scales.py` to regenerate the independently computed speed/angle/prop illustrations. Those numbers have no Godot dependency and are not material-response measurements.

## Integrity and review

The [manifest](evidence/round6/manifest.json) records per-run script hashes, source identities, checked return/completion/diagnostic status, qualifying/excluded classifications, assertion totals and retained relative log/report paths. Original reports keep their historical absolute execution paths. The source manifest and probe bytes are sufficient to reconstruct the component inputs; engine imports are recreated separately.

Root review checked the mathematical clear-path bound, zero/far/penetrating controls, accepted-versus-direct distinctions, source conventions and result counts. Independent source reviews covered geometry/continuation, prop/water and canonical plan/audio ownership. The report keeps the weaker first geometry fixture, deliberate current policies and unsuccessful full-Main attempts visible. The four new records remain open; this evidence package is not a runtime repair.

Review corrections made before publication distinguish subsystem tie ordering from session precedence, represented compliant geometry from search padding, conditional changes in flight authority, sampled GP-07 coverage from continuous clearance, and a commanded recovery/end state from mere nonterminal continuation. Point kinematics and effective-mass arms use their respective reference points; each accepted work increment contributes once. These wording corrections change no executed probe or production code.
