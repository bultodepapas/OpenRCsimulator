# R11: identified session cost on the development host

2026-10-14. All six runs in [verification.json](verification.json) complete with unchanged solver identities, identical aircraft/field bytes and exact full-checkpoint restoration. This is a measured cost result, **not a passing performance gate**. Observed wall-clock values for both old and corrected models exceed 500 microseconds; concurrent work prevents a quiet-host acceptance claim. No speedup, target-machine qualification or physical-accuracy claim follows.

## Method and identity

Windows x86_64, AMD Ryzen 9 5900X, 24 logical CPUs, official Godot 4.7.2 `ed1daf0bf`. The pinned executable SHA-256 is `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. Six fresh measurement processes ran sequentially. A later process inspection found a stale WSL snapshot/hash job that had remained active despite the requested pause. Its interference is unbounded; these are diagnostic wall-clock measurements, not isolated-host performance qualification. The stale job was stopped after discovery. Each regime has one separately reported first pass of 480 ticks, then three measured repetitions of 480 ticks from the same full checkpoint. Total: 34,560 measured ticks and 11,520 first-pass ticks; no partial runs. Timing uses individual integer-microsecond wall-clock intervals, not batch-average percentiles.

The measured call is `FlightSession.sim.step()`, including its synchronous session subscribers. The live `_physics_process` callback, input collection, rendering and optional recorder are excluded. Full checkpoint hashes are verified before each repetition and at each endpoint, outside the timed interval. Each session is freshly prepared for its own physics law; this is a workload comparison, not a same-state isolated-kernel attribution experiment.

Before solver: `f2cd23dd5dd04af0ff51547f45c2ceaea23c05fbd03d59541dcac949dd4bd26e` ([R00 identity](../../R00/baseline-identity.json), [retained solver/data subset](before-solver-source.tar.gz), [subset manifest](before-solver-source.json)). Corrected solver: `e987ea81c90e32f7400eae386c02ded31e05de03e6b7205bcd035c66a1efb1a9` ([retained source](../../R05/glow-contact-20261014/candidate-02-solver-source.tar.gz)). The two aircraft files match across versions. Each raw report identifies aircraft, field, source, harness, weather, engine and host.

Airborne fixtures start at 1,000 m; runway starts use the field threshold. `stall` imposes 15 degrees initial incidence; `high_rate` imposes 22 degrees with p=2.2 and r=1.2 rad/s, leaving propulsion powered. These labels identify synthetic workloads, not validated stalls or spins. The column run uses the explicit dry ISA mode; reference runs use the uniform reference atmosphere.

## Repeated-pass results

Values are **p50 / p95, microseconds per tick**. Raw reports also retain every tick, mean, p99, maximum, first-pass distribution and checkpoint hashes.

| Aircraft | Regime | Before, reference | Corrected, reference | Corrected, column |
|---|---|---:|---:|---:|
| Stik | trim | 784 / 866 | 1018 / 1075 | 1110 / 1239 |
| Stik | stall | 806 / 924 | 1009 / 1077 | 1105 / 1170 |
| Stik | high_rate | 833 / 1018 | 915 / 1236 | 1058 / 1410 |
| Stik | runway | 1584 / 1675 | 1731 / 1826 | 1598 / 1937 |
| Jet | trim | 1097 / 1158 | 1262 / 1354 | 1213 / 1491 |
| Jet | stall | 1026 / 1201 | 1286 / 1352 | 1220 / 1501 |
| Jet | high_rate | 956 / 1164 | 1185 / 1595 | 1446 / 1798 |
| Jet | runway | 1744 / 1832 | 1962 / 2047 | 1806 / 1987 |

Reports: [old Stik](before-stik-reference.json), [corrected Stik](after-stik-reference.json), [Stik column](after-stik-column.json), [old Jet](before-jet-reference.json), [corrected Jet](after-jet-reference.json), [Jet column](after-jet-column.json). The observed corrected p50 is 915–1,962 microseconds in these fixtures. Every repeated-pass mean and median exceeds 500 microseconds. Staying within a 4.167 ms tick period is not the stricter 500 microsecond budget, nor a rendered-frame guarantee.

First process preparation takes 165–294 ms; subsequent preparations take 29–53 ms. Preparation includes construction, setup, field selection, altitude selection and reset, but excludes process startup and preloaded-script compilation. These are first-use versus repeated-use measurements; OS caches were not flushed. The fixed process/regime order and host scheduling limit causal before/after comparisons. Do not attribute every difference to one changed equation or infer that column atmosphere is cheaper from a single row.

Godot retained static-memory deltas are 656 bytes per Stik repetition and 664 bytes per Jet repetition. These are endpoint deltas, not allocation counts or evidence of a leak. The process peak is monotonic; it cannot be read as a separate per-sample peak. Allocation traffic, kernel attribution, recording overhead, additional family/event workloads and accepted target-machine qualification remain open under R11/Gate P.

## Reproduction and first attempt

The frozen [harness](measure_cost.gd) and [runner](run_cost.py) are retained beside their results. With matching immutable app copies, run `python run_cost.py --godot <pinned-executable> --before <old-app> --after <corrected-app> --out <fresh-directory> --ticks 480 --samples 3 --preparations 3`. The canonical authoring copies are in [research/remediation](../../../../../../research/physics-audit-2026-10-14/remediation/run_cost.py).

The [first batch](../session-cost-20261014/verification.json) also completed but mixed first-use and repeated-use samples and checked numeric endpoints without the complete restored checkpoint. Its raw results and original instrument remain available. This second batch addresses those measurement limitations; the first batch is not silently substituted for a stronger gate.
