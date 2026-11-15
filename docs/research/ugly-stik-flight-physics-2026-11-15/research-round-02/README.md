# Research round 02 — 24 planned investigations, two focused follow-ups

**Date:** 2026-11-15. **Branch:** `audit/ugly-stik-flight-physics-2026-11-15`. **Research baseline:** `08f0c08348395c0d6d9f7e224f66460828f59a7f`. The [24-question plan](research-plan.md) was committed and published as [`973ac3b42708102a6ebc95b64b3e42e688aae573`](https://github.com/bultodepapas/OpenRCsimulator/commit/973ac3b42708102a6ebc95b64b3e42e688aae573) before external investigation. Each question below now has a source-backed decision, code boundary, alternatives and acceptance criteria. Two subsequent questions address uncertainties that the first pass actually exposed.

The package contains **26 investigation reports**, five structured registers with **107 source records / 105 distinct URLs**, a human-readable [source index](source-index.md), an ordered [integration backlog](integration-backlog.md), [research review](research-review.md), [implementation review](implementation-review.md), and [executed verification](verification.md). Sources include original studies, official manuals/API contracts, exact engine implementation, maintainer-owned repositories and bounded developer/forum experience. These counts describe evidence records, not 107 independent experiments or 107 studies of this aircraft.

## What this round changes

Three groups of evidence-tool changes are implemented: interrupted flight-card jobs retain useful logs/receipts; comparisons require meaningful, unambiguous coverage and respect declared failure receipts; runway reports verify matched image bytes and distinguish incomplete/unknown observations from unchanged results. **48 focused Python tests pass**, all **18 original retained audit profiles** pass the generic structure check, and three retained campaigns compare unchanged against themselves at zero tolerance. The independent review identifies no blocker in those targeted closures. These are Python-tool results with synthetic states/profiles/PNGs and a real Python timeout child; no new simulator flight, native rendering, controller, target-hardware or physical-flight qualification is claimed.

The application tree remains `565e4a839e63c1b65064d0da4e6e1366b13ebbc7`. Runtime aircraft equations, stock identities, coefficients and input policy are unchanged in this round. That leaves the physical proposals reviewable without pretending that literature or a software receipt supplies the missing measurements.

## Ordered investigation register

“Prototype” means an actionable design and acceptance experiment exist, but the implementation/measurement has not qualified it. “Use existing” means an existing repository workflow can save work; it does not imply new measurements were taken.

| ID | Investigation and principal decision | Disposition |
| --- | --- | --- |
| R01 | [Input observations](investigations/r01-raw-input-observations.md): establish initial-axis availability and observation ownership; S2-01 narrows the event/poll concern on the default route. | Prototype, then native-device qualification |
| R02 | [Calibration cadence](investigations/r02-calibration-cadence-and-endpoints.md): repeated cached reads are not independent reports; compare explicit endpoint confirmation and report-aware policies. | Prototype against matched traces |
| R03 | [Focus/reconnect identity](investigations/r03-focus-reconnect-and-identity.md): separate selected owner, connection, mapping and focus; qualify queue-origin assumptions. | Prototype within the pinned backend contract |
| R04 | [Latency and feel](investigations/r04-latency-and-control-feel.md): separate raw input-to-marker, command-to-servo and aircraft response; preserve deliberate radio/gamepad shaping. | Use existing marker/replay; measure |
| R05 | [Low-Reynolds evidence](investigations/r05-low-reynolds-airfoils.md): geometry and covered-wing identity precede polar adoption; donor sections are sensitivity references. | Measure and prototype |
| R06 | [Stopped propellers](investigations/r06-stopped-propellers-and-windmilling.md): powered 12×8 data do not close the zero/negative-power domain; repair must include shaft breakaway. | Prototype signed force/torque with S2-02 |
| R07 | [Propwash coupling](investigations/r07-propwash-control-coupling.md): reuse the optional shared-kernel route only with installation geometry and electric admission. | Prototype optional capability |
| R08 | [Motor/ESC/battery](investigations/r08-electric-motor-esc-battery.md): identify actual source, current conventions, brake mode and transient limits. | Bench measurement before parameters |
| R09 | [Glow operating domain](investigations/r09-glow-operating-envelope.md): separate practical RPM, propeller rating, fitted domain and numerical support. | Defer arbitrary clamps; measure installation |
| R10 | [Mass/CG/inertia](investigations/r10-measured-mass-cg-inertia.md): use existing reducers, quantify air-added inertia and systematic error. | Use existing workflow; data adoption pending |
| R11 | [Induced-flow coupling](investigations/r11-induced-flow-spanwise-coupling.md): replace global-speed assumptions only with finite receiver-local behavior and independent checks. | Prototype isolated closure with S2-02 |
| R12 | [Stall/hysteresis/spin](investigations/r12-dynamic-stall-and-spin.md): compare a model hierarchy and withheld maneuvers; no transplanted donor polar or generic B–L fix. | Measure and prototype |
| R13 | [Modal identity](investigations/r13-mode-identification.md): preserve raw spectra, distinguish coupled/block models and mark ambiguous labels. | Offline diagnostic/report revision first |
| R14 | [Trim continuation](investigations/r14-bounded-trim.md): an unsolved point is not proof of no equilibrium; retain bounds, seeds and residuals. | Versioned report semantics, then prototype |
| R15 | [Timing and replay](investigations/r15-fixed-step-and-replay.md): compare identical accepted ticks separately from wall-clock lag and rendered pacing. | Use existing replay; qualify cross-rate workload |
| R16 | [Integrator stages](investigations/r16-integrator-and-actuator-coupling.md): distinguish sampled and continuous states before changing coupling. | Retain current contract; prototype only with evidence |
| R17 | [Ground and landing](investigations/r17-ground-contact-and-landing-evidence.md): Electric statistics, actual adapter clearance and physical gear behavior have distinct gates. | Dedicated statistics candidate, then qualification |
| R18 | [Identification/validation](investigations/r18-system-identification-and-validation.md): constrain input/actuator/mass errors, identify observable parameters and hold out complete maneuvers. | Use existing traces/reducers; acquire independent data |
| R19 | [Interrupted-run evidence](investigations/r19-interrupted-run-evidence.md): preserve both streams, per-job failures, catalog receipts and summary failure status. | Implemented and tested here |
| R20 | [Comparison eligibility](investigations/r20-comparison-eligibility.md): explicit roster/coverage, structured identities and failed-receipt checks. | Implemented and tested here |
| R21 | [Capture provenance](investigations/r21-capture-provenance.md): image integrity, declared context, missing frames and UNKNOWN observation outcomes. | Report fixes implemented; producer provenance/native capture pending |
| R22 | [Profiling opportunities](investigations/r22-profiling-opportunities.md): attribute real costs with the existing diagnostics before optimizing allocations or stages. | Use existing tools; target-hardware measurement |
| R23 | [Reuse and licensing](investigations/r23-reuse-and-licenses.md): choose specific offline tools before adding runtime dependencies; record exact distribution terms. | Reuse ideas/local tools; external adoption deferred |
| R24 | [Optimization experiments](investigations/r24-benchmark-evidence.md): repeated matched runs, actual 1080p workload, observer overhead and uncertainty. | Measurement protocol ready; no speedup claimed |

## Second round: questions revealed by the evidence

### S2-01 — Exact input backend

The [pinned-backend investigation](second-round/s2-01-pinned-input-backend.md) retrieved Godot commit `cafc17a192acf67903910a68aeb3c076c0907a4b`, rather than assuming current documentation described that binary. The getter reads Godot's event-fed cache; the cache is set before the corresponding motion event is dispatched. Ordinary OpenRC flight disables accumulation. Thus the earlier injected disagreement is a valid replaceable-reader counterexample, but has not been shown on that default engine route.

The vendored SDL also has a concrete initial-axis path that suppresses motion until activity for some nonvirtual axes. Mapping removal, Godot slot reuse and focus flushing narrow which queued-event hypotheses are plausible. The version header says SDL 3.4.16 while the same commit's inventory says 3.4.12; the source discrepancy is not a separately measured binary version. The report preserves backend/device exceptions and the remaining physical-device tests. R01–R03 have been reconciled with these findings.

### S2-02 — Concrete physics prototype contracts

The [physics-contract investigation](second-round/s2-02-physics-prototype-contracts.md) provides independent numerical fixtures for force/torque signs, passive power, friction hold/breakaway, free-body rotor coupling, finite-bus power accounting and a two-receiver induced-flow solve. It identifies an integration dependency: an electric stopped-propeller change must revisit the flight session's exact-rest breakaway branch, not only replace the propeller map. The numbers are explicitly synthetic and algebraically checked; they are not measured Stik parameters or executed simulator acceptance tests.

## Engineering conclusions

The most valuable next step is to constrain what reaches the aircraft model before tuning what the aircraft does. A delayed/incorrect control command, estimated actuator response or uncertain inertia can masquerade as an aerodynamic defect. Conversely, complete replay and plausible animation do not establish target-aircraft realism. The [integration backlog](integration-backlog.md) defines scoped work items and what would close each one.

The original catalog conclusion still stands at this baseline: Basic and Electric are the two stock Stiks; finite-glow variants have technical/research and compatibility uses. This round supplies no basis for deleting those identities. Cross-aircraft differences remain useful controls—for example, an Extra's optional wash versus absent Stik wash—but are not interchangeable aerodynamic truth. See the [original fleet comparison](../fleet-comparison.md) and [variant route audit](../variants-and-routes.md).

No universal “better feel” constant emerges from the research. The useful deliverable is a narrower, testable set of hypotheses, stronger tools for judging them, and implementation boundaries that protect existing behavior while evidence is acquired.
