# RCV-41 — Identity verification CPU optimization

2026-10-15. Work in progress. Owner: RC ground-vehicle track.

## Plan and experiment gates

1. Measure the remaining RCV-40 costs and compare file hashing APIs, full-content digest reuse and native hexadecimal validation.
2. Preserve file reads on every artifact check. Bound any cached bytes, compare full contents, retain remap fallback and malformed-input rejection. Reject optimizations that rely only on path, timestamp or size.
3. Check exact artifact identities through mutation, deletion, empty/large files and remap cases; check digest types, signs and Unicode. Parse drafts outside `app/`.
4. Compare complete sessions using alternating baseline/candidate ticks and exact states, telemetry, tapes and checkpoints. Independently verify baseline/candidate replay; retain changed source/solver identities.
5. Integrate only measured wins, run relevant identity/session/native regressions, then replace this plan with the accepted evidence and remaining limits.

The [exploration receipt](exploration.json) compares five repeated batches on the production source files. Larger buffered hash reads alone did not show a consistent benefit and are not selected. Full-content comparison avoids repeated SHA computation while still rereading every byte. Digest validation can use Godot's native ASCII hexadecimal check if optional signs are explicitly rejected. Deep-copy removal and control-tape append changes are deferred: their smaller potential benefit would add ownership and serialization risk to this phase.
