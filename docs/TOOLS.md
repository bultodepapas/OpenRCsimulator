# Tooling index

Resolution priority: **1080p primary; above-1080p resolutions (including 1440p, 4K and higher) secondary desirable; 720p tertiary and last**. Follow the [shared policy](../AGENTS.md#display-resolution-priorities). Existing 720p defaults, fixtures and historical results retain their stated scope and do not qualify the primary target.

Canonical setup and command index. Code, configuration and generated data define implemented behavior. Run commands from the repository root in Bash unless labeled PowerShell; native Windows Python examples use `python` instead of `python3`. Detailed tool contracts live in the linked READMEs. To find the tool for a task, start at the [tool index](tools/README.md).

## Developer setup

The standard engine is official Godot **4.8-beta1**, a prerelease, with CLI identity `4.8.beta1.official.4d10419ca`. The CI host is Ubuntu 24.04 x86_64. Install Git, Bash, curl, unzip, GNU coreutils, util-linux and Python 3 (`python3`). `app/get-godot.sh` downloads the pinned Linux x86_64 editor or Windows x86_64 console editor under Git Bash, verifies the official archive's SHA-512 and exact version, and checks cached binary hashes on reuse.

```sh
git clone -c core.autocrlf=false https://github.com/bultodepapas/OpenRCsimulator.git
cd OpenRCsimulator
"$(app/get-godot.sh)" --headless --path app --editor --import
"$(app/get-godot.sh)" --path app
```

Import before standalone scripts on a fresh checkout. Test and capture runners import automatically. Interactive runs need a display. Captures also need Xvfb, Mesa/OpenGL, Python venv support and pip 22.3+; `app/tests/visual-env.sh` installs the hashed CPython 3.12 visual environment. Export needs `zip` and `app/get-templates.sh`; its initial official template download is about 1.36 GB. The installer verifies SHA-512 and uses Godot's exact `4.8.beta1` template directory under the host's Godot data folder. It also prepares the project-local macOS universal template selected by the export preset, preserving the installed official templates.

**Windows:** Git Bash supports the pinned native editor download and focused headless checks. Run `bash app/get-godot.sh` there first; it installs both Windows executables into `.tools/`. Use WSL2 Ubuntu on its Linux filesystem for the Linux CI/capture/export environment. Clone with the command above; CRLF files can break Bash scripts. Keep Linux and Windows import caches in separate checkouts. After installing the native editor, PowerShell can use:

```powershell
$GodotWindows = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
& $GodotWindows --headless --path app --editor --import
& $GodotWindows --path app
# Focused native check; repeat for the affected test scripts:
& $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_simulation.gd
```

Inspect exit status **and** engine errors in logs: Godot can report runtime script errors with exit code zero. WSL results establish Linux behavior, not native Windows GPU or device acceptance. On macOS, open `app/project.godot` with the matching Godot build.

**Linux Wayland:** beta1 can crash while falling back from unavailable X11 to Wayland ([upstream issue #124731](https://github.com/godotengine/godot/issues/124731)); the [follow-up fix #124734](https://github.com/godotengine/godot/pull/124734) merged after this pinned build. In a working Wayland session, bypass X11 with `python3 tools/graphics/launch.py --display-driver wayland`. The launcher forwards that existing engine option. CLI imports, tests and exports should use `--headless`, which selects the headless display driver. Headless WSL import/export checks do not qualify desktop Wayland rendering.

For focused checks, use the [checked Godot runner](../tools/godot/README.md):
`python tools/godot/run_checked.py --timeout 90 -- $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_simulation.gd`
(PowerShell). It retains bounded logs and JSON verdicts, catches zero-exit engine/script/shader errors, and supports required completion text and strict warning checks. `app/test.sh` uses it for its direct Godot calls; `OPENRC_CHECK_OUT` selects the evidence parent. App CI jobs that reach the test step retain diagnostic artifacts for seven days. Run `python tools/godot/summarize.py <collection> --junit <new.xml>` after capture to validate log integrity and export one JUnit case per invocation; see the runner guide for limits and exit codes.

Node 24 (`.nvmrc`) is used by tree-authoring tools and the frozen three.js prototype; the production app and static project site do not require Node. To reproduce the Linux app CI job with Docker and `act`: `act push -P ubuntu-24.04=catthehacker/ubuntu:act-latest -j app`.

Use ignored `tmp/` or `output/` for scratch results and `.playwright-cli/` or `.playwright-mcp/` for browser sessions. Retain accepted evidence under `docs/research/` or `docs/media/`. Local cleanup must preserve source deliveries, `references/`, tool binaries/environments and registered worktrees (`git worktree list`), including those nested in scratch directories.

## App and release commands

| Purpose | Command | Scope |
| --- | --- | --- |
| Engine | `app/get-godot.sh` | Pinned binary and verified download. |
| App checks | `app/test.sh` | Every GDScript parses; unit/session/UI tests, model contracts, traces, replay and frame-rate independence. |
| Offline regressions | `research/test-tools.sh` | Measurement reducers, importers and validation tools. |
| Visual checks | `app/capture.sh` | Rendered cases, image guards, traces and complete manifest in ignored `app/captures/`. |
| Run | `"$(app/get-godot.sh)" --path app` | Home; [controls](FIRST-LAUNCH.md). |
| Quick flight | `"$(app/get-godot.sh)" --path app -- --quick-flight` | Direct Club field runway start; no player preferences. Like Home, it trims every airplane for level flight at 50 % throttle (D6e-R4; technical launches without `--quick-flight` keep the reference trim at the slow start speed). An airplane without landing gear (the X8) gets the hand launch instead (`--start=hand_launch`, X8-07). Add `--start=airborne` for the airborne start (`--start=airborne_half_power` names the same 50 % operating point explicitly on any route), `--aircraft=<catalog-id>`, `--battery=ideal` (constant voltage instead of the default finite pack for aircraft whose catalog entry has `battery_data`, BAT-13), `--rates=full` or `--hud=overlays`. |
| Select landscape | `"$(app/get-godot.sh)" --path app -- --quick-flight --landscape=green_paradise` | Flat grass with an airborne start. `--landscape=club_field` selects the default club; unknown IDs are refused. Home remembers its selection; direct launches ignore it. [Authoring and limits](LANDSCAPES.md). |
| Experimental High | `python tools/graphics/launch.py --profile high` | Temporary Forward+ trial; also available from Home settings. [Scope, launcher and native probes](../tools/graphics/README.md). |
| Club scenery | `app/run-landscape.sh` | Forces scenery on for Club field. Normal launches already default to on; opt out with `-- --scenery=off`. This flag does not select a landscape or add club scenery to Green paradise. |
| Landscape checks | `"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_landscapes.gd` | Loading, keyboard switching, saved selection, restart and lighting isolation. For rendered captures, omit `--headless` and add `-- --capture-landscapes=<absolute-dir>`; inspect both Home and flight images. |
| Live debug bridge | `python3 tools/debug/debugctl.py launch`, then `ui`, `press text=Fly`, `fly aircraft=<id>`, `shortcuts`, `control name=<action>`, `state`, `logs --follow`, `crawl`, `run repro.txt` | Drive a running app from the shell without a mouse: every menu, setting, shortcut and controller action, sticks/truck input, pause/step, telemetry CSV, screenshots, flight logs, live log and events, UI crawl. Isolated profile, 1080p by default, loopback only, debug builds. Bug hunting: `frames` (hitches with causes), `break` (tick watchpoints), `objects`/`soak` (leaks), `profile` (GDScript CPU), `monkey` (seeded UI fuzzing), `logs --summary`; `tools/debug/gdscript_warnings.py` collects the engine's own compiler warnings against a baseline. [Guide](../tools/debug/README.md). |
| Companion solver re-bind | `python3 tools/companions/rebind.py` | After a physics/sim edit: replays the companion tapes on the accepted and current solver; `--accept` re-pins when identical. [Guide](../tools/companions/README.md). |
| Traces, flight logs, physics benches, frame diagnosis | [Physics tools](tools/physics.md), [graphics tools](tools/graphics.md#frame-diagnosis), [shared tools](tools/shared.md#launch-flags) | Commands, result reading and gotchas. [Flight-log manual](FLIGHT-LOGGING.md). |
| Repository size | `python3 tools/repo/check_large_files.py` | Refuses tracked files above 50 MiB not recorded in `tools/repo/large_files.json` and any above GitHub's 100 MiB push limit; run by `app/test.sh` and the opt-in pre-push hook. [Evidence-size convention](README.md#conventions-for-documents). |
| Crash-cost data | `python3 research/crash-economics/build_runtime.py` | Regenerates the accident-cost sidecar after aircraft or price-source edits; `--check` only verifies. Opt-in pre-push check: `git config core.hooksPath tools/hooks`. |
| Process RAM and disk | Checked runner `--resources`; `python tools/godot/storage_audit.py . --out <new.json>` | Optional process RAM/CPU/I/O, system pressure, volume capacity and read-only file-size audit; [setup, limits and usage](../tools/godot/README.md#process-ram-io-and-storage-pt1h-r4). |
| Packages | `app/export.sh` | Windows/Linux/macOS ZIPs, pack smoke checks and `dist/SHA256SUMS`. Preserves exporter-managed native libraries beside Windows/Linux executables. Recreates `dist/`. |

For experimental-aircraft evaluation, `app/test.sh` may report two named physical checks as pending: only the Stik's right-first 240 Hz reference-doublet `|β| ≤ 25°` screen, and the R02 yaw-damping comparison. The Stik screen is an estimated boundary check; D10-R2 recovery, yaw-rate, finite-state and timestep-convergence checks remain mandatory ([D10-R2 decision and evidence](research/flight-dynamics/stik-lateral-directional-2026-10-18/README.md#6-decisions-and-adoption-d10-r2-2026-10-18)). The P-51 ground and handling checks are strict again ([P51-22 resolution](research/p51-realism/P51-22/README.md#resolution--2026-10-16)). Standalone scripts default to strict acceptance:

```sh
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_rudder_authority.gd
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_yaw_damping.gd
```

The [D10-R2 Stik decision](research/flight-dynamics/stik-lateral-directional-2026-10-18/README.md#6-decisions-and-adoption-d10-r2-2026-10-18) and [R02 yaw comparison diagnostic](research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/README.md) explain these pending checks. `app/test.sh` supplies only the corresponding `--allow-known-stik-rudder-sideslip` or `--allow-known-r02-yaw-alpha11` argument to each script. A pending physical check is not a pass.

Before exporting, install both qualified x86_64 native libraries and their matching aggregate receipt through the [native builder's installation workflow](../research/rc-monster-truck/native/README.md#installing-and-exporting). Export rejects a missing platform row, incompatible source/ABI/solver identity or binary hash mismatch. Its Linux host probe also checks the selected native backend and float64 ABI; Windows/macOS resource checks under the Linux editor do not replace target-host execution.

[CI](../.github/workflows/ci.yml) also checks schemas, generated geometry/physics and the Windows/Linux native ground-vehicle evaluators. `app/test.sh` alone does not run every CI check. Software checks do not establish physical aircraft accuracy, radio latency or target-GPU performance.

CI divides app verification into eight unit partitions and one integration job; all nine, plus visual, native and prototype checks, are required for tagged publication. The export job can run once both Linux and Windows native builds pass, independently of the app partitions. Each app job imports its own checkout. The integration job retains every offline/reference check, complete GDScript parse pass, model contract and CLI/replay check. `app/test.sh` without these variables still runs the complete suite. Reproduce one partition with `OPENRC_TEST_PART=units OPENRC_UNIT_SHARDS=8 OPENRC_UNIT_SHARD=0 app/test.sh` (indices 0–7), or the remaining checks with `OPENRC_TEST_PART=integration app/test.sh`. A partition result alone is not a complete app result. `python3 app/tests/test_ci_partitions.py` verifies coverage, invalid selections and failure propagation with a disposable engine stub.

The frozen prototype's separate CI job runs `npm ci`, `npm run typecheck`, `npm test`, `npx playwright install --with-deps chromium`, `npm run capture` and `npm run e2e` from `prototypes/stage0/three/`.

## CodeRabbit reviews

[`.coderabbit.yaml`](../.coderabbit.yaml) configures the hosted GitHub App. Install
[CodeRabbit](https://github.com/apps/coderabbitai/installations/new) with access
only to `bultodepapas/OpenRCsimulator`, then ensure this repository is enabled in
the [CodeRabbit repository settings](https://app.coderabbit.ai/settings/repositories).
Public repositories qualify for [free OSS reviews](https://docs.coderabbit.ai/management/plans#open-source)
without a paid subscription or credit card. `enable_free_tier` does not activate
OSS eligibility; repository visibility and App access do. No CI workflow or API
secret is needed.

New accounts can show a 14-day Advanced trial. Public-repository OSS access is
separate from that trial and continues without a paid subscription. Included
OSS review limits differ from trial limits; check `coderabbit usage --agent`
for current availability. Paid usage continuation is not required for OSS.

Non-draft PRs targeting the default branch receive automatic reviews, including
incremental reviews on pushes. Public repositories with fewer than 10 stars
require a manual trigger under the OSS policy. Reviews pause after five reviewed
commits on an active PR; this pause is separate from OSS quotas and rate limits.
On a PR, comment `@coderabbitai review` for an incremental
review, `@coderabbitai full review` to re-read the entire diff, or
`@coderabbitai configuration` to inspect effective settings. Verify installation
by opening a non-draft PR and checking for the CodeRabbit bot review/check;
an existing PR can use the manual review command. OSS [rate limits](https://docs.coderabbit.ai/management/rate-limits)
still apply. Chat replies require a mention; issue enrichment and planning are off.
The bot applies the repository guidelines and advises reviewers; it does not
replace CI, physical validation or maintainer approval. It aborts a review when
the PR is merged or closed (`abort_on_close`, default on): PRs #6 and #7 were
merged before their reviews finished. Wait for the CodeRabbit check before
merging when you want its review.

### Local CLI and agents

The [CLI](https://docs.coderabbit.ai/cli) reviews local changes before a PR.
Download the official installer (`https://cli.coderabbit.ai/install.sh`), read
it, then run it; it verifies a signed release manifest and installs `coderabbit`
and `cr` into `~/.local/bin`. Sign in once in your own terminal with
`coderabbit auth login` (browser); agents never run the login or handle tokens.
`coderabbit doctor` checks readiness.

- **Claude Code:** install the official plugin with `/plugin install coderabbit`.
  It adds `/coderabbit:code-review`, `/coderabbit:autofix` and the
  `coderabbit:code-reviewer` and `coderabbit:autofix` agents. Do not copy
  `.agents/skills/code-review` into `.claude/skills/`: the name collides with
  Claude Code's built-in `/code-review`.
- **Codex:** uses the skills in `.agents/skills/{code-review,autofix}`, pinned by
  [`skills-lock.json`](../skills-lock.json).

Common commands: `coderabbit review --agent --base main` or `--uncommitted`
before a PR; `coderabbit pullrequest <n> --show-threads --agent` to read the
App's open threads; `coderabbit usage --agent` for quota. A local review sends
the diff to CodeRabbit, so check the scope for secrets first. A
`review_skipped` result is not a clean review.

CLI 0.9.1 `coderabbit config validate` fails with `unknown keyword:
"x-undocumented"` because it compiles the current remote schema strictly. On
2026-10-27 `.coderabbit.yaml` had 0 errors against the same schema with a
non-strict JSON Schema validator. Recheck after `coderabbit update`.

## Release sequence

1. Review the selected diff and retain proof beside the owning research evidence.
2. Run applicable schema/generator, offline, app and visual checks. Export from an isolated Linux checkout; keep unrelated files out of `dist/`. After the last edit under `app/physics`, `app/sim` or `app/failures` (comments included: the pin hashes exact source bytes), run `python3 tools/companions/rebind.py --accept` and commit its three files; an exported build refuses AI companions while the pin is stale ([rebind tool](../tools/companions/README.md)).
3. Add `docs/releases/<tag>.md`. A `vX.Y.Z` tag must match `app/project.godot`; `git describe` supplies package identity. `app/export.sh` takes no version argument.
4. Create the annotated tag on the reviewed commit and push the commit and tag together (for example, `git push --atomic origin HEAD:main refs/tags/vX.Y.Z`). The tag must be visible when `main` exports: `app/export.sh` uses `git describe` and rejects a previous tag that differs from `app/project.godot`.
   CI exports on `main`, `v*` tags and manual dispatch. After checks and release notes pass, `vX.Y.Z` tags publish official releases; suffixed tags publish prereleases.
5. Verify all three archives and checksums. Linux execution and structural pack checks do not replace native OS, GPU, radio or pilot acceptance.
6. Update the [project website](../site/README.md#preview-and-maintain) from the published tag and assets, then verify the English and Spanish download and checksum links on the public page.

[Exported runway smoke and pilot card](research/menu-investigations/UI-06c/README.md) cover the Linux/Xvfb keyboard route, recorded traces, CLI parity and isolated preferences.

## Radio diagnostics

| Task | Command / reference |
| --- | --- |
| Device report | `"$(app/get-godot.sh)" --path app -- --input-report=input-report.json --t=20`; move all connected controls. [F1 format](research/radio-input/F1/README.md). Empty device lists are valid. |
| Filmed latency marker | `"$(app/get-godot.sh)" --path app -- --latency-patch --latency-axis=0 --latency-threshold=0`; [F6a protocol](research/radio-input/F6a/README.md). |
| Calibration regressions | `python3 research/input/d6b-r2/verify.py --out /tmp/d6b-r2-proof`; fresh directory, disposable defect tests. [Contract](research/radio-input/D6b-R2/README.md). |
| Latency video reduction | [research/radio-latency](../research/radio-latency/README.md): campaign manifest, annotated events and original clip identity. |

Callback timestamps are not USB polling intervals or physical stick-to-screen latency. Hardware claims require original device/display observations.

Weather and time controls: [wind](research/wind-implementation/README.md), [atmosphere](research/atmosphere/M5-ATM-2/README.md), [time of day](research/time-of-day-investigations/TOD-05/README.md). Direct examples: `--weather=gusty`, `--weather=turbulent`, `--weather=hot-high`, or `--time-of-day=05:45 --date=2026-03-20`. Home edits persist; direct routes do not use preferences. `app/tests/check_wind_trace.py` and `check_atmosphere_trace.py` validate the corresponding trace formats. For direct v11 standard-column reading, run `python3 app/tests/check_atmosphere_trace.py TRACE.csv --column`; this lane accepts only the calm preset (zero wind, gust and turbulence), not arbitrary weather-v4 settings. Without `--column`, the atmosphere reader retains its custom-atmosphere v6/v10 path.

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

After intentionally changing aircraft/model sources through their owning generators, regenerate model manifests with `python3 research/aircraft-standardization/build_models.py`, then descriptors with `python3 research/aircraft-editor/build_descriptors.py`, and repeat the checks above. Exact aircraft bytes and model-manifest hashes are inputs; honor `.gitattributes` before regenerating. [Byte/EOL lesson](LEARNINGS.md#2026-10-13--cr-01d--run-a-generators---check-at-head-before-regenerating).

Presentation slot/source changes use `python3 research/aircraft-standardization/build_customization.py`, followed by its `--check` and tests. This generator does not rewrite physical model manifests. Exported builds carry a separate closed presentation proof package; `test_presentation_sources.gd` checks its missing/corrupt proof refusals.

`app/test.sh` discovers the focused GDScript suites as part of the full suite. For native Windows, import first using [developer setup](#developer-setup), then run every Workshop suite:

```powershell
# $GodotWindows is the matching native console executable from developer setup.
Get-ChildItem app/tests/test_workshop_*.gd | Sort-Object Name | ForEach-Object {
    & $GodotWindows --headless --path app --audio-driver Dummy --script ("res://tests/" + $_.Name)
    if ($LASTEXITCODE -ne 0) { throw ("Workshop suite failed: " + $_.Name) }
}
& $GodotWindows --headless --path app --script res://tests/test_aircraft_customization.gd
& $GodotWindows --headless --path app --script res://tests/test_smoke_profiles.gd
& $GodotWindows --headless --path app --script res://tests/test_presentation_sources.gd
```

Inspect each suite's assertions and engine errors as well as exit status. Focused passes do not replace the descriptor check, full app suite or physical/pilot acceptance.

`test_workshop_store_interruptions.gd` runs 35 injected save-boundary cases by default. Add `-- --process-cuts` to terminate disposable writer processes at the same boundaries and inspect their filesystem prefixes from the reader process. This optional run exceeds the ordinary unit timeout; run it separately. It creates and removes only unique `user://workshop_store_cuts_*` fixtures and never uses the player library. [AE-03a](research/aircraft-editor/AE-03a/README.md) records the native Windows proof and remaining filesystem/platform limits.

`test_workshop_staging.gd` checks bounded cleanup of handled first-save failures, readback corruption, retained unknown data, reservation/path guards and directory links. It uses isolated `user://workshop_staging_test_*` fixtures; on Windows its link fixtures fall back to directory junctions through the built-in PowerShell when unprivileged symbolic links are unavailable. The retained-data warning in its negative case is intentional. It never reclaims a player lock or scans older staging directories.

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
& $GodotWindows --path app --audio-driver Dummy --script (Resolve-Path research/aircraft-editor/capture_recovery.gd).Path -- --lang=es --size=1280x720 "--out=$RecoveryOut.png" "--evidence=$RecoveryOut.json"
$MassOut = Join-Path (Get-Location).Path 'tmp/workshop-mass-review'
& $GodotWindows --path app --audio-driver Dummy --script (Resolve-Path research/aircraft-editor/capture_mass.gd).Path -- --lang=es --size=1280x720 --text-scale=2 "--out-dir=$MassOut" "--evidence=$MassOut/report.json"
& $GodotWindows --path app --audio-driver Dummy --script (Resolve-Path research/aircraft-editor/capture_thumbnails.gd).Path
```

These examples write ignored `tmp/` evidence; recovery and measurement require their output arguments. Use explicit phase paths from [AE-03c](research/aircraft-editor/AE-03c/README.md), [AE-12/13](research/aircraft-editor/AE-12-13/README.md) or [AE-24d.1](research/aircraft-editor/AE-24d-1/README.md) to reproduce those records. Native captures need a display. Headless companion suites are `test_workshop_drafts.gd`, `test_workshop_recovery_ui.gd`, `test_workshop_mass_edit.gd`, `test_workshop_mass_recipe.gd`, `test_workshop_mass_ui.gd` and `test_workshop_thumbnails.gd`. Recovery injection covers code boundaries; it does not establish hardware power-loss durability.

For Library/profile-copy review, supply `--library-build=<local-bundle-json>` with `--dialog=library|profile-copy`; optional `--favorite` marks that fixture. The helper imports into a unique capture-only library and removes the fixture afterward; it never writes player variants. Captures scroll the saved actions or copy decisions into view. Example: add `--aircraft=gp-extra-300s-60 --scale=1 --language=es --width=1280 --height=720 --text-scale=2 --library-build=C:/captures/build.json --dialog=profile-copy` to the native capture command.

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
