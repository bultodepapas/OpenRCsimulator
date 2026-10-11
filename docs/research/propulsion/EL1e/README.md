# EL1e — Two synthetic electric aircraft configurations

2026-10-10 · **Status: flight/product proofs and full app regression pass; experimental configurations only. Step prefix: EL.**

The canonical 4S/800 Kv and 6S/400 Kv fixtures exercise one loader/trim/physics implementation with independent configuration and state. They retain the Stik's mass, CG and locked inertia as an explicit numerical fixture. They are not measured electric conversions and do not represent the Timber. The catalog is unchanged; an explicit development route identifies the synthetic airframe on screen and suppresses the combustion sound.

```sh
"$(app/get-godot.sh)" --path app -- --electric-demo=4s
"$(app/get-godot.sh)" --path app -- --electric-demo=6s
```

Invalid demo selectors, a different visual aircraft and scripted visual flight are refused. These starts use prescribed 14.8/22.2 V terminal supplies; no SOC or endurance is simulated.

## Flown evidence

Each configuration completes level, banked turn, climb and throttle-chop/recovery scenarios for **30 s / 7,200 ticks**, producing 7,201 v7 rows. Starts are at 150 m for maneuver clearance. Turn/climb/chop use the explicit bounded attitude/sideslip controller in `flight_probe.gd`; it is a test pilot, not installed receiver assistance. The level case is hands-off. Commands and all endpoint electrical channels are checked independently from the CSV.

| Scenario | 4S | 6S |
| --- | --- | --- |
| Hands-off level | Altitude drift below 1e-8 m | Altitude drift below 2e-8 m |
| Climb | +65.87 m | +60.80 m |
| Banked turn | Completes more than 180° heading change; final bank 21.55° | Completes more than 180°; final bank 21.60° |
| Duty zero from 5–15 s, then restored | Zero drive-input current during the chop; powered recovery | Same |

All rows are finite and remain more than 10 m above ground. The strict v7 reader verifies exact aircraft-file SHA, source/configuration identity, tick/time continuity, the ideal conversion `Ibus=d*Im`, and electrical power balance. **32 corrupted-row controls** must be rejected. The 30-second traces are reproducible temporary artifacts; their hashes and reduced observations are retained in [flights.json](flights.json).

```sh
python3 research/propulsion/el1/verify_flights.py --godot "$(app/get-godot.sh)" --directory /tmp/el-flights
python3 research/propulsion/el1/product_check.py
```

[Product evidence](product.md) covers high-throttle arming, fresh-low arming, unplug pause/freeze, reconnect, keyboard return, reset, audio suppression, identical complete-state hashes at 30/60/144 rendering FPS and both datasets inside a Linux release export run from empty working directories. [EL1d](../EL1d/README.md) records the full regression pass and the missed 500 µs/tick performance target. Native Windows/macOS pilot acceptance is not established by the Linux proof.
