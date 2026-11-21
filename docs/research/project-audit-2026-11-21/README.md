# Mathematical and aerodynamic hardening - 2026-11-21

The [A36 original audit](../../../external%20Audits/physics-math-aero-audit-57abea0.md) reviews `57abea025f62b20233ca281d58d2acbee4ab8b8e`. This page owns its follow-up status and evidence. Work remains within the existing imported-aircraft, blimp, FPV/race, helicopter, battery, ground-effect, logging and CI owners; this is not a new simulation-kernel track.

The owner requested one GitHub branch containing every finding and continued physics, mathematical and aerodynamic improvement: `audit/physics-math-aero-2026-11-21`. Original artifacts below remain unchanged; implementation commits and later measurements must retain their own source identity.

## Continued independent physics investigation (A36 R2)

The [21 November second-pass physics and mathematical review](second-pass-physics-2026-11-21.md) adds two **source-confirmed** FPV defects: rotor aerodynamic coefficients failing to respond to a supplied non-reference stage density (R2-F01; R7 establishes that the current player drone session holds reference density), and a 90-degree Angle-heading reference seam near vertical pitch (R2-F02). The [portable independent equation probes](probes/physical_crosschecks.py) quantify both without claiming an application or Godot test. It also records a constructed blimp bus-power candidate (R2-I01) and separately quantifies already-known blimp buoyancy, FPV rotor inflow/ground effect, wing spanwise drag and turbine fuel limitations. No new runtime fix or physical calibration is claimed in R2. The original A36 findings and completed software gates below retain their distinct status.

## Third-pass energy, mass and numerical audit (A36 R3)

The [third-pass source and physical investigation](third-pass-physics-2026-11-21.md) records **R3-F01**, source-confirmed positive speed-based pack current during zero-command blimp rotor rundown (shipped-data half-speed witness **1.009759 A**, full-speed witness **8.294661 A**). **R5 narrows its interpretation:** zero command on a connected pack does not establish an unpowered coast; this is an unresolved ESC/shaft-power coupling gap, conditional on intended policy. R3 also records **R3-G01**, the Nitro truck's 100 g fuel state changing without recalculating body mass, CG or inertia (a **0.980665 N** full-to-empty weight delta), and **R3-O01**, shallow model and deep input-control copies in the 240 Hz Nitro hot path. The [independent Python arithmetic](probes/third_pass_power_and_mass.py) is checked separately from actual Godot stages; no new accepted-session, native or target-hardware performance qualification is claimed. R3 contains negative controls for Euler rigid-body equations, generalized inertia, rotorcraft atmosphere admission and divergence-free thermal streamfunctions. The R2 findings remain open and the original A36 evidence remains immutable.

## Fourth-pass wake integrity and stage work (A36 R4)

The [fourth-pass end-to-end physics audit](fourth-pass-physics-2026-11-21.md) follows v2 aircraft capability admission through model derivation, GDScript free-tail/wake loading and the native wake guard. **R4-F01** identifies unconditional missing-horizontal-tail Dictionary accesses in GDScript slipstream/swirl evaluation, despite tailless models intentionally omitting that surface and wake input permitting a vertical-only fin; the native wake checks presence first. **R4-F02** identifies missing cross-piece overlap and unique-tail-area validation: two identical nominal 0.10 m² wake pieces on the same 0.15 m² fin yield **133.3% asserted coverage** and exactly **twice the incremental tail force** in an independent attached-flow source-formula calculation (−0.982850911 N vs −1.965701821 N). **R4-O01** continues **A6 O5**, the existing prepared spatial-wind geometry opportunity; its 10 samples/stage and illustrative 9,600 queries/s are not measured counts or a speedup. R5 links the prior unguarded prototype and its failed stale-NaN refusal control, avoiding a duplicate optimization count. The [Python 3 equation and optional source-fingerprint probe](probes/fourth_pass_wake_partition.py) is not a Godot/complete-aircraft acceptance test. The R4 report records physical references, reference/native uncertainties, negative controls and exact follow-up gates. Earlier findings and tests remain separate.

## Fifth-pass feasibility, event geometry and thermal stability (A36 R5)

The [fifth-pass mathematical and physical investigation](fifth-pass-physics-2026-11-21.md) adds **three bounded findings and one consistency/calibration gap** at source `136b32e585dc84293b81fc036a81530a04da5397`:

| ID | Reproduced result | Evidence boundary |
| --- | --- | --- |
| **R5-F01** | Stock helicopter trim is added after swash travel limits; the applied angle triple requires a servo target **1.029262** when the allowed upper limit is 1 | Stock X-Cell session accepts a 240 Hz reference tick; independent inverse linkage and separately evaluated initial flap derivatives; no real-servo or crash claim |
| **R5-F02** | A curved path remains within the **0.542535 mm** chord allowance, yet its gate-plane intersection differs by **1.735358 mm** and lies outside an aperture that the real director scores | Analytic constant-acceleration piece through actual track/director APIs; no integrated FPV plant or collision-world false-award claim |
| **R5-F03** | An admitted custom battery's omitted thermal time constant gives RK4 amplification **6.016236**, versus exact cooling **0.01550385**, in an accepted reference tick | Constructed, fully admitted custom data; ambient-start positive-heat sign check and diagnostic refinement; no stock-pack instability claim |
| **R5-G01** | Near-ground differential aileron changes the local strip roll moment by **13.8979%**, while the public attached path leaves it unchanged | Stock Stik component calls plus independent strip algebra; a model-path difference, not a measured physical error |

The [portable reproducer](probes/reproduce_fifth_pass.py) reconstructs **439 real dependencies with no stubs** from pinned Git objects. Its clean import, four new probes and unchanged 19/33 race tests passed with zero engine errors/warnings; three independent Python oracles assert the claimed discrepancies. The [R5 evidence record](fifth-pass-evidence.json) retains full small logs, checked reports, source/data hashes and oracle output. Each finding includes alternative repairs, negative controls and promotion gates. R5 also corrects the R3 zero-command interpretation and deduplicates R4-O01 into A6 O5. No R5 production physics fix, native execution, complete-app qualification or measured performance gain is claimed.

## Sixth-pass propulsion, flap/wake consistency and tailless admission (A36 R6)

The [sixth-pass report](sixth-pass-physics-2026-11-21.md) reviews source `f2d9bf7c0e1fad77158bbadcb99c0c487ddb94ac` and adds two bounded consistency gaps, plus stronger evidence for an existing finding:

| ID | Reproduced result | Boundary |
| --- | --- | --- |
| **R4-F01, evidence upgrade** | A synthetic tailless tractor with a vertical-only wake passes complete admission, then component/setup evaluation reads the absent horizontal tail and emits engine errors | The matched no-wake control trims and accepts a reference tick; no stock X8, accepted wake-enabled tick or native/swirl execution claim |
| **R6-G01** | A one-knot custom Cp change gives **54.237530 W** of thrust work from **41.715561 W** of aerodynamic shaft input; a second custom map exposes the same class at normal trim | Custom-data hardening opportunity extending NITRO-01/02; the matched stock point passes; stage values and tick acceptance are distinct from an integrated energy result |
| **R6-G02** | Static and explicitly settled flap wake give different drag/pitch in all three stock flap-equipped models; the P-51 case differs by **0.153921 N** and **−0.024362 N·m** | 24 component/shared-Dynamics cases, 225 assertions and 15 conditional algebra checks; no physical calibration or ordinary clean-start failure claim |

The [single reproducer](probes/reproduce_sixth_pass.py) rebuilds **442 real dependencies without stubs**, retains unchanged stock inputs and verifies five labeled synthetic files. The [evidence](sixth-pass-evidence.json) contains **11 clean checked invocations**, **two exact expected checked failures**, input/backend identities and independent scalar-oracle output. The expected failures remain failures in their reports; child exit 0 is not treated as successful physics. Four unchanged wind/airship tests contribute **502 checks**. The report records rejected candidates, existing modeling limits, repair options and promotion gates; R4-F02 overlap and all earlier unresolved work retain their separate scope.

The [separate prior-head CI snapshot](sixth-pass-ci-snapshot.json) updates the formerly pending R5 CI: required CI completed with failure and MetalFX source controls passed. Inspected failures include stale rate-derivative provenance, math-wrapper violations and companion-source identity refusal. This focused research run does not close full CI or native/rendered/physical qualification. R6 changes no production law.

## Seventh-pass drone controls, numerical admission and rotor work (A36 R7)

The [drone-focused report](seventh-pass-drones-2026-11-21.md) reviews source `5a93c105be0736d23f52ac9b46812b3a5e358233` and adds **two conditional defects** while preserving distinct evidence for model limits and contract questions:

| Item | Result | Evidence boundary |
| --- | --- | --- |
| **R7-F01** | An imported BETAFLIGHT expo of 200 maps positive half stick to **−75°/s**; the simulated body responds in that direction | Constructed CLI/profile through the real adapter and stock-data Acro session; valid expo controls pass. No conforming firmware dump or completed player import UI claim |
| **R7-F02** | A custom **0.001 Ω** motor passes complete file/session admission, then its normal pad arming tick is rejected by the production policy | Correct rollback; the same frame/held command succeeds with diagnostic 4/8/16 plant pieces. Stock motor passes. Custom session API, not an observed player file-selection route |
| **R7-G01** | A 55° setting applied independently to roll/pitch permits a **70.792520° resultant target**; a stock session reaches 72.422756° transiently | Clarify per-axis versus cone semantics; not a confirmed specified cone violation or actual-attitude safety cap |
| **Existing rotor limitations, stronger evidence** | Accepted stock climb snapshots show a positive rotor-air power port, including **+89.386116 W** after reducing throttle; a constructed near-stop state exposes the relative/air-relative spin distinction | Full body/rotor/motor ledgers close; no spontaneous whole-vehicle energy growth or new duplicate finding count |

The [portable reconstruction](probes/reproduce_seventh_pass.py) uses **459 real dependencies, no stubs**. Nine clean checked invocations cover **80 observation checks**, **184 unchanged baseline checks**, and **17 independent equation/ledger cases**, with zero engine diagnostics and all source bytes unchanged. The [evidence](seventh-pass-evidence.json) retains full logs, hashes and checked outcomes with host-specific invocation metadata minimized. Repairs, alternatives and acceptance gates are documented; R7 makes no production change or performance claim.

R7 also [qualifies R2-F01's reachability](seventh-pass-drones-2026-11-21.md#r2-f01-reachability-correction): the current drone session constructs reference-density weather, so the earlier changing-density arithmetic is a controlled atmosphere counterfactual, not an observed player altitude effect. The [reviewed-head CI snapshot](seventh-pass-ci-snapshot.json) records completed CI failure and successful MetalFX source controls; complete CI, native and physical qualification remain separate.

## Eighth-pass helicopter contact, controls and rotor consistency (A36 R8)

The [helicopter report](eighth-pass-helicopters-2026-11-21.md) reviews `c1eb426900e594c20d095120c149386305afdd4d`, preserving the distinction between the historical playable X-Cell reference and the current HX-700 laboratory/inspector target.

| Item | Evidence and scope |
| --- | --- |
| **R8-F01** — new conditional contact-admission defect | The loader's mass-only skid stability guard omits geometry/inertia. Synthetic wider skids pass full loading and normal pad setup; a decaying coupled contact mode grows by 7.691392 in an accepted reference tick, with a separate 3 m/s wind/normal-start witness and matched stock/fine-step controls. No stock instability or current custom-selection UI is claimed. |
| **R8-G01** — arming contract | Stock scripted tapes pass a premix +0.9° guard while clipped trainer/swash output reaches +1.340338° at rearm after a 25 ms gap. HELI-20 explicitly retains premix for arming; the promised quantity needs a decision. This is not a proven physical hazardous start or a duplicate of R5-F01. |
| **HELI-05/06 evidence upgrades** | Constructed main-rotor tilt changes body work by 168.579 W at unchanged shaft draw; the complete geared kinetic ledger closes. An unsaturated near-zero-thrust tail state reconstructs −2.5 m/s wake and changes fin force by 19%; a separate high-sideslip constructed reset has a matched session stage and accepted tick. These quantify existing approximations, not new duplicate defect counts or energy-creation claims. |

The [portable reproducer](probes/reproduce_eighth_pass.py) reconstructs 438 real dependencies with no stubs. [Retained evidence](eighth-pass-evidence.json) records nine clean checked jobs, 140 observation checks, 276 unchanged helicopter checks and three independent Python oracles; all source bytes remain unchanged. The [CI snapshot](eighth-pass-ci-snapshot.json) returns no PR-triggered runs for this reviewed head; prior required CI remains recorded as failed. No R8 production fix, native/physical qualification or measured optimization gain is claimed. Proposed repairs preserve 240 Hz sampling and the helicopter's existing tick-policy ownership.

## Original evidence

| Artifact | Purpose |
| --- | --- |
| [Audit PDF](originals/OpenRCsimulator-audit-57abea0.pdf) | Nine-page report, derivations, numerical observations and limits |
| [Evidence ZIP](originals/OpenRCsimulator-audit-evidence-57abea0.zip) | Seven checked probes and reports, portable exact-source reproducer, source manifests and CI records |
| [Artifact identity](originals/SHA256SUMS) | Original file SHA-256 digests |

The ZIP contains no repository source files. Supply the original checkout and official Linux x86-64 Godot 4.8-beta2 executable to its reproducer. Four imports and six clean probes passed; the jet probe reproduces a specific expected checked failure. The blimp session uses the disclosed fail-if-used collision stub on an empty-scenery path. No rendered/native/hardware/physical qualification is implied.

## Follow-up status

| Audit ID / owning area | Work and acceptance | Status |
| --- | --- | --- |
| F1 / IAQ, AC-PX | Preserve combined propeller thrust and torque through table construction; qualify interpolation/extrapolation and caps | Implemented and checked for identical propellers at common RPM and inflow; mixed propulsion remains an approximation |
| F2 / IAQ, AC-PX | Keep body drag dimensional area consistent with final biplane/fitted geometry and uniform scaling | Implemented and checked at scales 0.5/1/2, including fitted geometry, later chord edits and legacy receipts |
| F3 / BL-03 | Passive fixed-deflection fin forces over signed flow; retain small-angle slope and quantify full-angle changes | Implemented; 2,160 individual fin cases and crossflow/reverse-flow continuity checked; finite-angle calibration open |
| F4 / BL-05, SF boundary | Depletion ends battery supply; accepted charge bounds, refinement and checkpoint/replay | Implemented with a located event, connection latch and unpowered actuator hold; refinement, rollback and replay checked |
| F5 / IAQ, AC-PX | Escape literal jet percentage; formatted provenance and zero engine diagnostics | Implemented; unchanged complete Phoenix reader test passes |
| F6 / IAQ, AC-PX follow-up | Correct the static propeller figure-of-merit coefficient conversion; independently verify dimensional thrust/power/disk-area ratio | Implemented with a dimensional oracle, explicit derivation-version change and single/multi-propeller admission checks |
| O1 / Creator lifecycle | Retire abandoned candidates while preserving live package owners; sustained memory/setup measurements | Partial: a setup retires the derived candidates it created and its draft does not use (`test_creator_phoenix_readers`); packages of superseded accepted setups stay for undo/reopen; RSS/speedup unmeasured |
| G1 / CI, release | Restore 13 sidecars and complete required CI on the integrated source | Sidecars generated by pinned engine UID allocator; tracked-sidecar check passed, full CI still required |
| G2 / BL-07, SF boundary | Failed preparation preserves the accepted flight, tape and observers | Implemented: the release state is validated on a detached kernel before commit (`test_airship_energy_bounds`) |
| G3 / BL-08, FL/UI | Retained in-flight recorder failure/limit notification and recoverable-prefix handling | Implemented: recorder `ended` signal, in-flight flash and retained HUD log line; failed files keep an inspectable prefix (`test_airship_recorder_notice`) |
| R2-F01 / FPV | Rotor loads follow stage density | Implemented: coefficients at 1.225 kg/m³ scale with ρ/ρref; identity `rotor_density` (`test_mr_rotor_density`). Per R7 the player drone route currently installs only reference density, so this is component consistency; altitude handling is not flight-qualified |
| R2-F02 / FPV | Continuous Angle-mode target | Implemented: heading-free reduced-attitude error, law `openrc-fc-acro-angle-turtle-v3`; singular only exactly inverted (`test_mr_angle_continuity`) |
| R2-I01 / BL | Report delivered bus power | Implemented: `power_w` is terminal power; request, ceiling and limit reported separately |
| R3-F01 / BL | Zero-command pack draw policy | Implemented: non-braking ESC policy, law `airship-kirchhoff-6dof-v3`; regeneration and braking not modeled |
| R3-G01 / RCV | Nitro fuel mass, CG and inertia | Open: needs the tank's full/empty datum and position; no fabricated datum |
| R3-O01 / RCV | Per-tick model/controls copies | Measured, not changed: 5.4 µs of a 9,538 µs reference step (0.06 %); native dispatch shares the adapter boundary |
| R4-F01 / aircraft | Tailless vertical-only wake | Implemented: guarded horizontal-tail lookup in wake and swirl (`test_tailless_vertical_wake`) |
| R4-F02 / aircraft | One physical tail patch per wake load | Implemented: contract refuses undeclared-tail, over-area and overlapping collinear pieces (`test_wake_coverage`) |
| R4-O01 / A6 O5 | Prepared spatial-wind geometry | Open optimization, unchanged; needs invalidation design and target-host profiling |
| R5-F01 / HELI | Trim inside swash feasibility | Implemented: trim joins the pilot axes before mixer/servo limits; GDScript and native (`test_heli_trim_feasibility`); native parity not run locally |
| R5-F02 / FPV race | Angle-projected chord bound | Implemented: path policy `openrc-chord-path-v3` (`test_race_director`) |
| R5-F03 / battery | Pack thermal stiffness at launch | Implemented: cooling mode in the electric step guard (`test_battery_session`) |
| R5-G01 / ground effect | Shared aileron ground effect | Implemented on both paths and native; mirror-bank check compares the bank-induced part (`test_ground_effect_aileron`, `test_ground_effect`) |
| R6-G01 / aircraft | Ct/Cp energy balance | Implemented: `PropellerPowerBound` admission on the runtime law; every stock propeller passes (`test_propeller_power_bound`) |
| R6-G02 / aero | Static versus settled flap wake | Implemented: NAN is the settled wake in the flap composition; GDScript and native (`test_flap_settled_wake`) |
| R7-F01 / FPV rates | BETAFLIGHT expo above 100 reverses partial stick | Implemented: BETAFLIGHT expo domain 0..100, refused per axis (no clipping); stored profiles above 100 are refused on load (`test_mr_rates`) |
| R7-F02 / FPV motor | Motor admitted beyond the 240 Hz step | Implemented: plant refuses h·λ > 0.5 with λ = (1/(R·Kv²) + 2·kQ·Ωmax)/J; stock 0.197, R7 motor 11.85 (`test_mr_motor_step`). Common-mode/contact stiffness is not covered by this necessary bound |
| R7-G01 / FPV Angle | Per-axis or cone tilt limit | Decided: per-axis Euler limits, documented in the controller (full diagonal 70.79° at 55°); no behavior change |
| CI H6 | Bare transcendental calls | Fixed in `hull_contact.gd` and the multirotor session (bit-identical) |

## Extension sequence and gates

1. Restore verification and fix jet diagnostics without weakening gates.
2. Repair Phoenix aggregation/reference-area invariants and version the derivation; qualify old receipt/draft admission and source-matched imported performance cards.
3. Repair blimp passivity/resource boundaries with independent energy checks, timestep refinement and checkpoint/replay; preserve shared-kernel ownership and float64/240 Hz.
4. Bound Creator candidate lifetime and instrument complete setup/memory workloads before claiming optimization gains.
5. Continue physical aerodynamics: coefficient reference conventions, finite-wing/section translation, low-speed control authority, propulsion energy and source-matched flight envelopes. Distinguish a calibrated model from an internally consistent estimate.

Use the [numerical-change checks](../../tools/physics.md#numerical-change-checks), [flight logging workflow](../../FLIGHT-LOGGING.md), [imported-aircraft plan](../../plans/imported-aircraft-quality.md) and [airship plan](../../plans/rc-airship.md). Required CI, actual-native parity/selection where affected, rendered flows, pilot/physical acceptance and target-host performance remain separate gates.

## Implemented invariants and compatibility

### Phoenix propulsion and body drag

The aggregate propeller uses `D_eq = sqrt(N) * D`, preserving total disk area. For identical physical propellers at common RPM and axial inflow, its tables use `J_eq = J / sqrt(N)`, `Ct_eq = Ct / N` and `Cp_eq = Cp / N^(3/2)`. Substitution into `T = rho*n^2*D^4*Ct` and `Q = rho*n^2*D^5*Cp/(2*pi)` gives exactly `N*T` and `N*Q`. The runtime's fixed Ct extrapolation floor is encoded as a flat table tail after the transformed crossing. Tests cover interpolation, extrapolation, an interior Cp minimum and counts 2/4/8/16.

Rotor inertia sums the individual physical rotors before applying the pre-existing explicit-shaft stability floor. Equivalent diameter and inertia still pass through the real aircraft validator: an unsupported large aggregate is refused, not silently clipped. This representation does not establish independent motor dynamics, separated thrust axes, counter-rotation or heterogeneous source propellers. The importer still represents mixed units using the first propeller's properties.

The source body contribution is retained as a dimensional drag area, `Cd_body * A_frontal`, scaled with size squared. The compiler divides it by the current wing area when forming CD0. Changing the wing reference therefore no longer changes the source body's drag force at the same dynamic pressure. Valid legacy converter receipts reconstruct the area from their saved source span and aspect ratio; direct legacy physics blocks lacking that geometry keep their former dimensionless interpretation.

Phoenix derivation version is now **20**. A saved version-19 package identity follows the existing explicit setup-reset path instead of silently acquiring changed physics. New derivations reopen without that reset. The F6 correction intentionally changes some single-propeller power estimates and motor sizing as well as multi-propeller estimates; it is not a bit-preserving data migration.

### Blimp fin work and battery boundary

The fin force separates lift perpendicular to local airflow from crossflow drag along the deflected effective normal and skin drag. For a held deflection, lift does zero work and both drag terms do non-positive work. The swept individual-fin maximum was `-0.021571144267 W`; continuity witnesses crossed the pure-crossflow and reverse-axis seams. Normal-force changes relative to the previous expression were about **-0.131% at 3 degrees** and **-9.433% at 30 degrees** in the reported forward-flow fixture. The larger-angle behavior is intentional and still needs physical calibration.

Depletion is a shared-kernel located event. Trial stages retain the connected moving-side derivative so the root can be located; the committed transition sets SOC and the connection latch to zero together. Accepted states and restored checkpoints enforce the charge/latch domain. Disconnected battery voltage, current, electrical power and motor drive are zero. Propellers retain the existing finite exponential coast estimate. With no separate receiver/BEC source modeled, achieved vector and fin angles hold after disconnection; unpowered blowback is outside this approximation.

The law identity is **`airship-kirchhoff-6dof-v2`** and the continuous layout grows from 11 to 12 entries. The session layout identity also changes. Logs store the depletion event's tick and sub-tick location; verification compares it alongside byte-exact state continuation. Old-law logs/checkpoints are refused by identity instead of being replayed under a different law. No supported native blimp backend exists in the reviewed source, so this change stays in the reference vehicle law and the existing kernel transaction.

The known constant-current event agrees at 240/480/960 Hz to approximately `1e-12 s`. For the coupled battery/body fixture, event-time differences against 960 Hz were `1.1998e-9 s` at 240 Hz and `6.9646e-11 s` at 480 Hz. Additional checks cover crossings near both tick edges, an exactly-once transition, failed-transition rollback, checkpoint continuation, log event omission, and holding nonzero actuator angles against changed commands after cutoff. These are numerical/software checks, not a universal propulsion energy proof.

## Verification record

Candidate checks use the pinned Linux x86-64 Godot **4.8.beta2.official.cafc17a19** (SHA-256 `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`) and the checked runner, which scans engine diagnostics as well as process exit status. The complete Phoenix readers passed **277 checks** at the production **240 Hz** setting in an isolated source/dependency fixture with real preload resources and no stubs. Relevant production and test files were byte-identical to the candidate.

| Unchanged test entrypoint | Passed checks | Covered boundary |
| --- | --- | --- |
| `test_creator_phoenix_readers.gd` | 277 | Converter, package invariants, real electric admission, legacy receipts and landing-gear/start path |
| `test_airship_energy_bounds.gd` | 18 | 2,160 fin cases, event refinement, depletion, rollback, checkpoint/log replay and actuator hold |
| `test_airship_dynamics.gd` | 50 | Existing analytical and behavioral dynamics checks |
| `test_airship_session.gd` | 43 | Complete session, actual field obstacle inventory, wire/beam strikes, terrain contacts and input-tape replay |
| `test_airship_flight_log.gd` | 25 | Complete real-field log test, mid-flight replay, corruption, terminal outcome and restore behavior |

All five completed with **zero failures, engine errors or warnings**. [Qualification record](qualification.json) retains the checked reports, small engine logs, before/after power observations and exact source identities. The [fixture manifest](integration-manifest.json) identifies 432 source/data/resource files and the minimal project settings; 20 unchanged data files preserve the checkout's CRLF bytes and explicitly record the conversion from their LF Git blobs. It also describes reconstruction from the published runtime commit. Generated import/UID cache bytes are outside the fixture's source identity; tracked application UID sidecars pass their separate preflight check.

The initial Phoenix fixture used Godot's 60 Hz default and lacked some scenery resources. Its landing-gear refusal is invalid evidence about the 240 Hz production application. The corrected complete test supersedes those attempts. Earlier adapted blimp session/log checks excluded scenery. The first broader session attempt also lacked parked-aircraft collision metadata and failed; the final 43/25 checks above include it. None of these fixtures constitutes a complete application import, rendered flight, native flight or target-hardware benchmark.

Independent review checked the propeller algebra and runtime floor behavior, dimensional figure of merit, body-area reconstruction, passive fin work, depletion event/accepted-state boundaries and source-matched evidence. No blocking defect was found within the stated scope. Required branch CI and broader application/native/render/physical gates remain separate from that review.

## Remaining work with acceptance criteria

| Item | Next concrete step | Acceptance evidence |
| --- | --- | --- |
| O1 superseded accepted packages | Give derived packages explicit owners (draft, undo history, preview, flight) and retire unowned ones | Repeated setup/scale/restore workload with live-owner assertions, retained-package counts and measured RSS |
| Native and CI | Rebuild and requalify the native kernel for the mirrored edits (slipstream, swirl, aero, helicopter controls, flight session, aircraft data); rebind companion identities; run required CI | Native parity/selection gates and green required CI on the integrated source |
| D11g Stik provenance | Regenerate the three Stik rate-derivative source strings (values are unchanged) together with the pinned aircraft-byte gates | `derive_rate_derivatives.gd --check` clean on main |
| R3-G01 Nitro fuel mass | Measure tank datum, position and full/empty mass, then vary mass/CG/inertia from the shared inventory | Full/half/empty support, weight and replay checks |
| Mixed Phoenix propulsion | Decode each source unit and define the supported aggregation domain | Heterogeneous diameter/pitch/RPM and mixed jet/prop cases, explicit refusal where no supported representation exists |
| Physical aerodynamics | Calibrate imported coefficient references, finite-wing translation and full-angle fin behavior against source-matched observations | Matched aircraft/prop data, compatible recorded command tapes, flight envelope comparisons and pilot acceptance |
| Energy and performance | Bound the complete blimp electrical/mechanical model and measure full Creator workloads | Power-domain admission, explicit stored-energy accounting and real target-host CPU/RAM measurements |

## F6 follow-up: dimensional figure of merit

Independent implementation review found an additional defect in the original [Phoenix power derivation](../../../app/workshop/creator/phoenix/physics.gd): it divided by `sqrt(2/pi)` when converting Ct/Cp to static figure of merit. This finding is additional to the immutable original PDF/ZIP, not a rewritten historical observation.

With `T=rho*n^2*D^4*Ct`, shaft power `P=rho*n^3*D^5*Cp`, disk area `A=pi*D^2/4` and ideal static actuator-disk power `P_ideal=T^(3/2)/sqrt(2*rho*A)`:

\[
FM=P_{ideal}/P=\sqrt{2/\pi}\,C_T^{3/2}/C_P.
\]

The old expression is `pi/2` times this physical ratio. Its nominal 0.8 cap therefore forces the actual ratio down to at most `0.8*2/pi = 0.5092958`, making some estimated props unnecessarily power-hungry. A dimensional example with rho=1.225 kg/m³, n=100 rev/s, D=0.25 m, Ct=0.1 and Cp=0.05361651462 gives physical FM about 0.4705887; the old expression gives about 0.7391990. The existing reader test repeated the incorrect expression, so a coefficient-only regression was not independent.

The correction must intentionally qualify changed single-propeller as well as multi-propeller packages, including motor sizing, admissibility and the 3-weight thrust cap. Its new oracle computes thrust, shaft power and ideal disk power in dimensional quantities. The 0.8 ceiling remains an estimated model constraint, not physical calibration against an actual imported aircraft.

## Further energy-model questions

Battery disconnection alone does not close the blimp's complete electrical/mechanical budget. The existing prescribed motor response does not explicitly fund rotor kinetic energy, and admitted thrust/pitch-speed/shaft-power parameters need a consistency domain: for the simple forward quadratic thrust-speed model, peak useful power is proportional to `T0*pitch_speed*abs(n)^3/4`. Compare that with available shaft power before claiming universal energy closure. Retain finite, explicitly estimated coast behavior while this broader BL power-model qualification remains open.
