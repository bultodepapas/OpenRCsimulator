# Workflow and job inventory

The baseline declares **26 jobs across eight workflows**. The candidate declares **27**. The additional job runs CI and host-tooling regressions alongside preflight. Expensive first-tier simulator jobs require both to succeed. The complete baseline and candidate configuration, including every shell command, condition, trigger path, action input and permission, is indexed by exact Git blob. [Machine-readable workflow inventory](CI_WORKFLOW_INVENTORY.json)

Baseline commit: `85a2475f60029a4b6b09f23f643119bceea84a45`. Candidate branch: `audit/ci-quality-performance-overhaul-2026-11-22`. The candidate identifiers in the JSON are content hashes of its workflow files.

| Declaration | Baseline | Candidate |
| --- | ---: | ---: |
| Workflow files | 8 | 8 |
| Job definitions | 26 | 27 |
| Step definitions | 184 | 188 |
| Shell or interpreter command steps | 100 | 102 |
| External action steps | 84 | 86 |
| Same-repository workflow calls | 2 | 2 |

A matrix job appears once in these counts. The per-job tables give its declared fan-out. A reusable caller has no steps of its own. Its called job appears once in the corresponding workflow section. Path filters, comparisons, cancellations, manual inputs and upstream failures determine the work that actually starts.

## Workflow triggers and scope

| Workflow | Candidate events | Candidate scope | Baseline to candidate |
| --- | --- | --- | --- |
| [ci.yml](../../.github/workflows/ci.yml) | Main pushes, version tags, all PRs, manual dispatch | Read-only unless publishing a version tag | Changed |
| [godtest-tooling.yml](../../.github/workflows/godtest-tooling.yml) | Path-filtered main/performance pushes and PRs, manual dispatch | Three portable operating systems | Changed |
| [metalfx-source.yml](../../.github/workflows/metalfx-source.yml) | Path-filtered main pushes and PRs, manual dispatch | Linux source and mutation controls | Same |
| [native-macos.yml](../../.github/workflows/native-macos.yml) | Reusable call or manual dispatch | macOS ARM64 source correctness | Same |
| [publication-rebind.yml](../../.github/workflows/publication-rebind.yml) | Reusable call or manual dispatch | Linux and Windows historical comparison | Same |
| [telemetry-contracts.yml](../../.github/workflows/telemetry-contracts.yml) | Path-filtered main pushes and PRs, every tag push, manual dispatch | Offline receiver and container contracts | Changed |
| [telemetry-health.yml](../../.github/workflows/telemetry-health.yml) | Daily at 09:17 UTC or manual dispatch | Public receiver health with no token permissions | Same |
| [testqueue-windows.yml](../../.github/workflows/testqueue-windows.yml) | Path-filtered main pushes and PRs, manual dispatch | Windows containment and tooling contracts | Same |

The primary CI workflow uses shadow selection. Production checks and the frozen prototype run on every eligible CI event. Only the website may skip under the current changed-path policy. Main, version tags and manual CI select export when production is selected. Unknown or unavailable comparison information selects the full union. The source-bound receipt and final verifier enforce the effective selection. [Selection policy](../../tools/ci/policy.py) · [Release preflight](../../tools/ci/release_preflight.py)

## Job decisions and dependencies

Source links refer to the job declaration in each revision. Dependency IDs are the candidate’s direct GitHub Actions prerequisites. Empty dependency lists identify jobs that are independently schedulable within an eligible workflow. The stable final gate and its policy select which results must succeed.

### CI

| Job and source | Disposition | When it runs | Direct prerequisites | Checks and risk covered |
| --- | --- | --- | --- | --- |
| `scope` · [base L36](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L36) · [candidate L36](../../.github/workflows/ci.yml#L36) | Improve | Every CI event | Independent | Verify the checked-out commit, comparison base, release inputs, UID sidecars and documentation links. It emits the source-bound selection receipt. Full commit history and tags remain available with historical blobs fetched on demand. |
| `tooling` · [candidate L64](../../.github/workflows/ci.yml#L64) | Add · Parallelize | Every CI event | Independent | Run actionlint plus the CI and Linux host-process regression suites alongside preflight. A failed checkout, linter or test fails this required job. Each regression suite can still report after an independent check fails. |
| `publication-fixture-evidence` · [base L66](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L66) · [candidate L97](../../.github/workflows/ci.yml#L97) | Keep | Manual CI with publication_rebind | Independent | Call the two-platform rebind collector. It measures source changes against one fixed accepted baseline. It is outside the publication gate. |
| `site` · [base L71](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L71) · [candidate L102](../../.github/workflows/ci.yml#L102) | Keep · Improve | Selected website changes, full-scope events and unknown changes | `scope` | Check generated locales and links, static translations, download routing and the historical GitHub analytics fixtures. The branch disables checkout credential persistence before dependency installation. |
| `three` · [base L89](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L89) · [candidate L122](../../.github/workflows/ci.yml#L122) | Improve | Every CI event under the current shadow policy | `scope` | Type-check and run Vitest, install Chromium, render three images and exercise the real keyboard-to-panel path. The candidate removes the three pre-existing PNGs and requires each to be regenerated and nonempty. |
| `app` × 9 · [base L115](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L115) · [candidate L163](../../.github/workflows/ci.yml#L163) | Keep · Improve | Every CI event under the current shadow policy | `scope`, `tooling` | Run one integration shard and eight disjoint unit shards. Integration runs schema/loader, generators, offline Python tooling, app integration and parse coverage. It now requires the real Godot client to deliver expected data to a loopback receiver. Unit shards cover discovered scripts, and the owning shard fetches the pinned historical fixed-brake sources. |
| `native-linux` · [base L286](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L286) · [candidate L353](../../.github/workflows/ci.yml#L353) | Keep · Parallelize | Every CI event under the current shadow policy | `scope`, `tooling` | Build the Linux ground-vehicle native library and verify loading, float64 behavior and reference parity. Emit a same-run binary and build receipt for pair installation. |
| `native-kernel-macos` · [base L320](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L320) · [candidate L387](../../.github/workflows/ci.yml#L387) | Keep · Parallelize | Every CI event under the current shadow policy | `scope`, `tooling` | Call the ARM64 macOS source qualification workflow. Its result is required for CI. Export does not consume an installed macOS kernel from this job. |
| `native-kernel-linux` · [base L326](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L326) · [candidate L393](../../.github/workflows/ci.yml#L393) | Keep · Parallelize | Every CI event under the current shadow policy | `scope`, `tooling` | Compile production and mutant Linux libraries, run oracle/trajectory and guard checks, install the verified library and exercise native session, replay, helicopter and simulator boundaries. Export consumes its binary and source-bound qualification inputs. |
| `native-kernel-windows` · [base L488](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L488) · [candidate L555](../../.github/workflows/ci.yml#L555) | Keep · Parallelize | Every CI event under the current shadow policy | `scope`, `tooling` | Verify the pinned Windows toolchain archive, import using the Windows engine, build and exercise native and mutant DLLs, then run installed native production checks with a byte-stable LF checkout. Export consumes the verified DLL and receipts. |
| `visuals` · [base L650](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L650) · [candidate L717](../../.github/workflows/ci.yml#L717) | Keep · Improve | Every CI event under the current shadow policy | `scope`, `tooling` | Run the complete checked visual import and render, timings, diagnostics and mutation evidence. Raw capture upload now fails if empty and has a 14-day retention period. Full render remains a required check. |
| `visual-groups` × 7 · [base L751](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L751) · [candidate L822](../../.github/workflows/ci.yml#L822) | Parallelize · Keep opt-in | Manual CI with visual_shadow | `scope`, `tooling` | Run seven isolated capture groups under the same run identity and record per-group output inventories. Experimental and allowed to fail. Preserve the complete visual job until hosted equivalence is demonstrated. |
| `visual-shadow` · [base L814](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L814) · [candidate L885](../../.github/workflows/ci.yml#L885) | Sequential | Manual CI with visual_shadow after both visual jobs | `scope`, `visuals`, `visual-groups` | Download full and group inventories, compare outputs and report differences. It must wait for producers. It is allowed to fail, and the required gate excludes it. |
| `vulkan-captures` × 2 · [base L850](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L850) · [candidate L921](../../.github/workflows/ci.yml#L921) | Keep opt-in | Manual CI with vulkan_captures | `scope`, `tooling` | Exercise the Mobile and Forward+ renderers using software Vulkan on the core capture group. Exploratory renderer coverage stays separate from the required full visual result. |
| `native-windows` · [base L897](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L897) · [candidate L968](../../.github/workflows/ci.yml#L968) | Keep · Parallelize | Every CI event under the current shadow policy | `scope`, `tooling` | Select the matching MSVC tools, then build, load, float64-check and compare the Windows ground-vehicle evaluator. The verified pair requires this artifact together with the Linux one. |
| `native-rc-runtime` × 2 · [base L1002](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L1002) · [candidate L1073](../../.github/workflows/ci.yml#L1073) | Sequential after builds · Parallelize by OS | Every CI event under the current shadow policy | `scope`, `native-linux`, `native-windows` | Both OS lanes download both ground-vehicle artifacts and install the matching qualified pair without a rebuild. Check installed-native session guards and trajectory. The cross-platform prerequisite is intentional. |
| `export` · [base L1061](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L1061) · [candidate L1132](../../.github/workflows/ci.yml#L1132) | Sequential after producers | Main, version tags and manual CI | `scope`, `native-linux`, `native-windows`, `native-kernel-linux`, `native-kernel-windows` | Install both ground-vehicle artifacts and both Linux/Windows kernel artifacts, build three platform archives and run Linux/package checks. Emits six named release files. Outer ZIP compression is disabled for the already-compressed main payloads. |
| `native-kernel-windows-package` · [base L1167](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L1167) · [candidate L1240](../../.github/workflows/ci.yml#L1240) | Sequential | Each selected export | `scope`, `export` | Download the exact release archive, verify its checksum, permit one transfer retry and reverify before extraction. Run the packaged Windows executable through all five native qualification modes and the default route. |
| `required` · [base L1258](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L1258) · [candidate L1331](../../.github/workflows/ci.yml#L1331) | Keep · Improve | Every CI event, including upstream failures | `scope`, `tooling`, `three`, `site`, `app`, `visuals`, `native-linux`, `native-windows`, `native-kernel-linux`, `native-kernel-windows`, `native-kernel-macos`, `native-rc-runtime`, `export`, `native-kernel-windows-package` | Recompute the selection from event/git data, reject omitted or unsuccessful required jobs and reconcile all parse/unit receipts against the checkout. The candidate requires the tooling result and materializes source needed to independently recompute every script digest. |
| `release` · [base L1284](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/ci.yml#L1284) · [candidate L1365](../../.github/workflows/ci.yml#L1365) | Sequential | Version-tag refs after required, export and packaged Windows success | `required`, `export`, `native-kernel-windows-package` | Verify tag, source commit, notes, run identity, manifest and archive digests. Publish with job-scoped contents write permission, then re-read the release and its assets. Per-tag concurrency serializes publication. |

### GOD TEST portable tooling

| Job and source | Disposition | When it runs | Direct prerequisites | Checks and risk covered |
| --- | --- | --- | --- | --- |
| `contracts` × 3 · [base L37](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/godtest-tooling.yml#L37) · [candidate L41](../../.github/workflows/godtest-tooling.yml#L41) | Improve | Relevant main or performance-branch pushes, PRs and manual runs | Independent | Run GOD TEST campaign and telemetry fixtures, frame-watch shutdown tests and a dry-run campaign plan on Linux, Windows and macOS. The candidate aligns GOD TEST path matching on push/PR and cancels superseded PR runs. Actual rendering and hardware FPS remain local qualifications. |

### MetalFX source controls

| Job and source | Disposition | When it runs | Direct prerequisites | Checks and risk covered |
| --- | --- | --- | --- | --- |
| `portable` · [base L31](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/metalfx-source.yml#L31) · [candidate L31](../../.github/workflows/metalfx-source.yml#L31) | Keep | Matching main pushes and PRs, or manual runs | Independent | Verify the SHA-256 of the pinned engine source archive on fetch or cache hit. Run each MetalFX engine and mutation-control suite in Linux and retain logs. This qualifies the portable patch behavior. |

### Native kernel correctness (macOS ARM64)

| Job and source | Disposition | When it runs | Direct prerequisites | Checks and risk covered |
| --- | --- | --- | --- | --- |
| `native-macos` · [base L11](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/native-macos.yml#L11) · [candidate L11](../../.github/workflows/native-macos.yml#L11) | Keep | Called by selected CI or manually dispatched | Independent | Verify Python/architecture and obtain the pinned editor. Run the ARM64 native source correctness harness and retain build, floating-point and guard diagnostics. The host inventory can be partial. Source correctness is required when the parent selects this lane. |

### Collect publication rebind evidence

| Job and source | Disposition | When it runs | Direct prerequisites | Checks and risk covered |
| --- | --- | --- | --- | --- |
| `collect` × 2 · [base L23](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/publication-rebind.yml#L23) · [candidate L23](../../.github/workflows/publication-rebind.yml#L23) | Keep opt-in | Manual workflow or explicit manual CI call | Independent | On Linux and Windows, constrain the supplied historical ref to the accepted SHA, test the collector, fetch needed historical content, and compare checked captures to the candidate. Retain manifests and capture evidence. |

### Telemetry contracts

| Job and source | Disposition | When it runs | Direct prerequisites | Checks and risk covered |
| --- | --- | --- | --- | --- |
| `contracts` · [base L30](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/telemetry-contracts.yml#L30) · [candidate L32](../../.github/workflows/telemetry-contracts.yml#L32) | Improve · Reschedule | Relevant main pushes and PRs, every tag push, or manual runs | Independent | Check schemas, generated examples, receiver/database behavior, dashboards and deployment helpers. Build a container, require healthy readiness, POST a canonical batch, check storage/UID and purge. Restricting branch pushes to main removes duplicate topic-branch runs with open PRs. An explicit all-tag pattern preserves the baseline tag coverage; GitHub does not apply path filters to tags. Real client E2E runs under the required app integration job. |

### Telemetry receiver health

| Job and source | Disposition | When it runs | Direct prerequisites | Checks and risk covered |
| --- | --- | --- | --- | --- |
| `health` · [base L15](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/telemetry-health.yml#L15) · [candidate L15](../../.github/workflows/telemetry-health.yml#L15) | Keep | Daily at 09:17 UTC or manual | Independent | With zero token permissions and no checkout, GET the configured public receiver health endpoint and require JSON status ok. An unset endpoint is an explicit no-op, so that run cannot establish deployed availability. |

### Windows test queue regressions

| Job and source | Disposition | When it runs | Direct prerequisites | Checks and risk covered |
| --- | --- | --- | --- | --- |
| `contracts` · [base L51](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/.github/workflows/testqueue-windows.yml#L51) · [candidate L51](../../.github/workflows/testqueue-windows.yml#L51) | Keep | Relevant main pushes and PRs, or manual runs | Independent | Install the pinned psutil dependency, run Windows process ownership and scheduling, MCP/debug, checked/resource runner, performance admission and GOD TEST fixtures, and preserve the Python exit status through Tee-Object. Retain unique real Windows containment coverage when considering duplicate portable fixtures. |

## Security, failure propagation and artifact boundaries

Every external action reference in both revisions points to a full commit SHA. The six distinct actions are GitHub-owned. Seven workflow files grant read-only contents and the health probe explicitly requests an empty permission set. The release job alone requests contents write. At baseline three checkout steps disable credential persistence. The candidate also disables it in CI tooling, website and prototype jobs. Source history readers keep credentials where authenticated fetches may be needed. [Checkout and permission declarations](CI_WORKFLOW_INVENTORY.json) · [Tag and release verification](../../tools/release/publish.py)

| Pinned external action | Baseline steps | Candidate steps | Commit |
| --- | ---: | ---: | --- |
| `actions/cache` | 12 | 12 | `0057852bfaa89a56745cba8c7296529d2fc39830` |
| `actions/checkout` | 23 | 24 | `11d5960a326750d5838078e36cf38b85af677262` |
| `actions/download-artifact` | 12 | 12 | `d3f86a106a0bac45b974a628896c90dbdf5c8093` |
| `actions/setup-node` | 2 | 2 | `49933ea5288caeca8642d1e84afbd3f7d6820020` |
| `actions/setup-python` | 5 | 5 | `a26af69be951a213d495a4c3e4e4022e16d87065` |
| `actions/upload-artifact` | 30 | 31 | `ea165f8d65b6e75b540449e92b4886f43607fa02` |

Linux and Windows editor cache hits rehash pinned executable bytes. Templates verify member hashes. MetalFX rehashes the archive after a cache hit. The Windows MinGW download has a pinned SHA-256 and native prerequisite locks record the godot-cpp revision and SCons wheel digest. The release-artifact consumer rechecks the Windows archive after transfer, including the one permitted retry. [Editor getter](../../app/get-godot.sh) · [Template getter](../../app/get-templates.sh) · [MetalFX controls](../../.github/workflows/metalfx-source.yml) · [Native prerequisites](../../tools/ci/release_preflight.py) · [Release workflow](../../.github/workflows/ci.yml)

The full visual render remains required. Its optional inventory, compact-diagnostic and deduplication preparations tolerate failure. Capture-group and Vulkan experiments are allowed to fail. The full capture upload falls back to the original evidence when deduplication cannot prove equivalence. A missing required capture upload fails the candidate. The aggregate recomputes selection and requires complete, source-matched script rosters. The separate contract workflows are outside that aggregate unless a reusable call is explicitly listed. [Visual and required jobs](../../.github/workflows/ci.yml) · [Phase roster verification](../../tools/ci/phase_roster.py)

The current release exporter uploads six named files together. The Windows qualification downloads that whole artifact to inspect the Windows package. Splitting platform transfers could reduce traffic. A follow-up must preserve the same-run producer, release manifest, checksums and qualification of the original bytes. Verify bytes and transfer duration before assigning a savings figure. [Exporter and package consumer](../../.github/workflows/ci.yml) · [Release manifest](../../tools/release/manifest.py)

The baseline has no repository-defined Dependabot configuration or dependency-review workflow. The telemetry Dockerfile uses a versioned base image and the website directly pins BeautifulSoup. A digest-pinned image and maintained transitive package hashes would make these inputs more reproducible. The maintenance tradeoff is regular platform-specific refresh and verification. Authentication, branch protection, runner-group access and repository billing are administered outside these files. [Receiver container](../../services/telemetry/Dockerfile) · [Website requirements](../../site/requirements-seo.txt)

## Reading the structured inventory

Choose a snapshot in `snapshots`, look up the workflow path in `files`, then take its blob ID to `documents_by_git_blob`. The `configuration` object preserves the full parsed YAML, including dispatch inputs, event filters, job and step expressions, deadlines, matrix values, environment, token permissions, shell commands, cache keys, upload paths and retention inputs. The `line_index` points to declarations and step locations. The `indices` object lists artifact/cache transactions, reuse calls and per-action counts. An omitted timeout, retention value or permission override stays omitted in the source configuration. [Workflow inventory data](CI_WORKFLOW_INVENTORY.json) · [Test effectiveness](CI_TEST_EFFECTIVENESS.md) · [Test inventory](CI_TEST_INVENTORY.json)
