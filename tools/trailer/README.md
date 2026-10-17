# Cinematic trailer tools

TRA-02…07 presentation tools for the 60-second English film **Every Input Matters**.
See the [production plan](../../docs/plans/cinematic-trailer.md) and its linked evidence for scope and results.
No tool here edits the simulation kernel, aircraft data, damage assessment or prices.

## Capture

Use Godot **4.7.2 stable**, Compatibility/OpenGL, and the repository's existing imported assets.
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

`capture_formation.gd` renders 420 PNGs using the production Stik models, field, smoke and propeller
blur. Four render actors follow authored paths. Its manifest records camera framing and separation.
It deliberately has no simulation session and is always labeled as a cinematic formation in the edit.

## Edit and rebuild

The export folder contains `timeline.json`, `sources/`, `evidence/`, `licenses/`, and an `editor/`
snapshot. Source paths in the timeline are relative to that JSON. Each shot specifies source start,
exact frame count, game-audio source/gain, and English graphics. The total must be 3,600 frames.
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

Output checks cover resolution, 60 fps, 3,600 frames, duration, full decode and decoded AAC true peak.
`render-manifest.json` retains source/output hashes and audio measurements. These checks do not
replace listening review, prove physical realism, or establish exact replay equivalence.

Keep `VIDEO-DESCRIPTION.txt` with the film: it includes the required Scott Buckley music attribution,
license link, edit note and formation disclosure. Delivery does not upload or publish the film.
