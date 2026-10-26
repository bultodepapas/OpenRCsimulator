# GP-16c / GP-14 — accepted component-failure events

2026-10-26. The qualified attached-support failure now reaches the existing
classifier and shared service bus. This is a bounded synthetic owner integration;
**stock FlightSession has no damage producer installed**. No contact-v1 packet,
Simulation kernel, force law, geometry or stock admission changed.

## Contract

`AircraftGroundDamage.accepted_observation` validates committed modes, first-failure
clock, losses, component/support bindings, prepared provenance and exact raw source
IDs, then returns a detached eight-key optional observation. It evaluates no
forces. A configured owner validates binding/actual transition batches; the fixture
reuses a detached valid empty packet between events rather than rebuilding
profiles every physics sample. No production performance qualification is claimed.

The adapter pins response/local-generation identity and checks the accepted tick.
Absent producers preserve the exact old sample bytes. The existing Detector
stages the complete batch until sample/continuity admission. Its existing
`_record_accident` alone opens the nonterminal accident and CRASH/M7 latch; each
newly failed component emits COMPONENT_DAMAGE and GEAR_FAILURE with the same
source evidence. Later components share the accident without another CRASH;
terminal escalation retains one M7. Invalid samples/packets, stale identities,
fractional/nonfinite ticks and late kernel refusal cannot leak failure attribution.

FlightEvent v1 construction/history remain unchanged. V2 is restricted to the
qualified failure pair and adds a closed physical_evidence object plus five SI
force/potential/loss measurements. Material remains unavailable/empty; severity
and root cause remain unknown. Observed capacity exceedance is not pilot intent
or a fabricated mechanical cause. Qualified CRASH coverage links observed source
IDs rather than claiming damage_unobserved. Rules v3 records the wider observed
M7 scope without retallying earlier records. No new classifier, timer or durable
deduplication latch was introduced; snapshot v1–v3 remain readable.

Service retains the same recursively frozen bus, 128-event/64KiB metadata bounds
and noncredit checkpoint branch. A bounded first-failure summary fits on the
existing M7 record before a flight timeline exists. The full later/preflight
per-accident archive remains open. General cosmetic damage alone is not an
implemented crash trigger.

## Actual physics and source IDs

[accepted-batches.json](current/final/accepted-batches.json) preserves the final
actual raw kernel events and complete shared packets:

- Light 1 kg at 0.8 m/s: no failure or shared accident.
- Heavy 4 kg at 0.8 m/s: one failure at tick 5, 104.339218812099 N against 100 N;
  loss 0.467105742877 J, continued accepted motion.
- Hard 1 kg at 2 m/s: one failure at tick 1, 127.179891862244 N against 100 N;
  loss 0.113686860915 J, continued accepted motion.
- Asymmetric first kernel boundary: left-component failure commits and publishes
  one pair. The next rolled state refuses the current aligned scalar capacity
  domain with no additional shared event. This is **not** qualified asymmetric
  dynamic continuation or a wrench/shear model.

The final suite explicitly compares shared source IDs, accepted ticks and loss
values with actual kernel records. Healthy rewind repeats the same physical ID
and is suppressed by the existing noncredit service branch. Failed-state
continuation emits no repeated physical failure. Late final-projection refusal
publishes nothing. Boundary sampling remains explicitly different from a
whole-interval overload maximum; no stock calibration or physical realism claim.

## Checks and source revisions

**332 affected checks ran on final source.** The narrow CRASH coverage correction
followed a complete earlier production cohort. Its **616 other regression checks**
are retained with that preceding source snapshot. The selected total is **948**;
this is not an all-final-source broad-suite claim. All accepted receipts are
complete, use exact completion markers/warnings-as-errors and have zero diagnostics.

| Suite | Checks | Source revision / receipt |
| --- | ---: | --- |
| Physical kernel → shared events | 197 | [final](current/final/checks/integration/report.json) |
| Existing semantic events | 135 | [final](current/final/checks/events/report.json) |
| Attached response/kernel drops | 125 | [preceding](current/preceding/checks/response/report.json) |
| Gear damage arithmetic | 113 | [preceding](current/preceding/checks/gear/report.json) |
| Survivable accidents | 68 | [preceding](current/preceding/checks/accidents/report.json) |
| Fleet statistics detector | 111 | [preceding](current/preceding/checks/detector/report.json) |
| Statistics lifecycle | 51 | [preceding](current/preceding/checks/lifecycle/report.json) |
| Actual legacy Session observers | 33 | [preceding](current/preceding/checks/session/report.json) |
| Counter resets | 48 | [preceding](current/preceding/checks/resets/report.json) |
| Store | 49 | [preceding](current/preceding/checks/store/report.json) |
| Background writer | 18 | [preceding](current/preceding/checks/writer/report.json) |

The original 43-check baseline demonstrates physical transport and the missing
shared bridge, including the old direct-only asymmetric check. An early 155-check
draft is retained only for its original v1 sentinel capture; it predates semantic
review fixes and is not final acceptance. Rejected receipts retain the inferred
test-type parse error, a wrongly sized metadata-limit fixture (63000 bytes still
left room; corrected to 65000), and a mistyped completion marker. Exact mutable
executed rejected-draft source was not retained; those runs are not relabeled as
passing. Pre-coverage 194/135 production receipts are separate and not double-counted.

`manifest.json` pins 84 artifacts, including nine original, nine preceding and nine
final selected source files, actual observations/batches and original receipts.
Supporting tests are copied at retention; not every loaded dependency is frozen.
Earlier immutable cohorts remain unchanged. Headless/Dummy checks do not establish
native audio, target-host performance, stock activation or complete GP-14/16.

Frozen compatibility SHA-256:

- V1 semantic payload: `146fb741db76bce8f3e5db66a6551d88b4ff8722a382e662e1ba11d1fde39830`
- Absent-producer sample: `15622bd38ecd3f7bb101b0aa8d5d0c1e220a5da89836b2ab47c04072cb6488f1`
