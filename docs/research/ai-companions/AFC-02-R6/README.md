# AFC-02-R6: seeds, behavior identity and flight status

2026-11-09, Windows x86_64, official Godot `4.8.beta2.official.cafc17a19`,
headless GDScript reference. This audit follow-up covers AFC-02 seed/admission,
AFC-05-R2 status and AFC-00-R6 Manager timing. The prior
[controller qualification](../AFC-04-R9/README.md),
[engine/aircraft qualification](../AFC-02-R5/README.md) and
[accepted-input/transition repair](../AFC-03-R2/README.md) retain their own evidence.
No aircraft data, physics law, golden flight, population or activity limit changed.

The allocator hashes a versioned turbulence domain, player/traffic seeds, stable
actor ID and retry nonce to uint32. Each fixed launch reserves the player's seed
and actual engine initial RNG state, then earlier allocations, with at most 64
attempts per actor. Traffic phase/direction still receives the original traffic
seed. Extending the ordered roster preserves earlier allocations, but live roster
changes and fleet restore are not implemented. Capture admission metadata retains
the canonical record and separate weather-active flags; each ORFL retains its
actual weather seed and complete OU checkpoint. RNG-state provenance is hex to
avoid JSON float64 rounding. Integral JSON numbers are validated against the
canonical roster; altered actors, seeds, nonces or keys refuse.

Zero is an ordinary valid engine seed. The allocator checks the actual mapping;
it does not invent a zero-seed alias. V1 calm weather is preserved without adding
turbulence, and a v2 zero-RMS profile reports inactive turbulence. Unique seeds
and initial states prevent identical starting realizations for the admitted
roster, not statistical independence of PCG streams.

Aircraft profile v2 binds `openrc-ai-behavior-manifest v1`, a closed set of sixteen
source paths with UTF-8/LF SHA-256 identities. Strict bounded JSON rejects duplicate
keys. The bytes parsed and hashed are the same buffer. Missing/extra/changed files
refuse before roster replacement. The set includes Main/AppRoot, admission,
manager/agent, configuration, airspace/static prediction, observation, pilot/base,
seed allocator, field/lake loaders, collision helpers and strict parser. Existing
engine, raw pilot/base, normalized solver and aircraft/field-data gates remain.
Manifest normalization does not relax the legacy raw controller gates. A full
listed mixed-purpose file is conservative; unlisted cosmetics and presentation
setting values are outside this manifest. This is a declared set, not complete
semantic closure, in-memory tamper detection or a security boundary. On-disk
sources must remain stable during the running process. Packaged source availability
remains a separate gate.

Main retains a detached accepted launch configuration, including accepted Off.
Status reports requested/admitted/pending counts and configurations separately
from actual active/airborne actors. Count, seed and Off changes wait for restart;
volume and labels apply immediately. Remove keeps preferences. Dirty drafts survive
status refresh, Cancel discards them, and failed saves roll back the setting
transaction. CLI Off/count zero remains zero on presentation-only Apply. Companion
status strings have translations in all eight non-English catalogs.

`last_tick_usec` sums separately measured matching Manager before/after callbacks;
the player solver gap is excluded. Reset, rejection and removal discard pending
samples; accepted postcommit faults retain the accepted timing pair. Successful
replacement/removal clears old-roster diagnostics. Opt-in phases are exclusive
prepare, advance, world publication and residual after-step overhead; render
presentation is separate. Prepare includes prediction/control; advance includes
synchronous AI recorder observers. Player recording and other callbacks outside
Manager are excluded. Detailed-off status omits unavailable phase buckets.
Wall-clock values never feed deterministic decisions. Separate prediction,
control and recorder attribution and a complete fresh 1080p hardware baseline
remain open.

The new seed/timing regression passes 83 checks, including zero/wrap cases,
forced collisions and exhaustion, JSON round trips and fractional refusal,
240 actual OU transitions, v1/zero-RMS preservation, detached persisted metadata,
three-agent byte parity with detailed timing/capture enabled, and a real earlier
postcommit fault observer. The existing Manager and recording suites pass
53 and 157 checks. Exact replay is numerical solver replay, not controller
decision replay or physical validation.

[Verification](verification.json) indexes checked reports, source identities,
mutation controls and retained tapes. [Behavior inventory](behavior-inventory.json)
checks all sixteen normalized pins. Compared with the prior R2 195-path receipt,
only Agent, Manager, FleetRecord, profile loader and Main differ; physics,
simulation, aircraft and field inputs match byte for byte. Main includes concurrent
economy presentation work; this is qualification of the recorded working tree,
not a claim that its inputs all belong to one commit.

| Check | Result |
| --- | --- |
| Seed/timing regression with final v2 admission | 83 checks, zero failures |
| Strict profiles / behavior manifest | 52 / 39 checks, zero failures |
| Final v2 Manager / capture consumers | 53 / 156 checks, zero failures |
| Observation / lifecycle | 21 / 653 checks, zero failures; 50 headless and 10 visual/audio rebuild cycles |
| Nine-locale dialog / strict draft / AppRoot shell | 42 / 60 / 65 checks, zero failures |
| Two-minute 1–3 calm/gentle matrix and two calm repeats | 156 checks, zero failures |
| Sixty-second gentle encounter survey | Six nominal cases pass the 30 m gate; constructed conflict fails |
| Retained baseline and candidate exact replay | Six complete replays, `solver_changed=false` |

The [matrix](matrix/scenario_metrics.csv) retains all six 28,800-tick scenarios,
[one-second samples](matrix/flight_samples_1hz.csv) and
[resolved allocations](matrix/seed_allocations.json). Minimum AGL is 34.321804 m,
maximum radial error 3.904957 m, minimum player separation 122.324777 m and minimum
fleet separation 118.771338 m. Both three-aircraft calm repeats complete with
byte-identical sampled state and commands. Calm behavior is preserved; the new
gentle seeds intentionally change the turbulence realizations and resulting
trajectories. These values are observations, not expanded admission gates.

All six nominal [gentle encounters](encounters/gentle.json) finish 14,400 ticks
without crash, refusal or fault; minimum player separation is 43.384803 m.
The repeat matches exactly. The constructed two-threat initial conflict remains
a failing survey case at 29.0 m player / 8.343604 m peer separation. Consequently
the report's all-cases separation flag is false. It is not an admitted production
spawn. Seed changes do not uniformly improve separation. The compressed
[trajectory CSV](encounters/trajectory.csv.gz) retains the actual sampled paths.

Six compressed [tapes](tapes/) preserve the pre-change calm companion, the new
calm companion, and a new gentle player/three-companion capture. All replay
exactly: the calm logs have 261 rows and each gentle log 241. The
[calm comparison](replays/calm-comparison.json) has no divergent row; its CSVs also
match byte for byte. Replays validate every recorded numeric sample on the same
solver, not just these rounded CSVs. The final 83-check suite adds JSON and
diagnostic assertions to the earlier 74-check run that produced the retained
gentle capture; runtime flight inputs are identical.

[Normal app admission](production-admission.json), without overrides, observes
three airborne companions with traffic seed zero through tick 3,213, profile
identity v2 and the recorded manifest hash. The
[timing sample](production-timing.json) records separate owned callback phases
after another 24 manually stepped ticks. A nonzero-tick capture request correctly
refuses the launch-only capture contract. Remove leaves zero active actors and
the three-aircraft request intact; [shutdown](production-stop.json) is unforced,
with no crash or leaked objects. Launcher exit code is unavailable. These headless
values are not hardware performance qualification.

UI checks assert a 1920×1080 logical viewport in all nine languages; they are
headless layout checks, not rendered hardware evidence. Strict draft admission
uses no solver override. The shell suite retains its existing test-only solver
override, while behavior-manifest enforcement remains active. The broader
[language gate](checks/unrelated-language-failure.json) still fails fourteen
checks for unrelated missing economy translations; none of the four new
companion messages is in that failure list. Required full CI and packaged
qualification are not replaced by these focused checks.

Reproduction uses the [checked runner](../../../../tools/godot/README.md),
`test_companions_seeds_timing.gd`, `test_companions_behavior_manifest.gd`,
`research/ai-companions/pilot_probe.gd` and the gentle encounter probe. Exact
arguments are retained in each checked report. Decompress each ORFL into a new
ignored directory and follow the existing [flight-log workflow](../../../FLIGHT-LOGGING.md).
This work does not qualify arbitrary-player avoidance, static containment,
additional aircraft, runway activities, live fleet restore or higher populations.
