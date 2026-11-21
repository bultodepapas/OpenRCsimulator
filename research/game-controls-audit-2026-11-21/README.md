# Game controls audit — replay tools

These tools accompany the [21 November report](../../docs/research/game-controls-audit-2026-11-21/AUDIT.md)
at source `57abea025f62b20233ca281d58d2acbee4ab8b8e`. They use the repository's
checked Godot runner; they do not replace its tools or establish the complete
application/CI gate. The retained Linux executable is
`4.8.beta2.official.cafc17a19`; `run_checks.py` and `run_legacy_race.py` verify
both the exact version and SHA-512 before running.

## Diagnostic meaning

| Tool | Scope and expected audited-baseline result |
| --- | --- |
| `run_checks.py` | Twenty-seven selected existing suites, unchanged; serial execution in one stable checkout, isolated user data per process, checked completion/log receipts. |
| `probe_quad_pause.gd` | GCA-01: accepted radio Pause button does not pause the real activity; Escape does. Learned-axis admission is checked separately from runtime button dispatch. |
| `probe_airship.gd` | GCA-02: real role/callback chain leaves the native map stale. GCA-03: an actual lease refusal clears but Continue does not re-resolve; explicit method-level reapply is the positive control. |
| `probe_profile_ranges.gd` | GCA-05: an accepted, persisted external tiny range reaches only half its endpoint; inverted gamepad idle is 0.5 and radio readiness stays blocked. Ordinary ranges are positive controls. |
| `probe_poll_budget.gd` | GCA-O1: count callbacks in 240 valid polls. No CPU, physical USB polling or latency measurement. |
| `run_legacy_race.py` | GCA-04: two writers both return OK while one device section is lost. A deterministic barrier is inserted only into a disposable source copy; the original loader inspects the result. |

**The new probes deliberately assert the adverse baseline.** A diagnostic pass
means its stated observation was reproduced, not that the game behavior is
correct or repaired. A candidate fix should replace that adverse expectation
with a regression of the intended invariant. The ordinary existing suites have
their existing success meaning.

## Prepare a source-bound environment

Follow the repository's [shared tooling rules](../../docs/tools/shared.md) and
[checked-runner guide](../../tools/godot/README.md). Use a stable checkout of the
recorded source, the pinned engine and all tracked dependencies needed by that
checkout. A sparse checkout that lacks translations, fonts, preloads or a GLTF
texture is not a valid passing environment.

Run from the repository root. The output directory below must be new for each
attempt. Keep full local receipts even when an attempt fails.

```sh
audit_godot="$(app/get-godot.sh)"
python3 tools/godot/run_checked.py \
  --out-dir tmp/controls-audit-replay-import --label controls-audit-import \
  --timeout 240 -- \
  "$audit_godot" --headless --path app --audio-driver Dummy --import
```

Inspect the generated `report.json`, `ok`, completion and every diagnostic.
This audit's first import generated desktop/headless metadata differences.
Restoring only those owned `.import` changes and importing again produced the
committed S3TC/ETC2 cache targets with the tracked app tree unchanged. Restoring
metadata without regenerating its referenced cache targets caused rejected
resource-load attempts. Do not copy that incomplete preparation or discard
pre-existing user changes. If import changes tracked metadata, inspect and record
it before deciding how to prepare a stable checkout.

No pool was configured for the retained local runs. On an enrolled host, use
the configured pool/admission route; do not bypass its authority. Import is
serialized. Independent suites must not run concurrently in this checkout.
Use separate frozen checkouts if parallel qualification is needed.

## Existing regression context

After a successful checked import and a clean tracked `app/` tree:

```sh
python3 -B research/game-controls-audit-2026-11-21/run_checks.py \
  --out tmp/controls-audit-replay-suites --skip-import --jobs 1
```

The runner refuses a changed tracked app, unexpected untracked app files, a
different engine and an existing output directory. It records any editor-created
untracked UID files, checks that they remain stable, and hashes every selected
test. The result is valid only if every checked receipt passes and the source
remains unchanged. `--script test_rc_input.gd` (repeatable) selects a smaller
subset; report the subset actually run. There is no claim of full CI.

## Focused diagnostic probes

The following loop is serial and gives each probe separate user data. These
scripts use actual production classes with synthetic sources and direct method
callbacks, not physical SDL events or a rendered player session.

```sh
audit_godot="$(app/get-godot.sh)"
audit_root="$PWD/tmp/controls-audit-replay-probes"
for audit_probe in airship quad_pause profile_ranges poll_budget; do
  case "$audit_probe" in
    airship) audit_marker=AIRSHIP_AUDIT_COMPLETE ;;
    quad_pause) audit_marker=QUAD_PAUSE_AUDIT_COMPLETE ;;
    profile_ranges) audit_marker=PROFILE_RANGES_AUDIT_COMPLETE ;;
    poll_budget) audit_marker=POLL_BUDGET_AUDIT_COMPLETE ;;
  esac
  env XDG_DATA_HOME="$audit_root/$audit_probe/user/data" \
      XDG_CONFIG_HOME="$audit_root/$audit_probe/user/config" \
      XDG_CACHE_HOME="$audit_root/$audit_probe/user/cache" \
    python3 tools/godot/run_checked.py \
      --out-dir "$audit_root/$audit_probe/checked" --label "$audit_probe" \
      --timeout 120 --require-text "$audit_marker" -- \
      "$audit_godot" --headless --path app --audio-driver Dummy \
      --script "$PWD/research/game-controls-audit-2026-11-21/probe_$audit_probe.gd" \
    || break
done
```

Inspect all four expected receipts and `AUDIT_OBSERVATIONS` records. The loop's
shell status alone cannot prove that all four ran. An error, missing marker or
partial run must remain failed/incomplete in the report.

## Instrumented legacy interleaving

```sh
python3 -B research/game-controls-audit-2026-11-21/run_legacy_race.py \
  --out tmp/controls-audit-replay-legacy
```

This one component experiment intentionally needs two writer processes. They use
isolated user directories and share only its disposable legacy target and
scheduling markers; do not run unrelated suites or imports alongside it. The
original production calibration file is never edited. The output contains the
original/instrumented hashes, exact scheduling patch, driver, four checked
receipts, marker files and the synthetic legacy file. Writer A waits until B
has loaded its earlier snapshot; B waits for A's successful save. Both execute
the original `ConfigFile.save()` operation.

The inspector requires seed and B to survive while A is absent. This proves a
possible lost-update schedule, not its physical frequency, power-loss behavior,
or V2 concurrency. A fresh output directory is necessary so an earlier barrier
cannot satisfy the next run.

## Retained results and boundaries

The [verification record](../../docs/research/game-controls-audit-2026-11-21/VERIFICATION.md)
distinguishes accepted runs, failed preparation and draft-probe errors. Compact
receipts, hashes and observations are in the report package; full regenerated
logs stay under ignored `tmp/`. The [qualification matrix](../../docs/research/game-controls-audit-2026-11-21/QUALIFICATION.md)
lists the physical, rendered, native-platform, package and pilot checks still
unrun. Do not treat a headless probe or post-conditioning replay as those gates.
