# P51-11 flaps and gear tools

2026-10-15 · **Status: research tools.** [Guide](../../../docs/P51-PLAN.md) · [Evidence](../../../docs/research/p51-realism/P51-11a/README.md)

`flap_probe.gd` runs on the runtime equations and prints:
- the trimmed maximum lift coefficient with power off, at 0/15/20/45/50° of flap (at each α, the elevator is solved for zero pitch moment);
- the elevator trim change with flaps, at the XP-51's 120 mph lift coefficient and at an equal fraction of the clean CLmax, power on and power off.

Pass `-- --data=<path>` to evaluate another aircraft or a disposable variant.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script "$PWD/research/p51/p51-11/flap_probe.gd"
```

`gear_fit_probe.gd` is the P51-11b fit study: for candidate stowed leg directions it solves the single hinge rotation that lays the main wheel flat and counts the tyre sample points outside the airframe (wing skins or fuselage); it also sweeps tail-wheel pivots and swings. Its chosen solution is authored in `source.json` `gear.retraction`.

Full-size references: NACA MR L-566 maximum lift table (gliding 1.5, landing 50° 1.6) and Table III trim changes at 120 mph.
