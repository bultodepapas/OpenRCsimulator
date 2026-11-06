# Game bugs and opportunities found while building debug tools — 2026-11-06

Dated research. These findings came up while PT1h-R9 to R11 were built and verified; they are not a systematic
audit. The tools and their evidence are in the [debug tooling note](debug-tooling-render-rewind-2026-11-06.md).

**Machine.** All runs: Windows 11, NVIDIA RTX 3090, Godot 4.8 beta2, Compatibility renderer, 1920×1080, vsync at
120 Hz, Ugly Stik on Club field unless stated. They are short development screens, not hardware qualification.
On Apple Silicon or other GPUs, re-measure with `render` and `ablate` before acting.

**Status.** The **Status** column is current; the [fix log](#fix-log-pt1h-r12) has the evidence for each fix. The
**Owner** column names the track best placed to decide on what remains open.

## Summary

| # | Finding | Kind | Severity | Owner | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Aircraft projected-shadow silhouette costs about 0.9 ms GPU per frame | Performance | High | Shadows / graphics | **Fixed** (PT1h-R12) |
| 2 | The aircraft costs 280 draw calls and about 1.2 ms GPU | Performance | Medium | Aircraft visuals | Open: asset pipeline |
| 3 | Desktop frames are CPU- or vsync-bound, not GPU-bound | Performance | Medium | Performance (PT) | Open: profile |
| 4 | Half 3D resolution makes Compatibility slower on a fast GPU | Performance policy | Medium | Graphics settings | **Already handled** by the reconstruction policy |
| 5 | Home → Fly builds the flight in one frame of 3.6–6 s | UX / performance | Medium | UI / loading | Open |
| 6 | A long stall when Home starts (one stale 971 ms GPU reading) | Performance | Low; needs a re-check | Graphics | Open: re-check |
| 7 | AppRoot setters ignore invalid values silently | Bug-prone API | Medium | App / UI | **Fixed** (PT1h-R12) |
| 8 | Paired visual checkpoint refused in default flights | Limitation | Medium | Time of day (TOD) | Open |
| 9 | Session restore leaves the pilot without control | Contract trap | Medium | Flight session | **Fixed** (PT1h-R12): explicit hand-back |
| 10 | Scripts re-set `visible` every frame on some nodes | Hygiene / CPU | Low | Rendering | **Not a bug** (see #10) |
| 11 | Key 3D nodes have generated names (`@MeshInstance3D@263`) | Debuggability | Low | Rendering / main | **Fixed** (PT1h-R12) |
| 12 | Almost no controls have accessible names | Accessibility | Medium | UI | **Fixed** (PT1h-R12): an app-wide label rule, Settings, close buttons |
| 13 | Shadow-pass counters read 0 in Compatibility | Engine reporting | Info | Graphics | Engine |
| 14 | Wireframe and most debug views do nothing in Compatibility | Engine limitation | Info | Graphics | Engine |
| 15 | Rendered airborne start opens on the launch menu | UX check | Low | UI | Open: design question |
| 16 | Orphan nodes created at flight start | Hygiene | Low | Main / flight | **Verified by design**: no leak |
| 17 | The bridge test used a fixed port that concurrent agents shared | Test bug | Fixed | Debug tooling | Fixed (PT1h-R11) |

## Performance

### 1. Aircraft projected-shadow silhouette, about 0.9 ms of GPU per frame

**Evidence:**

- `render` lists `AppRoot/Main/@MeshInstance3D@263/ProjectedShadow/Silhouette256` (256×256, update "once")
  at 0.84–0.92 ms median GPU on every frame. That is 30–37 % of the frame's GPU time.
- `ablate`: switching off every SubViewport saved 1.05 ms of a 2.59 ms baseline, against a noise of 0.075 ms.
  That was the largest saving after hiding the aircraft itself.
- The update mode is re-requested every frame, so "once" is effectively "always".
- The cost follows the aircraft's draw calls (finding 2), not its 65,536 pixels.

**Opportunities:**

- render the silhouette from one merged, low-detail mesh;
- or update it every second or third frame, or only when the attitude or sun changes beyond a threshold;
- or reuse the aircraft's draw list at a lower LOD.

**Measure again** with `ablate targets=@subviewports,airplane` and `render`.

### 2. The aircraft is 280 draw calls and about 1.2 ms of GPU

**Evidence:**

- `layers`: `airplane` has 99 geometry instances and 88 shadow casters.
  - `airplane/control_system` alone is 36 instances and 80 draw calls.
  - The wing frames, dowels and retainers are separate meshes.
- `ablate`: hiding `airplane` saved 1.24 ms (47 %) and 280 draw calls. This includes its silhouette pass.

**Opportunities:**

- merge static sub-meshes that share a material at export;
- draw far-away detail through LODs;
- stop casting shadows from small internal parts.

The node and hinge names in [AIRCRAFT_CONTRACT](../AIRCRAFT_CONTRACT.md) must stay stable, so merge only parts that
never move.

### 3. On a desktop GPU, the frame is limited by the CPU or by vsync

**Evidence:** in flight, the GPU worked 2.7–2.9 ms of an 8.9–9.5 ms frame (105–112 fps against a 120 Hz cap).

- `render` judged the frame `CPU` in one run and `frame cap` in another.
- `perf` once reported `process_ms` 11.4 ms.

**Opportunity:**

- On machines like this one, frame time is limited by the CPU side: GDScript, the simulation and the bridge.
- Profile a steady flight with `launch --script-profile`, then `profile seconds=20`, on Windows, and compare the
  result with the M1 GPU-bound picture.
- Optimizations for one platform do not transfer to the other.

### 4. Half 3D resolution costs 76 % more GPU on the Compatibility renderer here

**Checked (PT1h-R12): already handled.** [reconstruction.gd](../../app/render/reconstruction.gd) (VQ-07d, DT-MAC-07b)
chooses a reduced 3D scale automatically only for MetalFX Spatial on a Mac, and only when the 3D input stays
1080p-class. Every other platform's `auto` is Native, scale 1.0. Reduced scales come only from an explicit FSR or
DLSS choice. The measurement stays as evidence for that policy. The original note follows.

**Evidence:**

- `ablate` with `@half_res` (`scaling_3d_scale` × 0.5): −1.08 ms, so the GPU time grew from about 1.4 to 2.5 ms.
- In a second run it cost −0.11 ms. In neither run did it save time.

**Opportunity:**

- Treat 3D scaling as a fix for pixel-bound GPUs only, and decide it per platform or adapter.
- Do not apply it as a general "performance" preset. On M1 it is a large gain, because that frame is pixel-bound.

### 5. Home → Fly builds the whole flight in one frame

**Evidence:**

- `frames` in a headless run: one 5,966 ms frame at flight start, +1,684 objects, +538 nodes and +84 MiB, with
  physics catch-up (12 ticks).
- The 2026-10-24 note measured 3.25–3.7 s for the same frame.
- Rendered runs also showed a 142 ms frame with +176 orphan nodes right after the start.

**Opportunity:**

- A staged build with progress, or preparing the build behind the Home screen (see UI-05-R3 in
  [DECISIONS](../DECISIONS.md)).
- Re-measure on the current tree: the jump from 3.6 s to 6 s may be headless start-up noise or real growth.

### 6. A long stall when Home starts

**Evidence:** the first `render` on Home read one GPU frame of 971 ms. That reading had come from an earlier,
long frame: shader or pipeline compilation, or the first upload.

**Opportunity:** if this repeats on a cold start, warm shaders up behind the loading screen.

**Re-check:** `frames` and `render` right after `launch`, three cold starts.

## Bugs and API traps

### 7. AppRoot setters ignore invalid values silently

**Evidence:**

- `set_landscape`, `set_time_of_day`, `set_language` and `set_start_choice` return without effect or message for
  an unknown id. The guards are in [app_root.gd](../../app/app_root.gd).
- `set_start_choice("hand_launch")` on an aircraft that cannot hand-launch silently becomes `airborne`.
- The debug bridge's new `setup` now validates and reads back. Any other caller still gets no signal: command-line
  options, companions, scenarios, future scripting.

**Opportunity:**

- Return a result such as `{ok, applied, reason}`, or log a warning, from these setters.
- Show the adjusted start choice on Home; it already changes the button text.

### 8. The paired visual checkpoint (TOD-08a) is refused in default flights

**Evidence:** `main.checkpoint()` returns `{}` whenever `_field_world_lighting` is true, which is the default
time-of-day lighting. `restore_checkpoint()` then answers "visual checkpoint requires a ready production flight".

**Impact:**

- Any feature built on the paired checkpoint, such as practice "retry from here" or saved situations, works only in
  legacy lighting.
- The bridge's `rewind` and `bugit` use the session (physics) checkpoint for this reason. The visuals are rebuilt as
  on a restart.

**Opportunity:** extend the visual checkpoint to world lighting, which is the solar progression controller noted in
the code.

### 9. Session restore leaves the pilot without control

**Evidence:**

- `FlightSession.restore_checkpoint()` sets `input_enabled = false` and the pause reason "checkpoint restored
  (recorded inputs)".
- This is correct for replay: the restored inputs stay fixed.
- After a restore and `resume`, the Ugly Stik flew level for minutes with the sticks ignored.
- `rewind` and `bugitgo` hand control back explicitly.

**Opportunity:**

- Make the mode explicit in the API, for example `restore_checkpoint(snapshot, {inputs = "recorded" | "pilot"})`,
  before a player-facing "retry from here" feature uses it.
- Otherwise the first in-game use of restore will look broken.

### 10. Some nodes have `visible` set again every frame

**Correction (PT1h-R12): not a bug.** Godot's `Node3D.set_visible` and `CanvasItem.set_visible` return at once when
the value does not change. Re-assigning the same state sends no notification and has no measurable cost. The only
real effect is that tools cannot hide these nodes, and `ablate` already flags them as `overridden`. The original
note follows.

**Evidence:** while `ablate` held them hidden, `SunGlare`, the aircraft projected-shadow mesh
(`@MeshInstance3D@263`) and the flight `CanvasLayer`s came back on within the phase. The `overridden` flag marked
them.

**Impact:**

- Each assignment may send visibility notifications every frame, a small CPU cost.
- Debug tools and future features cannot hide these nodes.

**Opportunity:** set visibility on change only, or expose an explicit switch for each such feature. Those switches
would also become `ablate` flags.

## Debuggability and accessibility

### 11. Key 3D nodes have generated names

**Evidence:**

| Generated name | Node |
| --- | --- |
| `@MeshInstance3D@263` | aircraft projected shadow |
| `@Node3D@767` | smoke system |
| `@DirectionalLight3D@262` | sun |
| `@Camera3D@264` | flight camera |
| `@WorldEnvironment@228` | environment |
| `@Node@766` | flight session |

These names change between runs, so scripts, scenarios and reports cannot address the nodes reliably.

**Opportunity:** give them stable names where they are created, such as `AircraftShadow`, `Smoke`, `Sun`,
`FlightCamera`, `Environment` and `Session`. This is a few lines each.

### 12. Almost no controls have accessible names

**Evidence:**

- Only 2 `accessibility_name` assignments exist in `app/` (`ui/sky_controls.gd`).
- Settings' OptionButtons are named only by the Label before them in the grid.
- The overlay close buttons are a bare "×", identified only by their tooltips.
- Godot 4.5+ exposes `accessibility_name` to screen readers through AccessKit.

**Opportunity:**

- Set `accessibility_name` on value controls (option, slider, toggle) and on symbol-only buttons.
- Screen-reader players and agents both benefit. The bridge's `look` uses `accessibility_name` first, and the
  label-guessing becomes a fallback.

### 13. Shadow-pass counters read 0 on the Compatibility renderer

**Evidence:**

- `viewport_get_render_info(..., VIEWPORT_RENDER_INFO_TYPE_SHADOW, ...)` returned 0 draw calls, although the sun
  casts shadows.
- Ablating `@shadows` removed 138 draw calls and 55,551 primitives from the totals.

**Impact:** shadow cost is invisible in per-pass counters on this renderer. Use `ablate @shadows` instead.

### 14. Wireframe and most debug views do nothing in Compatibility

**Evidence:**

- `overdraw` and `unshaded` change the picture.
- `wireframe` covers only meshes created after it was enabled.
- The GI, SSAO and cluster views need Forward+ or Mobile.

This is an engine limitation. It is documented in the [bridge guide](../../tools/debug/README.md#render-cost-pt1h-r9).

## UX observations

### 15. A rendered airborne start opens on the launch menu

**Evidence:**

- In rendered sessions, `fly start=airborne` returned with the pause screen ("launch review") holding the flight
  (`holds: ["menu"]`). Headless runs started flying at once.
- Measurements and screenshots taken right after `fly` show the menu, not the flight.

**Check:** whether the player is meant to confirm every airborne start, or only the first one.

### 16. Orphan nodes at flight start

**Evidence:**

- One rendered start logged a hitch with +176 orphan nodes and +314 objects.
- Steady-state soaks report 0 orphans, so they are freed later or reused.

**Opportunity:** if they are temporary build nodes, free them in the same frame or build them inside the tree; that
also shortens finding 5. Check with `objects baseline=true` before Fly and `objects diff=true` right after.

## Test infrastructure

### 17. The bridge test's fixed port was shared with concurrent runs (fixed)

**Evidence:**

- Intermittent `test_debug_bridge.gd` failures returned another process's PID and state.
- Another agent was running the same checks on this machine. On Windows, two loopback listeners may share port
  47911.
- The test now picks a free port.

Other tests that open sockets already use port 0 (`fake_releases.gd`, `test_update_check.gd`).

**Opportunity:** when tracks run suites in parallel on one machine, avoid fixed ports and shared output folders
in new tests.

## Physics notes (no defect found)

- **Overlay against HUD.** The flight-model overlay agreed with the independent HUD: 26.3 m/s against 59 mph, and
  41.5 m against 136 ft.
- **Level flight.** The aerodynamic and propulsive force read 1.02 g up, and lift balanced weight at n = 1.00 g.
- **Exact restore.** Two branches restored from one checkpoint, each stepped 480 ticks, gave identical state hashes.
  A bugit checkpoint restored from Home matched its source hash.
- **Recovery after a nose-down input.** With pitch −0.8 and full throttle, the Ugly Stik flew an outside loop and
  kept flying, instead of diving in. With pitch −1, it crashed at 31.5 m/s. Plausible for that airframe; a pilot
  should judge it with a flight log, not this note.

## Fix log (PT1h-R12)

### #1 Projected-shadow silhouette

[projected_shadow.gd](../../app/render/projected_shadow.gd) reuses the drawn mask while the change cannot show in
the blurred shadow:

- attitude and light direction within 0.25°;
- blur within 2 mm;
- the same bounds and scale.

Tolerances are measured against the last drawn mask, so they cannot accumulate. The receiver still follows the
aircraft and its blur on every frame. Before, an exact comparison redrew the 165,398-triangle, MSAA 4x silhouette on
every flying frame. That included the blur, which changes with every millimetre of height.

**Effect** (rendered app):

| Flight phase | Masks redrawn |
| --- | --- |
| Hands-off flight | 2.3 % of frames |
| First 4 s | 2.7 % |
| Gentle climbing turn | 3.9 % |
| Active roll | 85.5 %, as intended |

The frame's median GPU time in steady flight went from 2.7–2.9 ms to 1.83 ms. A daylight screenshot at 3.9 m shows
the silhouette following the pitched-down attitude.

**Tests:** `test_projected_shadow.gd`, 47 checks, 5 new:

- the reuse cosine matches the angle;
- 0.1° steps are reused until the total from the drawn mask passes 0.25°;
- a reused mask still moves and blurs;
- a scale change always redraws.

The shadow, field-shadow, ownership, cue, windsock and Home-preview suites pass: 374 checks.

`redraw_count` stays on the node as a diagnostic.

### #7 AppRoot setters

`set_language`, `set_aircraft`, `set_start_choice`, `set_time_of_day` and `set_landscape` now return whether the
requested value is in effect. `set_start_choice` returns false when Home falls back, for example to `airborne` for
an aircraft that cannot hand-launch. UI signal callers ignore the value. No warning is logged, because some tests
pass invalid values on purpose.

### #9 Session restore and pilot control

`FlightSession.hand_control_to_pilot()` is the explicit hand-back after `restore_checkpoint()`, whose replay contract
is unchanged:

- pilot input resumes from the recorded throttle, with centred sticks;
- the flight stays paused until `resume()`;
- external drivers are refused.

The debug bridge's `rewind`, `checkpoint load` and `bugitgo` use it.

**Tests:** `test_checkpoint.gd`, 104 checks, 12 new: three per aircraft, for the Ugly Stik, Extra, P-51 and Vantage.
The restore pause reason, the refusal for an external driver, and the throttle, sticks, pause and untouched physics
after the hand-back.

### #10

Corrected to "not a bug"; see the finding.

### #11 Stable node names

| Node | Created in |
| --- | --- |
| `PilotCamera` | `render/pilot_camera.gd` |
| `Sun` | `render/atmosphere.gd` |
| `WorldEnvironment` | `render/world/world.gd` |
| `AircraftShadow` | `render/shadow.gd` |
| `FlightSession` | `main.gd` |
| `Smoke` | `main.gd` |

### #12 Accessible names

**App-wide rule.** [ui/accessible_labels.gd](../../app/ui/accessible_labels.gd), installed first in AppRoot:

- A Label immediately before a value control in the same container labels it, through
  `accessibility_labeled_by_nodes`. Value controls are option, range, text, list, and a check box without its own
  text.
- It applies to every node as it enters the tree, so screens and tabs built later are covered.
- The link is to the Label node, so the name follows the Label's text after a language change.
- Explicit names are never overridden.
- Internal children, such as scroll bars, are skipped. The first version asked their index, which the checked
  runner reported as 54 engine errors.

**Explicit names.**

- Settings rows also set their caption as `accessibility_name`, retranslated with the captions.
- Overlay close buttons take their tooltip ("Close · Wind").

The debug bridge's `look` reads the same link.

**Tests:** `test_accessible_labels.gd`, 11 checks:

- the first sweep, later rows and whole subtrees;
- the name following a text change;
- buttons, labelled check boxes, explicit names, missing or blank labels and non-container parents are left alone;
- internal scroll bars;
- disconnection.

### #16 Orphan nodes at flight start

**Verified as designed; no code change.** Home prepares the selected flight scene privately and attaches it after
validation (UI-05-R3 in [DECISIONS](../DECISIONS.md)).

Fresh rendered session:

| Moment | Orphans | Other counters |
| --- | --- | --- |
| Three start frames | +176, +10, +73 (hitches of 167, 84 and 495 ms) | |
| Flying, 6 s later | 0 | |
| Back on Home | 0 | the same 924 nodes; +81 objects, +3 resources, +12.6 MiB |

The remainder on Home is first-use caching: the fly/Home soak in `smoke` shows no growth after its warm-up cycle.
The three start hitches belong to finding #5.

