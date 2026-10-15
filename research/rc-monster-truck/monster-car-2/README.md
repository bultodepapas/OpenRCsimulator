# MONSTER CAR 2 — second ground vehicle

RCV-35 integrates the user's supplied nitro truck as a separate vehicle in the existing RC activity. Select **MONSTER CAR 2** in Home's RC car selector, then open the garage. The original Bisonte MT8 remains selectable. Both use the shared airfield and RC circuit.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app -- --vehicle=monster-car-2
```

Release the controls, then press **Drive / Enter**. Steering, cameras, body visibility, lights, contacts, laboratory experiments, damage, water effects and telemetry use the existing garage controls. The nitro engine starts at idle. Reverse input applies the brakes; this transmission has no reverse gear. Reset refuels and restarts the engine. Its default checkpoint is `user://rcv/monster-car-2-checkpoint.json`, separate from Bisonte's checkpoint.

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

Source dimensions, wheel locations, mass inventory, gear teeth, motion ratios and contact proxies drive the generated data. Suspension preload preserves the supplied ride datum with the source spring rates and travel. Nine source-derived chassis, bumper, roof and side probes complement wheel contacts. Engine RPM drives the reused procedural sound and bounded exhaust effect; those observers cannot change the simulation.

Recordings and checkpoints retain the selected vehicle, full state layout, source/configuration identities and composite solver identity. A Bisonte checkpoint cannot load into this car. The [session verifier](session/README.md) checks exact same-backend replay, including engine speed and fuel.

## Limits

This is an experimental software model, not a physically validated reproduction. Masses are Blender estimates. Engine torque, fuel capacity, clutch, tire and brake values are declared estimates rather than measured hardware data. The driveline uses one fixed forward ratio; there is no automatic shift, mixture/temperature model or moving fuel/slosh mass. Suspension coefficients are averaged for the shared four-corner solver. The visual rig retains the author's steering linkage while the base solver uses its existing front-wheel steering approximation. Rendering clamps movement to the authored animation range and reports physical travel beyond it.

The [dated RCV-35 evidence](../../../docs/research/rc-monster-truck/RCV-35/README.md) records numerical checks, replay, rendered inspection and packaging checks. Those checks do not establish target-hardware performance or measured handling accuracy.
