# Native accepted-flight audio: Turbo Lumber

2026-10-26. One production `main.tscn` flight with the installed finite-pack
Turbo Lumber completes the research FT-card-v5 takeoff, climb, approach, flare
and straight-ahead terrain rollout without a staged landing, reset, fault or
crash. It lands beyond the runway; this is not a runway-return circuit. The
advanced experimental wheel operator remains disabled. These observations
qualify this capture, not the fleet, aircraft realism or a new contact solver.

The original [capture report](turbo-lumber-evolution.json),
[analysis](turbo-lumber-evolution.analysis.json) and [log](turbo-lumber-evolution.log)
remain unchanged. Actual driver is WASAPI, stereo PCM16 at 48 kHz: 3,163,136
frames (65.8987 s), against 65.9026 s capture wall time and 65.7333 accepted
simulation seconds. Both Master and Soundscape captures report zero discarded
frames; the frame-clock difference is 187 frames / 3.896 ms. This is a capture
clock proxy, not speaker/device output latency. All 44 selected source hashes
match before/after capture. The engine is official Godot 4.8-beta1.

Observed liftoff, touchdown and rollout satisfy the per-aircraft continuous
sequence checks. Captured Master sample peak is -22.5044 dBFS, with zero clipped
samples. The existing [four-times FIR peak analyzer](source/tools/audio/bench_analyze.py)
measures [estimated true peak](true-peak.json) -22.5047 dBTP, below the proposed
-1 dBTP ceiling. This is numerical mixer evidence; listening, calibrated levels,
device/buffer characterization, isolated rolling/scrape audibility and combined
worst-case audio cost remain unqualified. The Soundscape capture excludes the
separate CrashAudio bus, while Master includes the scene mix. Wheel-contact
observations alone do not prove that a hull scrape was audible.

## Wrapper correction and scope

The [first launch](launch-refusal.json) stopped before capture because its wrapper
hardcoded nine aircraft; the active catalog now returns eleven. Listing now uses
nonempty unique active IDs. After the successful capture, a second hardcoded
nine was found in full-fleet summary flags. [The original summary](fleet_summary.json)
still has its original false fleet flags. A separate [metadata correction](aggregation-correction.json)
records successful requested-aircraft scope and incomplete full-catalog coverage.
No original capture result was rewritten. The [capture-time wrapper](check_fleet_sequence.capture.py)
and [corrected current wrapper](source/tools/audio/check_fleet_sequence.py) have
different explicit hashes. Six new catalog/scope regressions plus six existing
capture-checker tests pass: [receipt](wrapper-checks.json), [log](wrapper-checks.log).
Duplicates, missing results and truthy strings cannot establish qualification.

Reproduce using the existing tools/audio README workflow, from repository root:

```powershell
python tools/audio/check_fleet_sequence.py --godot .tools/Godot_v4.8-beta1_win64_console.exe --aircraft=turbo-lumber-evolution --continuous-straight --out-dir tmp/new-native-review --wall-timeout=360 --timeout=420
```

Use a new output directory and one native probe at a time. Original raw PCM is
kept locally in ignored tmp; [its identity](pcm-identity.json) permits comparison
without adding a 12.65 MB generated recording to repository history. Native
timing is not bit-reproducible. Reports retain actual source/data identities and
accepted clocks. No target-1080p rendering, acoustic realism, human audition or
whole-plan completion is established by this headless audio run.
