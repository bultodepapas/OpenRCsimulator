# Rendering

- Tools and verification: [docs/tools/graphics.md](../../docs/tools/graphics.md); bugs: [debugging-graphics](../../docs/tools/debugging-graphics.md).
- Shaders must not read `TIME`; animate from the `sim_clock` global uniform so captures repeat.
- Rendering converts float64 simulation state at the boundary; never feed render values back into the simulation.
