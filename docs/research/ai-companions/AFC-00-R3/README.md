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
physical-flight validity nor a wall-clock speedup. No timing was collected; longer
and dynamic avoidance qualification remains separate work. The score-call claim
relies on `_score_bank` being pure for the concrete production controller; an
external subclass that adds observable score-call side effects would observe
fewer calls.
