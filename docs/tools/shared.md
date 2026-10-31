# Shared tools

Engine, test and trace workflows used across domains. [Task index](README.md) · [Setup and releases](../TOOLS.md).

## Engine

Use `app/get-godot.sh` for the pinned engine; do not substitute a system installation. It prints the verified executable path on supported hosts. [Developer setup](../TOOLS.md#developer-setup) owns dependencies, native Windows commands and the Wayland workaround.

A fresh checkout, worktree or app copy needs an import before standalone scripts:

```sh
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --import
```

`app/test.sh` and `app/capture.sh` import automatically. Pass `--godot "$(app/get-godot.sh)"` to Python runners that accept it when recording an explicit engine identity.

## Full app suite

`app/test.sh` runs the repository's app checks: generators, all GDScript parse checks, discovered unit scripts and integration/CLI/trace/replay checks. Use focused checks during development, then the required full suite for app integration. The script stops at the first failure.

```sh
app/test.sh
# Reproduce one CI partition; neither command is the complete suite:
OPENRC_TEST_PART=units OPENRC_UNIT_SHARDS=8 OPENRC_UNIT_SHARD=0 app/test.sh
OPENRC_TEST_PART=integration app/test.sh
```

Unit shard indices are 0–7. Without partition variables, the script runs the full suite. Godot diagnostics go under `tmp/godot-checks/` (`OPENRC_CHECK_OUT` overrides the parent); open the failing `report.json` and `engine.log`. Exit zero means the configured software gates passed, including only the [named physical exceptions](../TOOLS.md#app-and-release-commands); pending physical checks are not passes.

For focused diagnosis, `OPENRC_TEST_PART=integration-source`, `integration-parse` or `integration-runtime` selects one integration phase. Each imports safely and is incomplete on its own; CI still uses the combined `integration` partition. Parse/unit runs retain unique source-bound roster receipts, reconciled by the final CI gate. [Local preflight and receipt contracts](../../tools/ci/README.md).

- Use a stable checkout for a long run. A detached worktree at `HEAD` **does not contain uncommitted changes**; ensure the snapshot contains the intended edits and generated outputs, then record its identity. Changes during a run invalidate that result.
- Use separate checkouts and isolated `user://` profiles for concurrent suites. Serialize imports in one checkout; Windows native-extension hot-reload DLLs can contend even with separate profiles.
- Install integration dependencies from the manifests used by [CI](../../.github/workflows/ci.yml), including the X8 generator's requirements. Use a tool-specific environment; do not reuse an incompatible visual/audio environment.
- Honor [`.gitattributes`](../../.gitattributes). A byte mismatch may be an EOL mismatch; inspect `git check-attr` and the generator contract before changing data or attributes. Some artifacts deliberately use CRLF or preserve exact bytes.
- A failed unit hides subsequent results. Run the integration partition or selected remaining scripts separately for diagnosis; do not report that partial set as the full suite.

## CI-only checks

[CI](../../.github/workflows/ci.yml) adds schema, selected generator, offline-tool, visual, native-backend and package gates to the app suite; some generator checks also run locally inside `app/test.sh`. Use the workflow's current commands and dependency manifests for the affected area.

`research/test-tools.sh` runs offline regressions and ends with `Offline tool regressions passed`. Schema commands and requirements live in [the schema guide](../../research/aircraft-data/schema/README.md). CI step “Generated geometry and physics data match their sources” lists its generation checks. These checks do not regenerate accepted artifacts.

## One Godot script

Use the [checked runner](../../tools/godot/README.md) to catch engine, script and shader errors even when Godot exits zero:

```sh
python3 tools/godot/run_checked.py --timeout 90 -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script res://tests/test_simulation.gd
```

Replace the script with the affected test. For scripts outside `app/`, use an absolute `--script "$PWD/research/…/probe.gd"`. Parse-only checks add `--check-only`. Choose a timeout appropriate to the script; `--require-text` can enforce its completion marker and `--warnings-as-errors` is opt-in.

The runner retains `engine.log` and `report.json`. Read `ok` for the verdict: `complete` only means process/output collection finished. The runner guide owns exit codes, output limits and process cleanup.

### Write a test

There is no GUT or GdUnit. Follow [`test_simulation.gd`](../../app/tests/test_simulation.gd): extend `SceneTree`, count assertions, print the failure count and exit nonzero on failure. `app/test.sh` discovers `app/tests/test_*.gd`; add a per-file timeout only when the default is insufficient. Keep drafts outside `app/` until they parse.

## Launch flags

Engine arguments precede `--`; OpenRC arguments follow it. No user arguments opens Home; any user argument selects the direct route without player preferences. Unknown app flags may be ignored, so verify names against current source and confirm the resulting configuration.

```sh
"$(app/get-godot.sh)" --path app -- --quick-flight --aircraft=jensen-das-ugly-stik-60 --start=airborne
# Create a fresh output directory and replace <new-dir>; use an absolute trace path:
"$(app/get-godot.sh)" --headless --path app -- --trace="$PWD/tmp/<new-dir>/flight.csv" --t=3
```

| Selection | Behavior / reference |
| --- | --- |
| `--quick-flight` | Club runway start and level trim at 50% throttle; gearless aircraft use hand launch. Without it, technical starts retain the reference trim. |
| `--start=airborne` / `airborne_half_power` | Airborne start; the latter explicitly names the 50% operating point on any route. |
| `--landscape=green_paradise` / `club_field` | Select landscape; Green paradise uses an airborne start. Unknown IDs are refused. [Landscape guide](../LANDSCAPES.md). |
| `--battery=ideal`, `--rates=full`, `--hud=overlays` | Explicit technical selections; ideal battery applies to catalog entries with battery data. [Controls and modes](../FIRST-LAUNCH.md). |
| `--weather=gusty` / `turbulent` / `hot-high` | [Wind](../research/wind-implementation/README.md) and [atmosphere](../research/atmosphere/M5-ATM-2/README.md) contracts. |
| `--time-of-day=05:45 --date=2026-03-20` | Visual [time of day](../research/time-of-day-investigations/TOD-05/README.md), separate from physical weather. |

Trace output includes initial state and fixed ticks; check identities, completion and expected duration with the relevant [physics trace validator](physics.md#headless-trace-checks). Rendered capture flags live in [graphics tools](graphics.md#single-capture). For input, recording and shortcuts, use [FIRST-LAUNCH](../FIRST-LAUNCH.md) or the [debug bridge](../../tools/debug/README.md), not a duplicated key list.

## Evidence summary

`python3 tools/godot/summarize.py tmp/godot-checks --junit tmp/<new-results>.xml` validates the checked-runner collection and writes one JUnit case per invocation. A failed or invalid invocation makes the summary fail; see [the runner contract](../../tools/godot/README.md#integration-and-verification-pt1h-r1).

## CI

Use `gh run list --limit 5`, then `gh run view <id> --log-failed`. App jobs map to the unit/integration partitions above; diagnostic artifacts are retained for seven days.

The [workflow](../../.github/workflows/ci.yml) owns the dependency graph. Its central source/release preflight precedes expensive work. Export depends on Linux/Windows ground-native builds and the Linux NK-3 build. Publication requires export and `CI required`, which checks the selected job results and parse/unit rosters. Shadow selection keeps all app partitions, visuals and the frozen prototype required; website checks are included when selected. A green export or a single app partition is not a green release. [Orchestration and rollout limits](../../tools/ci/README.md).

## External tools

Use codebase-memory-mcp for code discovery, following [AGENTS](../../AGENTS.md#discover-code); index the repository if needed and verify stored line ranges against current source. Use `rg` for literals, non-code files or insufficient graph results.

[CodeRabbit setup](../TOOLS.md#coderabbit-reviews) owns hosted/CLI review instructions. Other tools and exact dependency versions belong to their own READMEs; availability in one developer's environment is not a repository guarantee.

## Known broken or stale tools

These are operational caveats, not a saved inventory of one machine. Recheck against current source when relevant; report fixes to the [owning track](../README.md#tracks-plans-and-step-ids).

| Tool | Required care |
| --- | --- |
| `research/flight-test/run.py --only` | Unknown names can yield empty or partial results with exit zero. Verify the requested case set against [the card](../../research/flight-test/README.md). |
| `research/flight-test/{summarize,spin_state,polar_fit}.py`, `research/flight-dynamics/power-climb/fleet_neutral_point.py` | Do not probe with `--help`: these entrypoints lack argparse and may treat it as input or execute the job. Read their source/guide first. |
| `research/aircraft-standardization/conformance.py` | Can overwrite `--out`; use a fresh path. [Contract](physics.md#aircraft-conformance-and-unchanged-behavior). |
| `research/validation/dashboard.py --check` | Recomputes a source-bound snapshot, including a Godot collector; stale results need investigation, not an automatic refresh. |
| Audio generators/importers | Install each tool's requirements from [the audio guide](../../tools/audio/README.md); the visual environment is not interchangeable. |
| `app/tests/test_mass_trace_contract.py`, `tools/night-lighting/build.py --check` | Run explicitly for their affected area; not covered by `app/test.sh` or `research/test-tools.sh`. |
| `app/tests/capture_ground_terrain.gd` | Writes `res://../ground_terrain_probe.png` (repository root with `--path app`); prefer [current area checkers](graphics.md#area-capture-checkers) with explicit scratch outputs. |
