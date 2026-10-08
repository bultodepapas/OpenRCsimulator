# Tooling index

**Updated:** 2026-10-08

**Status:** Practical entrypoints for the current app, evidence reducers, visual tools and research experiments. Code defines behavior and accepted inputs; the owning plan records status, and each tool README describes its usage contract.

Run commands from the repository root unless a command says otherwise. `$(app/get-godot.sh)` resolves the pinned Godot 4.7.2 binary and downloads it to ignored `.tools/` when needed. Visual render checks use Xvfb and the pinned Python environment returned by `app/tests/visual-env.sh`. Generated captures and local source references are not committed.

## App and release commands

| Purpose | Entrypoint | What it proves or produces |
| --- | --- | --- |
| Get the engine | `app/get-godot.sh` | Downloads the pinned engine and verifies its SHA-512. |
| Run checks | `app/test.sh` | Headless parse, unit, app-route, model-contract, trace and frame-rate checks. It checks every GDScript in `app/`; a parse error fails the run. |
| Offline tool regressions | `research/test-tools.sh` | Bounded reducer/importer/audit harness tests used by CI; synthetic fixtures do not close physical gates. |
| Capture app visuals | `app/capture.sh` | Xvfb render set, image checks, traces, scenario comparisons and a complete run manifest under ignored `app/captures/`. |
| Preview optional scenery | `app/run-landscape.sh` | Opens the app with `OPENRC_SCENERY=on`; scenery remains opt-in in the regular app. |
| Build release packages | `app/export.sh` | Windows, Linux and macOS builds, smoke checks, archives and SHA256SUMS in `dist/`; export templates are downloaded and verified as needed. |
| Run the app | `$(app/get-godot.sh) --path app` | Opens the Godot app. See [AGENTS.md](../AGENTS.md) for controls and aircraft IDs. |

`app/capture.sh` composes focused checks from `tools/` and `app/tests/`. Use the focused command below when iterating on one visual feature; the complete capture run is broader and takes longer. `app/test.sh` is the normal software verification suite, not evidence that a model matches a real aircraft.

## Release sequence

1. Finish a small, committed change and review the selected diff. Retain per-step proof in `docs/research/`; stage explicit paths in the shared checkout.
2. Run app, offline-tool, schema/generator and capture checks. Build with `app/export.sh` in an isolated checkout with enough output and temporary space; inspect failures before tagging.
3. Add `docs/releases/<tag>.md`. The tag's numeric version must match `app/project.godot`; `git describe` supplies the complete package/build identity.
4. Push the reviewed commit and `v*` tag to the repository. CI repeats checks, exports all platforms and publishes a prerelease with checksums. Tags without their own notes fail before packaging.
5. Check the tagged workflow and download/verify its three ZIPs and `SHA256SUMS`. Keep native OS, radio, GPU and pilot acceptance separate from this software release proof.

## Radio diagnostics

| Step | Command | Inputs and limits |
| --- | --- | --- |
| [F1 input report](research/radio-input/F1/README.md) | `$(app/get-godot.sh) --path app -- --input-report=input-report.json --t=20` | Observe a connected radio and move every control. Produces `openrc-input-report v1`; the duration defaults to 10 s and is capped at 3600 s. It records Godot callback times, not hardware report intervals, RF state or stick-to-screen latency. An empty device list is a successful diagnostic. |
| [F6a live marker](research/radio-input/F6a/README.md) | `$(app/get-godot.sh) --path app -- --latency-patch --latency-axis=0 --latency-threshold=0` | Starts a live flight and marks when the selected raw Godot axis crosses the threshold. Axis is 0–9; threshold must be strictly between −1 and +1 in raw-axis units. Film the stick reference and marker together using the F6a protocol. The marker is not a software latency estimate and does not include servo or aircraft response. |
| [F6b video reducer](../research/radio-latency/README.md) | `python3 research/radio-latency/reduce.py research/radio-latency/example.synthetic.json research/radio-latency/example.synthetic.csv` | Requires a campaign manifest and annotation CSV. Real campaigns need original-clip hashes, verified acquisition cadence and retained frame annotations. It does not decode video or authenticate annotations; synthetic examples are not physical measurements. |

F1/F6 software checks establish collector and route behavior. Physical radio, camera and display observations remain the independent evidence for those steps.

## Aircraft measurement reducers

These offline Python tools reduce recorded observations; they do not write aircraft physics data. Their checked-in examples are synthetic fixtures. For physical work, follow the linked procedure, retain raw records, replace every synthetic input and preserve the report beside its source files.

| Step and tool | Entry command | Required evidence and scope |
| --- | --- | --- |
| [VAL-5a weighing](../research/validation/weighing/README.md) | `python3 research/validation/weighing/reduce.py research/validation/weighing/example.synthetic.json --output /tmp/weighing-result.json` | Python 3.10+, standard library. JSON needs simultaneous tare-corrected scale readings, support coordinates, a level setup and uncertainty/provenance. Reports mass and horizontal CG only; it cannot establish vertical CG or flight behavior. |
| [VAL-6a inertia](../research/validation/inertia/README.md) | `python3 research/validation/inertia/reduce.py research/validation/inertia/synthetic.json` | Python 3 standard library. JSON records bifilar/compound loaded and tare swings, axis geometry, cycles and standard uncertainties. A synthetic plank check verifies the algebra; physical rig alignment, damping and aircraft measurements remain open. |
| [VAL-7a static propeller](../research/validation/static-prop/README.md) | `python3 research/validation/static-prop/reduce.py research/validation/static-prop/example.synthetic.json` | Python 3 standard library. JSON requires matched static thrust, RPM, diameter and density; torque is optional. Without measured torque it reports no shaft power, Cp or figure of merit. It does not fit throttle lag. |
| [VAL-7b/c RPM step](../research/validation/rpm-step/README.md) | `python3 research/validation/rpm-step/reduce.py research/validation/rpm-step/example.synthetic.json` | Python 3 standard library. JSON contains command time, steady endpoint RPM and the ordered transient series. Lag/delay are two-crossing diagnostics; acquisition, filtering and endpoint stability must be established separately. Uncertainty is opt-in and can be withheld when crossing/order margins are unresolved. |
| [VAL-8a ground video](../research/validation/ground-video/README.md) | `python3 research/validation/ground-video/reduce.py research/validation/ground-video/example.synthetic.json research/validation/ground-video/example.synthetic.csv --output /tmp/ground-video.json` | Python 3.10+, standard library. Campaign JSON plus event CSV carry original frames, surveyed along-runway positions, cadence and uncertainties. A real campaign declaring a clip hash must pass the original clip with `--video /path/to/clip`. The reducer does not decode video, survey perspective or infer instantaneous airspeed/liftoff speed. |
| [VAL-8b roll video](../research/validation/roll-video/README.md) | `python3 research/validation/roll-video/reduce.py research/validation/roll-video/example.synthetic.json research/validation/roll-video/example.synthetic.csv` | Python 3.10+, standard library. Campaign plus CSV annotate repeated physical roll phases and signed complete-turn counts; a real hashed clip is supplied with `--video /path/to/clip`. Reports cycle-average completed-roll rate, not instantaneous body-axis rate, roll-mode damping or control derivatives. |

Each reducer README lists its `test_*.py` command and measurement contract. Those tests prove parsing and reduction behavior; a passing test does not validate a scale, swing rig, engine, propeller, flight card or airplane model. See the [VAL-5–8 evidence reports](research/README.md#entry-points-per-track) and [ROADMAP](../ROADMAP.md) for physical gates.

## Flight and physics experiments

| Work | Entrypoint | Interpretation |
| --- | --- | --- |
| [E4b long-circuit sensitivity](research/ground-contact/E4b/README.md) | `python3 research/landing/e4b/measure.py --out /tmp/e4b-proof` | Requires Python standard library and pinned Godot; output directory must be new. Optional `--source` selects an isolated app snapshot and `--godot` selects the engine. It replays the frozen E4a tape in disposable copies and measures adjacent-float math sensitivity. It covers one calm, eastbound, wash-off Stik circuit on the executing platform. `ok: true` means the experiment completed, not that every perturbation stayed within tolerance. |
| [VAL-3 modal dashboard](../research/validation/README.md) | `python3 research/validation/dashboard.py` or `python3 research/validation/dashboard.py --check` | Uses current Stik analysis and locally supplied modal reference JSON. Writes `dashboard.md` and `snapshot.json`; `--check` detects stale/tampered output. Red reference comparisons are diagnostic results, not software failures or aircraft acceptance. |
| Sensitivity sweep | `$(app/get-godot.sh) --headless --path app --script "$PWD/research/sensitivity/sensitivity.gd"` | Reproducible parameter sensitivity table. This is a simulation study, not independent physical validation. |
| Aircraft data derivation | See the aircraft step READMEs, e.g. [`P51-05`](../research/p51/p51-05/derivation.md), [`EX-05`](../research/extra-300/ex05/derivation.md), and [`AV-06`](../research/avanti-s/av06/derivation.md). | These scripts generate checked-in model/data outputs from documented measurements and assumptions. Regenerate them; do not hand-edit generated outputs. |

The complete map of research reports and experiment families is in [docs/research/README.md](research/README.md). It distinguishes the committed report/evidence in `docs/research/` from reproducible scripts and data under root `research/`. Some aircraft scripts require local-only files under ignored `references/` and cannot be rerun from a fresh clone.

## Visual and asset tools

| Tool family | Useful entrypoints | Inputs, dependencies and limits |
| --- | --- | --- |
| Trees | `python3 tools/trees/place.py --check`; `"$(app/tests/visual-env.sh)" tools/trees/check_review.py --app app --godot "$(app/get-godot.sh)" --out /tmp/tree-review` | Placement check compares generated field data. `check_review.py` uses Xvfb/OpenGL for the runtime MultiMesh and shader path. The source-to-atlas bake is documented in [tools/trees/README.md](../tools/trees/README.md); it needs Node 24 (`npm ci --prefix tools/trees`), pinned Godot and the visual environment, and writes only to a fresh `--out` directory. It does not update `app/` automatically. |
| Grass | `python3 tools/grass/place.py --check`; `"$(app/tests/visual-env.sh)" tools/grass/check_grass.py --app app --godot "$(app/get-godot.sh)" --out /tmp/grass-review` | Generator verifies the committed visual-only clump layout; renderer check captures production A/B and requires Xvfb/OpenGL. For edge seams use the `check_grass_seam.py` command in the [README](../tools/grass/README.md). The layout is estimated and unsurveyed, not collision or terrain data. |
| Horizon terrain | `python3 tools/terrain/gen_terrain.py --check`; `"$(app/tests/visual-env.sh)" tools/terrain/check_horizon.py --app app --godot "$(app/get-godot.sh)" --out /tmp/horizon-review` | The generator checks the visual hill profile in `app/data/fields/horizon.json`; the render checker needs Xvfb/OpenGL. This is a distant visual profile, not a full terrain grid or physics/collision surface. |
| Ground surfaces and cues | See focused commands in [tools/ground/README.md](../tools/ground/README.md): `check_surfaces.py`, `check_stripes.py`, and `check_windsock.py`. | Use the pinned visual Python environment, Godot and Xvfb; provide a fresh output directory. Captures exercise production field/render code and image guards. Pixel or repeatability checks do not establish human readability or physical surface friction. |
| Sky and clouds | `"$(app/tests/visual-env.sh)" tools/atmosphere/check_phase6.py --app app --godot "$(app/get-godot.sh)" --out /tmp/atmosphere-review`; `"$(app/tests/visual-env.sh)" tools/atmosphere/check_cloud_probe.py --app app --godot "$(app/get-godot.sh)" --out /tmp/cloud-probe` | Fixed-camera production captures and a GPU density probe, using Xvfb/OpenGL. The probe checks shader properties, not hardware performance or atmospheric realism. |
| Scenery | See [tools/scenery/README.md](../tools/scenery/README.md): `place.py [--check]`, model baking, `scenario.sh`, `capture.sh`, and `landscape_metrics.py`. | Placement is deterministic. Model baking consumes the pinned third-party sources identified in `assets/scenery/PROVENANCE.json`; scenario/capture commands need Xvfb. Scenery is visual and off by default; its screenshots and budgets do not prove flight-physics changes. |
| README gallery | See [docs/media/README.md](media/README.md) for the exact `capture_aircraft.gd`, production flight capture and `package_media.py` commands. | Linux/Xvfb/Mesa, pinned Godot and visual Python/Pillow environment. Produces studio catalog renders and a flight screenshot; the model tour is not a flown maneuver or gameplay validation. |

Visual scripts under `tools/` generally create evidence in a caller-selected output directory. Read the family README before rerunning: many checks need an empty directory, fixed renderer, or a baseline app snapshot. The full app capture run records a manifest so old images cannot silently enter a new result.

## Native performance experiments

Native code is research-only; the simulator's production path remains GDScript. Both experiments below build ignored local artifacts and compare against GDScript in isolated projects.

| Experiment | Entrypoints | Limits |
| --- | --- | --- |
| [Gate P native slipstream](research/simulation-state/Gate-P/README.md) | `python3 research/native-slipstream/build.py --output .tools/native-slipstream/libopenrc_slipstream.so`; then `python3 research/native-slipstream/run.py --library .tools/native-slipstream/libopenrc_slipstream.so --output /tmp/gate-p-results` | The builder downloads pinned SCons/godot-cpp sources into `.tools/`; Linux x86_64 is the verified target. The runner needs Python 3.10+, pinned Godot and a clean committed `app/`, creates fresh clones and runs the full comparison by default. Windows/macOS recipes are unrun. `--quick --skip-suite` is diagnostic only. The existing evidence does not close Gate P or justify a production dependency. |
| [E0b6p prepared-model candidate](../research/propwash/e0b6p/prepared-model/README.md) | `python3 research/propwash/e0b6p/prepared-model/build.py --jobs 2`; then `python3 research/propwash/e0b6p/prepared-model/run.py --godot "$(app/get-godot.sh)" --output /tmp/prepared-model-run1` | Builds a research library with the locked toolchain, verifies source hashes and runs disposable baseline/candidate comparisons. Outputs must be distinct. The prepared snapshot requires explicit invalidation/re-preparation after model edits; it is not production reload/checkpoint wiring. |

The native evidence proves numerical agreement and measured performance only for its documented fixtures and platform. It does not establish independent flight realism, broad portability or a production performance win. See each experiment report before changing the scope.

## Keeping this index current

Add or update an entry when a tool gains a supported command, changes input contract/dependency, or moves between experimental and production use. Link the owning plan or README rather than copying its status table. Keep software verification, synthetic fixtures and independent physical evidence clearly separated.
