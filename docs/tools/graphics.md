# Graphics and rendering tools

Tools to capture, compare and measure what the renderer draws. Each entry: purpose · when · command · result · gotchas. Shared runner, suite and flags: [shared](shared.md). [Back to the index](README.md).

Captures on the dev VM and CI use Xvfb with Mesa llvmpipe (software OpenGL, `gl_compatibility`). They prove determinism and image contracts, not target-GPU appearance or performance. Headless runs render nothing.

## Visual capture suite

- **Purpose:** render the reference views, field cases, UI screens and every area checker; check images, readability and a trace.
- **When:** before committing a change under `app/render/`, shaders, landscape, scenery or UI layout; CI runs it as "Godot visual captures".
- **Command:** `app/capture.sh`
- **Result:** `app/captures/run-manifest.json` exists only when every capture, image check and trace passed. Any failure exits nonzero and prints the failing step; per-area output is under `app/captures/<area>/`.
- **Gotchas:**
  - It runs everything (more than 25 steps) and cannot select one case; for a focused check run the [area checker](#area-capture-checkers) or a [single capture](#single-capture).
  - It holds a lock on `app/captures/`; a second run exits with "another capture run owns …".
  - It sets `OPENRC_SCENERY=off` and `LP_NUM_THREADS=1` so captures repeat byte for byte.
  - Shaders must not read `TIME`; animation uses the `sim_clock` global uniform (`app/test.sh` enforces this).

## Single capture

- **Purpose:** render one view to PNG with a fixed simulation time.
- **When:** to see a change, or to make a before/after pair.
- **Command:**
  ```sh
  OPENRC_SCENERY=off OPENRC_SCENERY_BIRDS=off OPENRC_ENGINE_SHADOWS=off LP_NUM_THREADS=1 \
  xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy \
    -- --capture --t=1.5 --out="$PWD/tmp/view.png" [view flags]
  ```
  The environment prefix matches `app/capture.sh` so repeats are byte-identical. View flags:
  - ground, grass, field surfaces: `--look_az=0 --look_el=-15 --hide_airplane` (or `--look_el=0` for the horizon);
  - airplane: `--inspect`; the deflected surfaces add `--roll=1 --pitch=1 --yaw=1`;
  - sun and lighting: `--look_az=225 --look_el=25`; top view: `--look_az=0 --look_el=-90 --look_alt=30`;
  - `--scripted` flies the fixed circle; `--autozoom=0` keeps the follow camera at its default distance (mostly sky).
  Every reference case is a `shot` line in [`app/capture.sh`](../../app/capture.sh).
- **Result:** the PNG plus a sibling `.json` manifest (renderer, adapter, identities) and a log line `saved … (error 0) draw_calls=…`.
- **Gotchas:**
  - Use an absolute `--out`. Unknown flags are ignored silently.
  - A fresh checkout or app copy must be imported first (see the [index rules](README.md#rules-for-every-tool)).
  - For a before/after pair, copy `app/` to `tmp/cand/app/` and symlink the repository's `assets/` to `tmp/cand/assets` (the app reads `res://../assets/`); otherwise the copy exits 30 with "authoring source is missing". Run the engine and visual venv from the repository root.

## Compare captures

- **Purpose:** decide whether two capture sets differ.
- **Command:** `"$(app/tests/visual-env.sh)" app/tests/compare_captures.py compare <reference-dir> <test-dir> [--max-bad 50] [--flip 0.1]`. Airplane readability: `… compare_captures.py readability <captures-dir> --require "capture-land-30m.png:-0.40:0.15:30:25"`.
- **Result:** same renderer: SHA-256 must match exactly. Different renderer: fails when more than `--max-bad` pixels exceed the FLIP threshold.
- **Gotchas:** byte equality holds only for one Mesa build. Each PNG needs its manifest `.json`. On the same renderer it reports only `sha256 equal` or `differs` per file; no repository tool localizes a difference. To show where an image changed, diff the two PNGs with NumPy and Pillow from the visual venv and inspect the result.

## Area capture checkers

- **Purpose:** focused, repeatable A/B and contract checks per rendering area.
- **When:** after changing that area. Each is also a step of `app/capture.sh`.
- **Command:** `"$(app/tests/visual-env.sh)" tools/<area>/check_<x>.py --app app --godot "$(app/get-godot.sh)" --out tmp/<new-dir>`. The visual venv (`app/tests/visual-env.sh`) installs pinned CPython 3.12 packages on first use.
- **Result:** exit 0 and a `summary.json` in `--out`; exit 1 names the failing image or check.
- **Gotchas:** most need Xvfb (they start it) and a new `--out`. The area READMEs own options and limits; many show PowerShell commands with the Windows engine, so substitute `"$(app/get-godot.sh)"`.

| Area | Checker run by `app/capture.sh` | Contract |
| --- | --- | --- |
| Grass placement, seams | `tools/grass/check_grass.py`, `check_grass_seam.py` | [tools/grass](../../tools/grass/README.md) |
| Ground surfaces, stripes, windsock | `tools/ground/check_surfaces.py`, `check_stripes.py`, `check_windsock.py` | [tools/ground](../../tools/ground/README.md) |
| Horizon | `tools/terrain/check_horizon.py` | [tools/terrain](../../tools/terrain/README.md) |
| Sky, clouds | `tools/atmosphere/check_phase6.py`, `check_cloud_probe.py` | [tools/atmosphere](../../tools/atmosphere/README.md) |
| Trees, tree wind | `tools/trees/check_review.py`, `check_wind.py` | [tools/trees](../../tools/trees/README.md) |
| Treeline readability | `app/tests/treeline_readability.py capture` | — |
| Visual-quality cases | `app/tests/visual_quality_cases.py` | [VQ guide](../VISUAL-QUALITY-PLAN.md) |
| Landscape lighting and glare | `tools/landscape/verify_*.py` (not in `capture.sh`) | [tools/landscape](../../tools/landscape/README.md) |
| Projected shadows | `tools/shadows/vq04a_verify.py` (not in `capture.sh`) | [tools/shadows](../../tools/shadows/README.md) |
| Sky, stars, time progression | `tools/world/parity.sh` (not in `capture.sh`) | [tools/world](../../tools/world/README.md) |
| Scenery placement and capture | `tools/scenery/scenario.sh` | [tools/scenery](../../tools/scenery/README.md) |
| Birds (position vs CPU reference, byte repeats) | `tools/scenery/check_birds.py` (not in `capture.sh`) | [tools/scenery](../../tools/scenery/README.md) |
| Engine smoke | standalone project `tools/smoke/` | [tools/smoke](../../tools/smoke/README.md) |
| Audio generation and packs | — | [tools/audio](../../tools/audio/README.md) |
| Gallery and README media | `tools/readme/` | [media workflow](../media/README.md) |
| Propeller blur | `res://tests/capture_propeller_blur.gd` | [VQ-05 contract](../research/visual-quality-implementation/VQ-05/README.md) |
| Trailer, night lighting, transmitter overlays | `tools/trailer/`, `tools/night-lighting/build.py --check`, `tools/ui/build_*_overlay.py` | [trailer plan](../plans/cinematic-trailer.md); others have no guide |

Layout data generators (`tools/{grass,trees,scenery,terrain,world}/…py --check`) run inside `app/test.sh`; regenerate through them, never by hand.

## Landscape checks

- **Command:** headless: `python3 tools/godot/run_checked.py --timeout 300 -- "$(app/get-godot.sh)" --headless --path app --script res://tests/test_landscapes.gd`. Rendered: omit `--headless`, run under `xvfb-run -a`, and add `-- --capture-landscapes=<absolute-dir>`; inspect both Home and flight images.
- **Result:** test output `N checks, 0 failed`. [Authoring and limits](../LANDSCAPES.md).

## Frame diagnosis

- **Purpose:** CPU/GPU frame timings, memory context, worst frames and budget bursts.
- **When:** performance questions on a machine with a real display and GPU.
- **Command:** add `--frametimes=<new.json> --frame-diagnostics` after the engine's `--`, then `python3 research/performance/frame_diagnose.py --report <json> --log <engine.log> --out <new-diagnosis.json>`.
- **Result:** `openrc-frame-diagnosis` JSON. Headless runs report "no viewport rendering timings".
- **Gotchas:** llvmpipe timings do not qualify any GPU. [Options and limits](../../research/performance/README.md#cpu-gpu-and-memory-diagnosis). Process RAM and disk: [tools/godot](../../tools/godot/README.md#process-ram-io-and-storage-pt1h-r4).

For OFF/Classic/Festival aircraft-lighting comparisons, the existing [flight harness's real-time mode](../../tools/trailer/README.md#real-time-lighting-measurements) supplies bounded controls and profile identities to this collector. Its Movie Maker mode remains a separate visual-evidence route.

## Experimental High profile (Forward+)

- **Command:** `python3 tools/graphics/launch.py --profile high [--dry-run]`
- **Result:** launches the app with the Forward+ trial; probes write `stage-N.json` receipts. [Scope, launcher and native probes](../../tools/graphics/README.md).
- **Gotchas:** needs a native GPU renderer; unverified on the dev VM.

## Native performance experiments

[Session performance tools](../../research/performance/README.md) and the research-only native candidates are listed in [TOOLS → Native performance experiments](../TOOLS.md#native-performance-experiments).
