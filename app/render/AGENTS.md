# Rendering

- Tools and verification: [docs/tools/graphics.md](../../docs/tools/graphics.md); bugs: [debugging-graphics](../../docs/tools/debugging-graphics.md).
- Shaders must not read `TIME`; animate from the accepted simulation clock so captures repeat. World effects use the `sim_clock` global uniform. Aircraft RGB materials use a per-instance phase derived from that same clock (or the Workshop's isolated 240 Hz preview clock), so preview scrubbing cannot move a live flight's lights.
- Rendering converts float64 simulation state at the boundary; never feed render values back into the simulation.
