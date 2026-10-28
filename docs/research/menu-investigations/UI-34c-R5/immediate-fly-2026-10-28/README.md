# UI-34c / DT-11a: immediate Fly preparation overlap

2026-10-28. **Adopted for the measured loading route.** Five alternating native 1080p
pairs reduce median first click-to-ready **3.789 → 3.531 s (6.8%)**. Every pair improves
(5.0–11.0%). Warm readiness changes **1.480 → 1.503 s (+1.6%)**, within the observed
run variation. This is a loading scheduling change; aircraft data and physics are unchanged.

## Implementation and transaction boundary

Main validates launch options and starts a detached FlightSession before building the
world. `begin_staged_setup()` reserves/adopts the existing managed numeric trim job;
`finish_staged_setup()` polls and validates it at the existing Checking flight boundary.
The public session stays null during world construction. `setup_staged()` remains the
compatibility wrapper. No second worker pool or cache was introduced.

Default-weather/full-fuel trim preparation, selected weather/fuel application, contacts
and the final reset keep their original order. Main owns its frame waits: removing a
Main while retaining the node can free its private Session without leaving Main awaiting
a destroyed coroutine. Controlled cancellation drains the worker; raw removal transfers
drainage to the existing cache owner. A cancelled or invalid preparation cannot publish.
A successfully validated and finalized setup may retain its trim if a later loading stage
is cancelled, as with the previous staged path.

## Measured route

- Windows, Ryzen 9 5900X, RTX 3090, NVIDIA 617.42; official Godot **4.8-beta1 / 4d10419ca**
  console/editor executable, Compatibility renderer, Dummy audio driver.
- Turbo Lumber Evolution, Club Field, airborne, native **1920×1080 window**, ordinary
  Home Fly and End flight signals. Actual physics backend: `gdscript_reference`;
  native admission excludes this aircraft. No scripted poses, forced ticks or focus bypass.
- Baseline `1ff734925`, isolated from the moving working tree. Candidate changes only
  startup scheduling and its tests. Both use the same extended loading probe and prepared
  imports. Source/binary hashes and checked-run verdicts are in [manifest.json](manifest.json).
- Five fresh processes per role, two transitions each; A/B, B/A, A/B, B/A, A/B. Zero Home
  dwell, menu prefetch off. All 20 first draws were unpaused, with zero orphan nodes.
- OS/import/shader caches are not cold or controlled. This is process-cold versus
  same-process warm evidence, not disk-cold, exported-package or minimum-hardware qualification.

Raw reports are retained as `base-final-1..5.json` and `candidate-final-1..5.json`.

| Median | Baseline | Candidate | Interpretation |
| --- | ---: | ---: | --- |
| First click → validated ready | 3.789 s | 3.531 s | 6.8% shorter complete loading route |
| First click → first flight draw | 3.811 s | 3.558 s | 6.7% shorter |
| Warm click → validated ready | 1.480 s | 1.503 s | No warm improvement established |
| First loading feedback | 51.3 ms | 55.6 ms | Both below 100 ms in every run; within the 13–57 ms spread |
| Checking flight work | 397.3 ms | 4.5 ms | Most numeric preparation now completes during world construction |

Candidate median acquisition is 34.1 ms and the world interval is 847.8 ms.
`finish_setup_usec` includes remaining wait, validation and the initial reset, not just
worker time. Each first flight starts exactly one worker and retains one successful
entry; its warm flight starts none. Do not add overlapping intervals as separate costs.
Maximum first-load frame intervals remain **242–285 ms baseline / 251–269 ms candidate**;
this change does not solve construction hitches or the ≤2 s cold-Fly target.

With normal `scene_trim` Home preparation, one exploratory pair at each dwell confirms
the route remains usable; these single pairs do not establish additional speedups:

| Home dwell | First ready, baseline → candidate | Warm ready, baseline → candidate |
| --- | --- | --- |
| 0 s | 3.724 → 3.504 s | 1.488 → 1.507 s |
| 2 s | 1.572 → 1.555 s | 1.275 → 1.271 s |
| 5 s | 1.608 → 1.591 s | 1.276 → 1.262 s |

The `*-prefetch-*.json` reports retain actual dwell, Home-to-ready, cache adoption,
frame intervals, allocation counts and clean shutdown. All first draws were unpaused.
The [20-transition run](candidate-soak-20.json) also stays unpaused, returns to exactly
828 Home nodes each time and reports zero orphan nodes. One worker supplies the first
flight and 19 cache hits supply the rest; shutdown drains preparation and audio.
Static allocation grows about 0.60 MB after the first return while the probe retains
19 further reports; that measurement does not isolate a production memory leak or
establish flat RSS/VRAM. The longer memory qualification remains open.
Earlier exploratory timing used a 4K fullscreen window despite a 1080p command-line
request, or preceded the final teardown correction; those runs are excluded above.

## Correctness and remaining gates

- `test_menu_trim_prepare.gd`: 49 checks; split/wrapper exact state and checkpoint,
  pending/completed adoption, one-worker ownership, duplicate calls, busy/cancelled,
  invalid preflight/final validation and destroyed-consumer paths.
- `test_main_startup_overlap.gd`: 18 checks; actual synchronous/overlapping Main,
  airborne and runway glow Stik, seeded non-calm weather and 50% fuel. Complete
  tick-zero checkpoints, start and aircraft identities match byte for byte.
- `test_flight_loading.gd`: 56 checks; ordinary loading, duplicate activation, world
  rejection, cancellation, controlled Quit, raw AppRoot disposal, and retained Main
  removal during both cancellation drainage and finalization.
- `test_launch_trim_cache.gd`: 47 checks. Four existing golden flights pass without
  re-recording; their normal floating-point comparison tolerances remain unchanged.
- After integration, checked import succeeds; `test_flight_session_staged.gd` passes
  12 checks and Main's 18-check parity comparison passes again. The loading probe's
  six teardown/handoff/file-preservation fixtures also pass. Full-suite and package
  qualification were not run for this slice.

Software and loading evidence does not establish physical validation. The full fleet,
landscape/day/night/route/input matrix, release-package checks, RSS/VRAM measurement,
above-1080p coverage and DT-12's 50-cycle/30-minute gate remain open in the
[owning plan](../../../../MENU-REDESIGN-PLAN.md#acceptance-and-stop-conditions).

## Reproduction

Freeze both application snapshots, with matching `assets/` beside each `app/`, and
import them with the pinned engine. Run sequentially on the same host, alternating roles:

```powershell
python tools/godot/run_checked.py --timeout 180 --out-dir tmp/loading-checks --label candidate -- `
  .tools/Godot_v4.8-beta1_win64_console.exe --path <snapshot>/app --audio-driver Dummy `
  --resolution 1920x1080 --windowed --script "$PWD/research/performance/loading_probe.gd" -- `
  --output="$PWD/tmp/loading-candidate-new.json" --cycles=2 --prefetch=off --dwell-ms=0 `
  --aircraft=turbo-lumber-evolution
```

Check `complete`, actual `viewport_size`, pause state, worker counts and the checked
runner's verdict. Use new output names. Repeat with `--prefetch=scene_trim` and
`--dwell-ms=0|2000|5000`; retain full elapsed Home-to-ready as well as click latency.
The [existing probe guide](../../../../../research/performance/README.md#homefly-loading-and-lake-geometry)
defines timing and cleanup semantics.
