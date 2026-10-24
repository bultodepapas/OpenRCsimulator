# CAM-AUD-2026-10-24 — Camera audit

2026-10-24. A full audit of the game's cameras: defects, smoothness, options, realism, effects and quality, with measurements and an external survey. No runtime file was changed. The [camera plan](../../../plans/camera-views.md) owns the remaining work; the steps this audit proposes are added there as CAM-23…CAM-31.

Base commit `4e0a3710`, Godot 4.7.2 (Compatibility renderer, MSAA 2×, 240 Hz physics). Software checks ran on the shared VM (Mesa llvmpipe, no GPU, no display, no sound). They establish behaviour and relative cost only: not readability, comfort or target-machine performance (Gate 2, CAM-21/22).

## Verdict

The camera core is sound. Views read the same interpolated 240 Hz pose the aircraft is drawn with, filters are exact discretizations, cameras never write the session, and 100 existing checks pass. The weak points are at the edges of that core:

1. The pilot auto-zoom is defined in absolute pixels, so the aircraft's on-screen size depends on the resolution. Wherever the law is active at both resolutions, the aircraft at 4K is half its 1080p size on the same monitor (F1).
2. The chase misses the plan's own smoothness budget: 11 cm frame-rate dependence in a turn (budget 1 cm) and a 0.5 s framing slide every time the view is entered (F2, F3).
3. No camera setting exists: no FOV, default view, zoom strength, sensitivity or persistence (F6).
4. After a crash, every view except the pilot's aims at the impact point, not at the wreck. In the live run, "Inspect wreck" showed empty grass and the orbit could not turn (F5). The helicopter and the RC truck duplicate the rig and lose its fixes (F9).
5. Most of the plan's views and pilot aids (zoom laws, natural FOV, magnifier, fly-by, FPV, field cameras, transitions, listener policy) remain unbuilt.

## Method

| Part | What | Result |
| --- | --- | --- |
| Code read | `app/render/camera/*`, `pilot_camera.gd`, `main.gd` seams and frame order, `crash/director.gd`, `helicopter_main.gd`, `vehicles/ground/ground_camera.gd`, consumers (audio, world exposure, sun glare, lake reflection, overlays, population) | Findings below |
| Existing tests | `test_camera_math`, `test_camera_views`, `test_pilot_aids` through `tools/godot/run_checked.py` | 21/21, 57/57, 22/22 pass |
| Behaviour probes | [probe_views.gd](../../../../research/camera-views/audit-2026-10-24/probe_views.gd): synthetic loop, hammerhead, 60° turn, crab, overhead and low passes, auto-zoom by resolution | §Measurements |
| Candidate laws | [probe_candidates.gd](../../../../research/camera-views/audit-2026-10-24/probe_candidates.gd): fixed sub-steps, state velocity, heading feed-forward, pilot screen-roll cap. A re-implementation without changes matches production exactly | §Measurements |
| Frame pacing | [probe_jitter_fix.gd](../../../../research/camera-views/audit-2026-10-24/probe_jitter_fix.gd): presented (interpolated) time vs wall clock with `physics_jitter_fix` 0.5 and 0 | F7 |
| Live app | Debug bridge at 1920×1080 under Xvfb (llvmpipe, about 1 fps): airborne Stik; pilot, chase, orbit and close-up views; manual zoom; a dive into the ground in orbit view; "Inspect wreck"; camera keys and controller actions; clean stop | Law confirmed live; F5 raised to High; F19 found. Clean exit (no crash, 0 leaked objects). Screenshots kept outside git |
| External survey | Two read-only research passes (RC/flight sims, real cameras, comfort, camera design; Godot engine, add-ons, effects). They extend the [2026-10-13 survey](../../../plans/camera-views.md#10-external-evidence) | §External survey |

Probe commands are in each script header. They write nothing.

## Findings

Severity: **High** = visible defect on the primary target (1080p) or above; **Medium** = visible defect in a common case or a broken plan contract; **Low** = polish, rare case or consistency.

| ID | Severity | Finding | Evidence | Remedy (step) |
| --- | --- | --- | --- | --- |
| F1 | High | **Auto-zoom is resolution-dependent.** `Spec.AUTO_ZOOM.target_px = 30` is absolute, so the span covers 4.2 % of the height at 720p, 2.8 % at 1080p and 1.4 % at 4K. On one 27-inch monitor at 300 m the aircraft is 3.1× its real angular size at 1080p and 1.6× at 4K. The zoom engages from 58 m at 1080p but from 116 m at 4K | Auto-zoom table below; `pilot_camera.gd` `auto_fov` | Express the target as a fraction of the viewport height. A default of 30/1080 keeps 1080p unchanged and makes 1440p/4K match it (CAM-23) |
| F2 | Medium | **Chase is frame-rate dependent beyond the plan budget.** Matched-time camera position differs by 11.1 cm between 30 and 144 fps in a 60° turn and 4.4 cm in a 60 m circle (the plan's jitter case); the plan's frame-rate budget is ≤ 1 cm (§7). The spring is exact only for a constant goal; the goal moves within each frame | `probe_views` and `probe_candidates` | Fixed 1/240 s sub-steps with the target interpolated inside the frame: 3 mm and 1 mm (CAM-24) |
| F3 | Medium | **Chase entry slide.** Every entry into chase (C, 2, restart, `--view=chase`) starts the look-ahead from zero velocity. The aircraft then slides from −1.3° to −6.7° on screen over 0.5 s, with second differences up to 5.4 px at 1080p | `probe_views` (all four manoeuvres) | Prime and drive the velocity from the simulation state: `sim.interpolated()` already returns it. Transient 0 (CAM-24) |
| F4 | Medium | **Overhead pass flips the horizon.** Outside the 2026-10-23 pole fix, world-up `look_at` spins the picture about the view axis at up to 2388°/s (40° in one 60 fps frame) for a pass 0.5 m beside the zenith, and 706°/s at 2 m. Gaze rate stays ≤ 78°/s | `probe_views` overhead passes | Optional screen-roll rate cap. 180°/s gives ≤ 195°/s, exact aim and ≤ 29° transient horizon tilt; the pilot judges it in CAM-22 (CAM-28) |
| F5 | **High** | **"Inspect wreck" can show an empty field.** After an impact, `director.aim` overwrites chase, orbit and close-up with a fixed world offset (impact + (5, 3.2, 6) m, FOV 58°) aimed at the **impact point**, not at the wreck. In the live run the Stik's wreck core slid 15.9 m and projected at x = −540 px, off screen. After "Inspect wreck" the orbit showed only grass, and dragging changed the orbit azimuth but not the camera. The pilot view kept the wreck in frame. The offset also has no terrain, obstacle or water check and is a hard cut. The helicopter route feeds the wreck to the rig instead, so the two routes differ | Live run (below); `main.gd` `_process`, `director.gd` `aim`, `helicopter_main.gd` | CAM-03 `request_focus` on the wreck core. First slice: the orbit retargets the wreck core and stays controllable, and the director's view gets clearance (CAM-27) |
| F6 | Medium | **No camera settings.** FOV, default view, auto-zoom on/off and strength, chase distance, orbit sensitivity/invert and comfort options are all missing, and nothing persists. Every flight starts in the pilot view with auto-zoom on. XAG 117 and the Game Accessibility Guidelines ask for an adjustable FOV, sensitivity, and a way to disable automatic camera motion | `preferences.gd`, `settings_screen.gd` have no camera keys | CAM-17 (existing), scoped by this audit |
| F7 | Low–Medium | **`physics_jitter_fix` is left at its default 0.5 although the flight interpolates.** Presentation uses `Engine.get_physics_interpolation_fraction()`, and Godot's documentation asks for 0 with any interpolation. At 50 fps (4.8 ticks per frame) the presented-time error against the wall clock was 0.37–0.50 ms RMS with 0.5 and 0.12–0.20 ms with 0 in three repeats. At 75 and 144 fps the VM noise dominated. Presented time always equals Godot's `delta` exactly | `probe_jitter_fix` | Set it to 0 after an A/B with the jitter metric on the target machine (CAM-25, main line owns `project.godot`) |
| F8 | Medium | **Depth precision.** The flight uses near 0.1 m and far 21 km in every view; the RC truck uses near **0.01 m**. With Compatibility's 24-bit buffer (reverse-Z gains nothing there), the depth step is ≈ z²/(near·2²⁴): 0.6 m at 1 km for the flight and 6 m at 1 km for the truck. CAM-02b (pilot near 0.5 m) is still open | Table below; `ground_scene.gd` | CAM-02b, plus per-view near planes and the truck (CAM-26) |
| F9 | Medium | **Routes duplicate camera code and drift apart.** The helicopter re-implements input: it has no Shift+C or Backspace key, its wheel ignores `factor` and never marks the event handled, and a restart does not reset the rig. It also hard-codes span 1.55 m and `pilot_zoom = 0.35`, which `view_reset` silently discards. The truck has its own rig with zoom steps of 0.9/1.1, its own pilot-view law `2·atan(2/d)` clamped to 18–65°, and near 0.01 m | `helicopter_main.gd` `_unhandled_input`, `_on_session_resetting`; `ground_camera.gd` | One input router and a per-vehicle camera profile in data (span, default zoom, near), shared by every route (CAM-26) |
| F10 | Low–Medium | **The audio listener jumps with every view change.** FlightAudio reads `_camera.global_position`. The soundscape zeroes listener velocity above 150 m/s, but view changes never call `reset_observer`, so propagation delay jumps with the ear | `flight_audio.gd`, `soundscape.gd` | CAM-16 (existing; the audio owner checks audibility) |
| F11 | Low | **Orbit controls are raw.** Mouse deltas are applied unsmoothed at a fixed 0.3°/px, with no sensitivity or invert setting. Rotation has no keyboard or gamepad control. The cursor stays free during a drag, and each wheel notch jumps the distance 19 % with no easing | `orbit_view.gd`, `main.gd` `_camera_input` | Smooth rotation and dolly with the existing damper; capture the cursor while dragging; settings; gamepad look (CAM-17, CAM-29) |
| F12 | Low | **Chase lags in turns.** The heading damper leaves the aircraft 15.7° off-centre in a 60° bank and 8.8° in a 60 m circle. This is partly intended (it shows the turn) | `probe_candidates` | Heading feed-forward, as PicaSim does for its follow: 9.1° and 7.1°. Owner choice (CAM-24 option) |
| F13 | Low | **Clearance is terrain-only and a hard floor.** Chase and orbit clamp the output height to terrain + clearance (a kink when it engages) and ignore trees, hangars, barrier and people | `chase_view.gd`, `orbit_view.gd` | CAM-09 obstacle shortening with hysteresis; smooth floor |
| F14 | Low | **Loops whip the horizon-locked chase.** At the top of a 15 m loop at 20 m/s the camera yaws 180° at up to 280°/s; a hammerhead gives 137°/s. The aircraft never leaves the frame | `probe_views` | Inherent to horizon lock; 3D follow is the remedy (CAM-09) |
| F15 | Low | **The close-up rolls rigidly with the aircraft** (inverted flight shows the world upside down) and duplicates the orbit, which the plan meant to replace it | `pilot_camera.gd` `aim(inspect)` | Keep it as a preset of the orbit in the airplane's yaw frame (CAM-10 remainder) |
| F16 | Low | **Gamepad camera control is minimal.** Zoom moves one step per press, there is no hold-to-zoom and no analog look or orbit, and no transmitter switch is available (D9) | `controller_actions.gd` | CAM-17 bindings |
| F17 | Info | **Frame order.** `World.update` (eye adaptation from camera pitch) runs before `_render_pose`, so it reads the previous frame's camera. The adaptation filter is slow, so this is negligible today. Any new camera consumer must run after the rig (FlightAudio and the lake reflection use priority 100) | `main.gd` `_process` | Document the order contract in the rig (CAM-24) |
| F18 | Info | **Base FOV is wide.** 50° vertical against an orthoscopic ≈ 31° for a 27-inch 16:9 monitor at 60 cm. Inside 58 m at 1080p the aircraft shows at 0.6× its real angular size. D11 is still pending | Auto-zoom table | CAM-07 natural FOV preset and FOV setting (CAM-17) |
| F19 | Low | **The crash text promises a key that is blocked.** The crash description ends "[C] Change view", but the accident-report card swallows every key except Escape and R until "Inspect wreck" minimizes it (`accident_report.gd` `_unhandled_input`, intended). Controller camera actions do get through. Live: C and 1 left the view unchanged; `camera_pilot` changed it | Live run | Crash and UI tracks: align the text with the card, or let camera keys through |

Rechecked and found correct: interpolation (lerp position, shortest-path nlerp attitude, rates from the current state); one pose source for the aircraft and every view; exact damper and spring; finite bases at the poles; chase teleport snap; pause freezing; ordering of audio and lake reflection after the rig; trace identity (CAM-01-10 evidence). The rig costs 9 µs per frame for the chase on the VM, including the probe's trajectory.

## Measurements

### Auto-zoom by resolution (F1, F18)

Span 1.5 m (Stik class), today's law (30 px, FOV 6–50°). Each cell gives vertical FOV, span in pixels, and **on-screen ÷ real angular size** for a 27-inch 16:9 monitor viewed from 60 cm.

| Distance | 720p | 1080p | 1440p | 2160p |
| --- | --- | --- | --- | --- |
| 25 m | 50.0° 46 px ×0.6 | 50.0° 69 px ×0.6 | 50.0° 93 px ×0.6 | 50.0° 139 px ×0.6 |
| 50 m | 39.6° 30 px ×0.8 | 50.0° 35 px ×0.6 | 50.0° 46 px ×0.6 | 50.0° 69 px ×0.6 |
| 100 m | 20.4° 30 px ×1.6 | 30.2° 30 px ×1.0 | 39.6° 30 px ×0.8 | 50.0° 35 px ×0.6 |
| 200 m | 10.3° 30 px ×3.1 | 15.4° 30 px ×2.1 | 20.4° 30 px ×1.6 | 30.2° 30 px ×1.0 |
| 300 m | 6.9° 30 px ×4.7 | 10.3° 30 px ×3.1 | 13.7° 30 px ×2.3 | 20.4° 30 px ×1.6 |
| 500 m | 6.0° 21 px ×5.3 | 6.2° 30 px ×5.2 | 8.2° 30 px ×3.9 | 12.3° 30 px ×2.6 |

The 6° floor equals a ≈ 229 mm full-frame lens (research pass 1, derived).

### Chase and pilot manoeuvres (F2–F4, F12, F14)

60 fps unless stated; boom 5.25 m (span 1.5 m); chase FOV 55°; pixels at 1080p.

| Case | Off-centre max | Camera yaw rate max | Screen 2nd difference | Notes |
| --- | --- | --- | --- | --- |
| Straight + loop (R 15 m, 20 m/s) | 25.9° | 280°/s | 0.80 px RMS, 5.4 px max (entry) | Never out of frame; vertical ≤ 7.7° |
| Hammerhead | 19.5° | 137°/s | 0.43 px RMS | Heading jumps to the pivot side, then to the exit |
| 60° bank turn (R 23.5 m) | 15.7° | 49°/s | 0.33 px RMS | Steady heading lag |
| Crab 60° (track constant) | 6.3° | 0°/s | 0.38 px RMS | Follows the track, as designed |

| Chase law (60° turn / 60 m circle) | Off-centre | ∣30 − 144 fps∣ | Entry transient |
| --- | --- | --- | --- |
| Production | 15.7° / 8.8° | 111 / 44 mm | 1.28°/frame |
| State velocity | 15.8° / 8.8° | 114 / 46 mm | 0 |
| Sub-steps 1/240 s | 15.8° / 8.8° | 3 / 1 mm | 1.28°/frame |
| Sub-steps + state velocity | 15.8° / 8.8° | 3 / 1 mm | 0 |
| + heading feed-forward | 9.2° / 7.2° | 3 / 1 mm | 0 |

| Pilot pass (20 m high, 25 m/s) | Gaze rate max | Horizon rotation max (production) | With 180°/s cap | With 90°/s cap |
| --- | --- | --- | --- | --- |
| 0.5 m beside the zenith | 78°/s | 2388°/s (39.8°/frame) | 192°/s, tilt ≤ 29° | 103°/s, tilt ≤ 49° |
| 2 m | 78°/s | 706°/s | 195°/s, tilt ≤ 19° | 110°/s, tilt ≤ 40° |
| 5 m | 76°/s | 286°/s | — | — |
| Low pass 8 m in front, 1.5 m high, 30 m/s | 215°/s | 215°/s | — | — |

### Live run (F1, F5, F19)

Debug bridge, 1920×1080, Home → Fly airborne (Ugly Stik 60), then the [scenario](#reproduce-the-live-run). Values are read from the running app.

| Moment | Reading | Observation |
| --- | --- | --- |
| Pilot view, 71.5 m away, 30 m high | FOV 41.9° | Matches the 30 px law for a 1.52 m span. The frame shows only sky: no ground or horizon reference (CAM-06/06b) |
| Four zoom-in steps | `pilot_zoom` 0.5, FOV 23.8° | As designed |
| First switch to chase | One 2.8 s frame against 0.87 s typical | Inconclusive at 1 fps on llvmpipe; recheck on the target (CAM-31) |
| Dive into the ground in orbit view | Camera at impact + (5, 3.2, 6) m, FOV 58° | Director override (F5) |
| Wreck after the slide | Core 15.9 m from the impact point; screen x = −540 px in orbit and chase, (841, 554) in pilot | Wreck off screen in every non-pilot view |
| "Inspect wreck", orbit, drag 500 px | Azimuth 89.2° → 69.8°; camera position unchanged | Orbit not controllable; empty field on screen |
| Accident card open, keys C and 1 | View unchanged; controller `camera_pilot` works | F19 |

### Depth step in the Compatibility renderer (F8)

`Δz ≈ z²/(near·2²⁴)`, derived.

| Near | 100 m | 300 m | 1 km | 3 km |
| --- | --- | --- | --- | --- |
| 0.01 m (truck) | 6 cm | 54 cm | 6.0 m | 54 m |
| 0.1 m (flight, all views) | 6 mm | 5 cm | 0.6 m | 5.4 m |
| 0.25 m (plan: chase/orbit) | 2 mm | 2 cm | 0.24 m | 2.1 m |
| 0.5 m (plan: pilot, CAM-02b) | 1 mm | 1 cm | 0.12 m | 1.1 m |

Compatibility allocates `GL_DEPTH24_STENCIL8`. Since 4.3 its GL code uses a reversed depth convention, but without `glClipControl`, so 24-bit fixed-point depth gains nothing from it ([renderer table](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html); engine source; [PR #88328](https://github.com/godotengine/godot/pull/88328)). At near 0.1 m the 0.05 m pilot-aid shadow offset starts to fight at about 300 m; at 0.5 m, at about 700 m. Near planes are the only cheap lever. Logarithmic depth would need every material to write depth, and split-depth viewports double the cost.

## External survey

Accessed 2026-10-24. "Derived" means our arithmetic. Only findings beyond the [2026-10-13 survey](../../../plans/camera-views.md#10-external-evidence) are listed.

### Simulators

| Source | Camera law or feature worth adopting | Link |
| --- | --- | --- |
| PicaSim, now open source (PolyForm **Noncommercial**: study its laws, never copy its code) | Auto-zoom blends in angle space: `fov = (1−a)·70° + a·2·atan(r/d)`, a = 0.65, and the zoom keys change a. "Horizon amount" lowers the aim toward eye level: `aim.y −= (aim.y − eye.y)·0.6·(1−a)`. The follow uses velocity feed-forward: target `p + v·T` (T = 0.1 s·(1−a)), then a critically damped smoother. An aircraft-only zoom inset takes 0.2 of the screen. Aerotow framing keeps two targets in view. A 150 m sky grid overlay can be aligned crosswind or with the runway | [Rowlhouse/PicaSim](https://github.com/Rowlhouse/PicaSim) (`Camera.cpp`, `Aeroplane.cpp`, `PicaSim.cpp`) |
| FlightGear fly-by (`Nasal/view.nas`) | Places the camera 0.8·(3.5 s × ground speed) ahead along the course, deviated by 0.7–1.2·D (D = 25 m), to the side when below D AGL. It re-places once the aircraft is 1.7·D past and never goes below terrain + 2 m | [view.nas](https://gitlab.com/flightgear/fgdata/-/raw/next/Nasal/view.nas) |
| aerofly RC 10 | The model camera follows the CG, ignores pitch and roll, and stays within 4 model radii. F5 recentres. Split screen for two models; multiplayer view lock on another pilot's model | [manual §11–19](https://www.ikarus.net/en/rc10-manual/) |
| X-Plane 12 | Linear spot (the camera coasts at the aircraft's velocity at selection), still spot, runway, tower and circle views. Quick Looks save and recall aircraft-relative views | [desktop manual](https://www.x-plane.com/manuals/desktop/) |
| MSFS 2024 | Drone camera: travel and rotation speed, follow, lock, focus off/auto/manual; top-down and photo states | [camera SimVars](https://docs.flightsimulator.com/msfs2024/flighting/programming-apis/simvars/camera-variables/index.md) |
| War Thunder 2.25 | Replay "two-plane camera" keeps one aircraft in frame while tracking another. Shake toggle; free-camera speed capped to the aircraft's speed | [update 2.25.1.89](https://devtrackers.gg/war-thunder/p/d99e1803-update-2-25-1-89) |
| RealFlight Evolution 2024–25, Liftoff, Uncrashed, TRYP | No new camera laws documented. Liftoff tilts the FPV camera live and syncs angles while spectating; Uncrashed exports replay video | [RealFlight](https://www.horizonhobby.com/realflight/), [Liftoff update notes](https://www.liftoff-game.com/news/update-147-released) (via search excerpts) |

### Real cameras

| Topic | Numbers | Link |
| --- | --- | --- |
| Telephoto | Full frame (derived): 200 mm ≈ 6.9° vertical, 600 mm ≈ 2.3°. Field photographers use 150–600 mm | [Park Cameras](https://www.parkcameras.com/blog/tips-and-inspiration/tips-and-tricks-for-fantastic-airshow-photos_tutorial-25-07-2018-1) |
| Prop blur and shutter | A full disc needs about 1/60–1/250 s; faster than 1/500 freezes the blades. Exposure = (shutter angle/360)/fps | [Nikon](https://www.nikonusa.com/en/learn-and-explore/a/tips-and-techniques/taking-great-photographs-at-airshows.html), [RED](https://www.reddigitalcinema.com/red-101/shutter-angle-tutorial) |
| Rolling-shutter prop bend | `I(r,θ) = f(r, θ + (ω/v)·r·sinθ)`; readout ≈ 1/max fps (inferred) | [jasmcole](https://jasmcole.com/2014/10/12/rolling-shutters) |
| FPV systems | DJI O4 Pro 155°, 15 ms (Goggles 3); O4 117.6°, 20–35 ms; O4 Wide 159°. Analog and HDZero 10–20 ms, DJI and Walksnail 20–45 ms. Failure looks: analog snow, HDZero analog-like sparkles, DJI and Walksnail freeze | [DJI O4 specs](https://www.dji.com/o4-air-unit/specs), [Oscar Liang](https://oscarliang.com/fpv-system/) |
| Horizon levelling | GoPro levels up to 27° (mode-dependent) or locks through 360°; Insta360 defaults to 45° | [GoPro HERO12](https://community.gopro.com/s/article/HERO12-Black-In-Camera-Horizon-Leveling-And-Horizon-Lock?language=en_US), [Insta360](https://onlinemanual.insta360.com/oner/en-us/camera/horizonlock) |
| Handheld shake | Body sway below 3 Hz, hand tremor about 3–9 Hz, testers use ±0.5° (patents and a datasheet: indicative only) | [US7917022](https://patents.google.com/patent/US7917022) |

### Comfort, accessibility and camera design

| Source | Use for OpenRC | Link |
| --- | --- | --- |
| Xbox Accessibility Guideline 117 (updated 2026-06) | Adjustable FOV, per-axis sensitivity, ways to turn off shake, bob, blur and automatic camera motion | [XAG 117](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/117) |
| Game Accessibility Guidelines | Default FOV 60° for TV and 90° for monitor, for first-person and chase views. The pilot view's orthoscopic argument (D11) is a separate case | [GAG FOV](https://gameaccessibilityguidelines.com/if-the-game-uses-field-of-view-3d-engine-only-set-an-appropriate-default-for-the-expected-viewing-environment/) |
| Diels & Howarth 2013 | Sickness peaks for 0.2–0.4 Hz fore-aft oscillation, so camera springs stay critically damped and should be tested for ringing in that band | [Loughborough repository](https://repository.lboro.ac.uk/articles/journal_contribution/Frequency_characteristics_of_visually_induced_motion_sickness/9346865) |
| Guo et al. 2013 | Passive viewing makes people sicker than playing, so replays and automatic views need the strictest comfort defaults | [paper](https://www.ieda.ust.hk/dfaculty/so/pdf/Guo-et-al-2013-EHF2013.pdf) |
| Bos et al. 2012 | An earth-fixed reference plus an anticipatory cue cut sickness by more than 4× | [TNO](https://publications.tno.nl/publication/101097/No1dby/bos-2012-optimising.pdf) |
| Eiserloh, GDC 2016; Cinemachine 3.1 | Trauma shake (trauma², linear decay, noise channels). Impulses that propagate at 343 m/s and dissipate with distance. Composer dead zone and hard limits; deoccluder minimum occlusion time and damping when occluded | [Bevy reference](https://bevy.org/examples/camera/2d-screen-shake/), [Impulse](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/CinemachineImpulseSource.html), [Deoccluder](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/CinemachineDeoccluder.html) |
| Unreal Gameplay Cameras (5.5+, experimental) | Rigs built from nodes, a director that picks rigs, base/global/visual layers, and a blend stack that freezes an interrupted blend | [quick start](https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-camera-system-quick-start) |

### Godot 4.7 and 4.8

| Topic | Fact | Consequence | Link |
| --- | --- | --- | --- |
| Jitter fix | "When using a custom physics interpolation solution, the physics jitter fix should be disabled by setting it to 0.0." Default 0.5 | F7, CAM-25 | [ProjectSettings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-physics-common-physics-jitter-fix) |
| Delta smoothing | Active only with V-Sync Enabled. Adaptive and Mailbox V-Sync are unsupported in Compatibility | Measure CAM-21 with V-Sync on and off | same page; [jitter and stutter](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html) |
| Camera under interpolation | The docs recommend a manual camera updated in `_process` from the interpolated pose, which is what the rig does | Keep it; do not switch to engine interpolation or SpringArm3D | [advanced interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html) |
| SpringArm3D | Updates every physics tick with no smoothing and sees only Godot physics bodies, not our CollisionWorld or heightfield | Write chase clearance ourselves (CAM-09) | [SpringArm3D](https://docs.godotengine.org/en/stable/classes/class_springarm3d.html) |
| Lens shift | `PROJECTION_FRUSTUM` + `frustum_offset` works in Compatibility (sky shear fixed in 4.4); `size` is the near-plane height. `unproject_position` honours the offset, but `project_ray_*`, `project_position` and `is_position_in_frustum` do not | CAM-06b vertical shift; tests measure with `unproject_position` | [#86138](https://github.com/godotengine/godot/pull/86138), [#61174](https://github.com/godotengine/godot/issues/61174), [#75973](https://github.com/godotengine/godot/issues/75973) |
| Near-camera parts | `Z_CLIP_SCALE` and `fov_override` (4.5) draw near objects pulled toward the camera with their own FOV; GLES3 has the code path (source reading, not run) | Onboard airframe parts without a second viewport (CAM-11) | [#93142](https://github.com/godotengine/godot/pull/93142) |
| Custom projection | 4.8 `RenderingServer.camera_set_xr_projections()` (experimental) accepts any matrix; no depth gain | Watch for the 4.8 upgrade only | [#116424](https://github.com/godotengine/godot/pull/116424) |
| Effects absent in Compatibility | Auto-exposure, depth of field, motion blur, TAA/FXAA/SMAA, FSR (falls back to bilinear), CompositorEffects; aerial perspective is commented out in the GLES3 scene shader | Keep the custom exposure; any DOF or blur must be our own shader on a `SubViewport`, and only in video views | [renderers](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html), [CameraAttributes](https://docs.godotengine.org/en/latest/classes/class_cameraattributes.html) |
| Effects present | Glow, MSAA 3D, depth/height fog with sun scatter, simplified SSAO since 4.6 | Already used | [#109447](https://github.com/godotengine/godot/pull/109447) |
| Measurement | `viewport_set_measure_render_time` gives GPU time through GL timestamps. Pipeline-compile counters are always 0 in Compatibility, and there are no ubershaders | Find view-switch hitches by frame time; warm up the shaders a new view shows | [RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html), [jitter and stutter](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html) |
| Docs error | "3D rendering limitations" still says depth is "32-bit on desktop", which source and the renderer table contradict for Compatibility | Possible upstream docs fix | [limitations](https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limitations.html) |

### Add-ons, libraries and tools

The project rule is to reuse free downloads before writing code. No camera add-on fits, because the rig already does what they do, and does it without their defects.

| Candidate | Licence and status | Decision | Reason |
| --- | --- | --- | --- |
| [Phantom Camera](https://github.com/ramokz/phantom-camera) | MIT, v0.11.0.3, active | Not adopted | Duplicates the rig. Its third-person collision is SpringArm3D, and it has an open bug: damped follow of physics objects jitters below 60 fps ([#206](https://github.com/ramokz/phantom-camera/issues/206)) |
| Shake add-ons (Shaker, Camera Shake 3D, NodeShaker3D) | MIT or CC0; Cinematic Camera Shake is AGPLv3 (rejected) | Not needed | No shake by default. The optional trauma shake is about 20 lines on the built-in `FastNoiseLite` |
| [lawnjelly smoothing](https://github.com/lawnjelly/smoothing-addon) | MIT | Obsolete | Its README points to core interpolation |
| Motion blur and lens-flare add-ons | MIT | Not usable | The maintained ones are CompositorEffects, which Compatibility lacks; sun glare already exists |
| [opentrack](https://github.com/opentrack/opentrack) | Free external app, active, includes a webcam (NeuralNet) tracker | Adopt for X-PERC-8 | Its UDP output (`double[6]`, port 4242) needs only a `PacketPeerUDP` reader |
| [TrackIR Godot SDK](https://github.com/TrackIR/TrackIR-SDK-Godot) | No licence file | Do not vendor | Redistribution rights unknown |
| [GDMP](https://github.com/j20001970/GDMP) (MediaPipe) | MIT, native | Not now | Heavy native libraries; opentrack covers webcams |
| godotshaders barrel and VHS shaders | CC0, MIT or GPLv3 per shader; some ports declare CC BY-NC-SA | CC0 only, with provenance | For the CAM-12 warp and the analog FPV look; reject non-commercial ports |
| PicaSim source | PolyForm Noncommercial | Study, never copy | The laws above are re-derived, not ported |
| [MangoHud](https://github.com/flightlessmango/MangoHud) / [PresentMon](https://github.com/GameTechDev/PresentMon) | MIT | Use for CAM-21 | Frame-interval CSV on Linux (OpenGL included) / present-to-display timing on Windows |

## Proposed steps

Added to the [plan](../../../plans/camera-views.md#8-steps) as proposed rows. Each is small and has its own proof; the order puts fixes to existing behaviour before new views.

| ID | Work | Proof |
| --- | --- | --- |
| CAM-23 | Resolution-independent auto-zoom: target as a fraction of the viewport height (default 30/1080), used by the pilot aids and the FAR warning alike | 1080p pilot captures byte-identical; 1440p and 2160p span fraction equal to 1080p's; the 720p change is shown and explained |
| CAM-24 | Chase smoothness: velocity from the simulation state (prime and drive), fixed ≤ 1/240 s sub-steps with the target interpolated inside the frame, optional heading feed-forward; document the frame-order contract for camera consumers | `test_camera_views` gains the turn, loop and hammerhead tapes: ∣30 − 144 fps∣ ≤ 1 cm, entry transient 0, rig ≤ 50 µs |
| CAM-25 | `physics_jitter_fix = 0` (main line owns `project.godot`) | A/B with the CAM-21 jitter metric at 60/144 Hz, V-Sync on and off, on the target machine; traces byte-identical |
| CAM-26 | One camera input router and a per-vehicle camera profile in data (span, default zoom, near/far) for the airplane, helicopter and truck routes; truck near plane ≥ 0.05 m | `test_camera_route` per route (Shift+C, Backspace, wheel `factor`, reset on restart); truck before/after captures |
| CAM-27 | First crash-focus slice of CAM-03: non-pilot views frame the wreck core, not the impact point; the orbit retargets it and stays controllable; the director's view gets a terrain, obstacle and water clearance and a short blend | `test_crash_pose` unchanged for the pilot view; the live scenario below shows the wreck on screen after "Inspect wreck" in orbit, chase and close-up; clearance checks |
| CAM-28 | Pilot overhead option: screen-roll rate cap, off by default until CAM-22 | Probe numbers reproduced in a test; the pilot rates it |
| CAM-29 | Orbit and controller polish: damped rotation and dolly, captured cursor while dragging, sensitivity and invert settings, controller look and hold-to-zoom | `test_camera_views` continuity; `test_camera_route` for mouse and controller |
| CAM-30 | Field-videographer view: ground tripod with a telephoto (2.3–10° vertical), damped operator pan-tilt, FlightGear-style re-placement, optional 3–9 Hz handheld jitter (off in comfort mode), shutter-aware propeller disc | Placement never inside terrain or obstacles over a recorded circuit; captures; comfort mode removes the jitter; cost |
| CAM-31 | Camera quality gates: jitter metric through `unproject_position`, frame-rate independence on recorded flight tapes, a ringing check in the 0.2–0.4 Hz band, first-switch hitch per view with `debugctl frames` | New test and a `debugctl` scenario in the smoke set |

Order: CAM-24, 23, 26, 25, 27 (fixes) → 02b, 17 with 29 (settings) → 06/06b/07 with 28 (pilot aids, judged in CAM-22) → 16 → 14 and 30 (spectator views) → 18 → 11/12 → 09 → 31 alongside each.

How the survey refines existing steps:

| Step | Refinement |
| --- | --- |
| CAM-06 | Add PicaSim's angle-space blend as the "auto-zoom amount" slider, and its horizon amount as a cheap alternative to KGIV |
| CAM-06b | Use frustum mode with `frustum_offset`; test framing with `unproject_position` only |
| CAM-09 | Our own swept sphere against heightfield and boxes; pull in fast, ease out slowly after a dwell time (Cinemachine deoccluder) |
| CAM-11/12 | DJI O4/O4 Pro/analog presets (FOV, latency as a frame queue); failure looks per system; horizon-levelling options (rigid / ±27° / ±45° / 360°); `Z_CLIP_SCALE` for airframe parts; CC0 barrel warp |
| CAM-14 | FlightGear placement law plus our sun-side and obstacle rejection |
| CAM-16 | Call `reset_observer` on every cut |
| CAM-17 | XAG 117 block: FOV (labelled vertical, with a natural-FOV helper), automatic-motion off, per-axis sensitivity and invert, chase distance, camera-motion intensity 0–100 %; comfort defaults in replays |
| CAM-18 | Aircraft-only magnifier through a `SubViewport` cull mask (PicaSim), which removes most of the second-render cost; the full-scene inset stays the expensive option |
| Later, no step yet | Trauma shake that reaches each camera after distance/343 s (never in the pilot view); two-target framing for companions; X-Plane "linear spot" and Quick Looks; sky-grid overlay (HUD track); split screen |

## Reproduce the live run

From the repository root, on a machine with no other rendered Godot app:

```sh
D="python3 tools/debug/debugctl.py"
$D launch                                   # 1920×1080; note the port it prints
OPENRC_DEBUG_BRIDGE=<port> $D run research/camera-views/audit-2026-10-24/live_scenario.txt
OPENRC_DEBUG_BRIDGE=<port> $D stop
```

Screenshots go to the run folder under `tmp/debug-bridge/`. A relative `screenshot path=` resolves against `app/`, which git does not ignore, so pass an absolute path or none. The wreck's slide distance varies from run to run.

## Limits

- VM software checks only. The jitter-fix result is a timing measurement under a noisy, vsync-less VM clock; the target machine decides.
- Probes use synthetic trajectories, not flight logs; a recorded tape (FLIGHT-LOGGING) is the next level of evidence for CAM-24.
- External findings are dated 2026-10-24; commercial simulators document cameras poorly, and gaps are listed in each survey.
- Readability, comfort and the choice between candidate laws (F4, F12, D4, D11) need the pilot on the target display (CAM-22).
