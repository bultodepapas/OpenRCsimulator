# G2a / G2b observational cost

2026-10-09 · **Status: measured software cost; performance acceptance remains open.**

Godot 4.7.2-stable (official), Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz, 12 logical CPUs, headless Linux. The complete gate, refinement sweep and isolated mutation runs had finished; no other Godot process was active. All cases ran serially.

Each of seven samples resets the same P-51 scenario, advances 240 untimed warm-up steps, then times 240 `Simulation.step()` calls. Trim/renderer/audio costs are outside the interval. The reported median is a median of batch means, not an individual-tick tail bound. Trim holds its solved commands; punch holds throttle at 0.8. Each candidate is a different physical integration/reaction model; this is not a causal single-operation comparison.

| Air | Fixture | Split (µs/step) | Coupled RK4 (µs/step) |
| --- | --- | ---: | ---: |
| calm | trim | 508.9 | 1262.8 |
| calm | punch | 517.3 | 1324.8 |
| hot-high | trim | 524.7 | 1269.0 |
| hot-high | punch | 487.7 | 1283.6 |

The largest coupled median is 1324.8 µs, about 31.8% of a 240 Hz interval. The 500 µs target remains unmet; split also exceeds it in three of these four cases. This supports keeping the new route experimental. A shared stage evaluation could remove its current repeated aerodynamic evaluation; that optimization must preserve torque closure, convergence, replay and failure semantics. Shared-host load and sequential ordering remain measurement limits.

**Reproduce:**

```sh
"$(app/get-godot.sh)" --headless --path app \
  --script "$PWD/docs/research/propulsion/G2a-RK4/cost.gd" -- \
  --out="$PWD/docs/research/propulsion/G2a-RK4/cost.json"
```

[Raw samples](cost.json) identify the [benchmark source](cost.gd) and [application/test manifest](source-manifest.json). These measurements do not validate physical coefficients or rendered-frame performance.
