# NK-3 native stage evaluator (research)

Step NK-3 of the [native-kernel scoping](../../docs/research/native-kernel-scoping-2026-10-27.md#phases-r-research-i-implementation):
a GDExtension (godot-cpp) port of the joint RK stage of the electric Ugly Stik (`jensen-das-ugly-stik-60`),
`FlightSession._wheel_evaluate`, proven byte-identical to the GDScript reference per component and through the real
kernel tick. Nothing here is installed into `app/`; build outputs stay in the ignored `tmp/native-kernel/`.
Evidence and timings: [docs/research/native-kernel/NK-3](../../docs/research/native-kernel/NK-3/README.md).

## What is ported

| Native (src/) | Mirrors (current app/ GDScript) |
| --- | --- |
| `nk_math.hpp` | `math3d.gd` shim plus engine `absf`/`maxf`/`minf`/`clampf`/`lerpf`/`wrapf` semantics |
| `nk_terrain.hpp` | `ground_terrain.gd` `sample_validated` (micro-relief, surface-table validity) and `_compose_lake`; `lake_surface.gd` terrain sampler (covered early-out, five-point stencil, bed profile) |
| `nk_wheels.hpp` | `ground_wheels.gd` `evaluate` (diagnostics off), `frame`, `coefficients`, `compressions` |
| `nk_aero.hpp` | `air_data.gd` `compute`; `ground_effect.gd` `factors`; `aero.gd` `loads` and its strip, oracle and tail laws |
| `nk_prop.hpp` | `propulsion.gd` legacy propeller: datum stage inflow, `coefficient`, `thrust_torque`, untilted `loads_from_thrust_torque`; `dynamics.gd` `rotor_momentum` |
| `nk_hull.hpp` | `hull_contact.gd` `loads` (flat and lake branches, airframe friction, shared regularization) |
| `nk_stage.hpp` | `flight_session.gd` `_wheel_evaluate`, `_ground_evaluation` (fixed gear), `_ground_up`, calm `air_data`; `dynamics.gd` `loads_from_air` without slipstream |
| `nk_kernel.cpp` | `OpenRCNativeKernel` (RefCounted): prepare, per-call and per-tick methods, probes, counters, benches |

Laws: `Aero.LOADS_LAW` `section-plane-source-weighted-wake-velocity-v2` (envelope, coupled or uncoupled strips,
ground effect, downwash lag, twist, `wing_cm_ac`, body terms, E0a2 or legacy tails); `Wheels.ROLLING_LAW`
`wheel-positive-terrain-excess-v2`; soft hull `soft-hull-spring-friction-v2` with the lake normal law.

## Contract

- `prepare_stage(config)` decodes everything once: the validated model, landing gear, surface table, lake and its
  validity, the session's prepared hull (`_hull_contact`), the layout indices, density and ground-effect reach.
  `stage_adapter.gd` `config_for(session)` builds it. `prepare_ground` and `prepare_aero` remain for components.
- `set_tick_context(aux, inputs, deflections, time_now)` once per tick: the aux the kernel installs after
  `pre_tick`, the inputs, the session's own `_deflections(aux)` (`[elevator, aileron_right, aileron_left, rudder]`)
  and `sim.time()`. `stage(body, continuous, t)` is then the joint stage: `{loads, derivative, rotor_momentum}` with
  `StringName` keys like the reference literal, or `{}` exactly where the reference returns `{}`.
- `stage_adapter.gd` `install(session, native)` swaps exactly one boundary (`sim.model.stage`, SF-08) and wraps
  `sim.model.pre_tick` to hand over the tick context; the tick transaction, pre-step, collision and observers stay
  GDScript. A refusal changes nothing on the session.
- D6: decoding refuses unknown keys in every dictionary the laws read and unported capabilities: retractable gear,
  glow, coupled shaft, turbine, liquid or finite fuel, flaps, slipstream or wash pieces, rotor dynamics or another
  stage method, tilted or non-legacy propellers, live-mass (geometry-only) hulls, and any weather that is not calm,
  uniform and settled (spatial, turbulence, vertical column, pending reset). The caller keeps the reference.

## Exactness rules (keep them when extending the port)

1. Copy the current GDScript operation by operation, including `+ 0.0` sign scrubs, grouping and branch order.
2. Every simulation value is `nk::R`: its `+ - * /` are single SSE2 instructions with the left operand first
   (inline asm). x86 returns the first operand's NaN when both are NaN; the pinned engine's GDScript evaluator is
   left-first on every path, while GCC commutes `+` and `*`. Plain `double` matched every finite result but not
   NaN signs on malformed inputs.
3. Engine C++ helpers are not the GDScript evaluator: `lerpf` computes `weight * (to - from) + from` (the pinned
   binary's NaN priority, found by the math probe).
4. `pow_` hides its exponent from constant folding (asm barrier); `build.py` refuses a library without a `pow`
   import. Transcendentals call the same glibc symbols the engine uses (NK-1).
5. Float literals must parse identically in GDScript; the oracle compiles the spellings in `literal_table()`.
   Add new literals there. GDScript's `-0.0` literal is +0.0; build -0.0 from bits in tests.
6. Dictionaries returned to the kernel use the reference's key types and order (`{loads = ...}` is `StringName`).

## Build, verify, negative control

```bash
python3 research/native-kernel/build.py --jobs 4                       # library, descriptor, receipt
python3 research/native-kernel/run.py                                  # milestone-1 component oracle
python3 research/native-kernel/run.py --script stage_oracle.gd         # stage, prop, hull, ground, D6 refusals
python3 research/native-kernel/run.py --script trajectory.gd --option ticks=14400   # + timing pairs, attribution
python3 research/native-kernel/build.py --jobs 4 --mutant              # -DNK_MUTATION negative control
python3 research/native-kernel/run.py --mutant [--script stage_oracle.gd]           # must FAIL
python3 research/native-kernel/run.py --render tmp/native-kernel/<results>.json
```

All three harnesses run with `--path app` through `tools/godot/run_checked.py`, load the extension with
`GDExtensionManager.load_extension` and the reference scripts from `app/`, so edits there are verified
automatically; `stage_oracle.gd` and `trajectory.gd` extend `oracle.gd`. Trajectory options (`--option`):
`ticks`, `pairs`, `warmup`, `samples`, `repeats`, `timing-cases`, `only=all|timing|attribution`, `skip-timing=true`.
Run one Godot process at a time under `nice`; timings on a shared VM are indicative only.

## Windows design note (not built)

MSVC x64 has no inline assembly, so rule 2 needs another left-first mechanism there; none is verified yet:

1. **Preferred:** build the Windows library with MinGW-w64 GCC, like the official Godot Windows binaries. The same
   `nk::R` asm applies, and the extension links the same CRT math as the engine, which may restore NK-1's
   same-library identity. Verify with these oracles on a Windows host.
2. MSVC with a tiny MASM object exporting `nk_add/sub/mul/div(xmm0, xmm1)`: guaranteed operand order, at a call per
   operation (roughly 1–2 µs more per stage). Intrinsics such as `_mm_add_sd` do not guarantee operand order.
3. If neither proves identical, D3's tolerance tier applies on Windows: NaN-sign differences occur only on outputs
   the kernel rejects anyway, so NaN-class equality plus bit identity of finite outputs would be the criterion.
