# M5-W03b — wind UI rendered capture review

**Status (2026-10-09):** Final rendered UI checks pass after the Home layout, HUD localization, and identifier-only warning cleanup. The `release/` capture set is authoritative; the initial failure and the earlier corrected `fixed/` set remain preserved as before/after evidence.

The final capture set uses source HEAD `6973e42` plus the shared, uncommitted wind implementation; pinned Godot 4.7.2; Xvfb; OpenGL Compatibility with Mesa llvmpipe; and dummy audio. Each capture used a fresh `XDG_DATA_HOME` and `XDG_CONFIG_HOME`. [capture.gd](../../../../research/wind/M5-W03b/capture.gd) writes and removes its isolated preference file; no player settings were read or changed. Each PNG has a JSON report with its hash, viewport, visible Control rectangles, layout findings, nonblank check, and ten source SHA-256 values. The nine release reports share one source map, matching the current worktree; see the [release source manifest](../../../../research/wind/M5-W03b/captures/release/source-manifest.json).

## Reproduce

From the repository root:

```sh
GODOT="$PWD/.tools/Godot_v4.7.2-stable_linux.x86_64"
CAPTURE="$PWD/research/wind/M5-W03b/capture.gd"
OUT="$PWD/research/wind/M5-W03b/captures/release"
capture() {
  local name="$1" scene="$2" lang="$3" preset="$4" size="$5"
  local width="${size%x*}" height="${size#*x}"
  local xdg="/tmp/openrc-m5-w03b-release-${name}"
  mkdir -p "$xdg/data" "$xdg/config"
  env XDG_DATA_HOME="$xdg/data" XDG_CONFIG_HOME="$xdg/config" LP_NUM_THREADS=1 \
    timeout 180 xvfb-run -a -s "-screen 0 ${size}x24" \
      "$GODOT" --path app --windowed --resolution "$size" --rendering-driver opengl3 --audio-driver Dummy \
      --script "$CAPTURE" -- --screen="$scene" --lang="$lang" --preset="$preset" \
        --width="$width" --height="$height" --out="$OUT/${name}.png"
}
capture home-en-1280x720 home en calm 1280x720
capture home-es-1280x720 home es calm 1280x720
capture modal-gusty-en-1024x720 modal en gusty 1024x720
capture modal-steady-es-1024x720 modal es steady 1024x720
capture modal-steady-en-1280x720 modal en steady 1280x720
capture modal-gusty-es-1280x720 modal es gusty 1280x720
capture modal-gusty-en-1920x1080 modal en gusty 1920x1080
capture flight-gusty-en-1280x720 flight en gusty 1280x720
capture flight-gusty-es-1280x720 flight es gusty 1280x720
```

Xvfb emits a V-Sync warning because llvmpipe cannot change V-Sync mode. Flight runs also print the existing Ugly Stik inertia data warning; all nine final capture processes exit successfully.

## Release results

| Capture | Layout result | Evidence |
| --- | --- | --- |
| Home, English, 1280×720 | 69 visible controls; zero zero-size, offscreen, or overlapping controls. Sidebar expands to 455 px from its nominal 440 px width, remaining within the viewport. | [PNG](../../../../research/wind/M5-W03b/captures/release/home-en-1280x720.png) · [manifest](../../../../research/wind/M5-W03b/captures/release/home-en-1280x720.json) |
| Home, Spanish, 1280×720 | 69 visible controls; zero zero-size, offscreen, or overlapping controls. Sidebar is 440×720; its content column is 360×660 with 36 px top and 24 px bottom inset. | [Initial failure](../../../../research/wind/M5-W03b/captures/home-es-1280x720.png) · [fixed PNG](../../../../research/wind/M5-W03b/captures/fixed/home-es-1280x720.png) · [release PNG](../../../../research/wind/M5-W03b/captures/release/home-es-1280x720.png) · [release manifest](../../../../research/wind/M5-W03b/captures/release/home-es-1280x720.json) |
| Weather modal, English Gusty, 1024×720 | 27 visible controls; zero layout findings | [PNG](../../../../research/wind/M5-W03b/captures/release/modal-gusty-en-1024x720.png) · [manifest](../../../../research/wind/M5-W03b/captures/release/modal-gusty-en-1024x720.json) |
| Weather modal, Spanish Steady breeze, 1024×720 | 27 visible controls; zero layout findings | [PNG](../../../../research/wind/M5-W03b/captures/release/modal-steady-es-1024x720.png) · [manifest](../../../../research/wind/M5-W03b/captures/release/modal-steady-es-1024x720.json) |
| Weather modal, English Steady breeze, 1280×720 | 27 visible controls; zero layout findings | [PNG](../../../../research/wind/M5-W03b/captures/release/modal-steady-en-1280x720.png) · [manifest](../../../../research/wind/M5-W03b/captures/release/modal-steady-en-1280x720.json) |
| Weather modal, Spanish Gusty, 1280×720 | 27 visible controls; zero layout findings | [PNG](../../../../research/wind/M5-W03b/captures/release/modal-gusty-es-1280x720.png) · [manifest](../../../../research/wind/M5-W03b/captures/release/modal-gusty-es-1280x720.json) |
| Weather modal, English Gusty, 1920×1080 | 27 visible controls; zero layout findings | [PNG](../../../../research/wind/M5-W03b/captures/release/modal-gusty-en-1920x1080.png) · [manifest](../../../../research/wind/M5-W03b/captures/release/modal-gusty-en-1920x1080.json) |
| Gusty flight HUD, English, 1280×720 | 3 visible controls; zero layout findings | [PNG](../../../../research/wind/M5-W03b/captures/release/flight-gusty-en-1280x720.png) · [manifest](../../../../research/wind/M5-W03b/captures/release/flight-gusty-en-1280x720.json) |
| Gusty flight HUD, Spanish, 1280×720 | 3 visible controls; zero layout findings | [PNG](../../../../research/wind/M5-W03b/captures/release/flight-gusty-es-1280x720.png) · [manifest](../../../../research/wind/M5-W03b/captures/release/flight-gusty-es-1280x720.json) |

All release PNGs decoded, matched their manifest SHA-256 values, and passed the nonblank check. The nine manifests share the same ten source hashes, which match the current worktree. The previous `fixed/` captures remain available as the pre-cleanup set. Flight renders have per-capture image hashes but are not pixel-identical between runs; their displayed HUD text and measured flight values are stable.

The gusty flight was frozen at 4.0 s (960 ticks). TAS was 14.035 m/s, horizontal ground speed was 19.830 m/s, and wind was 6.0 m/s from 270° with +1.5 m/s upward. The HUD displays 14.0 m/s airspeed and 19.8 m/s ground speed. The ground-speed and wind line is localized in Spanish.

## Initial Spanish Home finding

Before the Home adjustment, the Spanish sidebar measured 462×734 against its intended 440×720 bounds. The checker reported that offscreen panel and two collapsed spacer Controls; no overlaps. The [initial PNG](../../../../research/wind/M5-W03b/captures/home-es-1280x720.png) and [initial manifest](../../../../research/wind/M5-W03b/captures/home-es-1280x720.json) preserve that evidence. The final Spanish Home capture above confirms the corrected bounds.
