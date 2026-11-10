# Checked Godot commands

`run_checked.py` wraps the existing Godot CLI with Python's standard library by default. It
fails on engine, script and shader error records even when Godot exits zero. No
code is installed in the game or simulation loop. Import resources before running
project scripts; the wrapper does not change engine options or project settings.

From the repository root, PowerShell:

```powershell
$GodotWindows = (Resolve-Path '.tools/Godot_v4.8-beta2_win64_console.exe').Path
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

## Fixed-brake legacy gate (GP-12)

`test_fixed_gear_brake_input.gd` requires the strict reference runner. After
importing the candidate project, run it through `app/test.sh` or directly:

```sh
python3 tools/godot/fixed_brake_legacy.py --godot "$(app/get-godot.sh)" --out-dir tmp/godot-checks
```

The runner reconstructs the pinned pre-brake R3 owner and requires all 16
original goldens for the current OS using the verified historical beta1 editor.
It then imports the verified source with the current beta2 editor and compares the
candidate against a same-host beta2 reference. Only after the original golden run,
the disposable reference matches pinned fuel, Avanti, Extra, and Stik input bytes.
The current Extra must reduce to the previous pinned bytes by removing exactly the
two reviewed EX-14i/j additions. Exact-once edits update the glow flight and trace
law declarations, the aero loads law declaration, and the propulsion coefficient
declaration and non-turbine configuration identity. A separately pinned contract
edit admits the Extra's new conventional-wing offset; a pinned decoder edit adds
that value to the normalized model used by the checkpoint configuration hash.
The historical aerodynamic evaluator does not read the new field and retains its
original numerical equations. Original pins and derived overlay bytes are checked
before and after capture; `reference-overlays.json` records their hashes. The
trace and session overlays also have independently pinned hashes.

For each of four aircraft, Godot produces the checkpoint, metadata, CSV, and
three-tick state digests; the runner also compares the complete captured initial
checkpoint, metadata, and CSV values with type-sensitive equality. Values are not
normalized and original goldens are not rewritten. This demonstrates exactness for
the captured no-brake states and ticks only; it establishes neither cross-engine
equivalence nor general equivalence of the historical and current laws.

The historical editor is obtained automatically in `.tools/` on Linux and
Windows x86-64 when absent, with the official archive, executable hashes and
engine version verified. An incomplete or changed cache is retained and fails
closed; a stale `.fixed-brake-beta1.lock` must be inspected before removal.
Use `--historical-godot PATH` to select an already installed beta1 editor.
Both engines are checked against their exact pins before and after the gate.
The runner checks reference pins and candidate source stability, retains full
values and input and engine identities under `tmp/fixed-brake-evidence/`
(`--scratch-dir` overrides this), and runs the candidate unit through the checked
runner. Missing history, inputs, engine identity, or an oracle fails the gate.
The two historical commits, their app blobs and root attributes, and the
repository's `assets/` tree must be available. The CI unit shard fetches only
those Git objects; the isolated historical checkout forbids lazy network access
and verifies all 4,291 paths, modes and object IDs. This comparison is software
verification and does not establish physical validation.

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

## Native Apple Silicon setup and preflight (DT-MAC-02a)

For the existing shared M1, start with the [access and workflow guide](../../docs/tools/macos-m1.md)
for SSH, installed engine/Python paths, isolated workspaces and retained evidence.
The setup below describes acquiring tools in a new native checkout.

From a native ARM64 macOS shell, with Git, Bash, curl, unzip, `shasum`, `file`
and Python 3.11 or newer available, run from the repository root:

```sh
godot_exe="$(app/get-godot.sh)"
app/get-templates.sh
python3 tools/godot/macos_preflight.py --godot "$godot_exe"
```

The editor getter downloads the pinned official 4.8-beta2 ARM64 archive, checks
its SHA-512 and exact engine version, retains its app bundle and returns the
executable path. It checks the cached bundle against a local file manifest on
later runs. It refuses a changed or incomplete editor cache and retains a corrupt
downloaded archive or incomplete extraction for inspection; it does not silently
overwrite them. A stale lock from an interrupted getter also needs inspection.
The template getter verifies the matching official archive and all four installed
files against member SHA-512 pins derived from that authenticated archive, including
on offline warm runs. It uses macOS's `shasum`. Beta2 uses the unmodified official
macOS ZIP; the beta1 universal debug/release swap is retained only for historical
reproduction and is not used by the current presets. A corrupt downloaded template archive is
retained without extraction. A changed or incomplete installed template set is
retained and rejected: inspect it and move it aside before retrying. Cold installs
verify staging and exclusively created destination files under a shared cache lock;
a stale `.openrc-<version>.lock` directory needs inspection before removal.
Neither getter installs Python.

The preflight writes a new uniquely named JSON receipt under
`tmp/macos-preflight/`; `--out-dir DIRECTORY` selects another parent. It records
model, OS build, memory, process and hardware architecture, filtered GPU/display
inventory, editor executable path and hashes/version, and discovered tool paths.
It checks Rosetta for the Python process and, where applicable, tries an ARM64
engine `--version` using `arch`; that forced invocation does not establish the
architecture of a normal GUI launch. Display dimensions come from the system
report and do not establish drawable or render pixels. Serial-number fields from
the display inventory are not written, but the receipt can contain local paths.
Tool paths indicate discovery, not working SDKs. `--dry-run` prints collection
scope without inspecting the host or writing a receipt and works on Windows;
actual collection requires Darwin and `--godot`. Use `--help` for all flags.

The optional `host_state` field reads Foundation thermal state and Low Power Mode
once through the installed `osascript`, capped at 3 seconds and 4 KiB within the
overall budget. Each field distinguishes available, unsupported, unknown and
error; optional failure does not invalidate the core inventory. Memory pressure
remains unknown. This is a preflight snapshot, not a sustained observation or
throttling test; no background sampler or helper is installed.

Exit 0 means the inventory was collected, not that the machine, renderer or
package is qualified. Exit 1 writes a partial receipt with reasons; inspect it
before using the results. Exit 2 indicates invalid setup, a non-Darwin collection
request or an output failure. Collection has bounded command output and a
55-second budget; no dependencies are installed. For an initial checked import:

```sh
python3 tools/godot/run_checked.py --timeout 600 --out-dir tmp/dt-mac-import --label dt-mac-import -- \
  "$godot_exe" --headless --path app --audio-driver Dummy --import
```

On 2026-10-28, portable downloader, template, preflight and correction fixtures
passed on a Windows host with native Python/Git Bash and WSL Linux. Tests requiring
real beta1 editor exports with macOS templates were skipped, as was the FIFO fixture on Windows.
These checks do not establish native Mac execution or GPU performance. Linux
cross-export and its existing release gates still apply.

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

The console prints passed, skipped and failed totals, the first 20 skips, and the
first 20 failures with next actions and source context. XML includes every
invocation. Exit 0 means no retained invocation failed or was invalid; a skipped
invocation is not a pass.
Exit 1 means a failed/invalid invocation, and 2 means invalid configuration,
empty/missing collection or output failure. Limits: `--max-runs` defaults to 10,000
(hard maximum); `--max-log-bytes` defaults to 64 MiB per log;
`--max-total-log-bytes` defaults to 512 MiB per collection. Metadata is capped at
256 KiB per report and collection entries at 20,000. Processing is offline with
bounded log reads. Regular files at the collection root (such as exported XML)
are ignored; run evidence must be in immediate subdirectories.

JUnit counts **commands**, including imports and parse checks, not GDScript
assertions. A passing collection cannot prove that every intended suite was
launched; the shell/CI exit status remains authoritative for suite completion.
A passing script that prints a declared `<subject> SKIPPED: <reason>` line (for
example, the 1920×1080 lighting pixel suites under `--headless`) is reported as a
JUnit `<skipped>` case and counted separately; it never qualifies the skipped
contract. Its exit verdict is unchanged, and a failed invocation stays a failure.
For the two lighting pixel scripts, a successful invocation must have exactly one
matching headless skip message or one terminal zero-failure completion with at
least 12 segment or 13 skin checks and a matching number of successful assertion
lines. The minimum allows counts to grow; it does not prove the assertions are
meaningful. Missing, inconsistent, duplicate or contradictory evidence is
invalid. A genuine engine `--check-only` invocation is a parse check and is
exempt. Headless skips appear in the console and JUnit; a checked-runner failure,
including a missing required completion marker, is never converted into a skip.
The unit roster still records command execution, not pixel assertions. These
reports do not qualify display-backed 1920×1080 rendering or a native GPU. Those
two pixel suites run display-backed in the `quality` capture group; CI-09 remains
open until those rendered checks and their negative controls are qualified. The
capture group validates its checked pixel collection with this same summarizer
before publishing the lighting milestone.
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
$GodotDirect = (Resolve-Path '.tools/Godot_v4.8-beta2_win64.exe').Path
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
| `--resource-max-samples COUNT` | 2,100; range 1–10,000. At 1 Hz this allows launch, 30 s warmup, 1,800 s flight and stop margin. Reaching it stops sampling, not the game; verify actual timestamp coverage against the frame stream. |
| `--resource-disk-path DIRECTORY` | None. Repeat up to eight times for volume free/total capacity; directories must exist. |
| `--resource-threads` | Off. Include thread counts; Windows process enumeration makes this substantially more expensive. |

The unique run directory gains `resources.json` with timestamps, raw samples,
per-field availability, bounded errors, summaries, tool hashes and invocation/log identity.
`report.json` records its size/hash and coverage. `sampled` means a series was
collected, not that every instant or allocation was observed. `capped`, `partial`
and `no_samples` require reviewing the retained coverage/errors. Telemetry failure
does not change the engine verdict; failed resource publication is explicitly
reported as `unavailable`. `summarize.py` validates engine/log verdicts only and
does not validate this optional resource attachment.

`required_coverage` separately reports whether every retained sample includes
process RSS, user/system CPU time and system available memory, with a verified PID
and no cap or sampler stop. Optional process I/O may be `null`/`unsupported` on
macOS. The v1 `coverage` and `measurement_status` fields keep their legacy meaning;
incident and Perfetto reports preserve both. A `complete` required-channel result
does not establish a full flight: compare first/last sample timestamps with the
actual frame capture interval, including launch, warmup and stop margin.

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
  Optional thread counts stay `null` / `disabled` unless requested.
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

### Optional macOS host-state companion (DT-MAC-02e)

Build this developer-only companion before timing, using the installed Apple SDK:

```sh
mkdir -p tmp/macos-host-build
xcrun --sdk macosx --show-sdk-version
xcrun clang --version
xcrun --sdk macosx clang -arch arm64 -fobjc-arc -fblocks -O2 -mmacosx-version-min=12.0 \
  -framework Foundation -framework IOKit -framework CoreFoundation \
  tools/godot/macos_host_state.m -o tmp/macos-host-build/host-state
shasum -a 256 tools/godot/macos_host_state.m tmp/macos-host-build/host-state
file tmp/macos-host-build/host-state
```

Record the compiler, SDK, command, deployment floor and source/binary hashes as
the build receipt. The helper is not installed or started by default. Add
`--resources --host-state-helper "$PWD/tmp/macos-host-build/host-state"` to the
same checked-runner command used for a direct Godot launch. Use the pinned psutil
environment above and the [long capture](../../research/performance/README.md#long-continuous-captures-dt-mac-02b)
workload for a sustained run. Timeout must leave room for launch, warmup and the
entire capture; the companion itself is limited to 3,600 s. Launching a shell or
another wrapper instead of the game makes process resource attribution invalid.

The runner supervises the companion and writes `host-state.jsonl` plus
`host-overhead.json` in its unique run directory. The checked report contains the
capture ID, byte/hash and coverage of the host stream, helper binary hash, local
source hash and overhead receipt. The local source hash does not establish what
the binary was compiled from; retain the build receipt. Helper and local source
hashes and file identities are checked before launch, immediately after launch
and after stop; detected drift or an unreadable file makes host coverage partial.
These checks cannot detect every transient replacement or attest the executed
bytes: use a frozen, run-owned helper path and do not rebuild it during capture.
`host-overhead.json` uses
the same resource sampler for helper and runner CPU/RSS, separately from the game.
They cover their sampled intervals, not necessarily the full frame interval.
Failure or non-Darwin unavailability is reported without stopping a healthy game.

The helper reads Foundation thermal and Low Power Mode before and after
subscription, records later notifications and takes one-second snapshots along
with the IOKit power source. Initial reads, callback observations and snapshot
query brackets are retained. Nominal may be Foundation's fallback for unavailable
thermal awareness; AC snapshots can miss short transitions. Memory pressure is a
Dispatch **event stream** with an initially unknown value. No event does not mean
no pressure; OS coalescing/loss count is unavailable rather than zero. Event
coverage and the last known pressure value are different facts. The helper caps
output at 4 MiB, 4,096 snapshots, 1,024 events and 3,600 s; loss, missing trailer,
failed channels, a two-second snapshot gap or a sleep-clock mismatch make the
receipt partial.
Foundation notification ingress allows one pending callback per type; suppressed
or pending-at-stop callbacks are counted as local drops and make it incomplete.
The native fixture can test this without inducing system pressure:

```sh
OPENRC_TEST_MAC_HOST_HELPER="$PWD/tmp/macos-host-build/host-state" \
  python3 -m unittest discover -s tools/godot -p 'test_macos_host_state.py'
```

This injects notifications only into the helper process. Its `--test-flood` run
is explicitly marked as test mode and the measurement validator refuses it.

The current host stream uses macOS `CLOCK_UPTIME_RAW`, the same underlying clock
as the supported Godot and CPython 3.9 macOS monotonic implementations. The
runner passes the verified helper path and SHA-256 to Godot and opts all three
resource samplers into bounded raw-uptime anchors. The companion also exposes
`--clock-sample` for the frame collector's bounded, pre-warmup and post-seal
anchors. Unsupported clock APIs or failed probes leave alignment unavailable;
the healthy game keeps running. UTC anchors remain approximate annotations, and
their drift does not validate the direct raw clock. Host v2 separately brackets
the difference between sleep-inclusive `CLOCK_MONOTONIC_RAW` and raw uptime;
more than 50 ms of possible change makes coverage partial. Host v1 retains its
original UTC-drift rule and does not acquire new clock evidence retroactively.

The frame collector accepts only the exact official Godot 4.8 beta1
`4d10419cacd6d3009976e8f9fd3abd970fd58018` and beta2
`cafc17a192acf67903910a68aeb3c076c0907a4b` metadata. Their
[beta1](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/drivers/unix/os_unix.cpp)
and [beta2](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/unix/os_unix.cpp)
macOS tick implementations use the same Mach clock; Apple's
[clock implementation](https://github.com/apple-oss-distributions/Libc/blob/main/gen/clock_gettime.c)
maps `CLOCK_UPTIME_RAW` to that source. Version metadata is not binary attestation:
retain the executable identity and preflight. A new native run must establish
both raw anchors and their join; this change cannot repair earlier missing anchors.

All streams share the runner capture ID. Compare helper readiness and endpoint,
and first/last process-resource samples, to the entire actual frame capture
interval using their bounded raw-offset intervals. `coverage=complete` describes the
helper's own observations and does not establish that they covered the flight,
that pressure began normal, or that instrumentation was inexpensive. Run the
documented diagnostic-on/off controls before using the results for performance
claims. The generic incident/Perfetto reducers do not ingest this host stream.

## Incident bundles and Perfetto timelines (PT1h-R5)

Capture frame diagnostics and OS counters in the **same checked invocation**:

```powershell
$GodotDirect = (Resolve-Path '.tools/Godot_v4.8-beta2_win64.exe').Path
$Frames = Join-Path (Get-Location) 'tmp/incident-frames.json'
.tools/godot-diagnostics-venv/Scripts/python.exe tools/godot/run_checked.py --resources --resource-interval 1 --timeout 180 -- $GodotDirect --headless --path app --audio-driver Dummy --max-fps 60 -- --scripted "--frametimes=$Frames" --frame-diagnostics --warmup=1 --t=10
```

Use a fresh frame-output path for each capture. The runner prints the unique run
directory. Replace `RUN_DIR` below with that directory; the two offline tools use
only Python's standard library and never launch the game:

```powershell
python tools/godot/incident_bundle.py RUN_DIR --frames tmp/incident-frames.json --out tmp/incident.zip --note "Describe the trigger and expected behavior"
python tools/godot/perfetto_export.py --frames tmp/incident-frames.json --resources RUN_DIR/resources.json --out tmp/timeline.json
```

An incident bundle can be complete even when its captured run was skipped. For a
verified lighting pixel skip, `run.status` is `skipped` and `run_ok` is false;
the console identifies the run as skipped and unqualified.

Open `timeline.json` in [Perfetto](https://ui.perfetto.dev/) with **Open trace file**.
Frame slices represent wall intervals, including waiting; counter names include
units. Process CPU, RSS, I/O, system memory and volume capacity retain their
separate meanings from the resource guide above. GPU zero readings are omitted
as unavailable-or-zero. Headless runs cannot establish GPU performance. Viewport
timers may describe a previous render frame; coincident spikes do not prove cause.
Remove `--headless` for a visible capture with the active graphics backend.

Combined timelines require matching nonempty capture IDs and two clock anchors
from both producers. Each timeline keeps its monotonic durations; UTC anchors
only estimate alignment across processes. The trace records uncertainty and
observed drift. The 20 ms per-anchor floor is an estimate, not an OS guarantee;
brief clock excursions between anchors can escape detection. Detected drift
beyond the allowance rejects the merge. `--max-clock-drift-ms` defaults to 50
(range 0–1,000), in addition to anchor uncertainty. Avoid using this alignment
to attribute individual short frames to OS samples. Older reports can be viewed
one at a time with just `--frames` or `--resources`.

The exporter validates v2 reports and complete v3 report/sidecar pairs. A v2
retained prefix is marked partial; incomplete or damaged v3 streams are rejected
by the same strict reader used by the long-capture reducers. Unknown values are
never converted to zero; unknown metric names are listed in trace metadata.
The combined input budget defaults to 320 MiB (`--max-input-bytes`, maximum
1 GiB); each JSON document is limited to 256 MiB. The sidecar separately has
the shared reader's 256 MiB limit, and retained numeric arrays have a 128 MiB
limit. The event budget defaults to
500,000 (`--max-events`, maximum 1,000,000). If a timeline would exceed that
budget, choose a frame window and/or counters; nothing is silently sampled:

```powershell
python tools/godot/perfetto_export.py --frames tmp/long-frames.json --out tmp/window.json --start-frame 60000 --end-frame 90000 --frame-metric draw_calls --frame-metric physics_step_usec
```

Frame indexes are zero-based, start inclusive and end exclusive. Slices retain
their original indexes and timestamps; selected counters are exact for that
window. Trace metadata records the full source frame count, selected indexes,
monotonic bounds, selected/omitted tracks, clock anchors and uncertainty. For v3
it also records the report and sidecar hashes. Resource tracks retain all their
samples and declare that scope. For combined sources, estimated timestamp
bounds show whether resource samples bracket the full and selected frame windows;
uncertainty applies and discrete samples do not prove coverage between them.
Metadata marks a selected timeline as incomplete
for the full session while recording whether its scope and source are complete.
Requested metric names must exist in the source. The exporter exits 0 for a
successful complete or explicitly selected scope, 1 for partial v2/resource
evidence or invalid sources, and 2 for configuration, budget or output errors.
Invalid sources and budget failures produce no trace. All output paths must be new.

An incident ZIP contains only the checked receipt, engine log, declared resource
attachment and explicitly selected frame/flight-log attachments. It includes a
manifest with hashes, association checks and missing/corrupt evidence. It never
recursively collects the run folder. `--flight-log PATH.orfl` preserves an opaque,
caller-selected attachment; packaging does not validate replay or prove that the
flight log belongs to this run. The [flight logging workflow](../../docs/FLIGHT-LOGGING.md)
remains authoritative for replay. Logs, command arguments and paths are retained
verbatim; the tool does not upload them.

Bundle completeness and the engine verdict are separate: successfully preserving
a failed run does not make the run pass. Review the manifest and console summary.
The bundle exits 0 when complete, 1 when evidence is partial, and 2 on
configuration/output errors. Its per-file budget is 256 MiB (`--max-input-bytes`,
maximum 256 MiB), with 512 MiB total (`--max-total-bytes`, maximum 1 GiB).
Oversized attachments are omitted with a manifest issue. Stop capture producers
before packaging so their files form a stable snapshot.

A v3 `--frames` report and its declared same-directory sidecar are copied into
`frames/` under their original sibling names. The shared reader validates their
counts, sequence, hash, values, endpoints and completion before the bundle marks
the pair valid. A damaged or incomplete pair is retained when readable and within
budget, with an explicit invalid/partial status. To retain an abrupt-crash sidecar
when no report exists, use `--frame-stream PATH.frames.jsonl`. It may accompany
`--frames` to preserve a missing or malformed report receipt as well, but never
replaces the declared sidecar of a valid v3 pair.
That attachment is opaque: its frame range, validity, capture association and
completion are unverified, regardless of its file hash. It is never accepted as
a complete stream by the reducers or timeline exporter. See the
[long-capture reducers](../../research/performance/README.md#long-continuous-captures-dt-mac-02b)
for capture and soak rules. After extracting a bundle, place a copy of its
`engine.log` next to the frame report with the report's basename and `.log`
extension for reducers that require the matching log. Required-resource coverage is checked against its
channel counts, sample statuses and stop reason when those fields are present;
older declarations without counts are retained as unverified.

## Repeated scene lifecycle checks (PT1h-R6)

After importing the project, run a fresh-process, headless Home → flight → Home
and Workshop open/close check:

```powershell
python tools/godot/lifecycle_check.py --godot .tools/Godot_v4.8-beta2_win64.exe --scenario both --cycles 3
```

Linux: use `python3` and `--godot "$(app/get-godot.sh)"`. Add `--resources` using
the pinned psutil environment above for process RAM, CPU and I/O. The command
prints a unique directory under `tmp/godot-lifecycle` containing `summary.json`,
`probe/lifecycle.json`, isolated preferences, and the checked engine log/receipt.
No diagnostic code is loaded during normal play. Player preferences, controller
profiles and Workshop variants are isolated from this probe.

| Option | Default and meaning |
| --- | --- |
| `--scenario` | `both`; select `flight` or `workshop` to narrow a failure. |
| `--cycles` | 3 measured cycles; range 2–30. |
| `--warmup-cycles` | 1 full cycle before the baseline; range 1–5. |
| `--settle-frames` | 8 frames per checkpoint; range 3–300, plus deferred-cleanup frames. |
| `--dwell-seconds` | 0.25 extra seconds per checkpoint; range 0–10. |
| `--timeout` | 300 seconds for the engine; maximum 3,600. |
| `--max-node-growth`, `--max-orphan-growth` | 0; allowed increase over the settled baseline, range 0–10,000. |
| `--max-static-growth-mib` | Disabled; optional allocator-growth budget, range 0–4,096 MiB. |
| `--out-dir` | Parent directory for fresh run folders; existing captures are preserved. |

The check compares equivalent settled Home states after warm-up. It fails for
excess node/orphan growth, selected retired objects still alive, engine errors,
incomplete evidence, or ObjectDB/resource shutdown leak warnings—even when Godot
exits successfully. Ordinary warnings remain visible without failing the check.
Exit codes are 0 passed, 1 failed/incomplete, and 2 configuration/output error.
`complete` describes capture coverage independently of `ok`.

Object/resource counts and static allocator bytes are recorded as trends. Static
memory is not process RSS; startup caches and the probe's retained samples can
increase it. A passing run checks these routes and selected object lifetimes,
not every reference or a long gameplay session. Flight is paused before return;
this is not a physics, GPU or frame-performance benchmark. The debug engine is
required because release counters cannot establish these checks.

The observer retains IDs and strings rather than owning inspected objects.
Orphan inventory stops above 2,048 nodes, details are capped at 20 per sample,
and truncation is explicit. JSON input is capped at 4 MiB and the warning scan
at 8 MiB; oversized or unreadable evidence cannot pass. Reports include capture
identity and source/report hashes. Checkpoints preserve an incomplete prefix on
transition failure; a killed process or failed write may leave no usable prefix.

For attribution, use Godot's existing
[ObjectDB Profiler](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/objectdb_profiler.html):
take snapshots at the same settled Home state before and after repeated routes,
then compare classes and inspect retained references. Reproduce the reported
route first; a count increase alone does not identify its owner.

The integration partition runs disposable real-engine fixtures covering clean
transitions, an intentionally retained Workshop node, a failed return to Home,
invalid options and output preservation. Run them directly with
`OPENRC_TEST_GODOT` set to the direct engine executable:

```powershell
$env:OPENRC_TEST_GODOT = (Resolve-Path '.tools/Godot_v4.8-beta2_win64.exe').Path
python -m unittest discover -s tools/godot -p 'test_lifecycle*.py'
```

The slower production smoke additionally requires `OPENRC_TEST_LIFECYCLE_NATIVE=1`.
Recorded results and remaining uncertainties live in the
[diagnostic evidence](../../docs/research/visual-quality-implementation/VQ-01c/diagnostics/README.md#pt1h-r6-lifecycle-retention-checks).
