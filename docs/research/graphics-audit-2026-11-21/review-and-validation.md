# Review method, reproductions and limits

## Source and delegation

The lead created `graphics-audit` from main at **`57abea025f62b20233ca281d58d2acbee4ab8b8e`** and used a separate worktree. The audit followed root/scoped instructions, the [subagent guide](../../SUBAGENTS.md), [documentation ownership](../../README.md), rendering/tool rules and the repository's existing OpenRC tool skill. The final change is research documentation, isolated research scripts and retained evidence; it changes no application, shader, native library, engine pin, workflow or production test.

Three concurrent specialists were given self-contained briefs with the exact source identity, read-only source scope and owned scratch draft paths. The tool requests selected `gpt-6.1-terra` with `max`, as preferred by the guide; effective runtime model/effort were not independently attested. ChatGPT Work did not load the repo's local Codex profile automatically. The lead kept Git, application execution and integration ownership; helpers did not stage, commit, push, launch a game or run a benchmark.

| Assignment | Delivered evidence | Independent challenge |
| --- | --- | --- |
| Rendering/landscape review | Ten source-grounded findings plus rejected repaired leads | Good Enemy checked trigger/cost scope and counterevidence |
| Runtime/native review | Eight findings, native-route matrix, historical evidence limits | Good Enemy checked timer boundaries, native policy and repeated work |
| Graphics-policy/Good Enemy | Six calibration/measurement findings and synthetic cases | Rendering reviewer checked lifecycle reachability, fixture and formatter semantics |
| Lead CI/math integration | Exact-run jobs/logs, downloaded native artifact, arithmetic and checked policy execution | Runtime reviewer independently checked artifact and cost assumptions |

N5 and R3 describe the same staged-loading boundary and are cross-linked rather than counted as two independent causes. All required drafts and cross-reviews were collected. The Good Enemy also read the integrated executive report, native priorities and this validation report and returned no material blockers. Findings remain conditional where a device measurement is absent.

## Material review decisions

| Challenge | Resolution in this report |
| --- | --- |
| Companion work is not all outside `step_usec` | Corrected: planning-tick snapshot in `before_step` is inside; serial post-step prepare/advance is outside |
| Meadow does not sort every candidate | Corrected: full candidate scan, capped-species subset sorting; nominal density fractions are not exact output counts |
| A formatter example injected the rejected renderer's measurement | Replaced with a same-method Standard record; test explicitly does not run `runtime()` or the UI |
| Fixed fixture project name did not isolate each user profile | Final reproducer assigns fresh XDG data/config/cache directories inside its output; `HOME` remains untouched |
| High-only reconstruction cannot always be changed from Standard | C2 uses reachable AA changes and explains High/restart timing, saved intent and remeasurement escape routes |
| Historical Mac reference-only wording conflicts with code | Current Main/domain and later owner decision govern source admission; public-package and experimental-native qualifications remain separate |
| One-second native CPU ratios could be mistaken for FPS | Archive decoded and scope retained; llvmpipe belongs to a different visual job; no current rendered gain claimed |
| Cross-agent batching is not a simple native wrapper | Added stage dependency, divergence, transaction and fleet-replay limits; recommend individual admission first |
| Old cloud-cache, zero-opacity and calibration findings were already repaired | Excluded those as current defects; residual cases explicitly identify the narrower gap |
| Assertions passed while engine cleanup warned | Strict regression remains failed; preserve diagnostic rather than suppressing it |

## Execution environment and pinned engine

Host observation: Linux x86_64, nine available logical CPUs, no display environment and no GPU device under `/dev/dri`; OpenRC queue enrollment was false and no configured test-pool endpoint was available. This is adequate for read-only analysis and the isolated policy fixture, not target rendering or presentation. No hardware FPS, frame-pacing, VRAM or thermal result was produced.

The local official Linux engine was verified against the repository's download checksum, copied to the audit worktree's ignored tools directory and queried as **`4.8.beta2.official.cafc17a19`**. SHA-256:

```text
34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564
```

SHA-512:

```text
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

The [official beta2 release](https://github.com/godotengine/godot-builds/releases/tag/4.8-beta2) identifies engine source `cafc17a192acf67903910a68aeb3c076c0907a4b`. The exact engine source files could not be retrieved through the web service, so general Godot documentation is not presented as exact-pin implementation inspection. Application source, engine binary identity and executed fixture behavior are separate evidence.

## Reproduce the policy witnesses

From the repository root, with the pinned official Linux x86_64 binary available:

```bash
python3 research/performance/graphics-audit-2026-11-21/reproduce.py \
  --out /absolute/new-empty-audit-output \
  --godot .tools/Godot_v4.8-beta2_linux.x86_64
```

The script accepts only the recorded engine version/checksum. It extracts 15 unchanged transitive source/data dependencies from the audited Git object, copies their available tracked UID sidecars, creates a minimal fixture without application autoloads/plugins and uses a separate XDG profile per run. It does not modify the audited source, substitute fake production functions, render a GPU workload or import the complete app. The fixture selects Forward+ configuration solely so setting an FSR2 viewport property does not trigger a Compatibility warning under headless Dummy execution. This is not proof that FSR2 ran.

The repository's unchanged `tools/godot/run_checked.py` checks import, the synthetic probe and the existing calibration test sequentially, with completion markers and **warnings as errors**. The manifest records dependency, probe, runner, fixture and engine hashes, and verifies source/engine bytes remain unchanged. The result is deliberately nonzero when the existing regression test emits its warning; the script does not redefine success to hide it.

### Final result

| Check | Assertions / process result | Strict checked result | What it establishes |
| --- | --- | --- | --- |
| Minimal dependency import | Completed | Pass, zero warnings/errors | The isolated source closure imports with the pinned engine |
| Synthetic policy witnesses | 24 checks, 0 failed; exit 0 | **Pass**, zero warnings/errors | Stored High-veto asymmetry, reconstruction identity collision, classifier/floor examples and pure formatter mismatch |
| Unchanged `test_auto_calibration.gd` | 94 checks, 0 failed; exit 0 | **Fail**, one ObjectDB Node leak warning | Assertions passed, but this is not a clean regression gate |
| Source/engine stability | Exact bytes checked | Pass | The probe did not patch production dependencies or engine |
| Current source preflight | Thirteen absent UID sidecars; exit 1 | Fail | Same baseline integration failure as CI |
| Hardware/full app/presentation | Not executed | Pending | No GPU, UI-restart, native FPS or cross-platform conclusion |

Full bounded command receipts and excerpts are retained in [policy-checks.json](policy-checks.json), including earlier failed/corrected attempts. Run 1's Compatibility fixture caused an FSR2 warning despite passing assertions; run 2 corrected only the fixture configuration. Run 3 corrected the formatter example; run 4 added per-run user-profile isolation and is the final reproducible candidate. Early runs used a separate fixed fixture project name but did not have per-run XDG isolation, so they are not claimed as concurrently isolated. All runs preserved the production calibration path.

### Test-owned node leak

The unchanged test's `_test_view_tracking()` constructs `AutoCalibration.new(Node.new(), ...)`, frees the calibrator, and does not retain/free the supplied session Node; see [test source](https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/tests/test_auto_calibration.gd#L376-L398). A separate verbose diagnostic reported one leaked Node outside the scene tree, consistent with that lifetime. Verbose mode additionally produced a host GameMode warning and an engine path-reporting error while describing the orphan; these are diagnostic-run observations, not production FPS failures. The final ordinary checked run has the one cleanup warning above.

Fixing the test-owned Node lifetime is a small separate test maintenance change. This audit leaves the existing test unchanged and does **not** infer a production calibration leak from it. No additional broad test rerun was justified by a documentation/research-only change.

## Scope of the reproduced findings

- C2: the probe invokes real persistence, workload matching and startup-planning functions with injected synthetic facts. It does not perform a desktop restart. AA-only, size-only, combined, unchanged and already-fixed smaller-output controls are distinguished.
- C3: it obtains different reconstruction policies, assigns distinct viewport mode properties and observes identical workload dictionaries under the dummy backend. Actual reconstruction execution and GPU cost require the target renderer.
- C4/C5: 300 deliberately repeated positive values and a 120 Hz input expose classifier semantics. Equal values do not prove a real device returned stale readings, and a 60 Hz floor is an intentional policy rather than an asserted display failure.
- C6: it executes the pure formatter with a current-method synthetic record. The production UI route and wording remain a source-grounded follow-up.
- C1: pause/settings reachability and retained-sample behavior were independently source-reviewed; the fixture does not execute the full `_process` sampling lifecycle or a rendered pause/resume.

## Integration verification

The lead checks the final research files, source anchors, relative links, JSON syntax and arithmetic reproducibility, then runs `git diff --check` and verifies that application, engine, native and CI paths remain unchanged from the audit base. Only the dated reports/evidence, dated research scripts and navigation entries are staged. Branch publication is a documentation/research delivery, not merge approval, implementation of the proposed optimizations or a new green production CI claim.
