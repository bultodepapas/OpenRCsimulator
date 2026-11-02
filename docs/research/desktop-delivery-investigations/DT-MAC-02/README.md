# DT-MAC-02 — Mac measurement, package identity and native evidence

Initial preparation, 2026-10-28: implementation on Windows with three Terra 6.1 Max specialists:
native acquisition/compatibility, renderer/reconstruction, and capture/reducers.
The [Apple Silicon plan](../../../plans/apple-silicon-performance.md) owns status
and remaining acceptance. The [preceding research](../DT-MAC-00-R2/README.md) owns
the dated primary references and pinned-engine audit.

## DT-MAC-02c/d/h implementation (2026-11-02)

The debug bridge now constructs native Aqua rendered launches without Xvfb and
reads Mac RSS through the existing optional, PID-checked resource sampler. The
sampler probes unsupported process I/O once, retains null/status, and reports
required RSS/CPU/system-memory coverage separately from the v1 legacy receipt.
The default 1 Hz cap is 2,100 samples. DT-MAC-02d uses the shared v3 validator
to keep completed report/sidecar pairs together in incidents, preserve an abrupt
crash sidecar as explicitly unverified, and require an explicit scope for large
Perfetto timelines. Old v2 reports remain accepted. DT-MAC-02h adds a versioned
Mac reference-release bundle receipt covering executable, PCK and bundle contents,
independent of Linux NK-3 admission. Its GDScript and Python identities agree on
a PCK fixture. Final-ZIP integration and a native development-package exact
replay now pass as described below; distributed-package acceptance remains open.

Focused Linux fixtures passed: debug bridge 39, sampler 17 (one optional
real-child test skipped without psutil), runner 9, incident 26, Perfetto 25,
release receipt 8, flight-log 32 and session baseline 22. Mac fixtures passed:
debug bridge 39 (one skip), sampler 17 including real child, runner 9, incident
26, Perfetto 25, release receipt 8, flight-log 32, session baseline 22;
GDScript flight-log 3,275 and replay integrity 153 assertions passed. These
checks establish source contracts, not final-release acceptance.

### Final ZIP and manifest integration (2026-11-02)

The exporter now copies the staged Godot Mac ZIP and appends one external sibling
receipt. Finalization compares the app's file contents, architectures, creator and
permission attributes with the staged archive; it does not independently compare
timestamps or extra fields. Manifest v2 binds receipt/input-snapshot/probe hashes,
and transfer verification checks those identities against the archived app.
The private input snapshot is not published; the public set remains six files.
Generic verification preserves the exact historical v1 schema for integrity-only
checks. Current publication and downloaded retry require v2, preventing that
compatibility path from bypassing the new requirement.

Linux fixtures passed: release tools 63, exporter identity/actual packaging-tail
fixtures 35, flight-log Python 32, CI partition 13, shell syntax and diff checks.
An independent source review found no further concrete defect. Fixtures use
synthetic Mach-O, PCK and signature data; native development-package checks are
recorded separately below. Verification streams archive contents; archive limits
apply after Python parses the central directory. Downloaded/quarantined
installation and the complete six-file release pipeline remain open. Path translocation may prevent sibling-receipt access;
the intended move-app-and-receipt-together route still needs that native check.
The [release guide](../../../../tools/release/README.md#mac-reference-bundle-identity-dt-mac-02h)
owns commands, schema policy and installation limits.

Native package preparation exposed another build-memory risk: the source identity
helper buffered the complete binary Git diff. It now hashes that stream in bounded
chunks and concurrently drains stderr, retaining at most 64 KiB of diagnostics.
Tests preserve the old hash/dirty convention for clean, untracked, staged, deleted
and large binary changes, and cover subprocess and stderr-read failures. The
updated release suite passed 66 tests and exporter identity passed 35. An
independent review found no concrete regression. Only diff-output memory is
bounded; untracked-path sorting and Git's own CPU/memory remain separate costs.


### Native candidate ZIP and exact replay (2026-11-02)

The final candidate was exported on the M1 with the pinned ARM64 editor and the
corrected universal release template. `package-zip` preserved the staged bundle
bytes and added its external reference receipt. Both staged/final archive checks
found arm64 and x86_64 executables with executable permissions. After `ditto`
extraction, `codesign --verify --deep --strict --verbose=2` passed, and Python
bundle verification agreed with the runtime's ARM64 identity. This is an ad-hoc
signed development build; Intel execution, notarization, Gatekeeper and downloaded
quarantine/translocation are not covered.

The actual exported executable recorded 2,654 ticks and exactly replayed all
recorded numeric samples: `complete=true`, `mode=exact`, `solver_changed=false`.
Both sides used `macos-reference-bundle-v1` with the ARM64 identity below. Its
fixed packaged session probe also passed receipt/source verification and completed
240 warmup plus 960 measured trim ticks using `gdscript_reference`, observer on.
These headless checks establish packaged execution and replay, not flight feel,
render pacing or sustained performance.

The same package rendered the production field through its default Compatibility
path at a 2560×1600 viewport, with the expected reference-backend fallback.
`--capture --t=1.5` saved a visible aircraft, sky, terrain and HUD without engine
errors. The checked run reported four ObjectDB instances at exit; attribution
remains open. This paused static capture is a package graphics smoke check, not
moving readability, presentation or timing acceptance. The image SHA-256 is
`24b1ee94e7a445a6e0ba0a2d7847377d68920afa7966cc327f6bfcf132d2be05`;
PNG and capture receipt stay in ignored evidence.

| Artifact | SHA-256 |
| --- | --- |
| Final candidate ZIP | `f3ca7c892dcc3211df4bb54309839ea816b9547a3adf70d4fa1609257f2e505e` |
| Staged ZIP | `a9755a9d6473d32f74fa89654edc18a90155778b8b49a2926e6d2a83483ace53` |
| External receipt | `6a2ad3ae53a07e6cd108d395e26251e8815dbeafdfe4bfb5944605a079cecf2f` |
| Private input snapshot | `bbe022df7f836f4b6f69bfcb6037236b062863006b7399cc49394ae17de79986` |
| Executable | `2c349fc57fe9e08c8b9890f3656b5d963d2d08450cc36bdcdf3139e77b004bcd` |
| PCK | `8774b22470a69a687ca0e509dd421008df60eb3f07e94f56cc33509e1bc9ae53` |
| ARM64 bundle identity | `91827abfaf2f105cba0b8fac33d325adddc4645068d59772c930c1214cf208cf` |
| Packaged flight log | `c0d9cbb73f536c6c67c16a3f4b88f4e7f23140e585557e9bccde9fff76cf2367` |

The package was built in `/Users/gius/OpenRC-m1-package-check`, an isolated APFS
clone prepared from the candidate research application. The packaged capture
independently confirms the candidate ground shader hash recorded below; exported
GDScript resources are compiled `.gdc` files, not a complete original-source hash inventory. The
receipt binds the declared source snapshot, not source-to-binary reproducibility.
Its Git base is the Mac's
`cfad9b9fc787aab1512200abca9640133d0a81a9`, with a declared dirty worktree digest
`a2a42e5a238f28db21e2d58f7bd0ef8e7371d0e73a24b3cdf2039d7f38083167`.
The clone inherited an incomplete checkout, so this large dirty diff is not a
clean release at the Linux integration commit. Because this was a manual export,
the runtime build stamp says `export-manual`, empty commit and `dirty=false`;
`code_revision` is unavailable. That generic stamp does not reconcile with the
declared dirty source snapshot. The external receipt supplies the source/bundle
binding for these checks; normal build stamping and full pipeline reconciliation
remain required before release. The original Mac checkout and its
absent Git index were left untouched. The streamed identity capture completed
in 56.69 seconds; its aggregate resource figures do not isolate Python memory or
establish a measured memory saving.

The retained Mac artifact is
`/Users/gius/OpenRC-m1-package-check/tmp/native-candidate/OpenRC-M1-candidate.zip`.
Small receipts, checked logs, `.orfl`, replay CSV/report and the probe report are
copied to ignored `tmp/apple-opt-20261102/native/packaged-candidate/` on Linux.
The staged ZIP was removed only after byte-preservation verification and hashing
to make room for final extraction; the final ZIP and extracted app remain.
The Mac then had about 880 MiB free and Linux about 1.6 GiB. Sustained memory/swap
qualification needs adequate storage headroom; these constrained hosts do not
establish that gate. The complete release export/publish pipeline was not run.
SSH keys remain installed as requested.

## DT-MAC-04b / 06b optimization candidates (2026-11-02)

The source baseline is `85c9fd35f83a3f2b2aa3fdbaf67e9a73a8bcdb6e`.
The concurrent WEB-14 commit changes the website, not these application inputs.
Three bounded runtime changes preserve the existing simulation and quality settings:

- Statistics retain chronological packed TAS/groundspeed values alongside the
  existing window. Native sorting still operates on independent copies on each
  eligible tick once the window is full; snapshots, reset/restore and event
  ordering stay unchanged.
- Flight logging captures independent byte snapshots for its intervention guard,
  avoiding repeated conversion of the saved boundary and the discarded copy of
  `previous` in each recorded row. Chunk size, flush timing and replay policy stay
  unchanged. This source edit changes solver identity: old recordings require
  explicit candidate comparison, never a false exact-replay claim.
- Ground shading bypasses the nine-site parcel search at zero parcel weight and
  photo/dirt preparation when neither contributes. The dirt branch retains its
  original pre-grass normal. Shared procedural-noise changes remain experimental.

Frozen candidate SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `app/statistics/detector.gd` | `ee5b76a7e50650f1f727fc2cd477848198b61921c3fe610391806772e3745abb` |
| `app/sim/flight_log.gd` | `8c66f6f909a874e66588c9dcaf9d24ab4cdcea4602fba20f5f6cf04f1e5bc659` |
| `app/render/ground.gdshader` | `7d694f9ae11328389993da55fd13db44fa3feb407b57654ef001da4d48a274f3` |

Focused checks passed: logging 3,309 assertions, input recording 284, statistics
177, lifecycle 73 and resets 86; affected ground, terrain, lake and RC material
checks passed. Frozen-reference tests compare recording packet bytes and detector
events/snapshots, including invalid restore followed by another observation.
The detector reference comparison covered 12,960 real-flight ticks and 11,068
speed-window evaluations without a mismatch. Component timing is diagnostic only;
whole-app M1 measurements decide a performance claim.

The native campaign uses the same M1/8 GB built-in display, AC power and pinned
4.8-beta1 ARM64 engine. Research project names isolate saved preferences. The initial baseline native
release `.app` was exported with the corrected universal template (SHA-256
`95f6a5258f1b5b0e91ac56632ed4f74ebe92673f085aa608ff6d4e099b6b85d3`);
`codesign --verify --deep --strict` passed. That initial baseline bundle has no final reference receipt. The later candidate
package below has one; neither establishes distributed/notarized release trust.

Five actual Compatibility screenshots at 2560×1600 are byte-identical before and
after the ground shader change: `runway_inside`, `lake_shore`, `plain_overview`,
`horizon_raised25` and `horizon_raised120`. These fixed views establish their own
static parity, not RC dirt, motion or all-renderer coverage. Baseline/candidate
captures, checked logs and frame streams remain outside Git in
`tmp/apple-opt-20261102/native/` and the Mac scratch `tmp/apple-opt/`.
After connectivity resumed, all five candidate images were copied locally and
their SHA-256 values again matched the five retained baseline images exactly.

The production RC harness also checked the Bisonte at `track_start`, low-orbit,
day, 2560×1600 Compatibility. Both shader roles kept the production RC material
enabled (`variant=candidate`); state, camera, effective material readbacks, mesh
and other recorded source identities matched. Foreground dirt, grass and truck
pixels were exact. Three distant-object pixels initially differed (maximum
4/255); a same-candidate repeat varied at eight pixels (maximum 11/255) in the same
8×3-pixel background region. All pixels outside that region were exact across
all three captures. This demonstrates fixture variability without a shader swap,
not a changed ground surface. The inspected static view passes visual review;
motion and untested viewpoints remain separate. Receipts and PNGs are retained in
`tmp/apple-opt-20261102/native/rc-shader-{baseline,candidate,candidate-repeat}/`.
Four ObjectDB instances were reported at shutdown by baseline and repeat, but
not the first candidate; that warning is not uniquely associated with the shader.

The portable CPU comparison now uses the pinned psutil backend on macOS, preserves
unsupported main-thread CPU as null, pins and verifies the Stik, and records
sampling-boundary uncertainty. Darwin launches must pass the existing isolated
research-project validation. The cadence runner now actually alternates two
roles; its old rotation-plus-reversal canceled the intended alternation. Every
result row still needs inspection: a child failure row is not a complete pair.
The headless Home→Fly workload includes statistics; direct CLI flight omits that
service and cannot establish the detector benefit. This workload uses a 60 FPS
cap and time scale 0.5, so it is distinct from normal rendered release play.

Integrated Linux checks passed all four golden flights, identical state and flight
checkpoint hashes at 30/60/144 FPS, and a real 720-tick CLI trace. A 1080p llvmpipe
capture compiled the changed ground shader without errors; it is not native-GPU
performance evidence. The first parse attempt stopped after an unrelated website
commit moved HEAD. The subsequent full integration-parse gate passed all 1,561
scripts plus import on stable commit `bfed005e2da1421c32bf8083a181b823af1952e0`:
expected/completed rosters match, with digest
`2c1305211e364287ab933d2370e961e5f6dcf7239ed8c49f70036b32dbb57346`.
Candidate and parse-tool hashes matched before/after. Only the exporter and its
Python test changed during that run, outside the parse roster. Receipts remain
under `tmp/apple-opt-20261102/final-parse/`. Full CI/unit coverage remains open;
the runtime mutation prelude also needs more disk space than available for its
four disposable source copies.

The resulting collector repair now records draw counts, per-interval draw/reset
facts and main-window drawability independently of optional GPU diagnostics.
It covers the first measured interval and detects skipped intervals even if a
later update draws twice. New v2/v3 reports preserve data completeness separately
from rendering eligibility. The native reducer and grass-performance consumer
refuse rendered qualification without that evidence; historical reports remain
readable as unknown. This establishes global render-server progress only, not
main-viewport presentation or GPU completion. Focused checks passed: draw progress
24, native summary 49, diagnosis 30 and grass profiler 27; existing diagnostics
26 and sample collector 112. Real headless v2/v3 producers remained complete and
explicitly ineligible for rendered performance.

### CPU comparison status

The longer source-editor campaign requested five alternating baseline/candidate
pairs, each with 30 s warmup and 120 s measured. The M1 became unreachable over
SSH/Tailscale after five result rows had been retrieved. On reconnection, the
campaign was still running and was stopped. The sixth row completed after wake
and is excluded from timing decisions. Raw JSONL and console output were recovered
to `tmp/apple-opt-20261102/native/recovered-cpu/`. The pre-interruption prefix was:

| Pair | Baseline process CPU ms/simulated s | Candidate process CPU ms/simulated s |
| --- | ---: | ---: |
| 1 | 480.98 | 480.92 |
| 2 | 477.55 | 482.58 |
| 3, incomplete prefix | 481.85 | unavailable |

The two complete pairs average 2.485 more CPU ms/simulated s for the candidate
(about +0.52%); two pairs and unknown endpoint alignment establish neither a
practical saving nor a reliable regression. They cover only direct-process CPU in the
headless Home→Fly workload, not render speed, recorder overhead, descendants or
energy. All five retrieved rows identified the Stik and had sim/wall ratios
0.9986–1.0004. The bridge omitted snapshot ages, correctly leaving timing bounds
unknown. Runtime detector attachment/window eligibility, controller override and
field/weather identity were not independently captured during these runs; source
inspection alone cannot establish them. The statistics optimization remains an
unqualified candidate.

### Candidate native correctness after reconnection

All 24 transferred source hashes matched the prepared update, and the native
candidate import passed. M1 frozen-reference checks passed: flight log 3,309,
statistics 177 and draw-progress 24 assertions. An untimed Home→Fly inspection
confirmed the current detector hash above, attached statistics, no suspension,
a full 0.25-second/60-sample speed window and both 60-value caches. Radio input
was disconnected; bridge controls were accepted without a warning. This separate
inspection does not retrospectively prove every earlier benchmark's inputs.

The current candidate then recorded a marked 2,428-tick Stik flight and exactly
replayed every recorded numeric sample on the M1: `complete=true`, `mode=exact`,
`solver_changed=false`, `source-tree-v1` identity
`5d27509ef2bdae8788071440556550a3e4ce87f3cc7d8347244f9dabe26ebb95`.
The bridge stopped with no crash or leaked objects. Recording SHA-256:
`9026f0cc62b419d21015cf956515f9536056b3ad5ee7a855a85c4ee69cab40b7`.
The `.orfl`, CSV, replay report and bridge transcript are retained locally under
`tmp/apple-opt-20261102/native/candidate-session/`. This is a short source-build
software check, separate from the historical baseline replay, package replay,
control latency and physical flight validation.

### Mobile/Metal startup and frame-time screen

A longer retry of the frozen baseline release completed on AC. Total checked
process time was 163.862 s, including world preparation, 10 s frame warmup and
30.002 s measured. A ten-second `/usr/bin/sample` during startup retained
unsymbolicated engine frames and Metal compiler connection queues; a matching
process snapshot showed `MTLCompilerService` at roughly 653% CPU. Apple describes
this service as compiling uncached pipeline code ([Metal compilation model](https://developer.apple.com/videos/play/wwdc2020/10615/)).
This establishes active compilation during this retry; it does not attribute all
startup time or shared-service work to this app. The earlier 100 s timeout is
insufficient evidence of a permanent renderer hang. No default was changed.

The native 2560×1600, Standard, medium-detail, Native reconstruction, 4× MSAA,
uncapped fixed-view release screen completed 4,327 frames: p50 6.896 ms,
p95 7.726 ms, p99 8.572 ms, maximum 85.048 ms. A separate Compatibility screen
with the same requested camera/settings completed 624 frames: p50 47.074 ms,
p95 54.742 ms, p99 73.500 ms, maximum 122.737 ms. These are short callback-interval
screens, not alternating performance qualification, active flight, presentation
latency or a default-renderer recommendation. Mobile enables the existing HDR
viewport path; Compatibility does not. The startup sampling run is instrumented.

The Metal GPU/CPU viewport timers remained constant across all measured frames
(40.674 / 1.377 ms respectively), despite changing callback intervals. They are
unusable for per-frame cost attribution in this run. The frame-setup timer was
also constant: a window that stopped drawing is a concrete alternative explanation
for the short callback intervals. Until a drawn-frame counter confirms continuous
render progress, the Metal timing is **inconclusive**, not evidence of a speedup.
Seven leaked Texture RIDs
were reported at Metal shutdown. The cause and repeated-session implications are
not established. The raw Mobile landscape PNGs also lack the fixture's required
linear-HDR-to-display conversion; they cannot establish cross-renderer color
parity. Production `--capture` and debug-bridge screenshots already convert it.

After reconnection, the updated source collector detected 38 initial no-draw
intervals in a 30-second Metal retry, correctly refusing rendered eligibility.
A subsequent 30-second warmup and 60-second sample observed global render-server draw-count progress in every interval,
with no counter resets or undrawable samples. The matching Compatibility
screen used the same candidate, requested 2560×1600 viewport, camera, Standard
effects, medium scenery, Native reconstruction and 4× MSAA:

| Source-editor screen | Frames | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Mobile / Metal | 1,663 | 35.539 | 37.602 | 47.961 |
| Compatibility / OpenGL | 1,350 | 44.153 | 48.906 | 54.186 |

Both v3 collections and rendering-progress gates passed. Neither meets the
proposed frame-pacing budget. These two sequential fixed-view screens are not
alternating paired trials, active flight, presentation latency, thermal evidence
or a shader-specific speedup. The renderer paths also differ in HDR behavior.
The Metal viewport GPU timer varied in the preceding draw-observed retry; it was
not frozen like the earlier unusable screen. Metal reported seven Texture RIDs
at shutdown; Compatibility reported four ObjectDB instances. Their ownership
and candidate-vs-baseline attribution remain open. Raw checked logs, streams and
reductions are retained locally under `native/candidate-{metal,compat}-steady/`.
All 666 source hashes recorded in the Metal report matched the Linux candidate
except the intentionally isolated `project.godot`.

The existing opt-in MetalFX Spatial 85% route then completed a separate 60-second
screen after 30-second warmup: 1,941 frames, p50 30.452 ms, p95 32.368 ms and
p99 42.802 ms, with continuous draw progress. The device admitted spatial mode 3,
retained 4× MSAA, and reported nominal 2176×1360 3D input into 2560×1600 output.
The receipt correctly keeps `effective=unknown` and
`execution_status=unverified_trial`; viewport properties do not prove the actual
SDK pass. This single screen has no paired attribution, motion/readability or
GPU-capture proof and still misses the pacing budget. It does not promote a
default or qualify MetalFX. Raw evidence: `native/candidate-metalfx85-screen/`.

## First M1 native screening (2026-11-02)

The isolated test copy ran on a MacBookAir10,1 (Apple M1, 8 GB), macOS 27.0.1
(26A434), ARM64, official Godot 4.8.beta1.official.4d10419ca. Its built-in
Retina panel is 2560×1600 physical pixels and currently 1440×900 logical pixels.
The user authorized this display for M1 testing. Neither the system inventory
nor the Godot viewport report proves actual drawable pixels. The global 1080p
product target remains a separate output case. The scratch copy used a distinct
project name and linked the existing assets; key aircraft asset hashes matched
the Linux source. Raw reports and frame sidecars remain in ignored local `tmp/`.

Native preflight completed without issues. A fresh import completed in 214 s,
with eight ambient OBJ material warnings and no engine errors. The rendered Aqua
debug bridge reached Home and stopped cleanly; headless bridge smoke also passed.
A 10 s reference flight completed 2,401 trace rows with truthful GDScript
fallback, 12 resource samples, complete required RSS/CPU/system-memory coverage,
peak RSS 862.9 MiB and minimum system available memory 1,571.4 MiB. Optional
process I/O counters were unsupported on Darwin, explicitly null. This is a
short availability check, not a sustained memory or timing result.

One battery-powered Compatibility screen at requested 1920×1080, medium detail,
60 FPS cap and native reconstruction produced a complete v3 pair: 1,206 sample
frames over 30.017 s, p50 24.319 ms, p95 26.855 ms, p99 29.537 ms and maximum
253.679 ms; sim/wall ratio was 0.9818. Required OS resource coverage was complete.
The requested Godot window/viewport was 1920×1080, but the Mac's logical display
was 1440×900 and actual drawable pixels were unverified; it is not 1080p output
qualification. The short run misses the proposed p95 ≤18 ms and sim/wall
0.99–1.01 budgets. Compatibility GPU timing was unavailable. A Mobile/Metal
viability run timed out after 100 s before producing a frame stream and capped
its resource samples; it supplies no renderer comparison or performance claim.
The Mac was subsequently connected to AC for separate built-in-display screens.

On AC, fullscreen at the current 1440×900 logical display mode made Godot
report a **2880×1800** native reconstruction target. That 30.009 s capture
completed 615 frames with p50 48.393 ms, p95 54.149 ms and p99 57.466 ms.
It had no companion resource capture, so it is a separate screen only. A second
AC windowed run requested **2560×1600**, matching the panel's physical pixel
count, and Godot reported a 2560×1600 viewport and reconstruction target.
Its 30.021 s stream completed 610 frames with p50 40.132 ms, p95 62.695 ms,
p99 249.984 ms, maximum 601.782 ms and derived sim/wall ratio 0.8473.
The existing frame diagnoser found all 610 intervals over its 16.667 ms
screen, including three intervals above 470 ms; GPU timing was unavailable.
The checked runner passed with 52 resource samples, complete required-channel
coverage, peak RSS 956.3 MiB and minimum available system RAM 1,535.9 MiB.
The resource sampler ran from before the frame interval until after it; its
last 1 Hz point preceded the final frame by about 0.4 s. All 665 captured
source hashes matched this working tree except the deliberately renamed
scratch `project.godot`. The v3 validator found no stream errors, and the
native incident bundle retained both report and sidecar as a validated pair.
This one short AC run misses the proposed pacing and sim/wall budgets; it
does not establish a steady-state rate, drawable-pixel identity or GPU cause.
The three 30-minute AC soaks remain open. The user authorized the built-in
display for this M1 campaign; separate 1080p output remains untested.

An isolated headless debug-bridge flight then recorded a complete 5,738-tick
Ugly Stik `.orfl` and stopped cleanly with no leaked objects. The native Mac
editor exactly replayed every recorded numeric sample: `complete=true`,
`mode=exact`, `solver_changed=false`, identical `source-tree-v1` hashes and
GDScript reference stage identities. The retained `.orfl`, CSV and report are
in ignored `tmp/apple-m1-access/replay/`; the source log SHA-256 is
`6a1735ec5e27b315bc602e306a2661874e780302a8929b89fd12394937beba71`.
This source-build replay has no maneuver markers and is not an exported-package
replay, physical handling validation or a native-solver parity result.

## Implemented preparation

| Delivery | Implementation | Evidence boundary |
| --- | --- | --- |
| DT-MAC-02a: native editor | `app/get-godot.sh` downloads the exact official 4.8-beta1 ARM64 archive, verifies SHA-512, preserves the app bundle, checks Mach-O architecture/version and verifies a complete cached-file manifest | Official editor installed and native ARM64 import/launch screened on M1; a development release exported and passed strict codesign verification. Final distributed package and trust remain open |
| DT-MAC-02a: templates/preflight | Darwin `shasum` support, Python 3.11 prerequisite/override for the existing beta-template correction, bounded serial-filtered host/GPU/display/tool/engine inventory with unique JSON receipts | Native preflight passed. Host Python 3.9 cannot run the template getter; the development export used the corrected template prepared on Linux, with hash recorded above. Full release-pipeline qualification remains open. System display dimensions are not drawable pixels; Linux export/NK gates remain intact |
| DT-MAC-02b: long capture | Opt-in `openrc-frametimes v3` chunk stream, bounded memory/file/duration/frame counts, sequence/hash/completion/failure receipts, interruption handling, synchronous write timing; v2 short reports retained | Synthetic 30-minute 60/120 Hz streams and short native M1 rendered captures. No 30-minute native flight, observer-cost acceptance, power or thermal evidence |
| DT-MAC-02b: readers/identity | Existing native summary and frame diagnosis validate streams. Diagnostics include OS/architecture, method/driver, VSync/FPS cap, explicit timing/viewport scope and unknown command backend | Missing presentation/GPU observations stay unverified; DT-MAC-02d now accepts validated v3 streams in incident/Perfetto routes |
| DT-MAC-05a: isolated experiments | Preparation helper copies/hashes app sources, assigns a UUID user-data identity, isolates import cache, disables startup multi-bounce and links sibling assets. Launcher validates method/driver pairs and records requested/effective identity | Windows fixtures and headless identity checks. M1 Compatibility viewport sizes were observed; drawable identity and cross-renderer parity remain open. Initial Metal screens lacked valid draw evidence; the updated collector subsequently passed 60-second Metal and Compatibility screens. Neither meets the pacing budget. Forward+ untested |
| DT-MAC-07a–c: guarded MetalFX | Five opt-in Spatial/Temporal choices, runtime method/driver/RD/enum/feature/scale checks, provider-specific AA/sharpening, localized UI, explicit unknown execution and Native recovery | A Spatial 85% M1 screen admitted the route but leaves actual SDK execution unverified. Temporal requires Forward+ and falls back on history discontinuity without verified reset acknowledgement. Native motion, reset, resize, leaks and actual scaler-pass evidence remain open |

The shipped renderer default, engine pin and simulation physics are unchanged by
this preparation. It does not implement a Metal 4 command driver or frame
interpolation. Those require a separately reviewed engine integration and native
evidence; the current pin uses its MTL3 implementation. No renderer or quality
preset was promoted on the basis of Windows tests.

## Operating instructions

Use these authoritative guides instead of copying stale commands from this report:

- [Native Apple Silicon setup and preflight](../../../../tools/godot/README.md#native-apple-silicon-setup-and-preflight-dt-mac-02a).
- [Isolated renderer and MetalFX trials](../../../../tools/graphics/README.md#isolated-mac-renderer-trials-dt-mac).
- [Frame collection and reduction](../../../../research/performance/README.md).
- [First M1 session and acceptance matrix](../../../plans/apple-silicon-performance.md#10-first-test-session-on-the-available-m1).

Use new single-writer output directories. The raw v3 sidecar is part of the report;
retain both files and their hashes. Interrupted/capped prefixes are diagnostic
evidence, never successful sustained runs. `--scripted` is a rendering fixture;
headless captures do not establish active native graphics performance. The direct
technical route does not exercise Home preference loading or packaged launch.

Start with Compatibility on the M1's actual built-in display. Record OS, power,
logical/physical/drawable display dimensions, engine and source identities; run exact local replay and normal
Home/Fly/Workshop checks. Then compare prepared Mobile/Metal and Forward+/Metal
copies with fixed effects/workload. Only evaluate MetalFX after the native
bottleneck and moving-aircraft readability checks justify it. Test actual 1080p
output separately when a suitable display is available; 720p remains the last
compatibility target.

## Windows verification

Focused checks passed against the official Windows 4.8-beta1 engine and Python
fixtures; native Mac qualification is not implied:

| Check | Result / scope |
| --- | --- |
| Editor getter | 10 fixtures on Windows Git Bash and WSL; existing Windows/Linux cache paths and shell syntax checked |
| Template/preflight/correction | Initial combined getter/template/preflight/correction run: 40 tests per platform. Final rerun after shared template-cache hardening: 46 tests per platform, successful with five Windows skips (FIFO and four native export cases) and four WSL skips (native export cases) |
| Research launcher/profile | 21 Python tests, including actual Windows headless identity; 78 profile assertions |
| Research preparation | 13 fixtures including identity, path/copy validation, retained partial failure and atomic receipt publication |
| Stream collector | 112 Godot assertions including 30-minute-equivalent 60/120 Hz streams, bounds, malformed metrics, interruption and late report-path collision |
| Summary/diagnosis | 74 Python tests including legacy reports, long streams, missing/corrupt/oversized input, completion checks and explicit CLI soak-duration gates |
| Real capture | Seven actual headless Main cases: legacy and v3 short captures, frame-cap rejection, external-owner interruption and preservation of a late-created report sentinel |
| Reconstruction/preferences | MetalFX policy 51, shared reconstruction 118, display preferences 160, diagnostics 26, reconstruction history 16, FSR history 11, camera history 25, advanced graphics 146; Settings 1080p/200% and nine-language checks passed |

The shared tree advanced through externally created commits during this work;
the specialists did not commit or revert other workstreams. A detached test snapshot
was frozen from base `1fc7258e6e3f0d8bdbff88da365167f11912b3dd`, working HEAD
`3bfc7d65320320ceaaa8f174b0c977b618e1a6be` plus dirty changes. Its binary patch
SHA-256 is `cc5ca10f80ea6215f4600ba00cd4dc7ae1dbe7f51c5b34c539330a19bce9eb77`.
That first snapshot captured an in-progress UI review edit, and its warm-cache run
correctly rejected a type-inference error. After the specialists finished, the
snapshot was refreshed with their final files at 23:00 UTC: patch SHA-256
`1f481522f13e281324a28667ee2492158c504aadd44f946664074ff9786615b9`, same base and
working HEAD. The final per-file manifest is retained with local check output.
This is not an assertion that the changing shared checkout is one immutable
release candidate.

A later focused shared-tree check covered concurrent FSR runtime-failure changes:
reconstruction (118), MetalFX policy (51), FSR history (16), and advanced graphics
Settings (146) all passed. Reconstruction source stayed unchanged during the run,
SHA-256 `7ccf7d4bddfbfa2f6a236f73fc2ccf983ea8347e7de71f53771d7acae9615efd`.
This supplements the frozen snapshot rather than silently changing its identity.

The reducer subsequently gained optional `--minimum-warmup-s` and
`--minimum-sample-s` gates. Defaults remain 10/60 seconds and the three-run minimum
is unchanged; the Mac procedure explicitly requests 30/1800 seconds and three
independent soaks. CLI tests prove that valid short captures are rejected by that
soak policy without invalidating their collection. This is a separately verified
offline-tool change; the running integration snapshot was not mutated.

The first full-suite attempt exited during fresh import of the existing
`f4u_corsair.glb`, process status `4294967295`, without a script error diagnostic.
The cause was not established. Existing scene import caches were copied into the
snapshot and revalidated by Godot before the second attempt. This second run is
warm-cache software verification, not a successful cold-import qualification.
Final partition outcomes and outstanding failures are recorded below.

The refreshed suite next detected byte-pinned customization sources changed by
the disposable worktree's `core.autocrlf=true` checkout. Twelve presentation files
differed only by CRLF/LF; the live checkout's customization freshness check passed.
The snapshot was synchronized to the exact working-tree bytes (6,792 text/source
files checked, 2,800 copied), without changing the generated registry. Its
freshness check then passed. Final broad verification uses the existing
`integration` partition and four `units` shards, each with a separate user-data
directory; this changes test scheduling, not assertion or acceptance rules.

The complete **integration partition passed**. Its checked collection contains
**1,578 successful invocations**, including **1,538 script-parse checks**, with
zero rejected/invalid reports. The existing report summarizer verified the logs
and emitted JUnit. The suite also completed its Python-driven trace/CLI checks,
negative controls, model contracts, finite frame reports, numerical sensitivity,
and fixed-step/hash comparisons at 30/60/144 FPS. The retained integration log's
SHA-256 is `d8bf7c85e331f2a5f2478b5f8960c8723cb74b30974f9f947927d485d56aaf3e`.
These are Windows software results, not Mac, graphics-performance or physical
validation.

The broad unit run is complete under the existing stop-on-first-failure policy:

| Partition | Checked invocations, including import | Result |
| --- | --- | --- |
| Unit 0/4 | 217 | All passed; 216 selected unit scripts |
| Unit 1/4 | 54 | 53 passed, one failed; stopped at engine audio |
| Unit 2/4 | 62 | 61 passed, one failed; stopped at the fixed-brake reference check |
| Unit 3/4 | 216 | All passed; 215 selected unit scripts |

Across the four partitions, 545 of the frozen snapshot's 861 unit scripts were
attempted: 543 passed and two failed; 316 later scripts in the failed partitions
were not run. The existing named pending-physics policies in `app/test.sh` were
preserved. The checked-report summarizer validated each collection and wrote
JUnit output locally. This is **not a full-suite pass**.

The two failures are outside the edited graphics and capture paths:

- `test_engine_audio.gd`: 146 checks, three device-aware queue-target failures.
  A separate run with fresh user data reproduced two failures of the same assertion
  (exit 1, 60.547 s, not a timeout). Relevant audio source/config and all 370
  baseline-tracked simulation/physics/aircraft files match `c953c8c` after line-ending
  normalization, with the same pinned engine; a pristine baseline was not executed
  and the cause is not established. No audio or physics change was made.
- `test_fixed_gear_brake_input.gd`: 257 checks, two exact frozen-reference failures
  for `sebart-avanti-s-a200-p100rx` (checkpoint/metadata and CSV). The physics path
  was not changed and no golden data was re-recorded. The frozen Windows source
  pin is `3ebd08c2869207e869c3c127da6f0db7be1409a32ab0903b17d3211d0b2807b1`;
  the snapshot aircraft file is `048305d4000829fbcf4b1854bd0a89e506b7b01a6ed4a64f1c758519716dbbbd`.
  Historical commit `b1c6d9806`, before this Mac work, changed its description
  from `Ventage Jet` to `Vantage Jet`; parsed JSON is otherwise identical.
  Aircraft identity hashes include the description and feed checkpoint/trace
  metadata, explaining a provenance difference without establishing changed
  physics. The separate three-tick exact continuation check passed. The combined
  failing assertion does not separate checkpoint and metadata digests, so this
  is not a complete field-by-field runtime attribution. The acceptance failure
  remains open for the reference owner; it is not waived or physical validation.

Local raw check output is under ignored `tmp/dt-mac-prep/`; it is not a release
artifact or a durable substitute for the required native campaign. No screenshots
were added by this task. Existing unrelated trailer/media work was preserved.
