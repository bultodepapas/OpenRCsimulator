# PT1h-R14 — Internal debug tools: contracts and recovery

Reviewed **2026-11-07**. Baseline: [`9db50cfc70904e262247d97e1c368f7c499ff23d`](https://github.com/bultodepapas/OpenRCsimulator/commit/9db50cfc70904e262247d97e1c368f7c499ff23d), the preceding tool-review candidate in [draft PR #10](https://github.com/bultodepapas/OpenRCsimulator/pull/10). This review focuses on the internal debug stack, its consumers and failure recovery. It changes no simulation equations, aircraft data, engine pins or golden flights.

**2026-11-08 follow-up:** the repairs were integrated into the native working checkout and D14 was repaired. See
[native integration and current limits](#native-windows-integration-and-d14-follow-up-2026-11-08).
The original review, inventory and `verification.json` below describe the historical `644f4e7` candidate;
their source hashes and open-item statuses are not current-checkout receipts.

## Outcome and review boundary

Thirteen newly established defect groups have focused repairs. One additional warning-scanner listener-ownership defect is demonstrated with a competing synthetic server and remains unimplemented. The principal improvements are truthful command completion, preservation of diagnostic files and reproduction trails, isolated concurrent sessions, and correct unavailable-data reporting.

The [consolidated audit queue](../../../../external%20Audits/CONSOLIDATED-AUDITS.md) and [implemented-work ledger](../../../../external%20Audits/COMPLETED-AUDIT-WORK.md) were read before review. The October debug-gap review, November render/rewind review, tool guides, implementations, callers, tests, configuration, GitHub history and related PRs were cross-checked. The existing design has useful foundations: opt-in debug builds, main-thread scene mutation, network-thread liveness/logs, exact session-owned checkpoint validation, bounded normal log/frame rings and an engine-diagnostic-aware test runner. These remain in place.

This is executable contract verification with actual debug code and controlled sessions, not a full-app flight campaign. The source-only checkout omits large assets. Local fixtures retain actual debug implementations but substitute two unrelated dependencies: the landscape ID catalog and the language preference roster. The existing broad bridge suite additionally seeds its aircraft ground-start cache to avoid loading scenery through the catalog. Its protocol/UI assertions run, but that cache does not qualify real aircraft start capabilities. The project retains its input/physics settings while asset-dependent autoload, translations and editor plugins are disabled. Initial runs with missing resources or incomplete fixture settings are recorded as inconclusive, not passes.

[Verification and source identities](verification.json), [complete internal inventory](inventory.json), and the [repeatable checkpoint experiment](checkpoint-repro/README.md) contain the evidence boundaries. No target-device performance improvement, native Windows pass, crash-durability guarantee or physical validation is claimed.

## Inventory: actual workflow and ownership

The inventory contains **58 bridge commands**, **22 scenario scripts**, **three sibling cleanup files**, and a per-file source manifest. Maintained entry points remain in the [debug guide](../../../../tools/debug/README.md); this dated record does not create another command reference.

| Family / source | Users, entry point and inputs | Outputs, dependencies and workflow |
| --- | --- | --- |
| Live bridge — `app/debug/debug_bridge.gd` | Developers, tests and coding agents; opt-in `AppRoot` child; newline JSON commands, expressions, input events and absolute output paths | Structured state/results, UI operations, samples, screenshots and files. Depends on live session, scene tree, catalogs and engine. Network thread serves `help/ping/logs/state`; main thread owns scene changes. |
| Session client — `tools/debug/debugctl.py` | `launch/status/ready/stop/clean`, explicit/default ports and engine arguments | Session claims, current pointer, process/log/run files. Python standard library, pinned Godot, local TCP; used by humans, MCP and test/benchmark callers. |
| Reproduction automation — same client plus `scenarios/` | `run/smoke/soak/monkey`, UTF-8 command files, cleanup files, seeds and cycle counts | Exit verdicts, attempted-action trails, log/object deltas and smoke summaries. Drives the bridge; `research/test-tools.sh` exercises Python tests. These are software checks, not physical controller qualification. |
| MCP — `tools/debug/mcp_server.py` | Agent stdio JSON-RPC and declared tool schemas | Text/image tool responses and bridge/client calls. Prior PT1h-R13 request/Unicode/stop-result repairs are retained; no duplicate MCP implementation. |
| Log capture — `app/debug/debug_log.gd` | Godot logger callbacks and bridge events | Sequence-addressed records, grouped errors and profiler windows; mutex-protected ordinary ring feeds `logs`, reports and JSONL. Profiler callback byte bounding remains open. |
| Render diagnosis — `app/debug/render_probe.gd` | `render/layers/ablate/viewmode`, viewports and optional toggles | Raw observations, availability/validity labels, layer census and owned-state restoration. Existing invalid/stale GPU attribution repairs remain authoritative; no new GPU campaign. |
| Temporal debugging — `app/debug/rewind_ring.gd` | Armed tick-boundary capture; cadence, retention, attempt and target time/tick | Checkpoints and attempt summaries; restore delegates to session validation. Paused/stepping intervals do not capture. |
| Flight visualization — `app/debug/flight_gizmos.gd` | `gizmos`, selected layers, pose, float64 state, last loads, wind and air data | Render-only arrows, trail, label and machine-readable values. Uses the NED/FRD-to-render mapping; never feeds results into physics. |
| Checkpoints and BugIt — bridge plus client | `checkpoint save/load`, `bugit`, `bugitgo`; session carrier, absolute path or report folder | Verified UTF-8 checkpoint, source/context report and optional screenshot. Actual simulation compatibility and float64 restoration belong to `FlightSession`, not this file writer. |
| Compiler diagnostics — `tools/debug/gdscript_warnings.py` | File patterns, optional comparison/updated baseline and output paths | Godot LSP diagnostics and JSON; snapshot by default, explicit in-place mode. Baseline keys intentionally ignore moved line numbers. Listener ownership remains a separate gap. |
| Checked execution — `tools/godot/run_checked.py`, `app/get-godot.sh` | Engine command, timeout, required completion text and warning policy | Bounded logs, engine/source identities and JSON verdict. An exit-zero script with engine errors fails. Reused throughout this review. |
| Regression coverage — `app/tests/test_debug*.gd`, `test_render_probe.gd`, `tools/debug/test_*.py` | Loopback TCP, fake sessions, temporary files and injected failures | Focused assertions; GDScript files are discovered by `app/test.sh`, Python files by `research/test-tools.sh`. Native/full-app gates remain separate. |

## Prioritized findings

**Fixed** means implemented and locally verified within the stated fixture scope; it does not mean merged or full-CI-qualified. Every D item below is newly established here. No confirmed reintroduction of an earlier repaired issue was established.

| ID / priority | Affected file and function | Reproduction and practical impact | Disposition |
| --- | --- | --- | --- |
| **D01 / P1** | `debug_bridge.gd::_cmd_checkpoint`, `_write_checkpoint_file` | Under a real 64-byte file-size limit, the old save returns success after truncating an existing checkpoint. `get_error()` can still report OK. Unicode characters also undercount the encoded bytes. | **Fixed:** verify a sibling's exact UTF-8 bytes before publication; preserve old output on short write, destination-link meaning and Unix mode. Windows keeps a verified recovery copy. |
| **D02 / P1** | `debugctl.py::reserve_port`, session reads/writes/removal | Pause the first exclusive-create writer before JSON reaches its file. A second launcher treats the empty claim as stale and claims the same port. | **Fixed:** persistent OS lock serializes cooperating claim creation, publication, stale takeover and cleanup; process death releases the lock. |
| **D03 / P1** | `debugctl.py::clean` | With two tracked live sessions, `clean --keep 0` protects only the current session and deletes the other's run directory. | **Fixed:** protect every tracked live output; defer deletion while a live launch has not published its output path. |
| **D04 / P1** | `debug_bridge.gd::_cmd_step`, `_finish_step`, pending cleanup | A faulted simulation at tick 10 returns successful `step ticks=5` at tick 10. A 20→25 request paused at 22 also reports success. Global target state lets pending replies confuse separate jobs; timeout/disconnect originally lacked cancellation. | **Fixed:** job-owned result and exact target predicate; fault/reset/session/simulation/stop-owner checks; timeout/disconnect cleanup; preserve external boundaries. Step-time checkpoint saving is refused and rewind capture is suspended. |
| **D05 / P2** | `debug_bridge.gd::_process` | A dropped peer and its queued `time_scale`/`wait` request occur in the same drained batch. Cleanup runs first, then the command mutates state or recreates orphan pending work. | **Fixed:** discard that peer's queued commands. Deterministic queue injection establishes the ordering defect; the test is not presented as an organic disconnect-timing measurement. |
| **D06 / P2** | `debug_bridge.gd::_read_client` | A 1,048,577-byte JSON line is rejected without a newline but accepted with one; real TCP sends 1,048,578 bytes including the newline. | **Fixed:** apply the same byte bound before decoding a complete line. Exactly 1,048,576 bytes before newline remains accepted. |
| **D07 / P2** | `debug_bridge.gd::_number`, step/rewind argument conversion | `"1e400"` passes syntax validation and converts to infinity, unlike direct nonfinite input. Huge finite retention/cadence can overflow integer conversion. | **Fixed:** finite check after conversion; cap retention before integer conversion; refuse unrepresentable tick interval/target. Valid numeric strings and underflow-to-zero parsing retain their behavior. |
| **D08 / P2** | `rewind_ring.gd::capture/restore`; bridge `_cmd_rewind` | Tick-decrease-only logic misses accepted equal/forward restores. Also N snapshots span only N−1 intervals: default 240 samples at 0.25 s span 59.75 s, not 60 s. | **Fixed:** accepted-reset signal defines attempts, with guarded owned restore and cleanup; default capacity becomes 241 and the existing 100,000 cap remains. |
| **D09 / P2** | `flight_gizmos.gd::update_from`, `_arrow`, trail lifecycle | Unavailable wind is reported as calm; nonfinite air creates invalid vertices/fabricated air-relative force values. Zero airspeed or `axis_m=0` ends a surface with no vertices and logs engine errors. Equal/forward resets join unrelated trails. | **Fixed:** null unavailable values, omit dependent geometry, finalize only nonempty surfaces, clear stale values/trails at accepted boundaries. Actual calm and finite numerical controls remain valid. |
| **D10 / P2** | `debugctl.py::monkey` | A fake TCP bridge drops during the first attempted action. Follow-up diagnostics throw before the trail is saved. | **Fixed:** save the attempted-action trail on connection failure; retain status 2 and useful failure context, including startup/action/log/frame/final-state stages. |
| **D11 / P2** | `debugctl.py::run_script`, `_run_cleanup`, `soak` | Under simulated CP1252, actual `settings_revert.txt` sends `1920 Ã— 1080` instead of `1920 × 1080`; the selection is refused. | **Fixed:** explicit UTF-8 file reads. Locale simulation is not a native Windows pass. |
| **D12 / P3** | `debug_log.gd::since` | Cursor INT64_MAX overflows `after + 1` and returns old log records. | **Fixed:** under the mutex, return empty for a cursor at/after the newest sequence or a nonpositive limit. Filters/wrapping/multiline profiler controls pass. |
| **D13 / P1** | `gdscript_warnings.py::main`, output validation/publication | `--out` can replace a `.gd` input with JSON. Using one path for `--baseline` and `--write-baseline` rewrites the comparison before counting new warnings, changing the witness's exit 1 to 0. | **Fixed:** reject source/report/baseline aliases before collection, compare old keys even during explicit refresh, publish each UTF-8 file through staging. Preserve existing files on tested failures and clean only owned snapshots. |
| **D14 / P2** | `gdscript_warnings.py::Lsp.__init__`, `collect` | A foreign fake LSP listener already owns the requested port; the launched editor stub exits 9. The collector connects to the foreign listener and accepts empty diagnostics without polling its own process. | **Open, confirmed conditional input:** qualify listener ownership and editor lifecycle before accepting diagnostics. This does not establish that a real Godot collision occurred. |

The open D14 [conditional witness](lsp-listener-repro.py) runs with Python and a temporary local fake listener; exit zero means the defect was reproduced, not that a scan was qualified.

## Why the corrected contracts hold

### Checkpoint publication

The required success condition is `published_bytes == session_checkpoint.encode(UTF-8)`. Neither process exit zero nor a successful `store_buffer` establishes it. The candidate closes and reopens the sibling, checks its length, and compares every byte before replacing the named target. Normal Unicode save/load, a 240-byte basename, mode preservation and destination-link behavior have separate controls. Ten retained cases include directory links followed by `..` and refusal of a missing intermediate directory without changing an unrelated file. The limited-write experiment preserves the previous checkpoint and leaves no staged file.

A short random sibling basename avoids introducing a filename-length regression. Existing destination links resolve to their targets before staging; cycles/unresolvable links fail without replacing the link. Existing Unix mode bits are applied before publication. These controls were added after independent review exposed flaws in the first candidate; they were not silently counted as baseline defects.

The exact pinned engine matters: its [Unix rename](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/unix/dir_access_unix.cpp) uses `rename`, while its [Windows implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/windows/dir_access_windows.cpp) removes an existing target before `MoveFileW`. The candidate therefore retains a verified Windows recovery copy and attempts rollback on publication failure. A failed rollback identifies the recovery path; failed cleanup after success reports the retained copy. Native Windows failure injection, extended attributes/ACL preservation, concurrent external writers, and sudden-power-loss durability are not qualified. Exact readback costs O(B) time and temporary memory for B checkpoint bytes; no latency saving is claimed.

### Step ownership and truthfulness

A request owns its `(session, simulation, start_tick, target_tick)` and result. Success requires the same active session/simulation, no accepted reset, ownership of the stop boundary, no fault and `tick == target_tick`. A separate completed result prevents a later job from changing an earlier reply. Cleanup only releases the stop still owned by the request; a replacement boundary or newly reset unowned run remains with its new owner.

A reset notification only marks interruption; it does not mutate protected state during reset publication. Pending checks resolve it afterward. A temporary step stop must not become a normal resumable checkpoint: save/load is refused during the step and the rewind ring does not capture that interval. This is an explicit usability tradeoff, including gaps during long steps. A later enhancement could normalize transient metadata in a duplicated checkpoint only after its replay contract is independently verified.

### Rewind duration and discrete boundaries

Let `h` be physics ticks per second, `e=max(1, round(every_s*h))`, and `K=keep_s`. Sample spacing is `e/h`, and N snapshots span `(N−1)e/h`. Thus an uninterrupted, warmed ring needs

`N = ceil(K*h/e) + 1`.

The bridge caps N at 100,000 before integer conversion. At an arbitrary tick between samples, the newest sample is at or before now; the extra endpoint leaves an oldest sample at or before the requested past moment. This argument assumes admitted captures in one continuous attempt; refused captures, pause/step gaps and capped capacity can reduce available history. `summary` remains the authority for what is actually stored.

An accepted session boundary is independent of whether its tick decreases. The ring listens while associated with an armed session, coalesces repeated unsampled boundaries, excludes its own restore from opening another attempt, and disconnects on disarm/session change. Signal-less fixtures retain the decreasing-tick fallback.

### Numerical meaning of the gizmos

For a valid unit air direction u, `F_parallel=(F·u)u` and `F_perpendicular=F−F_parallel`; their sum preserves total force. When air data is unavailable there is no justified u, so the candidate returns null for airspeed/angles and along/across components and omits their arrows. Total force/gravity can remain valid independently. Wind in m/s is null when unavailable and zero only for actual calm. Load factor is dimensionless `−Fz/(m*g)`; the moment arrow's `M/(m*g)` has units of metres.

This does not make the channels simultaneous: `Simulation.last_loads` is the preceding step's RK4 k1 evaluation, air data uses the accepted state, and the basis is the displayed pose. No endpoint-load reevaluation or measured error magnitude was introduced. The guide now explains this limitation.

### Cost and lifecycle bounds

Claim operations serialize on a persistent lock file. The OS releases the lock on process death; deleting that lock file would break coordination between old and new open handles. The lock applies to clients using this version. Cleanup protects all live claims, but currently holds the lock during recursive old-run deletion; slow filesystem deletion can delay other clients. This is source-derived, not a measured stall.

Dropped-peer membership uses a dictionary, so filtering I inbox entries against D dropped peers costs expected O(I+D) time and O(D) temporary space. Existing pending-job cleanup has its own cost and is not claimed linear by this statement. Ordinary ring append still uses `pop_front`, O(N) at capacity; default N=241 is modest, but a true circular buffer could help the optional 100,000-snapshot case after profiling. The review does not invent an FPS gain.

## Verification and reconciliation

The pinned engine is **Godot 4.8.beta2.official.cafc17a19**. The checked runner requires meaningful completion text and checks engine diagnostics, not just exit status.

| Evidence actually obtained | Result and boundary |
| --- | --- |
| New bridge contract script | **26/26** pass; baseline bridge fails **13/26** assertions. Real TCP framing plus injected disconnect queues, numeric and file controls. |
| New step script | **24/24** pass; fake simulation/session ownership, faults, deadlines, disconnect, replacement and reset boundaries. |
| New observer script | **36/36** pass; baseline has **18 assertion failures**, five empty-surface errors and one nonfinite-vector warning. Headless mesh/telemetry checks, not visual qualification. |
| Existing broad bridge script | **114/114** pass in the documented isolated fixture; zero engine errors and exactly two intentional logger warnings. Catalog data/real flight capabilities are outside this fixture. |
| Existing render-probe script | **34/34** pass; synthetic validity/ablation restoration controls, no measured GPU verdict. |
| Client suite | **65 methods: 64 pass, one unchanged environmental failure** in `test_an_unreaped_exited_child_is_not_alive`. PID/procfs namespace mismatch was already established in PT1h-R13; test remains intact. |
| Warning scanner suite | **10/10** methods pass for output/admission/publication controls and owned-snapshot cleanup. Synthetic collector, not a live editor scan. |
| MCP suite | Existing **14/14 methods** pass for client compatibility; no new MCP finding or duplicated fix claimed. |
| Checkpoint experiment | Actual file-size limit; exact UTF-8, long filename, mode and link controls. See retained runner and case receipts. No native Windows execution. |
| Python compilation / whitespace / links | Changed code and documentation checked; source manifests retain identities. |

Combined Python discovery runs **89 methods: 88 pass and the same one environmental liveness test fails**. It is not a green suite.

The initial direct bridge run emitted missing-asset/compile diagnostics; the next minimal fixture also lacked `smoke_pump` input configuration. Neither is a successful candidate check. Fixing the fixture and preserving actual test/code sources produced the scoped 114-check pass above. No production source was weakened to hide those failures.

GitHub review found no issue result for the repository query `debug`; this is a search result, not proof that all related issues are absent. [Merged PR #8](https://github.com/bultodepapas/OpenRCsimulator/pull/8) and commits [fe121ae](https://github.com/bultodepapas/OpenRCsimulator/commit/fe121ae04e5fc93d9cb60b5c57f0b066a574bfb0) / [f2084f3](https://github.com/bultodepapas/OpenRCsimulator/commit/f2084f3b8c8c5ebc9eef942d2fbae47a66ecf9e8) already address stale/root/subviewport attribution, incomplete GPU phases and ablation ownership. They are not reopened as discoveries. PT1h-R13's MCP repairs are already in this review's baseline; its export/catalog proposals remain separate. No whole prior audit is marked closed.

Candidate full CI, full-app reset/weather/flight routes, rendered 1080p review, physical controls and native Windows filesystem/locking remain qualification gates. A previous branch or main CI success cannot qualify this source snapshot.

## Ranked next work and useful initial scope

Effort estimates below are engineering planning estimates, not measured completion times. Prefer the existing Godot debugger/profiler and project tools over another general debugger framework.

| Rank | Extension / initial scope | User, input/output and integration | Benefit / estimated cost |
| --- | --- | --- | --- |
| **1** | Fix D14 in the existing warning scanner: own a collision-resistant port, monitor the launched editor throughout collection, and refuse unproven listener identity | Developers/CI pass the existing patterns/baseline; return diagnostics with explicit engine/project/process identity, or tool failure. Add foreign-listener, failed-start, delayed-bind and mid-scan-exit controls. | Prevents a false clean verdict. Roughly 1–2 days; moderate cross-platform process/LSP testing. |
| **2** | Qualify checkpoint and session recovery on native Windows | Reuse the retained runner and client suite; test sharing violations, publication/rollback failure, link behavior, lock contention/process death and live-run cleanup. Output checked receipts with exact sources. | Closes the largest platform-specific boundary in the implemented fixes. Roughly 1–3 days with an available host; ongoing engine-upgrade gate. |
| **3** | Extend `DebugLog`/`profile` with a byte budget and completeness metadata | Existing script-profile users; accept multiline callbacks, frame them without silently dropping valid rows, report dropped bytes/records and `complete=false`. Preserve ordinary warning isolation. | Current profiler storage limits 20,000 entries but not callback bytes. Bounded memory and honest reports; roughly 1–2 days. No actual out-of-memory event measured. |
| **4** | Extend `bugit` with a local fallback and manifest | Authors filing crashes; use known session run files, attempted command trail, source/config identity and available snapshots when the bridge is gone. Produce a bundle manifest marking missing/incomplete components. | Less manual reconstruction of disconnect failures. Roughly 1–2 days; reuse current report/screenshot/checkpoint formats. No new replay format. |
| **5** | Add a small `debugctl doctor --json` mode only for uncovered preflight checks | Contributors/agents; inspect engine pin, selected session/port/PID consistency, writable output and relevant scanner-listener state. Return per-check statuses and actionable messages without launching/mutating a flight. Reuse `status/ready` implementations. | Diagnoses environment/ownership failures before a long run. Roughly 1–2 days; maintain with engine/client changes. Do not duplicate Godot's editor inspector or profiler. |
| **6** | Optional circular rewind storage and a lifecycle contract matrix | Debug developers with large history settings; benchmark append/lookup at default and maximum capacity, preserve chronological ordering/attempt cuts, and test reset boundaries in samples/watchpoints before changing them. | Removes O(N) front shifting if measurements justify it. Roughly 1–3 days; state/attempt invariants create moderate maintenance cost. Current sample/watchpoint issues are hypotheses, not verified defects here. |

The next integration step is to qualify these changes in the full provisioned application and required CI, then merge the reviewed candidate. Repeating old GPU rankings, creating a second profiler UI or retuning physics would not address the demonstrated failures.

## Native Windows integration and D14 follow-up (2026-11-08)

The starting checkout was `41ce5af6f`, which lacked the `644f4e7` debug repairs and PT1h-R13 MCP fixes. Their focused
debug patches were reused; unrelated PT1h-R13 work was not imported. Concurrent work advanced HEAD to `4bda2e454`
during verification. [Native receipts](verification-native.json) bind the debug sources by SHA-256 and distinguish
the shared-tree smoke observation from a stable whole-project qualification. Unrelated edits were preserved.
The historical candidate's [CI run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42377286844) now
reports success; that does not qualify these additional changes.

D14 now requires OS evidence that the exact accepted TCP connection belongs to the launched editor before any
source text is sent. Each scan selects an ephemeral port, refuses occupied explicit ports, monitors the editor
through bounded reads and completion, rejects failed initialization and missing diagnostics, and closes/reaps its
resources. Windows uses the real editor executable beside its console wrapper and matches encoded drive-letter
URIs. Unavailable ownership evidence fails closed. The historical `lsp-listener-repro.py` belongs to the original
candidate; current regressions live in `tools/debug/test_gdscript_warnings.py`.

Independent Good Enemy review also established that incomplete scans could erase warning baselines, filtered
refreshes could drop unrelated keys, and Windows `LK_LOCK` could exhaust its ten-attempt wait. Baselines now survive
tool/compiler failures and retain unselected file keys; claim locking retries only contention errors until ownership
is available. The Windows monkey fixture closes listening sockets without an invalid `shutdown` and proves each
intended disconnect phase occurred. The checkpoint resolver reports unresolved Windows links directly rather than
recursing on the engine's failed `read_link` return value.

| Verification | Result and scope |
| --- | --- |
| Native Windows Python discovery | 102 methods: 101 pass, one existing Linux `/proc` test skipped. Includes real TCP ownership, foreign listener refusal before source transmission, delayed/failed startup, mid-scan exit, incomplete frames, initialization failure, URI and baseline controls. |
| WSL/Linux Python discovery | 102 methods: 101 pass, one native-Windows-only lock test skipped. The formerly failing zombie-process test passes here. |
| Native Godot debug suites | Bridge contracts 26, step lifecycle 24, observers 36, broad bridge 114 and render probe 34 assertions pass (234 total). Actual provisioned project, no catalog/preference substitutions; two intentional logger warnings in the broad suite. Final checkpoint change rechecked with the 26-contract suite. |
| Native compiler collection | Pinned Godot 4.8 beta2, minimal isolated project: expected `UNUSED_VARIABLE` received, accepted connection owned by the launched editor, identity receipt retained. |
| Real Windows checkpoint filesystem | Eight cases pass: normal Unicode replacement, absolute link, relative link chain, directory-link parent, dangling-link refusal, cycle refusal, Windows missing-component normalization and a real sharing violation. The sharing case preserves original and recovery bytes. |
| Native claim locking | A real contender observes EACCES while another process holds the lock and acquires it after the owner is killed. Twelve retries and propagation of non-contention failures are tested separately; the real contention run does not wait ten seconds. |
| Full debug smoke | 52 stages pass, zero reported engine errors, zero leaked objects at shutdown. Headless shared-tree observation; concurrent unrelated edits and later lock/link refinements prevent treating it as final whole-project qualification. |

Native Windows link tests require symlink privileges. Windows resolves `..` in relative link targets before
traversal; POSIX follows the preceding directory link. The fixture checks each platform's actual destination.
The pinned Windows engine cannot resolve a dangling link's target through `read_link`; save safely refuses that
case. Its [implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/windows/dir_access_windows.cpp#L489)
also motivates the explicit failure check.
Links whose resolved target is a network share are refused because the pinned engine returns an ambiguous
`UNC/...` form; this prevents treating that target as a local relative path. Direct UNC paths remain unqualified.

Remaining qualification: native macOS ownership inventory, Windows rollback after an already removed destination,
power loss/ACL/UNC behavior, rendered 1080p inspection, physical controllers and required CI for the final source.
Profiler byte budgeting, offline BugIt recovery and measured rewind-storage optimization remain optional follow-ups;
no FPS improvement or physical validation is claimed.
