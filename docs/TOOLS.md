# Tooling index

Canonical setup and command index. Code, configuration and generated data define implemented behavior. Run commands from the repository root; detailed tool contracts live in the linked READMEs.

## Developer setup

The CI host is Ubuntu 24.04 x86_64. Install Git, Bash, curl, unzip, GNU coreutils, util-linux and Python 3. `app/get-godot.sh` downloads the exact Godot version pinned in that script and verifies the archive's SHA-512.

```sh
git -c core.autocrlf=false clone https://github.com/bultodepapas/OpenRCsimulator.git
cd OpenRCsimulator
"$(app/get-godot.sh)" --headless --path app --editor --import
"$(app/get-godot.sh)" --path app
```

Import before standalone scripts on a fresh checkout. Test and capture runners import automatically. Interactive runs need a display. Captures also need Xvfb, Mesa/OpenGL, Python venv support and pip 22.3+; `app/tests/visual-env.sh` installs the hashed CPython 3.12 visual environment. Export needs `zip` and verified Godot export templates; the initial template download is about 1.28 GB.

**Windows:** use WSL2 Ubuntu on its Linux filesystem for the Bash test/capture/export scripts. Clone with the command above; copying a CRLF checkout can break Bash scripts. For native Windows, install the matching official Godot build:

```powershell
$GodotWindows = 'C:\Tools\Godot_v4.7.2-stable_win64_console.exe'
& $GodotWindows --headless --path app --editor --import
& $GodotWindows --path app
# Focused native check; repeat for the affected test scripts:
& $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_simulation.gd
```

Inspect exit status **and** engine errors in logs: Godot can report runtime script errors with exit code zero. WSL results establish Linux behavior, not native Windows GPU or device acceptance. On macOS, open `app/project.godot` with the matching Godot build.

Node 24 (`.nvmrc`) is only needed for tree authoring and the frozen three.js prototype. To reproduce the Linux app CI job with Docker and `act`: `act push -P ubuntu-24.04=catthehacker/ubuntu:act-latest -j app`.

## App and release commands

| Purpose | Command | Scope |
| --- | --- | --- |
| Engine | `app/get-godot.sh` | Pinned binary and verified download. |
| App checks | `app/test.sh` | Every GDScript parses; unit/session/UI tests, model contracts, traces, replay and frame-rate independence. |
| Offline regressions | `research/test-tools.sh` | Measurement reducers, importers and validation tools. |
| Visual checks | `app/capture.sh` | Rendered cases, image guards, traces and complete manifest in ignored `app/captures/`. |
| Run | `"$(app/get-godot.sh)" --path app` | Home; [controls](FIRST-LAUNCH.md). |
| Quick flight | `"$(app/get-godot.sh)" --path app -- --quick-flight` | Direct flight; no player preferences. Add `--aircraft=<catalog-id>`, `--rates=full` or `--hud=overlays`. |
| Full field | `app/run-landscape.sh` | Forces scenery on. Normal launches already default to on; opt out with `-- --scenery=off`. |
| Flight trace | `"$(app/get-godot.sh)" --headless --path app -- --trace=/tmp/openrc-trace.csv --t=3` | Initial state plus each 240 Hz tick; [trace contract](research/trace-integrity/C7-R2/README.md). |
| Physics cost | `"$(app/get-godot.sh)" --headless --path app --script res://tests/bench_physics.gd` | Add `-- --aircraft=<catalog-id>`. Run alone on the target machine. |
| Packages | `app/export.sh` | Windows/Linux/macOS ZIPs, pack smoke checks and `dist/SHA256SUMS`. Preserves exporter-managed native libraries beside Windows/Linux executables. Recreates `dist/`. |

[CI](../.github/workflows/ci.yml) also checks schemas, generated geometry/physics and the Linux native ground-vehicle evaluator. `app/test.sh` alone does not run every CI check. Software checks do not establish physical aircraft accuracy, radio latency or target-GPU performance.

The frozen prototype's separate CI job runs `npm ci`, `npm run typecheck`, `npm test`, `npx playwright install --with-deps chromium`, `npm run capture` and `npm run e2e` from `prototypes/stage0/three/`.

## Release sequence

1. Review the selected diff and retain proof beside the owning research evidence.
2. Run applicable schema/generator, offline, app and visual checks. Export from an isolated Linux checkout; keep unrelated files out of `dist/`.
3. Add `docs/releases/<tag>.md`. A `vX.Y.Z` tag must match `app/project.godot`; `git describe` supplies package identity. `app/export.sh` takes no version argument.
4. Push the reviewed commit and tag. CI exports on `main`, `v*` tags and manual dispatch. After checks and release notes pass, `vX.Y.Z` tags publish official releases; suffixed tags publish prereleases.
5. Verify all three archives and checksums. Linux execution and structural pack checks do not replace native OS, GPU, radio or pilot acceptance.

[Exported runway smoke and pilot card](research/menu-investigations/UI-06c/README.md) cover the Linux/Xvfb keyboard route, recorded traces, CLI parity and isolated preferences.

## Radio diagnostics

| Task | Command / reference |
| --- | --- |
| Device report | `"$(app/get-godot.sh)" --path app -- --input-report=input-report.json --t=20`; move all connected controls. [F1 format](research/radio-input/F1/README.md). Empty device lists are valid. |
| Filmed latency marker | `"$(app/get-godot.sh)" --path app -- --latency-patch --latency-axis=0 --latency-threshold=0`; [F6a protocol](research/radio-input/F6a/README.md). |
| Calibration regressions | `python3 research/input/d6b-r2/verify.py --out /tmp/d6b-r2-proof`; fresh directory, disposable defect tests. [Contract](research/radio-input/D6b-R2/README.md). |
| Latency video reduction | [research/radio-latency](../research/radio-latency/README.md): campaign manifest, annotated events and original clip identity. |

Callback timestamps are not USB polling intervals or physical stick-to-screen latency. Hardware claims require original device/display observations.

Weather and time controls: [wind](research/wind-implementation/README.md), [atmosphere](research/atmosphere/M5-ATM-2/README.md), [time of day](research/time-of-day-investigations/TOD-05/README.md). Direct examples: `--weather=gusty`, `--weather=turbulent`, `--weather=hot-high`, or `--time-of-day=05:45 --date=2026-03-20`. Home edits persist; direct routes do not use preferences. `app/tests/check_wind_trace.py` and `check_atmosphere_trace.py` validate the corresponding trace formats.

## Aircraft measurement reducers

All reducers are offline Python tools. They consume observations and do not rewrite flight data. Their examples are synthetic; physical campaigns need raw records, configuration, calibration and uncertainty.

| Measurement | Tool contract |
| --- | --- |
| Mass and horizontal CG (VAL-5a) | [weighing](../research/validation/weighing/README.md) |
| Swing-test inertia (VAL-6a) | [inertia](../research/validation/inertia/README.md) |
| Static propeller thrust/RPM/torque (VAL-7a) | [static-prop](../research/validation/static-prop/README.md) |
| RPM step response (VAL-7b/c) | [rpm-step](../research/validation/rpm-step/README.md) |
| Surveyed takeoff/landing video (VAL-8a) | [ground-video](../research/validation/ground-video/README.md) |
| Completed-roll video (VAL-8b) | [roll-video](../research/validation/roll-video/README.md) |
| Propwash field observations (E0b7) | [propwash/e0b7](../research/propwash/e0b7/README.md) |

Each README owns its input format, command and tests. Without torque, static thrust/RPM cannot establish shaft power. Video cycle averages are not instantaneous velocity or angular rate.

## Flight and physics experiments

Use fresh output directories and the pinned Godot build. Run timing experiments alone; fixture equivalence proves software preservation, not physical validity.

| Area | Entrypoint / authoritative contract |
| --- | --- |
| Aircraft authoring | `python research/aircraft-standardization/conformance.py --godot <godot> --out <fresh-dir> --parse-all`; [aircraft contract](../AIRCRAFT_CONTRACT.md). Optional `--package` checks exports. |
| Natural Random | `python research/natural-random/verify.py --godot <godot> --out <fresh-dir>`; [evidence](research/natural-random/README.md). |
| Glow 2T/4T | `python research/glow-engines/verify_integration.py --godot <godot> --out <fresh-dir> --parse-all`; [current integration](GLOW-ENGINES.md), [isolated kernels](../research/glow-engines/README.md). |
| Helicopter | [current experimental flight session and checks](HELICOPTER.md); `research/helicopter/verify_kernels.py` owns independent kernel references and disposable defects. |
| Bisonte ground vehicle | [runtime/experiments](../research/rc-monster-truck/README.md), [native builder/parity](../research/rc-monster-truck/native/README.md). |
| Electric coupling | [EL2a-P1](../research/propulsion/el2a-p1/README.md), [EL2a-P2 event qualification](../research/propulsion/el2a-p2/README.md). Reference runs use their pinned NumPy/SciPy environment. |
| Taildragger and nose-over | `python3 research/ground-contact/e5a/verify.py --out /tmp/e5a-proof --mutations`; analogous `e5b/verify.py`. [E5a](../research/ground-contact/e5a/README.md), [E5b](../research/ground-contact/e5b/README.md). |
| Long-circuit sensitivity | `python3 research/landing/e4b/measure.py --out /tmp/e4b-proof`; [E4b limits](research/ground-contact/E4b/README.md). Experiment completion does not mean every perturbation passed. |
| Parameter sensitivity | `"$(app/get-godot.sh)" --headless --path app --script "$PWD/research/sensitivity/sensitivity.gd"`. |
| Modal dashboard | `python3 research/validation/dashboard.py --check`; [validation tools](../research/validation/README.md). Red reference comparisons are diagnostic results. |
| Aircraft generators | Source pipelines in the aircraft guides; examples: [P51-05](../research/p51/p51-05/derivation.md), [EX-05](../research/extra-300/ex05/derivation.md), [AV-06](../research/avanti-s/av06/derivation.md). |

[Research index](research/README.md) maps remaining experiments and dated evidence. Some source studies require ignored `references/` files and cannot run from a fresh clone.

## Rendering, field, audio and asset tools

Focused commands and dependency pins belong to the tool README. Most render checks need a display or Xvfb, OpenGL, and a fresh output directory. Headless simulation does not measure GPU performance; llvmpipe captures do not qualify target hardware.

| Tool family | Contract |
| --- | --- |
| Audio generation, native capture and packs | [tools/audio](../tools/audio/README.md) |
| Landscape lighting and glare | [tools/landscape](../tools/landscape/README.md) |
| Projected shadows | [tools/shadows](../tools/shadows/README.md) |
| Sky, stars and time progression | [tools/world](../tools/world/README.md) |
| Tree placement and atlas baking | [tools/trees](../tools/trees/README.md) |
| Grass placement and seams | [tools/grass](../tools/grass/README.md) |
| Horizon generation | [tools/terrain](../tools/terrain/README.md) |
| Ground surfaces and windsock | [tools/ground](../tools/ground/README.md) |
| Atmosphere and cloud probes | [tools/atmosphere](../tools/atmosphere/README.md) |
| Scenery sources, placement and capture | [tools/scenery](../tools/scenery/README.md) |
| Engine smoke | [tools/smoke](../tools/smoke/README.md) |
| Gallery/media | [media workflow](media/README.md) |
| Propeller blur | `res://tests/capture_propeller_blur.gd`; [VQ-05 contract](research/visual-quality-implementation/VQ-05/README.md). |

`app/capture.sh` writes a complete-run manifest only after all checks pass. Legacy landscape references explicitly disable scenery; scenery cases enable it. Fixed captures are not the normal Home/Fly route.

## Native performance experiments

[Session performance tools](../research/performance/README.md) provide the VQ-01c
complete-callback CPU probe, paired instrumentation checks and native-frame reduction.
The separate read-only texture inventory supports VQ-02a. CPU probe durations are
simulated ticks; they do not replace native frame, loading, package or pilot acceptance.

Flight physics uses GDScript. The ground-vehicle activity can use its qualified C++ evaluator, with GDScript reference/fallback; [build and platform contract](../research/rc-monster-truck/native/README.md). Other native candidates below remain research outside production:

| Experiment | Commands and limitations |
| --- | --- |
| Native slipstream | [Gate P](research/simulation-state/Gate-P/README.md): pinned builder and isolated comparison runner; verified Linux target. |
| Prepared model | [prepared-model](../research/propwash/e0b6p/prepared-model/README.md): snapshot lifecycle, paired clones and exact agreement. |
| Prepared path attribution | [prepared-cost](../research/propwash/e0b6p/prepared-cost/README.md): full-tick and separate phase measurements. |
| Aero/simulation attribution | [dynamics-cost](../research/propwash/e0b6p/dynamics-cost/README.md): nested costs, observer overhead and report guards. |
| Wing-loop candidate | [wing-loops](../research/propwash/e0b6p/wing-loops/README.md): production/candidate comparisons; combined candidate not adopted. |

Do not infer a production speedup or cross-platform qualification from a research fixture. Keep same-machine timing, numerical agreement and physical validation distinct.

## Keeping this index current

Update supported entrypoints when code changes. Link detailed contracts instead of repeating plan status or evidence tables. Retain one home for each tool and label measurements by platform and renderer.
