# Native and recording consolidation — 2026-11-28

Evidence for the [single consolidation plan](../../plans/vehicle-runtime-consolidation.md#61-native-and-recording-consolidation-cohort--2026-11-28). The plan owns priorities and status; this record distinguishes observed results from remaining qualification.

## Delivered scope

Two shared mechanisms now have one production implementation: fixed-wing native control encoding at seven existing call sites, and ORFL packet transport used by three recorders. A separately reproduced and corrected short-write defect prevents publication of a hash chain for a frame that was not completely appended. Family laws, the simulation transaction, numerical backend selection and recorder lifecycle remain with their existing owners. [Architecture responsibilities](../../STACK.md#shared-native-and-recording-boundaries) and [recording contracts](../../FLIGHT-LOGGING.md#durability-cost-and-limits) document these boundaries.

| Published commit | Reviewable change |
| --- | --- |
| `7bfb4b0ee57e093ff9b52752cb087771e89ca4ab` | Preserve the existing branch and integrate pinned main. |
| `9a299c2d5dda0fbae7cc2681fb373d7e9386d8e2` | Commit the scoped plan and adversarial acceptance gates before implementation. |
| `9fefe3a1059934329402c541aa68fa460b521c8f` | Centralize fresh five-lane float64 control packets and add independent caller checks. |
| `89aa14f6eb7c9253f7519329a2b53d923177453a` | Share bounded framing, checksum, chain and decoding; retain compatibility interfaces. |
| `97fdaf019b87713d024b2bbe2bad5d4d5a1dd4bf` | Correct buffered short-write detection and add the three-family Linux regression. This is the qualified simulation source for companion rebinding. |

Publication used the authenticated GitHub connector after direct Git push lacked credentials. Published commit metadata differs from the temporary local commits; each corresponding complete Git tree was compared and matched before the existing remote branch was advanced without force. The baseline aliases and tested tree are retained in [verification.json](verification.json).

## Branch and prior evidence

The existing consolidation branch ended at `023043b78daef10b0fc4f746ec83e7c41bf51d17`, one commit beyond the remembered `e6dc52ddb`. Its four commits change six documentation/inventory paths: four new files and two existing indexes, with no product changes. Pinned main is `8d4169f8febfd7d78a028eaa817414217a54f24b`; common ancestor `7940a4081e10994f34c858c4acac3d7a1a271464` leaves four branch commits and 208 main commits. Independent fetch/ancestry checks resolve the starting shallow checkouts.

Merge `7bfb4b0ee57e093ff9b52752cb087771e89ca4ab` has both tips as parents. Its `app`, `research`, `tools` and `.github` trees match main. At that merge the original plan, audit, source inventory and forty control cases match the existing branch tip byte-for-byte. Both documentation indexes survive. Other branches/worktrees, including active shader edits, were preserved.

The researcher rechecked the historical inventory: 759 of 839 application GDScripts still match, 80 changed, none disappeared; ten of sixteen core files changed. The current native guard repair supersedes an older swarm timing claim. PRs 16/17/18/21/22 retain separate helicopter, physics, EDF, CI and graphics scope; their code and historical passes were not imported wholesale.

## Ten specialist assignments

Every assignment requested `gpt-6.2-astra` with the supported model override. The tool accepted the request; independent effective-model telemetry is unavailable. Up to three helpers ran concurrently. The lead owns integration and claims.

| Specialist | Contribution |
| --- | --- |
| 1 · Branch history | Four-commit provenance, corrected tip, PR disposition and changed-source inventory. |
| 2 · Native architecture | Runtime ownership and seven matching encoders; distinct family context and late-admission risks. |
| 3 · Physics integration | Old/new servo timing and a counterexample to historical capsule equivalence. |
| 4 · Dependencies | Live compatibility facades and leaf ownership; direct StageConfig imports add no preload cycle. |
| 5 · Native readability | Typed encoder, explicit field order, naming and byte/call-order checks. |
| 6 · Duplication | Three actual ORFL writers, public consumers, independent packet/chain literals and write-failure questions. |
| 7 · Performance/memory | Matched full-recording and focused helper workloads; bounded timing/allocations claims. |
| 8 · Build/platform | Flat native source discovery, distinct qualification lists and pinned-toolchain limitations. |
| 9 · Regression/migration | Source-bound reference fixture, checked-runner admission, recorder and source migration checks. |
| 10 · Adversarial reviewer | Branch/design gates before implementation, counterexamples and final candidate review. |

## Independent objections

| ID | Challenge | Resolution or remaining proof |
| --- | --- | --- |
| O-01 / O-08 | Shallow histories and stale remembered branch tip could lose the canonical plan. | Corrected tip, non-rewriting merge and historical payload preservation independently checked. |
| O-02 | Flat C++ digest/build discovery misses nested headers/TUs; probes depend on current filenames. | No native source move. Future splitting must update discovery, compilation, identity and negative controls together. |
| O-03 | Four-lane research ABI and distinct old/new servo timing invalidate a universal cached context. | Fresh five-lane encoding retains call positions, mandatory keys, optional flap and empty bypass. Real GDScript callers pass independently specified packet/order checks; research/oracle encoders remain independent. |
| O-04 / O-05 | Solver fingerprint, mirrored native sources and checkpoint/backend identity differ. | Preserve all identities/refusals. New scripts cannot reuse old native receipts or historical exact-replay claims. |
| O-06 | Late-freeze probe lacked a qualified native backend; later install/context refusals remain. | Defer transaction repair; no implemented fix or new reproduced native defect claimed. |
| O-07 | Synthetic call/allocation counts and historical Windows timers do not establish candidate FPS. | Matched workload measurements only, with explicit host/backend and uncertainty. |
| O-09 | Independent ORFL recordings differ in headers/source/timing; footer embeds the pre-footer chain. | Separate literal packet equivalence from same-source recorder replay; preserve footer and owner cleanup rules. |
| O-10 | Store return values and flush error can all report success when no frame was written. | Reproduced on the pinned engine for all three original recorders. The separate correction checks each return, flush error and exact final cursor. Six positive and six limited cases pass, including owner disconnection/close and unchanged chain. Independent airship cases also cover partial writes and exact-limit successes. No rollback or durability guarantee. |
| O-11 | Airship and quad capsule clearance are no longer equivalent. | Reject merge: horizontal north-axis capsule, half-length 2, radius 0.5, point N=1.5 gives +1.0 versus −0.5 clearance. |
| O-12 | Diagnostic declarations enforce distinct source/export/Mac contracts and exact exporter-byte bindings. | Defer catalog consolidation until platform/provenance gates and independent mutation checks are available. |
| O-13 | Moving a local named `hash` introduced a warning outside its historical suppression path. | Rename the new local to `context`; individual parse and runtime checks have zero warnings. |
| O-14 | The initial test double made raw auxiliary state indistinguishable from correctly encoded controls. | Six raw lanes now produce distinct five-lane old/updated expected packets. Swapped-lane, raw-auxiliary and unconditional-downwash mutants fail with 21, 3 and 1 assertions respectively. Tests use a recording receiver, not a loaded C++ engine. |
| O-15 | The shared helper has a measurable cost; a reference recording cannot establish its native flight cost. | Accept the maintenance tradeoff explicitly: +0.062 microseconds per pack in the confirmation run. No claimed FPS or native speedup. |
| O-16 | Packet unit tests alone cannot prove owner cleanup or physical storage durability. | Add real three-family start/subscription/failure checks. Literal frames/chains and exact/over packet bounds remain independent; a partial tail can persist after refusal. |
| O-17 | A successful regression run nested receipts where the real CI collector rejected them. | Put checked runs directly in the collection and recordings/manifests in a sibling directory. The real collector reports two passes; the old writer produces a valid failing receipt and exit 1. |
| O-18 | The subprocess wrapper has a different admission classification. | The existing suite has the required inherited scope. Document standalone use for unenrolled Linux and require the admitted suite on enrolled hosts; no admission rule changed. |
| O-19 | Inserting the gate before H7 escaped the existing lightweight phase fixture's replacement boundary. | Move the unchanged gate after H7: all 14 existing phase-routing tests pass. No physics or assertion change. |
| O-20 / O-21 | Report wording attributed every engine invocation to the checked runner and called the historical accepted solver a Git parent. | Restrict runner coverage to the 21 script/13 parse checks; name the official replay workflow, historical accepted revision, candidate replay mode and current non-solver baseline explicitly. |

## Verification

Pinned Godot 4.8-beta2 SHA-256 is `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`. The host is unenrolled for shared test admission and has no configured pool; the 21 affected script checks and 13 parse checks used the supported local checked runner. The companion workflow used its own official inspection and replay tools. The isolated fixture retained verified production source/data and the real project for companion replay. Its backend was `gdscript_reference`; native-named tests exercised available reference/refusal paths.

| Check | Observed result and scope |
| --- | --- |
| Current baseline | 19 affected GDScript scripts pass before migration. Forty-four Python native tooling tests pass; the standalone glow rejection component passes 40 assertions with GCC 14.2.0. Neither result loads the extension. |
| Final affected scripts | **21/21 pass**, including the original 19 and two new boundary tests. Zero engine errors/warnings; four existing golden flights remain unchanged. Final companion profile: 95 checks. |
| Changed GDScript parsing | **13/13** individually pass checked `--check-only`, zero errors/warnings. |
| Native control packet | 22 checks through actual adapter/stage GDScript methods with an independent receiver. Covers float64 bytes, optional flap, fresh arrays, family refusal/order, old/updated servo sampling and empty downwash bypass; three deliberate mutants are rejected. |
| ORFL packet and owner checks | Independent literal frame/two chain values, exact 16 MiB packet boundary, oversized/caller-cap refusal, corruption/truncation; real recorder controls and disk-error cleanup for all three families. |
| Independent short-write witness | Ten real airship write cases: five valid writes, five refusals; includes exact 65,536-byte endings, zero-byte appends and 16-byte partial tails. Old buffered stores could all return true with error 0; final guard refuses before chain publication. |
| Recorded body blocks | Fixed-wing 3, multirotor 6 and blimp 9 blocks match baseline bytes. Headers and chained footers legitimately change with source identity. |
| Retained Jensen tape | All 261 CSV rows match for baseline exact, final exact and explicit final-candidate replay of the original tape; SHA-256 `9d858640d75fe9f53ea674df082a76d400a6fba6ad9c4c6ce06e604da0452d8d`. Exact old-source replay on the new solver is correctly refused; candidate comparison reports `solver_changed=true`. |
| Companion source migration | The unmodified official rebind workflow verifies **9 tapes × 2,881 rows**, with byte-identical historical-accepted-solver/candidate CSVs, both using candidate replay mode. Stored/decompressed tape and child-input hashes are checked. Only the generated profile fingerprint, accepted source and new receipt change; tapes and goldens are not regenerated. |

[Verification summary](verification.json) retains source identity, commands, completion contracts, checked receipt/log digests, block digests and mutation outcomes. The [official companion receipt](../ai-companions/AFC-02/rebinds/2026-11-28-bd5a8878-to-02f983b7.json) binds accepted source `97fdaf019` and solver fingerprint `02f983b71c34c76444c4dd60ca5717c494408feb00a98023f621b8fd0df9883b`. Agent 10 rehashed all nine stored/decompressed tape inputs and all eighteen child identities, checked the nine CSV digest pairs and raw checked logs, and directly compared the three retained Jensen CSV files. The historical accepted revision is `d52195d0667aec3b22e60cf79228b6aff020efb6`, distinct from the candidate's Git parent. The workflow uses `baseline=solver`: both comparisons retain current non-solver application code. The nine companion CSV pairs were temporary outputs of the official workflow; their receipt hashes are retained, not independent archived CSV files.

## Measured cost

Linux x86_64, AMD EPYC 9V74 virtual host, pinned logical CPU 8, headless pinned Godot, no simultaneous engine job. One warmup precedes balanced paired runs. The packer uses 64 real deflection dictionaries and 12 pairs of 200,000 calls. Recording uses eight pairs with original and final corrected writers in one process; the original quad/blimp hash owner is also frozen to avoid baseline contamination. Full flights use 480 real Jensen ticks and include start, marking, two full blocks, final flush and close. Packet cases use actual 240-row blocks, plus explicitly synthetic small/near-cap payloads. File flush timing includes Linux page caching.

| Workload | Baseline median | Final median | Median paired change [Q1, Q3] |
| --- | ---: | ---: | ---: |
| Five-lane pack, microseconds/call | 0.363 | 0.425 | +0.062 [+0.051, +0.083] |
| Full 480-tick recording, ms | 286.785 | 291.900 | +4.287 [−14.686, +10.744] |
| Fixed-wing 240-row packet, microseconds | 1324.17 | 1342.94 | +27.63 [+1.34, +54.80] |
| Multirotor 240-row packet, microseconds | 555.50 | 523.40 | −19.00 [−65.81, −10.43] |
| Blimp 240-row packet, microseconds | 216.92 | 223.63 | +5.67 [−3.24, +11.33] |
| Synthetic 172-byte marker, microseconds | 4.297 | 5.220 | +0.884 [+0.705, +1.044] |
| Synthetic 16,777,020-byte payload, ms | 59.286 | 59.824 | +0.044 [−2.085, +0.482] |

The extra helper call and tiny packet overhead are accepted maintenance/correctness costs. Opposite family signals and overlapping full-flight samples establish no general throughput gain. Quartiles describe sample dispersion, not confidence intervals. Seven source sites are not seven calls per tick, and these reference recordings do not exercise the native helper. An alternate resize/fill helper offered no packing improvement.

All completed flights retained identical numerical final states/body blocks and a peak buffer of 240 rows. Independent Python frame/chain reconstruction passed for every packet benchmark. Packet batches retained 64 additional Godot allocator bytes on both versions; this is an endpoint delta, not peak RSS/VRAM or a memory-saving result. [benchmarks.json](benchmarks.json) retains raw paired samples, source hashes, host details and checked-run identities. The final packet measurements supersede the earlier extraction-only run.

## Remaining qualification

The original controls cohort and C01–C40 remain open. Full required CI, actual installed native parity/selection, platform packages, live target performance and physical/pilot validation remain separate gates. This host has GCC 14.2.0, whereas native qualification pins GCC 13.3.0, SCons 4.10.1 and an unavailable pinned godot-cpp checkout. The lock was preserved. No C++ translation units or source-discovery rules moved. Native refusal checks and recording-receiver tests do not qualify native execution.

Whole capsule clearance consolidation was rejected with a concrete geometry counterexample. Native late-freeze behavior and diagnostic catalog consolidation remain unproven or platform-dependent work under the existing plan. No known-live facade or independent numerical oracle was removed as supposedly unused code. Agent 10 approved this scoped consolidation for draft-PR and required-CI review after the reporting corrections above; no implementation or companion-migration blocker remained. This is not approval for release, installed native execution or physical promotion. The separately reported CI outcome remains required; this report does not assert a full CI pass.
