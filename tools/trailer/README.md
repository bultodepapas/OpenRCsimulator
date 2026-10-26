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
records aircraft attitude, inputs and framing. `timber_dusk_director.gd` changes only the camera
for a closer front-quarter sunset view. Its accepted take uses native field lighting with
`--time=21:51` (the world's reference location/date, not the computer's local timezone).
Use `--movie-only` with Movie Maker and inspect extracted AVI frames; optional viewport PNGs
can inherit a decorated window's client size even when Movie Maker records native 1920×1080.
Create the `--write-movie` parent directory before launching Godot: Movie Maker opens its file
before the capture script runs, so the script's output-directory creation is too late for that file.

For RGB acceptance captures, `capture_flight.gd --lighting-preset=<id>` freezes an ordinary
Workshop trial from the chosen stock aircraft and built-in preset (`classic_rc`, `night_radian`,
`neon_rgb`, `night_aerobatics`, `festival`, `custom`). It does not save a build or modify physics.
Pass `--time_of_day=night` to the capture process for the existing moonlit world. `--shot=lighting-pass`
uses neutral flight controls with the existing trimmed throttle plus 0.08 and a moving close camera;
`--shot=lighting-pilot` uses the same controls with the production pilot camera, auto-zoom off and
the magnifier on. No previously recorded `.orfl` tape is replayed by these shots.

Each RGB frame records the actual rig allocation counters and world exposure. Pilot captures also record the visible
inset's dimensions, camera and AA mode. The main view uses 4× MSAA; the production inset uses 2×.
The manifest retains physical/presentation trial identities and capture/director/main/registry hashes.
The prepared runtime uses source junctions; those hashes do not make a shared checkout immutable.
These are offline moving-image checks,
not real-time GPU benchmarks or pilot acceptance. Respect the renderer's distance/quality limits:
the inset does not independently increase the primary camera's VFX birth or spill grants.
Every `--lighting-preset` capture, including a custom director such as `extra_rolls_director.gd`,
receives live RGB allocation and world-exposure fields from the harness. Its director must append
exactly one record for the current frame and simulation tick; missing or inconsistent evidence
fails the capture. The existing Extra director uses `--shot=extra-roll --seconds=6` for its ordinary
two-roll maneuver, so it can inspect `--lighting-preset=night_aerobatics` without a second controller.
Lighting shots and all explicit lighting-preset captures reject pauses, faults, crashes or a stalled tick counter, retaining an incomplete
manifest with the reason. This includes the simulator's normal pause on focus loss; a rendered
movie with repeated frozen frames is not a completed moving-flight take.

The capture now disposes its director and production scene before exit. Two process-frame waits
allow teardown; the checked Movie Maker run presents one additional cleanup frame. Retain measured
AVI frame counts and the manifest's expected lead/cleanup counts rather than assuming that every
encoded frame belongs to the requested flight interval. Unmodified AVI is the source; an optional
MP4 review copy must retain its own identity and must not be used for source-pixel comparisons.

### Real-time lighting measurements

The same `capture_flight.gd` accepts `--frametimes=<new absolute JSON path>` to run a native
director-controlled flight through Main's existing `FrameSamples` and `FrameDiagnostics` collectors.
It uses the built-in `lighting-pass` or `lighting-pilot` shot, requires a lighting preset, and also
accepts `--lighting-preset=off` as an explicitly disabled presentation profile. `--lighting-quality`
selects `low`, `standard` (default), or `high` without saving user preferences. Warmup defaults to
10 seconds and collection to 60 seconds; `--warmup` and `--t` use the existing collector bounds.

Run `prepare_runtime.ps1` after changing root application files such as `main.gd`: those files
are copies, while the runtime's directories are junctions. For reproducible comparisons, prepare
from an isolated source snapshot and retain its identities. Use a fresh output/profile for each run:

```powershell
$RgbRun = Join-Path $PWD 'tmp/rgb-performance-festival-new'
$env:APPDATA = Join-Path $RgbRun 'profile'
python tools/godot/run_checked.py --label rgb-performance-festival --warnings-as-errors --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --path tmp/trailer/runtime/app --audio-driver Dummy --rendering-method gl_compatibility --fullscreen --disable-vsync --max-fps 0 --script "$PWD/tools/trailer/capture_flight.gd" -- "--out-dir=$RgbRun" "--frametimes=$RgbRun/frametimes.json" --lighting-preset=festival --lighting-quality=standard --time_of_day=night --shot=lighting-pass --warmup=10 --t=60
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
gives the Extra six seconds at 13–19 s for two continuous rolls with a climbing exit. The Lumber
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

Output checks cover resolution, 60 fps, the manifest's frame count/duration, full decode and decoded AAC true peak.
`render-manifest.json` retains source/output hashes and audio measurements. These checks do not
replace listening review, prove physical realism, or establish exact replay equivalence.

Keep `VIDEO-DESCRIPTION.txt` with the film: it includes the required Scott Buckley music attribution,
license link, edit note and formation disclosure. Delivery does not upload or publish the film.
