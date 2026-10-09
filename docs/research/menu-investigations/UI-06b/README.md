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
