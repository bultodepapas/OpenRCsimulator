# E5b nose-over verification tools

2026-10-09 · **Status: synthetic Linux verification; no physical acceptance.** Owning step: [ROADMAP E5b](../../../ROADMAP.md). [Findings and retained evidence](../../../docs/research/ground-contact/E5b/README.md).

From the repository root, with Python 3 and the pinned Godot:

```bash
python3 research/ground-contact/e5b/verify.py --out /tmp/e5b-verification --mutations
```

The output directory must be new. The runner executes the full check, rejects engine errors or incomplete reports, records input/engine hashes and refuses input changes during the run. `--mutations` adds a fresh-clone quick control and four isolated force/surface defects. The working tree is never mutated. Omit that flag for the ordinary app-suite check. No extra dependencies are needed.

To inspect the raw numerical report directly:

```bash
"$(app/get-godot.sh)" --headless --path app \
  --script "$PWD/research/ground-contact/e5b/checks.gd" -- --out=/tmp/e5b.json
```

`--quick` runs only static force checks and short patch crossings; it explicitly reports scope `static-and-patch` and omits the rigid-limit ramps. The full run adds four stiffness/timestep/ramp-rate trials per aircraft. Allow several minutes on slower machines.

All fixtures omit aero, engine and crash-session behavior. Ramps use a synthetic horizontal tow through the CG, elevated contact stiffness and a ramped rolling coefficient in test copies. Patch crossings use ordinary gear, no tow and a synthetic rectangular resistance multiplier. No production aircraft, field or force law is changed.
