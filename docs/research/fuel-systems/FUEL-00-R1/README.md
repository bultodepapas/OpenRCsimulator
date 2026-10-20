# FUEL 00 R1 fuel system audit evidence

**Date:** 2026-10-19. **Source baseline:** `903d0b444`. The tree was clean at the start; unrelated documentation, website and cleanup edits appeared during review and were preserved. This review adds documentation, audit probes and a Word export helper. It does not alter simulation behaviour or regenerate aircraft data, physics, goldens or existing flight evidence.

The [fuel guide and remaining work](../../../plans/fuel-mass-balance.md) describe current code. This page owns the findings and reproductions at `903d0b444`; they are not current implementation status. The adjacent Word document is a dated export of the original audit plan, with its original source SHA-256 in metadata. It is not synchronized with later guide revisions. Its [export helper](../../../../research/fuel-systems/FUEL-00-R1/build_document.py) uses the managed document runtime and `python-docx==1.2.0`. Historical FUEL-00 through 04 evidence keeps its original scope.

## Source anchors

Locations below refer to the reviewed source baseline, not graph-index line ranges. The knowledge graph was consulted first; missing/stale GDScript results required working-source verification.

| Finding | Source and observation at the audited baseline |
| --- | --- |
| A1 | `app/render/crash/director.gd:95,215-220,249`: kerosene-only scalar versus live glow source map. `app/render/crash/effects.gd:483-504`: the stain uses the source map and already sees glow |
| A2 | `app/sim/flight_session.gd:146-160,3549-3550,3591,3729`: fill setter/reset and metadata exist; checkpoint does not serialize the selected fill |
| A3 | `app/physics/glow/installation.gd:142,247-283`: liquid found by display name, authored amount used as reference/capacity. `app/physics/aircraft_data.gd:1350-1444`: normalized tank IDs, capacity, residue and fill |
| A4 | `docs/AIRCRAFT_CONTRACT.md`, coordinates section; `app/physics/aircraft_data.gd:431-465`; `app/physics/glow/installation.gd:278-283`; `app/tests/test_fuel_start_fill.gd:47-48`: fixed datum is reference inventory CG |
| A5 | `app/physics/glow/fuel_feed.gd:64-74`; `app/physics/rigid_body.gd:71-113`; `app/physics/fixed_datum_body.gd:15-24`: current force convention and omitted rotational feed terms |
| A6 | `research/fuel-systems/FUEL-05/relabel_synthetic.py:23-34`; `research/avanti-s/av06/inputs.json:256-282`; `app/data/aircraft/sebart_avanti_s_a200.json:91,777`: donor IDs incomplete, main tank only, empty smoke tank and lumped accessories |
| A7 | `research/fuel-systems/mass_balance_report.py:71,102,155-204`: non-recursive scan, wet inventory comparison, positive-margin failure check and non-failing drift messages |
| A8 | `app/physics/glow/flight.gd:319-325`; `app/physics/electric_battery_step.gd:262-275`; `app/tests/test_sf_event_protocol.gd:264-268`: type renamed, charge field retained, type-only assertion |
| A9 | `app/physics/glow/profile.gd:48-54`; `app/physics/glow/installation.gd:310`; `app/tests/test_fuel_properties.gd:57-70`: embedded profile density, current equality and deliberate divergence fixture |
| A10 | Generator check logs below; `docs/research/fuel-systems/FUEL-05/ft-glow-compare.md`: missing commit identities and invalid trim in the current comparison |

`.orfl` mass/CG is at `app/sim/flight_log.gd:176-179`. Ordinary trace column definitions at `app/sim/trace.gd:16-26,55-61` still have no live mass/CG. The [R05-B integration boundary](../../physics-audit-2026-10-14/remediation/R05/R05-B-dynamic-mass-integration-boundary.md) retains contact-event/remainder and free-rotor scope; a live mass accessor alone does not close that handoff.

## Findings at the audited baseline

The following findings and proposed repairs are retained from the original audit plan. Later code supersedes their implementation claims; use the current guide above for supported behavior.

P1 blocks consistent software behaviour or the common standard; P2 blocks qualification or complete integration. Historical findings F01 through F22 remain in FUEL-00 as dated evidence.

**A1 P1 Crash remaining fuel is inconsistent.** At a production glow crash with 25 percent remaining, `energy_sources.glow_fuel` is 0.0749805 kg, while `report.fuel_kg` and the kerosene scalar passed to crash effects are zero. The director initializes that scalar from kerosene only. The glow stain reads the correct source dictionary; this does not prove a missing stain. Close under FUEL-06-R1 with typed fuel reporting, consistent consumer inputs and a production-path regression.

**A2 P1 Restored fill preference and provenance are incomplete.** A half-fill checkpoint restores its actual fuel correctly into a fresh full-default session, but the destination retains `fuel_start_fill = 1`. Its trace omits the half-fill selection and reset loads 0.299922 kg instead of 0.149961 kg. This does not show a failure of exact state continuation. Close under FUEL-07-R1 by declaring and testing a restore/reset policy, serializing the launch selection or recording it as unknown; never infer it from remaining fuel.

**A3 P1 Tank validation and the glow installation use different identities.** The contract binds liquid and shell by ID, but the glow installation still finds `fuel_inventory` by exact display name and prepares capacity from the authored liquid mass. It does not apply normalized capacity, pickup or unusable mass. A renamed item can satisfy the tank contract while breaking the installation. Close ID/capacity binding in FUEL-05-R1; close delivered feed and residue in FUEL-09.

**A4 P1 The old plan confuses balance CG and solver datum.** D2 and older FUEL-04 prose promise a datum at `plan_cg`; the audited contract, loader and installation retain the authored inventory CG. Empty-tank balancing does not move that reference. The fuel guide's section 3.2 and the [decision record](../../../DECISIONS.md) supersede that wording without rebasing runtime state.

**A5 P1 The proposed rotational feed formula had mixed signs.** Existing feed implements apparent gravity as minus non-gravitational force divided by mass and omits rotation. The old proposal added point-acceleration terms to that apparent gravity. Instead derive it from gravity minus the complete inertial acceleration at the liquid point. A rotating-point fixture must establish the signs before FUEL-09; this concerns the proposal, not an existing rotational implementation.

**A6 P2 Fleet migration and its evidence are incomplete.** FUEL-05 snapshots exist, but its linked README is absent. Synthetic electric donor IDs, declared-state CG ranges, Ventage hopper/smoke accounting and finite operation of the remaining combustion fleet stay open. Reconcile the Ventage shell/liquid centroid separation against an explicit physical interpretation. Its smoke tank is currently authored empty. Do not invent liquid to fill it or label estimated placements as measured.

**A7 P2 Mass-report coverage and drift enforcement are incomplete.** Its non-recursive glob omits the nested battery configuration. Registered static margins are gated, but printed `DRIFT` does not affect exit status. The informational `plan_cg_matches_inventory` compares wet inventory even for an empty-tank target, and the report does not expose the declared CG range. Close in FUEL-05-R1 with catalog-plus-supported-variant coverage, explicit declared-state results and a failing drift mode where required.

**A8 P2 Depletion event units leak from the battery helper.** Glow renames `battery_exhausted` to `fuel_exhausted` while retaining `charge_residual_c`. Normalize the fuel payload to a declared mass unit and test the complete schema under FUEL-08. Keep the reusable event locator.

**A9 P2 Registry/profile equality is tested but not enforced at loading.** Glow profiles still derive density from embedded component data. Current tests establish agreement with the registry; the runtime installation does not reject a divergent blend. Close this seam with AS/NITRO in FUEL-05-R1, including a mismatch refusal and source-identity test.

**A10 P2 Qualification evidence is not reproducible end to end.** Read-only generator checks flag stale Timber physics output; Ventage passes the UTF-8 check. FUEL-05 FT comparisons contain blank commit identities and an invalid 55AX trim result. Preserve these as findings, not accepted flight-feel proof. Resolve or classify each under its owner before FUEL-05/12 closure.

Fourteen focused native Windows tests passed with 4,626 checks and zero failures. Both A1 and A2 still reproduce. Ordinary CSV traces still lack live mass/CG although `.orfl` has them. No full-suite, target-GPU, pilot or physical-validation result is claimed by this audit.

## Native focused tests

Engine: `4.7.2.stable.official.ed1daf0bf`, Windows x86_64 console, headless, Dummy audio. All 14 test files passed, **4,626 checks, zero failures**. Exit codes and logs were inspected; this is not the complete app suite or physical validation.

From the repository root, use the native pinned binary documented in [TOOLS](../../../TOOLS.md), then repeat this invocation for each test below:

```powershell
& $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_fuel_properties.gd
```

| Test | Checks | Complete log |
| --- | ---: | --- |
| test_fuel_properties | 30 | [log](2026-10-19-test_fuel_properties-win-godot-4.7.2.log) |
| test_fuel_system_contract | 27 | [log](2026-10-19-test_fuel_system_contract-win-godot-4.7.2.log) |
| test_fuel_mass_reference | 26 | [log](2026-10-19-test_fuel_mass_reference-win-godot-4.7.2.log) |
| test_fuel_live_mass | 13 | [log](2026-10-19-test_fuel_live_mass-win-godot-4.7.2.log) |
| test_fuel_start_fill | 20 | [log](2026-10-19-test_fuel_start_fill-win-godot-4.7.2.log) |
| test_glow_fuel_feed | 28 | [log](2026-10-19-test_glow_fuel_feed-win-godot-4.7.2.log) |
| test_checkpoint | 92 | [log](2026-10-19-test_checkpoint-win-godot-4.7.2.log) |
| test_checkpoint_integrity | 149 | [log](2026-10-19-test_checkpoint_integrity-win-godot-4.7.2.log) |
| test_flight_log | 3247 | [log](2026-10-19-test_flight_log-win-godot-4.7.2.log) |
| test_glow_trace | 282 | [log](2026-10-19-test_glow_trace-win-godot-4.7.2.log) |
| test_trace_metadata | 349 | [log](2026-10-19-test_trace_metadata-win-godot-4.7.2.log) |
| test_dynamic_mass_contact_session | 15 | [log](2026-10-19-test_dynamic_mass_contact_session-win-godot-4.7.2.log) |
| test_crash_masses | 27 | [log](2026-10-19-test_crash_masses-win-godot-4.7.2.log) |
| test_workshop_compiler | 321 | [log](2026-10-19-test_workshop_compiler-win-godot-4.7.2.log) |

The resource-kernel momentum fixture reports an error-refinement ratio of 16.0003129; removing the datum correction leaves about 0.122812 law error that does not refine away. This is the retained audit run, distinct from historical FUEL-04 values.

## Reproduced integration gaps

The retained [probe scripts](../../../../research/fuel-systems/FUEL-00-R1/) read current production APIs and create session-local test states. They do not edit aircraft sources or goldens. The crash probe sets a known remaining amount and a forced contact; it is software integration evidence, not a measured crash.

```powershell
& $GodotWindows --headless --path app --audio-driver Dummy --script "$PWD/research/fuel-systems/FUEL-00-R1/checkpoint_fill_probe.gd"
& $GodotWindows --headless --path app --audio-driver Dummy --script "$PWD/research/fuel-systems/FUEL-00-R1/crash_fuel_probe.gd"
```

**A2 checkpoint result:** source selected 0.5, source fuel 0.149961 kg. Destination initially selected 1.0. Restore accepted and retained actual 0.149961 kg; destination selection stayed 1.0 and trace fill was absent. Reset loaded 0.299922 kg. See the [complete checkpoint log](2026-10-19-checkpoint-fill-probe.log). The probe establishes correct restored fuel and the reset/provenance gap; exact continuation is covered separately by focused checkpoint/log tests.

**A1 crash result:** the production director activated on a gear-travel-limit contact. Live remaining fuel and `energy_sources.glow_fuel` were 0.0749805 kg; generic `report.fuel_kg` and `_fuel_kg` were zero, with the label claiming remaining finite glow fuel. See the [complete crash log](2026-10-19-crash-fuel-probe.log). An unrelated unsupported-tree-wind warning is retained. The source dictionary supplies the glow stain correctly; the scalar mismatch does not establish absent stain behaviour.

## Fleet report and generator checks

The [current stored report](../../../../research/fuel-systems/mass_balance_current.json) and read-only report run cover 14 top-level configurations, nine with tanks. All registered full/authored/empty static margins are positive. The nested optional Timber pack configuration is absent from this scan; it is a fifteenth fixed-wing data configuration, not a new airframe.

```sh
python -I research/fuel-systems/test_mass_balance_report.py
python -I research/fuel-systems/mass_balance_report.py --check research/fuel-systems/mass_balance_current.json
```

The two report tests pass. The report check prints no drift on this tree. Its current implementation exits nonzero for nonpositive registered margin, but does not fail on drift messages; missing neutral points also need an explicit qualification policy. Only Extra declares `cg_range`, checked by the loader at empty tanks. Its full-tank CG being ahead of that interval is permitted by this declared-state rule.

Read-only generator `--check` results: glow installations, base Stik tank migration, synthetic donor relabeling, Extra, P-51 and Ventage pass. Timber reports stale aircraft physics data. Checks used Python UTF-8 mode; the [generator log](generator-checks.log) retains exact commands and results. Resolve the Timber discrepancy with its owner before qualification; accepted output was not regenerated.

## Review limits

This audit does not close FUEL-05 through 14, replay the FUEL-05 candidate FT recordings, re-record goldens, benchmark performance or validate hardware. The [original reference manifest](../FUEL-00/sources.json) retains sourced capacities, density and flow evidence. No new physical measurement was made. Software tests and a positive estimated static margin do not establish realistic handling or endurance.

## Word export verification

The dated Word export contains the original audit-plan Markdown, with its source SHA-256 in document metadata. The packaged `render_docx.py` pipeline rendered seven Letter pages; every final page PNG was visually inspected. Tables repeat their headers and no clipping or orphan final page remains. The packaged accessibility audit reports zero high, medium or low findings. Local Markdown targets and the DOCX source identity were checked.

Authoring used the managed Python runtime with `python-docx==1.2.0`. This Windows runtime bundles no LibreOffice and exposes no dependency-loader tool, so conversion used a task-local official LibreOffice 24.2.7.2 download under WSL, a fresh isolated profile, and the managed Poppler rasterizer. The user's desktop office installation was not used. Rendered PNG/PDF files remain internal QA intermediates under ignored `tmp/`; the delivered artifact is the DOCX.
