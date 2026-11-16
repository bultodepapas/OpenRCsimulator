# AC-12 known servo-arrival partition experiment

Owner: AC-12 / AC-CV-06. Registered after the
[stage-ramp investigation](AC-12-servo-stage-2026-11-16.md), before these experimental flights.
The retained session chronology records prose registration; frozen source binds the executed protocol.

The C01 charge discrepancy is quantitatively explained by the integral of signed current
differences, with cancellation at six seconds. The current differences agree with the
authored closed-form RPM/charge electrical response. This does not establish which upstream
integration mechanism produced them. Servo arrivals near 0.542, 1.084 and 1.542 s lie inside
the tested steps; pitch-rate differences change sharply there. This is a falsifiable lead.

Reuse the exact ramp-source model, raw aircraft JSON and complete recorded 240 Hz ramp
baselines for C01/pitch_doublet and C15/roll_doublet. Keep reference backend, calm weather,
airborne, finite electric battery, gearless, no flaps/failures/soft hull contacts. Do not
change the slew law, accepted endpoints, outer clock, wake sampling, data or tolerances.

Add a pure bounded slew interval planner that reuses the existing endpoint arithmetic.
Its strictly interior arrival offsets exclude jams, no motion and exact endpoint arrivals;
deduplicate simultaneous arrivals exactly, without epsilon merging. A reusable battery-step
composition merges up to three extra offsets with existing uniform contact subdivisions,
retaining their event ordering, atomic failure and derivative refresh. Empty or coincident
cuts use the old path directly. Reject unrepresentable absolute boundaries. Three new cuts
must not invalidate a previously supported 16-piece contact partition.

First require native known-answer tests: independent integrals of rising/falling ramp-to-hold
forcing at fractions 0.08/0.16/0.32/0.64/0.28, original endpoint bits, duplicate/nearby cuts,
jam and endpoint cases, invalid/nonfinite data, refreshed derivatives, rejected-piece atomicity,
event ordering and late clocks. Embed scalar quadrature in a valid rigid-body-shaped state.
Run affected existing actuator, battery-step and contact-step checks.

Three private variants differ only in one source-hashed mode constant: `none`, `arrival`,
`midpoint`. The none control must reproduce every packed original ramp row, CSV and all
17-column samples exactly before either split flight. Arrival splits at actual slew
completion. Midpoint splits the same hit ticks into the same number of uniformly spaced
pieces, controlling for additional RK stages and quaternion normalization. Preserve one
outer sample/commit and apply pack supervision only once. Known-time cuts are numerical
integration boundaries, not new physical events. Recompute the first derivative after
every piece; preserve the original supplied derivative on piece zero only.

Retain actual-instance checkpoint/model/environment/backend checks, original input tapes,
all committed servo comparisons, live event/intervention refusal, bounded split diagnostics,
complete source-changed candidate reports and hash-bound raw post-step telemetry.

For each split variant, fix the same two cells at 240/480/960/960/1920/1920/3840 Hz using
the strict audit, complete own-source exact replay and unchanged legacy rule. Compare the
whole signed RPM/current/charge histories and pitch-rate differences across the first
arrival (common samples 0.5416667 and 0.5458333 s). Report whether arrival alignment reduces
the local discrepancy relative to both none and matched-work midpoint; no reduction is
assumed. A failed gate remains failed. This selected study is not domain-wide G05, physical
validation or authorization to enable ClearView flight.

## Implemented components and native checks

The integration tree now contains `physics/slew_interval.gd`, the additive
`ElectricContactStep.advance_at_offsets` entrypoint and `tests/test_slew_partition.gd`.
No production caller selects the new entrypoint. Removing the added function leaves
the original contact-step implementation byte-identical. This component slice changed no
`FlightSession`, kernel, aircraft record, golden flight or admission rule. The subsequent
generic kernel transport is described separately below.

Final component source SHA-256:

| File under `app/` | SHA-256 |
| --- | --- |
| `physics/slew_interval.gd` | `35c7e1145c2d954698de3102f388dc25ef874b0a42eb3073acb754f55fd0c10a` |
| `sim/electric_contact_step.gd` | `8d360e6ffc6aedce9585c1169de4b477d622d77544f102a5881cc2ed0daffd49` |
| `tests/test_slew_partition.gd` | `5c24835630cb2c6faa72d7dbd5636dd459ce024ba6664ccb3f3dc4bd438870e7` |

Checked runs on ANGELA_AIR, arm64 macOS, official Godot
`4.8.beta2.cafc17a19` (engine SHA-256
`2051c48febe532a5b156ffd8dd0c9381f74e40fde9177faff07a713851baba80`):

| Check | Final request ID | Result |
| --- | --- | --- |
| New slew/partition known answers | `d6f98a46f41e40acb8cf07d30e115fb5` | 49 checks passed |
| Existing contact composition | `947bf007ca2b46bba9a8d6ae443c08b4` | 12 checks passed |
| Existing finite battery step | `3cab5dbe5fd84635bb748139b9f3aaca` | 63 checks passed |
| Existing actuator contract | `025c261e847448e28555956cc15a933e` | 47 checks passed |
| Final none control | `3f7cfc27ec2c4f0caefd42462c1e1093` | Both complete trajectories and telemetry equal the previous ramp source exactly |

All final rows have zero checked errors/warnings. Preliminary attempts remain retained:
the first battery attempt used an incorrect required completion string despite 63 passing
assertions, and two actuator fixtures lacked asset dependencies. The latter were corrected
by including the real dependencies, without editing or skipping the actuator test. Those
failed receipts are not counted as passes. Earlier 47/48-check partition revisions are
superseded by the final 49-check source, including the absolute-clock resolution guard.

Independent review found no further concrete derivative, event-window or atomicity defect
under the bounded-clock contract. Local piece widths are retained; represented joins may
differ by the existing capped clock tolerance, at most 1 ns. They are not guaranteed
bit-identical. The guard rejects pieces at or below 16 times the absolute clock rounding
scale. Preserving historical servo endpoint arithmetic can also leave a tiny residual:
`actual=0.015`, `demand=-0.01`, `rate=1/0.14`, `dt=1/240` yields
`-0.010000000000000002`, then an arrival about `2.43e-19 s` away. Such an unresolvable
cut is refused, not merged or silently discarded. This remains a limit on general opt-in
admission; the component tests do not qualify arbitrary future aircraft callers.

## Frozen experiment and artifact closure

The final none control and both split snapshots have identical file sets and bytes except
the one `AC12_SERVO_KNOT_MODE` constant in their private `FlightSession`. The three
component files above equal the final native-tested bytes in the integration tree.
The strict audit driver remains
`45d9b0dbb851e86cb90b9f566653a50d60bf62453e090fcc6767a9018f0edcfa`.

| Variant | Probe | C01 refinement | C15 refinement | Retained input archive SHA-256 |
| --- | --- | --- | --- | --- |
| Arrival | `e6e787b76a624196b5ebd5015aa7b713` | `52c1063777c8444b91e677257c32d5bc` | `1c58e4cd18c54e7aa7d0d11c33d18cab` | `d44bc775749b28ab56adc3030d80607a9a97ce40d4afd69388effc0082917d14` |
| Midpoint | `29f08bb8a3124641a822f52ee1cbccd1` | `a90a7d6b6de24a178dea4017e32ba168` | `74ae2cddc0354b7a86136c9dc500fc0b` | `d39a617fc67eea6e54a5ebfc275a2d1debd60ca185f590d1bd8d40b9295fcae6` |

Both probes passed with three split ticks and six pieces per cell. C01 ticks were
130/260/370; C15 ticks were 123/247/363. Arrival used the actual offsets; midpoint used
half a tick in those same ticks. Every one of the 1441 committed servo rows retained its
original bits. Actual-instance initial context matched, scratch was cleared, and neither
cell produced a live kernel event or intervention.

All four refinement jobs passed operationally with zero checked errors/warnings. The 28
flights completed at the seven registered rates with valid clocks and finite traces.
Eight same-rate repeat comparisons were byte-identical. Each candidate's own baseline
replayed exactly, including tick 0 through 1440, with `solver_changed=false`; its extra
reader telemetry equalled its live 240 Hz trace. Source-changed probe reports retain
`solver_changed=true`, complete candidate status and actual-context checks. These are
different claims, not interchangeable replay modes.

All 16 refinement pairs were independently recomputed from the 17-column binary64
samples. Every metric matched the strict audit's cached input within the retained reducer's
cross-check limits. Each cell's 14 scientific files, checked log/report, source inventory,
engine identity and project-name transformation were verified and retained outside Git.
Only verified duplicate completed source/output copies and incoming caches were released
on the Mac; failed receipts and original native input archives remain retained on D:.

Evidence root: `D:\OpenRCsimulator-clearview-scratch\ac12-evidence-20261116`.
`servo-knots-{arrival,midpoint}-refinement/` holds the four cells and independent
metric receipts; `servo-knots-{arrival,midpoint}/` holds the probes.
`knot-study/comparison-receipt.json` binds the full-inventory comparison, main component
parity, signed history ranges and first-arrival samples. The none control is retained in
`servo-knots-none-final/`; native input archives are in the sibling
`retained-mac-inputs-20261116/` directory. No third-party assets or scientific binary traces
were added to Git.

## Numerical results and interpretation

The rule, floors, tolerances, bounds and seven-rate sequence were unchanged. All seven
metrics pass in each of the four split cells. The previous ramp-only C01 charge failure
remains part of the record.

| Cell / variant | Angular-rate estimated error at 240 Hz, degrees/s | Charge estimated error at 240 Hz, fraction | Charge ratio, 480/960 difference divided by 240/480 difference | Inherited rule |
| --- | --- | --- | --- | --- |
| C01 / ramp without cuts | 0.00327695 | Refused (`-1` sentinel) | 9.60813036 | Fail |
| C01 / arrival | 0.00299530 | 7.5163294e-8 | 0.27545196 | Pass |
| C01 / midpoint | 0.00298912 | 5.7260921e-7 | 0.15853288 | Pass |
| C15 / ramp without cuts | 0.05678753 | 5.8190850e-5 | 0.23240126 | Pass |
| C15 / arrival | 0.00669195 | 2.1077480e-6 | 0.29547533 | Pass |
| C15 / midpoint | 0.01512296 | 1.4052337e-5 | 0.33801925 | Pass |

For C01, the signed pitch-rate difference between 240 and 480 Hz is
`-0.00010275505 degrees/s` immediately before the first arrival (0.5416667 s) for all
variants. At 0.5458333 s it becomes `-0.00088898079` without cuts,
`-0.00012811814` with arrival cuts and `-0.00050857444` with midpoint cuts. The variants'
240 Hz samples are bit-identical through the 130 pre-arrival rows, and through 123 such
rows for C15. The retained traces contain the whole signed RPM/current/charge histories,
including subsequent cancellation; a final charge difference alone does not describe them.

Arrival alignment reduces this local C01 discrepancy relative to both controls. It also
has lower charge estimates than midpoint for both cells and a lower angular-rate estimate
for C15. Midpoint alone also clears the selected C01 failure, and its C01 angular-rate
estimate is slightly smaller. The evidence therefore supports resolving arrivals as a
useful integration boundary, without attributing every improvement exclusively to arrival
timing or claiming fourth-order convergence of the full sampled model.

## Remaining integration boundary

The candidate ramp law and its diagnostics remain private. A production adapter still needs
to select the generic interval transport below, a versioned law selector,
aircraft checkpoint/trace identity and candidate-only replay migration. Legacy and
`framed-sampled-v1` contracts must retain their existing meanings. Native admission must
refuse this unsupported law before recording unless reference selection is explicit.
Historical Creator drafts and default physical bytes must remain unchanged.

The two selected cells are not the 17-case/four-tape domain, exported desktop coverage,
1080p UI evidence or physical validation. G05 and ClearView trial/publication remain
closed. Installing an aircraft adapter cannot be replaced by promoting session scratch state.

## Generic interval transport integration

`VehicleModel.PROTOCOL_JOINT_INTERVAL` (`joint-interval-v1`) and its kernel dispatch are
implemented, with no production vehicle opt-in. Stage and contextual policy receive the
same semantic nine-key context: kind, before/after auxiliary arrays, before/after mode
arrays, inputs, tick, time and timestep. `pre_tick` runs once on detached read-only inputs;
its output becomes the accepted candidate sample. Boundary evaluation has equal before/
after arrays and zero duration. The existing full-frame reset API remains framed-only.

Callbacks receive independent copies. The kernel rejects argument mutation, net edits to
kernel/model state and transition reentry. A contextual policy cannot temporarily change
the live model before a delegated derivative and hide the edit afterwards. Substep k1
results and declared event transitions have the same protection on this opt-in path.
The protected input observer permits pilot input updates and checkpoint reads, while
blocking nested transitions and premature pause/fault publication. Stage queries beyond
representation-scale endpoint roundoff fail; permitted roundoff is clamped before the
law sees a time. Earlier rejected derivative queries remain latched even if a policy
ignores their return value.

The accepted interval protocol is pinned through reset/restore and checkpoint v2.
Changing protocol without another accepted boundary is refused in either direction,
including after the input observer. Legacy and framed-sampled-v1 callback signatures and
checkpoint shapes retain their meaning. Interval stages supply their joint rotor momentum;
an inactive legacy rotor callback is not evaluated. A non-null invalid interval policy
is refused rather than silently replaced with ordinary RK4.

Final native checks used a small isolated project containing the 12 real transitive source
files needed by the five kernel tests. It has a minimal project configuration and no
production autoloads; no test was skipped or rewritten to avoid a dependency. The three
changed code/test files were copied into the integration tree only after their hashes
matched the frozen checked input. This proves those components and the listed contracts,
not application/autoload or exported-platform coverage.

| Check | Request ID | Result |
| --- | --- | --- |
| New analytic integral, interval/policy/reset/restore and rejection cases | `8c63be7709434beba5d0b4dc429d8a16` | 130 checks passed |
| Existing simulation | `853fb098fbd84a048b6911c0b2e2a4fa` | 11 checks passed |
| Existing VehicleModel | `a135faaa5d6145eca72b861e4564c4a0` | 40 checks passed |
| Existing framed protocol, including legacy dispatch | `dbbc6a4357fe4267aea8e5f088df3718` | 50 checks passed |
| Existing endpoint transitions | `f158c04370c84c7198ef6573370a47fc` | 274 checks passed |

All five final runs passed on the same official arm64 Mac engine with zero checked
errors/warnings. Input archive SHA-256:
`02d321a414aeabd87e36a1d334ba2b3307c72966023dbdeef9f07468799819b3`.
Final file SHA-256:

| File under `app/` | SHA-256 |
| --- | --- |
| `sim/simulation.gd` | `539b647c9c772e0bdcfb8390a4ff3b0b04f1834f1a43dff3a120e6231acd2eea` |
| `sim/vehicle_model.gd` | `344f8c102445659c8bac83d44db69f25093c2ff359a35f4108eb69c5da41bacd` |
| `tests/test_sf_joint_interval.gd` | `8f68eea0e6cc97745bb45a2e80e4bf978f2c3db3cf03f8f33b0a71e747e367f0` |

The read-only independent review identified invalid-policy fallback, inactive-rotor
evaluation, nested policy/observer reentry, mutable k1 aliases and excessive stage-time
slack in drafts. The final implementation addresses these and the new tests exercise
their rejection. The final static review found no further material defect in its scope.

Superseded attempts remain retained. `4f726869af2544b4b518d87343958094` ended
`INFRA_FAILED`, with incomplete execution evidence and an empty check log; collection
also encountered a missing-log-field error. Its verified available artifacts and exact
original input archive were retained independently; the incomplete native source remains
untouched. `3079f0e52bb74f57b9a92579cec8ac51` exposed a test-fixture variable-shadowing
parse error (two checked errors), fixed in the final test. Neither is a pass. Windows
request `39614203c3484f93b71501931905cfca` waited behind an unmanaged simulator and was
canceled before dispatch when its input became obsolete; that other simulator was preserved.

`interval-study/integration-receipt.json`, frozen inputs, checked reports and failure
receipts are retained under the evidence root above. This transport does not itself install
or qualify the servo ramp law, change stock golden flights, or enable ClearView trial/publication.

### Real consumer regressions

The affected existing consumer tests also passed on the integrated code under an isolated
minimal project. All copied GDScript inputs were checked against the main tree byte for
byte. These tests exercise ordinary fixed-wing sessions, declared events and contact
policies, the Creator's existing estimated aircraft and the actual framed multirotor path.

| Unmodified existing test | Final request ID | Checks passed |
| --- | --- | --- |
| `test_sf_event_protocol.gd` | `ce8d6952126245b8930f4da6194c495d` | 46 |
| `test_sf_contact_substeps.gd` | `8254dd6a9e21408fa978381bf7579005` | 13 |
| `test_sf_event_refinement.gd` | `0b55ea6a73ca429faaa55e82016d291d` | 60 |
| `test_dr_multirotor_kernel.gd` | `6183036274ea4081836e3eebf1eb4798` | 15 |
| `test_creator_flight.gd` | `9f5d5b457c2c468ca60175ab4a682c02` | 56 |

All final reports have zero checked errors/warnings. The Creator test covers its 20 s
hands-off flight, signed control responses, hand launch, existing step-refinement check
and dihedral response; this is its original test, not the private servo-ramp candidate.
Its final archive is
`804452a4b4d91dbd2fa8023dffbe297d8e7f19b87a1b876c8a40bd05a77347d7`;
the four other passing consumers use
`a4b70ffa3fe8109a726ac6de003628aa3054a1e2e778258b11b89d064341d0bc`.
`interval-study/consumer-validation.json` binds all five checked reports and source parity.

The initial consumer fixture omitted glTF sidecars: import attempt
`3cebb791957245d8b9104c5b690a2449` failed before test execution with 20 checked errors.
Its input and import artifacts remain retained; four obsolete waiting rows never dispatched.
The real local buffers/images were then included. Creator attempt
`a8c6d33f53e8451f91b8946c1aae71d2` printed 56 passing assertions but retained eight
dependency compile errors, so its checked result remains failed. The final fixture adds
the three real relative preload dependencies, without changing the test or production code.
Only the affected Creator check was repeated for that closure correction.

Required application CI, production autoloads, exported/platform coverage and rendered
1080p evidence remain open for the combined candidate. Passing these targeted software
checks is not physical validation or complete ClearView qualification.
