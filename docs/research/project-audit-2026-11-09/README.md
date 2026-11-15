# Project audit of 2026-11-09 — original evidence and current-source reconciliation

Intake and source review: **2026-11-15**. The two original audit rounds examined
[`45d86d250f6e38a3d9b60d30c01bdc2396571efe`][baseline] using
**Godot 4.8.beta2.official.cafc17a19**. This reconciliation examines
[`ad21070798bfb9658785576a9c0b8bfc9a71fc7f`][reviewed], 151 commits later.

The original five findings have received corrections within documented scopes.
The three round-two defects remain in the inspected source. Historical execution
results establish the original witnesses; this intake did not rerun the simulator
against the newer commit. The current source, retained remediation evidence and
observed CI status are separate evidence classes.

The [remediation follow-up](#a35-remediation-follow-up) records
the subsequent F06–F08 corrections against main `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`.

The [external-audit pending queue][pending] remains the authoritative home for
remaining actions. Its source **A34** identifies round one; **A35** identifies round
two. The [implemented ledger][completed] owns delivered corrections. This folder
preserves the reports, explains their relationship to the newer source, and links
the existing owners; it is a dated review, not another active backlog.

## Contents and provenance

| Deliverable | Contents | Intake check |
| --- | --- | --- |
| [Round-one report](originals/OpenRC_Simulator_Audit_45d86d2.pdf) | 12 pages; F01–F05, additional research questions and rejected claims | Saved report copied without editing |
| [Round-one evidence](originals/OpenRC_Simulator_Audit_Evidence_45d86d2.zip) | Original probes, nine checked report/log pairs, 69 pinned production source copies, inventories, verification and replay helpers | 108 checksummed files; original receipt/source verification passed |
| [Round-two report](originals/OpenRC_Simulator_Audit_Round2_45d86d2.pdf) | Eight pages; F06–F08, mathematical derivation, controlled interventions and secondary observations | Saved report copied without editing |
| [Round-two evidence](originals/OpenRC_Simulator_Audit_Round2_Evidence_45d86d2.zip) | Seven checked report/log pairs, 27 pinned source copies, two one-line diagnostic variants, verification and replay helpers | 63 checksummed files; receipt/source/variant verification passed |

[original-artifacts.json](original-artifacts.json) records each delivered file's
size and SHA-256. The ZIP hashes match the original audit records. The PDF hashes
identify the retrieved saved versions; they are not a claim about any earlier
pre-upload representation. Original evidence retains its historical paths and
timestamps. No report, log, source snapshot or diagnostic patch inside the ZIPs
was rewritten for this intake.

The archive checks establish internal byte integrity and source identity. They
do not independently rerun or validate the reported experiments. In round one,
seven checked reports passed and two strict gates completed with nonzero exits.
In round two, passing witness assertions demonstrate the stated defects or
controls, not that the underlying game behavior is correct.

Additional records:

- [Current repository and CI review](current-state-2026-11-15.md).
- [Finding-by-finding source identities](source-review.json), including original
  and reviewed Git blob IDs and the limits of whole-file equality.
- [Observed GitHub CI and open-PR snapshot](ci-status-2026-11-15.json).
- [Integration validation](integration-checks.json), limited to this evidence and
  documentation change.

## Findings crosswalk at the reviewed commit

| Source / finding | Current disposition | What the evidence supports |
| --- | --- | --- |
| A34 / F01 — reverse-flow wing discontinuity | Corrected; retained regression evidence | Physical angle and stall progression are separated; the production evaluator, wake consumers and native mirror retain the reviewed repair. No fresh engine or physical-validation claim. |
| A34 / F02 — graphics-dependent obstacles | Corrected for the reported quality/hardware choices | Collision uses the selected full scenery layout; collidable objects remain visible across quality settings. Explicit scenery selection remains a scenario choice. |
| A34 / F03 — stale statistics lock | Corrected for qualified version-2 leases; legacy limitation remains | Integral JSON numbers are accepted and constrained stale-lease recovery exists. Old three-field records and unsupported/ambiguous scopes deliberately remain read-only. |
| A34 / F04 — eager optional resources | Reported resource paths corrected; broader costs unqualified | The six material maps and selected track, lake-audio and engine resources load on use. This does not establish whole-application laziness or a current RAM/VRAM saving. |
| A34 / F05 — cloud-layer seed mismatch | Original mismatch corrected; transition admission is separate work | Eligible layer seeds reach distinct cache slots and the shader selects by matching seed. Existing A28 / DT-MAC06b work owns capacity admission during cloudy-to-cloudy transitions. |
| A35 / F06 — swept lake normal sign | Present by current source inspection | Positive-down gradients have the wrong horizontal signs in the swept helper. Original full-tick false-crash witness and sign-only control are retained. |
| A35 / F07 — aircraft tolerance omitted from lake sweep | Present by current source inspection | The session prepares model-specific limits but does not forward them to the swept query; shared constants decide its energy/depth policy. |
| A35 / F08 — repeated quarantine blocks statistics | Present by current source inspection | An existing fixed quarantine filename causes immediate failure, even for identical damaged bytes, and makes the owned store read-only. |

## Round-one corrections and remaining limits

### F01 — retain the repaired reverse-flow law and its evidence

The old witness measured a force difference of **3.59879 N** and a roll-moment
difference of **1.24661 N·m** across a near-identical reverse-flow state pair.
These are measurements at the original commit, not current values.

Current [`wing_polar.gd`][polar] keeps the progressed forward-angle law through
45 degrees, blends to the physical-angle law by 90 degrees, and uses the periodic
physical-angle continuation beyond that. [`aero.gd`][aero] passes angle and
progression separately to force and wake consumers. The native mirror uses the
same law. These files and the reverse-flow regression have the same Git blobs as
the repair recorded in `0ab4d1e3b6bf052133a5456cbd3d73924646a055`.

The existing [reverse-flow repair record][reverse-repair] retains 218 regression
checks and 593,941 native component comparisons. Its small engine `wrapf` endpoint
residual, native-installation limits and lack of physical calibration remain
explicit. The intake does not promote that historical candidate evidence into a
fresh run on `ad210707`.

### F02 — preserve scenario physics across visual quality

[`collision_setup.gd`][collision-setup] now builds the full selected layout and
lights without filtering collision by quality. The scenery builder keeps
collidable objects in its visual selection, and circuit Automatic selection is
consistent across hardware/detail choices. The
[landscape collision regression][collision-test] checks complete world equality
and the bench case, rather than only object counts.

The original counts and terminal bench sweep remain useful negative controls.
They are not measurements of the current scene. The explicit scenery-off option
still changes the selected scenario. The existing ledger's bounded native visual
evidence does not qualify every scene, adapter or performance condition.

### F03 — distinguish new leases from legacy lock recovery

The current [store lease parser and recovery path][store-lock] accept finite
integral JSON numbers and require a qualified matching scope, an available UDP
lease, an absent process and stable lock contents before reclamation.
[Flight-statistics documentation][statistics-guide] limits automatic recovery to
qualified Windows/Linux scopes. A pre-upgrade three-field record remains
deliberately ineligible; the regression explicitly expects read-only behavior.

The retained 84 cross-process checks per qualified host belong to the existing
repair evidence. Supporting old ambiguous locks or another platform needs an
explicit recovery policy and its own evidence. Removing fail-closed safeguards
solely to make a stale-file test pass would not establish safe ownership.

### F04 — verify actual selected paths before claiming savings

The reported six-map material module now stores resource paths and loads maps
when configured. Track view creation follows its empty-track guard; lake audio
and the selected engine scene also load on use. The
[optional-resource regression][optional-test] checks disabled cache states and
enabled binding/preparation in bounded fresh-process fixtures.

There is a related current path worth measuring: the selected ground activity
preloads its effects scripts before checking `enable_vehicle_effects`; both
scripts preload the smoke texture. The application itself selects that ground
scene lazily, and other consumers may share the texture. Therefore neither a
default-airplane cost nor incremental effects-off residency has been established.

The original **21.66 MiB** was an isolated, headless Godot-tracked module-load
increment, including dependencies. It is not a measured current saving, process
RSS reduction, VRAM saving or frame-rate result. Follow-up should first measure
off/on cache residency on actual activity routes, then matched cold/warm startup,
peak/retained memory and hitches on target hardware.

### F05 — keep seed binding separate from cache admission

Current [atmosphere binding][atmosphere] requests actual eligible layer seeds.
The cache binds up to four distinct seeds and the shader matches each layer to
the corresponding slot, with an analytic fallback. The
[layer regression][cloud-test] includes a three-layer prestorm and synthetic
validated images; it is a binding test, not a GPU bake or performance benchmark.

Old retained tiles can still fill all four slots during a direct cloudy-preset
transition. The [existing desktop handoff][desktop-handoff] already assigns that
admission problem to A28 / DT-MAC06b. Retain live sky/ground-consumer transitions,
stale-completion handling and native image/timing checks under that owner instead
of counting the same issue again as the original seed mismatch.

## Round-two defects retained for implementation

### F06 — use the positive-down surface gradient consistently

For a lake or bank graph in north/east/down coordinates,

```math
D=h(N,E),\qquad
\mathbf n=\frac{(h_N,h_E,-1)}{\sqrt{1+h_N^2+h_E^2}}.
```

This normal is orthogonal to both plane tangents `(1, 0, h_N)` and
`(0, 1, h_E)`. The current [swept collision helper][lake-normal] instead uses
`(-h_N, -h_E, -1)`. Its dot product with the first tangent is `-2 h_N` before
normalization, so the error is geometric and cannot be repaired by tuning an
impact threshold. The distinct hull-contact helper already uses the correct
conversion; its tests do not cover the swept helper.

The original controlled bank case reported **8.057085 m/s** and
**5.296564 J/kg**, while recomputing with the geometric normal gave
**0.447301 m/s** and **0.016943 J/kg**. A sign-only intervention removed the
false terminal event in one accepted production tick. It did not establish a
completed landing or later trajectory.

`lake_collision.gd`, `lake_surface.gd` and `hull_contact.gd` retain their old Git
blobs, but the surrounding `flight_session.gd` changed. Thus the sign defect is
present in inspected code, while a current integrated numerical result still
requires a new run. The pending queue specifies plane-gradient/tangent checks,
both horizontal slope signs, point angular velocity, water/bank cases, sampled
and fixed-mass entry points, and full-session controls under the existing ground,
surface and crash owners.

### F07 — forward aircraft policy to every swept-bank decision

The X99 data specify **12.5 J/kg** and **0.12 m** hull limits, explicitly estimated
pending physical drop tests. The current session prepares that tolerance for
HullContact, but its [lake-sweep calls][lake-call] omit the policy.
[`lake_collision.gd`][lake-policy] uses shared **2.5 J/kg** and **0.08 m** defaults
for the relevant energy, depth and early/fallback decisions.

In the original stopped-motor X99 witness, the unmodified tick terminated at
**2.840178 J/kg**. The sign-only control still terminated at **2.862489 J/kg**.
A threshold-only diagnostic survived that tick without a lake event, hull
terminal, gear collapse or prop strike. This isolates the energy-policy path
from F06. It does not separately execute the depth mismatch.

The diagnostic globally changed a fallback constant to 12.5; that is retained
as an experimental intervention, not a production fix. Implementation must
carry the prepared per-aircraft policy through both swept entry points and all
early/deep-contact decisions, while retaining defaults for aircraft without
overrides. Acceptance needs separate energy and depth boundary cases, tolerant
and default aircraft, and combined F06/F07 controls. Numerical agreement with
authored limits does not validate the aircraft's real impact tolerance.

### F08 — make quarantine recovery repeatable without losing evidence

The current [`_quarantine_bad_snapshots`][quarantine] returns false immediately
when the fixed quarantine filename for an invalid slot already exists. It does
not compare the damaged bytes. The opener then sets `writable=false` despite
owning the writer lock, so later commits and deletion are refused. This is a
different cause from F03.

The original isolated Store fixture preserves a valid alternate generation and
demonstrates the failure twice: immediate no-write reopen, and a stronger case
with successful healing, normal reopen and healthy commits before another
same-slot corruption. Both damage events deliberately use identical bytes.
The first sequence alone does not characterize every normal service startup,
because service recovery can write a healed slot. The second controls for that
objection. Valid history remains present; the finding is loss of write/recovery
availability, not demonstrated historical-data destruction.

A repair should recognize already-preserved identical bytes and safely preserve
new damaged contents under bounded collision-safe naming. It must integrate
with the existing deletion-fence purge so additional copies cannot restore
deleted history. Current tests cover first corruption and another deletion
scenario, not these repeat-corruption sequences. The pending queue retains
immediate reopen, healthy healing/re-corruption, distinct damaged bytes,
write-failure, owned-lock, valid-history and deletion controls.

## A35 remediation follow-up

The GP-10b / UI-FS-03 remediation branch incorporates this evidence intake and main
`e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. The reviewed integration baseline is
`d1e55d5b9c81d33f8ebf4a75528a67bd87b2d70a`.

- **F06.** The swept normal uses `[h_N,h_E,-1]` for positive-down bank and water
  gradients. Tests cover both slope signs and axes, plane tangents, wave normals,
  rotating point velocity and the original Stik accepted-tick scenario.
- **F07.** Both swept APIs accept the prepared HullContact policy. The session
  forwards that policy through fixed and sampled mass queries. Energy, separating
  depth and final crush decisions use the aircraft limits in soft-bank mode.
  Regression cases bracket 2.5/12.5 J/kg and 0.08/0.12 m, retain hard-bank and water
  behavior, and exercise the original stopped-propeller X99 tick. Lake-enabled
  metadata and checkpoint configuration identify the corrected swept law.
- **F08.** Quarantine compares existing bytes before copying. Each snapshot slot
  has eight bounded names, including its historical unsuffixed name. Identical
  corruption reuses preserved bytes, distinct corruption uses an available name,
  and copies require successful write and explicit readback. Exhaustion or failed
  preservation keeps the recovered history read-only. The deletion-fence purge
  enumerates the same names. Tests cover repeated, distinct and empty damage,
  healthy commits, competing ownership, interrupted preservation, exhaustion and
  later history deletion.

An independent read-only review identified and resolved a sampled-test setup
error, hard-mode separating-depth handling and empty-file readback ambiguity.
Terra review workers did not initialize; the completed review used the session's
available model.

The frozen Windows baseline completed 41 lake-session checks with exactly the
two new F06/F07 expected-survival assertions failing. Its checked report has no
engine errors or warnings. The original F08 witness also reproduces on the
unchanged baseline store in an isolated Linux/WSL project. The corrected store
passes 209 checks through the checked runner on that private Linux runner.

The standard companion rebind compares all nine retained tapes against the
complete accepted source baseline. All 2,881 CSV rows per tape remain
byte-identical. The generated receipt renews the profile from `a81c2b2d` to
`4ff26331`. The profile consumer passes 52 checks. [Companion comparison](../ai-companions/AFC-02/rebinds/2026-11-15-a81c2b2d-to-4ff26331.json).

The [verification record](remediation/verification.json) retains source identities,
checked report/log pairs and compressed fleet captures. The corrected candidate
passes the lake collision regression, 47 lake-session checks, 38 sampled-contact
checks and 207 deletion-boundary checks. The fleet policy passes 598 checks and
its Python campaign tests pass 66 tests.

Both baseline and candidate fleet captures pass 170 checks. All eight baseline
rows reproduce the existing Linux pins. The [452-check typed comparison](remediation/fleet-comparison.json)
preserves row, refusal, physical frame, setup, outcome and ownership data. Only
the embedded checkpoint configuration changes. The active V5 live-configuration
pins record that change. The original and candidate capture bytes are preserved
in `baseline-fleet.json.gz` and `candidate-fleet.json.gz`; decompress each into a
fresh scratch path before rerunning the retained `compare_fleet.gd` recipe.

The [publication source renewal](remediation/publication-rebind.json) verifies all
eight Windows/Linux baseline/candidate captures from [the capture workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43742060049).
The strict packer preserves every retained shaft/weather frame and event array.
The promoted fixture has SHA-256 `7b51caf56d64d8944fab076e4a2faa85cbc14ff66e22c1512359eda9cb055e50`.
Its Linux adoption tests pass 214 shaft and 313 weather assertions. GitHub retains
the complete CI results for the integration commit.

Shared-pool attempts retain cold-import timeout, disk-exhaustion and transport
diagnostics. A private WSL runner provides the isolated Linux fallback. These
checks establish the stated software scopes. The X99 limits retain their
estimated physical provenance.

## Other ideas and negative findings retained

- **Local-wing closure research (R02).** The old strict yaw comparison had one
  failure in 19 checks, with a 7.573% difference against a 7% screen; its
  independent derivative converged. This is a model-comparison question, not a
  measured 7.573% physical error. The [existing lateral/directional study][yaw]
  owns it. No fresh AVL campaign or current strict-test result is claimed here.
- **Rudder allegation rejected.** The old 25.42-degree claim did not survive
  the audit's clean run: the recorded 24.88/24.08-degree cases passed their
  handling criteria. The retained strict invocation still failed an
  unconfigured FakeEdgeTX fixture. Keep the receipt and its actual explanation;
  do not reclassify it as a proven rudder defect.
- **Zero-intensity glare work.** The second package retains callback and skyline
  mesh observations while overlay intensity is zero. Current source still
  prepares skyline work before the final intensity multiplication, but the
  source has changed. Neither the old callback count nor packed payload size
  measures current frame time, allocation copying, VRAM or a leak. Existing
  SUN-09/SUN-08 work should decide priority from a matched complete-scene
  profile, preserving cloud-disc/state requirements.
- **Rejected performance amplification.** The foliage fixture retained one
  cache entry across 100 builds. Packed-array alias behavior alone did not
  establish repeated allocation copying. No major cache leak, universal FPS
  improvement, energy-creation result or asset-size-to-RAM equivalence is
  inferred from these observations.
- **Unsupported routes retain their limits.** A retained Workshop route is not
  playable helicopter qualification. Numerical witness completion is not a
  physical-controller, graphical, aircraft-calibration or release certificate.

## Verification and replay boundaries

To inspect the original packages, extract each ZIP into a separate new directory
and read its `README.txt`. From that extracted directory, the standard-library
integrity command is:

```sh
python3 verify.py
```

With a Git checkout containing the original commit, also compare the packaged
source copies directly with its tree:

```sh
python3 verify.py --repo /absolute/path/to/OpenRCsimulator
```

These commands do not launch Godot. Each ZIP also includes `audit_commands.json`,
original reports/logs, SHA-256 manifests and a portable `replay.py`. Their replay
contract uses the original commit and exact recorded engine, a complete imported
project for production probes, and a new output directory for every execution.
Some original probes depend on Linux facilities. A sparse source checkout is
adequate for this review, not for claiming a complete game replay.

For current-source reproduction, first adapt and inspect the recovered witness
against the exact candidate, then route execution through the repository's
current [test-queue and checked-runner policy][tooling]. Keep new results and
source identities separate from the historical package. Intentional defect
witnesses can pass because the defect remains; correction tests must assert the
desired behavior and retain the historical case as a negative control.

[baseline]: https://github.com/bultodepapas/OpenRCsimulator/tree/45d86d250f6e38a3d9b60d30c01bdc2396571efe
[reviewed]: https://github.com/bultodepapas/OpenRCsimulator/tree/ad21070798bfb9658785576a9c0b8bfc9a71fc7f
[pending]: ../../../external%20Audits/CONSOLIDATED-AUDITS.md
[completed]: ../../../external%20Audits/COMPLETED-AUDIT-WORK.md
[polar]: ../../../app/physics/wing_polar.gd#L82
[aero]: ../../../app/physics/aero.gd#L472
[reverse-repair]: ../aero-consistency/reverse-flow-2026-11-09/README.md
[collision-setup]: ../../../app/scenery/collision_setup.gd#L10
[collision-test]: ../../../app/tests/test_landscape_collision_setup.gd#L106
[store-lock]: ../../../app/statistics/store.gd#L843
[statistics-guide]: ../../FLIGHT-STATISTICS.md
[optional-test]: ../../../app/tests/test_optional_resource_loading.gd#L17
[atmosphere]: ../../../app/render/atmosphere.gd#L722
[cloud-test]: ../../../app/tests/test_sky_relief_layers.gd#L17
[desktop-handoff]: ../desktop-delivery-investigations/external-handoffs-2026-11-14.md
[lake-normal]: ../../../app/sim/lake_collision.gd#L519
[lake-call]: ../../../app/sim/flight_session.gd#L3531
[lake-policy]: ../../../app/sim/lake_collision.gd#L349
[quarantine]: ../../../app/statistics/store.gd#L812
[yaw]: ../flight-dynamics/stik-lateral-directional-2026-10-18/README.md
[tooling]: ../../tools/README.md
