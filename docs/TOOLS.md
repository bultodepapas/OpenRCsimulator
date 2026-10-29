# Tooling and release workflows

Start at the [task index](tools/README.md) to choose a tool. This page owns setup, release preparation, radio diagnostics and Workshop commands; linked tool READMEs own their detailed contracts. Run commands from the repository root in Bash unless labeled PowerShell; use `python` on native Windows.

## Developer setup

Use the official Godot **4.8-beta1** prerelease pinned by [`app/get-godot.sh`](../app/get-godot.sh), which verifies the archive, exact engine version and cached executable hashes. The downloader supports Linux x86_64, Windows x86_64 under Git Bash, and native Darwin ARM64. On Linux and Windows install Git, Bash, curl, unzip, GNU coreutils, util-linux and Python 3.

```sh
git clone -c core.autocrlf=false https://github.com/bultodepapas/OpenRCsimulator.git
cd OpenRCsimulator
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --import
"$(app/get-godot.sh)" --path app
```

Import before standalone scripts on a fresh checkout; the test and capture runners import automatically. For captures, install Xvfb, Mesa/OpenGL, Python venv support and pip 22.3+; `app/tests/visual-env.sh` supplies the pinned CPython 3.12 packages. Exports need `zip` and `app/get-templates.sh`, which verifies the matching official templates and prepares the project-local macOS template.

**Windows:** run `bash app/get-godot.sh` in Git Bash first. Use WSL2 Ubuntu on its Linux filesystem for the Linux CI/capture/export workflow, keeping Windows and Linux checkouts and import caches separate. Native PowerShell:

```powershell
$GodotWindows = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
& $GodotWindows --headless --path app --audio-driver Dummy --import
& $GodotWindows --path app
python tools/godot/run_checked.py --timeout 90 -- $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_simulation.gd
```

Use the [checked runner](../tools/godot/README.md) for focused tests: Godot can print script errors and still exit zero. WSL checks establish Linux behavior, not native Windows GPU/device acceptance. For the native Apple Silicon downloader, template prerequisite and hardware inventory, follow the [macOS setup and preflight](../tools/godot/README.md#native-apple-silicon-setup-and-preflight-dt-mac-02a). Native Mac execution remains to be verified; Linux cross-export and release gates are unchanged.

**Linux Wayland:** beta1 can crash while falling back from unavailable X11 to Wayland ([issue #124731](https://github.com/godotengine/godot/issues/124731); [fix #124734](https://github.com/godotengine/godot/pull/124734) postdates this pin). In a working Wayland session, launch with `python3 tools/graphics/launch.py --display-driver wayland`. Imports, tests and exports use `--headless`; these do not qualify desktop Wayland rendering.

Node's version is pinned in [`.nvmrc`](../.nvmrc) for tree authoring and the frozen three.js prototype; the production app and static site do not need Node. [CI](../.github/workflows/ci.yml) owns the Linux package prerequisites and job commands.

Use ignored `tmp/` or `output/` for new scratch results; retain accepted evidence with its owning track. Cleanup must preserve source deliveries, `references/`, tool environments and registered worktrees (`git worktree list`), including those inside scratch directories. Captures and performance evidence follow the [1080p-first resolution policy](../AGENTS.md#display-resolution-priorities).

## App and release commands

| Task | Entry point | Contract or limit |
| --- | --- | --- |
| App checks | `app/test.sh` | [Full suite and focused checks](tools/shared.md#full-app-suite); partitions alone are incomplete. |
| Offline regressions | `research/test-tools.sh` | [Additional CI checks](tools/shared.md#ci-only-checks). |
| Visual checks | `app/capture.sh` | [Capture suite and area tools](tools/graphics.md); outputs under ignored `app/captures/`. |
| Direct flight or trace | [Launch flags](tools/shared.md#launch-flags) | Explicit aircraft, start, landscape and weather; direct routes ignore player preferences. |
| High graphics | `python3 tools/graphics/launch.py --profile high` | [Graphics modes](../tools/graphics/README.md). |
| Windows NVIDIA package | `python tools/graphics/native/product.py --package` | Current app with DLSS, DLAA and Reflex; [build and launch](../tools/graphics/native/README.md). |
| Club scenery | `app/run-landscape.sh` | Forces Club scenery on; `--scenery=off` opts out on direct launches. [Landscape checks](tools/graphics.md#landscape-checks). |
| Running app | `python3 tools/debug/debugctl.py launch` | [Debug bridge](../tools/debug/README.md): UI, controls, telemetry, logs, captures and bug hunting; `smoke` is the regression pass. |
| Companion solver pin | `python3 tools/companions/rebind.py` | Read-only comparison; `--accept` changes the pin only after identical tapes. [Rebind contract](../tools/companions/README.md). |
| Repository size | `python3 tools/repo/check_large_files.py` | [Evidence-size policy](README.md#conventions-for-documents). |
| Crash-cost data | `python3 research/crash-economics/build_runtime.py --check` | Verification only; omit `--check` to regenerate intentionally. |
| Process RAM and disk | Checked runner `--resources`; `python tools/godot/storage_audit.py . --out <new.json>` | [Options and limits](../tools/godot/README.md#process-ram-io-and-storage-pt1h-r4). |
| Packages | `app/export.sh [--output-dir NEW_DIRECTORY]` | Creates one new `dist/export-XXXXXXXX/` directory by default; preserves previous/failed outputs. Three OS archives, pack checks and `SHA256SUMS`; follow [release preparation](#release-sequence). |

The suite permits only two named physical checks to remain pending: the Stik right-first 240 Hz reference-doublet `|β| ≤ 25°` screen, and the R02 yaw comparison. [D10-R2](research/flight-dynamics/stik-lateral-directional-2026-10-18/README.md#6-decisions-and-adoption-d10-r2-2026-10-18) and [R02 diagnostics](research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/README.md) own their rationale. Recovery, yaw-rate, finite-state and timestep checks remain mandatory; [P-51 checks are strict](research/p51-realism/P51-22/README.md#resolution--2026-10-16). Run `test_rudder_authority.gd` and `test_yaw_damping.gd` through the [checked runner](tools/shared.md#one-godot-script) without allow flags for strict results. Pending is not a pass.

`app/test.sh` is not all of CI. See [CI coverage and diagnostics](tools/shared.md#ci); software checks do not establish physical accuracy, radio latency or target-GPU performance.

## CodeRabbit reviews

[`.coderabbit.yaml`](../.coderabbit.yaml) owns hosted review policy. Give the [GitHub App](https://github.com/apps/coderabbitai/installations/new) access to this repository and enable it in [repository settings](https://app.coderabbit.ai/settings/repositories). Check [current OSS eligibility](https://docs.coderabbit.ai/management/plans#open-source) and [limits](https://docs.coderabbit.ai/management/rate-limits) with the provider; do not infer availability from old trial or quota notes.

For an authorized PR review, `@coderabbitai review` requests an incremental review; `@coderabbitai full review` rereads the diff. Wait for the actual review/check before treating it as evidence. A skipped or aborted review is not clean approval; reviews do not replace CI or maintainer decisions.

### Local CLI and agents

Follow the [official CLI installation](https://docs.coderabbit.ai/cli), inspect the installer before running it, and sign in with `coderabbit auth login` in your own terminal. Agents must not handle login tokens. `coderabbit doctor` checks readiness.

- **Claude Code:** use the official `coderabbit` plugin. Do not copy the repository's `code-review` skill into `.claude/skills/`; it collides with Claude Code's built-in name.
- **Codex:** use `.agents/skills/{code-review,autofix}`, pinned by [`skills-lock.json`](../skills-lock.json).

Local review: `coderabbit review --agent --base main` or `--uncommitted`. Read PR threads: `coderabbit pullrequest <n> --show-threads --agent`. Check availability: `coderabbit usage --agent`. Local review sends the selected diff to CodeRabbit; inspect its scope before submission.

## Release sequence

1. Review the selected diff and retain proof with the owning track. Run applicable schema/generator, offline, full app and visual checks on the exact source intended for release; [CI](../.github/workflows/ci.yml) defines the publication dependencies.
2. After the last edit under `app/physics`, `app/sim` or `app/failures`, follow the [companion rebind workflow](../tools/companions/README.md) and commit the pin, qualification record and receipt together. A stale pin disables exported companions; changed behavior requires requalification.
3. Prepare an isolated Linux export checkout. Install matching Windows/Linux ground-vehicle artifacts through [their builder](../research/rc-monster-truck/native/README.md#installing-and-exporting) and qualified Linux NK-3 artifacts through [its installation and package workflow](../research/native-kernel/README.md#linux-release-packages). Export checks source/ABI/solver identities, receipts and binary hashes; keep required native libraries beside the executables.
4. Add `docs/releases/<tag>.md`. A `vX.Y.Z` tag must match `app/project.godot`; `app/export.sh` takes no version argument and uses `git describe`. Each run reserves a fresh `dist/export-XXXXXXXX/`, or a new path supplied with `--output-dir`. Existing destinations and paths inside `app/` or Git metadata are rejected, including symlink aliases. Failed outputs remain for inspection. A checkout lock refuses competing exporters; still use an isolated checkout to avoid other import/build/editor mutations. Linux requires `flock` and `realpath` from the documented system tools. CI uploads the exact successful run's three ZIPs/checksums and verifies them after artifact transfer.
5. When publishing, create the annotated tag on the reviewed commit and push commit and tag together, for example `git push --atomic origin HEAD:main refs/tags/vX.Y.Z`. The tag must be visible when `main` exports; a previous tag with a different project version is rejected. CI exports on `main`, `v*` tags and manual dispatch. Publication waits for all required checks and release notes; numeric tags publish releases and suffixed tags prereleases.
6. Verify all three archives and checksums. Linux execution and structural pack checks do not replace native OS, GPU, radio or pilot acceptance; use the [exported runway smoke and pilot card](research/menu-investigations/UI-06c/README.md).
7. Update the [project website](../site/README.md#preview-and-maintain) from the published tag/assets and verify public English/Spanish download and checksum links.

## Radio diagnostics

| Task | Command / reference |
| --- | --- |
| Device report | `"$(app/get-godot.sh)" --path app -- --input-report=input-report.json --t=20`; move axes and press/release buttons. [F1 format](research/radio-input/F1/README.md); an empty device list is valid. |
| Filmed latency marker | `"$(app/get-godot.sh)" --path app -- --latency-patch --latency-axis=0 --latency-threshold=0`; [F6a protocol](research/radio-input/F6a/README.md). |
| Calibration regressions | `python3 research/input/d6b-r2/verify.py --out tmp/<new-dir>`; [contract](research/radio-input/D6b-R2/README.md). |
| Video reduction | [Latency reducer](../research/radio-latency/README.md): campaign manifest, annotated events and original clip identity. |

Callback timestamps are not USB polling intervals or physical stick-to-screen latency. Hardware claims require original device/display observations.

## Aircraft Workshop

The [Workbench guide](AIRCRAFT-WORKSHOP.md) owns the workflow, supported adjustments and evidence map; the [AE plan](plans/aircraft-editor.md) owns pending integration gates. Run these checks from the repository root:

```sh
python3 research/aircraft-standardization/build_models.py --check
python3 research/aircraft-editor/build_descriptors.py --check
python3 research/aircraft-standardization/build_customization.py --check
python3 research/aircraft-standardization/test_customization.py
python3 research/aircraft-editor/test_descriptor_checkout.py
```

The checkout test creates and removes disposable Git fixture repositories, including fixture commits, under ignored `.tools/`; it never stages or commits the working repository. It checks LF/CRLF checkouts and generator consistency. A descriptor rejection must be resolved in the owning aircraft/module pipeline; do not weaken assertions or hand-edit generated descriptors.

After source changes, follow the [model → customization → descriptor generation order](AIRCRAFT_CONTRACT.md#model-and-package-contract), then repeat the checks above and review the generated diff. Honor `.gitattributes`: exact aircraft bytes and model-manifest hashes are inputs. Presentation-only changes do not rewrite physical manifests. `test_presentation_sources.gd` checks the exported presentation proof package.

`app/test.sh` discovers the focused GDScript suites as part of the full suite. For native Windows, import first using [developer setup](#developer-setup), then run every Workshop suite:

```powershell
# $GodotWindows is the matching console executable from developer setup.
$WorkshopSuites = @(Get-ChildItem app/tests/test_workshop_*.gd | Sort-Object Name | ForEach-Object { $_.Name }) + @(
    'test_aircraft_customization.gd', 'test_smoke_profiles.gd', 'test_presentation_sources.gd'
)
foreach ($Suite in $WorkshopSuites) {
    python tools/godot/run_checked.py --timeout 90 -- $GodotWindows --headless --path app --audio-driver Dummy --script ("res://tests/" + $Suite)
    if ($LASTEXITCODE -ne 0) { throw ("Workshop suite failed: " + $Suite) }
}
```

Inspect each suite's assertions and engine errors as well as exit status. Focused passes do not replace the descriptor check, full app suite or physical/pilot acceptance.

For the longer abrupt-writer run, execute `test_workshop_store_interruptions.gd` separately with `-- --process-cuts`, using the current pinned engine and an adequate timeout. [AE-03a](research/aircraft-editor/AE-03a/README.md#reproduce) owns the protocol and limits. It and `test_workshop_staging.gd` use unique disposable libraries; neither repairs player locks nor establishes hardware power-loss durability.

### Workshop captures

For a native rendered still:

```powershell
& $GodotWindows --path app --script (Resolve-Path research/aircraft-editor/capture_workshop.gd).Path -- --language=es --1080p
```

Arguments after `--`: `--language=en|es`, `--scale=<factor>` (default `2.0`), `--width=<px>`/`--height=<px>` (default 1280×720), `--1080p`, `--text-scale=1|1.5|2`, and `--out=<PNG-path>` (default `user://workshop-review.png`). Review cases: `--page=appearance|lighting|smoke|audio|setup|compare`, `--preview`, `--dialog=library|save|guard|bundle-import`, `--invalid`, `--long-name`, `--opaque`, `--reduced-motion`, `--aircraft=<catalog-id>` and `--fullscreen`. Customization cases accept `--paint-color=#RRGGBBAA`, `--marking=RC-27`, `--smoke-preset=1..6`, and `--smoke-seconds=0..16`; inscription requires a registered mount. The script applies the shared canvas policy, writes a JSON geometry sidecar, and returns nonzero for out-of-bounds key actions/popups. Inspect the PNG as well; rectangles do not prove legibility. Fullscreen evidence must report the actual monitor/window pixels. A custom output directory must already exist. The script uses a separate empty-library root and needs a display; it does not save player variants. The [initial captures](research/aircraft-editor/AE-01-10/README.md#native-captures) retain their original scope.

For a moving preview capture, add `--smoke-motion=pass --smoke-seconds=3 --smoke-preset=2 --page=smoke --scale=1` to the Workshop capture command; use `--smoke-seconds=6` for the paused endpoint. The sidecar records motion, tick, rig position, particle allocation and playback-control bounds. This illustrative pass does not run flight physics or establish a GPU cost result.

The native GPU birth-color/lifecycle probe is `research/aircraft-editor/capture_smoke_profiles.gd`. Run it with the same display command in place of `capture_workshop.gd`; it writes rate captures and `metrics.json` under ignored `tmp/smoke-profile-native/`, returns nonzero when its checks fail, and allocates the production shared 768-particle profile budget. It is renderer evidence, not a portable performance benchmark.

The recovery, measurement and thumbnail helpers create disposable libraries, exercise real UI/renderer paths, and return nonzero on failed assertions:

```powershell
$RecoveryOut = Join-Path (Get-Location).Path 'tmp/workshop-recovery-review'
& $GodotWindows --path app --audio-driver Dummy --script (Resolve-Path research/aircraft-editor/capture_recovery.gd).Path -- --lang=es --size=1920x1080 "--out=$RecoveryOut.png" "--evidence=$RecoveryOut.json"
$MassOut = Join-Path (Get-Location).Path 'tmp/workshop-mass-review'
& $GodotWindows --path app --audio-driver Dummy --script (Resolve-Path research/aircraft-editor/capture_mass.gd).Path -- --lang=es --size=1920x1080 --text-scale=2 "--out-dir=$MassOut" "--evidence=$MassOut/report.json"
& $GodotWindows --path app --audio-driver Dummy --script (Resolve-Path research/aircraft-editor/capture_thumbnails.gd).Path
```

These examples write ignored `tmp/` evidence; recovery and measurement require their output arguments. Use explicit phase paths from [AE-03c](research/aircraft-editor/AE-03c/README.md), [AE-12/13](research/aircraft-editor/AE-12-13/README.md) or [AE-24d.1](research/aircraft-editor/AE-24d-1/README.md) to reproduce those records. Native captures need a display. Headless companion suites are `test_workshop_drafts.gd`, `test_workshop_recovery_ui.gd`, `test_workshop_mass_edit.gd`, `test_workshop_mass_recipe.gd`, `test_workshop_mass_ui.gd` and `test_workshop_thumbnails.gd`. Recovery injection covers code boundaries; it does not establish hardware power-loss durability.

For Library/profile-copy review, supply `--library-build=<local-bundle-json>` with `--dialog=library|profile-copy`; optional `--favorite` marks that fixture. The helper imports into a unique capture-only library and removes the fixture afterward; it never writes player variants. Captures scroll the saved actions or copy decisions into view. Example: add `--aircraft=gp-extra-300s-60 --scale=1 --language=es --width=1920 --height=1080 --text-scale=2 --library-build=C:/captures/build.json --dialog=profile-copy` to the native capture command.

### Bundles and offline analysis

Export a saved build from **Library → Export selected**; import creates a new local UUID after validation. A direct technical launch reads the bundle without importing or writing player preferences:

```powershell
& $GodotWindows --headless --audio-driver Dummy --path app -- --aircraft-variant=C:/captures/build.json --trace=C:/captures/build.csv --t=0.25
```

Use an existing export and an existing output directory. `--aircraft-variant` is mutually exclusive with `--aircraft`, `--battery`, `--electric-demo`, `--experimental-aircraft-data`, and `--scripted`. The bundle embeds data and exact source bytes; it does not supply executable resource paths or replace installed dependencies. Trial metadata keeps physical `workshop` identity separate from visual `workshop_presentation` identity.

Offline analysis uses the source-only runner and data-only examples. Each output must be a new local JSON file:

```powershell
$Analysis = (Resolve-Path research/aircraft-editor/run_experiment.gd).Path
& $GodotWindows --headless --path app --script $Analysis -- --aircraft=jensen-das-ugly-stik-60 --out=C:/captures/stik-static.json
& $GodotWindows --headless --path app --script $Analysis -- --aircraft=jensen-das-ugly-stik-60 --recipe=../research/aircraft-editor/examples/glide.json --out=C:/captures/stik-glide.json
& $GodotWindows --headless --path app --script $Analysis -- --aircraft=jensen-das-ugly-stik-60 --sweep=../research/aircraft-editor/examples/sweep.json --out=C:/captures/stik-sweep.json
```

Replace `--aircraft` with `--bundle=C:/captures/build.json` to analyze a detached export. Relative input/output paths resolve from `app/`. Static reports and bounded grid/seeded sweeps expose existing compiler estimates; fixed-tape experiments run at 240 Hz for at most 120 seconds with at most 64 input spans. Reports include frozen build/presentation identities, solver/build pins, initial checkpoint, environment, tape and stop reason. Body speed is not airspeed. An unsupported flight experiment writes its reason and exits 3; malformed input exits 2. These results establish software behavior, not measured performance or physical validity. The runner refuses existing outputs and input/output collisions.

The [trace-dialog capture](../research/aircraft-editor/capture_trace_recovery.gd) uses a deterministic failed recorder in a separate quick-flight process. Run `& $GodotWindows --path app --audio-driver Dummy --script (Resolve-Path research/aircraft-editor/capture_trace_recovery.gd).Path`; it captures Spanish at 1280×720/200% text to `user://trace-recovery-es-200.png`, or accepts `-- --out=<PNG-path>`. This checks native dialog fit; it does not simulate a disk failure or establish trace durability.

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

The flight-test battery, aircraft generators, golden flights, probes and track verifiers live in [physics tools](tools/physics.md); debugging steps in the [physics playbook](tools/debugging-physics.md). [Research index](research/README.md) maps dated evidence; the [tools/input map](../research/README.md) pairs experiment folders with their reports. The [literature-library workflow](research/flight-dynamics/rc-validation-library-2026-10-18/README.md#recheck-the-collection) verifies local originals and regenerates CSV/BibTeX from source manifests. Some source studies require ignored `references/` files and cannot run from a fresh clone.

## Rendering, field, audio and asset tools

Capture, comparison, per-area checkers and frame diagnosis live in [graphics tools](tools/graphics.md); debugging steps in the [graphics playbook](tools/debugging-graphics.md). Each tool family's README owns its commands and dependency pins: [audio](../tools/audio/README.md), [landscape](../tools/landscape/README.md), [shadows](../tools/shadows/README.md), [world](../tools/world/README.md), [trees](../tools/trees/README.md), [grass](../tools/grass/README.md), [terrain](../tools/terrain/README.md), [ground](../tools/ground/README.md), [atmosphere](../tools/atmosphere/README.md), [scenery](../tools/scenery/README.md), [smoke](../tools/smoke/README.md). Headless simulation does not measure GPU performance; llvmpipe captures do not qualify target hardware.

## Native performance experiments

Use [session performance tools](../research/performance/README.md) for complete-callback CPU probes, paired instrumentation checks, native-frame reduction and texture inventory. Simulated-tick CPU durations do not replace rendered-frame, loading or package measurements.

Current backend selection belongs to [STACK](STACK.md#runtime). [NK-3](../research/native-kernel/README.md) owns flight-backend builds, exactness gates, installation and packaging; [C++ development tools](../research/native-kernel/README.md#c-development-tools-nk-3) cover sanitizers, symbols and diagnostic builds. The ground vehicle has a [separate native builder](../research/rc-monster-truck/native/README.md). Do not infer full-fleet or cross-platform qualification from a local native library.

Older isolated experiments remain reproducible under their own contracts:

| Experiment | Contract |
| --- | --- |
| Native slipstream | [Gate P](research/simulation-state/Gate-P/README.md): pinned builder and comparison runner. |
| Prepared model | [prepared-model](../research/propwash/e0b6p/prepared-model/README.md): lifecycle and paired clones. |
| Prepared path attribution | [prepared-cost](../research/propwash/e0b6p/prepared-cost/README.md): full-tick and phase measurements. |
| Aero/simulation attribution | [dynamics-cost](../research/propwash/e0b6p/dynamics-cost/README.md): nested costs and observer overhead. |
| Wing-loop candidate | [wing-loops](../research/propwash/e0b6p/wing-loops/README.md): unadopted combined candidate. |

Keep same-machine timing, numerical agreement and physical validation distinct.

## Keeping this index current

Give each command one detailed home and route to it from the task index. Update examples with their entrypoints; keep dated results in existing evidence, not current setup instructions. Verify links, flags, output locations and side effects before recommending a tool.
