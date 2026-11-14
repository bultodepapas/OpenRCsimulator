# Evidence verification

> **Archive curation note:** This independent review describes the original working evidence set of 44 runs. The delivered archive selects 29 successful original runs; earlier failed and superseded attempts are not included. See selected_runs.json for the exact selection. Additional portable-launcher delivery checks are stored separately in ../delivery_verification/ and are not part of that original 44-run count.

Verified from retained files without rerunning Godot or tests. The clean sparse checkout is at `f41d0fd2eb5483c609bcd858bcf22776eb311e14`; its local `origin/main` tracking reference resolves to the same commit. This check did not fetch the remote. The engine executable’s independently recomputed SHA-512 is `428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9`; the retained engine logs identify Godot `4.8.beta2.official.cafc17a19`.

## Existing tests

The 14 distinct existing scripts below reported **845 checks passed**. Thirteen counts come from numeric completion lines. The controller-actions script has no numeric completion line: its successful log contains 24 individual `ok` lines and the final “all controller action checks passed” marker. The two earlier controller-actions runs with seven Spanish-translation failures are excluded; the selected run uses the completed translation fixture. All listed reports say `ok=true`, process exit 0, and zero recorded engine errors. The checked runner was not configured with a required completion string for these tests, so the completion lines were checked manually.

| Test script | Checks | Retained checked-runner report |
| --- | ---: | --- |
| `test_controller_conditioning` | 57 | [test_controller_conditioning-stateh0z](parent/runs/test_controller_conditioning-stateh0z/report.json) |
| `test_controller_profile` | 74 | [test_controller_profile-hplpeilt](parent/runs/test_controller_profile-hplpeilt/report.json) |
| `test_controller_actions` | 24 | [test_controller_actions_complete-fixture-lycwwram](parent/runs/test_controller_actions_complete-fixture-lycwwram/report.json) |
| `test_rc_input` | 41 | [test_rc_input-b3pujj8u](parent/runs/test_rc_input-b3pujj8u/report.json) |
| `test_rc_calibration` | 39 | [test_rc_calibration-jum0kyc9](parent/runs/test_rc_calibration-jum0kyc9/report.json) |
| `test_jeti_runtime` | 105 | [test_jeti_runtime-vvr_oscm](parent/runs/test_jeti_runtime-vvr_oscm/report.json) |
| `test_jeti_identity` | 56 | [test_jeti_identity-8uu1agzc](parent/runs/test_jeti_identity-8uu1agzc/report.json) |
| `test_controller_registry` | 27 | [test_controller_registry-qef29si_](parent/runs/test_controller_registry-qef29si_/report.json) |
| `test_radio_menu` | 180 | [test_radio_menu-__x0evr2](parent/runs/test_radio_menu-__x0evr2/report.json) |
| `test_controller_store` | 47 | [test_controller_store-qtezrwk3](parent/runs/test_controller_store-qtezrwk3/report.json) |
| `test_controller_profile_hardening` | 94 | [test_controller_profile_hardening-wr12r9vn](parent/runs/test_controller_profile_hardening-wr12r9vn/report.json) |
| `test_controller_diagnostics` | 49 | [test_controller_diagnostics-0nwny1yz](parent/runs/test_controller_diagnostics-0nwny1yz/report.json) |
| `test_input_report_buttons` | 15 | [test_input_report_buttons-877dpnkw](parent/runs/test_input_report_buttons-877dpnkw/report.json) |
| `test_controller_auto_defaults` | 37 | [test_controller_auto_defaults-a1p2pp3j](parent/runs/test_controller_auto_defaults-a1p2pp3j/report.json) |

## Copied sources and fixture boundaries

Each copied file with a corresponding tracked `app/` path was compared against the exact Git blob and SHA-256 of the target source bytes; sparse-excluded asset sources were read from Git objects. Generated `.godot/` caches and helper scripts were not treated as production code. The detailed per-file values are in [verification_summary.json](verification_summary.json). The 29 entries of the parent’s original source manifest also match both the current fixture and the target source.

| Disposable project | Byte-identical tracked files | Deliberate or generated differences |
| --- | ---: | --- |
| `calibration/project` | 25: 24 GDScript files and one shader | Minimal `project.godot`; 24 generated `.gd.uid` files and one `.gdshader.uid` differ. Two audit scripts and one probe UID are fixture-only. |
| `profiles/repro` | 214, including 100 GDScript files, three shaders, 102 matching UID files, source assets and other tracked resources | Minimal `project.godot`; one `build_info.gd.uid` differs. Four regenerated SVG `.import` files differ only in their UID fields. Four probe scripts and one probe UID are fixture-only. |
| `routing/probe` | 127 GDScript files | Minimal `project.godot`; `scenery/collision_world.gd` is an intentional stub for the isolated airship resume-gate probe. Three probe scripts are fixture-only. |
| `parent/project` | 30: 29 GDScript files and the Spanish translation source | Minimal `project.godot`; 29 regenerated `.gd.uid` files differ. `audit_hotpath.gd` and `shell_projection.gd` are fixture-only. |

The only differing tracked **production GDScript body** is the explicit routing collision stub. The parent projection contains inert fixture objects around 13 extracted `app_root.gd` methods; each method body and source line was independently compared and matches exactly. It is still an isolated projection, not the complete AppRoot application. UID and import-metadata differences are real: they are not included in the byte-identical counts, and full resource-identity behavior was not tested. The minimal project configurations also affect test setup, including translation loading.

## Selected diagnostic and probe runs

These are synthetic observation probes. A passing probe means it completed its checks or printed the requested discriminating result; it does not mean the observed product behavior is correct. Do not add the probes’ overlapping counts to the 845 existing-test checks.

| Evidence | Completion or result | Retained checked-runner report |
| --- | --- | --- |
| calibration regression observations | `Calibration audit: 16 checks, 0 failed` | [calibration-range-kind-oc1xiz39](calibration/runs/calibration-range-kind-oc1xiz39/report.json) |
| calibration UI observations | `Calibration UI audit: 5 checks, 0 failed` | [calibration-ui-audit-s8fv9m38](calibration/runs/calibration-ui-audit-s8fv9m38/report.json) |
| profile observations | `AUDIT_PROBE_COMPLETE failures=0` | [profile-audit-probe-clean-95t_jjdb](profiles/checks/profile-audit-probe-clean-95t_jjdb/report.json) |
| capture observations | `CAPTURE_PROBE_COMPLETE failures=0` | [capture-audit-probe-_6ptodtq](profiles/checks/capture-audit-probe-_6ptodtq/report.json) |
| race writer A | `WRITER_DONE name=A ok=true error=` | [race-writer-A-voljxvdk](profiles/checks/race-writer-A-voljxvdk/report.json) |
| race writer B | `WRITER_DONE name=B ok=true error=` | [race-writer-B-5x8nh0xi](profiles/checks/race-writer-B-5x8nh0xi/report.json) |
| race final store | `FINAL_STORE names=["Writer B"] ok=true` | [race-final-store-2eo9smvp](profiles/checks/race-final-store-2eo9smvp/report.json) |
| routing adapter observations | `probe complete` | [routing-probe-o8_odrzc](routing/runs/routing-probe-o8_odrzc/report.json) |
| quad flight controller observations | `quad FC probe complete` | [routing-quad-fc-_56c9onu](routing/runs/routing-quad-fc-_56c9onu/report.json) |
| airship pause observations | `airship pause probe complete` | [routing-airship-pause-isolated-htm18wz6](routing/runs/routing-airship-pause-isolated-htm18wz6/report.json) |
| projected hot-path count | `HOTPATH_AUDIT_COMPLETE` | [hotpath-count-kyz0guyw](parent/runs/hotpath-count-kyz0guyw/report.json) |
| projected hot-path timing | `HOTPATH_AUDIT_COMPLETE` | [hotpath-timing-isolated-24rd1oly](parent/runs/hotpath-timing-isolated-24rd1oly/report.json) |
| projected shell parse | `Parse-only: checked runner passed; no required text` | [shell-slice-parse-v9jv7f9j](parent/runs/shell-slice-parse-v9jv7f9j/report.json) |

The final calibration input probe contains 16 checks, the calibration UI probe five, the profile probe 12 `OBSERVED` lines, and the capture probe six `OBSERVED` lines. The final calibration input run deliberately emits two overlap warnings; its report records zero errors and `ok=true`. The concurrent-writer observation is three separate successful checked runs; the final store retaining only Writer B is the adverse observation. Routing probes print values rather than an assertion count.

The projected hot-path timing log reports a median **1,217.2535 µs/event** for the production-method projection and **292.0475 µs/event** for a map-cache-only prototype, across seven alternating rounds of 2,000 synthetic events on the recorded Linux host. This is not a full-app, device, latency, frame-pacing, or target-hardware measurement; the prototype has no cache-invalidation implementation. The count fixture directly records seven `_controller_bindings` calls, eight `profile_for_device` calls, and a stored generic-identity map size of 30 for each selected/unselected event. The code constructs per-action identity dictionaries in the loop, but the fixture does not instrument allocation counts.

## Retained failures and integrity

All **44** retained checked-runner reports were matched to their current log byte lengths and SHA-256 values: **35** report success and **9** report failure. A matching log hash proves consistency with its report, not independent authenticity or an immutable record of all test inputs. Final reports cited above are selected successes; earlier failures remain in place:

- Two controller-actions attempts failed seven translation assertions before the fixture was completed.
- Two profile-probe attempts encountered missing fixture dependencies/assets; their checked runners failed despite completion text.
- The first airship-pause attempt encountered missing render dependencies; the cited isolated run uses the disclosed collision stub.
- One calibration probe had 10 checks with zero assertion failures but the wrapper expected the wrong `8 checks` completion marker; the later runs passed with corrected markers.
- Two hot-path draft attempts and one projection parse attempt failed on draft parse issues before the cited successful runs.

No physical controller, SDL or USB enumeration, graphical flight session, exported package, RF-loss case, full suite, or target-hardware performance test was performed in this verification. The current fixture hashes and checked-runner logs do not by themselves prove that no file changed while a prior run was in progress.
