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
