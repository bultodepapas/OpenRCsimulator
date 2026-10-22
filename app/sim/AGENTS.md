# Simulation kernel and sessions

- Tools and validation: [docs/tools/physics.md](../../docs/tools/physics.md); bugs: [debugging-physics](../../docs/tools/debugging-physics.md).
- The kernel reads layout and evaluators only from the installed `VehicleModel`; no vehicle-specific branches ([STACK](../../docs/STACK.md#boundaries-and-data-flow)).
- Validate session-loop changes with the flight-test battery and `test_golden.gd`.
