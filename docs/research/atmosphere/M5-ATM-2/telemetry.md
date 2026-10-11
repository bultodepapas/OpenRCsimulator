# M5-ATM-2 atmospheric telemetry

**Status:** Trace v6 and focused CLI verification implemented and passing (2026-10-09). **Step:** M5-ATM-2.

Custom atmosphere flights write `openrc-trace v6` with `openrc-flight-meta v5`, the full `openrc-weather v3` configuration, the atmosphere model ID and complete kernel state. The CSV appends seven atmosphere columns after the base flight and weather columns; OU columns appear only when any turbulence RMS component is active. Density is constant for the flight. The trace reports TAS and equivalent airspeed separately, with `EAS = TAS·√(rho/1.225)`.

[`check_atmosphere_trace.py`](../../../../app/tests/check_atmosphere_trace.py) independently recomputes field pressure from geometric elevation and QNH using the ISA troposphere, then computes liquid-water Buck vapor pressure, moist and dry-air density, dry-air charge ratio, and density altitude. It checks the full metadata state against those equations, every row's constant atmosphere fields, EAS, trace timing, and weather model. Only after those checks does it project validated rows into the existing independent v4/v5 wind verifier. The reader rejects reference-atmosphere traces; those retain the legacy trace formats.

The focused real-engine test covers the four catalog aircraft at 0.1 s and 1 s in the hot-high preset (25 and 241 rows), hot-high and cool-dense presets, and a custom v3 weather file combining OU turbulence with atmosphere. It also rejects malformed atmosphere state, out-of-range and boolean inputs, reference mode in v6, corrupted density/EAS rows, changed columns and tick gaps. Invalid source weather is refused before the trace file is created. A 480-tick hot-high checkpoint has the same SHA-256 at 30, 60 and 144 FPS: `4a29bd1f1704a444ed8a63ce7008d3e8d310aa250c0789d42834c1ee22c2a187`.

For hot-high, the independent result is `rho = 0.9439353096847437 kg/m³`, `sigma = 0.7705594364773417`, dry-air charge ratio `0.754410799788835`, and density altitude `2634.5338157095093 m`. Across the four models the maximum CSV atmosphere-field error was `4.91e-10` in the trace units; maximum EAS error was below `5e-10 m/s`. The mixed OU trace's maximum independent wind/turbulence error was below `5e-10 m/s`.

**Reproduction:** `python3 app/tests/test_atmosphere_cli.py -v`; for a saved v6 trace, `python3 app/tests/check_atmosphere_trace.py TRACE.csv --duration 3`.

This proves trace and runtime consistency for the implemented uniform-field model. It does not validate local meteorology, vertical density variation, or aircraft engine maps. The kernel assumptions and limits are recorded in [M5-ATM-1](../M5-ATM-1/kernel/README.md); the companion [trim report](trim.md) covers solver density plumbing.
