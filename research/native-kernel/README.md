# NK-3 native stage-evaluator components (research)

Step NK-3 of the [native-kernel scoping](../../docs/research/native-kernel-scoping-2026-10-27.md#phases-r-research-i-implementation),
milestone 1: GDExtension (godot-cpp) ports of the fixed-wing stage components the electric Ugly Stik
(`jensen-das-ugly-stik-60`) uses, proven byte-identical to the GDScript reference. Nothing here is installed into
`app/`; build outputs stay in the ignored `tmp/native-kernel/`. Evidence and timings:
[docs/research/native-kernel/NK-3](../../docs/research/native-kernel/NK-3/README.md).

## What is ported

| Native (src/) | Mirrors (current app/ GDScript) |
| --- | --- |
| `nk_math.hpp` | `math3d.gd` shim plus engine `absf`/`maxf`/`minf`/`clampf`/`lerpf`/`wrapf` semantics |
| `nk_terrain.hpp` | `ground_terrain.gd` `sample_validated` (micro-relief, surface-table validity) and `_compose_lake`; `lake_surface.gd` covered-terrain sampler (bank AABB early-out, five-point stencil, bed profile) |
| `nk_wheels.hpp` | `ground_wheels.gd` `evaluate` (diagnostics off, as `FlightSession._ground_evaluation` calls it), `frame`, `coefficients`, `compressions` |
| `nk_aero.hpp` | `air_data.gd` `compute`; `ground_effect.gd` `factors`; `aero.gd` `loads` with `_global_loads`, `_local_loads`, `_wing_flow`, `local_flow_weight`, `_wing_lift_coefficient_with`, tail and section laws |
| `nk_kernel.cpp` | `OpenRCNativeKernel` (RefCounted): `prepare_ground`, `prepare_aero`, per-call methods, probes, benches |

Aero supports `Aero.LOADS_LAW` `section-plane-source-weighted-wake-velocity-v2` with an envelope, coupled or
uncoupled strips, ground effect, the downwash lag, twist, `wing_cm_ac`, body terms and E0a2 or legacy tails.
Wheels support `Wheels.ROLLING_LAW` `wheel-positive-terrain-excess-v2`, anchors, brakes, steering and the lake.

## Contract

- `prepare_ground(gear, surfaces, lake, lake_valid)` and `prepare_aero(model)` decode the validated dictionaries
  once. Per-call methods take `PackedFloat64Array` state (13 values), never the dictionaries.
- D6: decoding refuses unknown keys in every dictionary the laws read (`reference`, `aero`, `envelope`,
  `surfaces`, tails, `ground_effect`, gear and contacts) and unported laws (flaps, tailless elevons, tabulated wing
  polar, empty envelope). A refusal returns `{ok: false, error}`; the caller keeps the GDScript reference.
  `backend_identity()` reports the two law identities; the oracle compares them with the loaded scripts.
- Lake validity comes from the caller (`LakeSurface.is_valid_definition`); an invalid table or lake reproduces the
  reference's `[NAN]` failure shapes.

## Exactness rules (keep them when extending the port)

1. Copy the current GDScript operation by operation, including `+ 0.0` sign scrubs, grouping and branch order.
2. Every simulation value is `nk::R`: its `+ - * /` are single SSE2 instructions with the left operand first
   (inline asm). x86 returns the first operand's NaN when both are NaN; the pinned engine's GDScript evaluator is
   left-first on every path, while GCC commutes `+` and `*`. Plain `double` matched every finite result but not
   NaN signs on malformed inputs (milestone evidence).
3. Engine C++ helpers are not the GDScript evaluator: `lerpf` must compute `weight * (to - from) + from`
   (the pinned binary's NaN priority, found by the math probe).
4. `pow_` hides its exponent from constant folding (asm barrier); `build.py` refuses a library without a `pow`
   import. Transcendentals call the same glibc symbols the engine uses (NK-1).
5. Float literals must parse identically in GDScript; the oracle compiles the spellings in `literal_table()`.
   Add new literals there. GDScript's `-0.0` literal is +0.0; build -0.0 from bits in tests.

## Build, verify, negative control

```bash
python3 research/native-kernel/build.py --jobs 4           # tmp/native-kernel/lib + .gdextension + receipt
python3 research/native-kernel/run.py                      # oracle against app/ at run time; must pass
python3 research/native-kernel/build.py --jobs 4 --mutant  # -DNK_MUTATION: reassociated/commuted operations
python3 research/native-kernel/run.py --mutant             # must FAIL (the oracle detects every mutation)
python3 research/native-kernel/run.py --render tmp/native-kernel/results-<stamp>.json
```

`run.py` runs `oracle.gd` with `--path app` through `tools/godot/run_checked.py`; the oracle loads the extension
with `GDExtensionManager.load_extension` and the reference scripts from `app/`, so edits there are verified
automatically. Options: `--states` (default 12,000 per component), `--variant-states`, `--timing-rounds`, `--seed`.
Run one Godot process at a time; timings on a shared VM are indicative only.
