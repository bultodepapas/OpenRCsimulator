# EL2a-P2 event qualification tools

2026-10-11 · **Status: reproducible software qualification; physical acceptance remains open.** [Evidence and numerical contract](../../../docs/research/propulsion/EL2a-P2/README.md).

Use pinned Godot 4.7.2 and Python 3.10+. Run from the repository root with durable, fresh output paths outside `app/`. These tools copy source before injecting defects; they never mutate the source app. Timing runs must execute alone, without other suites or rendering.

## Analytic crossings and real defects

```sh
python3 research/propulsion/el2a-p2/verify_localization.py \
  --godot "$(app/get-godot.sh)" --app app --out /absolute/fresh/localization
```

Requires exact positive completion counts for the new analytic event tests and the existing stop/battery-step tests, then rejects five actual code defects. Engine/parse failures do not count as defect detection. Original file bytes are restored after every mutation and the pristine event suite runs again. The report records source, test and engine hashes; logs remain beside it.

## Independent scalar physics references

```sh
python3 -m venv /absolute/research-env
/absolute/research-env/bin/pip install -r research/propulsion/el1a-r2/requirements.txt
/absolute/research-env/bin/python research/propulsion/el2a-p2/verify_independent.py \
  --godot "$(app/get-godot.sh)" --app app --out /absolute/fresh/independent.json
```

Reuses the existing EL1d/EL2a analytic and SciPy DOP853 equations, fixtures and tolerances. NumPy 1.26.4 and SciPy 1.11.4 are required exactly. Complete raw probe output, source/probe/verifier hashes and all check results are retained. The wrapper handles the pinned engine's `--version` exit convention without weakening normal process checks.

## Paired real-session event measurements

Keep a baseline checkout at `5f85109ada405071864ee1c3c5c2a97ecaa4bc84`:

```sh
python3 research/propulsion/el2a-p2/compare_events.py \
  --baseline-app /absolute/baseline/app --candidate-app "$PWD/app" \
  --godot "$(app/get-godot.sh)" --out /absolute/fresh/performance --rounds 6
python3 research/propulsion/el2a-p2/test_compare_events.py
```

Six cases cover powered/coasting battery exhaustion on 4S/6S, a fixed-bus rotor stop and a no-event battery control. Each run starts from a fresh trimmed session. Alternate AB/BA order; timing covers only each accepted event's full simulation tick. Compare event states within predeclared component bounds and complete native checkpoints exactly across repeats of each implementation. Cross-version event bits may change; the no-event control must retain exact bytes. Reports and checkpoint blobs remain under the output folder. `--smoke` checks one short case only and cannot establish repeatability or performance.

The report parser has eight regression tests covering missing events, incomplete tick counts, malformed/nonfinite layouts, changed replay, byte corruption and tolerance violations. They run in the ordinary `research/test-tools.sh` suite.

## Complete application and flight regression

Run `app/test.sh` from a fresh candidate checkout with isolated runtime settings. For the independent eight-flight/48-corruption check, use `research/propulsion/el2/verify_flights.py` against both snapshots. Compare the resulting complete no-event traces, checkpoints and refinement endpoints with `research/propulsion/el2a-p1/compare_flights.py`. These supplement the event probes; they do not establish measured motor, battery or aircraft accuracy.
