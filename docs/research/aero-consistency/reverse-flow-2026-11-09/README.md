# Reverse-flow continuation repair, 2026-11-09

Owner: shared aerodynamics, D8b-R2d-R1. Baseline `5e673fbbdd4a2af94fb619eac87430d82f4d46c5`;
Godot `4.8.beta2.official.cafc17a19`, native Windows x86-64. The external audit examined
an older commit; its reverse-flow witness still reproduces on this baseline.

## Law and boundaries

`WingPolar.evaluate` receives the geometric angle and a separate positive strip
progression factor. Up to 45 degrees it retains the existing progressed table
exactly. From 45 to 90 degrees a smoothstep blends to the unscaled table; beyond
90 degrees the periodic separated law uses the geometric angle. For factors above
one, the unscaled reference lift uses the lower progressed attached fraction in
its coupled-base correction. This prevents reattachment during the blend, even
for valid authored tables retaining attachment above 45 degrees. Factors tending
to one converge to the unchanged shared-table path.

This is a numerical continuation policy, not a new measured aircraft calibration.
No aircraft coefficients, generated physics data, timestep or kernel branch were
tuned. Force, wake, clean-flap reference and spatial admission consumers share the
API; the C++ mirror uses the same operation order. Native preparation also admits
the stock Extra's existing separated-force pitch offset, which it previously
rejected, with finite/range/layout guards.

`Aero.LOADS_LAW` is now `section-plane-source-weighted-wake-velocity-v4`.
Live restore and exact replay reject the old law. An explicit candidate replay
admits only the known v3-to-v4 aerodynamic boundary with unchanged wake unit and
existing layout/admissibility checks. It does not migrate other laws.

## Numerical and integration evidence

| Check | Observed result |
| --- | --- |
| Stock reverse seams | All six strips independently cross their actual wrap boundary at roll rate 1 rad/s, then with pitch/yaw rates 0.3/-0.2 rad/s; ground effect both absent and supplied. Incoming wake is held fixed. Perturbations refine from 1e-4 to 1e-10 m/s on each side. |
| Historical negative control | The frozen baseline evaluator fails all 24 seam bounds. The original roll-only witnesses reproduce 3.598791785 N and 5.289152788 N jumps. Maximum over both rate cases: 5.296046943 N, 1.254195927 N m. |
| Candidate seams | Maximum refined component differences: 0.000753387 N and 0.000480603 N m. The remaining small discontinuity belongs to Godot's approximate `wrapf` endpoint snap; no exact mathematical continuity at that implementation threshold is claimed. |
| `test_wing_reverse_flow.gd` | 218 checks pass: force/wake consistency, refinement, both branches, factors 0.01 through 6, factor-one continuity, C1 joins, a penultimate knot at 89.9 degrees, delayed 50-degree detachment, monotone retention and coupled-base derivative. |
| Existing polar/session checks | 126 polar and 8 session checks pass. |
| Existing consumers | 774 separated-offset, 102 flap-offset, 7 Extra post-stall, 13 Extra handling, 8 checkpoint, 201 attached-spatial and 91 full-angle-spatial checks pass on the final candidate. |
| Flight logging | 4,391 checks pass, including explicit candidate migration, unchanged complete initial numeric state, exact-law refusal and incompatible-wake refusal. |
| Existing golden and trace consumers | Four original golden flights pass without rewriting; the 20-test application trace/metadata suite passes. |
| Companion admission | All nine retained accepted/current tapes remain byte-identical (2,881 rows each), and the [guarded solver rebind](../../ai-companions/AFC-02/rebinds/2026-11-09-b0a074e4-to-a4ee8de9.json) renews the source pin. Strict live profile and behavior checks pass 52 and 39 checks; seed/timing and Manager checks pass 83 and 53. A matching frozen tree passes real Home-to-Fly and a production quick flight with three active airborne companions, no test override, faults or crashes. Only proven identity pins change; controller gains remain unchanged. |
| Native components | Pinned GCC 13.3.0 strict-FP Linux/WSL build passes 593,941/593,941 byte-exact comparisons, including the stock Extra, deterministic delayed-detachment cases, wake, ground effect, and separated-offset refusal controls. The checked run is complete, source-stable and valid. This is component agreement only; the binary was not installed or promoted. |
| Ordinary tape | Baseline exact replay and candidate replay both complete 480 ticks. All exported numeric channels are identical; `first_divergence` is null. |
| Reverse tape | Baseline exact replay and candidate replay both complete 480 ticks. Candidate divergence starts at tick 1. This is an integrated tail-first rotating release, not a measured or pilot-qualified aerobatic maneuver. |

Both candidate reports explicitly contain `solver_changed: true`, `complete: true`
and `status: ok`. Candidate row zero retains the recorded historical `last_loads`;
new-law force samples start at tick 1. The two tapes use the same accepted stock
Extra data, complete body/internal initial state and post-conditioning input tape.
The aircraft input is frozen at SHA-256 `82776c0b9bda73162843225aa5abb7c8525b7d6c6e5d309beeb10146fa7222a7`:
a concurrent EX-14j data change is excluded from this solver experiment. The native
component run separately includes that newer stock input; both identities are in
the manifest.

The [evidence manifest](evidence.json) binds both compressed baseline ORFLs,
baseline/candidate CSVs, exact/candidate reports, comparisons and candidate sources.
The retained payload is approximately 1.1 MB, without images. The compressed native
oracle report retains its source/binary identities and component results; incidental
shared-host microbenchmarks do not establish performance qualification. Raw checked logs live
locally in `tmp/audit-physics-20261109/` and `tmp/godot-checks/audit-final-*`.

The [focused verification index](verification.json) also retains checked-report/log
hashes for the statistics, scenery, cache and optional-resource repairs from this
audit. The existing evidence summarizer validates all 32 selected invocations:
32 passed, zero skipped, zero failed/invalid. This selected collection is not a
full application/CI run. Native 1920×1080 Low-scenery and Prestorm captures remain
in ignored `tmp/audit-render-1080-{low,sky}-2/`; the GPU numerical probe is
`tmp/audit-render-native-probe-2/probe.json`. No images are added to Git.

The [companion behavior receipt](../../ai-companions/AFC-02/rebinds/2026-11-09-b0a074e4-to-a4ee8de9-behavior.json)
preserves the seven checked reports/logs, production launch status and matching
916-file runtime/configuration inventory used before promoting the two changed
behavior-source hashes. It establishes the exercised launch/admission paths, not
general behavioral or physical equivalence.

## Reproduce and interpret

Use the [checked runner](../../../tools/shared.md#one-godot-script) for
`res://tests/test_wing_reverse_flow.gd` and the existing consumer tests above.
The negative control loads the baseline `app/physics/aero.gd` from a disposable
path using the test's `--reference-aero=<absolute-path>` argument; its 24 orderly
assertion failures are expected, while engine/script errors are not.

Decompress the ORFL/CSV payloads into a fresh ignored directory. For exact baseline
replay, reconstruct the recorded commit in a disposable checkout using
[baseline-sources.json](baseline-sources.json): `exact` keeps Git blob bytes, `lf`
normalizes CRLF to LF, `crlf` normalizes then expands LF, and `mixed` expands only
the listed one-based `crlf_lines`. Verify every raw SHA-256 before importing the
pinned engine. The sorted URI-plus-bytes fingerprint must equal the manifest's
baseline solver hash. The two mixed-ending ground-vehicle scripts are unrelated
baseline inputs, not physics edits in this repair.

Run the matching checkout's existing [flight-log exact/candidate and comparison
commands](../../../FLIGHT-LOGGING.md#compare-a-physics-change). Candidate replay
uses the decompressed `aircraft-baseline.json.gz` and the corrected source. That
payload is an exact copy of the accepted baseline generated data, not an edited
aircraft candidate.
Never report candidate replay as exact solver equivalence or physical validation.

## Remaining qualification

Required full CI, complete native fleet/package admission, independent RC-aircraft
measurements and pilot acceptance remain separate gates. The older publication
fixture and strict fixed-brake input pin already reject the current baseline's
EX-14i sources/data; those historical proofs were retained rather than relabeled.
The fixed-brake tool's v4 identity-only overlay is derived from pinned original
bytes and passes its four focused overlay tests. The broader suite's pre-EX-14i
Extra input mismatch remains unresolved.

The local-wing circulation/closure validation gap from the audit remains a
separate research question. This repair does not relax its comparison screen or
claim new physical accuracy.
