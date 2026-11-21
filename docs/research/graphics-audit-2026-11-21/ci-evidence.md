# GitHub, CI and artifact evidence

Inspected on 2026-11-21 against [`57abea025f62b20233ca281d58d2acbee4ab8b8e`](https://github.com/bultodepapas/OpenRCsimulator/commit/57abea025f62b20233ca281d58d2acbee4ab8b8e). This report evaluates what CI actually established, rather than treating a workflow name or a green neighboring commit as a performance result. Machine-readable observations and log excerpts are in [ci-evidence.json](ci-evidence.json); the downloaded CPU specimen is in [native-ci-specimen.json](native-ci-specimen.json).

## E1. The audited main commit does not have a successful core CI result

The main push [run 44833680915](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44833680915), created 2026-11-20 at 23:01:54 UTC, is bound to the audited SHA and concluded **failure**. The [preflight job 136624634353](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44833680915/job/136624634353) passed the orchestration/queue Python suites, then stopped on thirteen missing or invalid tracked Godot UID sidecars. Inspection of this tree confirms these thirteen are absent:

```text
app/landscapes/phoenix_flight.gd.uid
app/landscapes/phoenix_flight.gdshader.uid
app/landscapes/phoenix_images.gd.uid
app/landscapes/phoenix_library.gd.uid
app/landscapes/phoenix_objects.gd.uid
app/landscapes/phoenix_source.gd.uid
app/landscapes/phoenix_zip64.gd.uid
app/tests/test_landscape_import.gd.uid
app/tests/test_landscape_import_images.gd.uid
app/tests/test_landscape_import_zip64.gd.uid
app/tests/test_phoenix_flight_calibrations.gd.uid
app/ui/landscape_import.gd.uid
app/ui/phoenix_panorama.gdshader.uid
```

The required aggregate job also failed. The native Linux, Windows and macOS jobs, ground-native checks, app shards, visual captures, release builds and Windows native-package qualification were **skipped**, not passed and not demonstrated broken. The run had no artifacts when inspected. A successful telemetry-health workflow at the same SHA does not replace these gates.

The lead reproduced the source gate locally with the unchanged source:

```bash
python3 tools/ci/release_preflight.py --root . --event push \
  --ref refs/heads/graphics-audit \
  --sha 57abea025f62b20233ca281d58d2acbee4ab8b8e
```

It returned exit 1 with the same thirteen paths; a clean detached baseline reproduction is retained in [local-preflight.json](local-preflight.json). A retry in the worktree after documentation edits correctly stopped earlier on the dirty-source guard; that failed attempt is also retained. This report branch does not generate or add them: they belong to the Phoenix source change, and changing them here would obscure the baseline under audit. The immediate integration action is to repair the UID ownership in its source change, then obtain the required current-commit jobs. This is an evidence and release blocker, **not a measured cause of FPS loss**.

## E2. The earlier successful run has useful but bounded coverage

The latest successful core main CI found in the inspected run history was [44747723262](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44747723262), created 2026-11-20 at 13:49:36 UTC, at [`5d50481b3e1bd135fa11a9d412d10f581ee48d38`](https://github.com/bultodepapas/OpenRCsimulator/commit/5d50481b3e1bd135fa11a9d412d10f581ee48d38). Its 27 returned jobs include successful app units/integration, Linux and Windows native checks, macOS ARM64 **experimental fixed-wing source correctness**, ground-native production checks, visual captures, export builds and Windows native-package qualification. Optional visual groups/publication were skipped as configured. Those are meaningful correctness and package checks for that source identity.

The inspected app/render/simulation/native/workflow subset changed by 19 files, 915 insertions and 139 deletions between that successful commit and the audit baseline. Changes include Main, cameras/lens/wreck effects and several vehicle/contact paths. A later tree with different code cannot inherit the earlier tree's complete pass. A macOS correctness job also does not establish a native-default public package or a CPU/GPU performance gate.

### Visual CI executes a software renderer

The [successful visual job 136329178466](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44747723262/job/136329178466) explicitly logs `OpenGL API 4.5 ... Mesa 25.2.8 ... Compatibility` and `llvmpipe (LLVM 20.1.2, 256 bits)`. The workflow uses an Ubuntu/Xvfb/Mesa route. Optional Vulkan capture jobs use a software Vulkan route and are not a default physical-GPU matrix; see the [audited workflow](https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/.github/workflows/ci.yml).

These captures can catch shader errors, resource mistakes and visual regressions under the tested software implementation. They do not measure NVIDIA/AMD/Intel driver performance, Metal tile behavior, a laptop power state, display cadence, VRR or native Retina presentation. Software CI should retain this functional role; target performance needs its own hardware evidence and identity.

## E3. Inspection of an actual native artifact prevents a false FPS conclusion

The lead downloaded and inspected artifact **14636191460**, `nk3-native-linux-diagnostics`, from the older successful run. Archive size: **422,224 bytes**; 116 members; verified SHA-256:

```text
7e4600b6d29c1e064b12aa067d2c15187f46e1a7cdba432ef7d235c32a63b188
```

The retained extract contains the complete small `production-probe/session_baseline.json` and four individual case JSON reports, plus member hashes. It does not retain a signed download URL or the large release/capture archives. The runtime reviewer independently checked the same four reports.

| Property | Observed artifact value | Interpretation |
| --- | --- | --- |
| Source | `5d50481b3e1bd135fa11a9d412d10f581ee48d38` | Earlier than the audited source |
| Engine | `4.8.beta2.official.cafc17a19` | Same declared pin, with binary identity retained |
| Host | Linux x86_64, AMD EPYC 7763, 4 logical CPUs | Shared CI CPU environment, no target GPU evidence |
| Aircraft/cases | Jensen DAS Ugly Stik 60; trim and runway | Two regimes of one aircraft |
| Repeats/order | One reference-to-native pair per case | No repeated paired variation estimate |
| Warmup/sample | 24 / 240 ticks at 240 Hz | 0.1 / 1.0 simulated seconds |
| Native identity | Actual native stage-v2, ABI 2 | More than a requested-native flag |
| Counters per native case | 264 contexts; 1,056 stage calls | Native path executed in this specimen |
| Correctness specimen | Matching typed per-tick fingerprints | Not every checkpoint, event or session field |
| Scope | Detached input + session/simulation callbacks | Omits ordinary Main attachments, rendering, audio, scheduler and real OS input |

| Case | Reference callback mean | Native callback mean | Ratio reference/native |
| --- | ---: | ---: | ---: |
| Trim | 911.1875 µs | 514.7083 µs | 1.7703× |
| Runway | 1,966.3667 µs | 742.8583 µs | 2.6470× |

These are **unreplicated CPU smoke observations**, retained exactly to show the evidence boundary. They support that the native route executed and had lower sampled callback cost in those specimens. They establish neither a robust performance distribution nor any current full-app FPS gain. The visual job's llvmpipe identity must not be attached to these headless CPU probes; they are different jobs and different scopes.

## Improving the gates

1. Restore current-source preflight and full required correctness/export jobs before claiming current qualification. Keep source, engine, native source, native binary and package digests bound together.
2. Keep fast native wiring smoke in CI, but label one-pair, one-second output as smoke. A performance regression decision needs repeated current-target runs and known noise.
3. Add scheduled/manual physical-hardware lanes for selected Windows, Linux and Apple Silicon hosts, with the [platform protocol](platform-validation.md). Avoid blocking unrelated PRs on unstable shared-host FPS thresholds until that lane's variance is characterized.
4. Record process interval, GPU work and presentation as separate metrics; gate completeness, timing scope and actual backend for every vehicle before evaluating speed. Missing device fields must be missing, not zero.
5. Add focused calibration policy regressions for C1–C3 after their intended behavior is decided. Fix the existing test-owned Node lifetime before calling the strict calibration test green; see [review and validation](review-and-validation.md).

## Retrieval limits

GitHub's commit-workflow helper initially returned no PR-triggered runs for main; the generic Actions run list exposed the push runs. The former is not evidence that main lacked CI. A workflow-specific list URL was rejected by the connector; the generic branch-filtered list, exact jobs, logs and artifact APIs supplied the evidence above. GitHub CLI authentication was unavailable, so it was not used to infer run status. The retained inventory records what was retrieved; it is not an exhaustive scan of every historical run, PR or artifact.
