# MONSTER CAR 2 — second ground vehicle

RCV-35 integrates the user's supplied nitro truck as a separate vehicle in the existing RC activity. Select **MONSTER CAR 2** in Home's RC car selector, then open the garage. The original Bisonte MT8 remains selectable. Both use the shared airfield and RC circuit.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app -- --vehicle=monster-car-2
```

Release the controls, then press **Drive / Enter**. Steering, cameras, body visibility, lights, contacts, laboratory experiments, damage, water effects and telemetry use the existing garage controls. The nitro engine starts at idle. Reverse input applies the brakes; this transmission has no reverse gear. Reset refuels and restarts the engine. Its default checkpoint is `user://rcv/monster-car-2-checkpoint.json`, separate from Bisonte's checkpoint.

The garage provides **Stop engine**, **Start engine**, **Refuel nitro tank**, and **Clean vehicle**. Engine service requires a paused, stationary car (body speed at most 0.1 m/s and each wheel at most 0.5 rad/s). Stop the engine before refuelling; starting requires fuel. The HUD shows remaining fuel and the garage also shows grams and instantaneous g/min. Service saves any active recording first and is refused if that export fails. Stop/refuel/start preserve chassis pose and damage, are stored as ordered replay actions, and mark the current run assisted. Reset starts a new unassisted run. Cleaning affects only cosmetic dirt, sheen and particle buffers.

**L** switches the headlights and running markers, **K** switches the roof/front auxiliary LEDs and fog lenses, and **N** switches the green underbody neon. The garage has the same three controls. Headlights and neon start on; auxiliaries start off. Brake lamps brighten independently of these switches, including when the headlights are off. This forward-only transmission has no white reversing lamp. Hiding the body also disables its light beams; restoring it restores the selected lights. Reset releases the brake lamps and retains the light switches. The [RCV-38 lighting evidence](../../../docs/research/rc-monster-truck/RCV-38/README.md) records the bounded rig, native captures and checks.

## Source and reproduction

The immutable delivery is [`monster car 2/`](../../../monster%20car%202/): editable Blender source, exported GLB/FBX, collision proxies, simulation metadata and author scripts. No substitute truck geometry was created. The asset manifest and [asset guide](../../../assets/vehicles/monster-car-2/README.md) identify the source bytes and runtime copies. The delivery is user supplied; local integration does not establish a third-party redistribution license.

`build_vehicle_data.py` generates [`monster_car_2.json`](../../../app/data/vehicles/ground/monster_car_2.json) from the delivered simulation metadata, visible GLB and collision GLB. Edit the generator or source inputs, then regenerate; do not hand-edit runtime physics data.

```powershell
python research/rc-monster-truck/monster-car-2/build_vehicle_data.py
python research/rc-monster-truck/monster-car-2/build_vehicle_data.py --check
```

`visual_bake.py` evaluates the original Blender drivers and writes compact transform samples for Godot. The runtime adapter restores the flattened GLB's suspension, steering, wheel and engine movement. Blender +X forward, +Y left, +Z up maps to Godot -Z forward, +X right, +Y up. The source chassis datum is 0.087 m above the Blender ground plane. The rendered root accounts for all three CG coordinates; the visual adapter never feeds transforms into physics.

## Physics and saved state

The shared float64 body solver retains its 31 states. `nitro_dynamics.gd` appends engine angular speed and fuel mass, giving this vehicle 33 states. It integrates an estimated engine torque curve, inertia, idle control, drag, centrifugal clutch, fixed forward ratio and fuel consumption at the existing 240 Hz session rate. The body uses the existing RK4 solver; the powertrain uses a midpoint update. The optional native body evaluator still receives only the original 31 body values.

Source dimensions, wheel locations, mass inventory, gear teeth, motion ratios and contact proxies drive the generated data. Suspension preload preserves the supplied ride datum with the source spring rates and travel. Nine source-derived chassis, bumper, roof and side probes complement wheel contacts. A stopped engine cannot restart from throttle. Signed clutch torque permits wheel-overrun engine braking while engaged and accounts for gearbox losses. The visible clutch bell follows wheel/transmission phase independently of the engine flywheel.

The dedicated procedural two-stroke sound observes RPM, fuel flow, throttle, clutch load and contacting tire slip. Exhaust follows combustion/load, dust requires moving tire contact on a dry loose surface, and grime covers the complete authored shell and tires. These bounded observers cannot change simulation state; pause freezes particles and silences the engine voice. The sound is a presentation model, not a recording of a particular real engine.

Recordings and checkpoints retain the selected vehicle, full state layout, source/configuration identities and composite solver identity. A Bisonte checkpoint cannot load into this car. The [session verifier](session/README.md) checks exact same-backend replay, including engine speed and fuel.

## Limits

This is an experimental software model, not a physically validated reproduction. Masses are Blender estimates. Engine torque, fuel capacity, clutch, tire and brake values are declared estimates rather than measured hardware data. The driveline uses one fixed forward ratio; there is no automatic shift, mixture/temperature model or moving fuel/slosh mass. Suspension coefficients are averaged for the shared four-corner solver. The visual rig retains the author's steering linkage while the base solver uses its existing front-wheel steering approximation. Rendering clamps movement to the authored animation range and reports physical travel beyond it.

The [dated RCV-35 evidence](../../../docs/research/rc-monster-truck/RCV-35/README.md) records numerical checks, replay, rendered inspection and packaging checks. Those checks do not establish target-hardware performance or measured handling accuracy.

The [RCV-36 follow-up](../../../docs/research/rc-monster-truck/RCV-36/README.md) records engine-service replay, clutch/stall corrections, sound, grime, dust, exhaust and native-rendered inspection. Fuel consumption changes the fuel inventory; body mass and CG remain static because the source tank's included fuel mass is unresolved.

The [RCV-37 performance evidence](../../../docs/research/rc-monster-truck/RCV-37/README.md) measures animation and sound optimizations against retained source snapshots. Rig bindings and interpolation scratch are prepared once per vehicle; sound calculations that are constant within an audio block run once per block. Geometry, particle budgets, sound samples and the 240 Hz physics solver are preserved. The source-only comparison harnesses live in [`rcv37/`](rcv37/).
