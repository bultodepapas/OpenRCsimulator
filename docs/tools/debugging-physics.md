# Debugging physics and flight

Extends the [shared playbook](debugging.md). Tools: [physics](physics.md). [Back to the index](README.md).

## Reproduce

- Headless trace from the trimmed start: `"$(app/get-godot.sh)" --headless --path app -- --trace=tmp/bug/t.csv --t=5 --aircraft=<id> [--start=airborne] [--weather=calm]`. Every 240 Hz tick is a row; columns follow the [trace contract](../research/trace-integrity/C7-R2/README.md).
- A maneuver: run the single flight-test case that shows it, with traces for every tick: `python3 research/flight-test/run.py --out tmp/bug/ft --aircraft <id> --only trim_sweep,stall_power_off,vmax,<test> --full-traces --diagnostics`. `--diagnostics` adds `<test>.aero.csv` with α, β, airspeed and the oracle, local and blended coefficients.
- In the running app: `debugctl.py launch --headless`, `fly aircraft=<id> start=airborne`, drive it with `sticks`
  and stop at the moment it goes wrong with a watchpoint, `break expr="-s[2] < 1" wait=true` (pauses at that exact
  tick); then `state` and `step ticks=1` ([debug bridge](../../tools/debug/README.md#hunting-stutter-leaks-and-bugs-pt1h-r8)).
  It is diagnosis, not evidence: input enters at frame boundaries.
- Pilot input: record an `.orfl` and verify exact replay first ([flight log](physics.md#flight-log-and-replay)). Without exact replay, a candidate comparison proves nothing.

## Observe

- Live values per tick without a trace: `debugctl.py watch --every 24 --csv tmp/bug/w.csv h=-s[2] p="rad_to_deg(s[10])"`
  (`s` is the state: NED position, body velocity, quaternion, body rates).
- Plot or reduce CSV columns with existing free tools (Python with the visual venv, a spreadsheet, gnuplot). Do not add plotting code to `app/`.
- Check the input side before the model: servo deflections and `controls` limits, trim, rates (`--rates=full` removes pilot rate shaping), then forces and moments.
- Separate model paths with `--diagnostics`: oracle versus local surfaces shows which aerodynamic model carries the load. `--only aero_sweep` shows the same without flying.
- Integration problems: run the frame-rate-independence and golden checks (`test_golden.gd`); a divergence there points at the integrator or tick ordering, not at aircraft data.
- Known open physics limits (spins, knife-edge side force, pending rudder and yaw checks) are listed in [TOOLS](../TOOLS.md#app-and-release-commands) and the flight-test findings ([FT-05](../research/flight-test/FT-05/README.md)); confirm your symptom is not one of them.

## Verify

1. The reproducing trace or test changes as intended.
2. Battery: baseline and candidate with the same `--aircraft` and `--only`, then `compare.py`. Explain every change beyond tolerance; unexpected changes in other tests are regressions until explained.
3. Golden flights: an intended physics change fails `test_golden.gd`; re-record with `record_golden.gd` only with the explanation in the commit and the owning research report.
4. Generated aircraft data: the owning generator's `--check` passes.
5. `app/test.sh` passes, including the parse check and the float64 guard.
