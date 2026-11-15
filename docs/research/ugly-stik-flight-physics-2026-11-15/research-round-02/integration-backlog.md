# Ordered integration backlog

This is an implementation-ready audit backlog, not a claim that the remaining proposals have shipped. Each item names the producer/consumer boundary, a useful first increment, the evidence required for acceptance and a decision to avoid until that evidence exists. References point to the completed investigations and the retained earlier audit. Owners are engineering roles, not assignments to specific people.

The [five Stik foundation plans](../../../plans/stik-foundations/README.md) provide the next scoped implementation sequence and a mapping back to these items. This backlog retains the original research handoff; the plans use existing track owners and do not duplicate their runtime status.

## Delivered in this branch

| Work item | Changed boundary | Result and limits |
| --- | --- | --- |
| E01 — Failure capture | `research/flight-test/run.py`, shared `profile_io.py`, tests and operating README | Separately captured timeout streams survive; expected launch/profile errors become per-job receipts; catalog discovery has a failure receipt; malformed summary reduction is recorded without publishing a partial summary. Filesystem failure/forced termination cannot be guaranteed durable. |
| E02 — Comparison eligibility | `research/flight-test/compare.py`, shared profile reader and tests | Union aircraft roster by default; explicit baseline scope; nonempty shared coverage; typed field identities; declared receipt/profile consistency; finite tolerances. Legacy profile-only results remain visibly unverified. Exit 2 marks ineligible evidence, exit 1 requested differences, exit 0 eligible completion. |
| E03 — Capture/report integrity | `tools/scenery/scenario_report.py`, tests and README | Frame coverage and context are explicit; matched image hashes are verified; missing evidence is unknown/error. New sync rows count observations and distinguish UNKNOWN from FAIL; old complete receipts retain declared outcomes with coverage unverified. Native producer identity and full schedule qualification remain open. |

All delivered changes concern evidence production/reduction. [Verification](verification.md) records 48 focused Python tests and compatibility against retained profiles; the [independent implementation review](implementation-review.md) bounds the conclusions.

## Next software increments

### I01 — Qualify raw-radio initial values and recovery ownership

**Owner:** input/session. **Depends on:** [R01](investigations/r01-raw-input-observations.md), [R03](investigations/r03-focus-reconnect-and-identity.md), [S2-01](second-round/s2-01-pinned-input-backend.md).

Use the pinned engine facts to define an observation capability: value, initial availability if available, selected role/connection/mapping, focus state and what the timestamp actually measures. Godot's cached float is not an independent hardware report. Start with diagnostic traces and explicit unknowns for raw devices; preserve the separately verified gamepad route. A generation stamped at application dispatch must not be described as proof of backend event origin. Avoid requiring arbitrary movement of every held-at-connect axis until the user workflow and device behavior are qualified.

**Acceptance:** direct and managed session paths; offset centers; nonzero controls held before connect; low/high throttle and explicit Continue; same slot/new device; mapping changes; background events, focus flush and recovery; two similar devices; sleep/wake; quiet controls. Record exact OS/backend/device/firmware and independent physical motion. Retain the existing injected callback disagreement as a seam test, without asserting it occurs in ordinary default engine ordering. This work can implement a qualified subset; it cannot manufacture a universal heartbeat.

### I02 — Replace poll-count endpoint evidence

**Owner:** controller calibration/UI. **Depends on:** I01's observation semantics and [R02](investigations/r02-calibration-cadence-and-endpoints.md).

Prototype explicit held-end confirmation and report-aware endpoint candidates on the same trace corpus. Keep center/low return, reversal and asymmetric-travel handling, compatible AUX merge, draft isolation and Save/cancel semantics. A percentile or median alone must not be advertised as independent sample evidence. Retain a clear inconclusive outcome rather than silently widening a range from a cached spike.

**Acceptance:** the previous single retained outlier repeated over polls no longer permanently reduces the known real travel; a legitimate held endpoint still calibrates. Exercise jitter, slow/bursty reports, short dwells, simultaneous mixes, missing axes, persistence rejection and reconnect during calibration. Compare final normalization, not wizard completion alone. Parameter thresholds require trace-based justification.

### I03 — Make card horizons and solver outcomes explicit

**Owner:** flight-test card and consumers. **Depends on:** [earlier horizon reproduction](../follow-up-01/evidence-contracts-and-failure-paths.md), [R13](investigations/r13-mode-identification.md), [R14](investigations/r14-bounded-trim.md), [R20](investigations/r20-comparison-eligibility.md).

This is the next bounded evidence improvement after the Python fixes. Add requested/observed duration and termination cause to maneuvers; a requested 10/20/30-second sample unavailable after early termination remains unavailable. Change misleading `first_untrimmable` semantics to a versioned unsolved/bound/residual report. Preserve raw modal roots, derivative/model assumptions, complex-pair periods and explicit ambiguous labels. Do not silently repurpose the old period or maximum-speed fields.

**Acceptance:** version the card, retain old baselines, and test a genuinely completed case plus the prior high-starting-altitude early-floor counterexample. Verify consumers cannot turn a terminal value into a future-time measurement. Recheck modal cases around the FS-64V pair transition and the local full-throttle trim point with named assumptions; do not call them physical instability or global maximum speed. Solver replacement is a separate prototype, not necessary to improve reporting.

### I04 — Record accepted source identity in native runway captures

**Owner:** scenery fixture/session integration. **Depends on:** [R21](investigations/r21-capture-provenance.md).

Extend the producer from the accepted live session: aircraft input-byte identity, accepted power-source mode, engine/code identity, capture dimensions and versioned expected frame schedule. The current schedule has four full-schedule cameras plus three closeups; a blanket five-by-twelve expectation is wrong. A capture in ideal-electric mode must not stand in for normal finite-pack Home flight. Read actual accepted identities, never substitute today's catalog/file bytes for a previous run.

**Acceptance:** same accepted inputs repeat on the supported native capture path; changed aircraft bytes/source mode/settings are visible; omitted or duplicated schedule entries cannot count as complete. Compare native pack and ideal captures deliberately. Preserve legacy manifests as unknown. Existing 1280×720 fixture behavior does not itself qualify target-hardware 1080p performance; qualify a suitable actual-1080p path separately.

### I05 — Install the dedicated Electric landing-statistics candidate

**Owner:** statistics and fixed-wing adapter. **Depends on:** [R17](investigations/r17-ground-contact-and-landing-evidence.md), [prepared candidate](../follow-up-01/electric-integration-plan.md).

Use Electric-specific gear points/roles and accepted identities; do not alias the Basic row or weaken geometry tolerance. The retained 30-check synthetic candidate already reduces setup work, but remains uninstalled and does not establish actual adapter clearance or UI lifecycle. Cover both ideal and finite-pack source acceptance deliberately.

**Acceptance:** actual adapter samples just below/above clearance, sustained takeoff, touchdown and stop, touch-and-go, bounce/rearm, crash and unreviewed geometry, then persisted/reloaded statistics and UI. Unsupported history remains unknown; do not award retrospective success. Physical wheel/contact realism is a distinct experiment.

## Physics prototypes and measurements

### I06 — Measure the actual installation and propagate uncertainty

**Owner:** aircraft/validation. **Depends on:** [R04](investigations/r04-latency-and-control-feel.md), [R08](investigations/r08-electric-motor-esc-battery.md), [R09](investigations/r09-glow-operating-envelope.md), [R10](investigations/r10-measured-mass-cg-inertia.md), [R18](investigations/r18-system-identification-and-validation.md).

Reuse existing weighing, inertia and positive-powered propulsion reducers. Record physical build, battery/fuel state, installed throws/linkage, loaded servo time, winding/current conventions, propeller identity, ESC firmware/brake settings and sensor clocks. Quantify in-air swing corrections and systematic errors rather than promoting the reducer's output directly to rigid-body truth. Separate manufacturer practical operating ranges from actual measured installation maps and numerical support limits.

**Acceptance:** repeated raw observations with uncertainty, valid mass/inertia tensor and coordinate conversion, held-out component runs, and source generator provenance. Change generated data only through its owner after these records exist. Until then, the virtual ballast and estimated actuator/propulsion parameters remain labeled estimates.

### I07 — Add an opt-in signed propeller and complete breakaway path

**Owner:** shared propulsion/session. **Depends on:** I06 and [R06](investigations/r06-stopped-propellers-and-windmilling.md), [S2-02](second-round/s2-02-physics-prototype-contracts.md).

Select measured signed surfaces or an explicitly bounded blade-element candidate. Return coherent axial force and aerodynamic shaft torque near stop; coordinate `propulsion.gd`, electric exact-rest friction, coupled rotor/body equations, ground-source friction and stop events. A high-advance-ratio table row cannot alone define `n=0`, and the available powered UIUC 12×8 campaign does not supply negative-power data. Brake/coast/regeneration and unsupported reverse flow are explicit domains.

**Acceptance:** the synthetic sign/power/hold/breakaway examples in S2-02; finite limits and declared continuity; consistent momentum and stored-energy accounting; stop/restart events and step refinement; unchanged old-law replay; then independent installed propeller/glide observations. Any stopped phase-average law must distinguish locked-blade azimuth effects where relevant. No arbitrary drag constant or coefficient transplant closes this ticket.

### I08 — Correct the isolated induced-flow closure before expanding it

**Owner:** aerodynamics/shared model. **Depends on:** [R11](investigations/r11-induced-flow-spanwise-coupling.md), [S2-02](second-round/s2-02-physics-prototype-contracts.md).

Build a receiver-local attached-flow prototype against the supplied two-strip algebra and a separately configured lifting-line/VLM reference. The current maximum 3D speed gives a cosine weight under uniform sideslip, but a direct division by a stagnating receiver creates another failure. Keep the isolated 2D closure assertion separate from real 3D yaw physics. Coordinate local/global blending, induced drag and tail wake so the replacement does not double count.

**Acceptance:** uniform and unequal local speeds, mirror/rate gradients, nearly zero/reversed receiver flow, density/speed scaling, finite force limits, span/time refinement without refitting, declared attached-domain limits and stage/replay identities. Measure whole-flight cost and held-out forces/moments before claiming realism or performance improvement.

### I09 — Introduce Stik wash through the existing optional capability

**Owner:** aircraft data admission and shared aero. **Depends on:** I06/I07 and [R07](investigations/r07-propwash-control-coupling.md).

Survey hub/axis and tail geometry, model partial immersion, and admit the optional capability for electric data through the strict parser. Reuse stage-local thrust/torque and the existing washed-minus-unwashed tail calculation. Keep wing/aileron wash a separate extension. Estimated geometry can support an experimental candidate, not calibrated stock control authority.

**Acceptance:** absent option leaves the old path unchanged; signed control response, wash-edge continuity, decay and near-zero-thrust behavior; no double counting of tail load, shaft reaction or gyro; static and flying powered/unpowered controls against independent measurements. Extra is a useful capability control, not donor Stik data.

### I10 — Fit aerodynamics only after the preceding uncertainties are bounded

**Owner:** aircraft validation/research. **Depends on:** I01/I02/I06 and [R05](investigations/r05-low-reynolds-airfoils.md), [R12](investigations/r12-dynamic-stall-and-spin.md), [R18](investigations/r18-system-identification-and-validation.md).

Confirm actual covered-wing geometry and surface state, then compare relevant section data in the correct Reynolds range. Test static and stateful separation candidates in increasing complexity. Hold out entire flights/conditions/directions, not adjacent time samples used for fitting. Require informative inputs and parameter-conditioning checks; a good fit must not compensate an unmeasured actuator lag or CG. The original discrete B–L label alone is not an implementation choice; inspect the actual upstream option and parameter domain.

**Acceptance:** independent static/control/moment evidence, positive and negative maneuvers at several speeds/power levels, uncertainty and residual histories, equilibrium/reversal/zero-speed limits, coupled stall/spin/recovery, and a blinded or counterbalanced pilot-feel evaluation as a separate subjective outcome.

## Performance and reuse

### I11 — One attributed optimization, measured in complete flight

**Owner:** runtime/performance. **Depends on:** [R15](investigations/r15-fixed-step-and-replay.md), [R16](investigations/r16-integrator-and-actuator-coupling.md), [R22](investigations/r22-profiling-opportunities.md), [R24](investigations/r24-benchmark-evidence.md).

Use the current debug/frame/resource/Perfetto tools before creating another wrapper. Find whether input dictionaries, stage temporaries, observers, rendering or loading actually dominate. Use a fixed accepted command tape and named hardware, actual 1920×1080 workload, balanced repeated runs, warmup and observer-off controls. The existing GOD TEST scaffold does not yet automatically supply every fixed-tape rendered pairing or statistical promotion gate.

**Acceptance:** located cost and practical improvement with uncertainty; no unacceptable tail latency, memory, quality or failure-detection regression; same-law replay preserved. If arithmetic order or sampled/continuous coupling changes, evaluate the changed numerical law separately. Defer a kernel rewrite, dropped validation or lower tick rate merely to improve a microbenchmark.

### I12 — Select a specific offline tool before adopting a dependency

**Owner:** tooling/maintainer. **Depends on:** [R23](investigations/r23-reuse-and-licenses.md).

SciPy/LAPACK can cross-check saved matrices and bounded solves; AVL/VortexLattice/AeroSandbox may help compare attached-flow geometry; JSBSim can provide an independently configured model comparison; OpenFAST/QBlade can inform particular wake/unsteady hypotheses. Existing Perfetto export is already integrated. Match the question and assumptions, pin exact code/binaries/data, and inspect the selected distribution's notices/dependencies. A project-level license is not a license for every aircraft asset or dataset.

**Acceptance:** a documented gap the current tools cannot answer, independent inputs and frame/unit conversion, useful disagreement analysis, exact provenance and terms, and a maintainer for future updates. Runtime adoption additionally needs all supported platforms, float64/shared-model/replay compatibility and a measured benefit. No external dependency is added by this research round.
