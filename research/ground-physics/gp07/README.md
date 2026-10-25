# GP-07 tools — airframe ground contacts

Evidence and findings: [docs/research/ground-physics/GP-07](../../../docs/research/ground-physics/GP-07/README.md).

| Tool | Use |
| --- | --- |
| `hull_coverage_dump.gd` | Builds an airplane's visual model as flown and dumps each visible mesh part's convex hull, its crash hull and gear contacts in body FRD about the CG. `godot --headless --path app --script "$PWD/research/ground-physics/gp07/hull_coverage_dump.gd" -- --aircraft=<catalog id> --out=$PWD/tmp/gp07/<id>.json` |
| `hull_coverage.py` | Sweeps ground directions over a dump: how deep the drawing sinks before physics touches (and where physics floats). `--candidate` tries another hull; `--greedy <m>` lists the drawn points a cover would add. Works for any catalog airplane. |
| `derive_stik_hull.py` | GP-07b generator of the Ugly Stik crash hull from the drawn model (named features, pruning, coverage gate). `--check` after any Stik model edit; `--write` updates the base and the four synthetic Stiks, then run `research/glow-engines/build_installations.py`, `research/crash-economics/build_runtime.py`, `build_catalog.py`, `research/aircraft-editor/build_descriptors.py` and the d8b-r2 candidate scripts (`--check` lists them stale). |
| `restitution_probe.py` | Restitution of one soft hull contact as integrated (RK4, 240 Hz, clamp and onset ramp). |
| `mutate.py` | Mutation check of `app/tests/test_airframe_contacts.gd` and the runway-strip presentation tests; needs about 2.5 GB in the scratch directory. Last result: `mutations.log`. |
| `mutation-old-hull.json` | The 2026-10 plan-estimate Stik hull, used by one mutation. |
