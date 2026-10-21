# VQ-01c startup attribution and loading profiles — 2026-10-21

These are bounded source/editor observations for startup focus and first-load attribution. They do not qualify the application, establish physical performance, or select a production change. The package retains startup runs 01–03 and loading profiles 03–05 only.

## Findings

Startup 01 recorded window focus entry and later unpaused samples; no application-focus transition was observed. Its exact observer source was not retained separately. The retained v2 observer adds an `AppRoot` lookup fallback for pause-menu state. Because the v1 source is absent, its focus-tracking capability cannot be established from source; the lack of events in run 01 means none were observed, not that tracking was unsupported. Startup 02 and 03 used the retained v2 observer.

In startup 02, `application_focus_out` arrived at 12.066897 s while the observer still reported `focused=true`. `paused_changed(true)` followed 304 µs later through `simulation._notification` at line 175; `window_focus_exited` followed 19.282 ms after the app event, with the menu hold set. Focus returned later, but the menu hold and pause remained. This records an actual focus transition after a briefly stale focus value; it does not support adding an immediate focus check as a fix.

In startup 03, application focus-out arrived at tick 0 while `focused=false`; the same notification paused the simulation 169 µs later. Window focus exit followed 9.894 ms later, and the menu hold remained set. Together these runs support retaining safe pause-on-focus-loss behavior and classifying these paused starts as observed focus-loss cases. They do not prove a source defect or identify whether the application or window notification should own the policy. Startup 01 is not a matched control for pause-menu state because its observer version lacked the `AppRoot` pause-menu lookup.

Each loading profile contains two Home→Fly cycles in one process; all reported first draws were unpaused at tick 12. Each was a fresh app process, but OS, import, and shader cache state was uncontrolled. Profile 04 measured the first Home `world.build` at 2,230.528 ms and the first `main._ready` at 1,544.750 ms. Its cold `app_root._create_flight` span was 1,596.654 ms and its warm span 0.785 ms. Profile 05 split that span: cold `flight_scene.load` was 1,627.941 ms versus 0.068 ms for instantiation; warm load was 0.763 ms versus 0.092 ms for instantiation. This attributes the sampled synchronous scene-creation cost to loading. It does not establish a benefit from asynchronous loading or justify adoption.

Home first-draw-from-source-load was 5.084 s in profile 04 and 5.099 s in profile 05. These are single-process observations, not a matched performance comparison; no Home-usability or loading target is qualified. Profile 03 is the earlier profile. The first/broad and deep generator sources are retained. Its report points to `profile-final`, and that copy's manifest and patch are retained as `sources/profile-final-manifest.json` and `sources/profile-final-loading-profile.patch`. The manifest records the source hashes but not the generator filename; its instrumented `main.gd`, helper, and probe hashes match the linked/deep provenance entries.

## Setup failures retained separately

Loading-profile 01 and 02 exited with code 1 and produced no timing report. Profile 01 could not fly because the scratch copy lacked sibling authoring inputs, including `assets/aircraft/model-bindings.json` and the Stik geometry source. Profile 02 stopped at the intentional SHA-256 guard for `render/aircraft_customization.gd`. These are setup/provenance failures, not timing samples; the guard was not changed, and subsequent profiles excluded that protected file. Their checked reports and engine logs are in `checks/setup-failures/`.

The initial headless observer `--check-only` also failed during setup because the native ground-vehicle GDExtension library was unavailable. Its report and log are retained under `checks/setup-failures/observer-parse-initial/`; this is not evidence of a GDScript parse failure.

## Reproduction and limits

Each `checks/<run>/report.json` preserves the checked command argument array, working directory, exit code, and engine-log hash. Startup runs used the normal `--path .../control/app` main-scene route with the Stik, windowed 1280×720, Dummy audio, a 60 FPS cap, `--warmup=2`, and `--t=15`; they did not replace the main scene with `--script`. Loading runs used the retained profiled probe with `--cycles=2`; their exact paths and output arguments are in each report. The adjacent `engine.log` files retain checked output. The six retained main runs (startup 01–03 and loading-profile 03–05) exited 0; the earlier failed setup attempts remain separate and are not counted as samples.

The package does not include full app snapshots, imported resources, caches, or the Godot executable, so it is not a standalone replay bundle. Original scratch paths in the reports identify the measured copies. `sources/source-manifest.json.gz` records the base source snapshot at commit `210018c5367defe04677cdc937d45e869bafc4b9` with clean status; the source manifest SHA-256 before compression is `d39ff1b0214de691bdd08c9a71db7e480c7049ccc9a47c2bcd64199803ca9a6f`.

Key retained source hashes (SHA-256 of original bytes):

| Source | SHA-256 |
| --- | --- |
| Startup observer v2 | `c82240ca406a2d94a5626dcd65e0b71aeec99fcc54d61caaa1db6f45fa6cc8a5` |
| First/broad profile generator | `8a6e16cb00509f05eaffeabb20e136223781b5f55960b1d40f865520a546eda3` |
| Deep profile generator | `a4cdf0f33ed7e2e859213476380f621dda8d20612df8587184fcfb53a3c1a5bf` |
| Split-scene generator | `7f8b635ab5b13131ff25ec7fdbcf300a983b464e82020b72396fd05fe53e38be` |
| Profiled `main.gd` (profiles 03–05) | `0654dd0821db0da8f91117f8f66c8c31a612e6ceeedd3dc83ef5d3873f466f58` |
| Profiled loading probe | `f37654552dde4f7c7f7dfb29fe858dbb3e64ccd13d9c5fc0788681fd3008b4f1` |
| Profile 04 `app_root.gd` before split | `5ec67652b0837e87ca70efc99ad0a3961dfee1749821b50edc7c994861fab1cb` |
| Profile 05 `app_root.gd` after split | `c7a1f4313826f74c4958aa5b1a350db4e34a43eba4ad93a1c3aaf6b036836f6e` |

The profile-04 pre-split `app_root.gd` hash matches the deep provenance manifest's profiled-source hash. The split source, patch, and generator are retained. `evidence-manifest.json` gives original and stored hashes and sizes for every retained artifact; compressed JSON was decompressed and byte-compared with its source. Ten compressed files passed that round-trip check. No snapshots or caches were copied.

The separate scene-warmup diagnostic and its adoption decision are documented [here](../loading/scene-warmup-2026-10-21/README.md).
