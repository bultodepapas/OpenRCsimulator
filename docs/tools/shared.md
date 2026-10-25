# Shared tools

Tools every domain uses: the engine, the test suite, headless runs, flags, traces and CI. Each entry: purpose · when · command · result · gotchas. [Back to the index](README.md).

## Engine

- **Purpose:** download and verify official Godot `4.8-beta1` (a prerelease) into `.tools/`; print its path. Exact CLI identity: `4.8.beta1.official.4d10419ca`.
- **When:** in every command that needs Godot. Never call a system `godot`.
- **Command:** `"$(app/get-godot.sh)"`
- **Result:** prints the Linux x86_64 editor path or Windows x86_64 console editor path under Git Bash; exits nonzero on an archive hash or version mismatch. Cached executable hashes are checked before reuse.
- **Gotchas:** a fresh checkout needs `"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --import` before standalone scripts; `app/test.sh` and `app/capture.sh` import by themselves. `--headless` selects the headless display and Dummy audio drivers. For beta1's X11/Wayland fallback issue and the existing launcher option, see [developer setup](../TOOLS.md#developer-setup).

## Full app suite

- **Purpose:** import, generator checks, a parse check of every `.gd`, every `app/tests/test_*.gd` script (676 on 2026-10-24), CLI/trace/replay and frame-rate-independence checks.
- **When:** before every commit that touches `app/`, and after integrating a script.
- **Command:** `app/test.sh`. One CI partition: `OPENRC_TEST_PART=units OPENRC_UNIT_SHARDS=8 OPENRC_UNIT_SHARD=0 app/test.sh` (shards 0–7), or `OPENRC_TEST_PART=integration app/test.sh`. Evidence goes to `tmp/godot-checks/`; override with `OPENRC_CHECK_OUT=<dir>`.
- **Result:** exit 0 means every step passed. Failing Godot calls print `Godot check failed: … report: <dir>/report.json`; open that report and its `engine.log`.
- **Gotchas:**
  - It takes over 40 minutes on the dev VM. For a quick check, run the affected scripts with the [checked runner](#one-godot-script) first.
  - The parse step launches Godot once per script; if your working tree changes during the run (another session pulls or edits), the result is invalid. Run long suites on a snapshot: `git worktree add --detach tmp/suite HEAD`, then run `tmp/suite/app/test.sh` (copy or hard-link the matching `.tools/Godot_*` binaries and generated `.sha512` cache receipt into `tmp/suite/.tools/` to skip the download; Windows needs both executables).
  - Two named physical checks run in "pending" mode inside the suite (`test_rudder_authority.gd`, `test_yaw_damping.gd`). Pending is not a pass; run alone they are strict. Details: [TOOLS](../TOOLS.md#app-and-release-commands).
  - The script stops at the first failure (`set -e`), and the integration tail runs after the units. One red unit script hides every later result: run `OPENRC_TEST_PART=integration app/test.sh` for the tail, and loop the remaining `app/tests/test_*.gd` through the [checked runner](#one-godot-script) to see all unit failures.
  - Parallel runs require isolated `user://` profiles. On Windows, even with separate profiles, concurrent editor imports in one checkout contend for the native extension's hot-reload shadow DLL. Serialize imports; use separate checkouts for parallel full suites. The documented remaining-unit loop can reuse an already successful import.
  - It does not run the CI-only checks below.

## CI-only checks

- **Purpose:** checks the CI integration job runs outside `app/test.sh`.
- **When:** after changing aircraft data, geometry, schemas or offline tools.
- **Command:** generator checks are listed in [`ci.yml`](../../.github/workflows/ci.yml) step "Generated geometry and physics data match their sources"; run each with `--check`. Offline tool regressions: `research/test-tools.sh`. Schemas: `pip install -r research/aircraft-data/schema/requirements.txt` into a venv, then `python research/aircraft-data/schema/check.py` and `test_contract.py`.
- **Result:** exit 0 each. `research/test-tools.sh` ends with `Offline tool regressions passed`.
- **Gotchas:** on the dev VM `python3 -m venv` cannot bootstrap pip; install with `pip install --target <dir> -r …` and run with `PYTHONPATH=<dir>`.

## One Godot script

- **Purpose:** run one test or probe and fail on engine errors that exit 0.
- **When:** whenever you run a single `.gd` script.
- **Command:** `python3 tools/godot/run_checked.py --timeout 90 -- "$(app/get-godot.sh)" --headless --path app --script res://tests/test_X.gd`. Scripts outside `app/` need an absolute path: `--script "$PWD/research/…/x.gd"`. Parse only: `--check-only --script res://…`.
- **Result:** exit 0 ok · 1 engine diagnostic or missing `--require-text` marker · 2 bad configuration · 124 timeout · 125 output limit · 127 launch failure. It keeps `engine.log` and `report.json` (`openrc-godot-check v1`) under `tmp/godot-checks/`. Full contract: [tools/godot](../../tools/godot/README.md).
- **Gotchas:** `complete` in a report means the process finished, not that it passed. `--warnings-as-errors` is opt-in.

### Write a test

There is no GUT or GdUnit. A test is `app/tests/test_<topic>.gd` that `extends SceneTree`, counts failures, prints `"%d checks, %d failed"` and ends with `quit(1 if _failures > 0 else 0)`; copy [test_simulation.gd](../../app/tests/test_simulation.gd). `app/test.sh` discovers every `app/tests/test_*.gd` automatically; add a per-file timeout in its unit section only if the script needs more than 60 s. Draft new scripts outside `app/` until they parse.

## Launch flags

- **Purpose:** start a session directly, without Home or preferences.
- **When:** to reproduce a bug, write a trace or capture a view.
- **Command:** `"$(app/get-godot.sh)" --path app -- --quick-flight --aircraft=<id> [--start=airborne] [--landscape=green_paradise] [--weather=gusty] [--time-of-day=05:45]`. Headless trace: `"$(app/get-godot.sh)" --headless --path app -- --trace=tmp/t.csv --t=3 [--aircraft=<id>]`.
- **Result:** a trace CSV with the initial state and every 240 Hz tick ([trace contract](../research/trace-integrity/C7-R2/README.md)).
- **Gotchas:**
  - Unknown flags are silently ignored and there is no `--help`: a typo still starts a flight. Confirm a flag exists with `rg -n '"<flag-name>"' app --glob '!captures/**'`.
  - Any user argument selects the direct English route; `--vehicle=` must be the only argument; rotorcraft IDs route to the helicopter session.
  - Documented flags: [TOOLS](../TOOLS.md#app-and-release-commands), [FIRST-LAUNCH](../FIRST-LAUNCH.md). Render/inspection flags used by captures: [graphics](graphics.md#single-capture).
  - In-app keys: F2 overlay presets, F3 developer overlays, F5 reload aircraft data, F10/F11 flight log record/marker, F6–F9 glow engine controls, N rate toggle.

## Evidence summary

- **Purpose:** check the integrity of a `tmp/godot-checks` collection and export JUnit.
- **Command:** `python3 tools/godot/summarize.py tmp/godot-checks --junit tmp/results.xml`
- **Result:** exit 0 pass · 1 failed or invalid invocation · 2 configuration error; prints `N invocations: P passed, F failed or invalid`.

## CI

- **Purpose:** find why a GitHub Actions job failed.
- **Command:** `gh run list --limit 5`, then `gh run view <id> --log-failed | rg -n 'FAIL|Godot check failed'`. Reproduce the Linux app job locally with `act push -P ubuntu-24.04=catthehacker/ubuntu:act-latest -j app` (unverified on the dev VM).
- **Result:** jobs `Godot app (units N)` map to `OPENRC_UNIT_SHARD=N`; `integration 0` to `OPENRC_TEST_PART=integration`.
- **Gotchas:** a partition result is not a complete app result. Diagnostic artifacts are kept for seven days.

## External tools

| Tool | Status |
| --- | --- |
| CodeRabbit GitHub App | Configured by [`.coderabbit.yaml`](../../.coderabbit.yaml); [usage](../TOOLS.md#coderabbit-reviews). |
| CodeRabbit skills in `.agents/skills/` | Need the `coderabbit` CLI, which is not installed on the dev VM. |
| codebase-memory-mcp | Not configured in this repository or on the dev VM; use `rg`. |
| `gh`, `act`, `xvfb-run`, `rg`, Node 24 | Installed on the dev VM. Blender, FFmpeg and `just` are not. |

## Known broken or stale tools

Checked on the dev VM on 2026-10-22; recheck before relying on an entry. Report changes here; owners are the tracks
in the [registry](../README.md#tracks-plans-and-step-ids).

| Tool | Problem | Owner |
| --- | --- | --- |
| `research/validation/dashboard.py --check` | Exits 1: "dashboard is stale". Not run by CI. | VAL |
| `research/flight-test/run.py --only` | Unknown test names are skipped without an error; the run then has an empty profile. | FT |
| `tools/flight_log/flight_log.py` | Default `--godot` is the Windows `.exe`; on Linux always pass `--godot "$(app/get-godot.sh)"`. | FL |
| `research/flight-test/{summarize,spin_state,polar_fit}.py`, `research/flight-dynamics/power-climb/fleet_neutral_point.py` | No argparse: `--help` crashes or runs the full job. | FT, D6e |
| `research/aircraft-standardization/conformance.py` | Overwrites an existing `--out`. | AS |
| `tools/audio/generate*.py`, audio importers | Require exactly `numpy==2.4.6` / `miniaudio`; no shared venv provides them (the visual venv has numpy 2.5.3). | AUD |
| `app/tests/test_mass_trace_contract.py` | Passes, but no runner executes it. | FUEL |
| `app/tests/capture_ground_terrain.gd` | Dead probe; writes to `.tools/gp-work/`. | GP |
| `tools/night-lighting/build.py --check` | Never run by CI or `app/test.sh`. | FW |
