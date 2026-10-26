# Dry hull scraping in fields with a configured lake

2026-10-26. The default club field installs a lake context even when the aircraft
is on dry ground. GP-19d refused all scrape observations whenever that context
was present, while accepted audio mode suppressed the old sliding cue. A real
Main-scene dry wingtip brush therefore had friction but no scrape sound request.
The retained baseline reproduces three failures in seven checks.

`HullContact.loads` and `loads_at_properties` now optionally fill a structured
`{available, reason, rows}` collector. The existing force owner's exact terrain
samples qualify the entire batch before any dry row is published. All sampled
branches outside coverage may expose their actual flat-force rows. Any covered
bank/bed/water branch makes the whole batch unavailable, including mixed batches
and the live-mass no-active-point early return. No extra terrain query, force
expression or force accumulation order is introduced. The historical Array
collector retains its behavior. A height-clear fast return may be available and
empty; that is silence, not a claim about geographic coverage.

Session consumes this collector, removes its blanket configured-lake refusal,
and includes lake data in its exact derived-cache key. Public nine-key packets
and seven-key rows, live fuel mass/CG, checkpoint state and material decoration
retain their owners. Contact power is still instantaneous `-Ft dot vt` from the
same computed force, not integrated heat or a speed-based substitute.

Four installed-source suites pass **502 checks** (388 force diagnostics,
56 Session/Main, 36 existing soft contact, 22 water Director), all complete,
warnings-as-errors and zero engine diagnostics. The Session test runs actual
Main default-field wiring: loaded dry brush queues before render, airborne reset
stays silent and a rejected step cannot append audio. Existing survivable belly
slide, propeller strike, hard-impact termination and exclusive water aftermath
checks pass. These tests preserve existing behavior; they do not calibrate it.

The [independent review](review/review.md) adds **43 checks** for constant/live-mass
force bytes, both mixed-point orders, early returns, detached caches, same-clock
lake mutation and changing fuel. Root reconciled its two exact draft hashes
with the promotion manifest; Session's only projection difference is its
production HullContact preload. The producer's 444 draft checks are retained
separately. The independent first run had a wrong completion marker; its failed
runner receipt remains alongside the corrected clean run.

`source/` pins nine selected files, not a complete repository snapshot.
`development/root-promotion.json` pins all four changed paths and their bases.
The gain source includes the separately qualified [unloading correction](../scrape-unloading/README.md).
The prior [native flight capture](../native-continuous-timber/README.md) predates
both corrections. This cohort uses Dummy audio and proves routing/queueing,
not native audibility or human listening. Covered lake scrape acoustics,
advanced contact observations and whole-flight performance remain open.

Reproduce using the checked runner with `res://tests/test_hull_friction_observation.gd`,
`res://tests/test_hull_scrape_session.gd`, `res://tests/test_soft_contacts.gd` and
`res://tests/test_water_director.gd`. Logs keep their original command paths.
`manifest.json` binds retained payloads; `transport.json` verifies exact bytes
through a fresh disposable Git clone with autocrlf, without staging the shared tree.
