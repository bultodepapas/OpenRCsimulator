# HELI ground-contact performance candidate

The disposable candidate reuses a single `GroundContact.surface_at` result for a skid's flat-pad test and friction lookup within the same RK-stage call. It adds no state and keeps the existing law, guards, and finite checks. No value is cached across stages or ticks.

The benchmark did not show a stable, meaningful speedup, so the candidate is **not integrated**. Production physics and Session files were not changed for this experiment.

## Method

Godot 4.7.2 at 240 Hz; each sample times the complete `session.sim.step()` call. The existing `Session._on_stepped` observer remains active; no additional tick observer or control trace recorder was used. Scenario setup and spool pre-roll are outside the timing samples. Each regime ran A then B, followed by B then A; every pair restored the same checkpoint. The harness checks tick acceptance and captures state, aux, continuous state, and shaft phase after each measured tick.

Run 1 measured 2,400 ticks/variant for stopped ground, 5,760 for the full 12 s soft spool, 2,400 for governed ground, and 2,400 airborne. Run 2 repeated those counts. Every A/B paired byte stream matched in all four channels: 8 of 8 pairs per run. The copied candidate-specific bristle test passed 15/15 checks.

Run 1's harness note says it overlapped root cycle evidence. Root later confirmed the 30-cycle batch had already finished; the 240/480/960 refinement was still running. Run 2 overlapped two other Godot processes used by `parse_all.py`. Neither run had isolated host load, so timings are development evidence only.

## Timing samples

Values are pooled over the two AB/BA pairs per run; p50 and p95 use nearest-rank percentiles. A is the copied baseline; B is the copied candidate.

| Regime | Run | A ticks; p50 / p95 µs | B ticks; p50 / p95 µs | Δ p50 / p95 µs |
|---|---:|---:|---:|---:|
| stoppedground | 1 | 2400; 1604 / 2626 | 2400; 1577 / 2577 | -27 / -49 |
| stoppedground | 2 | 2400; 2333 / 2816 | 2400; 2391 / 3113 | +58 / +297 |
| 12ssoftspool | 1 | 5760; 2521 / 3809 | 5760; 2045 / 3526 | -476 / -283 |
| 12ssoftspool | 2 | 5760; 2555 / 3212 | 5760; 2547 / 3195 | -8 / -17 |
| governedground | 1 | 2400; 2574 / 3218 | 2400; 1967 / 3172 | -607 / -46 |
| governedground | 2 | 2400; 2608 / 3159 | 2400; 2607 / 3076 | -1 / -83 |
| legacyairbornehover | 1 | 2400; 1116 / 1658 | 2400; 1396 / 1854 | +280 / +196 |
| legacyairbornehover | 2 | 2400; 1376 / 1677 | 2400; 1405 / 1653 | +29 / -24 |

Run 1 suggested large ground-only gains in spool and governed cases; the follow-up reduced these to approximately zero and reversed stopped-ground direction. The airborne control, where the bristle path is inactive, also varied in both directions. The paired byte evidence confirms behavior parity, but the timing deltas are host-load noise, not a reliable performance gain.

## Reproduction files

- [ABBA Godot harness](../../../../../research/helicopter/ground_start/contact_abba.gd) and [candidate skid test](../../../../../research/helicopter/ground_start/contact_candidate_test.gd). Run them against a disposable app copy containing the two candidate files; see [summarizer](../../../../../research/helicopter/ground_start/summarize_contact_abba.py).
- [Candidate diff](candidate.diff) and [source hashes](source-hashes.json). Each run's `performance.json` carries all input hashes, source fingerprint, exact tick counts, and parity checks.
- [Run 1 raw samples](run-1/samples_raw_godot.json), [CSV](run-1/samples.csv), [JSON](run-1/samples.json), and [summary](run-1/performance.json).
- [Run 2 raw samples](run-2/samples_raw_godot.json), [CSV](run-2/samples.csv), [JSON](run-2/samples.json), and [summary](run-2/performance.json).
- [Candidate test result](candidate-test.log), [parse result](candidate-parse.log), and the [initial harness failure diagnostic](diagnostics/runtime_failure_001.md).

The diff is review evidence. To repeat the experiment, copy `app` to a disposable project, copy `skid_contact.gd` and `helicopter_flight_session.gd` to the candidate filenames recorded in the diff, and apply the two shown changes there. Copy both research GDScripts into `project/research/helicopter/ground_start/`, then run:

```powershell
& .tools\Godot_v4.7.2-stable_win64_console.exe --headless --path tmp\heli-ground-contact-candidate-20261014\project --script res://research/helicopter/ground_start/contact_abba.gd -- --parse-only
& .tools\Godot_v4.7.2-stable_win64_console.exe --headless --path tmp\heli-ground-contact-candidate-20261014\project --script res://research/helicopter/ground_start/contact_abba.gd
& .tools\Godot_v4.7.2-stable_win64_console.exe --headless --path tmp\heli-ground-contact-candidate-20261014\project --script res://research/helicopter/ground_start/contact_candidate_test.gd
python research\helicopter\ground_start\summarize_contact_abba.py --project tmp\heli-ground-contact-candidate-20261014\project --out docs\research\helicopter\HELI-20\optimization\run-2
```

Save the generated `ground_contact_abba_raw.json` under the intended run directory before starting another run; the harness writes that same project-local filename each time.

This experiment is not H15 qualification and does not establish physical validity.
