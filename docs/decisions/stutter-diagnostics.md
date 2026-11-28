# Stutter evidence capture

Scope: the decisions, alternatives and evidence behind stutter evidence capture. These records retain the context of each choice; linked guides and the [current roadmap](../../ROADMAP.md) own implemented behavior and remaining work. [Decision index](../DECISIONS.md).

## Preserve stutter evidence before extending attribution

**PT1h-R15 / S0, 2026-11-19; planning direction.** Extend the existing bounded
callback recorder and client exporter. Preserve its live detector policy and
metric formulas; collect one owned incident with explicit lead-up/recovery and
coverage before adding continuous streaming or native instrumentation. Periodic
engine maxima, last-read GPU values and physics catch-up are contextual evidence,
not automatic CPU/GPU cause labels. Keep runtime identity separate from client
checkout identity, and retain independent clock domains until measured alignment
is available. GOD TEST owns campaign comparisons; platform profilers remain optional.
The [24 investigations](../research/release-readiness/PT1h-R15/research-2026-11-19.md)
justify this sequence and its deferred alternatives. The [active plan](../plans/stutter-diagnostics.md)
owns pending S1–S7 work. This decision adds no runtime feature or performance qualification.

**PT1h-R15-S3a, 2026-11-19; offline implementation.** Extend existing debug captures
and GOD TEST phase reports with observed slow episodes/time, without another recorder
or runtime instrumentation. Preserve original debug flags and mark disagreement;
window-edge episodes have unknown boundaries. GOD TEST reduces verified phase
samples and cannot substitute zero for a missing measurement. The three capture
formats retain their different thresholds, completion rules and clocks; future
attachment adapters must preserve originals and prove any joins. The
[tool integration evidence](../research/release-readiness/PT1h-R15/tools-integration-2026-11-19.md)
records the eight follow-up investigations and software-only verification.

**GOD-12-R1 / GOD-13-R1, 2026-11-20; source/debug campaign.** The three-aircraft
runway/menu tour reuses GOD TEST, the continuous frame watcher and the existing
process sampler. A position-based lap receipt establishes the flown circuit;
heading rotation alone does not. Passive device-wide GPU observations extend
capability reporting without claiming per-frame attribution or automatic rendering
device identification. Completion, raw-data integrity, monitoring availability and
performance screening remain separate. Resume preserves every planned slot and
requires the same retained source, engine, observers and host/boot identity.
macOS uses a verified private launch copy whose sole project change is a unique
application name, because its user-data path cannot use the Linux profile redirect.
Startup refuses an explicitly requested benchmark before normal profile access
when that isolation cannot be established. The [operating contract](../../tools/godtest/PERFORMANCE_TOUR.md)
owns commands and capabilities; the [GOD TEST ledger](../plans/god-test.md#13-execution-steps-and-evidence-ledger)
keeps real-hardware qualification open.

**GOD-12-R2, 2026-11-20; planned scenic/crash sequence.** The next three-aircraft
tour starts on the runway, climbs low, turns right past the club scenery and rural
house, completes the declared circuit count, then performs a horizontal roll and
an intentional terminal aircraft impact. Home and Pause navigation exercise panel
responsiveness without changing settings; aircraft-preview selection is the explicit
exception inside the isolated profile. Preserve impact, aftermath and accident-report
observations before returning Home. Expected aircraft accident, application completion
and performance remain separate outcomes; an app failure cannot satisfy the crash
phase. All three aircraft need admitted takeoff/roll profiles. This changes the
planned workload, not the implemented V1 command or its historical evidence; the
[revised GOD TEST contract](../plans/god-test.md#4a-planned-scenic-and-crash-tour) owns
route details and acceptance work.

**GOD-12-R3 / GOD-13-R2, 2026-11-20; independent audit.** Requested rendered
coverage must fail closed when drawing proof is missing; it cannot be downgraded
to successful headless execution. Independent coverage receipts, per-action settings
invariants and a terminal report bound to the accepted impact are required for the
revised tour. Preserve clock/monitoring uncertainty, sampled-device association,
failed attempts and absolute targets separately from collection success. Qualification
requires a resolved profile, admitted full-campaign resources and observer/host
evidence; documentation cannot close unimplemented guards. The
[source audit](../research/god-test/2026-11-20-plan-audit.md) records counterexamples;
the [GOD TEST plan](../plans/god-test.md) owns corrections and remaining acceptance.

**GOD-12-R2f/g / GOD-13-R2, 2026-11-21; implemented measurement foundation.**
Rebuild acceptance from raw observations and the owning runner's independent
timestamps, rather than treating summary labels as proof. An original graphics
request cannot become a successful headless run. Legacy evidence without newly
required owner receipts remains readable but cannot regain complete monitoring.
Local simulation pace uses verified ticks and supported fixed windows; omitted
tails remain inconclusive rather than receiving a positive target. Automatic
managed submission reserves the full expanded roster, while an execution lease
is explicitly not an end-to-end completion guarantee. This is intentionally
conservative: unresolved coverage preserves useful observations and blocks the
stronger claim. The [implementation evidence](../research/god-test/2026-11-21-measurement-hardening.md)
owns exact checks and limits; target-hardware and scenic/crash acceptance remain
with the existing plan. Revisit support thresholds only through a versioned,
predeclared protocol, not after seeing a candidate's results.

**PT1h-R15-S1a/S2a, 2026-11-19; automatic session watch.** Replace the planned
one-shot collector and two-snapshot union with a bounded multi-incident client
watch. It reads every new row through cheap passive `since`/`lean` polls guarded by
epoch and launch identity, and evaluates triggers on raw intervals client-side,
because bridge budget flags cannot see drops above the target and changing the
target resets other clients. Incidents keep the client rows plus one capped v1
snapshot; a full-ring fetch costs about 51 ms on the game thread and would cause
the stall it reports. A freeze is a main-thread poll unanswered while the network
thread's `ping` answers. Statistics stay per epoch segment and route.
[Evidence and audit](../research/release-readiness/PT1h-R15/watch-2026-11-19.md).
