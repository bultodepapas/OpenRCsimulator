# EL1d scalar momentum and stop qualification

**Status:** complete for the synthetic principal-axis fixture; no aircraft or hardware validation. **Step prefix:** EL.

`scalar_probe.gd` advances the pinned Godot motor, rotor-coupling, RK4 and stop code. `verify_scalar.py` builds expected values from an independent scalar equation and SciPy DOP853; it does not call production coupling code for the oracle. The fixtures are synthetic: 800 rpm/V, 0.06 Ω, 1 A no-load current, 6 V, 0.85 duty, 0.004 kg·m² locked inertia and 0.0001 kg·m² relative rotor inertia. They describe no Timber hardware.

For a single principal axis with no external moment, the reference uses `H = Jlocked*w + Jrotor*Ω`, `Q = kt*((duty*V - kt*Ω)/R - I0)`, and `Ω_dot = Jlocked*Q/(Jrotor*Jcarrier)`. Its smooth solution is exponential. It also integrates the independent electrical port powers and verifies that their energy balance closes. For the coast event it uses constant `Q = -kt*I0`, giving `t_stop = Ω0*Jrotor*Jcarrier/(kt*I0*Jlocked)`; event projection is checked against scalar angular momentum conservation.

Run with the pinned Godot and EL1a-R2 Python environment:

```sh
GODOT_PATH="$(app/get-godot.sh)"
python3 research/propulsion/el1/verify_scalar.py \
  --godot "$GODOT_PATH" \
  --app app \
  --output research/propulsion/el1/scalar_evidence.json
```

At 120/240/480/960 Hz, smooth endpoint angular-speed error was 1.44e-3, 8.25e-5, 4.94e-6 and 3.02e-7 rad/s, with observed orders 4.12, 4.06 and 4.03. Momentum drift stayed below 1e-13 kg·m²/s; electrical port energy residual stayed below 2e-12 J. The coarsest kinetic-energy versus source-work residual was 3.17e-4 J and decreased with refinement. The analytical coast stop was 0.367566340470006 s; the largest event-time error across the four rates was 4.65e-13 s and the cross-rate spread was below 2e-15 s.

The oracle covers a single principal axis, no propeller and no external moment. It does not qualify general tilted-axis gyro coupling, an aircraft flight, real motor parameters, or measured performance. The separate stop unit test checks momentum projection on a tilted shaft axis.
