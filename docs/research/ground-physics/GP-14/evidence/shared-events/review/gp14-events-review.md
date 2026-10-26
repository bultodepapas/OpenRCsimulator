# GP-14 event review

2026-10-26. Independent read-only review of
`tmp/gp14-events-draft/{flight_event,detector,service,test}.gd`, then focused review
of the promoted fixes in `app/statistics/detector.gd` and
`app/tests/test_ground_flight_events.gd`. No event runtime files edited by reviewer.

Two P2 findings were sent to root:

- A newly accepted terminal recontact returned before contact-edge processing,
  omitting BOUNCE or the first actual TOUCHDOWN of an already-open episode.
- V3 restore admitted impossible hop duration/tick ordering and inconsistent
  known/support flags, allowing fabricated timing evidence after restore.

Root's promoted fix processes support edges once for new consecutive valid terminal
endpoints, but not invalid/discontinuous or duplicate-tick guard observations.
Accident escalation still proceeds independently. V3 validation now bounds hop time
by accumulated clock (with floating-point allowance), requires hop start at/after
episode start, and rejects supported flags without known/contact-seen history.
Focused source review confirms these changes address the reported cases; root's
tests explicitly cover terminal bounce, first touchdown, invalid and same-tick
guards. Root reports 88 event checks and 33 real-session bus checks passing;
reviewer did not independently rerun those suites.

No duplicate M7/landing metric path was found: semantic events share the existing
classifier and do not increment metrics separately. Service compact detail has both
128-entry and metadata byte bounds; overflow does not suppress subscriber events.
Recursive read-only batches protect later listeners, and record replacement preserves
background snapshot copy-on-write behavior. V1/v2 snapshot migration retains their
historical coverage without inventing prior semantic edges. COMPONENT_DAMAGE and
GEAR_FAILURE remain reserved vocabulary without emitters. Comprehensive physical
event evidence and durable accident archive remain outside this slice.

The later fleet-profile-only regression suite passes 111/111 against the promoted
detector (`tmp/gp14-x8-checks/main/godot-lxa57g5p/report.json`).
