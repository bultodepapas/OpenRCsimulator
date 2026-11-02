# Debugging playbook

Reproduce, observe, fix, verify. Domain playbooks: [physics](debugging-physics.md), [graphics](debugging-graphics.md). Tools: [shared](shared.md). [Back to the index](README.md).

## 1. Reproduce

1. Record the exact identity: `git rev-parse HEAD`, `git status --short`, `"$(app/get-godot.sh)" --version`.
2. Find the smallest command that shows the bug, in this order of preference:
   - one existing test script through the [checked runner](shared.md#one-godot-script);
   - a direct headless launch with [flags](shared.md#launch-flags), for example `--trace=tmp/t.csv --t=3 --aircraft=<id>`;
   - a [single capture](graphics.md#single-capture) under Xvfb;
   - a recorded [flight log](physics.md#flight-log-and-replay) when the bug needs pilot input;
   - a [debug-bridge](../../tools/debug/README.md) `run` script when the bug needs menus, keys or a sequence of
     actions in the running app (`run repro.txt --fail-on-error`). A `monkey` failure already wrote one.
3. Repeat the reproducer when the failure appears intermittent or its deterministic behavior is in question. The simulation is deterministic at 240 Hz: a bug that does not repeat points at wall-clock time, threads, `user://` sharing between concurrent runs, or a working tree that changed under you.
4. If the failure is in CI, map the job to its shard (`Godot app (units N)` → `OPENRC_UNIT_SHARD=N`) and read `gh run view <id> --log-failed` ([CI](shared.md#ci)).

## 2. Observe

- Read the full engine log. `run_checked.py` keeps it as `engine.log` beside `report.json`; look for `SCRIPT ERROR`, `ERROR:`, `SHADER ERROR` and the first `FAIL` line.
- In the running app, use the bridge instead of temporary prints: `logs --summary` (errors grouped, with script
  location), `state`, `frames` (hitches and their causes), `objects` (live nodes by class, orphans), `break`
  (pause at the tick a condition becomes true), `eval`/`get` for any property.
- Print state from the test or probe script, not from production code. Put temporary probes outside `app/` (they run with `--script "$PWD/tmp/probe.gd"`) so the parse check and other tracks never see them.
- Search with `rg --glob '!app/captures/**' --glob '!tmp/**'`; check [LEARNINGS](../LEARNINGS.md) for the symptom before you dig.
- Bisect when a regression has a known good commit: `git bisect run <script that exits 0 on good>`, run in a separate worktree (`git worktree add --detach tmp/bisect <good>`) so the shared tree stays untouched.

## 3. Fix

- Change one thing. Keep simulation state in float64 and keep vehicle-specific logic out of the kernel ([AGENTS](../../AGENTS.md)).
- Regenerate generated data through its generator ([physics](physics.md#aircraft-data-and-generators)); never hand-edit it.
- For a reproducible regression missing from existing coverage, add a focused check that fails before the fix ([write a test](shared.md#write-a-test)). A rendered or device failure may need its owning capture or scenario instead.

## 4. Verify

1. The reproducing command now passes. Repeat it when investigating intermittence or replay consistency.
2. The focused checks for the touched area pass through their owning tool; run Godot scripts through the checked runner.
3. Follow the [verification scope](shared.md#verification-scope) for affected boundaries and the final CI gate. For a changed player flow, use the debug-bridge scenario or `smoke` when it covers that flow; add a scenario when existing checks leave a repeatable gap. Graphics changes need the affected area checker or capture.
4. For flight-feel, control or aircraft-physics tuning, follow the [flight-log baseline and candidate workflow](physics.md#flight-log-and-replay); add affected [flight-test battery](physics.md#flight-test-battery) cases. For shared solver changes, run the affected numerical and [golden checks](physics.md#golden-flights). Explain every listed change.
5. Put the proof (command, result, evidence path) in the commit message.
