# Three-aircraft circuit and menu campaign — 2026-11-20

Scope: **GOD-12-R1 / GOD-13-R1**, source/debug implementation and functional
verification. The [operating guide](../../../tools/godtest/PERFORMANCE_TOUR.md)
owns commands and capabilities; the [plan](../../plans/god-test.md#13-execution-steps-and-evidence-ledger)
owns outstanding qualification. The [companion evidence JSON](2026-11-20-performance-tour.json)
retains selected raw-artifact hashes and full lap receipts.

## Result and limits

The final three-aircraft run exited **0**. Ugly Stik, Avanti jet and Corsair each
completed normal Startup/Home/selection/loading, a position-observed clockwise
circuit enclosing the runway, Pause/Continue, Settings, Controls, lighting Apply,
Home and clean owned shutdown. All requested phases and frame streams were valid;
all three continuous frame watches completed their counter/identity checks.
The four pause/menu phases preserved ticks and physical state, then observed
healthy tick progress after resuming. No engine error, forced shutdown or reported
ObjectDB leak occurred.

This was a **Linux x86_64 headless development run**, using the GDScript reference
physics backend and official Godot 4.8-beta2 (`cafc17a19`). It establishes functional
control flow and evidence retention. GPU utilization was unavailable; process CPU
sampling was available. The suite correctly reports `data=valid`,
`coverage=complete`, `performance=not_qualified`, `hardware_qualified=false`.
Rendered FPS, native physics performance, input latency and target-hardware
acceptance are not established by this run.

| Aircraft | Runtime wall s | Accepted lap simulated s | Signed sweep | Accepted lap AGL range | Flight/menu coverage |
| --- | ---: | ---: | ---: | ---: | --- |
| Ugly Stik 60 | 136.146 | 42.583 | 360.029° | 51.442–60.417 m | complete |
| Avanti jet | 221.675 | 114.633 | 360.035° | 52.525–66.657 m | complete |
| F4U Corsair 250 | 207.732 | 97.750 | 360.024° | 20.033–48.255 m | complete |

All laps covered four quadrants and stayed within their recorded annulus outside
the runway. Completion uses accepted north/east positions, not heading rotation.
The experimental pilot uses ordinary controls; aircraft laws and fixed 240 Hz
physics are unchanged. Faster aircraft use larger radius targets. These are orbit
circuits, not takeoff/landing or calibrated pilot acceptance. The Corsair came
close to the 20 m lower AGL bound; target-host repeatability remains a qualification
item. Startup/loading target misses for all three aircraft remain in the report;
those headless observations do not establish a regression on any target GPU.
No numerical FPS improvement is claimed.

## Executed command and frozen inputs

```sh
python3 tools/godtest/godtest.py performance-tour --headless --repeats 1 \
  --sample-s 3 --timeout-s 600 --phase-timeout-s 240 \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --out tmp/three-aircraft-functional-final
```

This smoke uses three-second active dwells and the ordinary five-second pause.
The documented baseline uses three independent repeats. Target hardware must use
a rendered launch and the required native backend; headless callback intervals
are deliberately not promoted to a rendered baseline.

The run froze the working tree based on `c2f185294f6b8cad8ef71cb060b129a27c2277f9` before publication.
Executed Python/GDScript and authoring bytes match implementation commit
[`89754dd02733`](https://github.com/bultodepapas/OpenRCsimulator/commit/89754dd0273330d438cc152c7a7e2eca30088166).
Only the two tool-guide Markdown files were subsequently clarified. Publication
reapplied the local sparse checkout while flights used the independent snapshot;
required authoring files were restored afterward. Frozen app, imports and engine
bytes remained unchanged for every case. This is a per-file verified copy, not an
atomic Git/filesystem snapshot or a proven cold cache.

- Source-content digest: `b93082315199e47b90166fe6e4474077a1707f3c35c265687e92f41f734cbc1c`.
- Prepared-import digest: `7436bf2e48b599950a1c7a437978e2c3a7fae76e973b2299822768a833cd8a87`.
- Raw output: ignored `tmp/three-aircraft-functional-final/`. Each child retains
  manifests, source receipt, runtime/events/trajectory, verified frame stream,
  CPU/GPU observations, frame watch and engine/execution logs.
- Selected hashes are in the companion JSON. Preserve the complete frozen source
  and import directory when independently rebuilding the suite report.

## Verification performed

| Check | Result | Scope |
| --- | ---: | --- |
| GOD TEST Python fixtures | 104 passed | Manifests, stream/report integrity, sampler failures, isolation, ownership, resume and exact aircraft/display/source/engine/host checks |
| Existing frame-watch fixtures | 31 passed | Continuous cursor/identity/counter and cooperative stop behavior |
| Queue adapter completeness | 5 passed | Admission/tool routing |
| Queue contracts | 21 passed | Existing admission contracts |
| Runway-circuit checked Godot fixture | 0 failed; exit 0 | Full vs partial sweeps, quadrant wrap, corridor/altitude/time and reversal cases |
| Menu-safety checked Godot fixture | 0 failed; exit 0 | Pause/session invariants, resumed health and product preference path |
| Startup-guard checked Godot fixture | 0 failed; exit 0 | Refused profile, missing/non-debug/wrong observer, cleanup and normal route |
| Actual Startup negative smoke | expected exit 31 | Refusal marker, zero engine errors/warnings and no preference files written |
| Final application tour | 3 of 3 complete; exit 0 | Actual source application, accepted physical flight, menus, watch and shutdown |

The three checked success fixtures have zero engine errors/warnings and their
required markers. The negative Startup check intentionally exits nonzero; it is
refusal evidence, not a successful benchmark. Python test total: **161**.
These local checks do not establish that hosted macOS or Windows jobs ran. The new
[portable tooling workflow](../../../.github/workflows/godtest-tooling.yml)
configures Ubuntu 24.04, Windows 2025 and macOS 15 Python fixtures and a tour-plan
check. Hosted CI does not replace real GPU measurements.

## Corrections made and remaining qualification

The benchmark previously seeded the wrong display-settings filename. It now uses
`settings.cfg.display` and records applied display state after Home, at each phase
completion and before shutdown. Refused benchmark setup now exits before normal
profile access or Home. Exact-axis quadrant wrapping and full-circle rounding
have regressions without admitting a partial arc. Late failures after menus,
missing authoring inputs, incomplete monitor coverage and unknown ownership are
explicit failures rather than successful screens.

Resume preserves the full roster and prior attempts, verifies shutdown, and binds
retries to frozen source, engine, observers and host/boot identity. GPU monitoring
rechecks raw utilization, device identity and timing; absent counters or changed
observer code cannot become zero-load or complete results.

Real acceptance remains open on the actual **MacBook, Linux GPU host and Windows
host**. Use the Apple Silicon Retina native-panel exception and the recorded
1080p desktop configuration. Verify native physics artifacts, actual renderer and
visible window, device identity, power/thermal state and monitoring availability.
Intel utilization and Windows AMD utilization are unsupported by this sampler;
an unavailable channel prevents a complete rendered screen.

Keep repeated per-aircraft/per-phase results and a matched baseline/candidate on
the same physical host before calling an optimization successful. Release exports,
drawable-pixel/physical presentation validation and a statistical whole-flight
regression gate remain separate from this source/debug campaign.
