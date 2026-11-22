# Telemetry audit reproduction package — 2026-11-22

Reports: [TELEM-AUDIT-2026-11-22](../../../docs/research/telemetry/TELEM-AUDIT-2026-11-22/README.md).

Baseline: `7940a4081e10994f34c858c4acac3d7a1a271464`. These research scripts reproduce defects and a documented residual risk in that source. **Exit zero means the counterexample reproduced.** They are intentionally not added to the regular correctness test discovery. A future repair should convert the relevant cases into assertions of correct behavior while preserving this historical evidence.

The [second-pass package](round2/README.md) adds errors-only delivery, quota retry, invalid configuration, private import, GA4/window checks and bounded rollup/archive measurements. Its results and source/probe hashes are retained separately from this original evidence.

## Python probes

Use Python 3.12 and an isolated environment with the baseline receiver and reference requirements installed. See the owning [receiver README](../../../services/telemetry/README.md) and [reference README](../README.md) for their dependency/test workflow. The audit used Python 3.12.14. The extra `cryptography==50.0.0` was needed for the existing optional GA4 signing test, not these fake-OAuth probes.

From the repository root, with that interpreter active:

```bash
python research/telemetry/audit-2026-11-22/run_python_probes.py \
  --out /tmp/openrc-telemetry-audit-python
```

Choose a fresh directory outside the checkout. The runner sets its child temporary-data location there so the real dashboard's external-path guards remain enabled. It runs five probes, writes their logs and `results.json`, and exits nonzero when an expected baseline signature is absent. A POSIX permission probe is skipped explicitly on other operating systems.

| Script | Finding | Boundary exercised |
| --- | --- | --- |
| `integral_float_rollup.py` | TA22-R01 | In-process HTTP admission, temporary raw storage, actual daily aggregation |
| `publisher_race.py` | TA22-R02 | Two database connections, synchronized fake discovery and fake issue creation |
| `monitor_warning_probe.py` | TA22-O01 | Synthetic snapshot through actual dashboard alerts, health projection and independent checker |
| `ga4_credential_permissions_probe.py` | TA22-O02 | Fake OAuth callback/exchange and real synthetic file creation under umask 022 |
| `backup_validation_probe.py` | TA22-O03 | Structurally incomplete SQLite fixture through backup validator and actual archive reader |

No GitHub issue, OAuth provider or remote receiver is contacted. Synthetic fixture values are not credentials. The probe runner is the supported entry point; two standalone operations probes require its `OPENRC_AUDIT_TMP` environment variable.

## Godot probes

Use the repository-pinned engine obtained and verified through [the existing Godot tool workflow](../../../docs/tools/shared.md). From the repository root:

```bash
python research/telemetry/audit-2026-11-22/run_godot_probes.py \
  --godot "$(app/get-godot.sh)" \
  --out /tmp/openrc-telemetry-audit-godot
```

The runner copies the exact literal preload/load dependency closure into a fresh minimal project, hashes each source file, imports the project through `tools.godot.run_checked`, and executes each retained probe through the same checked runner. Existing host-admission enforcement is preserved. Keep the checkout stable while it runs. The evidence directory retains the project, logs, report JSON and source manifest for inspection.

The clock/context/sender fixtures are entirely local. The consent probe writes a synthetic enabled grant in its own temporary directory, makes that directory nonwritable, and restores directory permissions in `finally`. It skips explicitly when not running as a non-root POSIX user. It does not open the real player's profile. The project settings identify a separate audit user directory, and the probes supply their own consent path.

| Script | Finding / risk | Required baseline observation |
| --- | --- | --- |
| `context_boundary_probe.gd` | TA22-C01 | Mixed contexts still form one complete window |
| `epoch_boundary_probe.gd` | TA22-C02 | Old observations migrate into a later token |
| `crash_revision_probe.gd` | TA22-C03 | One detector accident is counted twice |
| `pending_age_probe.gd` | TA22-C05 | Pre-seal observation age exceeds the plain notice |
| `inflight_ttl_probe.gd` | TA22-C05 | Active retry survives original sealed deadline |
| `consent_failure_probe.gd` | Documented residual risk | Failed durable decline leaves an old readable grant |

This harness is a focused source-copy experiment. It does not run the full app, render a consent/crash UI, exercise native physical hardware, or replace the packaged release acceptance tests.

## Retained evidence

The [evidence directory](evidence/) contains original baseline test outputs, compact checked-run outputs, source hashes, the conditional timer calendar calculation and a [verification summary](evidence/verification-summary.json). The source inventory identifies baseline Git blobs; the Godot copy manifests identify exact script bytes copied into the isolated projects. Probe output may use synthetic release IDs and dates intentionally different from the audit date to exercise closed-day/week boundaries.

The [verification report](../../../docs/research/telemetry/TELEM-AUDIT-2026-11-22/verification.md) records all known limitations and the initial temporary-directory/import exceptions. No persisted artifact in this package contains live telemetry records, production secrets or a player's profile.
