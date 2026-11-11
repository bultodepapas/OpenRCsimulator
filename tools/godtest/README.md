# OpenRC GOD TEST

Automate normal startup, Home selection, real fixed-wing flight, pause/resume and
Home return. The [implementation plan](../../docs/plans/god-test.md) owns remaining
work, step status and evidence. The pilot is experimental; a completed command is
not physical validation or a qualified hardware result.

## Commands

From the repository root, with the pinned Godot editor and prepared imports:

```powershell
python tools/godtest/godtest.py list
python tools/godtest/godtest.py all --dry-run
python tools/godtest/godtest.py run smoke --headless
python tools/godtest/godtest.py run ugly-standard
python tools/godtest/godtest.py run ugly-standard --time night
python tools/godtest/godtest.py run jet-circuit --weather gusty --time sunset
python tools/godtest/godtest.py run ugly-standard --weather calm --sky electrical_storm
python tools/godtest/godtest.py run ugly-standard --phase pause --entry continuous
python tools/godtest/godtest.py run smoke --phase pause --entry isolated
python tools/godtest/godtest.py run ugly-standard --phase landing --entry isolated
python tools/godtest/godtest.py memory --cycles 50
python tools/godtest/godtest.py soak --minutes 30
python tools/godtest/godtest.py fleet --dry-run
python tools/godtest/godtest.py matrix --dry-run
python tools/godtest/godtest.py report tmp/godtest/<run-id>
python tools/godtest/godtest.py resume tmp/godtest/<suite-id> --out tmp/godtest/<fresh-retry-id>
python tools/godtest/godtest.py compare --baseline <run-a> --candidate <run-b> --phase loading
```

Use `--help` on a command for bounds and options. `--out` must name a fresh directory.
Use `--godot <absolute executable>` to override engine discovery. `--manifest <file>`
on `run <scenario>` reads a complete versioned JSON manifest; `--dry-run` prints an
example including all required fields. Unknown fields and unsupported combinations
are refused. `--repeats` is bounded to 1–20; it repeats runs but does not establish
an alternating A/B campaign or statistical confidence.

`all` expands the fixed `all-v1` list. `matrix` is a fixed risk-based screen, not
exhaustive pairwise coverage. `fleet` performs experimental airborne navigation on
the explicitly enumerated fixed-wing profiles; it does not certify fleet takeoffs
or landings. Helicopter and hidden technical variants are not silently included.
Only the stock Stik currently admits the full maneuver/landing attempt.

Continuous `--phase` includes preceding route phases. Isolated phases start from
a fresh accepted flight. The experimental isolated approach/landing fixture requires
the stock Stik, Club Field, an airborne start and calm weather; its one setup reset
is labeled separately from a continuous circuit. Every phase retains whether it was
requested or setup. An isolated stop currently includes descent/touchdown from this
declared approach fixture; it is not a ground-only braking test.

The complete Stik route attempts progressive takeoff, right climb, farmhouse and
flag gates, a five-wall-second menu pause, right circuit, roll, loop, approach,
landing, stopping, lighting changes, Home weather change/reload and clean close.
Maneuver failure remains visible; earlier samples survive. Exit 1 includes partial
coverage or ineligible data. Exit 2 is configuration/tool failure. The command may
finish its collection while reporting an aircraft accident or failed phase.
Landing/contact observations include the minimum supported-wheel runway margin.
An observed wheel outside the runway rectangle is shown separately in JSON/HTML;
completed stopping coverage does not establish a successful runway landing.

## Identity and isolation

The runner copies the current tracked/dirty/untracked app and GodTest bytes into
the run's `source/`, verifies copied hashes and copies prepared imported resources.
It also freezes the existing sustained-input helper. No copied input is a link back
to the working tree. `snapshot.json` records source/import hashes; post-run checks
detect changes to the frozen inputs. `working_tree_changed` describes unrelated
development after the snapshot and does not invalidate the unchanged copied run.
Suite cases share their first verified frozen project and use separate output/profiles.
`--snapshot <prior-run>/snapshot.json` reuses verified frozen inputs without another
project copy. Keep the referenced source directory intact. `resume` keeps valid
cases from a retained suite index and retries failed cases against their original
frozen inputs, preserving the prior attempts and instrumentation choice. A retry
uses the current external supervisor; its identity is recorded separately.
Preparation checks free space with a reserve before copying. Preparation remains
outside timing. Hashing/copying warms OS caches: these are new
process runs with unknown OS-cache state, not OS-cold measurements.

The existing debug launcher owns the process/port and redirects its profile under
the run. Runtime refuses a user-data directory outside it. It seeds fresh run-only
windowed/native-resolution preferences, disables update checks and marks the first
flight hint seen. Normal intro, Home, Fly, menu pause/continue, weather and lighting
Apply routes remain in use. Live radio selection is changed through the ordinary
controller service to keyboard. Crash auto-restart is disabled for visible attempt
boundaries and recorded evidence; no physical law or state trajectory is rewritten.

The launch adds no app user arguments. `OPENRC_GODTEST_CONFIG` activates a debug-only
observer from Startup; ordinary launches allocate no benchmark observer. The source
helpers currently require a source/debug application. Exported release and macOS
profile-isolation adapters are pending and are not represented as qualified modes.

## Measurements and reports

`runtime.json` keeps execution, data, coverage and flight outcome separately.
`events.jsonl` contains phase/selection/pause boundaries; `trajectory.csv` samples
accepted state at at most 10 Hz. The external owner verifies shutdown and checks
engine errors even when the OS exit code is zero. `progress.json` supports bounded
supervision and is not a performance result.

`frametimes.json` has format `openrc-godtest-frames-v1`. It reuses FrameSamples'
bounded v3 stream, percentiles and writer, but its endpoint is a scenario event.
`collection_bound_seconds` is a deadline, not a promised measured duration. Do not
feed this report to the existing fixed-duration native-summary qualification gate.
Phase frames use the phase active at the observed interval end; phase boundary
events retain their own monotonic timestamps. Very short phase percentiles are
exploratory. A whole-session distribution includes loading and pause by design;
phase results keep these separate from active flight. New phase percentiles are
reduced offline from the verified frame stream, avoiding sorting during maneuvers.

`report.json` and `report.html` preserve failed/unsupported phases and explain
ineligibility. The reducer verifies stream sequence, clock continuity, metric shape,
counts, hashes and trailer. Headless data cannot qualify graphics. Requested versus
actual window/viewport dimensions, display/GPU/backend and focus/draw observations
remain separate from physical monitor presentation, which is not measured.

GPU readings and engine allocation counters retain FrameDiagnostics' scope and
availability; engine memory is not process RSS or free VRAM. Optional OS resources
reuse the pinned existing sampler:

```powershell
& .tools/godot-diagnostics-venv/Scripts/python.exe tools/godtest/godtest.py run smoke --resources
```

See [resource setup and limits](../godot/README.md#process-ram-io-and-storage-pt1h-r4).
Resource sampling begins after bridge readiness and cannot prove full-startup RSS
peaks. No screenshots or video readback occur during the timing run.

The comparator currently admits matched complete transition phases only. Full
adaptive-flight geometric equivalence, fixed input-tape rendered replay, repeated
paired statistics and automatic regression promotion remain pending. An eligible
single pair is still an exploratory screen, not a statistical regression verdict.

## Verification

```powershell
python -m unittest discover -s tools/godtest -p 'test_*.py'
python tools/godot/run_checked.py --timeout 60 -- <absolute-godot> --headless --path app --check-only --script res://debug/godtest_driver.gd
python tools/godot/run_checked.py --timeout 60 --require-text 'GOD_FRAME_TESTS: 0 failed' -- <absolute-godot> --headless --path app --script <absolute-repo>/research/performance/godtest/test_frames.gd -- --test-output=<fresh-absolute-output>
```

Runtime changes also use the affected existing startup/frame/controller checks.
Rendered campaigns run serially on named real hardware, at verified 1080p first,
without competing GPU jobs. Follow the owning performance gates and retain failures.
