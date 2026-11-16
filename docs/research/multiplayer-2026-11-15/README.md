# Multiplayer research: what can operate with no new spending

**Research date:** 2026-11-15, America/Bogota. **Source baseline:** [`cfb5acd`](https://github.com/bultodepapas/OpenRCsimulator/commit/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b). **Scope:** the native Godot desktop application, not the frozen browser prototype. Provider plans and SDK status are dated observations, not permanent guarantees.

Read the [implementation plan](../../plans/multiplayer.md) for decisions, phases and gates; [repository audit](repository-audit.md) for code evidence; [primary sources](sources.md) for URLs; [verification](verification.md) for what was and was not tested. Source identifiers below refer to that register.

## Conclusions

The useful no-spend baseline is **player-hosted ENet**. It needs no hosted account for LAN or reachable direct sessions and fits the existing native engine. Private rooms are application behavior, not a paid hosting feature. The main engineering work is replica presentation, lifecycle, compatibility, timing and testing.

For wider internet reachability, **EOS P2P/lobbies is the preferred bounded trial**, with a community Godot wrapper and real export/network gates. A small **Cloudflare Free directory** is a possible independent discovery service. It is not a UDP relay. Keep the last qualified local/direct route usable if either service cannot be adopted.

Four different meanings of “free” must stay separate:

| Category | Examples | What the project can promise |
| --- | --- | --- |
| No hosted service needed | LAN, local ghosts, player-hosted direct ENet | No new provider fee; existing hardware/network and host availability required |
| Ongoing no-fee game service | EOS under its applicable game-services terms | No royalty/hosting fee for eligible services; account, SDK, service limits and maintenance still apply |
| Free quota with refusal at limits | Workers Free; Firebase Spark; GD-Sync's documented transfer cutoff | A bounded service that may become unavailable; confirm the actual plan before use |
| Free software, allowance or trial | Nakama/Colyseus/noray software, TURN allowances, free VM offers | Does not by itself establish a sustainable hosted service or a hard zero-dollar ceiling |

This survey covers the relevant **families of multiplayer systems** and representative providers. It does not claim every package in the ecosystem is interchangeable or that every researched option should be implemented.

## Systems from simplest to most demanding

| System / experience | Application work | Infrastructure and limitations | Disposition |
| --- | --- | --- | --- |
| Pass-the-controller/local turns | Local session/reset/result UX | No network; sequential play | Optional small feature, not simultaneous multiplayer |
| Recorded visual ghost | Safe trajectory export/import and replica playback | Local files; exact physics replay remains build/platform-bound | Useful optional reuse of replica work; not a prerequisite |
| Split screen/two local pilots | Multiple controllers, cameras, viewports, local sessions and UI | No server, but substantial rendering/input work | Separate feature; not automatically the fastest path |
| Two processes on one PC | Codec and basic transport/replica proof | Loopback; CPU contention can distort measurements | First engineering proof, not a LAN/WAN claim |
| Two-machine LAN | Host/join/leave, compatibility and replica lifecycle | Same subnet; firewall/AP isolation can still interfere | First supported live product |
| LAN discovery | Bounded broadcast/multicast and responses | May be blocked on guest Wi-Fi/VPN; direct address remains | Convenience after manual LAN works |
| Direct public IP / IPv6 | Same ENet data plane plus diagnostics | Publicly reachable UDP, correct firewall/port mapping; IPv6 on both ends where used | Qualified advanced access route |
| UPnP-assisted direct IP | Async mapping attempt and owned cleanup | Router feature only; no ISP-CGNAT control | Optional, explicit and timeout-bounded |
| Private virtual LAN | Existing ENet over tester-managed VPN | External software, membership, service terms and possible relay latency | Optional friendly-test access |
| Four-player private room | Roster, settings, ready/late join, host powers and cleanup | Can live entirely on the listen host | Core product milestone |
| Directory / short room code | Discovery, TTL, admission and rate controls | Resolves metadata; host can still be unreachable | Later convenience; separate from connectivity |
| Managed P2P with relay fallback | Provider identity/transport/lobby adapter | Native SDK and service dependency | EOS first trial |
| Explicit WSS room relay | Custom wire schema, bounded fan-out and backpressure | Reachable service, free quotas, TCP stalls | Alternative small-room trial if EOS fails; not simultaneous scope |
| Native WebRTC P2P | Extension, SDP/ICE/signaling and fallback handling | STUN helps discovery; difficult paths need TURN | Defer until a concrete ENet/EOS limitation justifies it |
| Community headless host | Headless networking/lifecycle, operator configuration | Someone supplies public machine, bandwidth, uptime and updates | Later optional self-host package |
| Authoritative server / ranked racing | Server simulation, prediction/reconciliation, credible results and identities | Sustained compute and operational ownership | Separate project; no free-cloud assumption |

Godot transport/UPnP/WebRTC facts: [S01, N01–N07](sources.md#networking). VPN facts: [S13–S14, N08](sources.md#services). The effort/disposition columns are project-specific engineering judgments.

### Topology and authority

| Design | Strength | Cost/technical risk | Choice |
| --- | --- | --- | --- |
| Listen-host star; owner-supplied poses | One connection per guest; modest native integration; responsive local flight | Host uplink/availability; no trusted competition | Adopt for initial free flight |
| Full mesh | Removes host forwarding for steady-state poses | `n(n−1)/2` links; more NAT, reconnection and ownership cases | Not justified for 2–8 pilots |
| Dedicated state relay | Clients use outbound connections; room can outlive a pilot | Central traffic/quotas; relay still does not validate physics | Possible later alternative |
| Server-authoritative physics | Common authority and stronger adjudication | Run multiple solvers; latency compensation and hosting | Defer |
| Input lockstep | Low input traffic in a proven deterministic system | Slowest peer affects progress; determinism not established across this project's platforms/backends | Defer |
| Full rollback | Can compensate latency for tightly coupled interactions | Checkpoint breadth, re-simulation, side effects and backend identity | Defer; existing recovery checkpoints are not a multiplayer rollback implementation |

A mixed trust model is deliberate: host-authoritative **room state**, owner-authoritative **aircraft presentation**. This is adequate for social flying with no aircraft-to-aircraft interactions. It cannot certify fair gate timing, collisions, instructor control or ranked results. The current [race model evidence](repository-audit.md#racing) explains why rendered snapshot chords must not become race adjudication.

## Managed services

All figures below were checked against primary sources on the research date. “Conditional” means not selected for production and not yet tested in this project.

| Candidate | Verified offer / operational boundary | Native Godot fit and decision | Sources |
| --- | --- | --- | --- |
| **EOS + EOSG** | Eligible game services offered without royalty/hosting fees; P2P, relay and lobbies | Preferred trial. Community EOSG **2.3.1**, released 2026-09-15, includes a Godot 4.7 load fix; 4.8-beta2 compatibility unproven. Developer portal/product/Connect identity and native exports are real work | [S02–S06](sources.md#services) |
| **Cloudflare Workers Free + SQLite Durable Objects** | Daily hard quotas; excess Free operations fail; separate Worker/DO meters | Good metadata directory. A Worker/DO does not accept ENet UDP. Use provider subdomain; no separate domain purchase | [S07–S09, N12](sources.md#services) |
| **GD-Sync Free** | **4 players/lobby**. Pricing card says **5 GB/month**, same page's table says **200 MB/day**; usage docs describe daily free reset and closing all rooms at transfer exhaustion | Credible constrained prototype, not an eight-player solution. Resolve contradictory quota before relying on it; conservative examples use 200 MB/day | [S10–S11](sources.md#services) |
| **noray / nohub / netfox** | Open-source traversal/relay and lobby tooling; public instances provided to try before self-hosting | Godot-oriented alternative; public demo capacity is not a production entitlement. Hosting and rollback-plugin integration are separate questions | [S12](sources.md#services) |
| **Tailscale Personal** | **6 users**, unlimited user devices, personal/non-commercial use; direct and relay routes | Optional eligible private tests. No assumption that project/business use qualifies, or that tagged-resource add-ons are free | [S13, N08](sources.md#services) |
| **ZeroTier Personal** | Current offer effective 2026-10-20: **10 users/devices, 1 network, 1 admin**, personal use | Optional private tests; external install and manual membership. Do not use obsolete 25/50-device claims | [S14](sources.md#services) |
| **WebRTC / Cloudflare STUN and TURN** | Public STUN is free; TURN/SFU share a **1,000 GB/month allowance**, then paid egress | Native extension + signaling required. STUN is not a relay, and a TURN allowance is not a demonstrated hard-zero account plan. Exclude metered TURN from required path | [S15–S16, N05–N07](sources.md#services) |
| **Photon Fusion for Godot 3** | Free **100 CCU** for one eligible Fusion/Quantum game/customer; 0.3 TB traffic allowance. Godot **3.0.0 preview Build 684**, 2026-10-26, explicitly not production | Godot support now exists; not Unity-only. Defer: preview maturity and exact free-plan traffic/spend behavior require proof; general traffic docs describe automatic overage invoicing | [S17–S20](sources.md#services) |
| **Photon Realtime** | Free 20-CCU development/non-commercial tier; Fusion free-100 entitlement is different | Not a drop-in justification for a free-100 native Realtime implementation | [S18](sources.md#services) |
| **Firebase Spark RTDB** | **100 simultaneous connections**, **1 GB stored**, **10 GB/month downloads**; no payment information required; no-cost quotas | Possible small directory/signaling alternative. Keep Spark; billing-account linkage changes eligibility to Blaze. Not a 20 Hz pose database | [S21–S23](sources.md#services) |
| **Supabase Free Realtime** | **200 concurrent connections, 2 million messages/month, 100 events/s** | Presence/directory alternative; fan-out defeats naïve pose streaming. Extra backend/auth/database scope is unnecessary for first rooms | [S24–S25](sources.md#services) |
| **Nakama / Colyseus** | Open-source/self-hosted server software; managed deployment is separate | Capable, but too much backend/operations for initial native visual presence; need an actual existing host | [S26–S27](sources.md#services) |
| **Steamworks / GodotSteam** | Networking/lobby services in Steam ecosystem; new Steam app fee **US$100** | Later distribution-specific route. No evidence the fee is already paid; exclude from mandatory zero-spend path. Sample app IDs are not a release strategy | [S28, N13](sources.md#services) |
| **Oracle Always Free VM** | Conditional free resources distinct from trial credits; card verification, regional capacity and idle reclamation constraints | Possible owner-operated infrastructure only if actually available and eligible. No VM or operational capacity assumed | [S29–S30](sources.md#services) |
| **Hosted PartyKit / PartyServer** | Hosted `*.partykit.dev` service shut down **2026-10-23**; PartyServer can deploy to an owner's Cloudflare account | Do not propose hosted PartyKit as a current free backend. PartyServer uses the account's Cloudflare quotas and still is not ENet UDP | [S31](sources.md#services) |
| **PeerJS public cloud** | Shared signaling; free TURN discontinued in 2023 | Browser-oriented library; not a native Godot peer or assured free relay. Self-hosting still needs a server | [S32–S33](sources.md#services) |

**EOS decision gate:** a 3–5 day trial must load/export the pinned wrapper on the exact Godot build, connect two real networks including a restrictive/hotspot route, explicitly force relay, and test reconnect/host loss. Confirm Connect identity and guest persistence; Game Services need not force each pilot to own an Epic account. A provider's 64-member lobby limit is not our room capacity. If required packaging/connectivity/terms evidence is missing, retain the smaller ENet release. Do not infer gameplay host migration from service lobby-owner promotion.

**WSS fallback:** reasonable for modest visual co-presence if native UDP/provider integration is blocked. Use `WebSocketPeer` and an explicit schema, not Godot's private high-level RPC format. Cap queues and disconnect stalled peers; replacing an unsent pose cannot cancel bytes already waiting for TCP retransmission. Qualify it separately under loss. A JS relay is extra server code, not a checkbox on a directory. [N02–N03](sources.md#networking)

## Capacity and cost models

These are **derived planning estimates**, not traffic measurements or vendor billing guarantees. Decimal kB/MB/GB are used. The plan proposes **128 application bytes per state at 20 Hz**, including its own header but excluding transport/IP/encryption/acknowledgment/control overhead.

### Player-hosted star

Let `n` include the host and let `Bf = 128 × 20 = 2,560 bytes/s`. Each guest sends its own state once; host forwards every other aircraft to each guest.

| Total pilots | Host inbound | Host outbound | Each guest inbound | Each guest outbound |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 2.56 kB/s | 2.56 kB/s | 2.56 kB/s | 2.56 kB/s |
| 4 | 7.68 kB/s | 23.04 kB/s | 7.68 kB/s | 2.56 kB/s |
| 8 | 17.92 kB/s | 125.44 kB/s | 17.92 kB/s | 2.56 kB/s |

Host inbound is `(n−1)Bf`; outbound is `(n−1)²Bf`. Four to eight pilots increases host outbound payload about **5.44×**, not 2×. This excludes provider routing overhead and visual-model cost. Measure actual NIC bytes and provider meters before raising the cap.

### Dedicated relay or all-to-all billed fan-out

A relay with `n` sending clients receives `nBf` and sends `n(n−1)Bf`. Four pilots generate **110.592 MB/hour outgoing** application payload; eight generate **516.096 MB/hour**. Inbound adds 36.864 and 73.728 MB/hour respectively. A player-hosted star and a dedicated relay have different byte totals: do not mix the models.

At a conservative **200 MB/day** GD-Sync allowance, the four-player outgoing-only example allows about **1.81 aggregate room-hours/day** before overhead. If **5 GB/month** is instead the applicable quota, the same simplified model permits about **45.21 aggregate room-hours/month** before overhead. Actual capacity is lower; all rooms share the application's allowance. The conflicting vendor reset period must be resolved, not averaged or combined.

Supabase's four senders at 20 Hz yield 80 incoming and 240 outgoing events/s, **320 events/s** under the documented sent-plus-received model, above Free's 100 events/s. The 200-connection allowance alone cannot qualify this workload. Different batching/broadcast settings change accounting and must be measured. [S24–S25](sources.md#services)

### Optional HTTP directory

Workers Free currently allows **100,000 incoming requests/day**. SQLite DO has separate limits of **100,000 billable requests/day**, **13,000 GB-s/day**, **5 million row reads/day**, **100,000 row writes/day** and **5 GB total storage**. Excess Free operations fail; daily limits reset at 00:00 UTC. These are independent ceilings, not additive credits. [S07–S08](sources.md#services)

For ten continuously advertised rooms and ten continuous browsers, both at 30 s intervals:

- Host heartbeats: `10 × 86,400 / 30 = 28,800 requests/day`.
- Browser polling: another `28,800 requests/day`.
- Baseline total: **57,600 requests/day**, before create/join/resolve/retry/cleanup or unrelated account traffic.
- One persisted row per heartbeat implies at least **28,800 writes/day**; listing ten rows per browser request implies roughly **288,000 reads/day**, before index scans and other storage work.

The proposed 70%-of-quota application threshold leaves headroom but is not a guaranteed abuse shield. Poll only while visible, bound page size, cache where correct, expire entries, back off, and retain direct joining. Public requests can still exhaust a free service; the zero-dollar property comes from the actual Free plan, not optimistic traffic projections.

A continuously active 128 MB DO costs approximately `0.128 × 3,600 = 460.8 GB-s/hour`; `13,000 / 460.8 = 28.21` continuously active object-hours/day across the account. Idle hibernation-eligible objects can consume much less. Do not equate connected sockets with continuous billing under the hibernation API, or assume a repeating timer saves that duration. A lightweight HTTP directory avoids unnecessary always-active room simulation. [S07, S09](sources.md#services)

## Practical limitations and alternative decisions

- **NAT:** a public code, HTTPS heartbeat, STUN response or successful LAN join does not prove an ENet host is reachable. Direct IPv4 needs an accessible route; IPv6 needs compatible endpoints/firewalls. Optional UPnP cannot map ISP equipment. Manual SDP/ICE exchange can demonstrate WebRTC without signaling hosting, but is poor room UX and still may need a relay. [S01, N01, N04–N07]
- **Physics:** 240 Hz RK4, float64 arrays, recovery snapshots and local exact replay do not establish cross-platform input lockstep. Network state is presentation output; local physics remains authoritative for that pilot. [Repository audit](repository-audit.md)
- **Freshness:** official `stable` Godot documentation can differ from the repository's pinned beta. Test its actual API/ABI. Float64 simulation data does not imply a double-precision engine; if a future engine does use double precision, native extensions must match. [N05, N09–N10](sources.md#networking)
- **Assets and identity:** start from an approved bundled subset. Display fallback or reject unsupported content rather than downloading/executing peer resources. A scene/model hash is not a generic proof of every physics and visual dependency. [Repository audit](repository-audit.md#content-and-lifecycle)
- **Public rooms:** require bounded admission, readable names, session kick/block, invite expiry and useful failures. A short human room code is a locator, not a durable identity or sole authorization. Direct P2P may expose network addresses; do not promise IP privacy or automatic encryption. [N02, N11–N12](sources.md#networking)
- **Operations:** trials, donated demonstration relays and unprovisioned cloud VMs are not a dependable service plan. Do not use CI runners or disposable development environments as permanent game hosts. No public uptime/SLA is promised from free quotas.

Unresolved implementation questions are intentionally gates: which stock aircraft/field qualifies first; exact packet/API performance; EOSG on all claimed exports; actual provider-account eligibility; GD-Sync's conflicting quota; Photon Free/Godot traffic enforcement; and real users' network mix. None requires inventing a paid fallback today.
