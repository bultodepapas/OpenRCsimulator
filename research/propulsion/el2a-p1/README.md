# EL2a-P1 verification and performance tools

2026-10-11 · **Status: reproducible software qualification tools.** No measured battery or aircraft validation. [Results and scope](../../../docs/research/propulsion/EL2a-P1/README.md).

Requires the repository's pinned Godot 4.7.2 and Python 3.10+ standard library. Run from the repository root. Use durable, fresh output directories outside `app/`; no runner deletes evidence or patches the source app. Do not run benchmarks alongside other tests or rendering.

## Frozen kernels and real defects

```sh
python3 research/propulsion/el2a-p1/verify_oracles.py \
  --godot "$(app/get-godot.sh)" --app app --out /absolute/fresh/oracles
```

Copies the app and frozen research kernels into a disposable workspace, imports without the source editor cache, and requires exact positive completion counts and clean engine logs. The source oracle compares full public results and the compact stage subset against the pre-change motor/supply implementation; the rotor oracle retains the original vector solve. Native Variant bytes include numeric precision, zero signs and key types. Source fixtures are synthetic, not parameter fits.

Three actual defects are injected and reverted only in that workspace: wrong rotor reaction sign, wrong compact pack-current sign, and removal of the SOC-rate overflow guard. Each must fail the intended numerical oracle, not merely produce a parse/engine error. Final hashes must match the pristine copy. The compact app regression also checks mutation of valid motor/pack inputs between calls, boundary semantics and overflow.

## Whole-session timing and event parity

Keep a separate checkout at the documented baseline revision, then run:

```sh
python3 research/propulsion/el2a-p1/compare.py \
  --baseline-app /absolute/baseline/app --candidate-app "$PWD/app" \
  --godot "$(app/get-godot.sh)" --out /absolute/fresh/performance \
  --batches 20 --rounds 2
python3 research/propulsion/el2a-p1/test_compare.py
python3 research/propulsion/el2a-p1/audit_sources.py /absolute/fresh/performance \
  --out /absolute/fresh/source-audit.json
```

The runner imports two isolated snapshots, records source/engine hashes and changed paths, and alternates AB/BA order. Six aircraft/configurations each run powered and source-off: four electric fixtures, Stik and P-51 controls. At 240 Hz each warms 240 ticks, restores that checkpoint outside each 120-tick timed batch, then checks complete native endpoint bytes. An untimed replay fingerprints all 121 boundaries. Median and nearest-rank p95 describe **batch-average tick cost**, not individual-tick latency or rendered frames. The case set does not qualify every aircraft/regime for Gate P.

Eight separate powered-exhaustion controls reuse EL2a's near-empty 4S/6S fixtures at 120/240/480/960 Hz. The original and optimized paths must retain exactly the same seed and final checkpoint bytes. Event latency is an individual diagnostic measurement, separate from warm-batch statistics. Its root search remains unchanged. Reports keep failed/incomplete runs and reject missing cases, malformed metadata, invalid timing, checkpoint corruption and mismatched trajectories.

`bench.gd` can also run directly with `-- --out=/absolute/new.json --batches=20`. It refuses an existing output. The comparator tolerates exit code 1 only for the pinned engine's strictly checked `--version` response; normal runs must exit 0.

## Thirty-second flights and independent electrical checks

Run the existing checker once against each snapshot, with distinct directories:

```sh
python3 research/propulsion/el2/verify_flights.py --app /absolute/baseline/app \
  --godot "$(app/get-godot.sh)" --directory /absolute/new/baseline-flights
python3 research/propulsion/el2/verify_flights.py --app app \
  --godot "$(app/get-godot.sh)" --directory /absolute/new/candidate-flights
python3 research/propulsion/el2a-p1/compare_flights.py \
  /absolute/new/baseline-flights /absolute/new/candidate-flights \
  --out /absolute/new/flight-parity.json
```

The last command compares eight complete traces, checkpoint fingerprints and ten refinement endpoints. Only the CSV's single wall-clock `created_utc` line is excluded; every numeric sample and all other metadata must match. Both independent electrical/flight reports must be complete first. Full integration still requires `app/test.sh`; these tools supplement it.
