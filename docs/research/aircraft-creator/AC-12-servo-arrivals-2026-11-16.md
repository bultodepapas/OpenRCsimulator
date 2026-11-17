# AC-12: explicit normalized servo arrivals

Preregistered 2026-11-16, before any refinement flight using this versioned law.
Owner: AC-12 / AC-CV-06. This record supplements the [arrival study](AC-12-servo-knots-2026-11-16.md);
its private ramp-law results do not qualify this different law. G05 remains open.

## Candidate and admission

`normalized-slew-arrivals-v1` is an explicit aircraft-data selector, carried by
`openrc-creator-definition v4`. Versions 1–3 keep their historical compiler bytes.
The new law evaluates a normalized linear servo ramp followed by an exact target hold.
One rounded binary64 `abs(target - start) / rate` arrival controls the endpoint,
stage sampler and partition planner. This is a rounded-arithmetic definition;
it is not an exact-real arrival comparison. Numeric equality, including signed
zero, preserves the original start bits. Reached endpoints store target bits.
Distinct represented interior arrivals are never merged by an epsilon.
An unrepresentable partition refuses the entire tick. The initially registered
absolute-clock transport failed as recorded below; its replacement uses a separately
identified local-clock protocol with unchanged servo and acceptance laws.

The current adapter installs the complete `joint-interval-local-v1` vehicle contract, with
body13, inputs4, aux4/5, continuous shaft/charge/energy/heat4 and modes1.
No servo trajectory survives the tick in hidden mutable session state.
Checkpoint v15 pins the law, callback protocol and explicit layout. Ordinary
restore cannot cross laws. Exact replay must validate the matching recorded
model, metadata and checkpoint and preserve the recorded physical frame.

Initial domain: conventional gearless single-tractor electric aircraft with
finite OCV/resistance battery, calm reference atmosphere, airborne/hand-launch
starts and explicitly selected GDScript reference backend. Pack ECM, flaps,
propwash transport/slipstream, spatial weather, failures, scenery/lake/track
collision contexts, soft hull contact and practice offsets are refused.
These restrictions also apply before reset/restore and during stepping.
Native execution and unrestricted interactive qualification are not implied.

## Fixed campaign

Initial campaign identity: `ac12-normalized-slew-arrivals-v1-20261116`.
The separately registered local transport uses
`ac12-normalized-slew-arrivals-local-v1-20261116` and reruns the entire same matrix.
The new [driver](../../../research/aircraft-creator/ac12/servo_arrival_campaign.gd)
uses exactly C01–C17 from the historical `campaign.gd`, each with its four
unchanged tapes: pitch doublet, roll doublet, rudder kick and throttle step.
Only the explicit definition version and servo selector change. No new trim,
geometry, package, command amplitude, time edge, start or environment is chosen
to improve a failed result. X/N follow-up cases are excluded from this registration.

All **68 cells** run six simulated seconds at **240, 480 and 960 Hz**, sampled
at the common 240 Hz boundaries: 1,440 rows, each 17 binary64 values. Every cell
records its own fresh 240 Hz baseline and requires complete exact replay from
tick 0 through 1,440, with 1,441 replay rows and `solver_changed=false`.
An older baseline, recovered prefix or candidate replay cannot satisfy this gate.

The historical seven metrics, formulas, floors, tolerances and maximum ratio
0.75 are used without modification. A failure remains a failure. Every cell's
initial physical frame, environment and canonical command edges must match
across rates before its refinement result can be interpreted. All 68 registered
cells must complete and pass; missing/refused cells cannot be omitted from the
denominator. A completed measurement is not automatically flight qualification.

The source manifest retained before dispatch is snapshot
`9812572a79a5481292eb46aedf333ac4`, SHA-256
`a3129c799c422501ce9649e503447c5e009cd3853482a4eb00f1cc7005ae57e3`,
with source digest `b1affa4fcd3e36049986d1c47f830d04c35d55f6a4718b1032201b527157313c`.
The final safety test on these bytes passed 139 assertions on Windows
(`b90c3a3c1b58480995f7cfc9e9ee73d0`), including refusal when a live caller removes
the selector from an already installed model. Selector checks avoid allocating
empty fallback dictionaries on the stock tick path. The kernel-only dependency
fixture passed its unchanged 130 assertions on Windows
(`e648f7aa80694c54b5efe9e6f9589e7b`); this does not erase the separate texture-import
failure or qualify the complete application.

The five diagnostic cells from the original current-source audit may additionally
run the already defined 240/480/960/960/1920/1920/3840 calibration sequence.
Report them separately; they neither replace a failed 68-cell result nor change
floors, thresholds or the registered acceptance rule. Any subsequent change to
the physical law requires a new source identity and a separately declared campaign.

## Evidence retention and release boundary

Before dispatch, retain the exact candidate snapshot manifest, source hashes,
entrypoint hash and pinned engine identity. Each audit report inventories the
actual source closure, engine binary, compiled aircraft and definition. Retain
every exact sample buffer, complete baseline `.orfl`, CSV, replay receipt and
checked-runner result outside Git. Independently recompute each metric from
the retained binary rows and verify all referenced hashes and sample counts.
Failed attempts and incomplete evidence remain explicitly labelled.

No new-law refinement flight had run at registration. The following component
integration results were subsequently collected; they do not qualify G05,
physical behavior, packaged targets or 1080p rendering.

| Check | Native request | Result |
| --- | --- | --- |
| Selected law, v4 carrier, atomic refusals and nonzero-boundary exact replay, Windows | `25d3366d5155466ca6bf46e3a3b0ea60` | 136 assertions, zero checked errors/warnings |
| Same selected-law test, Apple Silicon | `aafa47f6c6c44128aaa8930cf80adb3e` | 136 assertions, zero checked errors/warnings |
| Existing Creator compiler, Windows | `efbb6e5074164da2bb1acaa2038dcf17` | 196 assertions |
| Existing flight-log/reader contracts, Windows | `d626c253dd5541cbbd7a4eabc6c874df` | 4,417 assertions |
| Existing framed sampled model, Windows | `dffddc1d1bef4ce7843531c634d38eed` | 50 assertions |
| Existing endpoint transaction, Windows | `dc637123be7b445988022ca8f1ad7cad` | 274 assertions |
| Original audit contracts, Windows | `2cc0f6a515374e30b3eac055f0276e38` | 56 assertions |

All listed checks passed with complete checked receipts and zero errors/warnings.
The new-law unit replay verifies 13 rows from a nonzero boundary; it does not
replace the required 1,441-row baseline for any numerical campaign cell.
The source changes are integrated behind their explicit selector. Public
ClearView trial/publication gates remain closed. Python flight-log consumer
contracts passed 35 tests; the independent metric/ambiguity oracles passed six.
The full application/autoload, CI, exported desktop and rendered gates remain open.

The Windows fixture initially omitted three existing kernel test entrypoints;
those attempts did not execute the requested tests. After correcting that fixture,
one import process exited with Windows heap-corruption status `0xC0000374`, before
the joint-interval test, with Unicode diagnostics during stock texture import.
Its failed receipt and input remain retained; it is not a passing test. The
affected kernel check is being isolated to its actual dependencies. Apple
Silicon attempts `f10681c560f74a95a747fd0188c135d9` and
`8cc8af7b805640b8b083fec727b885e4` were refused for disk reserve before execution;
their original input/source/state remain intact. The later passing request above
used the same physics code after resource recovery.

Before the first numerical flight, the retained pre-selector source produced
the 17 historical case identities without flying (request
`29f0a84ecc8f41e4b0953fdb09a0eeb7`). Its case map SHA-256 is
`5ee4b31e617ba4fb35cefa41eed03a256fb9631e624717c9ff92cef3933a2f9a`.
The historical case recipe remains
`20acca0973e6c7285ad8f7c4cf5cdd1564f798f5a60887036d22f73e99ecaaf8`.
The new-law map must match every legacy definition/record identity before
proving that the sole physical record change is the explicit selector.
That check passed for all 17 cases in request
`9f29a9ab72f14e368fe37cd564d33446`, producing the preregistered selected map
`f1217baebde255a9b5d9516a1e70b9118ce048643a24639b7e0a73d3ce9edc86`.
Both maps must also match their copies in the frozen campaign inputs; caller
arguments cannot replace either anchor. The composite registration/order checks
passed 217 assertions (`98147821cd1c4d01b32820fb817280ef`).

A composite research owner sequences the same 68 registered cells in one
exclusive process, constructing fresh flight/replay sessions per cell and
clearing only per-cell audit caches. It changes no rate, tape, sample or verdict.
This avoids 68 identical source/resource copies. Every cell still has its own
fresh baseline and nine required artifacts. The verifier binds native job IDs,
log/report hashes, engine and complete source closure, expected case identities,
initial frames/environments/edges, binary traces and full replay/CSV contents.
It refuses comparison uncertainty that could change a floor, ratio or tolerance
decision. No result from the verifier's earlier incomplete implementation is accepted.
An incomplete or uninterpretable cell stops the composite owner. Its retained
prefix is diagnostic evidence; it cannot establish the 68-cell gate or substitute
for the missing cells. Complete cells with a failed numerical verdict remain
failures and do not stop measurement of the remaining registered cells.

G05 numerical closure is only one dependency of the ClearView first-flight
milestone. Source appearance, confirmed moving parts, provenance/rights,
persistence, Home/restart, lifecycle and packaged desktop/1080p evidence retain
their independent gates in the [import plan](../../plans/clearview-aircraft-import.md).

## Absolute-clock result and local-clock follow-up

Pilot `7983be2547604bf3b2dd41405bf5d405` completed C01/pitch-doublet at all three
rates; the strict independent partial verifier accepted its nine retained artifacts
and its full 1,441-row exact replay. This was one cell, not a campaign pass.

The full attempt `c03da259f4b04e6282782023c52f14fa` stopped at C02/rudder-kick,
tick 144 at 240 Hz. It retained six complete cells and one incomplete prefix.
The last rudder endpoint is `0.5397401129356305`, one ULP below the commanded
`0.5397401129356306`. At rate 5/s its remaining arrival is
`2.2204460492503132e-17` s, which collapses when added to absolute time 0.6 s.
The guard correctly refused publication. This is a failed measurement attempt,
not a numerical pass. Its frozen input, native receipt, all produced artifacts
and retained negative collection remain separate from future attempts.

The local follow-up is declared before its first refinement flight. It changes
the generic transport, not the rounded servo law, case geometry, tapes, metrics,
floors or thresholds. `joint-interval-local-v1` supplies stage/policy offsets in
`[0, dt]` and keeps the absolute origin in the same immutable context. Reset
stages have offset zero. The absolute-clock v1 protocol keeps its semantics.
Each planned piece retains its own origin and phase: a cut immediately before
the tick endpoint need not have a representable midpoint on the outer clock.
The local stage callback receives that piece origin separately; a compensated
sum samples the same rounded ramp/hold, preserving the original sampler whenever
the query sum is exactly represented. Every RK trial, including rotor/battery root refinements, must have distinct
represented start/midpoint/end and normal positive RK weights. Truly unresolved
trials still refuse atomically; no epsilon cut merging or target snap is added.
The existing event root time/value tolerances are unchanged; this is not a claim
of exact rotor/battery event localization below those tolerances.

Time-dependent generic laws can consume origin and offset separately. Adding
them into one float cannot preserve sub-ULP phase. The aircraft adapter therefore
admits only the unchanged base session/environment/weather and turbulence provider
under its calm/reference domain, where the accepted force laws are independent of
absolute stage time. Substituted or derived providers are refused. Local event
order is checked before conversion; distinct local events whose absolute ordering
cannot be represented are refused, rather than relabelled simultaneous.

The follow-up requires a fresh frozen source identity, strict independent verifier
and all 68 fresh full baselines. Nothing from the failed prefix is reused as a pass.

Before the first local refinement flight, the frozen candidate is
`8c342047d1fb4f8d903d1b8280d0903d`, manifest SHA-256
`0b5f1cd35e64307b1285774665a09e57322f948b2b9b6c1ef6a4e1f2362c6258`,
source digest `4809f880187d7503f3dd0d10ba88870b68b7b1dae4418d97b86aaaa10d120b78`.
Both registered case maps and all historical inputs retain their previous hashes.
The selected map retains its original campaign label as the physical inventory's
provenance. The verifier checks that original map label separately from the new
measurement campaign label; neither is caller-selectable.
The independent verifier pins this new manifest and the local campaign/protocol;
it cannot combine or relabel the absolute-clock prefix.

Local transport checks passed 29 assertions on Windows
(`f2ecbd65f3a443cca86e07cdf155611b`) and Apple Silicon
(`6dc021fd9bb74195945a8d933ede32fa`). They include the original one-ULP residual,
an analytic nonautonomous integral, short initial/final pieces, exact endpoint
identity, dynamic root refusal and subnormal RK weights. The unchanged absolute
protocol passed 130 assertions (`df37fabc0ed04731a5070342e584d176`). Authoring v4
passed 72 document/compile/restore checks (`a1b9bfa4770e4d478931a6fb54c23f76`),
preserving byte-identical v1–v3 documents when no law is chosen. The full selected-law
integration passed 142 assertions and 13 exact replay rows on Windows
(`b7aa9c1be24e4f30a21bfd2819f14ff8`). These are component results, not G05 closure.

The source replay fingerprint additionally binds `input/commands.gd` and `spec.gd`,
which supply stage surface-angle conversion and constants outside the existing
physics/simulation/failure source trees. The hash algorithm and identity format
are unchanged; the extra source dependencies cannot keep the previous digest.

The same selected-law integration passed 142 assertions on Apple Silicon
(`ea303f786c2e4910bdc0cf22f2e17272`). Local C02/rudder-kick pilot
`628a9629b38e43b9b7e35f09f0493906` passed the strict partial verifier, including
its 1,441-row exact replay. Neither component nor partial evidence closes G05.

### Complete local-clock result

Request `a82526ea29a54054a984ff75b327e57f`, native attempt
`A-33c8dd21677e48219a5c5e54fd642783`, completed all 68 cells on Windows using
the registered `8c342047d1fb4f8d903d1b8280d0903d` source. The independent full
verifier accepted measurement completeness, source/context identities and exact
baseline replays, but rejected numerical convergence: 60 cells pass and eight
fail. There are no missing cells. The runner's successful completion marker
establishes completed measurements only; `numerical_campaign_pass=false` and
`flight_qualified=false` remain authoritative.

| Cell | Failed metric | Refinement ratio |
| --- | --- | ---: |
| C01/rudder_kick | charge_fraction | 0.917357579600 |
| C02/throttle_step | rotor_rpm | 0.927326689910 |
| C04/throttle_step | rotor_rpm | 0.795016326665 |
| C05/throttle_step | charge_fraction | 3.02037337822 |
| C07/roll_doublet | charge_fraction | 0.798832722175 |
| C09/throttle_step | charge_fraction | 2.05640297818 |
| C14/rudder_kick | charge_fraction | 2.18640305585 |
| C16/throttle_step | charge_fraction | 1.56420172457 |

All eight fail the unchanged ratio rule, outside its floor exemption. The charge
metric compares final consumed charge, normalized by the finer run's final
consumed charge; it is not an SOC or maximum-over-time metric. Signed charge
differences can cancel before the final sample. This does not justify changing
the metric, floor, threshold or required matrix. Full raw reports, float64
samples, replay files, native receipts and independent verification are retained
outside Git in `G:/OpenRCsimulator-clearview-scratch/servo-arrivals-local-full`.
The finished native source/profile were relocated with SHA-256 inventories to
`G:/OpenRCsimulator-clearview-scratch/retained-local-full-native-20261116` to
relieve disk pressure. Junctions preserve old access paths; they do not establish
native source-manifest equivalence, because admission rejects reparse points.
The original frozen snapshot and the verifier's retained receipts remain intact.

### Registered private forcing-partition diagnostic

This diagnostic is registered before its first refinement flight. C07/roll
contains two servo zero crossings while the global drag law contains absolute
aileron deflections. Offline cusp-integral estimates predict the observed signed
airspeed-difference jumps near those crossings. A separate candidate will add
strict interior zero-crossing offsets to the local forcing partition, retaining
all existing arrival cuts, exact trajectory/endpoint arithmetic, outer cadence,
case maps, physical data, tapes, metrics, floors and thresholds. Three channels
can contribute six distinct cuts; only the local composer's diagnostic bound is
extended from three to six. The historical absolute protocol retains its bound.
An independent triangle-and-hold integral and byte-identical trajectory checks
passed 19 assertions on Apple Silicon (`fdc386a6abec4ddf8d6221f059b6fc17`).

The first comparison is C07/roll on the same Windows engine and unchanged
registered baseline; a different-platform comparison cannot isolate this change.
This is a separately labelled, separately hashed private study, never a G05 pass.
No production physics change follows without causal evidence and the complete
unchanged qualification matrix. Positive-RPM drive/coast transitions and
propeller-table knots are separate hypotheses for throttle cases; the zero-cut
study does not claim to resolve them or the remaining charge failures.

The private C07 candidate froze as `84117399fa01423f8b05a7377f8888e2`, manifest
`fa57063bba286221192d08c25da05abf17b2bded3fe74114f38208b5695c52ff`.
Windows request `719dec2b6fc54f6285c8b7c9cfca5417` completed the cell and its
1,441-row exact replay. A private copy of the independent verifier, pinning that
manifest, diagnostic label and exact C07 selector, accepted the partial result.
All numerical rules and case-map pins are unchanged. The two predicted coarse
forward-speed difference jumps decreased from `+1.913741245e-6` and
`-4.003649696e-7` m/s to `-1.138037220e-9` and `-1.725858567e-9` m/s.
Buffers agree bit-for-bit before the first crossing. The final charge ratio
improved from 0.798833 to 0.432667, while absolute final charge pair differences
increased because the original result had cancellation. Therefore the ratio
alone does not establish a smaller charge error. This cell supports the local
cusp mechanism, not full qualification. Its retained evidence is separate at
`G:/OpenRCsimulator-clearview-scratch/servo-zero-c07-retained`.

Before any throttle subdivision flight, register a separate C02/throttle study:
compare the unchanged registered baseline with two and four equal local RK
pieces per outer tick, each from a separate frozen source and campaign label.
Retain the unchanged outer cadence, sampled downwash, physical data, tapes,
measurement rule and strict local-clock checks. Refuse if the servo is moving
or an arrival cut is present; this isolates electrical/body integration from
servo forcing partitions. Inspect signed RPM/current differences near the
authored `J=0.373` propeller knot and positive-RPM coast-to-drive transition,
then the complete traces and exact own-source replays. This is a diagnostic
subset; neither selected subdivisions nor a partial pass close G05.

C02 two-piece request `00190f015910469c81fd5d50e2917f1a` and four-piece request
`306bc376e0af4e67912897f30adddb89` completed with strict partial verification and
full own-source exact replays. Their frozen snapshots are respectively
`b41ae902acec4c628446027a27bac626` (manifest
`be603a1c7d457b05b550beaf387e7ca28430e4f41436d77e904bcc0fad1fdd2b`)
and `47f1301aa5c34379bc485feff1e18a49` (manifest
`88a727b841dd7a56eaa341ae06ff04b4d6d864609319b1b9de3fc7880ab2341e`).
Both cells pass the inherited rule; rotor ratios are 0.163564 and 0.253057.
Near `J=0.373`, the coarse signed RPM-difference jump changes from
`-0.001820194446` to `+0.000049676045` and `+0.000022260067` rpm. At drive
resumption it changes from `-0.001423681357` to `+0.000683604101` and
`-0.000363728331` rpm. Grid phase and cancellation still matter: the two-piece
coarse maximum increases from 0.00121938 to 0.00217931 rpm. These are evidence
of piecewise integration sensitivity, not proof of monotone accuracy improvement.
Raw/definition, initial, engine, environment, command and edge identities agree;
all servo axes stayed bit-identically held. Retained outputs are separate under
`G:/OpenRCsimulator-clearview-scratch/servo-c02-pieces2-retained` and
`servo-c02-pieces4-retained`.

A separately labelled combined diagnostic is also registered before flight:
retain zero forcing cuts and add one exact `dt * 0.5` local boundary. Keep exact
duplicates shared, distinct cuts separate, all clock guards and the old absolute
protocol unchanged. Three servos plus the midpoint require at most seven local
interior cuts. The first diagnostic subset is the eight failed cells listed
above, in that order, with unchanged definitions, tapes and measurement rules.
It is not a new required matrix or a replacement for the complete 68 cells.
Any accepted candidate still needs all 68 fresh baselines/replays and the other
independent gates. This study tests a fixed integration partition; it does not
claim exact localization of propeller knots or drive/coast transitions.

The combined private source froze as `f11aa5b019764a43b9a93d11bd6354b7`,
manifest `c3990901a0c636b9f999ac1816e4e5ffb7d69b6d0d02d7fdd51748bb33c7409b`.
It passed 22 analytic partition assertions (`f1e4738180a74fcd9e7cdc676e596e5f`)
and 142 selected-law integration/replay assertions
(`5b2cb635177046798e8ae5e77d744a3c`) on Windows. The eight-cell request
`db3d0621fdda40fe8b396f21a26e23a0` completed and its strict partial verifier
accepted all eight inherited-rule results and full exact own-source replays.
The private verifier pins the manifest, diagnostic campaign, selector and exact
eight-cell order; metrics, rules and case-map identities are unchanged.
The eight failures were used to select this diagnostic subset, so it is not
independent qualification. Its retained `verification.json` SHA-256 is
`303de2d0919f3303cdabbdc1202fe928342c71e351348ede51d4eda70ebc088e`
and `partial=true`, `flight_qualified=false` remain authoritative.

Before production adoption or a fresh complete candidate campaign, the partition
policy must have an explicit runtime/checkpoint/replay identity. Historical and
private v15 checkpoints share law/protocol/layout across different algorithms;
an isolated v15 checkpoint cannot identify its policy. Do not infer an arrivals-only
policy from that wrapper. A new version must reject unbound current-runtime
restores, retain unmodified historical report reading, and keep exact historical
replay bound to the verified matching solver/engine source. Finer-rate and repeated
diagnostics remain separate from the unchanged complete 68-cell gate.

### Explicit policy identity and complete candidate registration

The current arrivals-only runtime now records `servo-arrivals-local-v1` in
checkpoint v16 and matching trace/replay declarations. It refuses unbound v15
restores, malformed or mismatched tokens, and replaced trajectory callbacks
before checkpoint publication, restore commitment or tick advancement. Snapshot
`0936861484854952a59678509b6af817` passed 258 checks on Windows
(`958abdec7af34463bc583471a790a115`) and macOS
(`cfb96a8ecc82426fbb2c916b3612412c`), each including a 13-row exact replay.
The Python report/CLI suite passed 37 tests. The current reader, rebound to the
verified historical physics sources and Windows engine, also replayed all 1,441
rows of the retained v15 C02/throttle baseline
(`a925a5afb2a24bdba5b82ccf6ec5647c`). Reading v15 assigns no partition policy.

Before its first full refinement flight, register candidate
`ac12-servo-zero-half-local-v1-20261116`, policy
`servo-arrivals-zero-half-local-v1`, checkpoint v16. The frozen source is
`c210d6369cae42e0a2b69f9a7ee1a255`, manifest SHA-256
`fade2c3eb4cc43e7b0e5c7cb5721cd3587818664068c9d21cc579509ca15f124`.
It retains the studied strict interior zero cuts and exact half-tick boundary,
all arrival cuts, unchanged trajectory/endpoint arithmetic and outer wake
cadence. The absolute-clock protocol keeps its three-cut bound; the local
policy admits at most seven. New-law integration/replay (258), independent
forcing integrals (22), and fixed campaign registration/order (217) checks
passed on Windows before the full run.

Run every original C01–C17 × four tapes, in the original order, at
240/480/960 Hz for six seconds with a fresh complete 1,441-row own-source exact
baseline per cell. Keep both preregistered case maps, all physical inputs,
metrics, floors, tolerances and the 0.75 ratio limit unchanged. The independent
collector must additionally require the v16 wrapper and the exact policy in
context and replay. No diagnostic subset or recovered prefix can substitute
for these 68 cells. Preserve every failure; this candidate is not public flight
permission or physical validation. Its full checked-job timeout is 10,800 seconds;
an observer timeout does not cancel or qualify the native run.

The complete candidate finished as Windows request
`58c04cf2adf4416688fcc2535808fe32`, attempt
`A-6eb32a9a9c0447a984a9111e70d8d6d2`. Native checked execution passed with
confirmed cleanup and complete evidence. Independent collection accepted all
68 registered cells, their source identities and their complete 1,441-row exact
own-source baselines. Numerical acceptance is **64/68**, so G05 remains open.
New failures are C06/roll (charge), C07/throttle (charge), C13/roll (charge),
and C17/rudder (charge and position). Those cells passed under arrivals-only;
the eight selected diagnostic successes did not predict the complete matrix.
The zero-half candidate is not adopted into the production runtime.

Retained evidence: `G:/OpenRCsimulator-clearview-scratch/servo-zero-half-v16-full-retained`.
Its `verification.json` SHA-256 is
`4028a067d8585eeb5968bfb76bc56a46dd2fb938448caf980f6610c808bfb511`;
independent verifier SHA-256 is
`5b289819a9a5f98bdbec91f31733257a4c2d80c649de24c91a19cb93a80050b4`.
The receipt declares `complete=true`, `partial=false`,
`numerical_campaign_pass=false`, `flight_qualified=false`. All original rules,
case maps and failed outputs remain retained; no tolerance or floor was changed.

### Stage-coupled wake candidate

The next private candidate is `ac12-servo-stage-wake-local-v1-20261116`,
policy `servo-arrivals-zero-half-stage-wake-local-v1`, checkpoint v17, coupling
`wing-wake-stage-coupled-rk4-v1`. It integrates the existing authored wake-lag
ODE from stage body, air and servo values instead of holding the outer tick's
advanced wake through every RK stage. The authored length and equilibrium law
are unchanged. A lagged model has five continuous values, with bit-identical
accepted RPM and wake mirrors; the electric evaluator still receives exactly
four values. A no-lag model retains four continuous values and a distinct v17
layout. Whole-tick `dt * V / length > 0.25` is refused, including during event
trials. This bound does not establish coupled-system stability or convergence.
The pre-setup selector is explicit and locked once setup begins. It refuses
models without the selected servo law. There is no checkpoint migration.

The private Windows unit request `servo-stage-wake-v17-unit-win-v4-20261116`
passed 112 checks with zero engine errors/warnings, complete evidence and
confirmed cleanup. Snapshot `1ad2869d1eb44e1b88e9fd2a21a2f4a5` has manifest
SHA-256 `cad936adc89d0cd4e8352bcf149d66c1866f7bbba470416695c99935fb941f06`;
attempt `A-38de9ba3131d424b8371339f7684baf9`, pool job
`47f069b02315486d8da935d6c39bc3d4`. Coverage includes analytic constant/linear
wake forcing through the actual partition/event composer, stage sensitivity,
no-lag and zero-speed cases, electrical events, exact accepted mirrors,
atomic refusal, selector locking, cross-wrapper refusal and a complete nine-row
own-source exact replay. Earlier attempts retained a parse failure and a test
fixture failure: constant folding lost the negative-zero sign. The corrected
fixture constructs and verifies its float64 bits at runtime.

Before numerical execution, register the same complete C01–C17 × four-tape
matrix and order, 240/480/960 Hz, six-second duration, physical inputs, case-map
hashes, metrics, floors, tolerances and 0.75 ratio limit used above. Require one
fresh complete 1,441-row exact own-source baseline per cell. The independent
collector must pin the frozen v17-aware replay validator, exact wrapper, policy,
coupling, layout and initial mirrors. Preserve all refusals and failures; do not
drop a cell that exceeds the new solver's explicit bound. Diagnostic subsets
remain separate. Unit success grants no flight permission. Production remains
arrivals-only v16; this candidate and its full numerical result are not adopted.

The numerical source is frozen at
`G:/OpenRCsimulator-clearview-scratch/servo-stage-wake-v17-campaign-snapshot`,
manifest `04328424615932e4c5773ac2f8b5e1bdd29127a536e90e1d551e0cfbee7243c3`.
Its first diagnostic uses C06/roll, C07/throttle, C13/roll and C17/rudder,
in that order, because those are the four zero-half failures above. It uses
the same three rates, six-second tapes and complete per-cell exact baselines.
The fixed four-cell selector accepts no overrides. Its collector requires
`partial=true`, leaves 64 cells missing and cannot establish G05. The unchanged
complete 68-cell selector is retained in the same frozen source.

The four-cell Windows request `5f33416c40cb40708741a773e013dd27`, attempt
`A-061f88f31b944e37ac8aeec0d752bea8`, completed with confirmed cleanup and
complete checked evidence. Independent collection accepted all four numerical
verdicts, frozen inputs, five-slot mirrors and complete 1,441-row exact baselines.
Retained `servo-stage-wake-v17-four-retained/verification.json` has SHA-256
`7ac2909ccf9f6496d4aa8025d46b064eddf5ea01212bb3629114d5103637cfb5`.
It reports `partial=true`, `complete=false`, `numerical_campaign_pass=false`
and `flight_qualified=false`. The verifier is
`5eb47c576db8ab354c79083ee665e6dc70ee4193e5808ad9baa7e2e6eedd3254`;
the frozen replay validator is
`88959ef7e777b091021c406c346cf45f5f3d5081106660d8e893ba395f3afb6c`.
The verifier executes hash-checked source, refuses unmanifested bytecode caches
for both validator modules, and prevents cache writes into frozen inputs.
Disposable clean/stale-bytecode checks passed. Its metric and numerical-gate
functions remain AST-identical to the zero-half collector.

The complete 68-cell request is `cb6f9c36b1b143afba6e6c4b0fbda3e6`, attempt
`A-de976cb2d06c4bc1ab4f151ef60df35b`, on the same frozen source and Windows
engine. It failed at C08/throttle: the 240 Hz run rejected its next joint stage
after 547 accepted ticks. The composite correctly stopped instead of skipping
that cell. There are 31 complete cells (30 numerical passes and a C03/throttle
failure), one incomplete cell and 36 unexecuted cells. C03 fails attitude and
charge convergence, with respective ratios 1.304515 and 1.280009. G05 remains open.

The failed checked job has confirmed cleanup and complete retained diagnostics;
its process exit is 1 and its outcome remains `TEST_FAILED`. The independent
retainer verified the 31 complete subcells, including exact full baselines, and
retained the incomplete C08 prefix. This does not turn the failed parent job into
a checked pass. Evidence is under `servo-stage-wake-v17-full-failed-retained`;
`failure-retention.json` reports `complete=false`, `partial=true`,
`numerical_campaign_pass=false`, `flight_qualified=false`.

The failure-retention receipt SHA-256 is
`abb447d64322573d1970fac27a36f25408e8d93a1bed0b41bb0824727d191408`.

C03's signed trace changes coincide with shared Ct/Cp and Ct-only advance-ratio
knots; the later coast-to-drive transition contributes a separate charge change.
These observations motivate an isolated coefficient-knot localization ablation,
not a replacement numerical rule. The private primitive refuses electrical
events, bounds work, preserves the no-crossing path and reports detected
endpoint branch changes only. It cannot certify hidden-crossing completeness.
Its canonical-cut regression and an observed earlier-excursion refusal are
required before aircraft wiring. No such policy is adopted into production.

### C08 refusal diagnosis and a separately versioned piece bound

Windows request `servo-wake-bound-probe-win-v4-20261117` passed ten diagnostic
checks with zero engine errors/warnings, complete evidence and confirmed cleanup.
Pool job `d64f165c33594dba85a64b4b99a3b52c`, attempt
`A-d2492fa2eb894aeaa9d8db4cde0b4349`, used snapshot
`04c22c43113c44679eabcc78e13611a3`. It reproduced the original 547 accepted
17-value float64 rows bit for bit, then the same C08 refusal. The base session,
record, tape, physical laws and existing refusal were retained; a bounded
observer was inserted immediately before that refusal. Earlier diagnostic
attempts retained a malformed record-identity lookup and the deliberate base
provider admission refusal; neither established a physical result.

At 2.28229166666667 s, an evaluated stage had speed 26.7027311200079 m/s,
authored lag length 0.445 m and outer timestep 1/240 s. The whole-tick ratio was
0.250025572284718; its half-width ratio was 0.125012786142359. This confirms
the whole-tick refusal as the cause of this retained failure. The checked log
SHA-256 is `853eb85024166d1778b1e6aafcf50b2720ef65e22202d0d7029d5254fa27c2ff`.

The next private policy is
`servo-arrivals-zero-half-stage-wake-max-piece-local-v1`. It retains the 0.25
sampled-stage refusal limit and applies it to the evaluated RK trial width,
capped by the mandatory half-tick partition. Initial k1 and accepted-boundary
checks use the maximum permitted half width. Reset boundary checks use the
candidate timestep rather than the previous simulation clock. The original
v17 selector and policy keep their whole-tick behavior; old/new checkpoints
cannot restore across policies, and exact replay selects the recorded policy
before setup. This is a separate solver candidate, not a changed numerical
acceptance rule or a stability proof. G05 remains open.

The private Windows batch
`servo-wake-max-piece-contract-c08-win-v2-20261117` passed with zero engine
errors/warnings, complete evidence and confirmed cleanup. Frozen snapshot
`81be790242124ecdbf7a040336ac81d5` has manifest SHA-256
`e3986e105f59a2c0ba34fb1aecb3f218ac5b8f85d646a7f60354de9f1b99942f`.
The new policy passed 77 checks (`7902ef0697ab4525ada29eda71be9b64`), including
actual RK/electrical-localization widths, boundary/reset clocks, selector locks,
cross-policy refusal and nine-row exact own-source replay. The unchanged
whole-tick policy passed its 112 checks (`b35b70a1ef1e49febb8c6354cec1a6b7`).
An earlier 77-check attempt retained two fixture failures: its fixed test speed
belonged to another geometry. The corrected tests derive speed from the actual
fixture's lag length; no production limit or numerical gate changed.

C08/throttle (`cd53109e5edd46ada0c619754657bb6d`) completed all three rates and
passed the independent unchanged numerical rules, initial mirrors and complete
1,441-row exact baseline. Evidence is under
`servo-wake-max-piece-c08-retained-v2`; `verification.json` SHA-256 is
`0c02f0d5f673b4a9e818bba154f46067f80cf4fc11a6c096280b9f7c20fedc70`.
Verifier `a1a47dd7147ca85ec121ed1963b0e2cb521bbeb3f30e3276f12fffc843298710`
requires both exact native prerequisite checks once, binds their report/log
hashes and verifies completed-source relocation inventories. Missing,
duplicate and absent-marker mutations were refused. Metric, gate, CSV and
cell-verification functions remain AST-identical to the prior collector.
The receipt remains `partial=true`, `complete=false`,
`numerical_campaign_pass=false`, `flight_qualified=false`, with 67 missing cells.

The unchanged complete matrix finished on that frozen source as request
`3af2eba922bd420abdfc27bd1eb303d9`, with zero checked errors/warnings,
complete evidence and confirmed cleanup. All 68 cells and their 1,441-row exact
own-source baselines were retained. The strict collector accepts 58 cells,
rejects eight numerically, and leaves two unresolved at its unchanged
charge-fraction noise-floor ambiguity guard. The numerical failures are
C03/throttle, C09/throttle, C10/throttle, C11/throttle, C12/throttle,
C13/rudder, C14/throttle and C15/rudder. C09/pitch and C16/pitch remain
unresolved. A successful checked process does not admit this campaign.
For C09/pitch, both adjacent floor branches would pass, but the unchanged
ambiguity guard still refuses the comparison. C16/pitch would pass below the
floor and fail above it; its reported ratio is 0.979219. Neither is resolved.

Evidence is under `servo-wake-max-piece-full-retained`; the diagnostic retention
receipt SHA-256 is
`47f453a1393e4208788cbc96ad1de090f124420abc4af4f29a3691e9c38eb4ef`.
It records a complete artifact inventory, incomplete strict verification,
`numerical_campaign_pass=false` and `flight_qualified=false`. The original strict
collector remains unchanged; the separate retainer preserves every rejected or
unresolved result instead of converting an exception into an accepted metric.

For the separate C03 investigation, the unwired observed-knot primitive passed
50 native Mac checks. Its actual-hub J provider passed 20 checks in request
`coefficient-branch-provider-unit-mac-v2-20261117`, job
`8252d004646c4fb883fde5215a649218`, with zero engine errors/warnings and confirmed
cleanup. It covers hub rotation, tilted axes, the exact 1 RPM branch and
shared/Ct-only knots; it refuses nonpositive inflow, table extrapolation and
contradictory electric/glow inputs. The provider must run at every observed
derivative stage and localization endpoint before an aircraft ablation. Neither
module establishes hidden-crossing completeness or flight permission.

Subsequent review found an accepted-cut endpoint defect not covered by those
50 primitive checks: shortened localization trials forwarded the original
owning-piece endpoint to the servo sampler. A valid split-clock round trip can
still leave a nonzero two-sum residual, so accepted k4 and next k1 could sample
different servo bits at the same cut. The private correction forwards the
validated shortened trial endpoint and retains the original endpoint for a
full-width trial. The native Mac counterexample failed exactly one of four
checks with the old helper (`f3a8afa15a7349a9978a641f235cb61a`), then passed
all four with the correction (`30eec3da06a14aadbe9148638e571c32`). The existing
50-check suite also passed (`d28f220ae3d04075a3d3c877ff29ae96`). All three have
zero engine errors/warnings, complete evidence and confirmed cleanup. The
before/after manifests differ only in `app/sim/coefficient_knot_step.gd`;
the corrected helper SHA-256 is
`60a72392f165334c3197c0c3e1c7c4ea1bba05286d256d1837b5c1b9c16cc0a4`.
Earlier check timeouts with empty engine logs remain infrastructure failures
and establish no code result. The aircraft ablation remains private and
unqualified: its initial full-source Mac unit failed to parse two test variables
inferred through a dynamic Node; explicit packed-float64 types correct that
fixture. The corrected unit passed 33 checks and nine-row exact own-source replay
on macOS (`440b84faab6d44a08b9954b4e0b69566`), with zero checked diagnostics and
confirmed cleanup. Its reported scope
may establish policy selection and numerical results only: the present wiring
does not retain actual knot-cut observations and cannot establish causal
localization from the aircraft artifacts.

The observed-only C03/throttle diagnostic then completed 240/480/960 Hz runs
and its full exact baseline on macOS (`56311a57ab8f49d68a59b30f0068c54f`).
Independent recomputation preserves the registered metric, convergence,
tolerance and ambiguity rules and accepts all seven metrics. The receipt
`servo-observed-coefficient-c03-mac-retained/independent-verification.json`
has SHA-256
`d3145b8f70d134d43aec0127c6b339a0b4ce129e6537a95b419dba37bbc94448`.
The verifier also binds the unique audit hash emitted by the checked native
log, its report/log artifact hashes, the exact selector and frozen entrypoint.
Six differences are below their registered noise floors; RPM has ratio
0.499625, so this is not evidence of global fourth-order convergence.

The native definition matches the registered case, but the raw record does
not: four crash-hull coordinates are `0.065616497644443` on Mac and
`0.06561649764444301` in the registered Windows record. Their cause and
cross-platform equivalence are not established. Source verification permits
only the recorded project-name isolation; all 1,059 frozen files and 378 audit
source hashes were checked. The diagnostic remains partial, has no actual
cut-observation or hidden-crossing certificate, and grants no flight permission.

A separate private guarded-cut candidate is in review. The observed-only
profile refuses ordinary stopped-rotor, nonpositive-inflow, extrapolation and
electrical-event states, so it cannot be the public flight route. The guarded
candidate treats only explicitly classified finite domain exits or actual
electrical events as reasons to retry the unchanged max-piece integrator from
the original state. Malformed state, arithmetic, clock, root-order and budget
failures remain fatal. Speculative derivative callbacks stop at the first
refusal, and retry restores the audited session caches. These are intended
contracts, not passing native or full-campaign evidence; the candidate remains
unintegrated and G05 remains open.

The first detached inspector fixture passed 62 native macOS checks
(`74999377b8d742bcbebfa8c9024881bf`), with zero checked diagnostics, complete
evidence and confirmed cleanup. Frozen manifest SHA-256 is
`5794a77f3e61e67f6190f95c0908f54fc4e52e4c8e2c99c2b8c41417ee419ba0`.
It covers every coupled coordinate, quaternion validity, electrical-domain
precedence, low RPM, actual hub projection, malformed tables/air and finite
unsupported inflow. Subsequent zero-initial-charge support and guarded-step
cache/event retry behavior still require native checks; this fixture does not
establish aircraft admission or baseline retry parity.

The subsequent guarded contract snapshot
`6c07a78c81cbf5d88fea5d5596f9d618f015142b4cdb138ed494b2d3e131b256`
passed 63 inspector and 42 detached retry checks on both Windows and macOS.
It includes zero initial charge, full state/event/cache byte parity with the
seven-cut baseline, callback shielding after an unsupported stage, typed
electrical retry, and fatal state/clock/cut validation. The retry budget test
targets the bounded knot primitive directly; it does not establish arbitrary
hidden-crossing completeness.

The full-source guarded snapshot manifest is
`ea5c55ee2ce04fe319981dabf710489f0c1f25b46e00a9aff3c68b87cc65eaad`.
On Windows it passed 85 real-session checks (`811a59aa07e44164b09ed745b3e826e5`)
and the unchanged 112-check old-policy suite (`369eec6d362f4f38b4539515dd879f95`).
The new suite includes actual kernel ticks for stopped rotor, zero/reverse
inflow, extrapolation and battery exhaustion, matching body/continuous/sampled
state, modes, events and caches against the baseline. It also covers both
four- and five-slot layouts, rollback without publication, policy-locked
checkpoints and nine-row exact replay. All checks have zero engine diagnostics,
complete evidence and confirmed cleanup.

A four-cell Windows diagnostic (`a971d358e51e488b8387620987232c59`) then completed
all rates and exact baselines. Independent unchanged strict checks accept
C03/throttle and C16/pitch and reject C13/rudder and C15/rudder. The registered
Windows record identities match. The collector's metric, ambiguity, source,
CSV, replay and cell checks are AST-identical to its strict predecessor; only
the explicit profile, selector, frozen source and prerequisite identities
change. This remains partial, with 64 missing cells and no numerical campaign
or flight qualification. The residual rudder failures have small absolute
pair differences but non-shrinking convergence; their rule provides no accepted
240 Hz error estimate. Preserve those failures while investigating actual law
boundaries; do not replace the rule with absolute tolerance alone.

## Guarded quarter-step diagnostic, 2026-11-17

The next private profile is
`servo-arrivals-zero-quarter-stage-wake-guarded-coefficient-cuts-local-v1`.
It adds mandatory rounded quarter/half/three-quarter cuts and explicitly permits
up to nine cuts, including servo zero/arrival boundaries. Wake guards use each
actual rounded piece width. Older research profiles retain their seven-cut
default. This is an empirical refinement candidate, not proof that every
coefficient or aerodynamic branch crossing was found.

Frozen manifest
`93556a71139cfe5a714eb2aa2f0f30effe969b0a94527cb3841356e68b682355`
passed 35 real-session quarter checks and 85 preceding guarded-profile checks
on Windows (`16be0ea26d5741a1aebd57f5aa7e4813`,
`5efc3539eeb24b328ab1a0047c172c38`), including nine-row exact replays.
The corrected detached cut-contract fixture separately passed 87 checks
(`7d21afb80862464d816712ada4756935`). The preceding fixture incorrectly
compared typed versus untyped empty event-array serialization; the correction
compares state bits and physical event contents separately and retains that
container-header counterexample.

The four-cell diagnostic (`f9bb65b3c2514df78f918f6d037922dd`) completed in
785.5 seconds with zero engine diagnostics and complete evidence/cleanup.
Independent strict verification accepts C03/throttle, C13/rudder, C15/rudder
and C16/pitch, including every own-source 1,441-row exact baseline. The retained
verification SHA-256 is
`984acb04ba6d62767a30a444a3796ce4ffd1a3007d2b988853ab40a29c18d03c`;
the verifier is `35eb382b343f2ae5a9d2ce35f6cc8c54e6063f69c1acc44799eb1604e126c828`.
Metric, ambiguity, source, CSV, replay and cell checks remain AST-identical to
the preceding strict verifier. Prerequisite markers now require exactly one
complete line, including their existing `flight_qualified=false` suffix.

This diagnostic remains partial with 64 missing cells. The unchanged 68-cell
campaign is running on the same frozen source under the existing exclusive
Windows checked-pool path (`5037de0315554f71b22568949d720aa2`). G05 remains open;
step-cost, actual-world launch and native target evidence remain separate.

The research source must not be integrated wholesale. Its non-wake default
changes Main's existing arrivals-only partition and cut preparation. Production
adoption must preserve `servo-arrivals-local-v1`, its three-cut default, original
v16 fingerprint and arithmetic, and select the distinct v17 profile before
setup. Old ORFL exact replay still requires its recorded solver/source and
engine; unchanged old arithmetic under a new source hash is not an old-hash
replay. Aircraft definition/publication/SourceRef identify the aircraft, not a
qualification receipt or a numerical profile. Future scratch and live launches
must bind and revalidate the same explicit profile and actual environment.
