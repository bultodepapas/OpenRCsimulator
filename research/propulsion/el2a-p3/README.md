# EL2a-P3 qualification tools

2026-10-11 · **Status: software qualification complete; repeatable speedup and physical acceptance remain open.** [Implementation and evidence](../../../docs/research/propulsion/EL2a-P3/README.md).

Use the pinned Godot 4.7.2 and Python 3.10+. Output directories must be fresh and outside `app/`. Defect injection runs only on disposable app copies. Run performance measurements without other Godot/test/render workloads.

```sh
python3 research/propulsion/el2a-p3/verify_motor.py \
  --godot "$(app/get-godot.sh)" --app app --out /absolute/fresh/motor
python3 research/propulsion/el2a-p1/verify_oracles.py \
  --godot "$(app/get-godot.sh)" --app app --out /absolute/fresh/oracles
```

The motor oracle pins the frozen pre-P1 implementation's LF source SHA-256 while recording raw checkout hashes. It compares native Variant bytes for both the full public result and the compact consumed subset. Fixtures include rest, drive, coast, disabled operation, malformed/nonfinite inputs, finite-input overflow and mutable definitions. Production defects must produce the intended comparison failure, not a parse/runtime error. Original source bytes are restored after each mutation. The runner requires the exact engine version, zero exit status and completion counts, and rejects output inside the source app. Eight `test_verify_motor.py` controls cover source pinning across LF/CRLF, source edits, completion/exit/error evidence, mutation anchors and recursive-copy prevention.

Reuse [P1's whole-session comparison](../el2a-p1/README.md#whole-session-timing-and-event-parity) for exact native checkpoints, all replay boundaries, eight exhaustion controls and AB/BA timing. Use separate identical baseline/candidate source snapshots except for the intended implementation/test changes.

```sh
python3 research/propulsion/el2a-e1/verify_envelope.py \
  --godot "$(app/get-godot.sh)" --app app --out /absolute/fresh/maneuvers
python3 research/propulsion/el2a-p3/compare_envelope.py \
  /absolute/baseline/maneuvers /absolute/fresh/maneuvers \
  --out /absolute/fresh/maneuver-parity.json
python3 research/propulsion/el2a-p3/test_compare_envelope.py
```

The comparator requires both independent twelve-case E1 reports to pass, matching engine/driver/verifier identity, raw trace hashes and complete row counts. It compares every CSV byte except the single `created_utc` header. Only the artifact path and timestamp-dependent raw hash are excluded from report comparison; metric types remain significant. Eight synthetic negative/positive controls cover corruption, changed samples/metrics, duplicate cases, incomplete verification and mismatched engine identity. This supplements `app/test.sh` and `research/test-tools.sh`.

## Component CPU diagnostic

`measure_supply_cpu.py` is Linux-only (`resource.RUSAGE_CHILDREN`). It runs the same `bench_supply.gd` against two supplied app snapshots, alternating ABBA twice. Each process validates 120 synthetic points before 300,000 supply calls; result and accumulated-output byte hashes must agree. Child user+system CPU includes process startup and compilation; loop wall time is recorded separately. Concurrent host work can still affect cache/frequency behavior, so this diagnostic cannot establish full-tick or real-time performance.

```sh
python3 research/propulsion/el2a-p3/measure_supply_cpu.py \
  --baseline-app /absolute/baseline/app --candidate-app "$PWD/app" \
  --godot "$(app/get-godot.sh)" --out /absolute/fresh/supply-cpu
```
