# EDF research calculations

This directory owns reproducible planning arithmetic for
[EDF-00](../../docs/research/edf-propulsion/README.md). The
[implementation plan](../../docs/plans/edf-propulsion.md) owns future work;
[physics and sources](../../docs/research/edf-propulsion/physics-and-sources.md)
owns inputs, equations and limitations.

From the repository root, using Python 3 and only its standard library:

```bash
python research/edf-propulsion/calculations.py --check
```

Regenerate the report after deliberately changing its sourced inputs:

```bash
python research/edf-propulsion/calculations.py > docs/research/edf-propulsion/calculations.json
```

The script computes nominal energy/current/duration examples, outlet/FSA
relationships, a casing-based tangential Mach proxy, incomplete mass subtotals
and two analytic source-audit counterexamples. The committed JSON includes source
conflicts and scope limits. `--check` verifies reproducibility with a `1e-12`
numeric comparison; it does not certify measured accuracy, runtime admission,
flight performance or hardware compatibility. No Godot process is started.
