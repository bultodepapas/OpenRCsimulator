# Test and observation matrix

Baseline: `cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`. Pinned Godot `4.8.beta2.official.cafc17a19`, Linux x86_64, headless/Dummy audio. [verification.json](verification.json) records the outcomes, engine/data identities and original-log hashes. Raw logs and runner reports are excluded from publication because they contain workspace metadata.

## Existing FPV-related suites

**25 suites, 1,120 checks, zero failed assertions and zero engine errors/warnings in the selected final runs.**

| Suite | Checks | Checked result |
| --- | ---: | --- |
| `test_controller_audit_vehicle_quad` | 56 | PASS |
| `test_dr_multirotor_kernel` | 15 | PASS |
| `test_mr_activity` | 96 | PASS |
| `test_mr_activity_race` | 19 | PASS |
| `test_mr_allocator` | 40 | PASS |
| `test_mr_camera` | 46 | PASS |
| `test_mr_controlled_plant` | 63 | PASS |
| `test_mr_data` | 86 | PASS |
| `test_mr_electric_bus` | 32 | PASS |
| `test_mr_fast_paths` | 17 | PASS |
| `test_mr_flight_log` | 31 | PASS |
| `test_mr_input` | 62 | PASS |
| `test_mr_osd` | 78 | PASS |
| `test_mr_rates` | 115 | PASS |
| `test_mr_sample_rate` | 11 | PASS |
| `test_mr_session` | 67 | PASS |
| `test_mr_visual` | 31 | PASS |
| `test_multirotor_arm_mode_aux` | 61 | PASS |
| `test_race_director` | 30 | PASS |
| `test_race_gate_crossing` | 19 | PASS |
| `test_race_model` | 30 | PASS |
| `test_race_records` | 13 | PASS |
| `test_race_session` | 49 | PASS |
| `test_race_session_replay` | 8 | PASS |
| `test_race_track` | 45 | PASS |

## Defect observation probes

A successful observation probe reproduces the baseline behavior. These are not desired-behavior product acceptance passes.

| Probe | Checks | Result |
| --- | ---: | --- |
| [air_start_regen.gd](../repros/air_start_regen.gd) | 5 | Observation reproduced |
| [controls.gd](../repros/controls.gd) | 24 | Observation reproduced |
| [direct_route.gd](../repros/direct_route.gd) | 6 | Observation reproduced |
| [minor_findings.gd](../repros/minor_findings.gd) | 10 | Observation reproduced |
| [physics.gd](../repros/physics.gd) | 7 | Observation reproduced |
| [profile_refusal.gd](../repros/profile_refusal.gd) | 10 | Observation reproduced |
| [racing.gd](../repros/racing.gd) | 11 | Observation reproduced |

## Deliberate engine-error case

`OPENRC_AUDIT_EXPECT_SCRIPT_ERROR=1` with `minor_findings.gd` repeats its ten admission/presentation checks, then invokes `RaceRecords.apply` on the accepted empty record entry. The observed diagnostic is:

```text
SCRIPT ERROR: Invalid access to property or key 'best_total_s' on a base object of type 'Dictionary'.
at: apply (res://vehicles/multirotor/race_records.gd:136)
```

The process exits 0, but the checked runner correctly exits 1. This intentional malformed-data observation is excluded from the clean baseline count.

## Import and excluded attempts

| Run | Outcome |
| --- | --- |
| `baseline-test_mr_activity` | Setup error: sparse checkout omitted fixed-wing authoring files required by Home; the unchanged suite passed after tracked sources were restored. |
| `fpv-audit-import` | Import completed with zero errors and eight unrelated OBJ ambient/PBR material warnings. |
| `repro-controls` | Superseded draft: two synthetic profile validation checks failed because dictionary keys did not match the serialized string-key form. The reviewed fixture passed. |

## Other verification

- [Generator consistency](generator-check.json): successful earlier `derive.py --check`, recorded from its observed tool result; shipped data hash matches.
- [Live UI smoke](ui-smoke.md): Home/catalog, course/OSD, countdown/GO/cancel, reset and Home; zero engine-error records and zero reported leaked objects at stop.
- Full CI, native rendering/hardware performance, real radios and selected-build physical validation remain open.
