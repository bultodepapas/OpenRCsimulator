# Checked Godot commands

`run_checked.py` wraps the existing Godot CLI with Python's standard library. It
fails on engine, script and shader error records even when Godot exits zero. No
code is installed in the game or simulation loop. Import resources before running
project scripts; the wrapper does not change engine options or project settings.

From the repository root, PowerShell:

```powershell
$GodotWindows = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64_console.exe').Path
python tools/godot/run_checked.py --label simulation --timeout 90 --require-text '11 checks, 0 failed' -- $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_simulation.gd
if ($LASTEXITCODE -ne 0) { throw 'Simulation check failed; inspect the reported log and JSON.' }
```

Bash:

```sh
python3 tools/godot/run_checked.py --label simulation --timeout 90 -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script res://tests/test_simulation.gd
```

Pass the entire command after the first `--`, including Godot's own `--` before
application arguments. Commands execute without shell expansion. Use the Windows
console executable when diagnosing Godot on Windows. Standard engine flags are
documented in the [Godot CLI manual](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html).

## Options and evidence

| Option | Behavior |
| --- | --- |
| `--timeout SECONDS` | Positive finite wall-clock deadline; default 60. Timeout terminates the invocation's process group on POSIX or its active process tree on Windows. |
| `--max-log-bytes BYTES` | Stop on output beyond this limit; default 8 MiB. Retain only the bounded prefix and mark it incomplete. |
| `--out-dir DIRECTORY` | Parent for unique run directories; default repository `tmp/godot-checks/`. Never replace an earlier run. |
| `--label NAME` | Human label in JSON and sanitized run-directory prefix. |
| `--warnings-as-errors` | Fail on `WARNING:` records, including Godot leak warnings. Default: record warnings without failing. |
| `--require-text TEXT` | Require a literal, single-line completion marker. Repeat to require multiple markers. Useful for tests that could exit before assertions run. |

Each invocation retains `engine.log` (combined stdout/stderr) and `report.json`
(`openrc-godot-check v1`). The report includes the exact argument array, working
directory, UTC start, elapsed wall time, child exit status, policy, verdict,
diagnostic counts and up to 20 samples with log line numbers and following context.
ANSI colors and indentation do not hide errors. Ordinary embedded mentions such
as `expected ERROR: example` are not error records. Output is replayed to stdout
after completion; failures also print the report path and first diagnostics to
stderr, so redirected parse checks still identify the problem.

`ok` is the verdict. `complete` means the process and output capture finished;
it does **not** mean the test passed. Timeouts, launch failures, log overflow and
capture failures are incomplete. A completion marker supplements the engine/error
checks; it cannot override them. Error counts on incomplete logs describe only the
retained prefix. Logs and reports accumulate intentionally; remove unwanted run
directories explicitly after reviewing them.

| Exit | Meaning / next action |
| --- | --- |
| 0 | Command exited zero and passed the selected log/completion policies. |
| 1 | Diagnostic or missing completion marker; inspect source location/context and full log. Also used for child statuses that cannot be preserved portably. |
| 2 | Invalid runner configuration or unwritable evidence path; correct the arguments/permissions. A child exit 2 is distinguished by JSON `reason=process_exit`. |
| 3–123 | Original child failure status (other than the cases above). |
| 124 | Deadline expired; inspect the last output before raising the budget. |
| 125 | Output limit or runner capture failure; inspect the prefix/`detail`, then fix runaway logging or capture failure. |
| 127 | Executable could not start; verify its path and permissions. |
| 130 | Interrupted; the runner attempted process cleanup. |

Keep stderr enabled in Godot. This wrapper classifies emitted diagnostics; it
cannot detect suppressed messages or prove that assertions ran without a suitable
completion marker. It is for foreground diagnostic commands, not daemon launchers.
Detached children or Windows children whose parent has already exited are outside
the process-tree cleanup guarantee; an inherited output pipe that remains open
fails the run. Headless success does not qualify graphics, hardware or physics.

## Integration and verification (PT1h-R1)

`app/test.sh` uses this runner for import and every command through its `run` /
`run_with_timeout` functions, including parse checks and reference/integration
probes. Existing per-suite time budgets and named pending physical checks remain
in that script. `OPENRC_CHECK_OUT` overrides the shell runner's evidence parent.
Failed app CI jobs upload `godot-diagnostics-<part>-<shard>` artifacts for seven
days. Python tools that launch their own subprocesses still own those subprocesses'
acceptance rules; this change does not silently replace their contracts.

```sh
python3 -m unittest discover -s tools/godot -p 'test_*.py'
OPENRC_TEST_GODOT="$(app/get-godot.sh)" python3 tools/godot/test_run_checked.py NativeGodotTests
python3 app/tests/test_ci_partitions.py
```

The first command runs portable process fixtures; the real-Godot matrix is skipped
unless `OPENRC_TEST_GODOT` is set. `research/test-tools.sh` includes the portable
tests, and the integration partition of `app/test.sh` runs the real-engine matrix.
The shell partition tests require Bash/Linux (use WSL on Windows).

Verified 2026-10-19 with Python 3.11.9 / native Windows and Python 3 / WSL Linux,
using the pinned Godot 4.7.2 build: 21 tests per platform with the native matrix
enabled; seven shell partition tests passed under WSL. Actual engine fixtures
cover clean exit, parse failure, runtime null access and missing resource errors
that exit zero, and a hung SceneTree. Portable fixtures cover colored/indented
script/shader errors on either stream, nonzero exits, warning policy, missing
executables/completion markers, invalid output paths/UTF-8, floods without newlines,
exact byte limits, injected log-write failure, bounded samples with correctly
attributed context, invalid programmatic byte limits, stale-evidence isolation and
timeout child cleanup. The production `test_simulation.gd` passed all 11 checks
through the runner.

Five paired Windows simulation-test processes measured median direct execution
0.275 s and in-process checked execution 0.291 s (about 16 ms supervision overhead;
Python interpreter startup excluded). This is a small local tooling measurement,
not a target-machine physics budget or a full-project acceptance run.

## Audit scope

The 2026-10-19 audit reviewed the main test entrypoint, capture runner, input
reporting, flight-log CLI and performance-output lifecycle. Highest priority was
inconsistent failure classification: several integration commands trusted only
Godot's exit code, and the unit log regex omitted shader errors. The checked runner
closes those paths and retains actionable evidence. Existing capture tooling already
checks errors and validates image/manifest identity; it keeps its own contract.

Two evidence-management behaviors remain explicit follow-ups: input reports replace
an existing requested destination, and performance capture reruns remove previous
same-name outputs. Use distinct output paths/directories when preserving baselines.
This repair does not change those tools' overwrite semantics. Flight-log report
write completion is handled in the [flight logging tool](../../docs/FLIGHT-LOGGING.md).
