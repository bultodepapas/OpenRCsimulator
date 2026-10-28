# FL-05 — Exact-replay marker debrief

2026-10-28 · Implemented offline analysis. [Operating contract and commands](../../../FLIGHT-LOGGING.md#debrief-marked-maneuvers). [MOONSHOT](../../../../MOONSHOT.md#6-first-engineering-transformation-flight-intelligence-from-verified-flight-records) owns the proposed flight-intelligence sequence; this evidence covers only its first infrastructure slice.

## Result

`debrief LOG --out NEWDIR` reuses the existing exact-replay command, then produces
descriptive F11 marker windows. It retains the CSV, engine report/log, source
and solver identities, metadata/events, and artifact hashes. A pilot can now
inspect a marked part of a flight without manually joining event ticks to the
whole-flight summary. There is no new recorder, simulation, plotter or campaign
runner, and no runtime/UI/physics/data/golden change.

State endpoints include both boundaries; command/servo/load intervals exclude
the left boundary. This preserves the recorded command's `k−1→k` meaning and
shares only the accepted state between adjacent windows. Same-tick marks retain
ordered labels. Prefix/tail and zero-duration windows remain explicit. Altitude
uses the local NED datum, not terrain-relative height. Statistics describe sampled
values, not an inferred maneuver, causal diagnosis, physical truth or skill grade.

The command refuses incomplete or candidate replay, solver/source mismatches,
omitted events, invalid event bounds/order and inconsistent CSV/report timing or
counts. A review identified that the existing Godot inspector can admit a crafted
non-marker event one tick beyond the final sample; the new debrief rejects all
out-of-range events before grouping markers. The underlying exporter was not
changed in this slice. Failed reduction leaves diagnostic replay artifacts and
does not publish a successful debrief.

## Verification

The compact [verification receipt](verification.json) records source SHA-256s,
engine/host identity, fixture results, final debrief artifact hashes and negative
controls. Source inspection began at `96287766296b3fef6a37dcd4cc3847d7efbe9f19`;
the shared tree advanced through `7291d9733` and `5af16fdcf` during work. File
hashes identify the tested implementation more precisely than a commit alone.

| Check | Observed result | Scope |
| --- | --- | --- |
| Existing `app/tests/test_flight_log.gd` through checked runner | **3,247 checks, zero failures**, six aircraft, 260 stepped ticks each | Recorder remains read-only, exact replay, lifecycle, bounds and corrupted-file refusals. Aircraft/control tape is a software fixture. |
| Final Python flight-log suite | **27 tests pass** | Existing reducers/CLI plus actual debrief CLI with mocked engine outputs: window timing, zero/one/duplicate/end markers, mid-flight tick 1200, metadata/hashes, candidate/source/solver refusals, omitted events, count/timestep drift and memory scaling. |
| Actual pinned-engine `debrief` on six newly recorded fixtures | **6/6 complete exact replays**, `solver_changed=false`; 261 CSV rows each | Stik, Extra, P-51, Avanti, Turbo Lumber Evolution and two-stroke glow Stik. Every fixture has a mark at tick 56: prefix `[0,56]`, tail `[56,260]`; 56+204 command intervals cover all 260 steps. |
| Actual-engine damaged-log controls | Truncated and bit-flipped copies refused; no `debrief.json` | Uses the existing fixture's mutations copied to disposable `.orfl` paths. No accepted log is modified. |
| Fresh checkout path check | **27 tests pass** in a fresh sparse local clone with the final tool/test files overlaid | Checks Python CLI/output-path behavior independently of the original working directory. No engine/import or full-product qualification is inferred. |
| Synthetic reducer allocation scaling | 1,000 rows: **1,362,353 B** peak; 20,000 rows: **2,138,303 B** peak in the specialist run | Twentyfold row count, fixed marker count. `tracemalloc` begins after CSV creation; includes reduction/hashing, not Godot or total process RSS. Test permits <4 MiB and <1 MiB growth. |

The allocation check is a bounded-memory characterization, not a throughput
speedup. It exercises a synthetic analysis fixture, not physical flight. This
development host also had unrelated work running, so no target-host timing, FPS,
input latency or performance improvement is claimed. Marker count is bounded by
the export's 10,000-event limit; memory can grow with marker count. The reducer
keeps accumulators rather than all trajectory rows, but exact replay still costs
the original solver's work and the existing CSV validation makes streaming passes.

## Reproduce

Use a fresh output root, import the project if starting from a clean checkout,
and select the repository's pinned Godot. Canonical tool contracts remain in the
[tool index](../../../tools/README.md), [checked-runner guide](../../../../tools/godot/README.md)
and [flight-log manual](../../../FLIGHT-LOGGING.md).

```bash
python3 -m unittest discover -s tools/flight_log -p 'test_*.py'
python3 tools/godot/run_checked.py --timeout 300 \
  --out-dir tmp/fl05-new/checks --label flight-log-baseline -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script res://tests/test_flight_log.gd -- \
  --out="$PWD/tmp/fl05-new/logs"

for aircraft in jensen_ugly_stik_60 gp_extra_300s_60 p51d_mustang_120 \
  sebart_avanti_s_a200 turbo_lumber_evolution stik_glow_61fx_2t; do
  python3 tools/flight_log/flight_log.py debrief \
    "tmp/fl05-new/logs/$aircraft.orfl" \
    --out "tmp/fl05-new/debrief/$aircraft" \
    --godot "$(app/get-godot.sh)" --timeout 120 || exit
done
```

Original raw outputs remain under ignored `tmp/moonshot-fl05-20261028/`, including
the retained complete `.orfl` baseline files, checked-runner receipts, per-aircraft
CSV/replay/debrief outputs and final Python test log. They are reproducible with
the commands above and recorded source/engine identities. The committed receipt
keeps hashes and compact results; no images or large raw logs were added.

No full `app/test.sh` or visual capture suite was needed for this Python-only
analysis change. The focused real-engine replay fixture verifies the relevant
production seam. Real pilot recordings, long-flight engine throughput, desktop
debrief UI, teaching efficacy, candidate branching and physical calibration remain
separate work. A successful synthetic debrief does not close those gates.
