# Game controls audit — verification record

## Outcome and evidence boundary

The audit reproduced the five stated defects within their individual scopes.
Four focused diagnostic programs completed successfully with **zero engine
errors and zero warnings**; the separate legacy interleaving completed all four
checked process stages with the same clean diagnostic counts. Those successful
witnesses describe adverse baseline behavior. They are not passing repairs.

The final serial attempt of **27 existing regression programs passed 22 and
left five failed or incomplete**. Its runner correctly returned exit code 1.
All 22 accepted programs have zero engine errors; one has two recorded focus
warnings. The five unqualified invocations report missing scene/vehicle assets,
associated script failures and, in three cases, timeouts. They are preserved as
failures, not counted as additional controls bugs or passing regression evidence.
No claim is made that missing assets are the only possible cause of every
uncompleted integration path.

This is Linux x86-64, headless, Dummy audio and synthetic input. It is neither
the complete app suite nor required CI, a rendered player journey, a native
Windows/macOS check, an exported package, physical-device qualification or pilot
acceptance. [QUALIFICATION](QUALIFICATION.md) retains those gates.

## Identity and source preparation

| Item | Recorded identity |
| --- | --- |
| Repository baseline | `57abea025f62b20233ca281d58d2acbee4ab8b8e` |
| Work branch | `audit/game-controls-2026-11-21` |
| Baseline `app/` Git tree | `afec0bb4b0eb17ae0b4baa3aa6fbbbbcfcb23059` |
| Engine | Official `4.8.beta2.official.cafc17a19`, Linux x86-64 |
| Production scope | No application source, profile preset, aircraft data, physics law or golden flight changed |
| Local scheduling | Final suites serial in one stable checkout; isolated XDG user directories per process |
| Test-pool enrollment | No configured pool/admission context was present for these local runs |

Engine SHA-512, verified through the repository getter and retained runner:

```text
428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9
```

The [source manifest](source-manifest.json) hashes 84 selected production,
fixture, tooling and governing evidence files against baseline bytes, plus the
new reproduction tools. This is a selected source manifest, not a full
transitive asset manifest. The checkout is sparse; the five unqualified programs
need larger scene/vehicle assets beyond the materialized static dependencies.

The last checked import passed with zero errors and 14 warnings saying that
missing UID files were re-created from cache. Their exact paths and hashes are
recorded in [verification.json](verification.json). They remained stable during
the serial attempt. After execution, only these owned generated untracked UIDs
were removed; tracked `app/` files and the final app working tree match baseline.
No `.godot` cache, generated metadata or source correction is part of the branch.
The [import receipt](evidence/import.checked.json) preserves that actual warning
state; it must not be described as a warning-free import.

## Existing regression attempt

The following command ran after successful import and inspection of the clean
tracked app tree:

```sh
python3 -B research/game-controls-audit-2026-11-21/run_checks.py \
  --out tmp/controls-audit-accepted --skip-import --jobs 1
```

The local folder name is not a verdict. The actual summary is 22 passed,
five failed, `production_unchanged=true`, `generated_uids_stable=true`, exit 1.
Full per-program checked receipts are retained under [evidence/regressions](evidence/regressions/);
[verification.json](verification.json) has their relative paths, hashes,
completion records and diagnostics.

| Existing program | Checked outcome | Completion evidence | Errors / warnings |
| --- | --- | --- | --- |
| `test_rc_input.gd` | PASS | 44 checks, 0 failed | 0 / 0 |
| `test_rc_calibration.gd` | PASS | 49 checks, 0 failed | 0 / 0 |
| `test_controller_profile.gd` | PASS | Controller profile: 91 checks, 0 failed | 0 / 0 |
| `test_controller_profile_hardening.gd` | PASS | Controller profile hardening: 94 checks, 0 failures | 0 / 0 |
| `test_controller_store.gd` | PASS | Controller profile store: 47 checks, 0 failed | 0 / 0 |
| `test_controller_audit_concurrency.gd` | PASS | Controller audit concurrency: 25 checks, 0 failed | 0 / 0 |
| `test_controller_registry.gd` | PASS | Controller registry: 27 checks, 0 failed | 0 / 0 |
| `test_controller_auto_defaults.gd` | PASS | Controller automatic defaults: 61/61 checks passed | 0 / 0 |
| `test_controller_external_audit.gd` | PASS | External controller audit: 42 checks, 0 failed | 0 / 2 |
| `test_controller_audit_shell.gd` | PASS | controller audit shell: 21 checks, 0 failed | 0 / 0 |
| `test_controller_audit_vehicle_quad.gd` | PASS | vehicle quad audit: 56 checks, 0 failed | 0 / 0 |
| `test_controller_audit_vehicle_airship.gd` | PASS | vehicle airship audit: 42 checks, 0 failed | 0 / 0 |
| `test_controls_setup_p0.gd` | PASS | all controls setup P0 checks passed | 0 / 0 |
| `test_controls_assign.gd` | PASS | Controls assign: 98/98 checks passed | 0 / 0 |
| `test_controls_workspace.gd` | PASS | Controls workspace: 106/106 checks passed | 0 / 0 |
| `test_setup_assistant_wiring.gd` | PASS | setup assistant wiring: 36 checks, 0 failed | 0 / 0 |
| `test_calibration_view.gd` | PASS | calibration view: 75 checks, 0 failed | 0 / 0 |
| `test_controller_pause_recovery.gd` | NOT QUALIFIED: timeout | No suite completion marker | 133 / 1 |
| `test_controller_recovery_focus.gd` | NOT QUALIFIED: timeout | No suite completion marker | 133 / 1 |
| `test_controller_routing_audit.gd` | PASS | controller routing audit: 31 checks, 0 failures | 0 / 0 |
| `test_mr_controller_authority.gd` | NOT QUALIFIED: engine_error | controller authority: 46 checks, 0 failed | 153 / 2 |
| `test_controller_menu.gd` | NOT QUALIFIED: timeout | No suite completion marker | 133 / 1 |
| `test_controller_conditioning.gd` | PASS | Controller conditioning: 57 checks, 0 failed | 0 / 0 |
| `test_controller_calibration_session.gd` | PASS | Controller calibration session: 20 checks, 0 failed | 0 / 0 |
| `test_controller_actions.gd` | PASS | all controller action checks passed | 0 / 0 |
| `test_controller_ground.gd` | PASS | Ground controller integration: 24/24 checks passed | 0 / 0 |
| `test_controller_car.gd` | NOT QUALIFIED: process_exit | No suite completion marker | 1 / 0 |

`test_controller_external_audit.gd` records two `grab_focus` warnings from
`controller_setup.gd` in this headless fixture. The checked runner's default
policy records warnings without failing. These warnings are disclosed; this
result does not qualify visible focus or accessibility.

The three timeout programs are `test_controller_pause_recovery.gd`,
`test_controller_recovery_focus.gd` and `test_controller_menu.gd`. They report
missing moon/tree/vegetation/population and aircraft-contract resources, followed
by null-state script errors; they do not complete their intended journeys.
`test_mr_controller_authority.gd` prints 46 passing assertions but has 153 engine
errors and two warnings, including a leak warning after missing scene/audio
resources. It is **not a pass**. `test_controller_car.gd` exits after a missing
`MT8_Bisonte.glb` vehicle resource. A fresh complete source environment is needed
to requalify these five programs and distinguish any remaining failure.

## Focused witnesses

The small witness logs and exact legacy patch are retained losslessly as JSON
`text` fields. Their decoded-byte hashes preserve the original output, including
whitespace, while container hashes identify the committed files.

All four diagnostic programs were run through `tools/godot/run_checked.py`,
with a required completion marker and inspection of `ok`, `complete`, error and
warning counts. See the [replay guide](../../../research/game-controls-audit-2026-11-21/README.md)
for exact commands. The airship and quad programs ran sequentially before the
final serial suite attempt. The range and callback programs were earlier
independent checked runs; their source hashes and production inputs match the
retained files.

| Diagnostic | Checked result | Actual observation and scope |
| --- | --- | --- |
| [Quad Pause](evidence/probe_quad_pause.checked.json) | 5 checks, zero failed; zero errors/warnings | Valid radio button 20 OFF/ON does not pause a running real quad activity. Escape does. Learned-axis admission is validated, not its runtime edge sequence. [Raw witness](evidence/probe_quad_pause.log.json) |
| [Airship boundaries](evidence/probe_airship.checked.json) | 11 checks, zero failed; zero errors/warnings | UI role clears to -1 while native map stays at 7; selecting 8 still leaves 7. Real store lease refusal clears, but Continue stays blocked until explicit method-level profile reapply. [Raw witness](evidence/probe_airship.log.json) |
| [External tiny range](evidence/probe_profile_ranges.checked.json) | 8 checks, zero failed; zero errors/warnings | Span `0.0000005` validates and survives V2 storage. Full and inverted idle output are `0.5`; actual gamepad reader is ready at `0.5`, while the corresponding radio is unarmed. Normal endpoints are controls. [Raw witness](evidence/probe_profile_ranges.log.json) |
| [Poll callback budget](evidence/probe_poll_budget.checked.json) | Completion marker `POLL_BUDGET_AUDIT_COMPLETE passed`; zero errors/warnings | 240 configured valid polls call the axis reader 2,400 times and button reader 30,720 times. This is not an OS/USB, CPU, FPS or latency measurement. [Raw witness](evidence/probe_poll_budget.log.json) |

The airship mapping witness uses actual registry, service, shell and activity
callbacks plus native `InputMap` matching. It does not show a physical controller
clicking the rendered HUD. The airship retry witness uses an actual V2 lease and
resolver with a production session and synthetic input. A direct
`apply_controller_selection()` call is its positive control; the baseline
player route is Home → Controls → relaunch, not a hidden Controls entry in the
airship HUD.

### Legacy calibration interleaving

[The receipt](evidence/legacy-race.json) and
[exact scheduling diff](evidence/legacy-instrumentation.patch.json) identify the
instrumentation. Only a disposable copy of `rc_calibration.gd` is modified.
The instrumented method still validates and uses the original ConfigFile
load/save operations. Seed and inspection use the unmodified production source.

| Stage | Observation | Checked result |
| --- | --- | --- |
| [Seed](evidence/legacy-seed.checked.json) | `seed` save returns OK | Complete; zero errors/warnings |
| [Writer A](evidence/legacy-writer-A.checked.json) | Device A save returns OK after both writers loaded the original snapshot | Complete; zero errors/warnings |
| [Writer B](evidence/legacy-writer-B.checked.json) | Device B saves its earlier snapshot after A completed, returns OK | Complete; zero errors/warnings |
| [Inspect](evidence/legacy-inspect.checked.json) | Seed and B exist; A is absent through the unmodified loader | Complete; zero errors/warnings |

Original source SHA-256:
`7b424b39e986c2105e6085afacf1c087fe6d2809702fa5be48dada847b9e49d4`.
Instrumented source:
`68d4f30e74f831247e2fb681a450930dda7ecc6d66d7cd72c80cb313a4bed53e`.
Driver:
`96da6da534889f0307204c28bed23e7f81c06227a2c1cceca89f6543e3d00aeb`.

The two concurrent writers are one deliberately scheduled component experiment,
with isolated user directories and a shared disposable file/barrier. No unrelated
suite or import belongs alongside that experiment. This demonstrates a possible
lost-update interleaving, not its frequency, a physical incident, a power-loss
failure or V2-to-V2 data loss. The smoke writer's similar source path was reviewed
but not separately raced.

## Rejected and incomplete preparation

Preparation failures remain failures. The compact JSON records selected earlier
receipts and summary hashes; full local logs remain under ignored `tmp/`.

- The initial sparse checkout lacked translations and fonts; subsequent broader
  checks exposed missing tracked static preloads and a GLTF texture. Some suites
  printed successful assertions while engine diagnostics failed the checked
  invocation. Those are excluded from accepted evidence.
- A preparation batch named `controls-audit-qualified` reported 16 passes and
  11 failures, with `production_unchanged=false` while materialization/import
  preparation was still unresolved. It is not an accepted stable run. Earlier
  parallel batches in one checkout are also excluded from the final serial gate.
- Godot's first import generated 64 tracked `.import` changes. After inspection,
  only owned metadata was restored. Restoring remaps before regenerating their
  referenced compressed cache targets caused further rejected resource loads.
  A subsequent checked import generated the committed S3TC/ETC2 targets without
  a tracked app diff. No workaround changed production script behavior.
- The first airship and quad audit scripts failed parsing because four inferred
  boolean variables lacked concrete type information. Explicit `bool` types
  were added only to those new research scripts. Their later clean receipts,
  not the parse failures, support the observations.
- The final serial attempt still contains five unqualified integrations, as
  listed above. No missing resource, null-state cascade, leak warning or timeout
  is silently converted into a pass or promoted to a new controls defect.

## Independent review disposition

Two bounded reviews covered profile/persistence and routing/lifecycle paths;
an independent challenge review checked counterexamples and the integrated
report. The lead inspected source and actual receipts before accepting claims.
Material dispositions were:

- **Accepted and reproduced:** the five scoped defects. The small-range and
  legacy cases retained their external-profile and instrumented-copy limits.
- **Narrowed:** stale native menu matching is not proof of rendered activation;
  a temporary resolver failure requires an uncached connection; direct reapply
  is a diagnostic control; callback counts are not a performance measurement.
- **Reclassified:** quad fallback is an accepted activity policy with a general
  documentation conflict. It holds the session and invalidates arm continuity;
  an armed stored frame can persist until the first resumed tick disarms it.
- **Left open:** a long gap without focus/disconnect events is source-derived
  coverage work, including aircraft watchdog ordering. Direct launch/menu
  support and hardware/platform claims need explicit qualification.
- **Preserved:** earlier CTRL-01–15 corrections, the event cache and periodic
  store-read optimization. Intentional JETI mapping/capture policy was not
  promoted to a duplicate defect. No objection quota or new ownership track was
  introduced.

The [audit](AUDIT.md) owns conclusions, [REMEDIATION](REMEDIATION.md) owns proposed
repair acceptance, and [QUALIFICATION](QUALIFICATION.md) owns remaining platform
and device evidence. No production repair or release approval is implied.

## Artifact integrity

Local checks processed 108 Markdown destinations, validated local paths and
heading anchors and checked the bounds of pinned source references. All JSON
artifacts parsed, all 84 selected source hashes matched baseline, and both Python
tools compiled in memory. Independent review also verified the recorded source,
tool, receipt and original local log hashes and the 22/5 regression disposition.
The exact-text containers round-trip to the original raw bytes; their updated
hashes are recorded in the verification JSON. The final staged diff passes the
repository whitespace check. These are artifact-integrity checks, not additional
game or platform qualification.
