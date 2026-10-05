# Roadmap

Started **2026-10-05**. This is the route we plan to follow, built from the findings in [RESEARCH.md](RESEARCH.md). It is a direction, not a contract. Every stage ends with something we can see or run. Every technical choice is provisional and names the evidence that would change it. Choices are recorded in [DECISIONS.md](DECISIONS.md).

**Be water:** take the shortest path to a visible, flyable little airplane. Learn from it, then adjust. If a stage teaches us that the route is wrong, we change the route and record why.

## Where we are

- **Established:** an RC airplane simulator that grows from small to large ([AGENTS.md](AGENTS.md)).
- **Chosen:** the first aircraft is an Ultra Stick / Ugly Stick-style .60 nitro.
- **Researched, not yet executed:** simulators, flight physics levels, propulsion, input pipelines, platforms, and validation methods. One small numerical experiment has run ([propeller comparison](research/compare_static_propeller.py)).
- **Missing:** any running code. The research notebook keeps reaching the same conclusion: *more reading will not answer edit/run friction, controller compatibility, readability from the ground, or what feels right. We need a prototype.*

## Starting stack (provisional)

The full survey of options, versions and evidence is in [STACK.md](STACK.md). In short:

| Area | Starting choice | We change it if… |
| --- | --- | --- |
| Platform | Desktop browser | The Gamepad API cannot deliver transmitter channels, or latency is poor |
| Rendering | three.js r186, `WebGLRenderer`, isolated in `src/render/` | Upgrade churn hurts → Babylon.js. Scene authoring is the bottleneck → Godot 4.7 comparison |
| Language / build | TypeScript 7, Vite 8, Node 24 LTS, npm, Biome | — |
| Flight physics | Our own float64 module, never imports three | Rebuilding mature features costs too much → JSBSim |
| Tests | Vitest 5 (headless physics), Playwright (screenshots) | — |

The physics module must not import three.js. That boundary keeps the core portable if we move to another renderer or a native build later.

## The route

Each stage is small. "Done when" is the observable proof. Stages can be reordered if what we learn says so.

### Stage 0 — Hello, little airplane

A web page showing a blockout Stick (boxes for fuselage, wing, tail, wheels) over a flat green field with a horizon. A fixed camera at pilot eye height (~1.7 m) looks at the airplane. The airplane follows a scripted circle, with no physics yet.

- Dimensions from the Hangar 9 Ultra Stick .60 manual: 66 in span, 55 in length.
- **Done when:** `npm run dev` shows the airplane moving, and a screenshot proves it.

### Stage 1 — It answers the sticks

Keyboard controls aileron, elevator, rudder, and throttle. The control surfaces visibly deflect. An on-screen panel shows the raw input and the mapped command. A key resets the airplane.

- **Done when:** each key moves the correct surface in the correct direction, checked against a screenshot of neutral and deflected states.
- **Checkpoint:** was Three.js + TypeScript pleasant to change? If not, run the Godot comparison before going further.

### Stage 2 — First flight

A rigid body with 6 degrees of freedom and fixed-step physics. Rendering interpolates between physics states (from *Fix Your Timestep*). Forces come from a linear stability-derivative model (lift, drag, side force, roll/pitch/yaw moments, control derivatives), plus simple thrust = throttle × max thrust with a lag. The model includes a crude stall: lift is capped above the stall angle. The airplane starts in the air near level flight.

- Aircraft data lives in a JSON file. Every value carries its unit, source, and evidence kind (`manual`, `borrowed`, `estimated`, `measured`).
- **Done when:** you can take off from the air start, turn, climb, glide, and crash. Headless tests pass for:
  - Energy: a power-off glide loses energy and never gains it.
  - Force balance: a level-flight state produces small residual accelerations.
  - Signs: up elevator raises the nose, right aileron rolls right, right rudder yaws right.
  - Convergence: results at step `h`, `h/2`, and `h/4` converge.

### Stage 3 — Ground: takeoff and landing

The taildragger gear is modeled as spring-damper contact points, with rolling friction on grass (a labeled guess) and tailwheel steering. The airplane starts on the ground. Crashes are detected and followed by a reset.

- **Done when:** a takeoff run, a landing, and a nose-over all happen in a way that looks believable. A drop test shows no energy gain and no strong dependence on timestep.

### Stage 4 — A real transmitter

Browser Gamepad API with a raw channel inspector that shows every axis and button. Calibration covers center, endpoints, inversion, and channel assignment. No deadzone, expo, or circular limit is applied by default, because the radio already does that. When the device disconnects or focus is lost, the sim pauses visibly, and resuming requires an explicit action.

- **Done when:** one real EdgeTX/OpenTX radio (or whatever hardware we have) flies the airplane. The device, firmware, OS, and browser are recorded in a compatibility table.

### Stage 5 — It sounds and pulls like a nitro

The engine model has running/stopped states, a throttle → target rpm curve with a response lag, and an APC 12×6 Sport coefficient table that gives thrust and torque from rpm and airspeed. The reference engine is the O.S. MAX-65AX. Engine sound follows rpm through Web Audio. Fuel mass and CG shift are optional.

- **Done when:** throttle changes are audible, static and flying thrust come from the prop table, and every assumed engine number is labeled.

### Stage 6 — Better air and evidence

Any of these can be done, in whatever order playtesting asks for:

- constant wind, then gusts
- stall with hysteresis and a post-stall extension
- propwash on the tail
- ground effect
- flight trace export (CSV) and replay
- a chase camera and adaptive zoom for distant-aircraft visibility

### Later horizon (not scheduled)

- Pilot observation sessions using the protocol in RESEARCH.md.
- An aircraft package format and a second aircraft.
- Offline/PWA use.
- Native packaging.
- Buddy-box and shared control.
- Floatplanes and launches.
- An ArduPilot SITL link.
- Parameter identification from flight logs.

## Research tracks that run alongside

These feed the stages without blocking them:

1. **Aircraft manifest (feeds Stage 2):** build the JSON parameter file for the Hangar 9 Ultra Stick .60 conventional wing. Estimate inertia from a component inventory. Seed the nondimensional derivatives from the UltraStick25e specimen and label them `borrowed`.
2. **Propeller data (feeds Stage 5):** plot the APC 12×6 predicted load vs rpm at several airspeeds, extending the existing 11×6 comparison script.
3. **Hardware (feeds Stage 4):** find out which transmitters/gamepads we can actually test with.
4. **People (after Stage 3):** run 2–3 informal sessions with real RC pilots and watch where they get lost.
5. **License:** choose the project license before the first public release. Check that it is compatible with the UIUC "GPL'd data" terms if we bundle airfoil data.

## How we work

- **Small steps, visible proof:** every change should show a result (a screenshot, a test, or a trace). "Make it realistic" is not a task. "Up elevator raises the nose at 15 m/s" is.
- **Label honesty:** a guessed number is marked as guessed. Simulator behavior is never called "validated" without a comparison to real data.
- **Revisit points:** at the end of each stage, take five minutes to check whether the stack, the order, or the aircraft data needs to change. Record any change in DECISIONS.md and mark the old entry *superseded*.
