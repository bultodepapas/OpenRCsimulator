# Round-three audit reproduction

Report: [loading transactions, workload identity and remaining event boundaries](../../../../docs/research/performance-audit-2026-11-19/round-3.md).

This package reproduces **F46–F48**, the remaining **F02/F07** component observations, selected current regression controls and an existing Nitro-identity cost boundary. A successful baseline observation means the documented behavior recurred. It does not establish a repair, GPU performance or a full game run.

## Run

Use Python 3.10+ and the official **Godot 4.8 beta 2 Linux x86_64** binary, `4.8.beta2.official.cafc17a19`. Its required SHA-512 is:

```
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

The repository must contain Git commit `d736ee8a2eab0b59b0fa2c561a1eef07f5fae396`. If a shallow audit-branch checkout lacks it, fetch that commit first:

```bash
git fetch origin d736ee8a2eab0b59b0fa2c561a1eef07f5fae396
python3 research/performance/audit-2026-11-19/round3/run.py \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --out /absolute/path/to/new-round3-output
```

Use a new output directory. The runner refuses an existing directory, a different engine, differing pinned Git bytes, altered fixture assets or a changed checked-runner source. It uses the repository's checked runner in its supported location, preserving test-queue/admission imports. On an enrolled shared host, follow the repository's test-queue rules. This collection used an unenrolled local environment with no configured pool.

Application source comes from **pinned Git blobs**, independently of the audit branch's older runtime base. The runner does not switch branches, modify application files, change user preferences or fetch a new engine. Four disposable projects have independent data/config/cache roots. Simulation has an explicit 240 Hz setting; the rendering, loading and identity probes do not qualify simulation cadence.

## What runs

| Launch | Purpose and boundary |
| --- | --- |
| `r3-resource` | Unmodified current resource-event control: 90 checks. |
| `r3-collision-order` | Unmodified current scenery/lake tie-helper control: 17 checks. |
| `r3-collision-anchor` | Actual two-obstacle/two-point geometric contact query; establishes the F02 hierarchical anchor residual. |
| `r3-event-bound` | Synthetic independent time surfaces; shared event timestamp versus individual locator width. |
| `r3-airship-restore` | Actual terrain-only airship session and recorder; invalid replacement remains transactional, valid replacement closes once. |
| `r3-render-import` | Import only the bounded render dependency project. |
| `r3-lighting-off` | Actual Classic RC rig over a BoxMesh; OFF, same-time and re-enable parameter counts. |
| `r3-calibration-mixed` | Injected timing samples and active-flight predicate; production collection finalization/storage/reuse. |
| `r3-calibration-high` | Injected complete High verdict; workload-aware `needed()` versus output-size-only veto. |
| `r3-auto-control` | Unmodified current auto-calibration control: 94 checks; one recorded ObjectDB-at-exit warning. |
| `r3-cloud-control` | Unmodified current desired-set cloud-cache control: 16 checks using synthetic images. |
| `r3-loading` | Actual AppRoot/loading methods, controlled worker, backdrop and candidate stand-ins: 11 checks. |
| `r3-identity` | 240 repeated Nitro and 240 body identity calls; stable reference identities, no I/O or timing measurement. |

The final collection completed all **13 checked launches** with zero engine errors. All except the existing auto-calibration test had zero warnings. Each launch has a 60-second bound. The output includes raw `engine.log`, checked `report.json` receipts, and `audit_results.json` with commands, counts and hashes. The baseline predicates intentionally recognize the observed defects; a correct runtime repair should invalidate those predicates in a separately pinned candidate experiment.

## Exact fixture scope

[fixture_sources.json](fixture_sources.json) pins **712 source/data/support files** and **19 fixture assets**. The simulation/render/loading/identity source closures contain **211/65/694/7** paths respectively, with overlap. Those counts do not imply full dynamic coverage. Canonical blob bytes are used even where a developer checkout converts JSON to CRLF.

Simulation uses two assertion-only scenery substitutions, located under `fixtures/simulation/scenery/`. They are required to compile the terrain-only session closure without unrelated visual resources and fail if invoked. The tested scenery collision method itself is unchanged; its geometry probe builds a two-box component world directly.

Loading supplies a minimal project, three-entry global-script-class cache, placeholder scene/texture/audio resources and the controlled probe. **Thirteen dependency files** have explicit line-checked changes only to `preload` resource expressions. Those patches and both original/output hashes are in the manifest. AppRoot, Home, field validation and the loading/preparation scripts are unmodified. The probe overrides setup/process plumbing, preview requests, backdrop rebuild and flight creation; the real field JSON and skin-kit registry are copied. It establishes state transitions and admission counts, not real backdrop rendering or helicopter construction cost.

The render fixture's calibration samples/verdicts are synthetic. Only the active-flight predicate is overridden for mixed-workload finalization. Its actual viewport changes and production methods execute. The lighting probe counts the rig's aggregate material setter calls, not GPU uploads. `selection=disabled`, inherited lighting and mode OFF remain distinct paths.

The identity control has no native extension installed. The file-read byte totals in the report are source-derived arithmetic. An exploratory ptrace/strace launch was rejected before the engine started; it is not an I/O measurement.

## Provenance and limitations

The [published evidence](../../../../docs/research/performance-audit-2026-11-19/round-3-evidence.json) retains the final logs unchanged and separates nonqualifying exploratory attempts. A broad airship test with missing visual resources is not a pass despite its zero-failed assertion summary. A different loading-gate fixture that timed out at exit is also nonqualifying; the published probe is the independently reconstructed successful version.

No runtime repair, GPU timing, FPS, native backend, release, full-game integration, real controller, audio, sustained memory, other OS or full CI qualification is claimed. The owning acceptance tests and hardware gates are described with each finding in the report. Preserve the earlier round manifests; do not update their hashes to make another runtime appear equivalent.
