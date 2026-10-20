# Presentation media provenance

Status: refreshed 2026-10-16 from source commit `404bb1bfd225f25159a03d60dfebdf89622936e6` with the capture-tool changes hashed in the manifest. The eight vehicle stills and animated tour use a separate studio camera with a neutral three-light setup and dark background. The tour changes the camera angle; it does not represent flown maneuvers. Production model builders supply the geometry and materials; no physics or control parameters are changed.

`flight.png`, used by the root README, is the real application at a fixed 1.5 seconds of trimmed Stik flight, using the close-up camera and production field. Its capture sidecar is `flight.json`.

`manifest.json` records model bounds, catalog names/status, engine/renderer, animation dimensions and SHA-256 hashes. The GIF contains 576 frames at 800×450, lasts 34.56 seconds and stays below 12 MB. Each vehicle gets a full 360° camera orbit in 72 frames at 60 ms per frame. Its 64-color frames use no dithering; the source PNGs are retained untouched by the packager. Eight static 960×540 views provide an alternative to the animation. No external stock imagery or generated airplane artwork is used.

## Aircraft stills

| Aircraft | Studio view |
| --- | --- |
| Ventage Jet | [View](avanti-s.png) |
| RC Helicopter Research Trainer | [View](helicopter.png) |
| Bisonte MT8 | [View](bisonte-mt8.png) |
| MONSTER CAR 2 | [View](monster-car-2.png) |
| Jensen Das Ugly Stik 60 | [View](ugly-stik.png) |
| Great Planes Extra 300S .60 | [View](extra-300s.png) |
| P-51D Mustang 1/4 | [View](p51d-mustang.png) |
| Turbo Lumber Evolution | [View](turbo-lumber-evolution.png) |

Website review captures live in [site/](site/): eight WEB-06 partner views (1280×900 and 390×900, English/Spanish, day/night) and two support-strip views. [The website guide](../../site/README.md#web-06--manufacturer-acknowledgments-2026-10-17) owns their verification record. They are separate from the simulator media manifest above.

The root README's Club field / Green paradise comparison uses unedited native flight overviews from [L21–L24](../research/landscape-upgrade/L21-24/README.md), captured on 2026-10-19. Their [capture/source hashes](../research/landscape-upgrade/L21-24/captures.json) and reproduction commands stay with that landscape evidence, separately from the studio manifest.

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

The packager uses the existing pinned Pillow dependency. Animation frame PNGs remain in the temporary output directory; only the GIF, eight stills, flight screenshot and provenance are committed. Refresh this note's source commit when recapturing.

The current capture review inspected four orbit angles for each of the eight vehicles and decoded all 576 GIF frames. The tour order is Ventage Jet, helicopter, Bisonte MT8, MONSTER CAR 2, Ugly Stik, Extra 300S, P-51D and Turbo Lumber Evolution. Ten media hashes and both capture-tool hashes are recorded in the manifest. Native Windows Godot 4.7.2 with Compatibility/OpenGL on an NVIDIA RTX 3090 supplied these captures; this presentation makes no hardware-performance claim. The Linux commands above reproduce the same capture workflow.

For a studio-only refresh, copy the existing `flight.png` and `flight.json` into the temporary capture directory before packaging. They retain their original capture provenance; the field screenshot was not recaptured in this refresh.
