# Second swarm audit: reproducible evidence

Production source: [8d4169f8febfd7d78a028eaa817414217a54f24b](https://github.com/bultodepapas/OpenRCsimulator/commit/8d4169f8febfd7d78a028eaa817414217a54f24b). Read the [audit report](../../docs/research/swarm-systems-audit-2026-11-28/README.md) and its independent review before interpreting these witnesses.

These are **counterexample and work-count probes**. A successful exit means the dated observation was reproduced, including an expected refusal or incorrect result where applicable. It does not mean that a product defect has been fixed. Production source is unchanged on the audit branch.

## Engine witnesses

Follow the repository's [tool selection and host-admission rules](../../docs/tools/shared.md) and perform the normal resource import from the [setup guide](../../docs/TOOLS.md) first. The evidence uses Godot 4.8.beta2.official.cafc17a19 on Linux x86-64. No pool was configured in the audit workspace, so its owner ran the checked local runner serially.

The convenience wrapper takes an explicit pinned engine path:

    python3 research/swarm-systems-audit-2026-11-28/run_probes.py --godot /absolute/path/to/Godot

Use --case with a name below for a focused run. The wrapper delegates diagnostics, completion-marker checking and timeouts to tools/godot/run_checked.py. It gives every invocation a fresh directory under tmp. Expected native-unavailable warnings are retained; engine errors still fail the checked run.

| Case | Witness | Boundary |
| --- | --- | --- |
| turbine | turbine_admission.gd | Public loader, reference session setup, public runway start and accepted/refused ticks |
| skyline | skyline_tree_toggle.gd | Real visibility policy and cache; synthetic registered ordinary mesh |
| birds | birds_off_poll.gd | Stock field builder, forwarding runtime counter and live re-enable control |
| water | water_after_expiry.gd | Real Main callbacks and forwarding water layer; synthetic impact and manual frame delivery |
| rotor | rotor_null.gd | Documented normalized-domain limit in a constructed reference RK4 state |
| gate | gate_projection.gd | Documented chord-scoring limitation with prescribed point trajectories |
| lake | lake_crest.gd | Public point/hull collision queries on stock water and aircraft geometry |
| records | race_book_two_windows.gd | Two production scene objects and real attempt/book writes; synthetic terminal results |
| draft | controller_duplicate_draft.gd | Real Controls widget and profile store; synthetic registry device |

The records and draft probes use process-specific disposable user-directory paths, separate from normal profiles and race records. The water run selects the reference fallback because the native library is not installed; this is not native coverage. The headless skyline control cannot read stock MultiMesh transform buffers and does not establish rendered pixel differences.

## Independent calculations and C++ comparisons

Run numerical_oracles.py in the probes directory with the repository path as its positional argument. It reads the shipped lake and reconstructs the phase intersection, entry/exit roots and gate-crossing discrepancy.

The native specialist's two Python drivers compile only disposable C++ component experiments. They take the repository path as their positional argument. spatial_propeller.py builds the original stage header and an experimental reuse variant. retractable_context.py compares a copied bridge operation with a candidate that preserves immutable context. Neither driver changes production headers or installs a native plugin.

The recorded compiler is GCC 14.2 with C++17, -O2, -fno-fast-math and -ffp-contract=off. The qualified Linux native compiler is GCC 13.3. These comparisons establish their emitted calls, named copy traffic and tested output parity; they do not qualify a supported package, ABI, whole flight or FPS result.

## Retained receipts

The evidence directory contains compact checked-run reports, each successful engine witness's short raw log, baseline summaries, independent numerical/C++ results and the exact-baseline CI snapshot. evidence/manifest.json binds the probes and reports to SHA-256 hashes.

Original checked-run commands contain the staging paths used at execution. The manifest hashes bind those files to their byte-identical committed copies. The wrapper above resolves the committed locations for reproduction. Local paths in historical receipts are provenance, not dependencies.

The renderer regression uses [CI run 46158166434](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/46158166434), job 141020383019, artifact 15268578223. Its compact capture log is retained with the artifact's index. The archived ZIP digest is 013a65c6d0b678dd7486eb8d90700ef3da3ee0d20f9d62ed138dde1449ef3f51. No locally rendered capture or target GPU measurement is asserted.
