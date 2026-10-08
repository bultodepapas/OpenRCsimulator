# E4b — Long-circuit math sensitivity

2026-10-08 · **Status: offline experimental measurement tool.** Results and acceptance limits: [E4b evidence](../../../docs/research/ground-contact/E4b/README.md). No runtime or aircraft-data changes.

```sh
python3 research/landing/e4b/measure.py --out /tmp/e4b-proof
```

Use a new output directory. Requires Python's standard library and the pinned Godot from `app/get-godot.sh`. `--source /path/to/isolated/repository` selects the app snapshot; `--godot /path/to/binary` selects the executable. The E4a fixture and E4b scripts always come from this tool's repository. The runner freezes app/research sources with SHA-256 checks before creating disposable variants, isolates user settings, and never edits the source app. A local clone excludes other developers' unfinished app edits. Baseline physics must still match the saved E4a tape; this command never rerecords it.

Five fresh sessions replay the same 28,861 recorded controls:

1. Original dynamics with empty instrumentation declarations.
2. H7's selected aerodynamic, ground-contact and propulsion branch instrumentation.
3. Joint `sin_` and `atan2_` output perturbation toward positive infinity by one adjacent float.
4. The same joint perturbation toward negative infinity.
5. H7's deliberate aerodynamic `blend == 0` → `blend < 0` branch control.

Perturbations start **after** restoring the authentic initial checkpoint. All saved controls, derived model values, fingerprints and code-owned H9 tolerances remain unchanged. Python independently verifies wrapper bit patterns against `math.nextafter` for positive, negative and zero outputs. This measures joint sensitivity; it does not attribute effects to one function.

The probe compares current/previous body state and numerical auxiliaries at E4a's 483 boundaries, retaining peak absolute errors, fractions of H9 budgets and first exceeded ticks. It checks finite samples and discrete states separately, retains every tick's engine/anchor modes and selected branch sequences, and runs real session crash guards. It continues past numerical tolerance exceedances so the report shows the whole flight; a crash/fault/incomplete run is a failed experiment. `ok: true` means the measurement completed with valid controls, **not** that all candidate errors were within H9 limits.

Every-tick trajectory hashes include state, previous state, auxiliary state, modes, inputs, loads, tick and timestep. Raw/instrumented hashes must match exactly and both must reproduce every saved checkpoint. The deliberate branch change must be detected. Eleven comparator controls check a known 1 m error, first exceeded tick, exact sample count, fractional anchor flag, NaN previous state and infinite loads.

`verification.json` summarizes results. Each `CASE.json.gz` retains exact branch sequences in `branch_table` and their per-tick `branch_indices`; index zero is physics tick 1. `modes` uses the same timeline. Interning only removes duplicate sequences. `source-identity.json` identifies the app, experiment, native fixture and engine. Logs are rejected on engine errors or unexpected exits.

This remains an offline measurement, outside `app/test.sh`. It covers one calm, eastbound, wash-off Stik circuit on the executing platform. H7 instrumentation observes selected branches, not every conditional. Actual OS/CPU runs, other math wrappers, larger perturbations, calibrated wash and physical/pilot acceptance remain separate.
