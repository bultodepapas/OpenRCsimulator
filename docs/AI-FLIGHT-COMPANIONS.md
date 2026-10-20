# AI flight companions

Status: experimental airborne slice, 2026-10-20. The remaining work and release
gates live in [the implementation plan](../AI_FLIGHT_COMPANIONS_PLAN.md).
[Verification and measured limits](research/ai-companions/AFC-00-06/README.md).

## Use

1. Choose **Club field** and a fixed-wing player aircraft on Home.
2. Open **Flight companions**, enable companions, choose **1–3**, and Apply.
   Start with one; additional aircraft substantially increase CPU cost.
3. Fly. The companions launch airborne in separated circuits north of the runway.
4. **Pause → Session options → Flight companions** shows the current population.
   Apply changes, then **Restart flight** to rebuild the roster. Changes made here
   stay with this flight unless **Save these settings as the default** is selected.
5. **Remove companions now** immediately clears their sessions, models and audio.
   Restart brings back the configured roster. To keep them off, disable and Apply.
   Cancel discards the dialog draft.

Off is the default. Each companion uses the bundled Jensen Das Ugly Stik 60,
an experienced circuit controller, independent full aircraft dynamics, and a
bounded spatial engine voice. There are no duplicate cameras or field soundscapes.
Player aircraft selection does not change the AI aircraft.

The seed selects starting phase/direction and per-aircraft turbulence seeds.
Repeatability requires the same aircraft data, source, weather and initial roster.
The current roster is created only at tick zero; settings do not add aircraft
midflight. Menus, focus/controller holds and a stopped player simulation also stop
the companion clock.

## Current limits

| Setting or behavior | Available now |
| --- | --- |
| Field | Club field only; normal fixed-wing flights |
| Weather | Reference atmosphere; mean wind ≤1.5 m/s, gust ≤0.6 m/s, updraft ≤0.15 m/s, turbulence RMS ≤[0.15, 0.15, 0.08] m/s |
| Aircraft/activity/skill | Ugly Stik circuits, experienced pilots |
| Population | Experimental fixed roster of 1–3; higher counts refused |
| Avoidance | Predicted closest approach biases heading/altitude; no guaranteed separation from arbitrary player maneuvers |
| Aircraft contact | Disabled; overlapping airplanes do not exchange contact forces |
| Terrain/scenery | Each companion retains ordinary session contact/crash checks; only the player changes shared scenery damage |
| Crash/fault fallback | That companion stops, its voice is silenced, and status identifies it; restart or Remove clears it |
| Logging/checkpoints | Existing logs describe the player. A player-only paired checkpoint cannot save/restore while companions remain |
| Technical routes | Scripted flight, trace/capture, Workshop, experimental aircraft-data routes and Natural Random do not admit companions |

Takeoff/landing cycles, other models, low passes, aerobatics, overtaking activities,
pilot difficulty choices, incidents, comic scenarios and busy-skies presets are
still planned. No control advertises them as available. No model, physics law,
solver frequency or golden flight was retuned to make this slice work.

The measured three-companion CPU workload misses the plan's initial fleet budget.
This is not a 60 fps or target-hardware qualification. Long sessions, finite-fuel
recovery, fleet replay, full crash presentation, translation coverage and platform
package checks remain open.

## Developer entry points

Direct launches ignore Home preferences:

```powershell
.tools/Godot_v4.7.2-stable_win64_console.exe --path app -- --quick-flight --companions=1 --companions-seed=20261020
```

`--companions=0` explicitly disables companions. Counts above 3, invalid seeds and
unsupported enabled configurations fail before the flight is accepted.

| File | Responsibility |
| --- | --- |
| `app/ai/companions/config.gd` | Bounded settings and explicit CLI overlay |
| `app/ai/companions/pilot.gd` | Float64 guidance, control demands and proximity response |
| `app/ai/companions/manager.gd` | Stable tick snapshots, population ownership, scenery-mask publication |
| `app/ai/companions/agent.gd` | One external-driver session and its render/audio adapter |
| `app/sim/flight_session.gd` | Validated external commands, spawn and single-tick seam |
| `app/main.gd` | Launch/refusal, deferred restart, status and checkpoint boundary |
| `app/ui/companions_dialog.gd` | Draft settings; Home/Pause owners perform persistence |

These are programmatically composed nodes, matching the current Main/UI pattern;
there is no second Main scene per airplane. Every AI session owns its own
`VehicleModel`. The kernel remains unchanged.

The player keeps its original tick driver. `before_step` captures accepted tick N
states; the player's successful `stepped` signal plans every AI against that same
snapshot, then advances each once. Aircraft planning runs at 60 Hz and aircraft
physics at 240 Hz. A rejected player step never advances companions. Player damage
is mirrored after all AI finish that tick, for use at the next boundary.

Run focused tests through `tools/godot/run_checked.py`:
`test_companions_config.gd`, `test_companions_session.gd`,
`test_companions_pilot.gd`, `test_companions_manager.gd`,
`test_companions_dialog.gd`, and `test_companions_shell.gd`.
The long qualification matrix lives outside the regular unit suite in
`research/ai-companions/pilot_probe.gd`. The same directory contains complete
callback cost and native render probes. See the evidence report for invocations.
