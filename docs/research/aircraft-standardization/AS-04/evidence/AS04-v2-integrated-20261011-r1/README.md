# AS-04 verification run AS04-v2-integrated-20261011-r1

Status: FAIL.

- Baseline: `C:\DEVELOPMENT\OpenRCsimulator\.tools\as-baseline\app` (run times [8.613, 8.434])
- Candidate: `C:\DEVELOPMENT\OpenRCsimulator\.tools\as-integration\app` (run times [8.767, 8.922])
- Cases: 8 compared; 8 exact normalized-model matches; 8 exact flight-trace matches.
- Godot: `C:\DEVELOPMENT\OpenRCsimulator\.tools\Godot_v4.7.2-stable_win64_console.exe` SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Driver SHA-256: `18bebd1ea0bc643189d63f750d1bba6e3a793dc9c4c912641a28e78965fed9e9`.
- Timing: 2 paired rounds with alternating process order; per-aircraft validation-load and steady `Simulation.step()` p50/p95 are in `comparison.json` (descriptive only, no timing gate).
- Comparator self-check: deliberate model-value and state-byte changes were detected before app runs.
- Retained logs: one `.log` and raw `.json` probe per app/round; per-run provenance includes source manifests.

Failures:
- candidate_r1: app source changed while the probe was running
- candidate: source manifest changed between alternating measurement runs
