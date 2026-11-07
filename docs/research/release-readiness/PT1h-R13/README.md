# PT1h-R13 — Tool correctness and evidence review

Reviewed **2026-11-07, America/Bogota**. Baseline: [`997e212784dbf873a7b054ddbbc68e7905495adf`](https://github.com/bultodepapas/OpenRCsimulator/commit/997e212784dbf873a7b054ddbbc68e7905495adf). Scope: developer tools and their consumers, not a physics retuning or a cybersecurity review.

## Outcome and scope

This candidate repairs **five defect groups** and removes one mathematically redundant full-file CSV pass. Two further tool defects have reproducible conditional triggers and remain proposed work. The four focused suites pass **76 test methods**; additional evidence includes four detected weighing mutations, a real file-size-limit failure, actual benchmark-entrypoint scheduling fixtures, strict UTF-8 MCP transport, and 24 byte-equal CSV summaries. [Verification and source hashes](verification.json).

The review began with the complete [consolidated queue](../../../../external%20Audits/CONSOLIDATED-AUDITS.md) and [implemented-work record](../../../../external%20Audits/COMPLETED-AUDIT-WORK.md). It then used the existing [tool index](../../../tools/README.md), [research map](../../../../research/README.md), owning READMEs, implementations, callers, tests, configuration and GitHub history. The inventory is a broad census with selective deep review, not certification of every historical script. No confirmed regression was established: the cadence error is a surviving duplicate of an already repaired sibling algorithm, not a demonstrated reintroduction.

The source census contains **47,278 tracked blobs**, including **5,861 source files** under the explicit extension/name definition in the delivered inventory. The detailed manifest covers **1,859 files in 90 families**: eight changed source/test files with focused verification, 52 representative source reads, and 1,799 indexed-only files. These labels describe the manifest's recorded review depth, not the amount of surrounding documentation read. The census separately counts 1,927 documentation/retained reproduction source files, 394 retained asset-delivery sources, and 12 prototype sources; treating these as independently maintained tools would misstate ownership. Within the detailed manifest, 114 files are additionally labeled retained copies or dated research by path/name cues, without assuming they are obsolete.

The delivered per-file inventory records baseline blob identities, declared interfaces/dependencies, owning guides and review depth. It includes the four `app/tools/` scripts and six editor-addon scripts. All 1,859 records were retrieved and checked for unique paths and baseline identity; static Python extraction had no parse failures. A filename or static import alone does not establish actual execution. [Inventory coverage](inventory-coverage.md) and the [source census](tool-source-census.json) retain the exact scope; the full per-file JSON accompanies the downloadable review bundle. The existing maintained tool index remains the command-discovery owner.

All test mutations used disposable fixtures or copies. The source checkout omitted large binary assets and many historical data files; omissions were checked against Git before making findings. The required weighing fixture was obtained from the pinned source and verified as Git blob `826531ee518c299eb73fef3e9ce2b716801ad2fa`. No generated aircraft data, golden flights, simulation equations, engine pins or asset binaries are changed.

## Audit and GitHub reconciliation

The old queue is evidence about its recorded snapshot. Current source and later validation determine present status.

| Earlier item | Current evidence and classification |
| --- | --- |
| A27 CI-04, CI-05, CI-06, CI-07, CI-08, CI-10 | Already repaired by [b21c078](https://github.com/bultodepapas/OpenRCsimulator/commit/b21c0789649b856217d82faa112c190d34389a21): installed RC native production checks, complete fixed-FPS digests, nonempty converted-texture checks, bounded dependency setup, one fixture interpreter, and explicit refusal of unsupported desktop custom templates. These are not new findings or fixes from this review. |
| Full CI at the repaired source | [Run 42333181434](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42333181434) succeeded at the exact baseline: 20 successful jobs and one intentional tag-release skip. Both installed native-runtime jobs succeeded. This advances the old qualification record; it does not qualify this candidate or physical/native-GPU behavior. |
| A27 CI-09 | Remains separate: headless pixel-test skips are not closed by the above six source repairs. The new export finding below concerns different checks and a different success predicate. |
| A1/A7/A24 measurement eligibility, hitch/burst and target-platform work | Previously documented. Existing frame reducers, raw streams and diagnosis tools should be extended, not replaced by another profiler. No new target-host timing claim is made. |
| E300-01/02, CF-01/02/04 and generator physics conventions | Previously documented and still owned by their original generators/audits. This review does not count them again or regenerate aircraft physics. |
| Flight-test unknown `--only`, legacy unsafe `--help`, conformance overwrite, uncovered night-lighting/mass-trace checks | Already listed in [shared-tool caveats](../../../tools/shared.md#known-broken-or-stale-tools). They remain worthwhile work, explicitly classified as previously documented. |
| Tool discovery and local verification policy | [PR #8](https://github.com/bultodepapas/OpenRCsimulator/pull/8) already integrated graphics/diagnostic/benchmark hardening; [PR #9](https://github.com/bultodepapas/OpenRCsimulator/pull/9) already established impact-scoped local checks. The existing task index is the authoritative discovery surface. |

The reviewed GitHub issue results, [#3](https://github.com/bultodepapas/OpenRCsimulator/issues/3) and [#5](https://github.com/bultodepapas/OpenRCsimulator/issues/5), were verified closed/completed and concern controller/UI behavior, not an unresolved tooling queue. Path history was inspected for the changed tools. The capture job in the baseline run lasted **2 h 31 min 39 s**, calculated from its GitHub job timestamps, and was the observed critical path. This supports continuing the existing PT1-CI work; it is not a controlled before/after benchmark.

## Tool inventory by workflow

The following family map records actual workflow contracts. The accompanying machine-readable inventory provides individual paths and declared interfaces. “Reviewed” below does not imply every member of a family was executed.

| Family and entry points | Users and inputs | Outputs, consumers and workflow role | Dependencies / review boundary |
| --- | --- | --- | --- |
| `app/get-godot.sh`, `get-templates.sh`; `tools/godot/get_historical_godot.py` | Developers/CI; pinned host/engine/template identities | Verified tool paths and cached artifacts used by tests and exports | Shell/Python, download/hash tools; installation contracts inspected, no new engine installed |
| `app/test.sh`, `research/test-tools.sh`, `tools/ci/check-local.sh`, `check-sources.sh` | Contributors/CI; source snapshot and selected partition | Generator, parse, unit, integration and offline checks; scoped receipts and process status | Bash, Python, pinned Godot and area dependencies; call coverage traced |
| `tools/ci/{policy,phase_roster,capture_groups,check_docs,release_preflight}.py` | CI maintainers; event/change set, rosters, capture receipts, source tree | Conservative job selection, exact coverage reconciliation, link checks and release prerequisites | Python/Git, GitHub Actions; current b21 repair and hosted status inspected |
| `tools/godot/{run_checked,summarize}.py` | All tool authors; engine command, time/output limits and required text | Engine log, JSON verdict and JUnit; rejects diagnostics even with exit zero | Python stdlib/process APIs; source and callers reviewed; export reuse gap reproduced |
| `tools/debug/debugctl.py`, scenarios and `mcp_server.py` | Developers and coding agents; selected live session, commands, typed calls | State/UI snapshots, interactions, logs, captures, smoke/reproduction evidence | Python stdlib plus Godot debug bridge; MCP deeply reviewed and fixture-tested |
| `tools/godot/{incident_bundle,perfetto_export,lifecycle_check,resource_samples,storage_audit}.py`; `gdscript_warnings.py` | Investigators; logs, process/resource records, warning baselines | Incident bundles, timelines, lifecycle/resource summaries and warning comparisons | OS-specific collectors and optional pinned resource dependencies; source/docs mapped, no native campaign |
| `tools/flight_log/flight_log.py`, `app/tools/flight_log_cli*.gd` | Flight investigators; ORFL, matching solver/package and candidate data | Replay/export CSV, summaries, comparison and debrief JSON | Python stdlib plus matching Godot for replay; offline reducers deeply tested, live replay not rerun |
| `research/flight-test/{run,compare,summarize}.py`, `flight_test.gd` | Physics/aircraft developers; catalog IDs, card cases, frozen app | Per-aircraft profiles, traces, provenance and fleet comparisons | Python and pinned Godot; entrypoint, selection, outputs and existing limitations reviewed |
| `research/validation/*/reduce.py`, `research/propwash/e0b7/reduce.py`, `research/radio-latency/reduce.py` | Measurement contributors; tagged units, observations and uncertainty assumptions | Derived mass/CG/inertia/propeller/video/latency reports; no automatic aircraft-data promotion | Mostly Python stdlib; representative equations reviewed, weighing deeply tested |
| `research/performance/{session_baseline,app_cpu_per_sim,observer_cadence_bench,observer_cadence_ab}.py` | Performance developers; frozen sources, roles, modes and windows | Source-bound session/CPU/cadence JSON or JSONL | Python, Godot/debug bridge, Linux procfs or documented Mac counters; cadence schedule executed with a fake bridge |
| `research/performance/{native_summary,frame_diagnose,texture_inventory}.py` | Graphics/release investigators; raw frames, logs, textures and explicit policy | Eligibility reports, frame/burst diagnosis and texture inventories | Python; inspected implementation/test contracts, no new display or GPU measurements |
| `research/aircraft-standardization/{build_models,build_customization,conformance}.py`; `research/aircraft-editor/build_descriptors.py` | Aircraft/Workshop authors; catalog, registries and exact model/data bytes | Model manifests, presentation bindings, descriptors and conformance records consumed by runtime loaders/Workshop | Python, model validators and Godot for runtime checks; parser counterexample executed |
| Aircraft generators under `assets/` and `research/{ugly-stik,extra-300,p51,avanti-s,timber,f4u-corsair,...}` | Aircraft authors; source geometry, measured/estimated quantities and recipes | Generated geometry/physics and identity artifacts for production admission | Area-specific Python/Blender/Godot requirements; ownership mapped, known physics findings retained |
| `research/{native-kernel,rc-monster-truck/native}/build.py`, verifiers and package helpers | Native developers/release maintainers; pinned C++ sources/toolchains | Libraries, evaluator/trajectory evidence and package receipts | Compiler, godot-cpp and exact engine; baseline hosted status reviewed, no rebuild |
| `tools/graphics/{launch,prepare_research}.py`, `native/` builders | Graphics investigators; frozen project and optional engine/vendor candidates | Isolated launch/build/package identities and rendering probes | Godot, platform toolchains/vendor dependencies; contracts mapped, no new fork or deployment |
| `tools/{atmosphere,grass,ground,shadows,smoke}` checkers and `app/capture.sh` | Visual developers/CI; controlled scene/time/camera/material cases | Images, metrics, manifests and checker verdicts | Pinned Godot, visual Python dependencies and actual renderer; indexed/source-reviewed, not rendered here |
| `tools/{trees,terrain,landscape,scenery}` generators/converters | Environment authors; licensed sources, placement rules and source hashes | Atlas/mesh/material/terrain/placement data consumed by scenery/field loaders | Python/Pillow, Node and/or Blender/Godot per guide; representative source/consumer contracts reviewed |
| `tools/scenery/population/*` | Asset authors; people/car sources, outfits and textures | Population packs, merged atlases and export/runtime checks | Blender/Python/Godot; current nonempty-texture CI repair reconciled |
| `tools/skins/{build_skin_kits,pack_image,export_openrc_skin}.py` | Skin authors/players; matching model kit and texture files | Editable kits and texture-only ORSKIN archives; runtime revalidates model/image contract | Python stdlib packer; Blender/Godot for kit generation; source and tests reviewed, no real importer run |
| `tools/audio/*`, `tools/night-lighting/build.py` | Audio/environment authors; licensed recordings and source manifests | Banks, converted textures/manifests and analysis reports for runtime consumers | Separate pinned audio/visual environments; no audio-quality or lighting qualification |
| `tools/world/{sky_table,moon_fixtures,stars,twilight_check}.py` | World developers; dates, coordinates, ephemeris fixtures | Tables, fixture/sky diagnostics and source data | Python and relevant Godot captures; indexed against existing world guide |
| `app/addons/{aircraft_contract,build_info,native_kernel}/export_plugin.gd` | Exporters; catalog/proofs, source/build identity and selected target | Embedded authoring proofs, build metadata and native qualification sources | Godot EditorExportPlugin; implementations and downstream package checks reviewed |
| `app/export.sh`, `tools/release/{manifest,elf_audit,macos_reference_receipt,publish}.py` | Release maintainers; verified source/tools/libraries and packages | Isolated exports, ABI inventory, final manifests and publication verification | Godot, shell, archive/ELF/platform tools, GitHub; shell-gate counterexample reproduced, no real export/publication |
| `tools/companions/rebind.py`, qualification data | Companion maintainers; old/new solver identities and retained tapes | Explicit rebind evidence, preserving exact compared trajectories | Python plus Godot evaluator; existing A27 repair reconciled |
| `tools/{analytics,blender,branding,readme,trailer,ui}` and site automation | Maintainers/content authors; GitHub metadata, scene/source/media and locale inputs | Local analytics, editor bridge setup, branding/overlays/media and site content | Respective guides/pins; inventoried, not every implementation deeply reviewed |

The current tool index is useful and should remain authoritative. The main discoverability improvement is to expose completeness, side effects and evidence limits consistently in each existing tool's output and guide, rather than add another parallel command catalog.

## Prioritized findings

P2 here means a reproducible developer-workflow correctness or evidence defect. Ordering considers data preservation, misleading success and time lost. It does not imply a currently broken public release or physical flight defect.

| ID / priority | Status and history | Files / functions | Reproduction, impact and resolution |
| --- | --- | --- | --- |
| **T01 / P2** | New; candidate implemented | `research/validation/weighing/reduce.py::main`, new `refuse_alias`, `atomic_write` | A reducer-copy output target replaced the Python source with JSON and exited zero. A real 64-byte file-size limit truncated a previous report before exit one. Refuse input/source aliases and publish a completed temporary report atomically. |
| **T02 / P2** | New; candidate implemented | `tools/debug/mcp_server.py::handle`, `serve`, `_check_arguments` | Valid JSON with `params=true` or a list tool name terminated the persistent server; a string `headless="false"` selected headless launch. Validate before actions; survive decoder/UTF-8 boundaries and process subsequent requests. |
| **T03 / P2** | New; candidate implemented | `mcp_server.py::call_tool`, `sim_stop` branch | A stubbed real-client return code 2 produced `isError=false`. Preserve nonzero shutdown outcomes and diagnostics as tool errors. |
| **T04 / P2** | New; candidate implemented | `tools/flight_log/flight_log.py::_validate_header`, `_is_int_column` | `mode_0,mode_00,mode_2` passed despite missing slot 1. `mode_٠` bypassed integer parsing, rounding an int64 endpoint and accepting fractional modes. Require unique numeric slots and use the same decimal-suffix semantics for typing. |
| **T05 / P2** | Newly found surviving duplicate of known sibling repair; candidate implemented | `research/performance/observer_cadence_ab.py::main` | Rotation plus odd-round reversal canceled for two modes, yielding the same order every round. Reuse `observer_cadence_bench.py::role_order`; preserve window count and output contract. |
| **T06 / P2** | New; confirmed synthetic gate failure; proposal | `app/export.sh` import/export/package-smoke blocks | Actual shell block accepts selected exit-zero shader/indented/colored errors and empty smoke output. Reuse the checked runner and terminal completion markers; qualify all export branches before promotion. |
| **T07 / P2** | New; parser failure executed, consequences source-derived; proposal | `research/aircraft-editor/build_descriptors.py::ENTRY_RE`, `_parse_catalog_entries`, `expected_descriptors`, `main` | Reordering fields in one valid catalog entry silently omits it; normal generation then deletes outputs outside its partial expected set. Prove complete roster before replacement/removal and independently reconcile runtime catalog membership. |
| **T08 / P3** | New efficiency improvement; candidate implemented | `flight_log.py::summarize_csv` | Altitude RMS triggered a second parse of every column/row. Reuse the existing down-coordinate magnitude accumulator; exact arithmetic and full report equality retained. |

### T01 — Preserve collected weighing evidence

Correct publication means either the previous complete report or the new complete report is present; a failed write must not expose an incomplete replacement. For distinct input `I`, reducer source `S` and destination `O`, require `O` not to alias either `I` or `S`, including symbolic and hard links.

The baseline only protected the input. A disposable invocation of `reduce.py input.json --output reduce.py` returned zero after overwriting itself. A separate operating-system `RLIMIT_FSIZE=64` experiment truncated an existing report to 64 bytes and then failed. These are executed output failures, not hypothetical filesystem analysis.

The candidate serializes before publication, writes/flushes/fsyncs a sibling temporary file, and uses `os.replace` only after success. It preserves the established behavior of following a destination symlink and preserves an existing target's permission bits where supported. New reports use private temporary-file permissions, normally 0600 on POSIX. Replacement changes the inode; other hard links retain the old contents. These choices are documented in the [owning guide](../../../../research/validation/weighing/README.md).

Tests include direct/symlink/hardlink aliases; new and existing outputs; serialization, chmod, fsync and replacement failures; temporary-file cleanup; permissions and destination symlinks. The real file-size-limit failure now returns one while leaving the previous report intact. This is single-file publication under handled failures, not a multi-file transaction or a hardware power-loss durability guarantee.

### T02–T03 — Keep simulator automation alive and honest

One minimal baseline input is:

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":true}
```

`handle` accessed `.get` on a boolean outside the tool-error guard. A list-valued tool name instead failed the set-membership operation. In both cases, a following valid ping was never processed. Non-object messages were silently discarded, and a failed `debugctl.stop` was reported as a successful tool result.

The candidate distinguishes malformed envelopes, invalid parameter containers, unavailable tools and tool failures. It checks the flat argument contracts already advertised by this server: declared property names, required fields, types and enum choices. It does not implement a general JSON Schema engine or a new dependency. Boolean and numeric values remain distinct; a string `"false"` cannot silently become a true headless flag. Invalid calls are rejected before dispatch, while valid values reach the tool unchanged.

Decoder `ValueError` and `RecursionError` become parse errors, so oversized integer text and deeply nested JSON do not terminate the stream. JSON-escaped transport output preserves ordinary Unicode after decoding and prevents an escaped lone surrogate from raising `UnicodeEncodeError` on strict UTF-8 stdout. Valid notifications remain unanswered. A nonzero stop returns `isError=true` with its diagnostic; it does not silently force-kill an application.

These behaviors follow the [MCP base protocol](https://modelcontextprotocol.io/specification/2025-11-25/basic), [tool-result contract](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) and [JSON-RPC error distinction](https://www.jsonrpc.org/specification). Verification used protocol streams, strict UTF-8 output and stubbed bridge/client outcomes, not a live native application session.

### T04 — Column count is not a proof of state-slot coverage

Let `S` be the numeric suffixes of a family beginning at index `a`, and let `k` be its column count. The old check combined `min(S)=a` and `max(S)-a+1=k`. Those conditions are insufficient when distinct column names encode the same index: `[0,0,2]` satisfies both while omitting 1.

The added uniqueness condition `|set(S)|=k`, together with the existing bounds, proves that each required numeric slot occurs exactly once. The bounded digit parser remains in place; it does not convert an arbitrarily large suffix into a huge integer. Existing supported aliases, including Arabic decimal digits and 5,000 leading zeros, remain accepted individually and retain their original names in reports.

Typing must use the same admitted-name domain. The former ASCII-only mode regex excluded `mode_٠`, although header validation admitted it. At the int64 maximum `9223372036854775807`, the generic float parser rounded the value, and it accepted `1.5` as a mode. The candidate recognizes all admitted decimal mode suffixes and retains decimal int64 checks and exact minimum/maximum values. Regression coverage includes both int64 endpoints, out-of-range/fractional modes, three indexed families and alias collisions.

### T05 — Balance treatment order with a proven schedule

For two modes `[A,B]`, the old odd-round rotation produced `[B,A]`, then reversal restored `[A,B]`. Every round therefore assigned the same treatment to the same position. The four-mode fixture likewise visited only half the positions. An uncontrolled within-round drift could be mistaken for a treatment effect; no particular historical CPU number is proved wrong by this scheduling defect alone.

The existing `role_order` supplies the intended schedule. Two modes alternate. For `N>=3`, round `2k` uses rotation `k mod N` and round `2k+1` its reversal. Each adjacent pair balances pairwise precedence. Over `2N` rounds every role occupies every position exactly twice. Each round remains a permutation, so the job count and work performed remain unchanged. Partial cycles retain every job once per round but do not claim full position balance.

The actual Python entrypoint was exercised with a fake bridge, without sleeping or launching Godot. For two modes over four rounds, position counts changed from `[4,0]`/`[0,4]` to `[2,2]` each. For four modes over eight rounds, alternating `[4,0,4,0]`/`[0,4,0,4]` became `[2,2,2,2]` for every mode. Every fixture retained `N × rounds` rows and one launch/stop. [Before](cadence-order-before.json) and [after](cadence-order-after.json) evidence.

This repairs a surviving duplicated formulation: the sibling's earlier correction is recorded under DT-MAC-02, and AB path history has its original [1121e445 addition](https://github.com/bultodepapas/OpenRCsimulator/commit/1121e445a2f2be3bd376dec6f2fb96d893295a1c), not a subsequent repair and reintroduction. Scheduling remains O(N) time and temporary space per round. No runtime speedup or drift cancellation is claimed.

### T08 — Reuse the altitude RMS exactly

Altitude relative to the NED datum is `h_i=-d_i`. Therefore

```text
RMS(h) = sqrt(sum((-d_i)^2)/n) = RMS(d).
```

More strongly, `_Rms.add` begins with `abs(value)`, so its original sign-negated input and the already accumulated down-coordinate input produce the same sequence of magnitudes and floating-point operations, including signed zero. Reusing that accumulator is an exact transformation for the reader's admitted finite values, not a new summation method or a tolerance-based approximation.

The old code opened, validated and parsed every row twice. The candidate does so once, retaining O(C) accumulator memory for C columns. Both are O(RC) for R rows, but one complete parse is removed. [The experiment](summary-parity.json) recorded **24 byte-identical serialized summaries across 2,587 rows**, including sign changes, zeros and very large/small finite values. Reader constructions fell from two to one for every case. These are measured operation counts and output equality, not a claim of a 2× wall-time gain or any simulator FPS improvement.

### T06 — An exit code alone cannot certify a package smoke

The inspected exporter uses several different anchored grep expressions. Export/field-pack patterns omit `SHADER ERROR`; whitespace or ANSI color can hide diagnostic prefixes. None of the three inspected package smoke branches requires its terminal completion marker.

The reproduction executes the actual extracted shell block, replacing its `timeout` invocation with controlled fixture output. Exit-zero `SHADER ERROR: ...`, indented `SCRIPT ERROR: ...` and ANSI-colored `SCRIPT ERROR: ...` all pass the field-pack block, although `run_checked.py::inspect_log` detects each. Empty exit-zero output passes all three smoke branches without completion. Plain unindented `SCRIPT ERROR` fails as the negative control.

This establishes a gate defect under explicit inputs. It does not establish a broken release, a current native engine error, or that no other check would catch a particular damaged package. The focused repair should use the existing checked runner for import/export/package checks, require final meaningful completion markers, retain bounded logs and `export-failure.log`, and test clean/error/missing-marker/nonzero/timeout cases for every branch. An actual provisioned export remains the integration gate. No exporter code is changed in this candidate.

### T07 — Prove the catalog is complete before deleting descriptors

`ENTRY_RE` assumes each catalog dictionary begins with `id`. Two valid dictionary literals, one beginning with `id`, the other with `visual_family` before `id`, cause the actual parser to return only the first. Because it merely requires at least one match, partial discovery reports no error. The current catalog uses the assumed layout; no currently missing descriptor is asserted.

The dangerous downstream consequence is source-derived: `expected_descriptors()` generates from the partial list; normal `main()` writes that set and unlinks other JSON files; later `--check` compares against the same incomplete expectation. The runtime descriptor loader refuses missing descriptors, and Workshop recovery depends on that loader. Deletion and player recovery were not executed in this review.

Prefer an authoritative runtime-catalog export or a shared structured source, plus independent ID-set reconciliation. Fail closed on unsupported/partially parsed entries before touching outputs. Restrict removal to proved owned generated files and retain compatibility artifacts. Tests need reordered/commented entries, mixed vehicle kinds, duplicate IDs, unknown output files and interrupted staging. A generator compared only with its own mistaken parser cannot establish complete runtime coverage.

## Numerical review beyond the repaired code

Representative measurement reducers were checked against their stated contracts. These are software/formulation checks, not a source of measured aircraft parameters.

- Weighing uses net loads `n_i=gross_i-tare_i`, mass `M=sum(n_i)` and horizontal CG `sum(n_i*x_i)/M`. Sensitivities retain shared errors: common scale gain cancels from CG; common datum uncertainty does not average down. Existing analytic, finite-difference and seeded Monte Carlo tests pass; all four existing deliberate statics mutations are detected.
- Bifilar inertia uses full separation `D`, with `m*g*D^2*T^2/(16*pi^2*L)`. Compound tare is subtracted about the pivot before the rigid-body shift `Q^2/M`; repeated measurement identities preserve covariance. Alignment and nonlinear acquisition errors remain separate limitations.
- Static propeller reduction converts rpm to revolutions/s before `Ct=T/(rho*n^2*D^4)`. Shaft power uses measured torque, `2*pi*n*Q`; absence of torque does not justify inventing shaft power or Cp. Ideal actuator-disc power is a figure-of-merit reference, not propulsive efficiency.
- Video reducers use frame differences and acquisition cadence; cycle averages/net displacement do not become instantaneous airspeed. Acquisition, geometry and shared-error assumptions must travel with the resulting report.

The flight reader already contains useful scaled RMS and quaternion-angle formulations. The review preserves those rather than substituting naive squares or a near-zero `acos` calculation. Existing data provenance, strict admission, checked-runner diagnostics, exact roster reconciliation and source/package identities are strengths to retain.

## Verification and limitations

| Check actually performed | Result | Boundary |
| --- | --- | --- |
| MCP suite | 14 test methods passed | Protocol/typed inputs, continuation, strict UTF-8 and stubbed actions; no live simulator |
| Flight-log suite | 35 passed | Offline reduction, boundary data, debrief and CLI fixtures; no new flight replay |
| Cadence suite | 8 passed; new controls previously exposed three failing assertions | Scheduling, output identity, path/settings handling and failure cleanup; no timing campaign |
| Weighing suite | 19 passed; new baseline controls exposed five expected failures | Disposable exact fixture, numeric checks, output integrity and filesystem failure handling |
| Independent weighing mutations | All four detected | Existing synthetic statics controls; no physical calibration |
| File-size failure | Prior output preserved after a failed 64-byte-limited write | Real local OS limit, not a power-loss experiment |
| Summary parity | 24 reports byte-equal; 2,587 rows; two readers reduced to one | Canonical finite fixtures, no elapsed-time claim |
| Export negative controls | Selected bad/empty exit-zero outputs accepted by actual shell block | Fixture subprocess, no real export/release failure asserted |
| Independent combined-diff review | No new blocking regression identified | Evidence is review plus focused tests, not reviewer consensus as runtime proof |
| Baseline hosted CI | Exact-head success, 20 jobs plus intentional tag skip | Baseline only; candidate CI remains separate |

A broader debug run executed 70 tests and had one failure in unchanged `test_an_unreaped_exited_child_is_not_alive`. A direct witness showed the sandbox's Python PID was 5 while `/proc/self` resolved to PID 10433; child PID 6's procfs record described an unrelated process, while waiting on the actual child returned zero. The `/proc` assumption cannot be qualified in this environment. The test was not weakened or silently skipped, and the full debug suite is not reported as passing. The changed MCP suite is independently green.

No full local app/capture suite, Godot/Blender workflow, native rebuild/export, target GPU/display/radio test, physical measurement or performance campaign was run. The unchanged baseline's green CI must not be presented as verification of this candidate. Source hashes and the exact scope of each result are retained in [verification.json](verification.json). Existing CI already discovers all four modified focused suites.

Receipt provenance: the original cadence harness recorded the actual entrypoint path, orders and row/process counts, but did not capture a source hash during execution. The before/after source hashes now attached to those receipts were derived retrospectively from the pinned baseline and final candidate; their association is corroborated by the recorded edit/execution sequence. The downloadable inventory/evidence bundle includes that harness and all 24 exact CSV parity fixtures. Its parity replay driver checks the recorded source/input identities, all complete-report hashes and reader counts; replay of the retained cases passed. These are reproducible correctness experiments, not timing benchmarks.

## Ranked enhancement and new-tool plan

Effort ranges below are planning estimates for implementation plus focused fixtures, not measured delivery times. Platform qualification and acquisition of missing physical evidence are additional work. Reuse existing tools and free upstream functionality before adding another framework.

| Rank / initial scope | Problem, users and interface | Integration and acceptance | Benefit / estimated cost |
| --- | --- | --- | --- |
| **1. Extend exporter checks through the checked runner** | Release maintainers need a failed/incomplete smoke to fail release preparation. Input: exact existing engine/package command, timeout and terminal marker. Output: bounded log plus checked JSON verdict. Keep the existing `app/export.sh` user entrypoint. | Replace duplicate grep logic, preserve failure artifacts, test all branches with diagnostic/marker mutations, then run the normal provisioned export. Godot's process status alone does not enforce repository completion evidence. | High correctness return; roughly 1–2 developer days plus hosted export qualification. No new runner. |
| **2. Add a complete catalog/descriptor roster check to the existing generator** | Aircraft/Workshop maintainers need proof that every supported runtime entry has its intended descriptor. Inputs: authoritative catalog JSON, generated descriptors, compatibility artifacts and source identities. Output: exact missing/extra/duplicate/unsupported lists and a receipt. Proposed extension: `build_descriptors.py --check-roster <catalog.json>`. | Obtain the roster through a small checked Godot adapter or a shared structured owner; do not trust a second copy of the same regex. Stage all outputs before publication; remove only explicitly owned stale artifacts. Reuse production loaders and existing generator checks. | Prevents a partial discovery from deleting usable descriptors; roughly 3–5 days, with moderate ongoing schema/ownership maintenance. Godot's importer does not know this application-specific completeness contract. |
| **3. Add strict campaign completion to flight-test and cadence runners** | Physics/performance authors need typos, missing profiles and error rows to fail automation. Inputs: requested aircraft/cases/roles/rounds plus actual output rows. Output: matched expected/observed set, invalid/refused/error status and a nonzero incomplete verdict. Proposed option: `run.py ... --strict-results --report <receipt.json>`; analogous cadence summary. | Reuse the card's authoritative case list and existing JSONL/profile outputs. Require each requested item exactly once; retain deliberate invalid-pilot results separately from missing execution. Include fresh-output/stale-profile controls. Unknown `--only` and sibling cadence error-row behavior are already documented limitations. | Saves long reruns and misleading comparisons; roughly 2–4 days per runner family and small maintenance cost as case schemas change. Do not build a new benchmark engine. |
| **4. New small audit-evidence freshness checker** | Repeated reviewers need to notice that a queue predates a repair or exact-head run. Inputs: a small manifest of audit IDs, evidence commits, owning paths and run links. Output: newer-commit/CI observations and “needs review,” never automatic “fixed.” Proposed command: `tools/ci/audit_status.py --manifest <audit-evidence.json> --out <report.json>`. | Thin read-only Git/GitHub or `gh` adapter, linked from the existing audit queue. Existing doc link checks verify destinations, not semantic evidence freshness. Begin with A27 and PT1h items; missing permissions/runs remain unknown. | Demonstrated by the six stale A27 queue entries; roughly 2–3 days plus initial mapping and ongoing ID/source ownership upkeep. No new service or broad permission requirement. |
| **5. Extend existing frame/campaign reports with explicit policy** | Performance investigators need clean-run eligibility, maximum-stall and burst context alongside percentiles. Inputs: existing raw streams, source/settings identity and owner-chosen policy. Output: reason-coded eligibility and comparable complete pairs. | Reuse `native_summary.py` and `frame_diagnose.py`; preserve A1/A24 ownership. Godot profiling and Perfetto supply measurements, while this layer validates the repository's campaign contract. Do not invent acceptable hitch limits or mix diagnostic and clean sessions. | Better decisions, not a measured speedup; roughly 2–4 days of schema/fixture work, with target-host campaigns separately required. |
| **6. Optimize reducers only after identifying a material cost** | Analysts processing large retained streams can avoid repeated sorts/parsing. Input/output formats remain unchanged. Start with shared sorted vectors for the existing nearest-rank percentile calls. | Prove identical percentile definitions and missing/nonfinite handling. Three sorts becoming one still has O(n log n) complexity; benchmark representative retained streams before claiming elapsed-time improvement. | Lower priority than result correctness; roughly 0.5–1 day per narrowly bounded reducer plus measurements. |

Do not create another general asset browser, profiler, plotting application or test framework. The repository already has a task index, checked runner, debug bridge, replay tooling, area validators and source-bound reports; Godot and existing free tools cover many generic functions. The demonstrated gaps are mostly missing guarantees at their boundaries.

## Implementation files and ownership

The candidate edits the MCP server/tests/guide (PT1h), flight-log reducer/tests/guide (FL-04), same-session cadence tool/tests/guide (DT-MAC-02/VQ-01c), and weighing reducer/tests/guide (VAL-5a). It also records this evidence and reconciles historical audit status. No generated data or runtime physics is edited. The root review integrates source changes; the independent Good Enemy review remains read-only.

The next practical action is to review the focused candidate diff, run its required CI, and then take T06 before the next release-preparation change. T07 and strict campaign completeness follow. A new tool earns a place only when it closes a demonstrated contract gap with a smaller maintenance burden than extending what is already present.
