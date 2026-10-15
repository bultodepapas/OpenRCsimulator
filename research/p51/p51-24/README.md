# P51-24 sideslip tool

2026-10-15 · **Status: reusable tool.** [Plan](../../../docs/P51-REALISM-PLAN.md) · [Evidence](../../../docs/research/p51-realism/P51-24/README.md)

`sideslip_probe.gd` solves steady straight sideslips with the runtime `Dynamics.evaluate`. The sideslip is imposed. The unknowns are α, elevator, throttle (level) or flight-path angle (glide), bank, aileron and rudder, and all six accelerations are driven to zero. It prints rudder, aileron and bank per degree of sideslip at ±1° and ±2°. Compare these at equal CL with full-size steady-sideslip data such as NACA RM L6J25 Table I and MR L-566 Figure 39.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script "$PWD/research/p51/p51-24/sideslip_probe.gd" [-- --data=res://... --speeds=25.7,45]
```

Level rows include the RC propeller and slipstream; glide rows have the engine stopped.
