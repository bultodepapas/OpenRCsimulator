# Multiplayer: zero-spend implementation plan

**Owner:** multiplayer implementation lead, coordinating the existing SF/physics, UI, AFC, FL, DR and DT owners. **Prefix:** `MP-00…08`. **Status:** research and planning only; no multiplayer runtime delivered by this change. **Reviewed:** 2026-11-15 (America/Bogota), against `main` at [`cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`](https://github.com/bultodepapas/OpenRCsimulator/commit/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b).

This is the authoritative implementation plan. The [research](../research/multiplayer-2026-11-15/README.md) owns alternatives, dated prices/quotas and calculations; the [repository audit](../research/multiplayer-2026-11-15/repository-audit.md) owns source evidence. [STACK](../STACK.md#boundaries-and-data-flow) remains the simulation contract.

## 1. Decision and first product

Build **two-player LAN free flight with built-in ENet**, qualify direct internet joining, then **four-player private rooms hosted by a player**. Every pilot runs their own aircraft's existing physics. Other aircraft are visual replicas. Keep this local/direct path usable without a service account.

After private rooms work, timebox an **Epic Online Services (EOS/EOSG) connectivity trial**. It is the preferred candidate for easier joins through NAT and optional service-backed lobbies. Adoption requires exact-engine/platform tests and confirmed no-fee eligibility. If the trial fails, ship the qualified LAN/direct/private-network scope; do not replace it with an unverified promise. A **Cloudflare Workers Free directory** is an independent fallback for discovery of reachable ENet hosts. Select one online room service; do not build EOS, Firebase, Supabase and a custom relay simultaneously.

The first useful release supports one approved stock field, one stock fixed-wing aircraft, two pilots, host/join/leave, names, connection diagnostics and clean failure. Expand the bundled aircraft allowlist after replica checks. Free flight includes formation practice without shared collisions. A room is a roster plus rules and lifecycle; it can exist on the host before any cloud directory exists.

**Zero spending means no new project invoice.** It assumes existing computers, internet and development tools. It does not promise free electricity, unlimited capacity, permanent availability or successful connections through every network. No paid plan, new domain, expiring credit or automatic paid fallback is a required dependency.

## 2. Boundaries and ownership

| Proposed component / path | Owns | Must preserve |
| --- | --- | --- |
| `app/networking/` — session, codec, transport adapters, room state | Admission, routing, clocks, sequence/epoch handling, bounded queues and shutdown | No network writes into the local solver or controller; transport continues during local menu holds |
| `app/render/multiplayer/` — remote aircraft presentation | Interpolated transform, approved model, simple animation, label and stale status | No `FlightSession`, input device, camera/audio listener, local statistics or collision participant per remote aircraft |
| `app/ui/multiplayer/` | Host/join, roster, ready state, mismatch/failure messages | Existing screen stack, loading cancellation, controller arming, recorder prompts and explicit resume |
| `app/tests/test_mp_*.gd` | Codec, clocks, admission, impairment and lifecycle fixtures | Existing checked-runner and test-queue rules; real multi-machine evidence remains separate |
| Optional `services/multiplayer-directory/` | Small directory and quota enforcement if that route is selected | Metadata only; no physics, aircraft assets or flight telemetry storage |

These paths are **proposed**, not present networking modules. Shared edits in `app/app_root.gd`, `app/main.gd`, existing presentation builders, sessions and exports stay coordinated with their owners. Reuse companion visual construction and [frame/CG conversion](../../app/render/frames.gd); do not reuse its AI session/manager as a remote plane.

The host controls membership, room settings, readiness and entity ownership. Each connection controls only its assigned aircraft's pose. This is suitable for friendly flying; it does not establish fair competitive scores. One `VehicleModel` per `Simulation` remains intact. Multiple independent sessions already exist for AI, but remote visual presence does not require another solver.

## 3. Phases and gates

Estimates are **engineering judgment for one developer familiar with this repository**, including focused implementation checks. They exclude waiting for hardware/testers, upstream repairs and release review. Gates determine completion; calendar estimates do not. Each phase should be several small, independently reviewable commits.

| ID | Deliverable / scope | Dependencies | Required evidence / status | Effort |
| --- | --- | --- | --- | --- |
| **MP-00** | Source audit, option/cost comparison, protocol proposal and this plan | Pinned source and primary documentation | **Research complete.** Runtime, provider accounts and network performance untested; [limits](../research/multiplayer-2026-11-15/verification.md) | Delivered here |
| **MP-01** | Network lifecycle and fixed-wing snapshot contract; bounded codec; replica built from recorded/synthetic poses; feature disabled by default | MP-00; UI/SF/AFC interface agreement | Coordinate/CG/quaternion fixtures; malformed packet refusal; reset/epoch behavior; local accepted-state trace unchanged with replica enabled | 3–5 days |
| **MP-02** | Two processes on loopback, then two machines on LAN; manual endpoint; ENet; one stock field/aircraft; no accounts | MP-01 | 30-minute two-machine flight; both pilots see/control their own plane; 50 join/leave cycles; mismatch/full/timeout cases; gate A below | 5–8 days |
| **MP-03** | Direct internet join and useful network diagnostics; optional user-managed VPN; optional bounded UPnP | MP-02 | Two independent networks; reachable UDP success and CGNAT/unreachable failure; cancel/retry; no main-thread UPnP stall; exact access mode documented | 2–4 days |
| **MP-04** | Private rooms, **four total pilots including host**; roster, ready, locked settings, late join, kick, per-aircraft reset, reconnect and host loss | MP-02; MP-03 for internet claims | One host + three clients for 60 minutes; all lifecycle/impairment gates; only qualified transport combinations advertised | 5–8 days |
| **MP-05** | EOS/EOSG trial: P2P direct/forced relay and lobby/identity/export compatibility; explicit adopt/defer decision | MP-04 | Pinned SDK/plugin and license record; actual Windows/Linux/macOS loads; different-network and hotspot tests; zero-fee eligibility; no production dependency until pass | 3–5 days, stop at limit |
| **MP-06** | Easy room joining and optional public room browser using **one selected route**: qualified EOS, or Free HTTPS directory + reachable ENet | MP-04 and MP-05 decision | Invite isolation; stale-room removal; public listing opt-in; full/version/missing-content errors; outage/quota fallback; spend gate C | 5–10 days |
| **MP-07** | Cross-platform release qualification, diagnostics, performance and optional **eight-player** expansion | MP-06; DT/UI/physics gates | Real target-OS matrix, 1080p profiling and long sessions. Four remains the cap unless eight passes; no claim inferred from a vendor's CCU limit | 4–7 days |
| **MP-08** | Optional spectators, shared visual ghosts, informal challenges and later vehicle families | Relevant earlier gates and owning tracks | Separate scope and proof for each feature; no ranked or shared-physics promise | Re-estimate separately |

The core through MP-04 is **15–25 developer-days**; the full conditional sequence through MP-07 is **27–47**. Treat this as a planning range, not a delivery commitment. MP-03 and MP-04 can overlap after the basic transport is stable. A failed service trial does not block useful private LAN/direct sessions.

## 4. Session and room contract

Admission progresses through `connecting → compatibility → loading → ready → flying`. Connected is not ready. A bounded cancel/failure route exists at each stage. Reliable configuration and a current baseline must arrive before a replica is visible. The initial compatibility gate requires the same source/build family, protocol major, approved field bytes/scene identity, aircraft definition/model revision and shared environment profile. Platform-specific package hashes may differ; record them without requiring Windows and macOS binaries to be identical.

Use one stock world/profile first. Pin shared conditions and a fixed lighting selection before launch; lock changes during flight. Animated scenery/cloud details may differ locally: a shared starting time does not synchronize visuals driven by independent simulation clocks. Start with calm/no evolving turbulence. Shared gusts or animated world time later need a separate room-clock sampling design; copying a seed does not synchronize clients that pause or run slowly. Aircraft can differ only after each admitted stock model's visual/data identities are qualified. Custom Workshop models, downloaded skins and automatic content transfer are deferred.

| Event | Required behavior |
| --- | --- |
| Pilot menu or focus loss | Preserve existing safe local pause. Publish `PAUSED`, freeze that replica and stop its extrapolation. Network receive/host forwarding/heartbeats continue; no global pause and no remote command resumes local controls |
| Resume, reset, crash/restart, teleport | Reliable new flight epoch + accepted baseline; clear old interpolation; never sweep through the field from an obsolete pose |
| Client connection loss | Remove/fade stale replicas; apply existing safe local hold and offer explicit offline continuation or rejoin; local input never waits synchronously for network |
| Host leaves, sleeps or crashes | End the room within the timeout; other pilots enter the same safe local fallback. **No seamless host migration** in this plan, including when a service can promote its lobby owner |
| Rejoin | Fresh connection identity and roster/baseline; no old backlog. A stale packet or reused peer number cannot regain ownership |
| Loading, cancel, Home, quit | One connection owner; deterministic teardown; no ghost entities, sockets or signals retained after cancellation/exit |
| Workshop, checkpoint restore, time scaling | Leave the room through existing recorder/save flow before entering. No online restoration of a player-only checkpoint or unilateral room-time rewrite |
| Recording/statistics | Existing local logs contain only the local flight; remote presentation is not recorded/replayed and earns no local credit. Label this clearly; whole-room replay is later work |

Disable AI companions in the first online mode to keep the qualified workload and lifecycle bounded. Preserve the offline setting. If menu holds cannot be isolated safely in MP-02, explicitly leave the room on that transition; MP-04 must qualify continuous routing during local pause before shipping host rooms.

## 5. Snapshot and timing proposal

Retain 240 Hz local physics. Copy accepted state at the publication boundary, then encode/send outside the kernel at **20 snapshots per monotonic wall-clock second**. Publish only the latest completed state; discard missed send slots after a stall. No network wait, unbounded allocation or provider callback belongs in an RK4 stage or accepted-step transaction.

Keep physics tick, monotonic connection/room time and render playback time distinct. Use ping/echo to estimate each client's offset to the host clock; never compare unrelated local timestamps directly. Carry both simulation tick and mapped room sample time. The host bounds timestamps and sequence progression; clock estimates do not make a client authoritative over room time. Initial settings: 100 ms interpolation buffer, at most 100 ms extrapolation, active-plane stale display at 500 ms without a fresh accepted sample, replica removal/safe disconnect after 5 s without liveness. Tune against gate B, not anecdotal smoothness.

State freshness and connection liveness are separate. Send reliable pause/resume transitions and a 1 Hz bounded heartbeat repeating status and the last accepted sequence. A live intentionally paused aircraft stays visibly frozen even during a long pause; keep the original pose sample time. Heartbeats and retransmitting an unchanged state never make that pose a fresh physics sample. Test a lost initial pause notification, pause longer than 5 s, and explicit resume with a new epoch/baseline.

Detect sustained simulation/wall-time ratio below 0.95 over 2 s and mark `DEGRADED`. Disable extrapolation for paused/degraded peers; solver velocity is not wall-time velocity during slow simulation. On large timing discontinuities, request a fresh epoch/baseline. Never change local fixed dt to catch another machine.

**Proposed fixed snapshot: 128 application bytes**, little-endian with an explicitly versioned codec. This is a design budget; encoding and on-wire size must be measured in MP-01/02.

| Byte range | Field / representation | Bytes |
| --- | --- | ---: |
| 0–39 | Magic/protocol/type (4), flags/header size (4), room epoch/entity ID/flight epoch/sequence (`u32` each, 16), room sample microseconds and simulation tick (`u64` each, 16) | 40 |
| 40–63 | CG position NED, `float64 × 3` | 24 |
| 64–79 | Body→NED unit quaternion **w,x,y,z**, `float32 × 4` | 16 |
| 80–91 | Velocity NED in m/s, `float32 × 3`; convert from local body FRD velocity using accepted attitude | 12 |
| 92–103 | Angular velocity body FRD in rad/s, `float32 × 3` | 12 |
| 104–111 | Four approved stock presentation hinge angles, signed centidegrees (`int16 × 4`) | 8 |
| 112–119 | Propeller RPM (`float32`), normalized throttle (`u16`), presentation flags (`u16`) | 8 |
| 120–127 | Room configuration revision (`u32`), reserved zero (`u32`) | 8 |

This packet is presentation output; quantization never writes back to float64 simulation state. Model/skin identities travel once in bounded reliable metadata. Additional animation data requires a protocol revision and a new budget. No raw engine object/resource deserialization or arbitrary peer-supplied paths.

Separate reliable admission/roster/configuration/spawn/reset events from replaceable snapshots on distinct channels. ENet's high-level admission does not replace application validation. The host validates each inbound guest against its connection→owned-entity binding. Guests accept forwarded state only from the designated host and validate logical entity IDs against its authoritative roster; forwarding does not transfer aircraft ownership to the host. Test another-entity spoof and fake-host frames.

Check size, finiteness, quaternion norm and declared field-specific bounds for position, velocity, angular rate, RPM and approved hinge motion. Converted render transforms must also remain finite and representable: a finite float64 such as `1e300` is not a valid render position. MP-01 pins those bounds for its approved field/aircraft and tests finite-extreme inputs with no replica mutation. Use wrap-aware sequence comparison, rate-limit input and cap per-peer history at 64 snapshots plus 64 KiB reliable queued data. Reliable and unreliable channels can reorder relative to each other: unknown future epochs remain invisible until their reliable baseline arrives; old epochs are dropped. Rotation uses shortest-path interpolation and the existing render/CG conversion.

An adapter exposes join/leave, bounded control messages, latest-state sends and peer events. ENet may carry explicit bytes through Godot's multiplayer layer. A future JavaScript/WebSocket service must speak the explicit schema, **not Godot's private RPC wire format**. A WSS relay is a separate fallback trial: TCP can delay newer frames behind lost data, so latest-only application queues do not remove transport head-of-line blocking. [Networking sources](../research/multiplayer-2026-11-15/sources.md#networking)

## 6. Online route and hard-zero budget

**EOS first trial:** pin EOSG 2.3.1 or a deliberately reviewed successor, exact EOS SDK and license notices. A listed Godot 4.2+ minimum and a 4.7 compatibility fix do not prove 4.8-beta2 compatibility. Verify Windows/Linux/macOS exports, service-approved Connect identity, direct/forced-relay paths and graceful outage. A developer account/product configuration is required; a mandatory Epic player account is not assumed. Guest identity persistence/recovery must be specified. This plan creates no account or deployment. [Evidence](../research/multiplayer-2026-11-15/README.md#managed-services)

**If selecting the independent directory:** use the provider's free subdomain and Workers Free with SQLite Durable Objects; HTTPS JSON, max ten advertised rooms initially, host heartbeat every 30 s, TTL 90 s, list at most every 30 s and only while visible. An invite code locates a room; a separate random capability admits a private join, with expiry and owner revocation. Keep owner tokens out of listings. Here “private” means unlisted, possession-based friendly access; a capability sent over plain ENet does not establish confidentiality or an authenticated identity against an on-path observer. Stronger claims require a qualified protected channel. Publish reachable endpoints only for opted-in hosts and resolve them for intended joins; an HTTPS heartbeat does not prove UDP reachability.

Reserve 30% of provider request/write allowances. Stop admission/listing when the application allowance is consumed, return a useful unavailable state and retain direct join. Count other account traffic, cleanup, retries, index writes and hostile requests. Application counters improve availability planning; the actual provider **Free plan's refusal beyond limits** is the spending boundary. Confirm it in the selected account before deployment. No auto-upgrade or paid relay failover. Recheck dated terms before implementation and public release. [Quota model](../research/multiplayer-2026-11-15/README.md#capacity-and-cost-models)

UPnP is optional, explicit, bounded and off the main thread; remove only the mapping created by this session. It cannot configure ISP CGNAT. Eligible Tailscale/ZeroTier personal networks are optional private test tools with installation/account limits, not required public infrastructure. Plain direct ENet is not automatically an encrypted/authenticated service; make no such claim. Public stranger rooms wait for reviewed admission and abuse limits. No credentials for paid/provider administration go in exports.

## 7. Acceptance gates

All numbers below are **proposed pass criteria**, not achieved measurements. Record exact build, OS/hardware, resolution, transport/route, payload size, peers, reference trace, wall-time length, p50/p95/p99 and failure counts. Follow [existing verification scope](../tools/shared.md#verification-scope), checked runners and shared-host admission. Full required CI remains its own gate.

| Gate | Required evidence |
| --- | --- |
| **A — local correctness** | Same fixed input tape produces identical accepted local state with networking off/on for each qualified backend; malformed/oversized/duplicate/out-of-order/old-epoch packets cannot mutate local state. Healthy LAN admission ≤5 s excluding asset load. Cancel works at every stage; 50 cycles leave no residual replicas/sockets/signals |
| **B — four-pilot network and lifecycle** | 60-minute one-host/three-client session; controlled 100 ms RTT per client↔host leg, 20 ms jitter and 2% random loss. Target p95 rendered remote sample age ≤300 ms, stale display <1% outside injected outages. Also exercise 200 ms loss bursts, duplication, reordering, 1 s stalls, asymmetric links, host sleep/kill, pause/focus/Workshop/quit, resets and late joins. Separate source timestamp age from clock-estimation uncertainty; report failures, not just averages |
| **B2 — motion/performance** | Compare rendered replicas to recorded truth at their intended delayed timestamp for taxi, level flight and fast roll/reset traces; initial residual targets p95 ≤0.5 m and ≤2° outside marked discontinuities. Network-only p95 main-thread CPU ≤1 ms on the declared reference host; no unbounded queues or monotonic memory growth after warm-up. Qualify additional visual cost separately at **1080p first** against the existing physics/frame gates; reduce room cap/visuals if unmet |
| **C — service and cost** | Shared: actual account/plan/terms, outage/backoff/offline fallback, no charges or automatic paid route, full/mismatch and possession-based invite admission/expiry/revocation. **EOS route:** direct and forced-relay cases, identity and lobby teardown. **Directory + ENet route:** reachable joins, honest unreachable-host failure, expired listings filtered within TTL, quota refusal fixture plus provider evidence; no relay is required or claimed. Simulated quota exhaustion must be labeled simulated |
| **D — release matrix** | Real Windows x86_64, Linux x86_64, macOS ARM64 and Intel/Rosetta paths that will be claimed; each used as host and client, with distinct-machine/OS pairs. Exporting a ZIP is not target-OS execution. Required CI results, controller safety, local statistics/recorder behavior and offline launch pass. Untested target combinations remain unsupported beta claims |

Keep network impairment injection above the transport for reproducible codec/state tests; add real OS/network tests for transport effects it cannot emulate. A clean LAN run cannot close Internet/relay gates. Eight participants and spectators must repeat the capacity/performance gates; spectators still consume bandwidth and room slots.

## 8. Deferred scope and stop rules

Ghost files and pass-the-controller sessions can be zero-service side features; they do not verify live networking. Split screen needs separate input/camera/session work and is not assumed cheaper. Native WebRTC, GD-Sync and an application WSS relay remain researched alternatives, not parallel mandatory implementations.

Defer aircraft-to-aircraft collisions, shared control/instructor handover, aerotow, cross-platform input lockstep, rollback of the full solver, persistent worlds, global ranked results, integrated voice, asset upload/download and automatic host migration. Later informal drone races may share **client-reported** results, but sparse presentation snapshots must not adjudicate gate crossings; the DR track owns its 240 Hz race model.

Stop expansion if any phase changes offline flight results, cannot preserve pause/arming/recording, relies on unverified native binaries, has unbounded traffic/memory, requires a chargeable service or lacks real evidence for its advertised network/platform scope. Deliver the last qualified smaller scope. A free lobby's maximum members and a synthetic throughput estimate never justify increasing the product cap.
