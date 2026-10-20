# Checked Godot commands

`run_checked.py` wraps the existing Godot CLI with Python's standard library by default. It
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
console executable when diagnosing Godot on Windows, except for the optional
direct-process [RAM/I/O capture](#process-ram-io-and-storage-pt1h-r4). Standard engine flags are
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
`log_bytes` and `log_sha256` identify the retained raw log, including incomplete
prefixes. The digest detects changed artifacts; it is not an authenticity signature.
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
App CI jobs that reach `app/test.sh` validate their collection, export JUnit and
upload `godot-diagnostics-<part>-<shard>` artifacts for seven days, including failures.
Python tools that launch their own subprocesses still own those subprocesses'
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

## Collection summaries and JUnit (PT1h-R2)

Use a dedicated collection for each intended run, then summarize after every
producer has stopped. For example, PowerShell:

```powershell
$checks = Join-Path 'tmp' ('checks-' + [guid]::NewGuid().ToString('N'))
python tools/godot/run_checked.py --out-dir $checks --label simulation --require-text '11 checks, 0 failed' -- $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_simulation.gd
python tools/godot/summarize.py $checks --junit "$checks/results.xml"
```

The summary verifies each immediate run directory's JSON, raw log size/hash,
diagnostic counts and completion policy. Missing, malformed, changed or linked
evidence becomes an error. Downloaded artifacts can move: paths embedded in reports
are never followed. Reports created before `log_sha256` was added must be regenerated.
An empty collection is refused. JUnit output is exclusively created, never replaced.
Choose another XML filename when repeating a summary.

The console prints totals and the first 20 failures with next actions and source
context. XML includes every invocation. Exit 0 means all retained invocations
passed, 1 means a failed/invalid invocation, and 2 means invalid configuration,
empty/missing collection or output failure. Limits: `--max-runs` defaults to 10,000
(hard maximum); `--max-log-bytes` defaults to 64 MiB per log;
`--max-total-log-bytes` defaults to 512 MiB per collection. Metadata is capped at
256 KiB per report and collection entries at 20,000. Processing is offline with
bounded log reads. Regular files at the collection root (such as exported XML)
are ignored; run evidence must be in immediate subdirectories.

JUnit counts **commands**, including imports and parse checks, not GDScript
assertions. A passing collection cannot prove that every intended suite was
launched; the shell/CI exit status remains authoritative for suite completion.
Do not mix old runs into a new collection or use wrapper duration as a physics/GPU
performance measurement. This is a consistency check on trusted local artifacts;
someone editing both metadata and evidence can forge a verdict. The explicit
collection root may be an alias; linked run directories/files are refused.

PT1h-R2 verified 2026-10-19: 38 diagnostic tests passed on native Windows; Linux
passed 37 with the Windows junction test skipped. Both included the real Godot
4.7.2 failure matrix. Seven shell partition regressions passed under WSL. A
separate production simulation invocation passed its 11 checks; a deliberate
zero-exit runtime error produced a failed JUnit case with its source location.
The two-case report correctly contained one pass and one failure. Visual-tool
regressions also cover baseline preservation, lock errors and invalid deadlines;
the investigation records their final result. No full CI or fresh GPU run is
claimed.

## Audit scope

The 2026-10-19 audit reviewed the main test entrypoint, capture runner, input
reporting, flight-log CLI and performance-output lifecycle. Highest priority was
inconsistent failure classification: several integration commands trusted only
Godot's exit code, and the unit log regex omitted shader errors. The checked runner
closes those paths and retains actionable evidence. Existing capture tooling already
checks errors and validates image/manifest identity; it keeps its own contract.

The follow-up [20-source investigation](../../docs/research/debugging-tools-2026-10-19.md)
adds collection integrity/JUnit and repairs the performance-output lifecycle:
`visual_quality_cases.py --performance-only` now requires an empty `performance/`
subdirectory under `--out` (apart from its lock). Existing complete or partial
evidence is preserved; select a fresh `--out` for another run. Nonfinite deadlines
are refused. The existing three-process measurement contract is unchanged.

Input reports still replace an existing requested destination; choose a distinct
path when preserving a baseline. Flight-log report write completion is handled in
the [flight logging tool](../../docs/FLIGHT-LOGGING.md).

For opt-in CPU/GPU counters, bounded frame capture and offline hitch/log diagnosis,
see the [performance tool guide](../../research/performance/README.md#cpu-gpu-and-memory-diagnosis).
After importing the project, `OPENRC_TEST_GODOT=<engine>` also enables the three
production frame-capture regressions in `test_frame_capture.py`; the integration
partition runs them automatically. They test diagnostics off/on and incomplete
retained prefixes, not performance speed.

## Process RAM, I/O and storage (PT1h-R4)

Use `--resources` to sample OS counters outside the game. This reuses the free
[`psutil`](https://github.com/giampaolo/psutil/tree/release-7.2.2) library, pinned
only for this optional feature. Install it in an isolated environment:

```powershell
python -m venv .tools/godot-diagnostics-venv
.tools/godot-diagnostics-venv/Scripts/python.exe -m pip install -r tools/godot/requirements-resources.txt
$GodotDirect = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64.exe').Path
.tools/godot-diagnostics-venv/Scripts/python.exe tools/godot/run_checked.py --resources --resource-interval 1 --resource-disk-path . --timeout 300 -- $GodotDirect --path app
```

On Linux, create the environment with `python3 -m venv .tools/godot-diagnostics-venv-linux`,
then use its `bin/python` for the same pip/runner commands and `"$(app/get-godot.sh)"`
as the executable. Close the game normally within the chosen timeout. All existing
runner log policies still apply. Missing/wrong-version dependencies and invalid
options fail before launch.

| Option | Default and purpose |
| --- | --- |
| `--resources` | Off. Monitor only the directly launched PID; child processes are excluded. |
| `--resource-interval SECONDS` | 1; finite range 0.1–60. Shorter intervals cost more and still miss brief peaks. |
| `--resource-max-samples COUNT` | 600; range 1–10,000. Reaching it stops sampling, not the game. |
| `--resource-disk-path DIRECTORY` | None. Repeat up to eight times for volume free/total capacity; directories must exist. |

The unique run directory gains `resources.json` with timestamps, raw samples,
per-field availability, bounded errors, summaries, tool hashes and invocation/log identity.
`report.json` records its size/hash and coverage. `sampled` means a series was
collected, not that every instant or allocation was observed. `capped`, `partial`
and `no_samples` require reviewing the retained coverage/errors. Telemetry failure
does not change the engine verdict; failed resource publication is explicitly
reported as `unavailable`. `summarize.py` validates engine/log verdicts only and
does not validate this optional resource attachment.

Interpret the counters separately:

- RSS is resident process RAM (Windows working set), including shared pages.
  VMS is virtual address space on Unix and private commit on Windows. Neither is
  Godot's static allocator count, unique physical memory or a leak diagnosis.
- CPU percent derives from cumulative process CPU times and may exceed 100%.
  First samples and counter resets have no usable delta. I/O counters are OS
  process activity, not physical drive throughput; cached reads, pipes and
  platform semantics differ. Deltas cover the sampled window only.
- System available RAM/swap and volume free space include other applications.
  They cannot attribute pressure to Godot. A volume capacity sample is not the
  size of the directory passed to `--resource-disk-path`.
- Unknown, denied, unsupported and invalid values remain `null` with reasons.
  PID identity is checked; the tool never intentionally attaches to a replacement
  process. Use the direct Windows engine `.exe`: `_console.exe` is rejected because
  it launches a separate engine and would understate memory. Other launchers/shells
  are also unsuitable. OS/filesystem calls have cooperative time bounds;
  an unresponsive network filesystem can delay a poll.

For project **file sizes**, the read-only audit needs no dependency:

```powershell
python tools/godot/storage_audit.py . --out tmp/storage-review.json --top 20 --max-seconds 30
```

It identifies the largest files and Godot-related storage categories, plus free
space on the root volume. File bytes are logical sizes per path, not allocated
blocks; hard-linked files count once per path. Exclusions and skipped links are
reported; no symlink/junction entry is traversed, and no content is read or deleted.
Review `.godot` imports, assets and retained captures separately before deciding
what to keep. Run after producers stop for a more consistent snapshot.

The output must be new. Scan limits, unreadable entries and other incomplete
coverage produce exit 1 with a partial report; bad arguments or output failures
produce exit 2. Complete scans exit 0. Use `--help` for traversal budgets and
explicit exclusions. Totals on partial scans are lower bounds of the included
paths, not full project usage. Existing `research/test-tools.sh` discovery runs
the mock/filesystem regressions; the CI integration job additionally installs
the pinned backend and exercises real child allocation and I/O.

Focused verification after setup:

```powershell
.tools/godot-diagnostics-venv/Scripts/python.exe -m unittest discover -s tools/godot -p 'test_*.py'
```

The controlled process test checks an observed RAM increase and a flushed file
write against known allocations. Denied/unsupported counters, PID replacement,
counter resets, bounded samples, scan errors and failed report writes have
separate regressions. Real Godot test classes additionally require
`OPENRC_TEST_GODOT`; a passing resource fixture does not establish a leak-free game.
