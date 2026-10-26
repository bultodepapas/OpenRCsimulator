# GDU-03: Companion qualification on Godot 4.8 beta1

2026-10-25 (America/Bogota). The existing airborne Ugly Stik circuit scope passes
the unchanged qualification matrix on official Godot
`4.8.beta1.official.4d10419ca`. The same current controller also passes on the
4.7.2 baseline. This renews source/build admission; it does not expand activities,
weather, population or physical claims.

The [final-core follow-up](final-core/README.md) renews admission on source commit
`be068e5a3…` with canonical solver `5df257b3…`, after the invalid-start and shared
minimum-normal constant corrections. The original round below used `1f7daf66…`.

The [2026-10-26 aileron follow-up](../../../ai-companions/AFC-02/aileron-2026-10-26/README.md) renews the same narrow scope on corrected Stik data and current source. The dated results below remain historical.

## Actual flight qualification

Both checked matrices pass **148 checks, zero failures, zero engine errors and
zero engine warnings**. Each calm and gentle-practice case with 1, 2 and 3 aircraft
completes 28,800 ticks at 240 Hz (120 simulated seconds), without refusal, crash
or simulation fault. Two additional calm, three-aircraft runs on each engine
complete and have bit-identical sampled state/command traces within that engine.

The [beta matrix](beta-matrix/README.md), [baseline matrix](stable-matrix/README.md),
and their [checked logs/reports](checks/) retain the actual results. The maximum
radial error is 4.047819 m against the unchanged 40 m gate; minimum clearance is
34.310642 m against 20 m. Minimum player and fleet distances are 122.307209 m and
121.744244 m against 30 m and 15 m. TAS spans 14.569302–15.498761 m/s against
10–25 m/s. Maximum normalized input is 0.78539816. Field profile observations
come directly from the new beta CSV, at its six-decimal precision.

Both exported CSVs are byte-identical across the two engines:

| Artifact | Rows | SHA-256 |
| --- | ---: | --- |
| Scenario metrics | 6 | `4d36b98a23fe0a18c82873dbb6b8dd1a98390da8e6d49d566dbe6bb73b8d734f` |
| One-second flight samples | 1,440 | `8b6293ef761844afba150313152f2262e417af5ddc43373424a905ad805745d2` |

The [comparison receipt](matrix-comparison.json) establishes equality of these
rounded metrics and one-second position/clearance/airspeed/control samples. It
does not establish equality of every physics state at every tick, `.orfl` exact
replay, full fleet replay or controller decision replay.

## Admission identity and source drift

The previously pinned pilot `3842cbdba…` no longer matched production before this
engine upgrade. Later stopped-traffic/held-maneuver and terrain/traffic repairs
changed the source; their candidate checks did not renew source-profile admission.
This matrix flies the actual current pilot
`6c9eb4c53f4f80c284249fc143f976b2e5becc555a50ee415afe92bb8129b151` on both
engines. No controller or physics source was edited for this original round.
That round retained circuit dependency `1d5699fa…`, solver qualification `1f7daf66…`,
aircraft data `5ef239c6…` and raw Club field `de142b1a…`.

The [matrix input manifest](app-input-manifest.json) fingerprints the beta copy's
selected `.gd`, `.json` and project files. The [baseline differences](all-selected-input-differences.json)
retain every difference among those selected files: admission/test changes and
presentation customization/workshop records. The pilot, circuit, simulation,
physics, failures, aircraft definition and field inputs match. These manifests
are not complete exported-package manifests. [Engine identities](engine-identities.json)
include the actual console and companion executable hashes.

The loader now checks the full engine build identifier, including beta status,
official build and revision, rather than only numeric `4.8.0`. The profile test
checks changed status/build/revision/patch identities and rejects unqualified
engine metadata. Aircraft, controller/dependency, solver, field and 240 Hz guards
remain strict. Unknown performance values and unqualified runway modes remain
explicit. The source gate is still `test_companions_profiles.gd`.

After preserving the completed baseline matrix, the new loader/profile/test was
copied into that baseline app. Its existing source gate refuses Godot 4.7.2 with
exactly the expected runtime-build error; pilot and solver identities match and
there are zero engine diagnostics. This [expected refusal](checks/stable-admission-expected-refusal/report.json)
has process exit 1 and is deliberately separate from passing regressions.

## Reproduction and limits

The original merged app snapshot passed all **21 companion regression groups**, with zero
engine errors and warnings. The [regression summary](regression-summary.json)
links every checked invocation. Strict source/build admission passes 43 checks;
lifecycle passes 653 checks, including 50 headless and 10 visual/audio cycles.
Recording checks pass 156 checks, including their existing bounded exact replay
cases. Home/Pause/Main shell, presentation, interpolation, pilot, observation,
terrain/traffic, sessions, manager, airspace and recording paths are covered.
The selected app source/metadata files remain unchanged across these checks.

The [production manager probe](production-120s.json) also completes all 28,800
ticks with three companions and a player, actual Club collision/lake context,
calm weather and opposite-direction seed 1. Minimum clearance is 34.567785 m;
there is no refusal, crash or simulation fault. Its checked invocation reports
zero errors/warnings. This is a headless correctness run, not a frame-cost gate.

Three visual groups initially refused this app-only copy because required
root-relative authoring JSONs were absent. The 18 exact source-bound files were
copied, fingerprinted in [the external source receipt](external-authoring-sources.json),
and all three groups passed on rerun. An observation run exited zero without
diagnostics but used the wrong harness completion marker; its corrected-marker
rerun passes. These initial fixture/harness failures remain under `checks/invalid-*`.
No source-hash checks or application code were changed to address them.

The complete lifecycle run took 67.719 s, exceeding the suite's generic 60 s
supervision deadline. A later frozen-suite invocation stopped at that deadline
without engine diagnostics. Its fixed 50+10-cycle workload now has the same 180 s
deadline used by other complete-scene checks; no assertions or cycle counts were
reduced. The [frozen rerun](checks/lifecycle-180s/report.json) passes all 653 checks
in 59.469 s, with zero errors/warnings. No same-workload 4.7 timing was measured;
these shared-host timings do not establish engine speed parity or performance.

Run from the repository root with the pinned engine, after a clean import:

```bash
python tools/godot/run_checked.py --timeout 1800 \
  --require-text "companion pilot qualification:" -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/ai-companions/pilot_probe.gd" -- \
  --out="$PWD/tmp/gdu03-companions-new"
```

The output directory must be new. The probe now reports its actual engine in the
generated README; no fixture, scenario, duration, seed or acceptance gate changed.
The seed is 20261020; controller sampling remains 60 Hz with commands held across
four 240 Hz physics ticks. Use separate project copies and user-data directories
for a baseline comparison. Do not use concurrent runs for performance claims.

The matrix uses normalized Club surfaces and a stationary player reference,
without the full collision/lake inventory or scripted moving encounters.
[Existing qualification methods and limits](../../../ai-companions/pilot/README.md)
remain applicable. [Stopped-traffic](../../../ai-companions/AFC-04-R7/README.md)
and [terrain/traffic](../../../ai-companions/AFC-04-R8/README.md) verification
remain separate from this circuit qualification. General containment, terrain
safety, conflicting multiple threats, long multi-seed endurance, runway activities,
finite-fuel recovery, rendered/platform packages, target 1080p frame cost and
independent RC pilot/physical validation remain open. The experimental 1–3 roster
is not a newly qualified performance ceiling.

The first beta import exited zero but emitted 12 `get_multiple_md5` file-access
errors. An overlapping matrix was stopped, and a later matrix after that failed
import was also stopped; both are invalid qualification attempts. Their checked
receipts are retained under `checks/invalid-*`. A subsequent clean beta import
passed with zero errors/warnings before the accepted beta matrix began. The
baseline import also passed cleanly. No invalid attempt establishes a pass.

A later whole-app overlay encountered an unrelated concurrent merge with conflict
markers in Stik presentation sources and generated records. Its import also
reported 12 file-access errors, without a concurrent process in that app copy.
`checks/invalid-conflicted-overlay-import` retains this excluded attempt. The
earlier import errors therefore cannot be attributed solely to process overlap;
fresh-import/cache behavior remains an engine-upgrade investigation, independent
of the accepted circuit flights after their clean import.
