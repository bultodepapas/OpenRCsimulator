# Presentation media provenance

Status: retained render evidence from source commit `a6a3abf`; these images describe that snapshot, not current flight parameters. The four aircraft stills and animated tour use a separate studio camera with a neutral three-light setup and dark background. The tour changes the camera angle; it does not represent flown maneuvers. Aircraft geometry, materials and controls are unchanged.

`flight.png`, used by the root README, is the real application at a fixed 1.5 seconds of trimmed Stik flight, using the close-up camera and production field. Its capture sidecar is `flight.json`.

`manifest.json` records model bounds, catalog status, engine/renderer, animation dimensions and SHA-256 hashes. The GIF contains 96 frames at 640×360, lasts 10.56 seconds and stays below 2 MB. Four static 960×540 views provide an alternative to the animation. No external stock imagery or generated airplane artwork is used.

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

The packager uses the existing pinned Pillow dependency. Animation frame PNGs remain in the temporary output directory; only the GIF, four stills, flight screenshot and provenance are committed. Refresh this note's source commit when recapturing.

The original capture review inspected all four aircraft and decoded the 96-frame animation. The six media hashes are recorded in the manifest. The stills and tour retain the earlier catalog presentation; the current README uses the flight image. llvmpipe supplied the captures, which make no hardware-performance claim.
