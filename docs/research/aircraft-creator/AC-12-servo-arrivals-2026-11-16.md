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
Every RK trial, including rotor/battery root refinements, must have distinct
represented start/midpoint/end and normal positive RK weights. Truly unresolved
trials still refuse atomically; no epsilon cut merging or target snap is added.

Time-dependent generic laws can consume origin and offset separately. Adding
them into one float cannot preserve sub-ULP phase. The aircraft adapter therefore
admits only the unchanged base session/environment/weather and turbulence provider
under its calm/reference domain, where the accepted force laws are independent of
absolute stage time. Substituted or derived providers are refused. Local event
order is checked before conversion; distinct local events whose absolute ordering
cannot be represented are refused, rather than relabelled simultaneous.

The follow-up requires a fresh frozen source identity, strict independent verifier
and all 68 fresh full baselines. Nothing from the failed prefix is reused as a pass.
