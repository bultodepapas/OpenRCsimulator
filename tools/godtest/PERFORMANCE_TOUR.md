# Three-aircraft performance tour

The `performance-tour` command runs the existing GOD TEST application driver with
the existing continuous frame watcher and process resource sampler. It adds a
runway-position completion check, real Settings/Controls transitions, passive GPU
utilization sampling, and an independently rebuilt suite report. This is the
operating guide for **GOD-12-R1 / GOD-13-R1**, including the 2026-11-21
**GOD-12-R2f/g / GOD-13-R2** measurement hardening; the [GOD TEST plan](../../docs/plans/god-test.md)
owns qualification status. The [general tool guide](README.md) owns source freezing,
other scenarios, and event-stream semantics.

**Next sequence — planned, not implemented:** [GOD-12-R2 / scenic and crash tour](../../docs/plans/god-test.md#4a-planned-scenic-and-crash-tour)
adds runway takeoff, a low right turn past the pavilion/trees and rural house,
one or two same-flight circuits, settings-preserving Home/Pause browsing, a
horizontal roll and intentional aircraft-crash assessment. The commands below
still run **V1**, including its airborne start and lighting Apply. The plan owns
the new sequence and acceptance work; existing V1 results do not qualify V2.

The [independent audit](../../docs/research/god-test/2026-11-20-plan-audit.md) found
V1 execution/monitoring limits as well as V2 design gaps. Read
[managed-host admission](#managed-host-admission) and
[current verification limits](#current-verification-limits) before interpreting a
successful command as a complete rendered screen.
The [implementation follow-up](../../docs/research/god-test/2026-11-21-measurement-hardening.md)
records the corrected guards and their offline verification; it does not implement
the revised scenic/crash sequence.

## Run the complete workload

Use a prepared checkout, the repository's pinned engine, and the Python environment
with [the existing resource dependencies](../godot/requirements-resources.txt).
The command creates a fresh output directory and always retains failed cases.
Examples that pass `--godot`, `--out` or `--snapshot` are for an **unenrolled
standalone host**. On an enrolled host those options belong to the worker and
are refused; use the [managed route](#managed-host-admission).

```sh
python3 tools/godtest/godtest.py performance-tour --dry-run --repeats 3
python3 tools/godtest/godtest.py performance-tour --repeats 3 \
  --resolution 1920x1080 --scene-detail medium \
  --godot /absolute/path/to/the/pinned/Godot \
  --out tmp/performance-tour/baseline-01
```

`--graphics fixed` (the default) keeps the comparison workload: MSAA and other
graphics options stay at the product defaults, and only scene detail, window and pacing come
from the tour. `--graphics automatic` instead writes the first-run recommendation that
a fresh install stores for the GPU it runs on: MSAA, shadows, birds, runway meadow,
aircraft lighting and 3D render scale. The product's own preference writer stores
it, and the case records it as `identity.graphics`. Pair it with the renderer
Automatic would choose; on an integrated GPU that is
`--rendering-method gl_compatibility --scene-detail low`. Fixed and automatic
results are different workloads and are not compared.

The standard screen is three repeats of three aircraft: **nine separate owned
application launches**, in Stik → jet → Corsair order for each repeat. `--repeats 1`
is the first functional smoke run. `--cycles 2` repeats the entire Home/flight/menu
cycle twice inside each aircraft's launch, which is useful for reload and memory
investigations. Neither flag silently omits a failed aircraft.

| Aircraft shown to the player | Catalog identity |
| --- | --- |
| Jensen Das Ugly Stik 60 | `jensen-das-ugly-stik-60` |
| Sebart Avanti S A200 / P100-RX jet | `sebart-avanti-s-a200-p100rx` |
| F4U Corsair 250 | `f4u-corsair-250` |

The tour refuses an aircraft override, partial phase list, alternative landscape,
or isolated entry that would remove the required workload. For one investigation,
use `run runway-menus --aircraft <id>` instead. Normal pause, Settings, Controls,
lighting Apply, Home, and shutdown remain part of every complete tour case.

### What each aircraft actually does

This is the implemented **V1** sequence.

1. Start the real source/debug application through Startup and Home. Wait for a
   verified frame-watcher cursor before aircraft selection, and record for up to
   10 s whether the application window is focused. A flight that then starts
   paused while unfocused (for example on a locked desktop) fails with that cause.
   A headless Wayland compositor without a keyboard seat never focuses any window;
   there the driver substitutes AppRoot's focus probe and records
   `window_focus_probe_override`. Real focus-loss events still pause.
2. Select the required aircraft, Club Field, calm weather, clear sky, day lighting,
   and the recorded sky seed through the application. Weather keeps its preset's
   own turbulence seed, so it stays an exact preset that the Mac native domain
   admits. Verify the selected, loaded
   flight, and model aircraft IDs. Begin with the product's accepted airborne
   start, then stabilize the physical aircraft with ordinary control input.
3. Fly a clockwise circuit enclosing the loaded runway. The observer uses accepted
   north/east positions, requires all four quadrants and a full signed revolution,
   and keeps the aircraft within a continuous annulus outside the runway corners
   at 20–140 m AGL for at least ten simulated seconds. Radius scales with trim
   speed. A corridor excursion resets lap credit; reverse turns, stationary
   heading changes and partial arcs cannot pass. Bearing jumps over 45° and
   segments crossing the protected runway radius are rejected; this observer
   does not independently bound every small displacement by elapsed time.
4. Pause for at least five wall seconds. Verify the tick and physical state do not
   change. Resume and verify continuing ticks and a healthy, unobstructed flight.
5. Open the actual Settings screen through Pause, dwell, return, and resume.
   Repeat for Controls. Verify enabled/visible buttons, screen ownership, the
   same bound session, pause invariants, input ownership and healthy tick progress
   throughout each resumed dwell.
6. Exercise the existing lighting settings/Apply transition, resume, return Home,
   and close the owned process. A late accident, fault, pilot failure, missing
   screen close, reference-backend fallback, dropped recording, or forced exit
   cannot become a successful performance screen.

The circuit is an orbit around the runway, not a rectangular landing pattern. The
pilot is experimental and supplies commands through the existing input adapter;
it does not move the aircraft by teleporting or change the 240 Hz physics laws.
Takeoff, aerobatics and landing are outside this three-aircraft workload. Those
remain in the existing calibrated/experimental GOD TEST scenarios. Menu actions
exercise real UI handlers; they do not qualify physical keyboard, mouse or radio
input latency.

## Managed host admission

On an enrolled host, execution through `godtest.py` delegates to the existing
queue. The queue owns the engine, output and source snapshot; it rejects caller
`--godot`, `--out` and `--snapshot`, and does not accept `resume` as an execution
preset. Offline `list`, `--dry-run`, `report` and `compare` are not launches.

Inspect `performance-tour --repeats 3 --dry-run` before requesting resources.
Automatic `godtest.py` submission now calculates and passes a lease for every
expanded case, including repeats and documented preparation/cleanup reserves.
The nine-case plan with `--repeats 3` and otherwise default settings has 8,100 s
of scenario timeouts and a **14,924 s**
execution lease; one three-aircraft pass receives **5,630 s**. The dry-run output
exposes `case_timeout_sum_seconds` and `managed_admission`, not a claimed total
wall-time bound. A calculated lease over **21,600 s** is rejected before submission
without removing cases. Worker-owned paths and external manifests are rejected
before plan IO; option abbreviations are disabled at the worker parser as well.

The existing explicit
`testctl.py snapshot` / `submit --preset godtest` route accepts validated `--options`
with a timeout up to 21,600 s. Follow the [queue guide](../testqueue/README.md) for
a fresh snapshot outside the source checkout, matching source, owner/platform,
durable submission receipt, returned job/handle and evidence collection.

This explicit graphical adapter is **Windows-local and experimental**. The local
worker advertises Linux/macOS as unsupported; checked-pool SSH access is not a
qualified graphical campaign route. Use standalone instructions only on a genuinely
unenrolled target; an enrolled unsupported target needs an admitted platform adapter.
Verify the deployed authority's source and capabilities, not only local source.

Worker options contain the tour arguments without worker-owned paths and a declared
execution budget above the expanded cases plus adapter preparation/imports, reduction
and cleanup reserve. The `--options` shape is
`{"argv":["performance-tour","--repeats","3"],"timeout":N}`, with `N` replaced by
the preflight's validated execution budget in seconds (at most 21,600).
**Direct preset submission does not calculate or enforce the full-roster minimum**;
its generic default remains 3,600 s and an explicit shorter lease can still be
accepted. Use the matching source's dry-run calculation when taking that route.
The execution lease is not a completion guarantee: filesystem/reduction work has
a disclosed planning allowance, and queue waiting and worker preparation before
adapter process creation have separate scope.
Retain the private submission receipt and returned owner handle; a wait timeout does
not cancel the job. Inspect `status`/`result` for **FINISHED**, **cleanup CONFIRMED**,
**evidence COMPLETE**, then the actual `<attempt-output>/godtest` artifacts.
These states alone do not qualify performance.

Bounded preparation/storage, direct-preset budget enforcement, graphical platform
admission and source-bound enrolled-host resume remain
[GOD-13-R2 work](../../docs/plans/god-test.md#13-execution-steps-and-evidence-ledger).
If the budget or recovery route cannot be admitted, retain the refusal and start no
duplicate. Do not bypass enrollment, inherit another owner's handle or split the
roster into untracked jobs and call them the original complete suite.

## Target machines and display contract

Run each campaign on its actual OS, physical GPU and visible desktop. The desktop
must stay unlocked and undisturbed: a flight pauses on any OS focus loss, and the
case then fails. On macOS a locked screen keeps `loginwindow` in front, so even a
LaunchServices launch from SSH gets no focus. On a Wayland-only Linux session,
`debugctl` passes `--display-driver wayland` (Godot otherwise tries X11 and exits).
There Godot also reports the window undrawable during any stall longer than its
frame-event timeout (about 1 s); those intervals still invalidate render evidence
and are marked as freezes.

On a **headless Linux host** run Godot on X11 through the compositor's Xwayland:
`weston --backend=headless --renderer=gl --shell=kiosk --xwayland`, then `DISPLAY` set
and `WAYLAND_DISPLAY` unset. The host needs `xwayland` and the X11 client libraries
Godot loads at runtime (`libxcursor1 libxinerama1 libxrandr2 libxi6 libxrender1
libxext6`). Godot's Wayland backend does not suit a compositor that sends no input or
frame events: shutdown joins its events thread, which waits in an untimed `poll()`, so
6 of 21 cases there needed a forced kill. Its frame-timeout suspension also made a
single 1.7 s startup frame invalidate the phase. On the same UHD 630 hosts X11 gave
complete, valid cases and clean exits; Xwayland composition cost about 8 % of
flight FPS. The [2026-11-22 comparison](../../docs/research/god-test/2026-11-22-linux-uhd630-comparison.md)
records the evidence. Use the
[existing host admission](../testqueue/README.md) on enrolled machines. The CLI
retains its owning session through cleanup; the checked headless pool is not a
replacement for a rendered performance run. Use [the Mac guide](../../docs/tools/macos-m1.md)
or [the Linux access guide](../../docs/tools/linux-ssh.md) for configured hosts.
Hostnames, credentials and personal paths stay outside this repository.

| Target | Automatic tour renderer | Primary display run | GPU utilization source |
| --- | --- | --- | --- |
| Apple Silicon MacBook | Mobile / Metal | Native panel pixels, borderless; 1080p is a separate configuration | AGX `ioreg` statistics |
| Linux with a physical GPU and active X11/Wayland desktop | Forward+ / Vulkan | 1920×1080 first | NVIDIA `nvidia-smi`; AMDGPU read-only sysfs |
| Windows with a physical GPU and interactive desktop | Forward+ / Vulkan | 1920×1080 first | NVIDIA `nvidia-smi` |

These are explicit benchmark defaults. Check the **actual** renderer, driver,
resolution, backend and GPU identity in the report. A requested setting is not
proof it took effect. A software renderer is ineligible. A headless run validates
control flow and artifacts only; Xvfb/llvmpipe does not qualify the Linux GPU.
The driver samples applied window mode, VSync, frame cap and window/viewport size
after Home, at each completed phase, and before shutdown; the rendered reducer
refuses missing observations or settings that the platform did not apply.

Example for a 2560×1600 MacBook panel, using the prepared native source editor:

```sh
python3 tools/godtest/godtest.py performance-tour --repeats 3 \
  --window-mode borderless --resolution 2560x1600 \
  --rendering-method mobile --rendering-driver metal \
  --godot /absolute/path/Godot.app/Contents/MacOS/Godot \
  --out tmp/performance-tour/macbook-native-01
```

Use the measured panel dimensions for the actual Mac; 2560×1600 is an example,
not an automatic hardware detection result. Additional Mac panel sizes are
admitted in borderless mode. Mirroring or a different active screen can change
the output; a dimension mismatch fails the screen. The report distinguishes
requested window pixels and observed viewport coordinates. Native drawable and
internal reconstructed 3D pixels still need the [Apple acceptance checks](../../docs/plans/apple-silicon-performance.md).
This tour seeds native reconstruction; it does not claim MetalFX qualification.
The standalone example does not establish Mac graphical-worker admission, panel
pixel proof or native performance; those remain separate prerequisites.

Windows uses the same Python entry point, normally with the console editor:

```powershell
python tools/godtest/godtest.py performance-tour --repeats 3 `
  --resolution 1920x1080 --rendering-method forward_plus --rendering-driver vulkan `
  --godot 'C:\absolute\path\Godot_v4.8-beta2_win64_console.exe' `
  --out 'U:\OpenRC-perf\baseline-01'
```

Prepare and verify the [native physics backend](../../research/native-kernel/README.md#normal-flight-backend-selection)
for the exact source/engine/architecture before rendered runs. Actual native
selection is mandatory for this workload. On Windows and Linux, a rendered
`require_native` case refuses before creating its output (exit 2) when the installed
receipt's Godot executable, kernel binary or any mirrored source's raw bytes differ.
This early hint is not a qualification: the runtime backend receipt stays
authoritative, and macOS relies on it alone. Source/debug execution on macOS has
an implemented isolation adapter; release-export execution and native target
hardware acceptance remain separate work.

On macOS the canonical snapshot is unchanged. A verified per-run APFS copy changes
only `application/config/name` to a unique `OpenRC-GodTest-<uuid>`. Its fresh profile
is created in macOS Application Support and checked against the running project
before settings are written. `launch-snapshot.json` records original/launch
project hashes and the exact profile directory. Preserve that directory with the
run until evidence retention is complete. Linux and Windows use the existing
run-local profile redirection. No launcher repurposes the account's `HOME`.
When a benchmark is requested, Startup exits before reading preferences or
loading Home if the debug observer or its private-profile check is unavailable.
Godot's [user-data path contract](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html#accessing-persistent-user-data-user)
explains why the Mac needs the distinct adapter.

### Preflight and repeats

Use the pinned engine and current imports, a matching native artifact, and a fresh
output directory. Sparse checkouts must include the authoring receipts referenced
by `app/data/aircraft_models` and `aircraft_model_overlays`; missing inputs are
refused before launch. Keep the same revision, renderer, viewport, quality, camera,
aircraft order, weather, seed and pacing settings throughout a comparison.

Connect AC power, keep the lid/display active, and record the power mode, screen
refresh rate, driver, OS and background load. Stop competing simulator, capture,
encoder and GPU workloads through their owners. Allow a consistent idle/thermal
period between comparison blocks. Retain temperature/clock/power readings where
the backend supplies them. For Mac thermal/energy detail use the existing
[host-state helper](../godot/README.md) in a separately documented diagnostic run.

The default is uncapped with VSync disabled, so a cap cannot hide available
capacity. `--max-fps 60 --vsync-mode enabled` defines a separate player-pacing
campaign. Do not combine these populations. Every launch has fresh preferences
with the Master bus muted (`master_volume = 0`, recorded in `profile_overrides`);
audio streams and mixing still run. On Linux without an accessible ALSA playback
device (`/dev/snd/pcmC*D*p`; containers can list the host's cards in
`/proc/asound/cards` without one), the runner launches Godot's Dummy driver, which
still mixes every period at real-time pace, and records `audio_output` in
`execution.json`. Do not give such a host a `pcm null` ALSA default: it never
blocks, so Godot's mix thread spins a full core while holding the audio lock and
stalls loading (13.6–19.0 s instead of 6.5 s Home → flight on a UHD 630). Source copying and prior launches may warm OS/driver caches. These are not proven
OS-cold or shader-cold measurements, and the runner does not clear global caches.

## Metrics, evidence and verdicts

| Evidence | What it tells us | Limits retained |
| --- | --- | --- |
| Verified GOD TEST frame stream and phase events | Mean callback FPS, p50/p95/p99/worst intervals, 1% and 0.1% lows; time and counts above 16.667/33.333/50/100 ms; startup/loading and menu latency | Callback intervals, not presented frames; short-tail estimates are labeled |
| Existing continuous `frames watch` | Relative stutter, absolute stalls, sustained slow frames, FPS-drop episodes, frozen-frame observations, bounded incident lead-up/recovery and per-second/route views | Armed after initial Home; gaps, detector warmup, clipped edges and capture limits stay visible |
| Existing `ResourceSampler` | Direct-process CPU time and percentage, RSS/virtual memory, thread count, available host memory and process I/O | 100% means one logical CPU; may exceed 100%; no descendant totals or same-frame CPU attribution |
| Passive GPU sampler | Device-wide utilization; clocks, temperature, power and memory when supported; every observed device has its own identity | Other processes contribute; the rendering GPU is not automatically identified; Apple memory is shared memory |
| Runtime and frozen-source receipts | Aircraft/model/backend/engine/source identity, actual settings, trajectory, pause invariants, laps, completion and clean exit | These are software observations, not aircraft realism or pilot acceptance |

CPU/GPU monitoring is automatic for the tour. Intel GPUs and Windows AMD GPUs do
not currently have a utilization backend here. Unsupported counters are `null`
with a reason. Missing utilization, tool errors, changing devices, exhausted
sample caps or a worker that fails to stop make monitoring incomplete; they never
become zero-load readings. Optional unsupported temperature/power counters do not
invalidate otherwise complete utilization coverage.
Both samplers now need raw timing proof tied to the runner's independently recorded
owner windows. Their fixed contract is **1 Hz, at most 4,000 samples**; a raw artifact
cannot enlarge its own gap allowance. First, inter-observation and tail gaps must
stay within **3.25 s**, using conservative poll/query brackets. CPU required-field
statuses/counts, identity, counters and clean uncapped completion are checked
separately. GPU timing is recomputed for each observed device. At least two usable
observations are required; optional sensors remain optional. CPU must start before
GPU, and GPU must stop after CPU has finished, matching the recorded runner lifecycle.
Changed or unreadable observer code, an unexplained worker exit, or absent raw
samples prevent complete monitoring even when a summary says `available`.
Post-stop GPU readings are retained but do not establish pre-stop coverage. Starts
within the declared 50 ms stop race are excluded; later backend starts make coverage
incomplete. This conservative policy can reject a sequential multi-backend poll
that started before shutdown. Historical artifacts without owner receipts retain
their observations but cannot receive a complete monitoring verdict.
On Linux, an absent vendor backend is marked not applicable only when a readable,
consistent PCI/DRM inventory supports that conclusion; an absent executable by
itself is insufficient. This inventory does not identify the GPU rendering Godot.

Each suite has `suite.json`, `report.json`, and `report.html`. Each aircraft run
retains requested/resolved manifests, source/launch receipts, `runtime.json`,
`events.jsonl`, `trajectory.csv`, frame stream/receipt, `execution.json`, engine
logs, `resources.json`, `gpu.json`, and `frame-watch/` reports/incidents. The suite
report rebuilds child reports and verifies roster, source bytes, settings and
ordered phase coverage; it does not trust a cached `complete` flag. Do not remove
the referenced frozen source/import directory while reports need revalidation.

`data`, `coverage`, `monitoring` and `performance` are independent. A useful frame
recording can survive an unavailable GPU counter or a failed maneuver. A rendered
tour requires valid complete recordings and complete monitoring for successful
screen execution. Even then `performance=screen_only` is **not** a hardware
qualification or regression pass. Headless runs remain `not_qualified`.

Requested graphics cannot silently become a successful headless result. Reports
bind the original and resolved manifests, renderer receipt and diagnostics, strict
phase labels and raw draw counters. Each requested phase needs drawability and
positive draw progress inside that phase; a boundary-crossing frame alone is
insufficient. A missing or contradictory receipt makes coverage partial and data
ineligible. One narrow exception exists: during `startup`, intervals that still
draw within 2 s after the window's single observed switch into fullscreen carry
`render_window_transition` and count as `window_mode_transition_intervals`. macOS
reports its fullscreen Space animation (about 0.5 s on the M1) as undrawable. Any
other undrawable or zero-draw interval still invalidates the phase. Likewise, focus
losses inside `startup` precede any flight session and are not flagged; later
losses are. Explicit headless functional runs remain available without graphics
qualification. `reducer_sources` and the aggregate `reducer_sha256` include the
helper modules that now affect acceptance.

The established flight targets are p95 ≤18 ms, p99 ≤25 ms, and simulation/wall
pace near one. Startup and loading retain their own scope-specific targets.
Frame, simulation-pace and loading misses appear in suite observations. Child and
suite JSON/HTML now show phase-total pace, worst/fastest supported one-second pace,
maximum observed accumulated lag and missed/inconclusive screen targets.
The local reducer uses verified tick differences at 240 Hz. It excludes pauses,
crash holds and cross-phase intervals, rejects inadequate clock precision and
requires at least 0.9 s and two intervals per supported full window. Unsupported
windows, less than 90% supported active wall time or a boundary exclusion over
100 ms make local pace coverage unavailable; an unscored partial tail also prevents
a positive local target. Supported bad windows remain visible even when the phase
average recovers. First/boundary exclusions and all partial-window support remain
in the case JSON. These are exploratory observations, not diagnoses or a statistical
target pass. Inspect the exact affected phase, especially menu/loading
stalls that should not be averaged into steady flight. Per-phase 1%/0.1% lows use
the reciprocal of the mean of the slowest `max(1, floor(N*fraction))` intervals.
Watcher stutter/stall totals are overall; incident snippets cannot establish
complete per-phase stutter counts.

Repeats report medians and ranges of per-run phase statistics, never a pooled
percentile across unlike phases or machines. Compare a baseline and one candidate
on the **same physical machine**, alternating A/B blocks with matched conditions.
Keep all attempts, including failed runs and thermal outliers, and explain any
exclusion. The existing `compare --phase loading` and other admitted transition
comparisons are exploratory. Adaptive pilot routes and repeated A/B significance
are not yet qualified for an automatic whole-flight regression verdict.

### Current verification limits

The [2026-11-20 audit](../../docs/research/god-test/2026-11-20-plan-audit.md) is the
historical source review. The [2026-11-21 follow-up](../../docs/research/god-test/2026-11-21-measurement-hardening.md)
records implemented corrections and verification. The [plan](../../docs/plans/god-test.md)
keeps the remaining acceptance work explicit.

| Current V1 observation | Required interpretation |
| --- | --- |
| Requested render mode, raw drawing and required-phase receipts are now enforced in reports and CLI success | This proves engine observations only; physical presentation, drawable pixels and actual rendering-GPU association remain open. |
| CPU/GPU owner windows, raw gaps, sampling configuration and cross-observer order are now checked | Complete means bounded discrete observations during the recorded owner windows; no continuous or per-frame resource-cost claim follows. |
| GPU samples identify observed devices, separately from Godot's renderer | Retain a positive renderer-to-device association and physical-host identity; a sampled idle NVIDIA device does not prove utilization of an Intel renderer. |
| Samplers and engine phases use different monotonic clock domains | No automatic per-panel, impact or same-frame CPU/GPU attribution exists. A 1 Hz poll can miss a short event even after alignment. |
| Watcher coverage begins after initial Home; OS owner windows start after bridge readiness/setup | Earlier startup and observer setup are unobserved by those tools. No prompt-start claim is made from the bridge boundary. The first in-app collector interval is a bootstrap span, not guaranteed callback pacing. |
| Low-FPS tail `available` can still mean one slow tail observation; target booleans exist for short phases | Show count/duration/tail support and keep short-event tails exploratory. Exit 0 / `screen_only` does not mean performance targets passed. |
| Phase-total and local simulation pace, lag and targets now appear in child/suite JSON and HTML | Partial tails and unsupported coverage remain inconclusive; local windows are exploratory and can miss peaks between callbacks. |
| Retry summaries are retained in `suite.json`; selected cases are revalidated | Earlier failed attempts are not all revalidated/displayed. Preserve and inspect them and their ancestor source paths explicitly. |
| The transition comparator checks only part of the documented identity/coverage contract | `eligible=true` is exploratory, not proof of the same physical host, actual GPU, observer bytes or complete monitoring. |

An engine hash proves the selected bytes stayed the same; independently verify the
official pin and platform-native libraries/bundle. A window/viewport size is not
native drawable or internal 3D pixel proof. A host preflight or separate thermal
diagnostic does not establish power/thermal state throughout the measured tour.
Observer-cost controls and all three real-hardware campaigns remain open.

## Investigate and optimize from the evidence

Use the tour as a repeatable detector, then run the narrow diagnostic indicated by
the result. Heavy tracing or screenshots are separate from the measured baseline.
The [2026-11-21 stutter map](../../docs/research/god-test/2026-11-21-stutter-map.md)
marks the freezes detected on Windows and the M1.

| Observed symptom | Next existing tool | Controlled optimization experiment |
| --- | --- | --- |
| Brief hitch, freeze or FPS collapse | Retained `frame-watch/report.html`, its incidents, `timeline --stutter`, or `frames --out` | Reproduce the same phase; inspect loading, shader work, allocations, I/O and observer markers |
| High process CPU with GPU headroom | `launch --script-profile` / `profile`, [native development tools](../../research/native-kernel/README.md#c-development-tools-nk-3) | Change one measured hot path; verify unchanged physics and rerun the same circuit |
| High GPU utilization / render cost | `render`, `layers`, `ablate`; [graphics ladder](../../research/performance/graphics_ladder/README.md) | One quality feature or resolution change at a time; retain visual acceptance and actual pixels |
| First-load or menu-only spike | GOD TEST selection/loading/menu phases and verbose `timeline` | Separate asset decode, preparation, upload and scene attachment; compare initial and repeated entries |
| Increasing memory across Home/flight cycles | `--cycles`, existing `memory`, `objects`, `soak` and [resource tools](../godot/README.md) | Check lifecycle/resource release; distinguish retained caches from monotonic growth |
| Mac slowdown with clock/thermal changes | Existing Mac host-state helper; Instruments/Metal tools when available | Match power/display/cooling conditions before attributing the effect to a code change |
| Windows/Linux presentation or GPU-driver question | PresentMon, Nsight, RenderDoc, RGP or system tracing as appropriate to the installed GPU/API | Retain the external trace and exact identity as a separate attachment; quantify observer overhead |

The [debug investigation guide](../debug/README.md#choose-the-next-investigation)
owns the commands and supported export formats. Do not feed the event-bounded
GOD TEST stream into a fixed-duration native diagnosis or Perfetto importer as if
it were that tool's own format. Use the existing debug snapshot exporter for
HTML/CSV/JSON/Perfetto evidence and preserve its original receipts. GPU polls and
viewport timestamps may lag; correlation alone does not prove the cause of a hitch.

An optimization closes only with a matched before/after result, no missing cases,
unchanged required behavior, and a record of remaining platform limits. Do not
claim a general FPS gain from a headless test, a single counter or one aircraft.

## Recovery and verification

```sh
python3 tools/godtest/godtest.py report tmp/performance-tour/baseline-01
python3 tools/godtest/godtest.py resume tmp/performance-tour/baseline-01 \
  --out tmp/performance-tour/baseline-01-retry
python3 -m unittest discover -s tools/godtest -p 'test_*.py'
python3 -m unittest discover -s tools/debug -p 'test_frame_watch.py'
```

Before retrying after a lost supervisor, reconcile its owned process and host
admission. Resume retains prior attempts and matching frozen inputs; it must not
launch a duplicate session with uncertain ownership. Preserve the original suite
and source receipts so reused cases remain auditable.
The index retains the entire planned roster before the first launch and preserves
later completed cases through another interruption or a refused retry. Resume
requires the original engine bytes, observers, frozen inputs and the same OS
installation and boot. Host/boot IDs use hashes of the existing host-admission
identities; cloned machine IDs cannot distinguish physical machines. An unknown
owner, old index without these receipts, changed observer, another machine or a
reboot requires reconciliation or a fresh campaign. A preflight refusal retains
the original case references in the new index. The launcher pins the hashed engine
path and checks its command and executable bytes again after shutdown.

The `resume` example above is currently an **unenrolled-host** operation; enrolled
standalone resume is refused. Even on an unenrolled host, a started case missing
`execution.json` or verified shutdown, a reboot or incompatible retained identity
can require a fresh campaign. Manual reconciliation does not create an input the
current resume implementation accepts. Never edit receipts to force a retry.
Preserve all ancestor suites, failed-attempt directories, frozen source/import paths
and Mac launch copies/profiles until revalidation is complete. The current report
uses their original absolute paths and does not fully revalidate old attempt entries;
relocating an archive is not currently an automatic recovery operation.

For functional development only:

```sh
python3 tools/godtest/godtest.py performance-tour --headless --repeats 1 \
  --godot /absolute/path/to/the/pinned/Godot --out tmp/performance-tour/functional-01
```

Run the standalone `research/performance/godtest/test_runway_circuit.gd` through
the [checked runner](../godot/README.md) with completion marker
`GOD_RUNWAY_CIRCUIT_TESTS: 0 failed`. The menu guard fixture
`research/performance/godtest/test_menu_safety.gd` additionally requires
`OPENRC_GODTEST_TEST_PROFILE` and the OS profile redirection to identify the same
fresh directory; require `GOD_MENU_SAFETY_TESTS: 0 failed`. Never point that fixture
at a player's profile. The fixture validates guards and product settings, not a
rendered flight.
The Startup refusal fixture `research/performance/godtest/test_startup_guard.gd`
uses the same checked runner with a fresh redirected profile and completion marker
`GOD_STARTUP_GUARD_TESTS: 0 failed`.

The `GOD TEST portable tooling` workflow runs Python fixtures on Linux, Windows
and macOS. Existing full CI gates remain unchanged. Hosted CI, synthetic GPU
fixtures and headless functional runs do not substitute for the three real
hardware campaigns above.
