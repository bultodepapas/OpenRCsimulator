# Share, retain and defer decisions

**Scope:** runtime baseline `57abea025f62b20233ca281d58d2acbee4ab8b8e`; proposal reviewed at `542d92b304fc3b82678c4a90b848a88d82df0b22`. This is a design decision matrix; no extraction is implemented. The [VRC plan](../../plans/vehicle-runtime-consolidation.md) owns steps/status and the [control contract](CONTROL-CONTRACT.md) owns detailed acceptance.

| Concern | Decision | Authority and exception | First applicable VRC step |
| --- | --- | --- | --- |
| Rigid-body tick, events and rollback | Retain existing shared kernel | Simulation/VehicleModel; quad framed sampling and optional joint protocols remain explicit | 00, 11 |
| Aircraft v2 admission and law classification | Retain one registry/schema | AS/AircraftData/AircraftModules; other families retain distinct schemas | 00, AS coordination |
| Airframe, gear, flap, elevon and propulsion differences | Retain capability-driven laws and authored sources | Aircraft/AS/physics own generators and physical evidence; no per-ID kernel condition | 02 |
| Device/profile/calibration | Reuse existing services **where the route uses them** | D6/UI; direct/standalone readers and external drivers remain supported without a new mandatory singleton | 03 |
| Shell status/pause/resume | Characterize fixed-wing PauseMenu and existing AppRoot intent boundary; add an origin wrapper only if needed | Actual shell/activity entry point plus session chain; proof required even when no new wrapper is useful | 01, 04 |
| Status and capabilities | Retain current reads unless a small detached projection removes a named decision/dependency | Current owners; model-static features differ from live availability; the conditional flat view is only a subprojection | 01, 04; 08 for a later view |
| Start/reset/restore | Defer common API; characterize one owner transaction before any move | No universal checkpoint or recorder-rollback promise; fixed-wing and airship/quad ordering differs | 02 or later explicitly scoped 05 |
| Exit/disposal and observer lifetime | Preserve owners; extract only proven retirement mechanics | Tentative detach is not final close; writer/export failure and pending results retain their own policy | 07 |
| Terrain/weather/collision input builders | Optional sharing after equivalent-domain proof for real callers | LU/SC/GP; weather limits, material/contact and ordered obstacles remain family-specific | 06 |
| Recorder/statistics/trace | Keep formats, commit semantics and credit policy distinct | FL/UI-FS/activity owners; fixed-wing restore remains noncredit, quad outbox remains owned | 07 |
| HUD/camera/visuals | Use detached views and one useful component at a time | Render/HUD/UI; no state feedback or mutable resource sharing | 08 |
| Input/workload optimization | Measure and preserve temporal behavior before adoption | D6/F6/PT/VQ/NK; no new queue, stale sample or inferred USB/physical-latency result | 09 |
| Universal vehicle base, central family switch or new capability registry | Reject | Existing kernel/data authorities already cover the shared domain | Never |
| One replay/checkpoint format or unconditional close API | Reject | Would erase supported identity, recording and family safety semantics | Never |
| Mass migration, rename or golden regeneration | Reject | Obscures the cause of control/numerical regressions | Never |

## First bridge: smallest justified surface

Characterize one actual fixed-wing consumer, then define only the status fields and pause/resume intent it needs. There is no demonstrated universal status API to rename. AppRoot's Continue checks radio-menu center, screen identity and other holds, releases the menu hold and masks keys before calling session resume. Airship and quad perform their own activity checks. A common direct `session.resume()` call would bypass those differences.

The [implementation blueprint](IMPLEMENTATION-BLUEPRINT.md#3-first-consumer-fixed-wing-pausemenu) selects PauseMenu and defines its exact caller/fallback/Workshop lifetime scope. Keep current reads by default if a tiny projection adds indirection without reducing coupling. Existing AppRoot dispatch can satisfy the intent boundary if characterized and proven; a new wrapper is optional. Continue returns void and can close a crashed flight's menu without resuming ticks, so never manufacture a successful-resume receipt from dispatch alone.

Requests contain intent and optional expected-identity context; owners read live authority. Results reflect the existing operation, including unsupported/refused/accepted and committed-fault distinctions where provided. A view cannot grant readiness. Dynamic feature support, profile/action eligibility and actual backend are projected from the owner, not duplicated in a new registry.

Do not move prepare/reset/restore/close merely to fill out an aesthetically complete interface. Add a method only after a concrete second need or demonstrated isolation benefit and its refusal/commit/cancel witness. Keep payloads typed and bounded where feasible, with unsupported/unknown fields explicit; do not circulate a mutable dictionary containing live session or simulation resources.

## Family acceptance differences

| Activity | Full resume/admission chain to preserve | Checkpoint, recording and recovery boundary |
| --- | --- | --- |
| Fixed wing | AppRoot/screen stack/held keys and radio-menu center where applicable; session calibration, holds, crash/start/controller/native gates | Fixed-wing envelope; staged transactions; accepted observer fault differs from rollback; restore remains noncredit |
| Helicopter | Existing shell/activity plus rotorcraft/collective/mode/ready and native guards | Own rotorcraft envelope; direct legacy save failure can leave calibrated in-memory controls active but not saved |
| Airship | Activity samples armed input, then session requires low throttle and centered yaw | Specialized state/continuous restore and tape; reset notification may precede later reset refusal; no universal old-writer guarantee |
| Quad | Activity role/generation/profile retry/readiness, throttle policy and recovery, then session crash/fault/tape guard | Checkpointed FC memory, race/outbox/tape; pre-expo pilot input; automatic fallback held, first resumed tick semantics retained |
| Ground | Existing neutral/armed, hold and backend/data rules | Own damage/control tape and recording/export/discard protocol; optional later migration |

The bridge must retain existing guarded Fly/restart intent. It must not impose a second Continue on already-ready launch, radio-style low-throttle dwell on a verified pad, or fixed-wing shaping on quad. Radio menus, radio Pause, keyboard bindings and direct-launch profile resolution are separate support rows.

## What makes a move admissible

1. Name the precise owner/caller and current behavior, including failure and interrupted paths.
2. Pick applicable [case IDs](CONTROL-ACCEPTANCE.md) and fix affected baseline defects under their existing owners before moving the seam.
3. Prove the bridge preserves the actual input/event/poll/admission order and first accepted command, with a real consumer witness.
4. Apply [Q2](QUALITY-GATES.md#q2-state-replay-and-lifetime) when state, recording or identity is affected; do not require impossible exact replay across changed fingerprints or invent cross-family atomicity.
5. Keep the change independently revertible with accepted player data and the old route's semantics. If a smaller forwarding function is sufficient, use it.

Optional field/observer/view consolidation does not block a completed controls repair. Conversely, a clean architecture diagram does not waive a required control or device gate.
