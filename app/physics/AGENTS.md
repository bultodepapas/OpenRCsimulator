# Physics kernel

- Tools and validation for physics changes: [docs/tools/physics.md](../../docs/tools/physics.md); bugs: [debugging-physics](../../docs/tools/debugging-physics.md).
- Simulation state stays float64 (no `Vector3`/`Basis`/`Quaternion`/`Transform3D`); `app/test.sh` enforces it.
- An intended physics change fails the golden flights; re-record only with an explanation ([golden flights](../../docs/tools/physics.md#golden-flights)).
