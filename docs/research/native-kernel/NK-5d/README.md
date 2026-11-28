# NK-5d — native contact reach for the per-tick contact sweeps

2026-11-25. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-5c](../NK-5c/README.md).

## Why

Every accepted tick ends with the session's contact resolution (`post_tick_joint` or `post_tick`). With the Club
collision world (6,139 obstacle proxies) and the lake installed, a headless split at about 30 m showed it was the
largest remaining GDScript cost of a flying tick:

| Per tick, native backend | Corsair | P-51 | Avanti | Stik |
| --- | ---: | ---: | ---: | ---: |
| contact resolution | 125–129 µs | 126–146 µs | 90–96 µs | 69–71 µs |

In flight the answer is nearly always "no contact". The scenery sweep still measured its hull, formatted and looked up
its 32 m bin keys, and tested every obstacle box in those bins, because treetops share the layer of cells the aircraft
flies through. The lake sweep validated the lake, hull and states and measured every probe before its own height
reject.

## Change

- `nk_contact_reach.hpp` (`nk::ContactReach`) holds the bounds of the session's collision-world proxies in a north/east
  grid of 32 m cells. `reach_clear` builds one box around the tick's centre-of-gravity motion, widened by three times
  a reach radius and by explicit rounding margins. The radius is at least the largest of the hull point norms, gear
  probe norms and propeller hub norm plus radius. The result is two proofs:
  - **scenery clear**: no proxy box meets that box;
  - **lake clear**: the box's deepest point lies above LakeCollision's own reject threshold.
  It never reports a contact, and any doubt (non-finite input, too many cells, invalid bounds) proves nothing.
- `nk_kernel.cpp` binds `prepare_reach_world`, `clear_reach_world` and `contact_reach`. `native_stage.gd` prepares the
  bounds at installation (fixed-wing only) and again whenever the session's collision world or its proxies array is a
  different instance or size. `set_collision_world` always installs a new private deep copy, and nothing in the app
  mutates it afterwards.
- `flight_session.gd` asks once per resolution (`_native_contact_reach`). A proof skips only its own sweep and
  returns that sweep's "no hit" result. The sampled sweeps first repeat their own input checks; if one fails, the
  sweep runs and refuses as before. The unsampled sweeps return no event for invalid inputs anyway. Without a native
  stage, or without a proof, every sweep runs as before.

## Why the proofs are exact

- **Scenery.** `SceneryCollision.contacts` tests three kinds of box: the swept centre-of-gravity box ± the hull
  radius, the broad box ± the radius plus `_rotational_chord_padding`, and per-probe segment boxes ± that padding
  around probes at most the radius away. The padding is radius·(1 − cos θ/2) + 1e-9 ≤ 2·radius + 1e-9, so all of
  them lie inside the native box. If no proxy meets it, no candidate passes the sweep's overlap filter and the result
  is empty, in every branch: bins, the all-proxies fallback above 4,096 cells, and damaged proxies.
- **Lake.** `_first_hit_core` returns null when the deepest probe bound (deepest centre-of-gravity "down" + its radius
  + its rotation padding) is above `min(0, water level − maximum wave amplitude) − CONTACT_EPSILON_M`. The native box
  bounds that from below the same threshold, which GDScript computes with the sweep's own expression. The gear and
  propeller probes enter through the sweep's own `_gear_probe_point` and `_prop_disc_is_valid`.

## Evidence

- `app/tests/test_native_contact_reach.gd` (22/22), Corsair, P-51 and Stik:
  - Soundness: 4,000 random tick pairs each, near obstacles, over the lake and in open air. Some pairs move up to
    1.5 m, and one in 23 rotates up to half a turn in a tick, which tests the radius bound at its tightest. No
    claimed proof met a non-empty `SceneryCollision.contacts` or a non-null `LakeCollision.first_hit`. Scenery
    proofs held for 65–77% of pairs and lake proofs for 73–83%; 31–64 scenery hits and 40–73 lake hits occurred
    among the unproven pairs.
  - Equivalence: paired sessions with and without the shortcut flew byte-identical ticks, contact events, located
    events and crash records. Each aircraft flew a cruise of 480 ticks, a level flight into the tallest obstacle (crash
    after 275–308 ticks) and a sinking ditching (crash after 65–105 ticks).
- All nineteen installer gates are identical for binary `39f272aa96f2d77d43618828249a46b5ac199e6a4137bd63428f7130a5732686`,
  and the mutant build still fails. Accepted results (tool root, not in Git): `stage-20261125T213317439673Z.json`
  `b30238a30a82b764855d4f178a3761862f67af843c1f4d9adeb2c549eac9401d`, `stage_mutant-20261125T213346985631Z.json`
  `d97cabf6e5849dc0a56bf2adab8cd791356aeedaef8bda77a9883a02c2e1cb6b`, `trajectory-20261125T213416954742Z.json`
  `c15bc510ef681c8f0130607b174002fb05f3a914532f5a5764cf6fc192638640`, `liquid-stage-20261125T213642972936Z.json`
  `ed35ad4d9a938581b3dbf6bb5af49d94aa3a8eedd33ce66d9719923e59755392`.
- With the native stage installed, existing sessions take the new path. These suites pass: contact sessions, collision
  tie order, crash cause and integration, dynamic-mass contact (three suites), lake collision, session and ground
  contact, scenery damage and destruction, scenery trace, soft-ground scenery order, water checkpoint, RC-track
  crossing, the native suites, golden flights and replay integrity.
- An independent review found no exactness bug. Its follow-ups are included: an RC-track test override that kept
  the old signature, an overflow guard for cell counts at absurd coordinates, and dropping per-tick hull checks that
  a proof already implies.

## Gain

Same headless protocol, alternating runs with the shortcut off and on:

| Contact resolution per tick | Off (µs) | On (µs) |
| --- | ---: | ---: |
| Corsair | 125–129 | 71–75 |
| P-51 | 126–146 | 69–72 |
| Avanti | 90–96 | 59–70 |
| Stik | 69–71 | 14–21 |

The remainder for finite-fuel aircraft is mainly building the contact mass sampler (17–25 µs), which the sweeps need
only when something is hit.

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- The proof needs the native stage; the reference backend runs every sweep.
- The bounds follow the collision world by identity. Code that mutated the private world in place would need to
  reinstall it through `set_collision_world`.
