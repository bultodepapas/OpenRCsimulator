# Presentation media provenance

Status: refreshed 2026-10-13 from source commit `bc48fdd`. The five aircraft stills and animated tour use a separate studio camera with a neutral three-light setup and dark background. The tour changes the camera angle; it does not represent flown maneuvers. Aircraft geometry, materials and controls are unchanged.

`flight.png`, used by the root README, is the real application at a fixed 1.5 seconds of trimmed Stik flight, using the close-up camera and production field. Its capture sidecar is `flight.json`.

`manifest.json` records model bounds, catalog names/status, engine/renderer, animation dimensions and SHA-256 hashes. The GIF contains 120 frames at 640×360, lasts 13.2 seconds and stays below 2 MB. Its 128-color frames use no dithering; the source PNGs are retained untouched by the packager. Five static 960×540 views provide an alternative to the animation. No external stock imagery or generated airplane artwork is used.

## Aircraft stills

| Aircraft | Studio view |
| --- | --- |
| Jensen Das Ugly Stik 60 | [View](ugly-stik.png) |
| Great Planes Extra 300S .60 | [View](extra-300s.png) |
| P-51D Mustang 1/4 | [View](p51d-mustang.png) |
| Ventage Jet | [View](avanti-s.png) |
| Turbo Lumber Evolution | [View](turbo-lumber-evolution.png) |

## Reproduce

From the repository root on Linux with Xvfb and Mesa:

```sh
OPENRC_DOCS_COMMIT="$(git rev-parse HEAD)" LP_NUM_THREADS=1 \
  xvfb-run -a "$(app/get-godot.sh)" --path app \
  --rendering-driver opengl3 --audio-driver Dummy \
  --script "$PWD/tools/readme/capture_aircraft.gd" \
  -- --out-dir=/tmp/openrc-readme-render

LP_NUM_THREADS=1 "$(app/tests/visual-env.sh)" app/tests/capture_runner.py \
  --out /tmp/openrc-readme-render/flight.png --kind flight --scene field --timeout 60 -- \
  xvfb-run -a "$(app/get-godot.sh)" --path app \
  --rendering-driver opengl3 --audio-driver Dummy -- \
  --capture --t=1.5 --inspect --out=/tmp/openrc-readme-render/flight.png

"$(app/tests/visual-env.sh)" tools/readme/package_media.py \
  /tmp/openrc-readme-render docs/media
```

The packager uses the existing pinned Pillow dependency. Animation frame PNGs remain in the temporary output directory; only the GIF, five stills, flight screenshot and provenance are committed. Refresh this note's source commit when recapturing.

The current capture review inspected all five aircraft and decoded the 120-frame animation, including the Ventage Jet name and the experimental Turbo Lumber Evolution. Seven media hashes are recorded in the manifest. Native Windows Godot 4.7.2 with Compatibility/OpenGL on an NVIDIA RTX 3090 supplied these captures; this presentation makes no hardware-performance claim. The Linux commands above reproduce the same capture workflow.
