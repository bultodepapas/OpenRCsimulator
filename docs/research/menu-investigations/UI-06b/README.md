# UI-06b — Home runway selector

2026-10-08 · Step prefix: **UI-06b** · **Status: software verification complete.** This evidence covers the interactive Home selector, saved launch choice and runway-start route. It does not establish pilot handling, takeoff quality or physical model accuracy.

## Reproduce the focused UI checks

From the repository root:

```sh
XDG_DATA_HOME=/dev/shm/ui06b-focused .tools/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path app --check-only --script res://tests/test_ui_runway.gd
XDG_DATA_HOME=/dev/shm/ui06b-focused .tools/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path app --audio-driver Dummy --script res://tests/test_ui_runway.gd
```

Result: **0 failed.** The real keyboard path selects runway from Home, and fake joystick events do not navigate menus. The test covers old, invalid and future preferences; save failures; aircraft and field restrictions; a rejected launch and retry; Home → flight → Home → flight; R, Pause → Restart and crash recovery; and fake-radio throttle/roll input. The aircraft-sanitization route checks the Extra, P-51 and Avanti. Runway is written only after Fly succeeds, and the selected choice survives resets and the Home round trip.

The focused script passed Godot `--check-only`. The Godot project linter reported **0 errors and 0 parse errors**; its 12 warnings are existing references and fixtures elsewhere in the project.

The full `app/test.sh` run also exited successfully. Its consolidated run evidence is recorded with [UI-06c](../UI-06c/README.md).

## Captures

Each capture was produced with `.tools/visual-venv/bin/python app/tests/capture_runner.py`, the pinned Godot 4.7.2 executable, `xvfb-run`, OpenGL Compatibility/llvmpipe, dummy audio and a 1280×720 display. The runner verified the PNG, native manifest and image SHA-256. The Home manifests record the selector bounds and confirm that it fits the sidebar and viewport without overlapping Fly. Flight captures use the real Home → Fly route and record the selected runway choice before the transition. From the repository root, the commands are:

```sh
capture() {
  local name="$1" scene="$2" lang="$3" start="$4" aircraft="${5:-}"
  local out="$PWD/docs/research/menu-investigations/UI-06b/captures/${name}.png"
  local xdg="/dev/shm/ui06b-captures/${name}"
  local args=("--out=${out}" "--lang=${lang}" "--screen=${scene}" "--start=${start}")
  if [[ -n "$aircraft" ]]; then args+=("--aircraft=${aircraft}"); fi
  mkdir -p "$xdg"
  env XDG_DATA_HOME="$xdg" XDG_CACHE_HOME="$xdg/cache" LP_NUM_THREADS=1 \
    .tools/visual-venv/bin/python app/tests/capture_runner.py \
      --out "$out" --kind ui --scene "$scene" -- \
      xvfb-run -a -s "-screen 0 1280x720x24" \
        env XDG_DATA_HOME="$xdg" XDG_CACHE_HOME="$xdg/cache" LP_NUM_THREADS=1 \
        .tools/Godot_v4.7.2-stable_linux.x86_64 --path app \
          --rendering-driver opengl3 --audio-driver Dummy \
          --script res://tests/capture_ui.gd -- "${args[@]}"
}
capture home-runway-en home en runway
capture home-runway-es home es runway
capture flight-runway-en flight en runway
capture flight-runway-es flight es runway
capture home-airborne-en home en airborne
capture home-extra-en home en airborne gp-extra-300s-60
```

| Capture | Selector evidence | Result |
| --- | --- | --- |
| [Runway Home, English](captures/home-runway-en.png) | `Start: runway (experimental)` | Pass, 1280×720 |
| [Runway Home, Spanish](captures/home-runway-es.png) | `Inicio: pista (experimental)` | Pass, 1280×720 |
| [Runway flight, English](captures/flight-runway-en.png) | Interactive Home → Fly, selected start `runway` | Pass, 1280×720 |
| [Runway flight, Spanish](captures/flight-runway-es.png) | Interactive Home → Fly, selected start `runway` | Pass, 1280×720 |
| [Airborne Home, English](captures/home-airborne-en.png) | `Start: in the air` | Pass, 1280×720 |
| [Extra Home, English](captures/home-extra-en.png) | Runway selector disabled | Pass, 1280×720 |

Every image has a neighboring JSON manifest with the full hash and runtime evidence. The capture logs are retained alongside them. Flight transition timing in the manifest is diagnostic only: llvmpipe is not a performance measurement.

## Limits

This is software evidence from the source tree on Linux with software rendering. It verifies the selector, transitions, save/error behavior and selected-start propagation. It does not test physical radio hardware, a packaged build, pilot readability on target hardware, flight handling, taxi, takeoff or landing. The runway choice remains experimental and supported only by the default field with the Ugly Stik.

## 2026-10-16 — Fleet runway default (UI-06d-R3)

This follow-up supersedes the original aircraft restriction above. All eight current catalog airplane configurations support runway starts on the default field. Home starts with runway, then cycles to airborne and the optional Stik half-power start. Missing/invalid saved choices recover to runway; explicit airborne choices remain valid. Quick Flight defaults to runway and accepts `--start=airborne`. Technical traces retain their airborne reference fixture. Restart repeats the selected condition.

Native Windows Godot 4.7.2 checks passed without engine errors:

- `test_ui_runway.gd`: real EN/ES navigation, preferences, rejection/retry, radio isolation, restart and Home → Fly → Home for every airplane.
- `test_runway_fleet.gd`: 116 checks; every airplane launches at closed throttle on supported gear, stays parked for two seconds in calm and default gentle weather, restarts exactly and accepts an explicit airborne start. Maximum observed idle speed was 0.00224 m/s in gentle weather.
- `test_runway_cli.gd`: 10 checks; Quick Flight, explicit airborne/half-power selection, technical reference trace and invalid-option rejection.
- `test_start_choice.gd`: 36 checks; `test_runway_start.gd`: 18; `test_runway_checkpoint_metadata.gd`: 14; `test_prop_strike.gd`: 37; `test_ground_stiction.gd`: 25.
- Existing Home, language, weather, turbulence, pause lighting, flight-log UI and Workshop integration tests passed. Launch-caption layout passed 44 checks. Extra installation and airborne handling passed 17 and 12 checks respectively.
- `test_extra_runway.gd`: 16 checks; six seconds parked, followed by an uninterrupted three-second takeoff at both 240 and 480 Hz, with no crash or propeller strike. The 480 Hz run lifted off at 1.596 s and finished 5.04 m above its starting height. These are scripted software observations, not measured takeoff performance.
- Resource import and changed-script parsing passed. The Extra physics JSON, generated derivation and Workshop descriptor also reproduced in a fresh sparse clone with the four changed source/output files overlaid.

The native [Spanish Extra Home capture](captures/runway-home-extra-es.png), with [manifest](captures/runway-home-extra-es.json), was visually inspected at 1280×720 on the RTX 3090 Compatibility renderer: **Inicio: pista** is visible and **VOLAR** remains available.

The Extra now authors the shared estimated 1.25 breakaway factor through its [generator](../../../../research/extra-300/ex05/derive_physics.py); its Workshop descriptor was regenerated. The global descriptor check also reports a pre-existing stale P-51 descriptor (its recorded hash matches neither HEAD nor current source bytes); that unrelated descriptor was preserved. Physical ground handling remains experimental. The glow-engine variants retain their explicit warm-engine starter procedure. These checks establish software startup behavior, not measured flight realism or a new packaged release.
