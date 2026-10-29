# UI-34c-R5 — staged scenery construction, 2026-10-28

The former field builder constructed and attached all scenery in one loading phase. The candidate builds the same detached scenery in ordered units, batching work up to a 16 ms budget between existing loading checkpoints. Five measured pairs show a smaller maximum **scenery work phase**; they do not establish a whole-loading latency improvement or interactive-readiness qualification.

The budget is checked between units. A single placement, mesh conversion or unchanged subsystem can exceed it; birds are prepared with the initial lighting snapshot, and botanical construction remains indivisible. Completed scenery is attached only after the whole detached build finishes. Cancellation frees the unfinished tree.

## Method and identity

Windows, Godot 4.8-beta1 `4d10419ca`, Compatibility, RTX 3090, NVIDIA 617.42, windowed 1920 × 1080, Dummy audio. The [loading probe](../../../../../research/performance/loading_probe.gd) drove the real Home → Fly → Home route for Turbo Lumber, airborne start, keyboard input, prefetch off and zero dwell. Each fresh process ran two cycles. The second is warm **within that process**; fresh processes do not establish cold OS, import or shader caches. The runtime requested native physics but selected the GDScript reference on Windows.

The collector's post-run WMI and power-settings check reported Windows 11 Pro build 26100, Ryzen 9 5900X (12 cores, 24 threads), 66,995,304 KiB visible memory and the Balanced power plan. This was not recorded separately for each run, so it does not prove an unchanged power setting throughout collection.

Runs alternated candidate/baseline order: C1–B1, B2–C2, C3–B3, B4–C4, C5–B5. The collector observed no competing guard file during these runs; unrelated host activity and cache state were not controlled. Each [checked report](checks/) completed with zero parsed errors and warnings. The checks do not establish that every first draw was unpaused.

Baseline commit `faa73692ec14856cbc2a4d212ecaf1a782a66208` and the candidate runtime hashes are in the [manifest](manifest.json). Its [baseline inventory](inputs/baseline-identity.json) lists 1,531 GDScript hashes. At the post-run audit all those candidate paths existed and only the two runtime files and the then-unused staged-field test differed; the inventory does not cover assets, import caches or the external probe. The candidate's runtime hashes match the later integration identity.

The external probe differed from the frozen baseline: it adds explicit keyboard selection and pause/hold fields. Its [post-collection source](inputs/loading_probe.gd.txt) and SHA-256 are retained; the file was clean against then-current HEAD, but no per-run probe hash was recorded. Its containing commit was timestamped during the cohort, so the source identity is a post-run check, not proof of byte stability throughout every run. All ten reports do record `input_mode = keyboard` and the hold fields.

## Measured loading phases

Each cell reports baseline → candidate. **Max** is the largest elapsed `Building field scenery` work phase, **sum** is the sum of those phase intervals, and **count** is the number of such intervals. These are wall-clock intervals between checkpoints, including scheduling, not isolated CPU or frame-render times. **Reported ready** is Fly dispatch to validated scene readiness; it is not interactive readiness when paused. A dagger marks a candidate first draw paused at tick zero with `holds.menu = true`.

| Pair, fresh process | Max (ms) | Sum (ms) | Count | Reported ready (ms) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 210.577 → 22.266 | 210.577 → 230.420 | 1 → 22 | 3,499.964 → 3,628.712 |
| 2 | 208.611 → 22.322 | 208.611 → 231.973 | 1 → 22 | 3,743.315 → 3,763.273 |
| 3 | 330.087 → 29.240 | 330.087 → 287.103 | 1 → 24 | 4,308.262 → 4,174.907† |
| 4 | 264.633 → 30.068 | 264.633 → 304.377 | 1 → 25 | 4,079.712 → 3,943.069† |
| 5 | 223.724 → 38.481 | 223.724 → 311.889 | 1 → 25 | 3,629.536 → 4,191.834† |

| Pair, second cycle | Max (ms) | Sum (ms) | Count | Reported ready (ms) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 205.629 → 21.471 | 205.629 → 224.225 | 1 → 21 | 1,479.746 → 1,622.510 |
| 2 | 212.261 → 22.359 | 212.261 → 220.478 | 1 → 21 | 1,512.174 → 1,557.725 |
| 3 | 214.953 → 23.340 | 214.953 → 237.120 | 1 → 22 | 1,671.679 → 1,512.755 |
| 4 | 217.179 → 22.089 | 217.179 → 229.932 | 1 → 21 | 1,623.076 → 1,659.982† |
| 5 | 214.893 → 22.082 | 214.893 → 225.610 | 1 → 21 | 1,605.933 → 1,667.860† |

The five-run medians of the largest scenery interval are **223.724 → 29.240 ms** for first cycles and **214.893 → 22.089 ms** for second cycles. Their corresponding median sums are 223.724 → 287.103 ms and 214.893 → 225.610 ms. These describe the named phase only; other loading frames remained above 100 ms. Each recorded scenery phase precedes the reported first draw, but changing focus and scheduling can still influence timing.

Only pairs 1 and 2 have both cycles unpaused in both roles. Their candidate-minus-baseline readiness differences are +128.748 and +19.958 ms on first cycles, and +142.764 and +45.551 ms on second cycles; differences of the two-role medians are +74.353 and +94.158 ms. Two pairs are provisional evidence of a handoff tradeoff, not a qualified latency distribution. The other three fresh candidate draws and the last two warm candidate draws were paused. Their empty pause-reason string and `menu` hold are consistent with the existing focus-loss path, but the exact cause was not instrumented. Candidate pair 3's warm draw was unpaused; its fresh draw was not.

[All ten raw reports and stdout](raw/) and their [checked receipts and engine logs](checks/) are retained. The [manifest](manifest.json) records per-file hashes and the individual measurements; original absolute paths in checked reports describe the collection environment.

## Controls and limits

The earlier [4 ms draft and baseline pilot](pilots/) produced many more checkpoints and substantially longer reported handoff times. That exploratory run was affected by competing host work and used the earlier probe without explicit keyboard selection; it is not part of the five-pair cohort. The later [initial candidate pilots](pilots/) observed paused first draws, including a controller-selection failsafe in one run; neither is readiness evidence.

The independently loaded original Field and Scenery were compared with the candidate in both headless and native 1080p checks: **43 checks passed in each**, with zero parsed errors or warnings. They cover node order, mesh arrays, MultiMesh buffers, material properties and metadata across quality tiers and reordered groups, as well as input isolation, cancellation, abandoned-job cleanup and retry. The [headless](checks/parity-final-matrix-headless/) and [native](checks/parity-final-matrix-native/) receipts retain commands and output; the [reference Field wrapper](inputs/reference_field.gd.txt) differs from the baseline only in its absolute preload of the original Scenery. The later matrix test source is distinct from the test file present in the measured candidate snapshot.

After integration, the checked headless runs passed staged field (43), scenery build (161 reported `ok` lines), landscape eligibility (7), flight loading (56), startup overlap (18), scenery destruction (78) and time-of-day scenery (25): 388 reported checks in total. The separate Python loading-probe fixtures printed six passes. [Receipts and outputs](checks/) retain the command and diagnostics for the Godot runs; the Python output has no checked-runner receipt.

A separate [integrated native 1080p camera observation](checks/integrated-camera-observation/) returned to Home with zero reported orphans and drained audio and preparation. All 14 uncovered sampled frames reported a placed camera, render pose and completed startup. Its first draw was paused at tick zero with a `menu` hold, so this does not establish active input. Camera readbacks add overhead; this run is excluded from performance comparisons. The inspected screenshots remain in ignored temporary storage and are not part of this evidence bundle.

These checks establish software behavior on the exercised fixtures. They do not establish a loading gate, exported-package or multi-platform qualification, flight FPS, GPU performance or physical flight validation. The [NK-3 boundary receipt](inputs/nk3-boundary-check.json) reports no overlap between the four changed code paths and its 130 declared reference sources; this is not native-backend requalification. The candidate did not change the simulation kernel, physics laws or aircraft catalog.
