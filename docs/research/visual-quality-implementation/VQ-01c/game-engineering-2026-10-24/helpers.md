# VQ-01c — allocation and repeated-work follow-up, 2026-10-24

`math3d.q_rotate()` now allocates only its result instead of seven packed arrays,
with the same float64 expression grouping. `GlowFlight.point()` computes the fuel
feed target once per stage when its existing body/rotor reuse condition makes it
invariant. The fallback, solver iterations, validation and telemetry are unchanged.
`FlightAudio._process()` skips contact snapshots while paused; ground-audio pause
and resume handling still runs. No assets, graphics settings, control laws or
physical equations were simplified.

[Method measurements and source identities](helper-methods.json) retain nine
alternating batches, actual before/candidate scripts and exact-output checks.
Median local costs (microseconds; not frame-time savings):

| Work | Before | After |
| --- | ---: | ---: |
| Quaternion rotation, fixed input, 10,000 calls/batch | 3.4221 | 0.7894 |
| 55AX full Glow evaluate, 100 calls/batch | 366.37 | 341.39 |
| FS64V full Glow evaluate | 353.05 | 327.49 |
| 61FX full Glow evaluate | 581.37 | 555.84 |
| Extra non-feed control | 370.69 | 372.32 |

Paused audio saves one contact snapshot per paused render frame; no timing or
memory-size saving was measured. These are bounded implementation improvements,
not evidence of increased whole-game FPS.

## Native results

[All native runs, identities, counters and raw artifact hashes](helper-native-comparison.json):
Ryzen 9 5900X / RTX 3090, Godot 4.7.2, 1920x1080 Compatibility, 4x MSAA,
60 Hz VSync, Electrical Storm, live airborne simulation, Dummy audio, 10 s warmup
and 60 s wall-clock collection. Both builds use the same frozen application,
including paused-audio code; embedded source maps differ only in math3d and Glow
flight. Collection diagnostics were enabled equally. Two runs per aircraft:

| Aircraft/build | FPS | p95 ms | p99 ms |
| --- | --- | --- | --- |
| P-51 before | 59.85 / 59.95 | 18.139 / 17.791 | 22.952 / 20.570 |
| P-51 after | 59.25 / 60.00 | 18.821 / 18.109 | 26.761 / 20.122 |
| 55AX before | 54.39 / 57.53 | 24.971 / 21.107 | 33.967 / 31.445 |
| 55AX after | 42.46 / 58.49 | 64.023 / 20.355 | 79.050 / 28.346 |

**No reliable FPS, frame-pacing, whole-process CPU, memory or latency gain is
established.** The adverse 55AX candidate run remains included: it ended focused, unpaused
and fault-free but advanced only 13,536 ticks, versus about 14,400 in other runs.
Focus/pause history was not collected; end state does not prove continuous focus. Its stalls are not attributed to the change or to another process.
Later original-code reversals were contaminated: C: reached zero free space,
available RAM fell to 7.39 GiB, and another rendered game overlapped the P-51
reversal. They cannot settle causation. The historical P-51 ~29 FPS capture is
not a valid baseline for this change. One P-51 run in each primary campaign
reported the same 23 audio ObjectDB instances at shutdown; no leak fix is claimed.

## Verification and limits

- 10,021 direct-source rotation cases matched output bytes, including nonfinite
  and boundary inputs. Permanent math tests retain the old helper expression.
  Signed zero and subnormal fixtures are constructed from bytes with a positive
  control; the strengthened suite and direct-source comparison passed again.
- 103 full-result Glow comparisons passed across 55AX, FS64V, 61FX and Extra,
  including invalid states and stale prepared identities, with unchanged owners.
  The first probe failed its signed-zero comparator control; that artifact is
  retained. The corrected comparator/control passed. Feed-line cases were skipped
  because none of these installations has that module.
- All nine catalog airplanes matched numeric fingerprints for 240 warmup plus
  1,200 maneuver ticks each. The two runs used one path sequentially, with source
  replacement and hash verification between them; headless reports do not embed
  those source hashes. This is numeric parity on sampled sessions, not physical
  validation or exact flight-log replay.
- Ten focused engine suites passed 2,601 checks, including four unchanged golden
  flights, stage reuse, coupling, fuel feed, trace, simulation and audio. The
  float64 guard passed. The transcendental guard still flags the pre-existing
  `mass_inventory.gd:14` constant `pow(2.0, -1022.0)` from commit `7dedb38f2`;
  its injection self-test passes. The full repository suite was not run.
- The nine retained companion tapes replayed to byte-identical CSVs (18,474
  total rows per side); the generated solver rebind receipt and pin were retained.
  The solver qualification gate passes. Broader companion profile validation
  fails on the pre-existing pilot-controller hash mismatch, reproduced with both
  the accepted and optimized solvers. That safeguard was not bypassed.
- Nine Python companion rebind tooling tests passed. The tool can now put its
  disposable copies on D: with `--workspace-root`, preserving qualification gates.

[Actual gameplay checks](helper-gameplay.json) covered all nine airplanes: delivered
roll/pitch/throttle, more than 720 simulation ticks, chase/pilot cameras, pause,
resume and Home. Eight complete workflows used 1920x1080; the 61FX completed its
workflow at 1920x1061 and a separate 1080p input/chase retest was interrupted.
Rendered P-51, Corsair, Stik, 61FX and Turbo Lumber images were inspected with no
obvious missing mesh or HUD failure. This was a bounded software smoke test, not
pixel equivalence or pilot acceptance. No completed pass showed a flight fault
or crash. Initial viewport mismatch and external-process interruptions remain in
the receipts; other sessions were never stopped. The optional landscape change
was not reached. No images were added to the repository.

Raw local evidence is under `D:/OpenRCsimulator-evidence/optimization-20261024-code`
and `optimization-20261024-baseline`; it is not a durable release bundle. Other
hardware/platforms, long-session stability, VRAM and input-to-photon latency remain
unqualified. Method timing and native capture are kept separate, following
Godot's [profiling](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/the_profiler.html)
and [measurement guidance](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html).

Final Good Enemy review found no significant correctness issue in the two
helpers or paused-audio guard. It upheld the limited method-level conclusion,
with no whole-game FPS/frame-pacing or long-session qualification.
