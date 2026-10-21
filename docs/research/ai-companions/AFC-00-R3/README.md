# AFC-00-R3 — Reachable-clear fast-path equivalence

This receipt evaluates the research-only early return in
`research/ai-companions/performance/reachable_clear_candidate.gd`. The production
pilot remains pinned to SHA-256
`363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed`; the candidate
was injected only into detached test fixtures, and the accepted profile identity
remained on production.

The static differential passed 11 checks over 1,280 command/state pairs with no
failures. It found 130 clear comparisons and 766 held-maneuver comparisons, with
1,430 pure bank-score evaluations avoided. The real-session fixture passed 24
checks over 480 accepted 240 Hz ticks. Baseline and candidate player, companion,
control, controller-decision, and manager frames matched byte for byte at every
tick; 240 clear decisions avoided 2,640 score calls. The common input tape is
SHA-256 `dfd02e4f6bcf5f1c379e456c144a3d2d72c8cb7f8b3f47a94a3e0f79f8fcfadf`.

All six baseline/candidate ORFL streams were then replayed exactly. Each replay
was complete, reported `solver_changed: false`, and covered 481 rows (ticks 0–480).
Pairwise player and companion CSV comparisons each covered all 481 rows and found
zero position, velocity, attitude, or angular-rate differences. The raw D: paths,
SHA-256 hashes, per-stream replay reports, paired comparisons, source manifest,
and checked-runner logs are indexed in [verification.json](verification.json).

The source audit binds this result to the pre-fix fresh clone at commit
`16a6d9566e1fac0ca7ac96ce6e085beb9fe2c643`: all 428 paths in the flight report's
source/data manifest matched the clone bytes. A later visual-only `mountains.json`
line-ending repair is retained separately at
`D:/OpenRCsimulator-AFC-work/evidence/fresh-validation/mountains-before-attributes.json`;
the receipt records that pre-fix capture and the `.gitattributes` reconstruction
patch. The repair did not change simulator physics, but the checks here remain
bound to the recorded pre-fix source map.

The first flight-harness attempt failed two ORFL checks because it read the
footer's final tick from the wrong report level. The harness was corrected; the
next attempt passed 23 checks, and the final run passed 24 after adding the
source-identity recheck. All attempts and their raw logs are retained in the
receipt.

This is a two-second simulated software-equivalence result for one calm Club
scenario, two companions, and one scripted player tape. It establishes neither
physical-flight validity nor a wall-clock speedup. No timing was collected for
that equivalence run; the score-call reduction is not a measured speedup. Longer
and dynamic avoidance qualification remains separate work. The score-call claim
relies on `_score_bank` being pure for the concrete production controller; an
external subclass that adds observable score-call side effects would observe
fewer calls.

## Separate callback timing diagnostic

A later headless callback probe ran 240 warmup and 2,400 measured ticks for
production and candidate controllers at companion counts 0–3. All eight branches
completed at 240 Hz, retained production manager-profile identity, and produced
matching player/companion state and command fingerprints. The report serializes
every raw callback-bucket sample and its full p50/p95/p99/max statistics. An
independent check found no per-tick bucket-sum mismatches.

The complete-callback p95 values are compared directly with the 2 ms budget:

| Companions | Production p95 | Candidate p95 | Candidate vs 2 ms |
| ---: | ---: | ---: | --- |
| 0 | 3,751 µs | 1,529 µs | Under, but no AI callbacks ran |
| 1 | 4,919 µs | 3,948 µs | Over |
| 2 | 6,562 µs | 5,041 µs | Over |
| 3 | 8,706 µs | 7,099 µs | Over |

This is shared-host diagnostic data, not a causal wall-time result. A separate
vegetation benchmark was active during the callback run. Count 0 is a useful
noise control: no companion callbacks ran, yet the two branches differed by more
than 2 ms at p95. The result therefore makes no speedup or timing-acceptance
claim. Compare the directly measured complete-callback p95; marginal stage p95s
cannot be added because they need not refer to the same ticks. The wrapper timer
overhead is reported with the raw samples and is not subtracted.

The timing is bound to frozen clone commit
`16a6d9566e1fac0ca7ac96ce6e085beb9fe2c643`, with production pilot SHA
`363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed`, baseline
controller SHA `1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c`,
and candidate SHA
`3842cbdba80c7bef5041844132a811bfd27c1cb68de759ce06f39bb97ca1f024`. That
snapshot used profile-solver qualification
`1526c98431a7dee5206eb992e10f40e436a7ef80d173e8c1dbfe6f1ad8f33b7e`. The current
main profile carries the separate AFC-02 merged solver source SHA
`b9911cc9166e1cb8c523cfa61c2b4fb17dd0ac727384d9622ebf00afd9f16f30`; this
diagnostic does not qualify that solver merge. See the
[AFC-02 solver-merge receipt](../AFC-02/solver-merge-15f6efc7/receipt.json).

The exact production pilot was retained byte-for-byte at
`research/ai-companions/performance/reachable_clear_baseline.gd`. The differential
harness now resolves its baseline from that copy and passed 11 checks over 1,280
pairs (130 clear, 766 held, 1,430 score calls avoided). The pre-edit harness copy
and its original receipt remain indexed separately. Full run paths, source maps,
retry details, hardware, hashes, and the checked-runner reports are in
[callback-timing-supplement.json](callback-timing-supplement.json) and
[verification.json](verification.json).
