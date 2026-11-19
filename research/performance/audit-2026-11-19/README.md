# Reproduce the 2026-11-19 performance audit

Report: [CPU/GPU audit](../../../docs/research/performance-audit-2026-11-19/README.md).
Audited source: `894357de83762ff6e0fdc47b0024e60f3d8286b7`.

These are isolated **baseline observations**, including counterexamples to current
behavior. A successful run means the recorded baseline was reproduced; it does
not mean the reported bugs are fixed or that GPU/flight performance is qualified.

## Run

Use Python 3.10+ and the exact official Godot 4.8-beta2 Linux x86_64 binary pinned
by [app/get-godot.sh](../../../app/get-godot.sh). The runner checks its SHA-512 and
every source dependency before launch. No third-party Python packages are needed.
The full production asset import and native library are not needed for this fixture.

Follow the [test queue/admission rules](../../../tools/testqueue/README.md) for your
host. The audit used a local unenrolled host with no `OPENRC_TESTPOOL_CONFIG` and
the existing [checked launcher](../../../tools/godot/README.md). Enrolled/shared
hosts retain their queue/session ownership requirements; this recipe is not a bypass.

From the repository root, with a new output directory:

```bash
python3 research/performance/audit-2026-11-19/run.py \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --out /absolute/path/to/new-audit-output
```

The runner copies the manifest's exact dependency closure to that new directory,
creates a minimal headless project, and runs these sequential checks through
`tools/godot/run_checked.py`:

1. Import/parse the isolated fixture.
2. Run the unchanged `test_resource_event_step.gd` control: **54 checks, 0 failed**.
3. Run `event_probe.gd`: mixed interior/endpoint crossing, tolerance comparator and
   six permutations, plus the rejected packed-array copying lead.
4. Run `calibration_probe.gd`: UI/window size identity, isolated stale rejection,
   incomplete-neutral retry behavior, quantile policy and pure Retina scale math.

Each engine invocation has a 60-second timeout. Reports/logs and a parsed
`audit_results.json` remain under the supplied output directory. The runner
checks log hashes and exact completion markers, then checks the expected baseline
observations explicitly. It refuses existing output directories and changed source
hashes; it does not overwrite an app profile or launch a player scene.

## Evidence boundaries

- `event_probe.gd` calls the real solver. Its 1/240-second mixed-crossing case uses
  synthetic valid surfaces. The comparator case uses an admitted 4e-12-second
  interval and disabling transition flags. Neither establishes a stock-aircraft
  occurrence. The scenery comparator is separately source/mathematically reviewed.
- `calibration_probe.gd` uses actual pure policy functions and headless
  `Window`/`UiScale` behavior. Its stored 4K verdict and timing samples are synthetic.
  The Retina calculation is capability-table math, not Mac/GPU execution.
- The calibrator's incomplete/no-retry and exact-5%-tail behavior are intentional
  policy tradeoffs, not unconditional regression fixes.
- Probe exit status indicates completed collection. The runner's final status
  means baseline observations matched; it is not a future corrected-solver oracle.
- Linux binary identity is deliberately strict. A different OS/binary or corrected
  source needs a new explicitly scoped run and manifest; do not edit hashes to
  relabel changed evidence as this baseline.

## Files

| File | Role |
| --- | --- |
| [run.py](run.py) | Isolated fixture/checked-run orchestration and observation validation |
| [fixture_sources.json](fixture_sources.json) | Audited source SHA-256 values and pinned engine SHA-512 |
| [event_probe.gd](event_probe.gd) | Solver counterexamples and packed-array alias observation |
| [calibration_probe.gd](calibration_probe.gd) | Calibration identity/policy observations |

The report's compact evidence is derived from these results; no benchmark or
physical-flight validation is implied by the retained logs.
