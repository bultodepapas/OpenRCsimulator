# Graphics and rendering tools

Tools to capture, compare and measure what the renderer draws. Each entry: purpose · when · command · result · gotchas. Shared runner, suite and flags: [shared](shared.md). [Back to the index](README.md).

The Linux CI capture workflow uses Xvfb with Mesa llvmpipe (software OpenGL, `gl_compatibility`). It checks image contracts, not target-GPU performance. Use the [debug bridge](../../tools/debug/README.md#quick-start) for native 1080p review and report actual viewport dimensions; follow the [resolution policy](../../AGENTS.md#display-resolution-priorities). Headless runs render nothing.

## Visual capture suite

- **Purpose:** render the reference views, field cases, UI screens and registered area checks; check images, readability and a trace. The script owns suite membership; additional tools appear below.
- **When:** CI's complete visual gate, or local verification of a broad visual change or release candidate. During development use the affected [area checker](#area-capture-checkers) or [single capture](#single-capture), and inspect affected 1080p rendering when readability or presentation changes.
- **Command:** `app/capture.sh`
- **Result:** `app/captures/run-manifest.json` exists only when every capture, image check and trace passed. Any failure exits nonzero and prints the failing step; per-area output is under `app/captures/<area>/`.
- **Gotchas:**
  - For one case use an [area checker](#area-capture-checkers) or a [single capture](#single-capture). Experimental checker groups are described below.
  - It holds a lock on `app/captures/`; a second run exits with "another capture run owns …".
  - It sets `OPENRC_SCENERY=off` and `LP_NUM_THREADS=1` so captures repeat byte for byte.
  - Shaders must not read `TIME`; animation uses the `sim_clock` global uniform (`app/test.sh` enforces this).

The full suite also writes `app/captures/timings.tsv` with phase durations and pass/failure. These are wall-clock diagnostics, not a GPU benchmark. For a partial local investigation, use `bash app/capture.sh --group GROUP --out /absolute/new/output`; groups are `core`, `ui`, `quality`, `terrain-atmosphere`, `ground`, `vegetation` and `scenario`. Output must be fresh and outside `app/`; grouped runs isolate settings and preserve the checkout capture lock. CI's required visual gate still runs the full suite. Its `captures-app` artifact retains raw evidence; after a successful capture, verified identical L9c unfiltered-project trees may be stored once with a reconstruction helper. Distinct mutations, import logs, renders and summaries remain; [CI artifact reconstruction](../../tools/ci/README.md#capture-artifact-reconstruction) owns that contract. Follow the shared [verification scope](shared.md#verification-scope) for when to repeat local checks.

For an experimental coordinated run, add `--run-id UNIQUE_RUN_ID` to every group invocation. Use one fresh ID for all seven groups (1–128 ASCII letters, digits, dots, underscores or hyphens, starting with a letter or digit). Each successful group writes `capture-group-receipt.json`; a failed or interrupted group cannot finish its receipt. Use independent checkouts with identical source and inputs for concurrent jobs, and only one rendered process per host. Output inside a checkout must be Git-ignored. Keep source and imported configuration unchanged throughout the run; a changed commit or input requires a new run.

After all seven groups finish, supply the expected commit and run ID independently to the reducer, using the producing engine and visual interpreter:

```sh
python3 tools/ci/capture_groups.py reduce --repo "$PWD" \
  --run-id UNIQUE_RUN_ID --expect-commit FULL_COMMIT_SHA \
  --godot /absolute/pinned/godot --visual-python /absolute/visual-venv/bin/python \
  --out /absolute/new/experimental-result.json \
  --parts /absolute/core /absolute/ui /absolute/quality /absolute/terrain-atmosphere \
          /absolute/ground /absolute/vegetation /absolute/scenario
```

The reducer checks all seven distinct groups, ordered checker milestones, expected image IDs, output hashes and matching source/engine/configuration. It refuses stale or changed outputs and existing result files. Its result is explicitly `groups-recorded` with `production_qualified: false`; it never writes the legacy `run-manifest.json` or substitutes for CI acceptance. Receipt mode rejects unsupported rendering environment overrides.

**Hosted shadow comparison (PT1-CI-03).** Only a manual workflow dispatch with the `visual_shadow` boolean enabled runs the seven groups on separate runners (`visual-groups`) and compares them with the unchanged full job (`visual-shadow`). Each side publishes `capture_groups.py inventory`: a SHA-256 for every output, plus a hash of text outputs with the output root path normalized. `compare` requires seven passed receipts for this run and clean commit, with the same source inputs, engine, visual interpreter and configuration as the full run. It checks that each inventory matches its receipt and that each output belongs to exactly one group. It then classifies outputs as identical, normalized or different. The declared volatility model in `capture_groups.py` skips import caches/profiles (`.godot`, `.capture-profile`), the regenerable L9c mutation copies and dated `scenario/history`. It strips checked-runner random directory suffixes and drops run-clock/ID/log-digest JSON keys (`created_utc`, `capture_id`, `elapsed_seconds`, `log_sha256`, …) before the normalized hash. Each report lists that model. Extend it only after examining a reported difference. Image or data differences, missing or extra outputs and overlaps make the run `NOT equivalent`; differing logs/HTML are listed as diagnostics only. The step summary and `visual-shadow-comparison` artifact record counts, runner CPU models and capture-phase seconds. These jobs are non-blocking evidence, `production_qualified: false`; the full visual job remains the gate. The opt-in defaults to false: prior hosted comparisons disagreed, so extra runner work is deliberate while qualification remains open. History-dependent behavior and excluded mutation-project trees require separate qualification before promotion.

The `quality` group also renders the two lighting pixel suites (`test_lighting_skin_patterns.gd`, `test_lighting_segment_filter.gd`) at 1920×1080 through the checked runner, requiring their `N checks, 0 failed` completion lines. Both suites write required structured metric records under `lighting-pixels/*-metrics.json`; the shell and group inventory reject missing, incomplete, malformed or non-finite values. Their 14 segment and 15 skin measurements include full-precision decimal values and matching little-endian float64 hex; the validator rejects disagreement between them. They are compared as data with zero absolute/relative drift tolerance until matched evidence justifies a wider boundary; run-clock/path/log normalization does not apply inside these records. This compares the named error maxima, color weights and distances, not every unsaved pixel: the near-color assertions still report threshold outcomes. Incidental log wording and timing remain informational. Their headless unit invocations are declared skips, reported as JUnit `<skipped>`. Xvfb/llvmpipe passes do not qualify native GPU/driver output.

Complete assertion inventory and performance qualification remain pending, as does rendered group equivalence until hosted comparisons pass. Fixtures establish scheduling and rejection behavior. Receipts bind the Python executable and requirements source, but do not independently inventory installed Python packages or qualify the GPU/driver. Fresh scenario groups have no prior-run comparison history; the default full suite retains that history behavior. Historical 720p fixtures do not establish 1080p product qualification.

## Single capture

- **Purpose:** render one view to PNG with a fixed simulation time.
- **When:** to see a change, or to make a before/after pair.
- **Command:** reproduce the suite's 720p reference fixture (not 1080p acceptance):
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
- **Gotchas:** retain the same engine, renderer, driver and capture configuration for byte comparisons. Each PNG needs its manifest `.json`. A matching image does not establish legibility; inspect the actual captures.

## Area capture checkers

- **Purpose:** focused, repeatable A/B and contract checks per rendering area.
- **When:** after changing that area. Check `app/capture.sh` for inclusion; standalone tools are not implied by a passing full capture suite.
- **Command:** `"$(app/tests/visual-env.sh)" tools/<area>/check_<x>.py --app app --godot "$(app/get-godot.sh)" --out tmp/<new-dir>`. The visual venv (`app/tests/visual-env.sh`) installs pinned CPython 3.12 packages on first use.
- **Result:** exit 0 and a `summary.json` in `--out`; exit 1 names the failing image or check.
- **Gotchas:** most need Xvfb (they start it) and a new `--out`. The area READMEs own options and limits; many show PowerShell commands with the Windows engine, so substitute `"$(app/get-godot.sh)"`.

| Area | Entry point | Contract |
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

## High profile (Forward+)

- **Command:** `python3 tools/graphics/launch.py --profile high [--dry-run]`
- **Result:** starts the selected graphics mode. The separate verification probes write receipts; the launcher itself is not a performance test. [Modes, startup and probes](../../tools/graphics/README.md).
- **Gotchas:** use a compatible native renderer and the actual target resolution. Available settings do not establish hardware qualification.

The current [Windows NVIDIA application](../../tools/graphics/native/README.md#play-with-dlss-dlaa-and-reflex) has a separate build/package workflow for DLSS, DLAA and Reflex; follow that guide rather than the historical candidate preparation commands.

## Native performance experiments

[Session performance tools](../../research/performance/README.md) own CPU/GPU measurement. [Backend tools and older experiments](../TOOLS.md#native-performance-experiments) distinguish current native installation from isolated research candidates.
