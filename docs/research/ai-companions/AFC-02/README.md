# AFC-02: Companion admission and diagnostic capture

The first qualified profile pair is the Jensen Das Ugly Stik 60 at the default
Club field. It allows experienced pilots to fly airborne circuits with one to
three aircraft. Stall, approach, cruise and entry speeds remain unknown;
ground/runway operations remain unqualified. The profile
loader checks the aircraft data, normalized field geometry, controller and
solver source identities, and Godot 4.7.2 at launch. Exported runs without a
matching source identity fail closed. Static nominal-corridor admission was added
after the source-profile and checkout captures below.

## Fixed-roster diagnostic capture, 2026-10-20

The [current capture contract](../../../AI-FLIGHT-COMPANIONS.md#diagnostic-capture)
adds a developer-only fixed-roster manifest and summary around existing `.orfl`
writers. `fleet_record.gd` observes the common clock after the manager and all
per-aircraft log callbacks. It closes before removal, reset, replacement or
destruction. Faults without an accepted `stepped` signal are closed after the
signal stack unwinds. Writer failures, crashes and shared damage changes prevent
cohort completion. No session, kernel, pilot or FlightLog code was changed.

The manifest records capture-local IDs/generation zero, admission and source
identities; the summary fingerprints the closed files. The format explicitly
disables fleet restore, decision replay and shared-world replay. Completeness is
writer closure/alignment, not a readback or replay claim. Selected script hashes
are not a full application build hash. Direct geometry edits without a damage
signal remain outside this fixed-world contract.

Verification is linked and fingerprinted in the [capture receipt](capture-receipt.json):

- [157 recorder checks](capture-tests-native.json): the player and one companion match an
  unrecorded fixture byte for byte for every one of 260 accepted ticks, including
  inputs, body/previous state, auxiliary/continuous state, modes and loads. Both
  saved files pass the existing full reader and exact replay for 260 intervals
  (261 rows each). This crosses the writer's 240-row flush boundary.
- A short three-companion fixture closes all four files at common tick 3, with
  four rows each. Tests verify stored hashes, byte sizes and footer extents,
  duration closure, pause, detached status, no overwrite, refused reconfiguration,
  removal/reset/reconfiguration, tree exit and a detached manager's destruction.
- Writer failure and crash/fault boundaries are injected; shared damage uses a
  valid scenery damage record and its real signal. These are software failure
  path checks, not physical crash validation or a real disk-full/power-loss test.
- [28 CLI/config checks](checks/afc-capture-config-h0nm8z95/report.json) and
  [53 manager regression checks](checks/afc-capture-manager-njr9cs5h/report.json)
  pass. The [reviewed shell run](checks/afc-capture-shell-reviewed-laqfjrod/report.json)
  covers Home/Pause, direct capture startup, the fleet HUD, F10/F11, same-tick
  markers, restart without overwriting capture files and non-persistence of the
  output path. Review also closed the synthetic electric-demo eligibility gap.

Focused tests are discovered by the existing `app/test.sh` loop. Each checked
receipt records its exact invocation and completion marker; the recorder test
accepts optional `--out=<new absolute JSON path>`. Its generated captures remain
under ignored `tmp/` for inspection; the source test reproduces them. The retained
JSON/report/log files provide the portable evidence, not the local binary paths.

The first shell invocation passed its assertions but failed engine diagnostics:
the test helper stopped live AI audio before draining frames. Holding the fixture
before that artificial drain corrected the teardown. A subsequent passing run
was extended with the electric-demo refusal checks; only the reviewed run above
includes them. The known maple wind warning remains. Draft recorder runs caught
a multiline parser error and an incorrect test assumption about row-count
placement; those runs are not qualification evidence.
The earlier [direct Linux/WSL test output](capture-tests.json) also reports
157 passing checks. The native Windows checked run linked by the capture receipt
is the final integration evidence; no cross-platform trajectory equality is claimed.

The existing writers still perform synchronous I/O and the wrapper hashes files
at close. Four 512 MiB stream limits and a 120-second duration cap bound the
diagnostic, not its latency. No aggregate 128 MiB claim, recording-performance
pass, full fleet replay, physical validation or full application-suite pass is
made here. The earlier flight qualification and population ceiling are unchanged.

## Static circuit admission, 2026-10-20

`airspace.gd` checks actual session geometry once before the manager replaces a
roster. Continuous annulus/AABB intersection removes the gaps of point sampling;
positive-up altitude intervals are tested separately for each requested slot.
Rotated boxes and capsules use conservative enclosing bounds. Cached bounds must
enclose reconstructed shapes, with finite dimensions and normalized box headings.
The checker scans at most 10,000 proxies; it hashes the consumed bounds separately
from the supplied world identity and ignores spatial bins for this launch check.

The [complete Club inventory report](static-airspace.json) admits all three slots
against **6,031 proxies** and the default lake. The accepted contact-geometry
sphere is **0.898964 m**. With estimated 10 m radial / 2 m vertical tracking
allowances and 2 m obstacle clearance, the radial interval is **67.101–92.899 m**
around N199/E0. The lowest inflated height interval is **30.101–39.899 m**;
the other slots are 20 and 40 m higher. The minimum vertical gap to a horizontally
overlapping proxy, after all allowances, is **6.867409 m**. Ground/water uses a
global analytic upper bound, **0.007 m** in this fixture. No terrain sampling is
used to infer a continuous bound.

The pilot station and person/shelter/pavilion proxy footprints have a 30 m
horizontal exclusion policy. The inventory contains 62 protected proxies, not
62 distinct zones or people. This policy is an AFC estimate; the field does not
have complete authored pits-zone metadata. The radius encloses accepted hull,
wheel support and propeller contact geometry, not every rendered mesh vertex.
Empty collision inventory explicitly disables scenery checks while retaining
terrain/lake and pilot-station checks.

The profile now says `requires_session_check`; a successful source-profile load
alone cannot claim obstacle clearance. Failed admission preserves the previous
fleet, callbacks and accepted report. Off bypasses the gate. Reports are detached
launch diagnostics, not a tick-time service. Avoidance can command altitude changes
outside the estimated corridor: full-flight containment, recovery, moving hazards,
general field keepouts and dynamic encounter qualification remain open.

Verification:

- [48 airspace checks](checks/afc-airspace-unit-j4p9_9ti/report.json): real inventory,
  low/tall obstacles, per-slot gaps, inner hole, enclosing boxes, exact tangencies,
  thin obstacles between samples, capsules, exclusions, malformed data, stale
  identity, and 720 independent angular contact witnesses.
- [53 manager checks](checks/afc-airspace-manager-f_wcjb9x/report.json): obstruction
  with unchanged supplied identity, atomic refusal, detached diagnostics and Off
  bypass, alongside existing session/driver parity and shared-world tests.
- [30 source-profile checks](checks/afc-airspace-profiles-final-0h2f2775/report.json).
- [Home/Pause integration](checks/afc-airspace-shell-final-krjmtjox/report.json):
  passed with no engine errors; the pre-existing maple wind warning remains.
- [Accepted-flight trace run](checks/afc-airspace-equivalence-final-t1uzztmd/report.json)
  and [comparison](airspace-flight-comparison.json): 0, 1, 2 and 3 companions,
  240 warmup plus 2,400 measured ticks each. Every measured player/AI state and
  command fingerprint matches the retained
  [pre-clearance baseline](../AFC-00-R1/candidate-profile.json). This is software
  equivalence for that tape, not additional physical or performance qualification.

[Final source and evidence receipt](static-airspace-receipt.json). Run the tests
through `tools/godot/run_checked.py`; each linked receipt contains the exact
command and required completion marker. Optional `--out=<new path>` on the
airspace test captures the three-slot report and adds one file-write check. The
test refuses to overwrite existing evidence. `app/test.sh` discovers it through
the existing `tests/test_*.gd` loop; the full application suite was not run here.

The first manager invocation had a duplicate test-local variable name, and the
first profile runner used the wrong required completion string. Both were corrected
before the passing captures. The first shell/trace captures also hit a concurrent
Timber visual-helper parse error; those diagnostics invalidate their success
markers. The other work corrected the helper before our patch applied; this
increment changed no Timber files. Only the `*-final` shell/trace receipts above
establish passing integration. The initial `airspace-flight-traces.json` is retained
as failed-run evidence and must not be used as qualification.

## Earlier source-profile evidence

The [canonical profile receipt](canonical-profile-receipt.json) records the
then-current source pins and 29 focused loader checks. The earlier
[raw-identity receipt](profile-receipt.json) is retained as a historical
snapshot; it predates the checkout-independent solver qualification hash. The
separate [pilot matrix evidence](../pilot/README.md) records the existing
120-second circuit scenarios.

Launch integration and the full application shell checks are recorded in the
[manager report](checks/profile-manager-canonical-yp6wa77x/report.json) and
[shell report](checks/profile-shell-canonical-tmj4mqva/report.json). The manager
report covers 47 checks; the shell report passed with no errors and records one
pre-existing maple wind warning.

The later [evidence checkout check](evidence-checkout.json) confirms exact bytes
for the canonical profile log/report, manager log/report, integration receipt
and pilot CSV in fresh `core.autocrlf=true` and `false` clones. Its disposable
commit used the current evidence-file attributes, and the main repository index
remained unchanged.

Final admission review added a 240 Hz guard because the simulation derives its
step duration from `Engine.physics_ticks_per_second`, while this pilot is qualified
only at 240 Hz. The [rate-guard receipt](admission-rate-receipt.json) pins the final
sources and passing **30 profile / 47 manager checks**, including refusal at 120
and 480 Hz. This launch-only guard was added after the lifecycle/endurance capture;
it does not change the accepted 240 Hz flight. Earlier receipts retain their
original source hashes and test counts.

## Checkout comparison

The original [fresh-clone check](checkout-check.json) records the raw-hash
migration assessment. The follow-up
[canonical checkout check](checks/canonical-checkout-comparison.json) repeats
the disposable commit and fresh clones after the profile metadata changed.
With `core.autocrlf=true` and `false`, the aircraft JSON, field JSON, pilot
source and both AI profile JSON files have identical SHA-256 hashes in both
clones and the current worktree. The `.gitattributes` blob is identical, and
the main repository index hash remained unchanged.

At this checkout checkpoint, the runtime profile pinned the canonical solver qualification hash
`1526c984…8f33b7e`: strict UTF-8 decoding, CRLF/lone-CR to LF normalization,
then SHA-256 over each sorted resource path and normalized source. This hash
matches all 133 sources across both clones, with no per-file differences after
normalization. `FlightLog.solver_identity()` remains unchanged and is reported
separately as a raw-byte identity; it differs between clones (`939bea1d…179ec48c`
with `autocrlf=true`, `c4b300e7…1f0242ef` with `autocrlf=false`) because 54
source files have different checkout bytes. Regression checks reject code drift,
unknown normalization, and empty or missing source sets. This is software source
qualification, not a claim of cross-platform trajectory equivalence or new
physical validation. No solver code or additional `.gitattributes` rules were
changed for the solver identity. Captured evidence byte-preservation rules were
added afterward and are covered by the separate check above.

## Solver-only merge compatibility (AFC-02-R1), 2026-10-20

The Extra's opt-in fuselage side force changes `aero.gd` and `aircraft_data.gd`,
so the merged 133-source qualification hash is
`b9911cc9166e1cb8c523cfa61c2b4fb17dd0ac727384d9622ebf00afd9f16f30`.
The accepted Stik declares neither `body_cy_beta` nor `body_crossflow_area`:
the loader adds neither field and the new force branch remains inactive.
Stik data, the pilot and the qualified circuit scope are unchanged.

The [merge receipt](solver-merge-15f6efc7/receipt.json) identifies the isolated
upstream and merged sources, recordings, CSVs and checked runs. Fresh player and
companion recordings each contain 260 intervals: upstream exact replay is complete
with `solver_changed=false`; the same-data merged candidate has
`solver_changed=true` and a byte-identical CSV. Two retained AFC-04-R2 crossing
tapes also produce byte-identical upstream/merged candidate CSVs for all 2,880
intervals each. Candidate runs remain open-loop experiments, not exact replay.

The profile and its regression pin change together; source-drift refusals, strict
UTF-8/LF normalization and the 133-source assertion remain. Profile, manager,
recorder, shell and the three-second pilot heading checks pass on the isolated
merged application. This parity supports retaining the existing 148-check pilot
matrix as the qualification basis; that matrix was not rerun. No new activity,
physical-validation, moving-encounter or performance acceptance is claimed.

## Controller dependency and fresh Windows checkout

The [checkout verification](controller-dependency-checkout/verification.json)
qualifies snapshot `16a6d9566e1fac0ca7ac96ce6e085beb9fe2c643`, plus the explicit
Git line-ending corrections recorded there. The profile now binds both the
reachable-bank controller (`363942b4…259ed`) and its actual circuit base
(`1d5699fa…615c`). Missing, additional, malformed or changed dependencies refuse
admission. This closes the gap where a wrapper's unchanged hash could otherwise
hide changed inherited guidance.

A fresh local Windows clone with no Godot cache imported successfully. All
**1,200 scripts parsed**, with zero failures and no source drift across the
interrupted/resumed sweep. All **16 companion regression groups passed**:
1,696 numbered assertions, plus the dialog and shell checks. The final shell run
has no engine errors and retains three existing tree-material wind warnings.
This is a parser sweep and the companion suite, not the entire application's
test suite, a packaged export or physical validation.

The initial checkout exposed two byte-identity failures. Git converted the new
circuit base to CRLF, correctly causing source-profile refusal. It also converted
`mountains.json`, invalidating the existing settlement bake's source hash despite
identical parsed JSON. Explicit LF rules for both files fix fresh checkouts;
the disposable clone regenerated them through Git, and the settlement generator's
`--check` passed. No generated geometry or physical aircraft data was edited.
The receipt preserves both failures, an intermediate runner-marker failure and
the final passing runs. Retained source snapshots use `-text` to preserve their
original evidence bytes. Linux/macOS, export and pilot-review gates remain open.

## Five-source solver merge and controller promotion, 2026-10-21

The [five-source bridge](solver-merge-2f4f35c0/README.md) covers normalized solver
identity `2f4f35c0…cff4bfa`, including the earlier optional body-side-force changes
and subsequent Glow installation, propeller and bounded-trim changes. The accepted
Jensen Stik has none of the added optional inputs. Its trim and initial state match;
all six retained calm crossing tapes produce byte-identical candidate CSVs, and
the same-world closed-loop fixture matches its baseline. Candidate replays report
`solver_changed=true`; they are not exact replay of the changed solver.

The bridge deliberately keeps the frozen R4 pilot/profile and does not establish
loader admission. The separate [promotion receipt](../AFC-00-R3/promotion.json)
records the actual runtime pilot/profile updates and focused integration checks.
The runtime pilot is now `3842cbdba…1f024`, with the unchanged inherited circuit
base. Its pure-score early return has independent differential and flight evidence.
The source guards remain strict, and no aircraft/activity/count scope is expanded.

## Performance-only solver re-bind `29ac7fe9`, 2026-10-22

Five exactness-proven performance commits (glow feed reuse `e983eb49`/`126fbc47`,
P-51 k1 preview `f86d0759`, hull and lake contact skips `67ba2835`, `e9e07e68`,
`30b54621`) changed eight physics/simulation sources and moved the normalized
133-file identity from `2f4f35c0…cff4bfa` to `29ac7fe9…bb75a047`. A disposable
copy of the current app with only `app/physics`, `app/sim` and `app/failures`
restored from `fc726623` reproduced `2f4f35c0…`. All nine retained tapes
(six AFC-04-R2 crossings, three AFC-04-R1 parallel threats) replayed in candidate
mode on both sides with `complete=true` and byte-identical CSVs. The Jensen Stik
profile and its test now pin `29ac7fe9…`; profiles 37/0, manager 53/0, record
156/0, lifecycle 653/0, presentation 13/0 and airspace 48/0 passed. Candidate
replays report `solver_changed=true`; this is parity on these tapes, not exact
replay or a scope expansion.

## Electric hub-inflow solver re-bind `69bf5c78`, 2026-10-23

EL1d-R1 (`c0fe45fd`) moves electric propeller inflow to the hub in
`physics/dynamics.gd`, `physics/propulsion.gd` and `sim/flight_session.gd`;
the accepted Jensen Stik is not electric. The identity moved from
`29ac7fe9…bb75a047` to `69bf5c78…9ffc7290`. Two disposable app copies differed
only in `app/physics`, `app/sim` and `app/failures` (base from `7bb1d9f5`).
Both used the pre-F4U `wheel_profiles.json` (`98f4c84f`), because adding the
F4U profile changes the file identity that retained-tape checkpoints validate;
the Stik wheel rows are unchanged. All nine retained tapes replayed in
candidate mode with `complete=true` and byte-identical CSVs. Profile and test
now pin `69bf5c78…`. This is parity on these tapes, not exact replay or a
scope expansion.

## Re-bind gate and tool (AFC-02-R3), 2026-10-24

The solver pin now has one gate, `tests/test_companions_profiles.gd`; the other
companion suites test logic on the current identity (editor builds only).
[`tools/companions/rebind.py`](../../../../tools/companions/README.md)
automates the A/B above: it replays the nine retained tapes on the accepted and
current solver and re-pins only when every CSV is identical. Receipts are in
[rebinds/](rebinds/). Candidate replays now adopt the current
`wheel_profiles.json` file identity but still refuse a change to the Stik's own
wheel profile. Negative checks: a disposable 0.1 % density mutation in
`physics/aero.gd` changed all nine tapes (up to 0.68 N, exit 1, nothing
re-pinned); a disposable Stik wheel-row change made replay refuse the
checkpoint.
