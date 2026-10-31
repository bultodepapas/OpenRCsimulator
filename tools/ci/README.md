# Local checks and CI orchestration

PT1-CI. Work directly on the current checkout; these tools create no working-repository branches, PRs or commits. Tests create disposable Git fixtures only. Commands below use Linux or WSL, preferably a checkout on the Linux filesystem. [Developer setup](../../docs/TOOLS.md#developer-setup) owns the pinned engine and dependencies.

## Local entrypoint

```sh
bash tools/ci/check-local.sh quick
bash tools/ci/check-local.sh full
bash tools/ci/check-local.sh release
```

`quick` runs orchestration, partition and export fixtures; it launches no simulator or publication. `full` adds schema/offline/resource checks, complete app and visual suites, website checks and the frozen prototype. It checks the pinned Python requirements and Node major first; install those in an isolated environment, along with the existing prototype browser prerequisites. `release` first validates installed Windows/Linux ground-native and Linux NK-3 receipts, runs the full local checks and invokes the existing exporter. Missing or mismatched native inputs fail before the expensive suite. The command prints which platform/hosted gates it did not run. None of these modes publishes.

Full/release allocate fresh diagnostic directories under `tmp/local-checks.*`. Schema, app and visual checks use a fresh Godot data/config/cache profile there; inherited unit-shard settings cannot narrow the full app run. Export-template and prototype-browser downloads retain the caller's cache locations. On WSL, check free space on the Windows volume backing the virtual disk as well as Linux `df`; the latter can overstate available physical storage. The [export contract](../release/README.md) owns package identity and staging. Local success does not replace native-build qualification, the hosted event/artifact checks or desktop/device acceptance.

## Current CI behavior

[The single workflow](../../.github/workflows/ci.yml) runs on direct `main` pushes, version tags, PRs and manual dispatch. No PR is required to use it. Only superseded runs of the same PR are cancelled; main/tag/manual executions are retained. A central preflight checks clean source, tag/version/notes and existing pins before expensive jobs. The prototype stays in the same workflow, avoiding a cross-workflow dependency.

`policy.py` records changed paths and a conservative proposed scope, but **shadow mode still runs all production and prototype checks**. Six explicitly named guides are documentation candidates: `docs/README.md`, `docs/TOOLS.md`, `docs/DESKTOP-DELIVERY-PLAN.md`, `docs/plans/release-ci-efficiency.md`, `CONTRIBUTING.md` and `AGENTS.md`. Arbitrary Markdown, source/evidence/license files, deletions, non-regular files and unknown paths force the full union. Website checks run when selected. Tag/manual runs select all domains. There is no command-line switch to bypass shadow mode; activation still requires the plan's shadow-run evidence.

The scope job runs `check_docs.py` against the selected Git revisions. It checks new local links and anchors in these guides, including previously valid links that a changed target breaks. Existing unrelated link debt and links from guides outside the allowlist are not covered. External URLs are not fetched. A blanket `docs/plans/` exemption is unsafe: the fuel-system document builder consumes `docs/plans/fuel-mass-balance.md`.

The `CI required` job independently recomputes the selection from the event and Git history, verifies every selected job result, then reconciles exactly eight unit and one parse receipt against the checkout. It checks PR merge parents and fetches a missing comparison base only from the event's validated SHA. A receipt cannot choose its own comparison history. Failed, cancelled, missing or unexpectedly skipped jobs/receipts fail. Publication additionally requires export success. This job is not automatically a branch-protection setting: main had no branch protection or repository rulesets when inspected on 2026-10-31; this implementation changes neither. Release files are transferred and published by the [verified same-run helper](../release/README.md).

## App phases and coverage

The [shared app-suite guide](../../docs/tools/shared.md#full-app-suite) owns commands. Full/integration source checks call `check-sources.sh` once; its 17 generator commands include nine previously repeated in the same CI integration job. Independent oracle calls and real-engine diagnostic checks are distinct and remain required.

For local diagnosis, `OPENRC_TEST_PART` additionally accepts `integration-source`, `integration-parse` and `integration-runtime`. They are partial checks. `integration` still runs all three; the unset default also runs every unit. CI retains the existing integration job and eight modulo unit shards until split-run evidence is available. Every standalone phase still imports its own checkout safely.

`phase_roster.py` emits uniquely named `roster-*.json` only after the entire selected parse/unit list succeeds and its script/runner bytes still match. Repeated local runs retain prior receipts. CI uploads each job's receipts separately and validates exactly one parse and eight disjoint unit partitions. These receipts prove discovered-script execution, not all transitive runtime inputs or individual assertion counts. Heterogeneous runtime checks still rely on the shell exit and existing checked-runner contracts; complete runtime-case inventory remains pending.

Visual group diagnostics and `timings.tsv` are documented in [graphics tools](../../docs/tools/graphics.md#visual-capture-suite). Groups cannot be combined into complete-set evidence; CI continues to run the full capture command.

## Verification and remaining rollout

```sh
python3 -m unittest discover -s tools/ci -p 'test_*.py'
python3 app/tests/test_ci_partitions.py
python3 app/tests/test_export_identity.py
python3 -m unittest discover -s tools/release -p 'test_*.py'
```

Fixtures use disposable repositories, fake engines/checkers and mocked GitHub operations to test omission, failure propagation, input drift and release retries. They do not export or publish the simulator. The [implementation evidence](../../docs/research/release-readiness/PT1-CI-00/README.md#implementation-follow-up) lists actual results and limits. Current performance, full rendered equivalence, safe-scope activation and package rehearsal remain in the [execution plan](../../docs/plans/release-ci-efficiency.md).
