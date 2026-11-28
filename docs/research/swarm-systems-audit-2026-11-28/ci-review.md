# Exact-baseline CI review

Production source: [8d4169f8febfd7d78a028eaa817414217a54f24b](https://github.com/bultodepapas/OpenRCsimulator/commit/8d4169f8febfd7d78a028eaa817414217a54f24b). The [machine-readable snapshot](../../../research/swarm-systems-audit-2026-11-28/evidence/ci-snapshot.json) records the observation time, job states and run identities.

## Status at the retained observation

| Workflow | State | Observed results |
| --- | --- | --- |
| [Main push CI, 46158166434](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/46158166434) | Still running, not green | Two failed jobs: visual captures and unit shard 3. Other completed jobs and remaining active jobs are listed in the snapshot. |
| [Manual publication captures, 46158202470](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/46158202470) | Completed successfully | Linux and Windows capture jobs passed. |

The manual workflow's success establishes its own capture result. It does not update the tracked source-bound fixture automatically and does not make the main workflow green. Skipped dispatch-only jobs are not failures; active jobs are not passes. The first audit's six failures belong to a different source commit and are not repeated here.

## R2-SW-03: runtime shader-global introspection breaks the rendered capture

[Visual job 141020383019](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/46158166434/job/141020383019) failed in app/capture.sh. Its first core capture ran Godot 4.8-beta2 with Compatibility, Mesa 25.2.8 and llvmpipe.

The compact artifact contains two errors. RenderingServer's global parameter list query reports that it must not be used outside the editor. The following global add reports that the name already exists. Both point to app/render/field_detail_preferences.gd:19–20.

The call chain is production Main → World → the capture's atmosphere_field fixture → the real grass/ground material → ensure_ground_global. The project already declares openrc_ground_simple. Commit [9900d065](https://github.com/bultodepapas/OpenRCsimulator/commit/9900d065c2417b757d05b81a200d0fa48de72155) introduced the list-based existence check to address a separate missing-global exported pack check. The confirmed regression concerns runtime introspection and duplicate registration in this rendered capture.

The capture saved a PNG with a successful image-save status. The checked capture then rejected the engine errors. This is not evidence of pixel corruption, a rendering hang, an aircraft fault or an FPS loss. A local headless dummy renderer does not exercise the same renderer branch.

**Repair scope:** use a supported registration strategy for normal project-owned globals and the separate empty/headless pack setup. Test missing and preexisting globals under the relevant runtime renderers, plus the exported pack check. Keep diagnostic failures visible; suppressing the error scan would remove useful coverage.

Artifact 15268578223, capture-diagnostics, ZIP SHA-256:

    013a65c6d0b678dd7486eb8d90700ef3da3ee0d20f9d62ed138dde1449ef3f51

The retained [capture log](../../../research/swarm-systems-audit-2026-11-28/evidence/ci-capture.log) is 2,117 bytes and matches its [artifact index](../../../research/swarm-systems-audit-2026-11-28/evidence/ci-capture-index.json), SHA-256:

    526bc8722a4dabde0d22aa912d2105f9416fd948864e5470d12fc5c0c0e8974c

## Source-bound shaft-publication evidence refuses the current source

[Unit shard 3, job 141020383175](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/46158166434/job/141020383175), reports a failed prerequisite in test_shaft_publication.gd: the source-bound fixture cannot load because its manifest or source identity differs. The [job excerpt](../../../research/swarm-systems-audit-2026-11-28/evidence/ci-unit3-excerpt.log) retains selected failure lines, with terminal colors and trailing whitespace removed, rather than a whole unit log.

The independent verifier checked the current source using the bridge's script-lf normalization. The publication fixture's byte hash, named engine, format and both internal overlay hashes match. **Two of nineteen source pins differ:**

| Production source | Expected prefix | Actual prefix |
| --- | --- | --- |
| sim/flight_session.gd | 7046a99ff225 | 8df9adccef7c |
| sim/simulation.gd | 8da099ff3cef | 4a3ca39ee4c8 |

The [pin receipt](../../../research/swarm-systems-audit-2026-11-28/evidence/publication-pins.json) contains the complete hashes. This is a qualification gap before typed shaft endpoints are compared. It does not establish solver drift or justify replacing pins without renewing the underlying evidence. Keep the fixture binding intact, reconstruct or regenerate the appropriate source-qualified evidence, and require a deliberate source-mutation control when rebinding.

## Local evidence and remaining qualification

The audit independently ran nineteen selected unchanged Godot tests and nine new witnesses through the checked runner. Those results qualify their stated paths and coexist with the failed full CI gate. No test framework, source pin, production file or CI policy was modified to produce a passing audit receipt.

Native component comparisons used GCC 14.2; qualified native package, full replay and rendered target-hardware performance remain separate gates. This report is an audit snapshot, not a release approval.
