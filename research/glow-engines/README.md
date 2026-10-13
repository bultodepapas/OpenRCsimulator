# Standalone glow engine foundation

Implemented increment: NITRO-01a, with mean-cycle portions of NITRO-2T-02a / NITRO-4T-02a and a NITRO-02c thermal balance. [Owning plan](../../docs/plans/RC_NITRO_ENGINE_REALISM_PLAN.md) owns remaining steps; [evidence](../../docs/research/glow-engines/NITRO-01/README.md) records verification and limits.

## Interface and supported scope

`app/physics/glow/profile.gd` reads `openrc-glow-engine v1` standalone candidate data, validates the closed family/quantity contract and produces detached float64 parameters. File-backed identity hashes the same bytes parsed. `source.gd` dispatches explicit `glow_2t` / `glow_4t` and retains candidate identity. These profiles are not an active aircraft v2 capability and cannot replace catalog propulsion through the current aircraft loader.

`Source.evaluate(model, rpm, admission, mixture, dry_density_kg_m3, running, firing_fraction)` is pure. Admission is effective charge fraction, **not transmitter throttle**; mixture is fuel equivalence relative to the declared combustible blend. The initial kernels have no servo, charge-transport, plug-temperature or stochastic firing state. Tables are bounded, linear and flattened into `PackedFloat64Array` pairs; unsupported queries return `ok=false`. Callers must reject that result. They must not ignore errors or substitute another engine family.

| Kernel input | Meaning |
| --- | --- |
| Common displacement, mechanical torque, indicated efficiency | Cycle volume; positive moving loss torque; fraction of released chemical energy converted to indicated cycle work. These losses are subtracted once from indicated torque. |
| 2T delivery / trapping / scavenging pressure | Delivered charge per swept volume, retained fraction, and gas-exchange work `pressure * volume * delivery * admission` per revolution. |
| 4T volumetric efficiency / pumping pressure / intake pressure drop / valve torque | Fresh inducted charge per swept volume per 720° cycle; base pumping pressure **excluding throttle depression**; additional throttle-dependent depression; separate valve-train loss torque. |
| Fuel component volume fractions and properties | Normalize volume to mass; oil is explicitly inert in this version. AFR and LHV use the combustible methanol/nitro mass basis, while delivered/unburned flow includes gross premix and lubricant. |
| `running`, `firing_fraction` | Requested fuel/combustion enable and externally supplied fraction of successful opportunities. Opportunity frequency is `RPM/60` (2T) or `RPM/120` (4T); actual mean firing frequency is zero when there is no burned charge. |

Rich 2T four-stroking can use a reduced successful-fire fraction without changing its 360° mechanical cycle. This is a mean input to the kernel, not yet an automatic rich-mixture instability/event law. A true 4T retains a 720° cycle, independent intake/valve/pumping parameters and an independent work map. Neither kernel embeds a manufacturer or family power/efficiency advantage.

At zero RPM, evaluations report zero fuel, work and moving losses. Positive-speed loss torques have a discontinuous rest limit; this is **not** a start/static-friction/compression/stop model. The coupled bench qualifies positive RPM and refuses a step requiring unsupported negative spin. No rest, windmilling-start, stable idle, thermal stall or shutdown-event acceptance follows from these kernels.

`thermal.gd` provides a separate scalar head/case heat proxy. Its caller supplies independently calibrated capacity, combustion partition, airflow conductance and **effective evaporation energy per kilogram of delivered premix** (`premix_evaporation_j_kg`), including nonvolatile oil and the vaporizing fraction. It partitions chemical energy, shaft work, dissipative losses, exhaust, evaporation, ambient exchange and storage. Pumping dissipation is lumped into the head/case proxy; this is an explicit reduced partition, not a measured head temperature. It has no hidden family defaults or temperature failure thresholds.

## Generated candidate profiles

`build_profiles.py` owns all four files in `app/data/glow/`: closed runtime contract, offline schema and O.S. MAX-55AX / FS-64V candidates. Do not hand-edit them.

The candidates constrain **only the stated manufacturer rated power/RPM knot**. Intermediate WOT torque, delivery/trapping or filling, loss and efficiency knots are estimates; their inversion remains `derived` from explicitly estimated dependencies. The fuel blend is borrowed from the documented O.S. engine test campaign. Profile status is `candidate`; no measured full-curve, throttle, idle, temperature or acoustic calibration is claimed. Reference density and nominal mixture are modeling assumptions, not manufacturer test conditions.

```sh
python3 research/glow-engines/build_profiles.py --check
python3 research/glow-engines/test_profiles.py
python3 research/glow-engines/reference/test_reference.py
python3 research/glow-engines/reference/reference.py --check
```

Regenerate deliberately with `python3 research/glow-engines/build_profiles.py`; use `--check` before and after changing the source. The oracle generator is independent Python scalar mathematics and produces original synthetic vectors; it is not a calibration dataset.

## Coupled bench

Run the pinned Godot from [TOOLS](../../docs/TOOLS.md). On Windows, use `.tools/Godot_v4.7.2-stable_win64_console.exe` from an existing repository installation; the Bash downloader is for Linux/WSL.

```sh
GODOT="$(app/get-godot.sh)"
"$GODOT" --headless --path app --audio-driver Dummy --script "$PWD/research/glow-engines/bench.gd" -- \
  --profile=res://data/glow/os_max_55ax_candidate.json --prop-diameter-m=0.3302 --out=/absolute/fresh/2t.json
"$GODOT" --headless --path app --audio-driver Dummy --script "$PWD/research/glow-engines/bench.gd" -- \
  --profile=res://data/glow/os_fs_64v_candidate.json --prop-diameter-m=0.3556 --out=/absolute/fresh/4t.json
```

Omit `--profile` and select `--engine=2t` / `4t` for original synthetic fixtures. `--hz`, `--ticks`, `--sample_every` and `--carrier-mass-kg` select numerical experiments. An explicit `--engine` must match a supplied profile. Unknown, malformed or nonfinite options fail. Create output parent directories yourself and use fresh filenames.

The bench advances a free rigid carrier and relative shaft RPM through the existing `Simulation` coupled RK4 and `RotorCoupling`. Stage RPM drives engine work, propeller J/load, momentum and reaction exactly once; it records engine work, propeller drag/thrust work, external impulse and gross/burned fuel. Propeller Ct/Cp, rotor inertia and carrier tensor/mass are **synthetic estimates**, not the indicated engine's installation. Supply is offboard/prescribed: the carrier has constant mass; cumulative fuel is accounting, not an onboard finite-tank/endurance simulation. The thermal kernel is tested independently and is not yet a bench continuous state.

The reported wall time includes diagnostic queries/recording; it is not the full-flight 500 µs gate. The short admission schedule has sharp knots and demonstrates numerical refinement, not global smooth fourth-order convergence or measured throttle response.

```sh
python3 research/glow-engines/mutations.py --godot "$GODOT" --out /absolute/fresh/mutations
```

This makes disposable minimal projects. The unchanged control must pass; cycle-angle, opportunity-frequency, premix-oil and valve-loss defects must fail the independent oracle. Never mutate production scripts to exercise faults.
