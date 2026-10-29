# Cinematic trailer tools

TRA-02…07 presentation tools for the English film **Every Input Matters** (current cut: 58 seconds; [2026-10-21 runtime refresh](../../docs/research/cinematic-trailer/refresh-2026-10-21.md)).
See the [production plan](../../docs/plans/cinematic-trailer.md) and its linked evidence for scope and results.
No tool here edits the simulation kernel, aircraft data, damage assessment or prices.

## Capture

Use the pinned official Godot **4.8-beta1**, Compatibility/OpenGL, and the repository's existing imported assets.
The dated trailer refresh retains its original engine scope; these instructions do not establish a new paired trailer qualification.
Run `prepare_runtime.ps1` first. It creates `tmp/trailer/runtime/app` with a copied project configuration
whose startup viewport is 1920×1080. Its directories are junctions to the working repository: this is
an isolated capture configuration, **not a frozen source checkout**. Do not recursively delete its
junction targets. Retain the source identities with each production export.

`render_flights.ps1` captures the six ordinary fixed-wing shots serially. The flight driver supplies
pilot commands through the real session and observes the resulting state; it does not keyframe a
flight trajectory. `capture_vehicles.gd` uses the production application routes and normal keyboard
events for the helicopter and both cars. Keep captures focused: the production app can pause on
focus loss. A successful process exit alone is insufficient; inspect the capture manifest and logs.

Launch real-session captures with `--fixed-fps 60 --write-movie <absolute.avi>` and the isolated
project. Godot initializes the movie writer before a script can change window dimensions, so a
later `root.size` assignment or `--resolution` alone does not establish native 1080p recording.
Movie Maker provides synchronized 48 kHz PCM audio. Trim the recorded startup frames using each
manifest, not one shared offset: the accepted flight captures have 3 lead frames; vehicle routes
have their own measured offsets.

`capture_flight.gd --director-script=<absolute.gd>` selects a shot-specific command/camera driver.
The capture manifest retains that path, resolved world conditions and native lighting settings.
`extra_rolls_director.gd` supplies normal pilot commands for the six-second roll sequence and
records aircraft attitude, inputs and framing. `lumber_dusk_director.gd` changes only the camera
for a closer front-quarter sunset view. Its accepted take uses native field lighting with
`--time=21:51` (the world's reference location/date, not the computer's local timezone).
Use `--movie-only` with Movie Maker and inspect extracted AVI frames; optional viewport PNGs
can inherit a decorated window's client size even when Movie Maker records native 1920×1080.
Create the `--write-movie` parent directory before launching Godot: Movie Maker opens its file
before the capture script runs, so the script's output-directory creation is too late for that file.

**Mobile renderer:** production worlds and the magnifier require HDR viewport precision at night.
The pinned engine's RGBAH Movie Maker conversion writes incorrect pixels, so this harness rejects
Mobile `--write-movie` captures. Omit `--write-movie` and `--movie-only`, keep `--fixed-fps 60`, and
capture the PNG sequence instead. PNG readback is converted from linear HDR to sRGB before
8-bit quantization; it is not an artistic brightness adjustment. Encode a complete sequence with
the existing FFmpeg: `ffmpeg -framerate 60 -i frame_%05d.png -c:v libx264 -crf 18 -pix_fmt yuv420p review.mp4`.
Do not use `--sample-every` when creating a continuous movie. The manifest records root/inset HDR
flags and PNG color space. Sparse PNG captures are inspection samples, not full motion-video proof.

For RGB acceptance captures, `capture_flight.gd --lighting-preset=<id>` freezes an ordinary
Workshop trial from the chosen stock aircraft and built-in preset (`classic_rc`, `night_radian`,
`neon_rgb`, `night_aerobatics`, `festival`, `custom`). It does not save a build or modify physics.
Pass `--time_of_day=night` to the capture process for the existing moonlit world. `--shot=lighting-pass`
uses neutral flight controls with the existing trimmed throttle plus 0.08 and a moving close camera;
`--shot=lighting-pilot` uses the same controls with the production pilot camera, auto-zoom off and
the magnifier on. No previously recorded `.orfl` tape is replayed by these shots.

Select either existing world with `--landscape=club_field|green_paradise` (default `club_field`).
The harness validates the catalog ID and passes it to Main's normal landscape loader. Its manifest
records the requested/resolved ID, actual field path and field-file hash. Keep the same landscape
for paired cost or preset comparisons; a Green Paradise run cannot establish Club scenery cost.

Lighting trials have **no smoke by default**: `--smoke-pump=on` cannot activate an empty profile.
Add `--lighting-smoke=stock` to include the aircraft's existing authored stock source/show outlets
in either a preset or custom lighting capture. The harness freezes the ordinary Workshop profile
and verifies identical physical trial identity/data before and after adding smoke. Unsupported
aircraft refuse the request; no outlet or smoke source is inferred. `--lighting-smoke=off` is the
default. The manifest records the resolved stock preset and production smoke allocation/status;
RGB frame records expose it as `smoke_effects` (the older `smoke` field describes legacy exhaust).

The real-time mode also accepts this explicit stock-smoke workload and samples its production
status/allocation once per second beside the RGB counters. Compare OFF/Classic/Festival with
the **same** smoke option; the option changes presentation identity, not physical identity.
The default `--lighting-flight=workshop` route freezes the same detached trial used by Workshop;
companion options remain unavailable there. For the normal stock-aircraft workload, use
`--lighting-flight=normal --lighting-preset=festival --lighting-smoke=stock` and optionally
`--companions=3 --companions-seed=1`. Normal mode admits the six immutable choices (including
OFF), requires a preset, and rejects custom profile files. Both routes default smoke to `off`.
The harness starts ordinary Main, preserves its companion admission, then installs the approved
render rig through the existing API. Main owns its clock, mode, magnifier tags, resets and disposal.
Tick/time/float64 state/aux are checked around installation; this instantaneous guard does not
replace matched-flight physics evidence.

The manifest records the route, applied lighting profile hash, smoke profile/status and actual
companion counts/source identity. Missing/faulted/crashed companions invalidate the requested
workload at startup, every observed frame and completion. Stock smoke must resolve to a live
production renderer; unsupported aircraft fail explicitly. `--companions-record` remains refused;
use the dedicated companion recorder separately. A current qualification mismatch fails through
Main's ordinary admission and leaves an incomplete manifest. Never re-pin accepted profiles to
make a lighting measurement run. A full companion/field/smoke qualification still requires valid
companion source acceptance and its own uncontended timing evidence.

For a custom Workshop lighting draft, `--lighting-profile=<absolute.json>` accepts one bounded
data-only `openrc-aircraft-lighting` v1 profile (at most `LightingProfile.MAX_PROFILE_BYTES`).
The existing LightingProfile validator and `Trial.freeze()` build the detached Workshop trial;
the manifest records the input file SHA-256 and frozen Workshop presentation identity. This option
is mutually exclusive with `--lighting-preset` and is offline-capture only; `--frametimes` remains
preset-only. For a moving two-roll trail check, use the existing Extra director with
`--aircraft=gp-extra-300s-60 --director-script=<absolute path to extra_rolls_director.gd>
--shot=extra-roll --seconds=6`. The focused profile check can optionally write its admitted Night
Aerobatics trail fixture with `--trail-profile-out=<new absolute path>`; see
[`test_lighting_capture_profile.gd`](test_lighting_capture_profile.gd). The capture refuses an
input profile path that aliases its output `manifest.json`.

For full-airframe roll inspection, use that same Extra director with
`--shot=extra-roll-inspection --seconds=6`. It preserves the flight commands and moves the
camera rail 1.7 times farther away; the original `extra-roll` trailer framing is unchanged.
Each record includes `camera.inspection_framing` and the existing projected mesh-AABB bounds.
Those conservative bounds support a framing check; they are not measured lit-pixel coverage,
wing span or pilot readability. Keep source clips and inspect the complete motion as well.

For a continuous ground/departure lighting take, use
`--aircraft=jensen-das-ugly-stik-60 --start=runway --shot=lighting-takeoff --seconds=12`
with `--director-script=<absolute path to takeoff_director.gd>` and a lighting preset/profile.
This adapter reuses `app/scenery/takeoff_pilot.gd` through production Main: idle, throttle ramp,
rotation and climb, with ordinary pilot commands and a close chase camera. It is an estimated
Stik test scenario, not a general autopilot or an approach controller. Other aircraft, shots and
airborne starts are refused. Both catalog landscapes remain available.

Its `runway_departure` fields describe the accepted tick endpoint, explicitly labeled with
`state_sample` and `state_tick`; the base frame's visual pose remains interpolated. Records retain
pilot phase/time, speed, altitude, heading error, gear compression/support/clearance, hull contact
and the pilot-source hash. Wheel support uses positive gear compression; hull contact is a separate
crash predicate. Generic capture completion does not certify liftoff: check the recorded wheel
clearance, phase progression and advancing climb alongside the source movie.

For a synthetic-entry approach lighting take, use
`--aircraft=jensen-das-ugly-stik-60 --start=airborne --shot=lighting-approach --seconds=12`
with `--director-script=<absolute path to approach_director.gd>`. This adapter reuses
`app/sim/landing_maneuver.gd`, limited to its calm, wash-off Stik condition. It stages the
existing test's eastbound entry at 12 m/s and 6 m CG altitude, 94 m before the runway end,
then resets once before capture and delegates all subsequent motion to the live session.
The fixture selects reference-speed trim, sets altitude before solving it, and verifies that
reset preserved the exact declared state. Unsupported starts, aircraft and weather are refused.

The first frame's `approach_fixture` records initial state, solved trims and controller/session
source hashes. `continuous_from_runway=false` explicitly distinguishes this fixture from a
complete circuit. Per-frame/tick `approach` observations retain accepted endpoint phase,
speed, CG sink/height, gear support, minimum wheel-reference runway margin and maximum
wheel-reference sink including body rotation. These endpoints are not the interpolated visual
pose; the first image follows the initial reset by several accepted ticks. Hull contact remains
separate from wheel support. The 12-second take covers approach, flare and early rollout;
it does not prove a stopped or physically validated landing. Report the existing landing test's
0.5 m margin separately from actual runway containment, and retain failures rather than
retuning the controller or moving the entry to hide them.

An external director may expose `configuration_error() -> String`. A nonempty result after
`configure()` rejects the capture before the director enters the scene, writes a zero-frame
incomplete manifest and uses the normal scene/audio teardown. Directors should validate before
changing input/camera state. Existing directors without this optional method retain their route.

Each RGB frame records the actual rig allocation counters and world exposure. Pilot captures also record the visible
inset's dimensions, camera and AA mode. The main view uses 4× MSAA; the production inset uses 2×.
The manifest retains physical/presentation trial identities and capture/director/main/registry hashes.
The prepared runtime uses source junctions; those hashes do not make a shared checkout immutable.
These are offline moving-image checks,
not real-time GPU benchmarks or pilot acceptance. Respect the renderer's distance/quality limits:
the active pilot magnifier can improve aircraft-specific VFX birth detail and distance fading when
its projected view is more useful, while fixed scene-wide grant caps and main-view spill distance
rules remain unchanged. Every `--lighting-preset` or `--lighting-profile` capture, including a
custom director such as `extra_rolls_director.gd`, receives live RGB allocation and world-exposure
fields from the harness. Its director must append
exactly one record for the current frame and simulation tick; missing or inconsistent evidence
fails the capture. The existing Extra director uses `--shot=extra-roll --seconds=6` for its ordinary
two-roll maneuver, so it can inspect `--lighting-preset=night_aerobatics` without a second controller.
Lighting shots and all explicit lighting-preset/profile captures reject pauses, faults, crashes or a stalled tick counter, retaining an incomplete
manifest with the reason. This includes the simulator's normal pause on focus loss; a rendered
movie with repeated frozen frames is not a completed moving-flight take.

The capture disposes its director and production scene before exit, then observes a post-stop audio
mix through the supported mix-age clock and permits a subsequent main-loop cleanup. A two-second
watchdog fails the command and marks the manifest incomplete if teardown is not observed; elapsed
time alone cannot establish success. `FLIGHT_CAPTURE_AUDIO_DRAIN` records observed frames/wall time.
Cleanup frame count is variable (`movie_writer_cleanup_frames_expected = -1`). Retain measured
AVI frame counts rather than assuming every encoded frame belongs to the requested flight interval.
Unmodified AVI is the source; an optional
MP4 review copy must retain its own identity and must not be used for source-pixel comparisons.

### Real-time lighting measurements

The same `capture_flight.gd` accepts `--frametimes=<new absolute JSON path>` to run a native
director-controlled flight through Main's existing `FrameSamples` and `FrameDiagnostics` collectors.
It uses the built-in `lighting-pass` or `lighting-pilot` shot, requires a lighting preset, and also
accepts `--lighting-preset=off` as an explicitly disabled presentation profile. `--lighting-quality`
selects `low`, `standard` (default), or `high` without saving user preferences. Warmup defaults to
10 seconds and collection to 60 seconds; `--warmup` and `--t` use the existing collector bounds.
The FW-RGB-13 acceptance protocol requires an explicit **30-second warmup** and at least
60 measured seconds; the shorter default is useful for workload checks only.

For a **separate workload audit**, add `--lighting-workload-audit=on` to that same real-time
command. It observes RGB counters after every presented frame, including warmup, and retains
bounded maxima with first peak tick/frame/time, positive-frame counts and rising edges. This
catches brief Festival events that can fall between the ordinary one-second snapshots. The
manifest records the helper source hash and cumulative audit observer time, and explicitly marks
the run **ineligible for timing qualification**. Keep this audit's command, source, camera and
profile matched to the timing set, then omit the option (default `off`) for the timed repeats.
Never subtract observer time to manufacture corrected frame timings. Counts distinguish CPU live
states from GPU capacity; they do not prove visible pixels, field-light overlap, smoke allocation
peaks or companion coverage. The existing smoke snapshots remain once per second. A missing rig,
invalid metric, skipped observation index, reversed clock or tick invalidates the audit.

Run `prepare_runtime.ps1` after changing root application files such as `main.gd`: those files
are copies, while the runtime's directories are junctions. For reproducible comparisons, prepare
from an isolated source snapshot and retain its identities. Use a fresh output/profile for each run:

```powershell
$RgbRun = Join-Path $PWD 'tmp/rgb-performance-festival-new'
$env:APPDATA = Join-Path $RgbRun 'profile'
python tools/godot/run_checked.py --label rgb-performance-festival --warnings-as-errors --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --path tmp/trailer/runtime/app --audio-driver Dummy --rendering-method gl_compatibility --fullscreen --disable-vsync --max-fps 0 --script "$PWD/tools/trailer/capture_flight.gd" -- "--out-dir=$RgbRun" "--frametimes=$RgbRun/frametimes.json" --lighting-preset=festival --lighting-quality=standard --time_of_day=night --shot=lighting-pass --warmup=30 --t=60
```

This mode performs no image readback or movie encoding, and disables the director's full tick/frame
record arrays. Main retains its normal per-frame timing, GPU and resource metrics; the harness
samples RGB budgets at most once per wall second. These are **instrumented** measurements; retain
the diagnostic observer cost. The frame report uses `route=director-flight`, since ordinary manual
input is disabled while the director supplies commands. The companion manifest pins the frame
report and Workshop physical/presentation identities. Its `seconds` includes the harness loop and
warmup; use the frame report's `actual_sample_s` for the measurement interval. The two output paths
must differ. `complete` records successful collection and continuous flight, not hardware acceptance.

Native 1920×1080 is checked at runtime. Pauses, faults, crashes, backward ticks or more than 250 ms
without tick progress reject the run, including during warmup. Normal repeated ticks between 240 Hz
simulation steps are allowed at uncapped render rates. Movie Maker is rejected through
`Engine.get_write_movie_path()`. **Also verify the checked runner's full command contains no
`--fixed-fps`: Godot removes processed engine flags from `OS.get_cmdline_args()`, so the script
cannot certify their absence.** [Godot OS API](https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-get-cmdline-args),
[Engine movie path](https://docs.godotengine.org/en/stable/classes/class_engine.html#class-engine-method-get-write-movie-path).

Reduce each report with the existing [frame diagnosis tool](../../research/performance/README.md#cpu-gpu-and-memory-diagnosis),
using its exact checked engine log path. Compare OFF, Classic and Festival with the same aircraft,
source snapshot, camera, quality, world, resolution and command program; retain at least three
repeats per case and alternate their order. Run without competing Godot/Blender jobs or other
heavy workloads; discard a run if another task starts. A short smoke test, a valid reducer result,
or one full run cannot establish tier budgets, fleet worst cases or pilot readability. The manifest
leaves qualification explicitly unverified until the command, contention and acceptance evidence
are reviewed. The director's common inputs/physical identity do not constitute an exact ORFL replay.

`capture_formation.gd` renders 420 PNGs using the production Stik models, field, smoke and propeller
blur. Four render actors follow authored paths. Its manifest records camera framing and separation.
It deliberately has no simulation session and is always labeled as a cinematic formation in the edit.

## Edit and rebuild

The export folder contains `timeline.json`, `sources/`, `evidence/`, `licenses/`, and an `editor/`
snapshot. Source paths in the timeline are relative to that JSON. Each shot specifies source start,
exact frame count, game-audio source/gain, and English graphics. Duration is the sum of shot frames
divided by 60; revision 6 and the current refresh contain 3,480 frames. Older one-minute manifests remain supported.
The formation is stored as a lossless FFV1 source; ordinary takes retain their original MJPEG/PCM AVI.

The tested editor uses Python, **Pillow 12.3.0** and **FFmpeg/ffprobe 9.0.2 essentials**. Barlow Condensed
fonts and their SIL Open Font License are retained under `assets/fonts/`. No code-video framework,
paid music, generative-video service, or additional skill installation is required.

```powershell
python tools/trailer/assemble.py --manifest '<export>/timeline.json' `
  --ffmpeg '<ffmpeg.exe>' --ffprobe '<ffprobe.exe>' `
  --out '<export>' --work 'tmp/trailer/edit'
```

The editor preserves normal-speed simulation footage, applies a restrained grade, and adds titles.
For selected HUD-free flights, `remove_empty_ui_marker` removes only the empty 20×16 panel left in
the upper-left corner by the current UI. It never removes report qualifications or flight data.
The control/report shots keep their native UI. The disclosed formation uses a crossfaded engine
bed from the captured Stik. Music remains separate and replaceable.

Revision 2 opens with the full formation and uses manifest-level constant `music_gain` / `game_gain`
settings. No music reductions depend on obsolete scene timestamps. The music renderer
`audio_pipeline/revise_music.py` analyzes Uprising and produces a continuous 60-second cue with
a mild tempo adjustment, startup de-click and final one-beat fade. Its measured environment uses
NumPy **2.4.6** and Matplotlib **3.11.1**. Preserve `analysis.json` and the cue hash: onset proximity
and a fitted pulse do not establish subjective musical phrasing or a listening review.

Revision 3 retains that exact music stem. It opens with source seconds 2–7 of the formation and
gives the Extra six seconds at 13–19 s for two continuous rolls with a climbing exit. The Turbo Lumber Evolution
twilight insert remains at 22–25 s and bypasses the generic grade to preserve native sunset color.
The current [revision evidence](../../docs/research/cinematic-trailer/revision-3-2026-10-17.md)
records the accepted takes, measurement limits and output identity.

Revision 4 replaces only the 34–38 s MONSTER CAR 2 insert with a real ramp jump.
`capture_car_jump.gd` uses the production ground activity, supported `track_start` spawn and ordinary
accelerator input, with a side-quarter tracking camera. The accepted source has a measured +3 frame
offset between saved previews and AVI frames; its four surplus AVI frames are not all startup frames.
Use the retained frame-match evidence and timeline trim, not the original estimated offset.
The [revision-4 evidence](../../docs/research/cinematic-trailer/revision-4-2026-10-17.md) records the
launch, airborne interval, native landing and alignment to the unchanged score.

Revision 5 adds cinematic feature cards through each shot's `features` array. Each cue has
`headline` (one or two lines), optional `kicker` and `detail`, local `start`/`end` times,
and optional `xy`/`size`. Text bounds must fit the title-safe upper frame. A negative
start carries a card from the preceding shot without replaying its entrance; an end
beyond the shot duration preserves it through the cut. `graphics.compact` moves vehicle
labels to the lower right and the persistent formation disclosure to the lower left.
The [revision-5 evidence](../../docs/research/cinematic-trailer/revision-5-2026-10-17.md)
owns the feature wording, claim audit and cue sheet. It retains revision 4's media trims.

Revision 6 removes the reset/retry insert and the reset frames hidden at the end of the report
source. The clean report preserves source frames 0–175 and holds frame 175 for 14 additional
frames, then passes directly to the end card. `fade_in_frames` and `fade_out_frames` apply after
all graphics, allowing a short dip to black without leaving a title floating over black.
The last fade-out frame reaches black. The title card begins at 54 2/3 seconds; the film ends
at 58 seconds. See the [ending evidence](../../docs/research/cinematic-trailer/revision-6-2026-10-17.md).
`output_filename` can name the export; otherwise the editor derives its duration in the filename.
Supply a music stem with the corresponding duration and intended ending fade.

The 2026-10-21 refresh reruns every simulator picture scene and the formation on the current source tree, retaining revision 6's 58-second timeline. The current crash happens later than the old take; derive its approach, impact and report cuts from the new capture instead of copying old source offsets. Detect the report's first visible and first reset frames in the decoded AVI before making the clean FFV1 source. The [refresh evidence](../../docs/research/cinematic-trailer/refresh-2026-10-21.md) records the accepted boundaries and delivery.

TRA-09 (revision 8) adds presentation-only options. `capture_formation.gd --mix` renders five distinct
airframes with colored show-smoke tints (600 frames, still labeled cinematic). `capture_flight.gd` accepts
`--workshop-scale=<ratio>` (with a lighting preset; freezes the ordinary Workshop `virtual_similarity_v1`
recipe) and `--livery=<id>`. `flight_director.gd` adds `corsair-pass`, `x8-pass`, `mini-pass`, `giant-pass`,
`companions` (frames the first live AI companion and its nearest neighbor) and `corsair-roll`: wings-level
altitude hold at full throttle for 9 s, then full aileron held. Identical inputs give the same flight for every
livery, so the edit can cut between livery takes on one clock. `assemble.py` reads an optional
`end_card_detail` line and `video_description`. A timeline with `"style": "crystal"` renders cues with
`crystal_titles.py`: animated titles in the interface's green palette. Cue keys `align: "center"`,
`lower: true` (no scrim; lower safe area) and `credit` serve the end card. `capture_brand.gd` renders the
production brand intro as PNG frames for a `frames` shot. `capture_flight.gd` now detaches any connected gamepad/radio from the session after
startup (`FLIGHT_CAPTURE_CONTROLLER_DETACHED`): a desk controller otherwise froze takes at tick 3 while the
manifest still read `complete`. Check that the logged tick advances, not only `complete`.

Output checks cover resolution, 60 fps, the manifest's frame count/duration, full decode and decoded AAC true peak.
`render-manifest.json` retains source/output hashes and audio measurements. These checks do not
replace listening review, prove physical realism, or establish exact replay equivalence.

Keep `VIDEO-DESCRIPTION.txt` with the film: it includes the required Scott Buckley music attribution,
license link, edit note and formation disclosure. Delivery does not upload or publish the film.
