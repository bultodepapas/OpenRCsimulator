# Physics kernel

- Tools and validation for physics changes: [docs/tools/physics.md](../../docs/tools/physics.md); bugs: [debugging-physics](../../docs/tools/debugging-physics.md).
- Simulation state stays float64: no 32-bit Godot math types in `sim/` or `physics/`. `app/test.sh` greps every file here, Markdown included, for their names.
- An intended physics change fails the golden flights; re-record only with an explanation ([golden flights](../../docs/tools/physics.md#golden-flights)).
