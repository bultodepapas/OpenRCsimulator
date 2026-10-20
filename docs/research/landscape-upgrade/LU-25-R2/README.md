# LU-25-R2 — Skip unused lake diagnostics outside contact coverage

Measured 2026-10-19. A conservative contact-only lake query reduced the Stik runway
CPU callback cost by **19.60%**, the median of three paired runs (19.58–19.84%).
This is headless simulation CPU evidence, not rendered FPS, GPU, radio-latency or
physical validation. The complete application test suite was not run.

## Profile and change

The frozen baseline is commit `a3df9bc0555664776d8b30e5f0a9ed402361c1b7`.
[Identity check](baseline-identity.json) matched all 290 captured runtime/data files
after CRLF-to-LF normalization only; [byte hashes](source-hashes.json) retain the
actual measured copy. It already includes LU-25-R1 and the H16 ground-stage fix.

Nested method timers over 240 warmup and 2,400 sample ticks identified
`LakeSurface.sample_terrain_validated` as the largest measured runway leaf:
19 calls/tick and 1,011.6 microseconds self time/tick. Other large measured costs
were hull loads (461.8), wing flow (459.5) and ground microrelief (437.7).
These instrumented times include substantial tracing overhead and are used only
for attribution. P-51 trim instead had its largest measured leaf in segmented
slipstream (655.6 microseconds/tick); that separate candidate was not adopted.
All three profiles and logs are retained under `raw/profile-*`.

`GroundTerrain.sample_validated` and `HullContact.prop_disc_depth` discard the
lake result whenever `covered` is false. They now use
`LakeSurface.sample_covered_terrain_validated`, which returns `{covered = false}`
outside the bank polygon's axis-aligned bounds expanded by the full 0.025 m
finite-difference stencil. Near-bank, interior and concave-bounds misses retain
the original sampler. Nonfinite coordinates retain the invalid sample.
The public full sampler still supplies all outside distances and diagnostics.
The change adds no persistent cache, data fields, physics arithmetic or timestep
changes. See the [three-file patch](measured-tools/target.patch).

## Before and after

Godot `4.7.2.stable.official.ed1daf0bf`, Windows, Ryzen 9 5900X, native engine
process at normal priority, affinity mask 16 (logical CPU 4). Runs were serialized
on a shared development host; system-wide idle conditions were not established.
The production simulation remains at 240 Hz.

Each run compares two detached complete flight sessions using identical input,
field, lake and collision context. After 2,400 warmup ticks per session, 120 pairs
of 120-tick batches alternate AB/BA order, for 14,400 measured ticks per session.
The clock covers input/session and simulation callbacks, excluding fingerprinting
and checkpoint comparison. No profiler wrappers are present in these runs.

| Workload | Before median µs/tick | After median µs/tick | Median paired CPU reduction | Faster pairs |
| --- | ---: | ---: | ---: | ---: |
| Stik runway, repeat 1 | 2,632 | 2,118 | 19.58% | 120/120 |
| Stik runway, repeat 2 | 2,609 | 2,094 | 19.84% | 119/120 |
| Stik runway, repeat 3 | 2,600 | 2,086 | 19.60% | 120/120 |
| Stik airborne trim, single control | 749 | 723 | 3.56% | 114/120 |
| P-51 airborne trim, single control | 2,020 | 1,993 | 1.45% | 94/120 |

Reduction is the median of `100 * (1 - candidate_batch / baseline_batch)`, not
the ratio of independent per-tick medians. Runway repeats yielded 359/360 faster
pairs. Airborne controls were not repeated and support a narrower conclusion.
The earlier short preliminary runway run is retained separately and is not pooled.
[Campaign ledger](campaign.json) records exact commands and summary calculations;
`raw/paired-*.json.gz` retains every tick and batch measurement, with engine logs.

### Measured tradeoff

A separate direct-sampler test used six alternating pairs of 1,000 calls per
point after warmup. It is not a full-session result.

| Point | Before µs/query | After µs/query | Paired reduction |
| --- | ---: | ---: | ---: |
| Runway, outside bounds | 26.3645 | 2.5615 | 90.28% |
| Lake bed | 119.6845 | 121.9010 | -1.74% |
| Bank | 116.3600 | 117.8620 | -1.36% |
| Bank edge | 116.3315 | 117.6745 | -1.18% |
| Just outside bank, within stencil margin | 118.8790 | 119.2620 | -0.37% |

The extra bounds scan adds small measured overhead for fallback queries. No
full-session water-operation improvement is claimed. Raw component results and
the exact probe are retained, including these unfavorable measurements.

## Behavior and regressions

All five paired runs completed without engine errors. Numeric state, auxiliary
state, continuous state, inputs, loads and modes have equal trajectory hashes
across **72,000 measured ticks per implementation**. All **600 complete batch
checkpoints** are byte-identical. Production files match the measured intended
sources exactly; only the isolated benchmark copies rewrite dependency paths.

The new `test_lake_covered_sampling.gd` passes **761 checks** against original
method oracles. It covers default, translated, custom convex and concave lakes;
edge tolerance, expanded-boundary and finite-difference probes; nonfinite input;
full outside diagnostics; both ground query entry points; and full prop-disc
results. A deterministic sweep includes 200 positions (40 outside expanded
bounds) and 100 tilted-disc cases. Finite float values compare by bytes; NaNs
compare by classification. Oracle methods were checked against the baseline.
A disposable mutation that rejects all finite points is detected with 312
failures and no engine errors.

Fourteen targeted suites pass: covered sampling, ground terrain, lake definition
cache, lake surface, lake ground contact, lake collision, lake session, prop
strike, prop strike feedback, ground stiction, wheel session, checkpoint, water
checkpoint and ground start integrity. Existing inertia and renderer warnings
are retained in the logs.

`test_golden` still fails four flights: `roll_15`, `pull_throttle`,
`rudder_doublet`, and `glide_15`. Running it on the frozen baseline reproduces
the exact same four failure lines and numeric errors. No goldens were changed.
See [verification](verification.json), `raw/results.json.gz`, both golden logs
and all per-suite logs. These pre-existing failures remain unresolved.

## Reproduction and retained sources

Use a separate checkout of the baseline commit and the same pinned engine.
Import that checkout once before timing. The captured `project.godot` is retained
as `measured-tools/project.godot.txt`. Restore the frozen application to
`tmp/perf-pass3-20261019/base/app` under that checkout, with its resource imports
and root asset paths available. Do not import copies sharing read-only resources.

Copy `make_candidate.py`, `campaign.py`, and `paired_session.gd` from
`measured-tools` into `tmp/perf-pass3-20261019/`, then run from the checkout root:

```powershell
python tmp/perf-pass3-20261019/make_candidate.py
python tmp/perf-pass3-20261019/campaign.py
```

The generator uses the repository's `research/performance/session_pair_probe.gd`;
compare it with the retained exact probe when reproducing a later revision.
It creates a six-script isolated dependency graph: the three changed physics
files plus ground wheels, ground contact and flight session routing files.
Only `candidate` rewrites resource paths; `intended` holds the production bytes.
Gzipped complete before, candidate and intended scripts are retained under
`sources`, so the dependency rewrites and measured implementations are auditable.

Use a fresh output directory or preserve previous measurements before rerunning.
The dated scripts retain original Windows paths in the command ledger; relocating
the checkout requires regenerating candidate paths. `prepare_pass3.py` records
the original copying procedure and its dependency on the earlier pass's
instrumenter; the complete adapted `instrument.py`, profiler clock and probe
are retained directly, so that earlier temporary directory is not required to
inspect or rebuild instrumentation. Runtime benchmark copies must remain
uninstrumented. The original draft test paths likewise refer to the frozen copy;
the integrated regression test uses portable `res://` oracle fixtures.

[Manifest](manifest.json) hashes the retained artifacts. No renderer/GPU timing,
water-session performance qualification or full CI pass is implied by this report.
