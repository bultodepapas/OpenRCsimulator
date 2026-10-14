# UI-05-R1 — reuse unchanged Home keyboard legend

2026-10-14. Implemented in `app/ui/home.gd`; regression: `app/tests/test_ui_home_legend.gd`. This is a menu CPU/allocation repair, not delivery of the UI-22…29 redesign.

## Change

Home previously removed and queued all four legend rows for deletion whenever aircraft selection or application focus requested a refresh. An unchanged legend therefore replaced 28 descendant Controls. Home now resolves the current physical key labels and vehicle actions, compares that small string descriptor with its previous value, and keeps the existing Controls when it matches.

Changed keyboard layouts and airplane/rotorcraft actions still rebuild. Arrow controls, keycap styling, translated action Labels, controller visibility and Fly focus retain their behavior. The per-Home descriptor contains strings, not nodes or a retained keyboard-mapping Callable. No global cache, dependency, asset or simulation change is introduced. Home already stops its settling `_process` callback; this change does not claim an idle-frame optimization.

## Native measurement

Windows, pinned Godot 4.7.2 (`ed1daf0bf`), Compatibility, RTX 3090 / NVIDIA 610.88. Three fresh native processes at 1280×720, each with 24 alternating reference/candidate pairs. Each pair constructs a fresh Home per variant, waits four frames, then measures one synchronous call for each workload with a frame boundary between workloads. Pair zero is discarded. The table gives the median of the three per-process warm medians, with their range. No engine benchmark was deliberately run concurrently; the shared development host was not qualified as idle.

| UI operation | Reference, µs | Candidate, µs |
| --- | ---: | ---: |
| Unchanged legend refresh | 2030 (1666–2752) | 87 (83–98) |
| Same-aircraft `set_aircraft` including other card updates | 1965 (1829–3278) | 550 (534–755) |
| Application focus-regain notification | 1865 (1757–2791) | 81 (67–113) |

All measured unchanged reference refreshes replace the 28 descendants; all candidate refreshes retain them. These are synchronous UI call costs, excluding deferred destruction, subsequent layout/render work, aircraft backdrop construction and full Home/Fly loading. They are not frame-time percentiles, FPS or startup improvements. Absolute timings vary with the host; do not pool these with the rendering campaigns.

## Verification and limits

- New regression: **23/23 headless and 23/23 native**. Covers identical refresh, focus regain, airplane selection and fallback, rotorcraft transitions, controller hiding/restoration, injected QWERTY/AZERTY changes, drawn arrows, translation and node retirement.
- Existing controls-reference checks pass. The input-isolation test reports successful assertions and exit zero, but also logs the field-validation rejection described below; it is not a clean full-route result. The new `test_*.gd` file is automatically included by `app/test.sh`.
- All **eight native screenshot pairs match exactly**, covering EN/ES × airplane/rotorcraft × keyboard/controller at 1920×1080 on a plain viewport, with no 3D backdrop. The Spanish rotorcraft/keyboard capture was also inspected visually.
- A disposable defect that compares only vehicle actions and ignores changed printed keys fails both keyboard-layout rebuild and AZERTY-label checks; the production test detects that stale-cache regression.
- Broad Home layout and full-route checks are not all green. The reference reproduces a **444 px Spanish rotorcraft sidebar**, exceeding its 440 px contract in four layout cases. Home/language/aircraft/controller routes also encounter the shared field validator rejecting tree indices 271–274 inside its runway corridor. These are separately recorded baseline failures, not accepted behavior or a successful full-suite run. No field data or validator is changed here.
- Native radio hardware, other operating systems, exported routes and total Home loading are not qualified by this slice.

## Evidence and reproduction

`manifest.json` identifies retained files and their SHA-256 hashes. `source-before.json` pins the measured inputs; `home.patch` isolates this optimization from the other rotorcraft edits already present in the working tree. `reference.gd.gz` and `candidate.gd.gz` retain the exact measured Home implementations. The shared tree is not represented as an immutable whole-repository snapshot.

`single-summary.json` and `single-00/`…`single-02/` contain commands, raw observations and clean engine logs. `integrated-validation.json`, `contrast-validation.json` and their logs distinguish passing checks from baseline failures and the deliberate keyboard-layout defect. `captures.json` reports decoded pixel equality for each PNG pair.

To reproduce, decompress the retained `.gd.gz` scripts into a disposable directory outside `app/`. Use the pinned engine with `--path app --audio-driver Dummy --resolution 1280x720 --script <probe_single.gd> -- --directory=<directory>`; that directory must contain `reference.gd` and `candidate.gd`. For screenshots run `capture.gd` with the same directory and `--resolution 1920x1080`. Run `res://tests/test_ui_home_legend.gd` headless and native against production; its optional `-- --home=<script>` selects a disposable candidate. Do not run native timing alongside other Godot workloads.

## Next menu work

1. Repair and validate the reproduced Spanish rotorcraft width overflow, including keyboard-legend reachability at 720p.
2. Coordinate the field validation conflict with the field owner, then rerun the blocked complete Home/navigation routes.
3. Continue the owning redesign plan in order: UI-22 theme, then UI-23 scaling/display. Attribute total Home/backdrop loading separately before considering broader caching or asynchronous construction.

Do not retain whole hidden Home screens, cache keyboard layout globally or skip focus-time label resolution merely to reduce allocations: each would introduce stale state or lifecycle costs beyond this measured repair.
