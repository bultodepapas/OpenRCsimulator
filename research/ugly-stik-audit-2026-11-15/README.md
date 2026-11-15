# Ugly Stik audit reproductions — 2026-11-15

The [dated dossier](../../docs/research/ugly-stik-flight-physics-2026-11-15/README.md) owns findings, citations, limits and original receipts. These small tools inspect existing production equations/input classes. They do not modify aircraft data, install an alternative model or qualify real hardware.

The [follow-up probes](follow-up-01/README.md) cover input ownership, Electric statistics integration, modal/trim diagnosis, early-stop reporting, interrupted/corrupt evidence and runway comparison/history contracts.

Use the repository's pinned Godot `4.8.beta2.official.cafc17a19`, imported baseline dependencies and the existing checked runner. From the repository root, after following [Godot tooling](../../tools/godot/README.md), run:

```bash
python tools/godot/run_checked.py --timeout 120 \
  --require-text AUDIT_PROBE_COMPLETE -- \
  .tools/Godot_v4.8-beta2_linux.x86_64 --headless --path app \
  --audio-driver Dummy --script "$PWD/research/ugly-stik-audit-2026-11-15/physics_probe.gd"

python tools/godot/run_checked.py --timeout 120 \
  --require-text '0 failed' -- \
  .tools/Godot_v4.8-beta2_linux.x86_64 --headless --path app \
  --audio-driver Dummy --script "$PWD/research/ugly-stik-audit-2026-11-15/controls_probe.gd"
```

Check the command-line flag spelling against `python tools/godot/run_checked.py --help` if the shared runner changes. On an enrolled test host follow the pool/slot rules in the repository instructions. The original audit ran in an unenrolled isolated Linux workspace; it did not claim a native Mac or rendered performance gate.

`physics_probe.gd` reports static production-law values at prescribed states, including propeller/rudder increments, ideal-electric power-off shaft samples and global/local/production side-force sweeps. Fixed common RPM across aircraft is not matched power or thrust. Its output includes the exact aircraft inputs. `controls_probe.gd` injects values/events through the production reader/calibration classes and checks the two reported edge cases; five checks passing confirms the reproductions, not a repaired behavior or device-incidence claim.

The flight campaigns use the existing [flight-test tool](../flight-test/README.md). Exact selected rosters and finite-pack override are in the dossier's [verification commands](../../docs/research/ugly-stik-flight-physics-2026-11-15/verification.md). After reproducing those campaigns, derive compact trace evidence with:

```bash
python research/ugly-stik-audit-2026-11-15/summarize_traces.py \
  --dynamic tmp/ugly-audit-dynamic \
  --pack tmp/ugly-audit-electric-pack \
  --out tmp/ugly-audit-trace-observations.json
```

The extractor retains hashes of all 85 original campaign CSVs and exact raw rows around cited events/source-voltage comparisons. It does not interpolate or round them again. Original event detection is at the simulation tick rate; exported CSV rows are at 20 Hz, so the closest row is not necessarily the exact event tick. Full CSVs remain regenerable from the pinned source/card and recorded commands; they are not all committed to the documentation directory. Regenerated timing or trace bytes should be compared with their complete engine/platform/source identity before claiming equivalence.
