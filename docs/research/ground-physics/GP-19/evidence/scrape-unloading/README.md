# Scrape amplitude during unloading

2026-10-26. Accepted hull scrape grains now use the authored amplitude
`0.28 * min(sqrt(P / 100 W), 1)` from instantaneous dissipated friction power.
The former `0.06 + 0.22 * level` approached a finite gain of 0.06 as a loaded
contact unloaded to zero, then switched to silence. The new envelope tends
continuously to silence and retains the same maximum. The existing player's
quiet-signal cutoff remains. This is a presentation mapping, not measured
acoustic efficiency, sound pressure or integrated heat.

Only accepted-grain gain changes. Legacy impact/touch envelopes, assets, voices,
timing, cancellation and the simulation remain unchanged. The original 100 W
reference is an authored normalization; no material calibration is claimed.

The extended scheduling/pool test passes **60 checks** on the installed source;
the existing legacy audio suite passes **12 checks**. Both checked runs complete
with warnings treated as errors and zero engine diagnostics. The baseline fails
the two new limiting-response checks and passes its other 58 checks, showing
that the tests detect the old finite floor. The draft passes all 60. These
counts are separate executions, not 192 unique tests. No native listening or
audibility result follows from the Dummy-driver spy.

Reproduce with the checked runner and `res://tests/test_hull_scrape_audio.gd`
and `res://tests/test_crash_audio.gd`. `promotion.json` pins old/new source hashes;
`checks/` keeps original runner receipts and logs. Paths embedded in baseline
development harnesses refer to their original ignored workspace. The retained
baseline source suffices to reproduce the two failures with the installed test
retargeted to it. `manifest.json` binds this bounded cohort; `transport.json`
checks its exact bytes through a fresh disposable Git clone with autocrlf.
Earlier native flight capture remains evidence of its recorded source version,
not this changed gain or isolated hull-scrape output.
