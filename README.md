# OpenRCsimulator

An open-source RC airplane simulator, developed heavily with AI. The project is in a fluid, open research phase: we are still discovering what it should become.

Two principles guide the project:

1. We are building an RC airplane simulator.
2. We will grow from small to large, starting with something very simple that works and shows a little airplane, then expanding gradually.

Our first aircraft will be an **Ultra Stick / Ugly Stick-style .60 nitro airplane**. The exact airframe variant, dimensions, engine, and flight-model parameters remain under research. We will start with a simple representation and refine it gradually.

The simulator is built with **Godot 4.7** (GDScript) in [`app/`](app/), chosen after building the same small scene in three.js and Godot ([bake-off](prototypes/stage0/COMPARISON.md)). Physics stays in 64-bit floats, enforced by the test script. Platforms, physics depth, controls, compatibility and later aircraft remain open to research.

We will research options, try small experiments, and adapt as we learn. Keep choices easy to revisit and technologies easy to adopt or change. Open questions are invitations to explore.

[ROADMAP.md](ROADMAP.md) lays out the route in small stages, from a scripted little airplane to a nitro Stick flown with a real transmitter.

[STACK.md](STACK.md) surveys the development stack options (engines, renderers, toolchain, libraries) and explains the starting choice.

[DECISIONS.md](DECISIONS.md) records our current direction and the reasoning behind it as research progresses.

[LEARNINGS.md](LEARNINGS.md) records practical lessons from building and running things.

[RESEARCH.md](RESEARCH.md) collects exploratory findings, original sources, and open questions across simulators, physics, controls, and development approaches.

Licensed under the [MIT License](LICENSE). Third-party data, if bundled, keeps its own license.
