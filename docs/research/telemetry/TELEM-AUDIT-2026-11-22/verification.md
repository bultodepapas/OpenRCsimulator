# Verification record

Part of [TELEM-AUDIT-2026-11-22](README.md). Audited production source: `7940a4081e10994f34c858c4acac3d7a1a271464`. The audit branch adds documentation and research fixtures; runtime source was kept at that baseline during the checks.

## Environment and provenance

| Item | Observed value |
| --- | --- |
| Platform | Linux, non-root user; disposable isolated worktree and external temporary-data directory |
| Python | 3.12.14, isolated virtual environment |
| Receiver/reference dependencies | Exact pins from baseline `services/telemetry/requirements.txt` and `research/telemetry/requirements.txt` |
| Additional test dependency | `cryptography==50.0.0` to execute the optional GA4 RS256 test; no production dependency file changed |
| Godot | `4.8.beta2.official.cafc17a19`, repository-pinned Linux x86_64 binary verified by `app/get-godot.sh` |
| Godot SHA-512 | `428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9` |
| Engine invocation | Repository checked runner, retained engine logs, explicit completion markers, bounded timeouts |
| Host admission | Host not enrolled in the test queue; no pool configuration present. The existing checked runner's admission logic remained active. |
| Data | Synthetic fixtures, temporary SQLite files, fake OAuth/GitHub clients, and an actual loopback receiver for the existing Godot bridge |

The [primary-source inventory](../../../../research/telemetry/audit-2026-11-22/evidence/source-inventory.json), [Godot probe source hashes](../../../../research/telemetry/audit-2026-11-22/evidence/godot-probe-source-sha256.json) and [baseline isolated-copy hashes](../../../../research/telemetry/audit-2026-11-22/evidence/baseline-copy-sha256.json) identify the source used. An isolated Godot project supplied minimal project settings and exact copied scripts; its success is scoped to those scripts, not the full application project or its assets.

## Existing checks executed

| Check | Result | Retained evidence |
| --- | --- | --- |
| Receiver: `unittest discover -s tests -t . -v`, from `services/telemetry` | 142 discovered: 141 passed, Godot E2E initially skipped because `OPENRC_GODOT` was unset | [Receiver output](../../../../research/telemetry/audit-2026-11-22/evidence/receiver-tests.txt) |
| Reference/contracts: `unittest discover -s research/telemetry -p 'test_*.py' -v` | 128 passed, including property tests | [Reference output](../../../../research/telemetry/audit-2026-11-22/evidence/reference-tests.txt) |
| Dashboard, GA4, release metrics, backup, private sync and GitHub history test modules | 102 discovered: 100 passed, 2 Windows Task Scheduler cases skipped on Linux | [Operations output](../../../../research/telemetry/audit-2026-11-22/evidence/operations-tests.txt) |
| `tests.test_godot_e2e` with the pinned `OPENRC_GODOT` configured | 1 passed, resolving the receiver discovery skip | [Real loopback bridge output](../../../../research/telemetry/audit-2026-11-22/evidence/godot-e2e-test.txt) |
| `test_telemetry_queue.gd` | Passed; required completion text present; 0 errors/warnings | [Checked Godot suite results](../../../../research/telemetry/audit-2026-11-22/evidence/godot-baseline-suites.json) |
| `test_telemetry_service.gd` | Passed; required completion text present; 0 errors/warnings | Same results file |
| `test_telemetry_sender.gd` | Passed against its loopback fake; 0 errors/warnings | Same results file |
| `test_telemetry_admission.gd` | Passed; required completion text present; 0 errors/warnings | Same results file |
| `test_telemetry_contract.gd` | Passed with its literal preload dependencies copied; 0 errors/warnings | Same results file |
| `generate_contracts.py --check` | “Contracts match source.” | [Verification summary](../../../../research/telemetry/audit-2026-11-22/evidence/verification-summary.json) |
| `generate_examples.py --check` | “Examples match source.” | Same summary |

**Distinct Python total: 370 passed, 2 unresolved platform-specific skips.** The Godot bridge is one of the 142 receiver tests, rerun successfully on its own; adding 142 + 128 + 102 + 1 as independent test cases would double-count it. The five GDScript suites are reported as suites, not added to the Python test count.

The six operations modules were `tools/telemetry/test_dashboard.py`, `test_ga4.py`, `test_release_metrics.py`, `tools/telemetry/deploy/host/test_openrc_stats_backup.py`, `tools/telemetry/deploy/test_sync_private_github.py`, and `tools/analytics/test_github_history.py`. Their owning READMEs and the baseline [workflow](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/.github/workflows/telemetry-contracts.yml#L46-L69) provide the ordinary suite invocation. The [first-pass evidence](../../../../research/telemetry/audit-2026-11-22/evidence) records the probe outcomes and source hashes.

## New counterexamples

The portable runners were executed after packaging the probes. The final minimal Godot project imported successfully, and all six scripts completed without diagnostics. These are counterexamples: **exit zero means the baseline bug or residual risk reproduced**. After a repair, their current assertions should fail until intentionally converted into expected-correct regression tests.

| Finding / risk | Probe | Observed signature |
| --- | --- | --- |
| TA22-R01 | `integral_float_rollup.py` | 20 healthy + 1 changed numeric representation all accepted 202; 21 stored; `insight_cell`; no day status or rollup commit |
| TA22-R02 | `publisher_race.py` | Two `published` outcomes; fake create count 2; one final ledger number |
| TA22-O01 | `monitor_warning_probe.py` | Four actionable dashboard warnings; `health_status=ok`; empty `receiver_issues`; independent check returns no failure |
| TA22-O02 | `ga4_credential_permissions_probe.py` | Synthetic credentials mode 0644, newly created parent mode 0755 under umask 022 |
| TA22-O03 | `backup_validation_probe.py` | Backup validator passes; actual archive reader fails on missing `asset_glob` column |
| TA22-C01 | `context_boundary_probe.gd` | Complete 30-second window combines 15 seconds at each resolution and is labeled 2160p |
| TA22-C02 | `epoch_boundary_probe.gd` | Old token survives the first post-boundary frame; new epoch receives pre-boundary takeoff and full 48-second summary |
| TA22-C03 | `crash_revision_probe.gd` | Valid same-accident revisions `[0,1]`; count 2, or slice counts `[1,1]` |
| TA22-C05 | `pending_age_probe.gd` | Event from t=0 remains sendable at t=659 after sealing at t=60 |
| TA22-C05 | `inflight_ttl_probe.gd` | Retry at 599; active at deadline 600 with zero cancellation; response accepted at 601 |
| Consent residual | `consent_failure_probe.gd` | Current process off, save error 12, previous grant still readable, next service instance on |

Full concise outputs are retained in [Python probes](../../../../research/telemetry/audit-2026-11-22/evidence/python-probes.json) and [Godot probes](../../../../research/telemetry/audit-2026-11-22/evidence/godot-probes.json). The Godot file includes checked-run identity, duration, diagnostic counts and log SHA-256. The Python runner captures each exit code and stdout/stderr. Both runners use fresh temporary synthetic data and make no production calls.

TA22-O04 additionally uses the [systemd calendar output](../../../../research/telemetry/audit-2026-11-22/evidence/backup-timezone.txt): with `TZ=America/Bogota`, the unqualified 02:40 CT backup resolves to 07:40 UTC while the UTC-qualified exporter remains 02:55 UTC. The pull unit's 03:15 UTC follows directly from its unit definition. This verifies the conditional scheduling calculation, not the effective timezone of a deployed machine.

TA22-C04, TA22-H01 and TA22-L01 use source traces. Their proposed integration/fault-injection checks were not run. The reports keep that difference visible instead of treating plausible runtime consequences as observed production facts.

## Environment adjustments and incomplete attempts

1. This host initially placed Python temporary directories inside the checkout. The dashboard/GA4 path guards correctly refused some synthetic fixtures, yielding 2 failures and 7 errors in the first operations attempt. Setting `TMPDIR` to an external scratch directory resolved that environment issue; the complete rerun passed 100 tests with the same 2 Windows skips. This is not recorded as a product defect. The portable Python runner explicitly requires external output/temp storage.
2. A later expanded isolated editor import was terminated by signal 9 after 33.885 seconds, with only the engine banner retained. Its cause was not established. The explicit contract and detector-related scripts subsequently completed, and the final smaller probe project imported successfully. This sequence supports the focused results; it does not support claiming a completed full-project import.
3. The initial default receiver suite's Godot skip was deliberately resolved by configuring the verified engine and executing the existing end-to-end bridge with exact copied source. The two Windows-specific skips were not resolved on Linux.

These exceptions are also retained in the [machine-readable summary](../../../../research/telemetry/audit-2026-11-22/evidence/verification-summary.json). They should remain attached to the verification claim rather than disappearing behind an aggregate “all tests passed.”

## Checks not performed

No production host, real player's consent file, live raw/aggregate database, real OAuth exchange, real publication, off-site backup restore or notification target was exercised. No current secret, endpoint variable, host timezone, proxy header/log configuration, OS ACL or deployed source SHA was inferred from old reports.

The full `app/test.sh`/release pipeline, rendered `test_telemetry_app.gd`, local ground recording tests, RC-track flight/HUD rendering, real disk-full export failure, Windows/macOS package behavior and physical display/performance qualification were not run. Docker was unavailable, so the receiver container build/smoke step was not executed locally. These are explicit acceptance gaps for repairs and deployment qualification, not failures observed by this audit.
