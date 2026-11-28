# FPV racing contracts

Scope: the decisions, alternatives and evidence behind fpv racing contracts. These records retain the context of each choice; linked guides and the [current roadmap](../../ROADMAP.md) own implemented behavior and remaining work. [Decision index](../DECISIONS.md).

## Race state commits with the physics tick

**DR-23…26.** Local gate racing wraps the quad's model: the race phase, countdown, next gate, lap slots and attempt generation are a fixed suffix of the model's sampled and discrete arrays, and one endpoint transition composes the physical endpoint with a pure race director. A lap result therefore can never come from a listener that saw a different tick than the physics, and a refused tick commits neither a GO nor a crossing. Gate crossings are swept on the accepted tick's chord with strict aperture edges, a declared acceleration envelope for its in-plane uncertainty, and an unresolved (never scored) outcome when the uncertainty reaches an edge or the tick's body was corrected. Events are ordered by time with a one-microsecond tie group in which a crash wins. Terminal records go to a bounded, checkpointed outbox and are written to disk only on request; a full outbox refuses a new start. These are local practice rules (`openrc-local-race-v1`), with no federation compliance claim. Revisit if curved-path error near grazing crossings matters: supply located path pieces through an integration receipt. [Evidence](../research/drone-racing/M1-M3-2026-11-11/README.md#local-racing).

## Race gates are drawn as their collision panels

**DR-28/32 (2026-11-12).** A gate is solid where it is drawn. Each post and bar is a fabric panel box, 0.18 m wide in the gate plane and 0.04 m thick, with a 0.40 m top banner that carries the gate number. The race session collides with exactly these boxes, and the course identity includes their size, so an older race record is not replayed against a different solid. League gates frame the opening with 20–30 cm mesh panels, while the former 6 cm square tube nearly vanished at distance in a 1080p FPV picture. Readability comes from presentation only: striped panels in alternating colours, an LED strip on the aperture edge, the next gate lime and pulsing, the one after amber, a checkered start/finish gate (the last gate closes the lap) and a painted start pad. A second course on the default field, the Tower sprint, uses the existing upright format for a low hurdle, a raised tower gate and high and low passes. T cycles the courses of a field on the pad. Light is never solid. Additive neon halos, a chevron over the next gate, a dotted path from the previous gate to the next, a light washing the next gate, and a start light bar (red per countdown second, green at GO, yellow on the last lap, white at the finish) are drawn as light. They are exposure-compensated (scaled by exposure^-0.5 under the World's eye adaptation) so they keep their colour at night. The exit face of each gate is red, as a wrong-way cue. The compatibility renderer pays per draw call, so each gate's four panels are one merged mesh that carries per-box data in UV and UV2 (one draw, one shadow caster), and its four halos are another. Feet, plates and start lamps are course-wide MultiMeshes. Calm halos and the gate light are not drawn by day, and the exposure compensation is one global shader parameter. A six-gate course went from 79 draw calls and 0.51 ms of render CPU per frame to 20 calls and 0.19 ms, with the same look. Detail is shaded, not modelled: one fragment shader draws each panel as a fabric sleeve between a white PVC tube and an LED diffuser tube (cylinder normals from the flat faces, single LEDs, corner connectors, eyelets, stitching), with fine detail faded by pixel footprint so it never speckles at distance. Posts are cut where the bars cross them, so no coplanar faces flicker while the drawn union stays the collision union. Foot tubes (4 cm) and sandbags (9 cm) at the post feet and the start lamps (4.5 cm proud of the banner) are the only drawn parts outside the collision boxes; they are small, low or flush details that do not collide. The course costs 21 draw calls. Rejected: thicker drawn frames over thin solids (visible but non-colliding geometry in a racing sim); solid-looking decorative flags, banners or ground arrows near the flight path; and tilted dive gates or flags, which wait for a track-format revision. [Plan](../plans/drone-racing.md), [course visual](../../app/vehicles/multirotor/race_course_visual.gd).

## Race records are local, per course identity, with geometry-derived medals

**DR-37/DR-40 (2026-11-12).** The quad race keeps a local record book (`user://race_results/records.json`) beside the per-attempt result files, which stay the authoritative record of every attempt. Each entry is keyed by the prepared course identity, so a moved gate or another field starts a new entry instead of comparing unlike courses. It stores the best three-lap total with its lap times, the best single lap (an aborted attempt's completed lap counts), the best medal, finishes and attempts. A pad reset during a race is not an attempt. Medal targets are game targets, not pilot data: the straight gate-to-gate path flown three times from the pad at a mean of 5 m/s (bronze), 8 m/s (silver) and 11 m/s (gold). An unreadable book is kept aside and a new one starts. The flow inside the activity explains itself: the OSD says what the start needs (arm, then G; throttle low until GO), every refused start or GO names its cause, a results card shows the time against the best and the next medal, and G or R returns to the pad and flies on without the menu (G also stages the next start). Online leaderboards, ghosts and achievements outside a course were rejected: there is no account or validation path. [Plan](../plans/drone-racing.md), [record book](../../app/vehicles/multirotor/race_records.gd).

## FPV audit repairs fix the quad's control, energy, scoring and result contracts

**DR-14/16/21/25/26/26a (2026-11-17), [FPV audit 2026-11-16](../research/drone-racing/audit-2026-11-16/README.md).** Each choice below repairs one finding. Each regression test fails against the audit's baseline behaviour.

- **Controls.**
  - A refused managed profile keeps the selected device connected but unready. The quad never substitutes RcInput's built-in pad mapping (A01). The airship already behaved this way.
  - One physical control has one authority. LB arms, RB changes the mode and the profile's effective Pause button pauses, each only while no configured AUX member or Pause owns that button (A02).
  - An ordinary hold keeps an arm switch's ON only while the same source, mapping and connection hold. The live position must read ON through the whole hold. An OFF reading, an edge-toggle binding, focus loss or a source change ends that continuity. The menu then says that resuming disarms (A03).
  - Any change of the selected device's registry connection generation re-resolves the source and verifier behind the menu, before another tick is accepted (A19).
  - The direct route starts its own `ControllerService` (current store, refusal policy, UI device), because AppRoot's bytes are pinned by the companion behaviour manifest (A04/A05).
  - Help is generated from the effective bindings (A18).
- **Energy.** The damped bridge's regeneration is bounded by a declared charge-acceptance law (A06, bus law v2).
  - The pack accepts at most (capacity − charge)/0.2 s, so a full pack accepts none.
  - While that limit binds, the bus floats to the voltage at which the motors return only that current. The energy the pack cannot store is counted as pack loss.
  - Rejected alternatives: clamping charge or SOC, clipping pack current while keeping motor torque, and dropping active braking. The one-quadrant candidate weakened chop authority.
  - Hover admission solves the loaded shared pack (A08). One physical-invariant list guards raw and prepared models (A09).
- **Scoring.** The ruleset record adds `terminal_policy`: a crash or depletion decided on a tick's endpoint voids that tick's crossings (A10). An event locator can later narrow this.
  - The course identity hashes the resolved solid frame boxes (A15).
  - Both changes create new course identities. Older record-book entries remain as history under their old identities and are not re-ranked.
  - A pad-reset result keeps its terminal tick and reports the published-only reason code `pad_reset` (A14).
- **Results.**
  - Each attempt file has a random 128-bit publication id, kept across retries.
  - No-clobber publication: identical bytes count as an idempotent success, while other bytes are a conflict that stays pending (A12/A13).
  - The record book keeps a verified `.prev` copy that the loader recovers. Only complete entries load (A13/A16).
  - Opening the menu or a start retries pending saves. Leaving with unsaved results takes a second, informed Back to Home (A11).
  - These are graceful-session guarantees only, with no fsync or crash-durable queue.

## Quad crashes are graded and controllers arrive preconfigured

**DR-19c/DR-14d (2026-11-17), owner feedback.**
- **Crashes.** A deterministic gameplay law replaces "every contact ends the flight". Each prop's health is checkpointed state.
  - The frame and the props are judged separately, by closing speed and by obstacle material.
  - Most impacts bounce, using the shared energy-bounded scenery impulse, or wear and break props. Only the hardest end the flight.
  - The previous law stays selectable for practice.
  - Thresholds are estimates. No source gives fly-on versus walk-of-shame numbers; Betaflight does not disarm on impact by default.
- **Controllers.**
  - A recognized EdgeTX radio starts from CH5 arm (high end only), CH6 mode and CH9 restart. CH7/CH8 are avoided because Windows DirectInput can swap them.
  - Pads restart on View/Back.
  - Restart needs a fresh OFF and never fires while a menu owns the input.
  - Saved profiles are never rewritten.
- Rejected: turtle mode and motor or arm damage, until there is evidence. [Plan §17](../plans/drone-racing.md#17-pilot-feedback-2026-11-17-preconfigured-controls-and-graded-crashes).
