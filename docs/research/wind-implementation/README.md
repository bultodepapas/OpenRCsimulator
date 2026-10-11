# Playable wind and gust delivery

2026-10-09 · **Status: implemented and software verified.** Owner-selected scope: [WIND-PLAN](../../WIND-PLAN.md), M5-W01a…d/W02b/W03b. Independent pilot/atmosphere validation and wind gates remain open.

Subsequent delivery: [M5-W04a seeded temporal OU turbulence](M5-W04a/README.md). The evidence below describes the earlier uniform-wind/repeating-gust slice.

Home → **Weather** now configures uniform wind, horizontal and vertical repeating gusts, direction, duration and period. Calm remains the default. The editor supports EN/ES, presets, precise unchanged values, Apply/Cancel, persisted preferences and read-only future settings. Restart repeats the weather pattern. Direct CLI presets/files/overrides use the same validation and ignore interactive preferences.

## Physics and replay proof

- **54 field/config checks:** finite typed bounds, cardinal signs, meteorological-from conversion, zero air-relative flow, pulse peak/endpoints/area, pure query order, detached values and physical time beyond the 1024 s shader wrap.
- **51 flight checks:** four-aircraft uniform-wind Galilean invariance, correct air-relative loads/shaft inflow, stage-time queries, reset at t=0, atomic rejection and exact same-/cross-session weather checkpoint continuation. Maximum measured world-position residual against W·t is 1e-12 m. A 1.5 m/s windy Stik runway hold has <1e-12 angular residual and no measured drift over ten seconds. Manufactured cosine forcing at 30/60/120 Hz gives errors 1.3831e-7 / 8.6359e-9 / 5.3961e-10 m and ratios 16.016 / 16.004. This proves the temporal RK implementation; existing sampled RPM/downwash policies do not become fully coupled fourth-order dynamics.
- **29 trace checks and 9 HUD checks:** calm retains v3/v1 identity; wind uses v4 telemetry/v2 checkpoints. TAS/horizontal GS and state/k1 wind/time are distinct; mid-flight first loads use the recorded preceding state. Invalid weather/time/state/quaternion recordings refuse saving. The HUD has no bearing for zero horizontal flow and localizes the new weather line in Spanish.
- **45 weather UI checks:** draft precision/cancel, pending text, six values and preserved delay, presets, radio isolation, schema recovery/future-file refusal and Home→flight handoff. Existing Home/aircraft/language/Help/runway tests also pass. Rendered capture found and corrected Spanish overflow; all [nine release captures](M5-W03b/README.md) now have zero layout findings.
- **Real weather CLI tests:** six Python tests cover steady/updraft/gust traces, file/override routing, invalid flags/JSON/version/refused output and ten corrupted/truncated reader cases. An independent scalar quaternion matrix and pulse equation check actual v4 columns at CSV precision.
- **Render FPS independence:** active gusts and real injected keyboard commands at 30/60/144 FPS all reach tick 480 with SHA-256 `ce81c6c1c55ba01bc58acd48237a19d1acd19c153d8404184b35b823d238e6e9`.
- **Full regression:** the stable integrated `app/test.sh` exits 0 with **132 GDScript programs**, the new CLI checks, unchanged goldens, four default trimmed traces, FPS equality and ground checks. The frozen baseline suite also passes. [Evidence manifest](M5-W01d/manifest.json) identifies all inputs and completed artifacts.

## Performance and package proof

[Fleet comparison](M5-W01a/README.md) preserves complete calm state/aux/continuous/modes/inputs/loads and hashes at 0/240/480 for every aircraft. All steady/active-gust trim/stall/ground batches finish without numerical faults. The highest observed median is P-51 stalled gust flight at 530.08 µs/tick; the baseline was already 509.86 and host load overlapped measurement. This does not establish the 500 µs target budget or isolate a wind bottleneck. Gate P remains open.

Linux, Windows and universal macOS preview exports use the existing presets/templates. Native Linux runs steady/gusty/updraft traces for three seconds from an empty working directory; all **721 rows per case match source numeric rows byte for byte**, and the independent weather reader passes. Windows/macOS version fields and macOS universal ad-hoc signatures pass existing package checks. Native Windows/macOS launch, target GPU and physical-radio acceptance are separate. Preview files live locally in `dist/wind-preview/`; tracked [package proof](M5-W01d/package-smoke.json) stores identities rather than links into that ignored folder.

Structured project validation and three-scene input-fuzz smoke have zero engine/parse/configuration errors and zero physics-layer findings. Static lint retains 12 existing warnings. The broad scan includes ignored local capture copies and retains inherited warnings; scene/trace processes also emit known shutdown/driver warnings. Newly introduced class/parameter warnings were removed. This is not a warning-free whole repository.

## Scope and source accuracy

The physics uses one float64 air-velocity field through aero, propeller/shaft inflow, wake and downwash. It keeps inertial state and ground contact velocities unchanged. Only an airborne start adds wind to the initial ground velocity; no second wind force or position drift is invented. The field is stateless, deterministic and uniform; its regular pulses are authored practice inputs, not random atmospheric turbulence.

The current windsock shape/cloud drift are provisional and are not a calibrated wind response. Spatial gradients, stochastic/OU/Dryden turbulence, atmospheric density changes, seeded schedules and continuous flight-time editing remain future steps. Aircraft input data and aerodynamic coefficients are unchanged. Mathematical verification does not validate the inherited aircraft models or a real flying site's gust statistics.

Primary-source conventions and the original research remain linked from the [wind plan](../../WIND-PLAN.md). All new runtime code is original; no new engine/library dependency was added. Detailed old design is retained in commit `6973e42` and the existing research notebooks.

## Run and verify

```sh
"$(app/get-godot.sh)" --path app
"$(app/get-godot.sh)" --headless --path app -- --weather=gusty --trace=/tmp/gust.csv --t=5
python3 app/tests/check_wind_trace.py /tmp/gust.csv --duration 5
app/test.sh
```

Use Home → Weather for manual flying. Technical routes support `--weather=calm|steady|crosswind|gusty|updraft`, `--weather-file=path.json` and SI numeric overrides described in WIND-PLAN. Trace v3-only readers intentionally refuse windy v4 files.

Ready-to-paste commit message:

```text
feat(wind): add playable uniform wind and repeatable gusts

Proof: 54 field, 51 flight, 29 trace, 9 HUD and 45 UI checks; full app suite
(132 programs + CLI tests); exact calm fleet parity and wind checkpoint replay;
30/60/144 FPS equality; nine rendered captures; three export/source trace pairs.
Measured performance and physical/pilot/native-platform limits remain documented.
```
