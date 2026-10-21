# DT-11a: Windows release loading attribution

2026-10-21 · Source `2463af6547d44c3a7623d9d07790f12d39b4eb1c` · Godot 4.7.2 `ed1daf0bf` · Windows Compatibility.

**Outcome:** first-flight resource loading remains material in an actual release executable: **716.880 and 714.767 ms** in two active diagnostic runs, versus 1,615.810 ms in one source/editor run. Instantiation takes 40–43 µs in those release runs. This completes the package-attribution checkpoint after the [rejected warmup experiment](../scene-warmup-2026-10-21/README.md). It does not establish a new optimization or qualify the baseline.

The separate dependency diagnostic found distributed costs rather than one dominant optional dependency. Retain the runtime; investigate first-Home world/field construction next. No lazy-load rewrite, focus-policy change, physics change or renderer change is adopted.

## Package and collector

The frozen tree contains 3,840 tracked inputs from `app/`, `assets/aircraft/` and `tools/`. These runtime inputs match the preceding `210018c5` experiment. C: had about 435 MB free; D: had about 314 GB. Copies, imports and exports therefore used the isolated `D:/OpenRCsimulator-scratch/graphics-export-20261021-2463af65` directory. No existing cache, toolchain, worktree or user data was deleted or downloaded.

The installed official Windows release template and unchanged Windows preset were used, including `script_export_mode=2`, embedded PCK, normal export plugins and provenance guards. Mode 2 means compressed binary tokens; it is not a claim of ahead-of-time native compilation. [Godot 4.7 export preset modes](https://docs.godotengine.org/en/4.7/classes/class_editorexportpreset.html#enum-editorexportpreset-scriptexportmode).

The Windows-only export used the native editor's `--export-release Windows` with the build identity variables from `app/export.sh`. It did not run the destructive `dist/` replacement or Linux/macOS portions of that script. All five export invocations completed without engine errors or warnings. An unchanged application export is retained separately from the diagnostic executables.

The installed release executable does **not** expose `--script`, `--path` or `--main-pack`. Godot documents those as extended options, and unknown options can be silently ignored; an editor-hosted PCK run would answer a different runtime question. [Godot 4.7 command-line reference](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html).

The isolated collector therefore embeds a copy of the existing [loading probe](../../../../../../research/performance/loading_probe.gd) as `PackLoadingProbe`, a `SceneTree` subclass selected by `application/run/main_loop_type`. It retains the deferred `_run`, real Home Fly signal, bounded handoff/readiness checks, warm repeat and verified audio/settings cleanup. A custom main loop is an engine-supported entry point. [Godot 4.7 MainLoop](https://docs.godotengine.org/en/4.7/classes/class_mainloop.html).

An initial attempt with no main scene was rejected by the release template before the collector ran. The corrected diagnostic configuration uses an empty `PackageProbeHost` node as its main scene. It does not instantiate a second AppRoot. That failed invocation and its original configuration/hash are retained; it produced no timing sample.

Four artifacts are distinguished:

| Artifact | Changes from frozen runtime | Purpose |
| --- | --- | --- |
| `release` | None | Normal release entry point and trimmed-flight smoke |
| `collector` | Copied collector, empty host, diagnostic main-loop setting and build identity | Release-template Home/Fly collection without scene timers |
| `diagnostic` | Collector plus two synchronous timestamps around scene load/instantiate in AppRoot; bounded 16-entry metadata | Attribute first scene load without changing load order |
| `dependency` | Separate sequential direct-preload diagnostic described below | Locate incremental dependency costs; not an optimization candidate |

Every native loading report identifies its actual executable and records `editor_feature=false`, `debug_build=false`; the source comparison records both as true. Release runs launch normally from an empty working directory with no source-path override. The DLL beside each exported executable matches the Windows build receipt. [Artifact hashes](provenance/artifact-identities.json), [source verification](provenance/source-verification.json) and exact patches/sources preserve these distinctions.

## Measurements

Same host: Ryzen 9 5900X, RTX 3090, NVIDIA 617.42, 1280×720 viewport, Compatibility, VSync on, cap 60, Dummy audio. Native processes were serialized; no export, bulk copy or hash ran during their timing. Disk storage differs from the preceding C: study, so the source comparison also uses the isolated D: snapshot. OS/import/shader caches and background host activity remain uncontrolled. Fresh process does not mean cold caches.

| Run, in execution order | Home engine elapsed (s) | Home from resource load (s) | First Fly draw (s) | Warm Fly draw (s) | First scene load (ms) | First-draw state |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Collector 02 | 12.275 | 8.400 | 4.167 | 1.710 | Not observed | Active, tick 12 |
| Diagnostic 01 | 6.969 | 4.151 | 2.295 | 2.160 | 756.818 | Paused, tick 0; exclude from active comparisons |
| Collector 03 | 9.145 | 5.369 | 2.940 | 1.544 | Not observed | Active, tick 12 |
| Source 01 | 9.245 | 5.073 | 3.472 | 1.819 | 1,615.810 | Active, tick 12 |
| Diagnostic 02 | 6.492 | 3.911 | 2.162 | 1.440 | 716.880 | Active, tick 12 |
| Diagnostic 03 | 6.406 | 3.778 | 2.188 | 1.433 | 714.767 | Active, tick 12 |

The two active release diagnostics measure warm scene loads at 0.534/0.476 ms. All seven successful loading processes, including the separate dependency run, complete two cycles, release tracked audio and remove their isolated settings without an ObjectDB exit warning. Native first-flight node counts differ when Pause is open; some Home counts also differ. Zero reported orphan nodes and two cycles do not establish a leak-free lifecycle or soak.

The collector-only and timed runs are not a five-pair qualification campaign. Their substantial end-to-end variation prevents an observer-overhead or speedup claim. The source/release difference combines package representation, release-template behavior and run conditions; it cannot be assigned to token compression alone. The reported load span is synchronous resource work, not a GPU timer.

Home remains above the 5 s engine-elapsed goal in both active diagnostics, and first Fly remains above 2 s. The virtual desktop does not qualify the physical display, refresh, latency or minimum hardware. No pilot/readability or other-platform acceptance is implied.

## Dependency diagnostic and ROI decision

The live `main.gd` contains **66 literal preload paths**: 65 named constants plus the Workshop launch helper. In a separate release export, AppRoot loads each direct path in source order immediately before the first scene load. It records `ResourceLoader.has_cached` before each load and retains local resource references until the scene has loaded. Measurements are collected in memory and written after the cycles; this diagnostic adds no asynchronous request.

This intentionally changes dependency-loading context. Each duration includes transitive work not already cached; shared work is charged to its earliest loader. They are **not independent costs or additive potential savings**. The list totals 667.952 ms, followed by 192.730 ms residual scene loading. That separate 860.682 ms sequence must not be presented as a speedup against the unprimed 715–717 ms load.

| Largest incremental path | Time (ms) | Scope consequence |
| --- | ---: | --- |
| `render/crash/director.gd` | 101.322 | Normal crash presentation is configured before flight; deferring to impact risks a critical-event stall |
| `ai/companions/manager.gd` | 93.616 | Optional companions have a startup gate; a plausible small experiment, but not a demonstrated complete-path win |
| `workshop/launch.gd` | 92.397 | `from_args` runs during startup even without a variant; changing the boundary must preserve all argument validation |
| `economy/incident.gd` | 65.751 | Normal accident tracking begins during startup |
| `audio/flight_audio.gd` | 59.763 | Flight audio is prepared before use |
| `sim/recorder.gd` | 55.018 | Recording and technical routes require their own first-use and replay checks |
| `render/overlays/overlay_manager.gd` | 46.696 | Visible overlays and live toggles need parity and first-use checks |

[All paths, cache states and timings](runs/dependency-01.json) are retained. The two active diagnostics have combined Home-from-load plus first-Fly intervals of about 6.0–6.1 s. A roughly 94 ms optional load is about 1.5% of that interval as a screening estimate, before accounting for shared work or shifted cost. Neither a single lazy-load change nor a safe combined reduction meeting the >5% gate is established. Moving required loads into `_ready` would still charge them to first draw. Do not change startup just because a local resource timer can shrink.

## Verification and remaining failures

- Private import and release exports pass the checked runner; all source/package provenance guards remain enabled.
- The unchanged release executable records 721 trace rows spanning 720 ticks/3 s. `check_trimmed_flight.py --duration=3` passes: finite samples, 30 m altitude and 15 m/s level flight. This is software verification, not physical validation.
- That ordinary headless release smoke emits **four ObjectDB instances leaked at exit**. The runner's warning policy does not make that shutdown acceptable. It is retained as an unresolved normal-release teardown warning, separate from the loading collector's clean bounded cleanup; no root cause or repair is claimed.
- Final hashes show all 3,840 frozen production inputs unchanged. In the private snapshot only AppRoot and project configuration differ, with two added diagnostic files. Physics, aircraft definitions, generated assets and goldens are unchanged.

No full three-platform export pipeline, capture matrix, five-pair candidate acceptance, physical-display pacing campaign, 20-cycle growth test or soak was run. The one paused diagnostic is retained, not averaged into active measurements or forcibly resumed.

## Next bounded action

**DT-11a / UI / LU:** use this release collector to split initial Home construction into the existing field-builder callback (`World.build` already returns `field_build_ms`), surrounding world/environment work, scenery attachment and aircraft preview. Measure the package path, with one unchanged collector control and one diagnostic repeat; keep first draw separate from synchronous construction. Prior source evidence placed first Home `World.build` near 2.23 s, but that is only the reason to investigate the corresponding package stage.

Timebox this attribution to half an engineering day. Select one repeatable substage with plausible complete-path return; otherwise retain the baseline and move to the remaining native-pacing/visibility gates. A candidate still needs >5% complete affected Home/Fly improvement without moving the delay into another first-use event, unchanged validation/visual output where promised, five alternating fresh/warm pairs, and relevant lifecycle tests. Do not add another preload/cache framework or begin appearance tuning on this evidence.

## Reproduction and retained artifacts

[Manifest](evidence-manifest.json) records original/stored SHA-256 values. Large logs, source manifest and trace use deterministic gzip. Reports retain commands, working directories, timestamps, exit status, warnings and checked-log hashes, including the rejected no-main-scene setup. Binary artifacts remain in the isolated D: directory; their hashes are retained, not their hundreds of megabytes of data.

The `provenance/` recipes preserve this bounded experiment, not a general benchmark framework. Copy them into `<repo>/tmp/` in a checkout of the stated commit; they derive the repository path there and use the explicit D: snapshot path. Preparation refuses an existing snapshot and requires existing pinned tools/templates. Reconstruct the frozen inputs and private import cache before running the export recipe; run loading samples serially with `run_package_loading.py <collector|diagnostic|source|dependency> <fresh-number>`. The current collector preparation includes the empty host; `fix_collector_host.py` records the historical repair and must not be reapplied to that corrected preparation. The final project, probe and AppRoot variants are retained exactly; the initial collector patch alone predates the empty host. Production launch configuration is not changed.
