# P51-25 lateral-directional probes

2026-10-15 · **Status: reusable tools.** [Plan](../../../docs/P51-REALISM-PLAN.md) · [Evidence](../../../docs/research/p51-realism/P51-25/README.md)

Each probe runs headless on the runtime equations. Each accepts `-- --data=<path>` to fly another data file (for example a disposable variant under the ignored `tmp/`).

| Probe | Output |
| --- | --- |
| `roll_probe.gd` | Rudder-fixed aileron steps through the session: peak pb/2V per degree of total aileron. Compare with NACA MR L-566 Fig. 28. |
| `modes_probe.gd` | Dutch-roll frequency, damping and cycles to half amplitude, spiral and roll time constants at 22–45 m/s (`FlightModes.analyze`). |
| `deriv_probe.gd` | Roll and yaw derivatives per β, per one-side aileron and per rudder about the CG at the β = 0 trim, split into the blended aero, oracle, local, propulsion and slipstream parts. |
| `maneuver_probe.gd` | The handling-test loop (`--which=loop --stick=0.7`) or spin (`--which=spin`), every 0.25 s. The loop summary gives peak pitch attitude and peak \|β\| up to 360° of integrated q. |

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script "$PWD/research/p51/p51-25/modes_probe.gd"
```

Steady sideslips use [`../p51-24/sideslip_probe.gd`](../p51-24/README.md).
