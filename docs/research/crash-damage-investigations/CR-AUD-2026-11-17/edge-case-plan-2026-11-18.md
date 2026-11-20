# Implementation slices for CR-AUD-21 through CR-AUD-24

**Date:** 18 November 2026, America/Bogota.
**Status:** proposed work; no production correction is implemented by this audit.
**Evidence:** [third investigation](edge-cases-2026-11-18.md) and [verification](edge-case-verification-2026-11-18.md).

These slices extend the [original improvement plan](improvement-plan.md) and [second-pass plan](deep-dive-plan-2026-11-18.md). They do not replace the earlier world-composition, helicopter response, wreck conservation, or terminal-aftermath priorities. The owner names below describe repository responsibilities, not people assigned or notified by this audit.

## Scheduling and ownership

| Proposed slice | Owner and shared seams | Work | Proof/status |
|---|---|---|---|
| CR-AUD-21a | DR graded contacts; EL/BAT coupled powertrain; SF accepted state | Derive a passive body-and-shaft contact response | Pending; current direct-transition counterexample fails |
| CR-AUD-21b | DR/SF/FL | Integrate the response and qualify accepted ticks and replay | Pending; current probe does not execute that boundary |
| CR-AUD-22a | BL session; FL recorder | Define an immutable-world or explicit world-change recording boundary | Pending; public API can produce a complete, non-replayable terminal outcome |
| CR-AUD-23a | CR scenery geometry; GP/SF numerical contracts | Define dimensioned geometry tolerances and the slow-hard-contact policy | Pending; narrow numerical domain remains unqualified |
| CR-AUD-23b | CR fixed-wing session; SF accepted state | Implement bounded entry handling and growing-overlap behavior | Pending; accepted reference fixture passes through the isolated trunk |
| CR-AUD-24a | GP terrain; CR prop contact; fixed-wing/FL consumers | Unify propeller-disc contact against varying terrain | Pending; small dry-bank rim witness precedes the selected point |

Start the narrow airship boundary correction and the quad energy derivation independently. Keep the hard-capsule and bank changes behind explicit tolerance and geometry decisions; their P3 recommendation reflects limited demonstrated scope, not an established acceptable error budget. Coordinate each production change with its owning track and update that track's active status when work is actually accepted.

## CR-AUD-21a/b — Coupled prop contact with an energy bound

### Design decision

Specify the mechanical state and work ledger for an instantaneous blade contact. The admitted electric quad uses a locked inertia tensor and relative shaft speeds. The same conventions must appear in momentum updates, point velocity, and kinetic energy. The relevant point velocity includes body translation, body angular velocity about the hub/contact arm, and the relative shaft contribution. A contact against a moving obstacle would also need obstacle velocity; the retained counterexample concerns a stationary wall.

Choose a compatible generalized impulse formulation, or a conservative reduced response whose limitations are explicit. Include the rotor's reaction on the body exactly once. Apply any energy constraint to the combined body/shaft transition, including subsequent bounce, rather than relying on a separate body restitution cap. If fracture or deformation supplies or stores mechanical energy, represent and bound that state explicitly; a cosmetic health decrement is not an energy reservoir.

The existing positive kick at zero tangential speed is not automatically wrong. The rotor can transfer some of its energy to the airframe while the total decreases. Removing all kicks would suppress the counterexample but also discard intended response. Acceptance must check both the invariant and useful controlled behavior.

### Acceptance evidence

Retain the five current cases and require nonpositive coupled kinetic-energy change within a justified numerical tolerance for passive stationary contacts. Preserve the no-contact and stopped controls, finite state, positive model mass/inertia, and the expected rotor-damage ownership. Add both shaft directions where the supported law permits them, different body rates, small/full bite, ground/wall contact, and simultaneous contacts on multiple rotors.

Then construct an accepted-tick contact approach from a clear state, with full before/after body and shaft state. The current already-overlapping direct call is a unit-level counterexample and cannot substitute for this gate. Verify the electric plant's accepted-frame validator, event count, energy state, reset and recording/replay consumers. Reuse the existing graded-crash and electric-plant checks selected by the actual touched dependencies. If the response law changes, version its identity and explain replay compatibility; do not silently re-record goldens.

**Exit:** the retained case fails on the audited baseline and passes on the candidate; controls preserve their supported behavior; the integrated event is finite, passive under its declared work model, and deterministic on the qualified route. Physical blade/material calibration and pilot feel remain separate evidence.

## CR-AUD-22a — An atomic airship collision-world boundary

### Smallest reviewable correction

Protect the active writer's collision identity from the moment its header is created, including tick zero. Refuse every changed-world operation while a recorder is active, or establish an atomic recording boundary for every allowed identity change. Freezing a flight's world after accepted ticks can be an additional session policy; it is not sufficient by itself for a recorder already open at tick zero. An identical-world call may remain an idempotent no-op. A rejected changed-world call must not mutate the world, broadphase cache, pause state, recording state or tick.

If the product needs a paused world replacement, close the old recording before the mutation becomes visible to a later tick, then start any new recording with a checkpoint and identity that describe the new world. Specify signal order and failure behavior. If closing the file fails, do not silently continue a recording under a stale identity. A serialized transition design is also possible, but it requires a format/version change, validation and replay reconstruction; it is a larger feature than this audit's boundary repair.

### Acceptance evidence

Run the retained three-file matrix. The changed operation must be refused without side effects or produce a clean boundary whose files each verify under their own header. Unchanged-world pause/resume must keep its exact replay. Installing the stock world before recording must still reproduce the real obstacle crash.

Add changed-world calls at tick zero, paused positive ticks, unpaused positive ticks, and after a terminal crash. Check invalid inventory rejection, recorder-start failures and callback visibility. Do not assert a current player-facing midflight switch: the present activity installs its inventory at startup. Exercise that actual startup path as the consumer gate and keep API-only cases labeled accordingly.

**Exit:** no accepted tick is written under an obsolete collision identity; completed files meet their declared replay contract or expose a deliberate, versioned unsupported transition. The verifier should continue to reject genuine mismatches. Suppressing the terminal comparison would hide the defect and fails acceptance.

## CR-AUD-23a/b — Dimensioned entry tolerance and overlap policy

### Decision before a numeric change

The present constant participates in squared displacement, root-approach and distance checks. Inventory the units at every use before choosing a replacement. The retained straight-segment threshold maps to one micrometre of displacement; it is not a universal scalar vehicle-speed threshold once rotation, geometry scale or timestep changes.

Decide whether an arbitrarily slow hard entry should be terminal, a resolved contact, a tolerated overlap with a defined bound, or an explicit unsupported case. The current hard-terminal exemption from the soft-speed cutoff is insufficient as a numerical contract. Document a spatial/timing bound appropriate to the authored proxies and simulation scale. Reuse existing numeric primitives where they meet that contract; do not add an epsilon per symptom.

If small entries are tolerated, choose what happens when their penetration grows. Options include a bounded persistent overlap check, conservative projection/response, or a deterministic refusal. A start-inside state and a separating exit require an intentional policy to avoid false crashes or repeated impulses. Any per-tick recovery must keep event ordering, identity and damage publication consistent with the earlier audit's contact-ownership requirements.

### Acceptance evidence

Preserve the retained slow outside-to-inside cylinder case, its faster hard-entry control, outward/clear controls and the subsequent 120-tick forced trajectory. Add sphere-cap hits, near tangency, stationary overlap, inward and separating initial-inside states, and values immediately around each declared bound. Cover supported tick rates and coordinate magnitudes; distinguish native/reference routes where they exist rather than inferring parity.

Require the chosen response to occur before an overlap grows beyond its declared allowance. Check finite roots, deterministic earliest-event ordering, bounded iteration/work, and no-world parity. Existing ordinary-speed tree tests remain controls. The audit does not require a catastrophic crash at 0.1 mm/s as the only acceptable product decision; it requires the implementation and tolerance policy to agree.

**Exit:** the original numerical counterexample is either handled according to the chosen contact policy or explicitly diagnosed within a published bound, and the subsequent unconstrained passage is prevented or deliberately reported. Physical tree geometry remains an approximation.

## CR-AUD-24a — One disc/terrain query for the propeller owners

### Geometry and ownership

Define the represented disc and the supported terrain class before selecting a query. Against a plane, projecting its normal into the disc plane gives the extremal support direction. Against a varying bank, a single terrain sample does not establish a global penetration bound. Evaluate curvature, shore edges, transitions between ground and water, and wave/time dependence where supported.

Choose a bounded analytic, adaptive or conservative query with an explicit error/iteration budget. Share its result and validity contract between the fixed-wing strike guard and lake probe construction. Preserve the flat-ground result and make unsupported/invalid terrain distinguishable from a valid clear result. Do not conflate this geometry work with a new blade fracture or ground impulse model.

### Acceptance evidence

The retained positive rim witness must be detected under the selected tolerance, or the chosen tolerance must be explicitly justified and exercised on both sides. Keep the powered flat-ground and deeper-bank controls. Add bank gradients with both signs, yaw/pitch/roll permutations, nearly horizontal discs, edge/interior contact, shoreline transitions, and turbines/no-prop data. Use a demonstrable geometric oracle for planar cases and a converged or bounded independent reference for curved cases; 128 samples alone cannot certify absence of contact.

Run an accepted approach beyond the first positive witness to establish the actual detection delay and resulting engine/prop state. Verify reset, later terminal-crash propagation and recording identity when the law changes. CR-AUD-03's source-off/coasting issue needs its own control; a powered-bank fix must not be mistaken for correcting that independent guard.

**Exit:** owners agree on contact geometry and time within a declared bound, flat-ground behavior remains qualified, and the precise pose conventions are recorded. A rendered confirmation may then establish whether a measured delay is visually significant; headless geometry alone cannot.

## Verification and CI integration

Keep failing-baseline audit probes as evidence until corresponding production fixes are reviewed. Promote corrected, focused regression cases into the owning test suites when the intended policy is agreed. The audit launcher deliberately preserves nonzero exits; do not wire it into required CI as a supposedly passing baseline or invert assertions to hide known failures.

Use the repository's checked runner and shared-host admission paths, retain source/engine identities and completion markers, and distinguish desired assertion failures from parser/engine failures. Select checks by changed dependencies. Broader CI, platform parity, physical validation and target-hardware performance remain the existing required gates; the four short probes do not replace them.

No target-hardware benchmark, 1080p capture, large debris campaign or 300 km/h flight qualification was added in this pass. Any geometry search or persistent-overlap enhancement should acquire a bounded work budget and measured cost under its real contact load before rollout. That is a pending implementation gate, not a performance regression measured by this audit.
