# GP-14 — accident observation primitive validation

2026-10-26. The statistics adapter now checks the accident observation's schema
type before comparing its value. Malformed fields refuse cleanly; valid receipts
retain exact bytes and remain detached from their source. No physics, event
classification, packet version or supported source contract changes.

The retained `before` reproduction logs seven engine errors and one failed
assertion: several Variant types cannot be compared to a String, while StringName
was implicitly accepted. The first `main` receipt is rejected because its expected
completion count was incorrect; it is not a passing receipt. The corrected
production run passes 68 accident checks, with 135 shared-event and 33 real-session
checks also passing: **236 checks, zero engine diagnostics**. Thirteen checks were
added to the existing accident suite. Earlier evidence cohorts are unchanged.

`manifest.json` hashes the original sources, reproducer, selected current adapter
and test sources, and all five checked-runner reports/logs. This is software input
validation and observer regression evidence, not a full application snapshot,
physical validation, native audio or performance qualification.
