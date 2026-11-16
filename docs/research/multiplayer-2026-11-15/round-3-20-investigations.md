# Twenty practical multiplayer investigations

**MP-00-R3 · 2026-11-16 · research, not runtime qualification.** This round extends branch `plan/multiplayer-zero-budget-2026-11-15` from `0cc7635f9638ae67416198895654ad9694078451`. It identifies reusable examples, tools and tests for the [current plan](../../plans/multiplayer.md), without adding a service dependency. The [protocol](../../plans/multiplayer-protocol.md) remains the authoritative implementation contract. Each numbered investigation below includes a decision, evidence, an integration point and a bounded next experiment.

## Scope and decisions

The application audit remains pinned to `cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`. During this round, remote `main` advanced to [`6dfe1b9179af408f6b765b91ca164e626570db9f`](https://github.com/bultodepapas/OpenRCsimulator/commit/6dfe1b9179af408f6b765b91ca164e626570db9f). A full tree-path comparison found **43 changed paths**, concerning Extra aircraft presentation/customization, Creator, translations and documentation. The inspected kernel/session/frame/protocol integration sources did not change. This is a drift check, not a fresh full audit: reconcile current source and repin the selected stock assets before MP-01a. The research branch was not merged with `main`.

Three bounded researchers covered independent tool/transport/connectivity questions. The lead checked consequential original sources, integrated the findings and requested an independent challenge of datum/timing/vector semantics. No add-on, SDK, service, account, router mapping or packet capture was installed or created. The only new executable artifact is an **offline standard-library packet-vector generator**, with synthetic outputs. Experiments below remain pending.

**Decisions advanced:** use existing OpenRC tooling first; distinguish friendly-LAN examples from safe admission; describe position/velocity at the fixed body datum O; start with linear position interpolation and shortest-path quaternion slerp, with extrapolation disabled; hold UPnP automation until mapping ownership can be proved; keep optional discovery/VPN/relay routes separate. The EOS adoption blockers and five-room directory starting cap remain in force.

| # | Investigation | Disposition | Owning phase |
| --- | --- | --- | --- |
| 01 | Godot lobby/Bomber examples | Reuse lifecycle ideas; fix teaching shortcuts | MP-01/02 |
| 02 | netfox and snapshot interpolation | Study; use a small OpenRC presentation buffer | MP-01c |
| 03 | noray NAT orchestration | Conditional local spike; no hosted entitlement assumed | After MP-02 |
| 04 | Native WebRTC and signaling | Defer another adapter until needed | After MP-04 |
| 05 | GameNetworkingSockets and Steam boundaries | Defer native adapter; Steam fee is not a free prerequisite | After MP-04 |
| 06 | Nakama/Colyseus room examples | Borrow failure scenarios; defer backend adoption | MP-01b / later |
| 07 | UDP impairment with netem | Preferred controlled-network test tool | MP-04 |
| 08 | Wireshark/TShark accounting | Reuse bounded local captures | MP-02/04 |
| 09 | Checked multi-process Godot tests | Extend existing runner; defer extra test frameworks | MP-01/02 |
| 10 | Property-based/fuzz testing | Fixed corpus first; fuzz the real decoder later | MP-01a/b |
| 11 | GitHub Actions | Reuse existing partitions within verified free allowance | MP-01/07 |
| 12 | Local Workers/Durable Objects testing | Conditional local directory prototype | MP-06 |
| 13 | LAN discovery | Optional after manual joining; friendly LAN only | MP-02/03 |
| 14 | UPnP, NAT-PMP and PCP | Hold automation; manual fallback | MP-03 |
| 15 | Tailscale/ZeroTier | Optional user-managed testing route | MP-03 |
| 16 | STUN/coturn diagnostics | Diagnostic evidence, never reachability proof | MP-03 |
| 17 | Existing flight logs and ghost traces | Reuse for presentation fixtures; later ghost feature | MP-01c / MP-08 |
| 18 | Binary codec and golden vectors | Research generator delivered; Godot validation pending | MP-01a |
| 19 | Existing debug tools and plots | Add bounded wall-time network metrics later | MP-02/04 |
| 20 | Content identities and manifests | Reuse validated loaders; close admission coverage | MP-01a/04 |

Efforts below are **engineering estimates for one familiar developer**, not measured durations or twenty additions to the existing phase totals. Several are alternative or deferred spikes. Use existing computers and internet; free software does not supply free hosting, bandwidth, accounts or unlimited capacity. No dependency is adopted by linking to it. Pin the selected release/source and its licenses before any future import; an upstream compatibility statement is not a test on OpenRC's Godot **4.8-beta2**.

## 01. Godot lobby and Bomber examples

**Useful material.** The official [lobby tutorial](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html#example-lobby-implementation), [Bomber game state](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/networking/multiplayer_bomber/gamestate.gd) and [lobby UI](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/networking/multiplayer_bomber/lobby.gd) provide working-shaped examples of registration, disconnect handling, loading barriers and host controls. The demo repository declares MIT licensing; asset notices remain separate. The pinned development snapshot is a reference, not a qualified OpenRC build.

**Finding and decision.** The lobby tutorial counts `player_loaded()` calls instead of maintaining a once-per-current-peer READY set. Duplicate calls can increment its teaching counter. Bomber's host function ignores the `create_server()` return. Both use ordinary scene multiplayer/RPC patterns. Reuse the lifecycle checklist, not the admission implementation: OpenRC needs its standalone API, disabled automatic relay, per-generation readiness and checked bind errors.

**Next experiment — MP-01b/02b, 0.5–1 day.** In the proposed room-state/UI fixtures, exercise duplicate and stale READY, occupied-port failure, cancellation during load and host loss. Pass if no early start, stale roster or retained callback is possible and failure restores usable controls. A remote READY must never resume local input. Stop if the reference requires replacing the existing shell or tree-wide multiplayer configuration. No server or account is required; full UI work is already part of the main plan.

## 02. netfox and snapshot interpolation

**Useful material.** [netfox v1.35.3 TickInterpolator](https://github.com/foxssake/netfox/blob/c7fc6ea52b4e9087c980d9ca1f8c3826e3a6caa4/addons/netfox/tick-interpolator.gd) and its [interpolators](https://github.com/foxssake/netfox/blob/c7fc6ea52b4e9087c980d9ca1f8c3826e3a6caa4/addons/netfox/interpolators.gd) show property interpolation and teleport handling; the [license is MIT](https://github.com/foxssake/netfox/blob/c7fc6ea52b4e9087c980d9ca1f8c3826e3a6caa4/LICENSE). Glenn Fiedler's original [snapshot-interpolation tutorial](https://gafferongames.com/post/snapshot_interpolation/) explains buffering, linear/Hermite position interpolation and quaternion slerp.

**Finding and decision.** netfox's two-state smoother uses `NetworkTime.tick_factor` and writes managed properties around its tick loop. It is not OpenRC's bounded history of remotely accepted, wall-timestamped samples. Do not attach it to solver state or import rollback machinery. Fiedler's example delay is tied to his own rate/loss/jitter conditions, not proof for ours.

Start with linear position interpolation plus normalized shortest-path slerp. **Disable extrapolation initially.** A simulation velocity in metres per simulation-second cannot simply multiply an interval in wall-seconds during slowdown. A 100 ms stall with a last velocity of 20 m/s can produce a spurious 2 m prediction before the two-second DEGRADED detector reacts. Hermite tangents have the same time-unit issue.

**Next experiment — MP-01c, 1–2 days.** Compare algorithms on identical taxi, flight, fast-roll, pause/reset and short-stall traces, including stalls before DEGRADED and startup/rebaseline without a lower interpolation bracket. Require no forward-then-backward startup motion, the plan's delayed-truth motion targets and unchanged local accepted state. Preserve float64 until render conversion. Any later extrapolation needs a separately demonstrated timing policy and stays below the existing 100 ms ceiling. No dependency or service is needed.

## 03. noray NAT orchestration

**Useful material.** The pinned [noray protocol/configuration](https://github.com/foxssake/noray/blob/e5a9ff7b7978e467a8a432f0300ce007602277c1/README.md) covers TCP registration, shareable OpenID, private PID, UDP endpoint registration, hole punching and relay fallback. The server is MIT licensed. The [hosting guidance](https://foxssake.github.io/netfox/latest/hosting/) presents the free hosted instance as a way to try the software before self-hosting, not a production capacity or availability commitment.

**Finding and decision.** The [netfox bootstrapper](https://github.com/foxssake/netfox/blob/c7fc6ea52b4e9087c980d9ca1f8c3826e3a6caa4/examples/shared/scripts/noray-bootstrapper.gd) demonstrates handshake and reuse of the local port for ENet, but explicitly enables `server_relay=true` on the default API. Copying it unchanged defeats our application-first host validation. Godot's automatic guest forwarding and noray's network relay are different layers. NAT punching can fail; relays consume server ports and bandwidth. Keep noray a conditional experiment, not another required backend.

**Next experiment — after MP-02, 1–2 days.** On an already-owned local host, qualify registration, handshake, port reuse, timeout/cancel and cleanup with explicit application forwarding intact. Pass sender-binding and three-process forwarding fixtures before testing two independent networks. A local orchestrator result proves neither Internet reachability nor relay availability. Stop if a reachable owned host, bounded relay capacity or exact-engine evidence is unavailable. Preserve manual ENet; do not provision a paid host or treat a community endpoint as guaranteed infrastructure.

## 04. Native WebRTC and signaling

**Useful material.** Godot's [webrtc-native 1.2.2 release](https://github.com/godotengine/webrtc-native/releases/tag/1.2.2-stable), commit `62135fc034cbdc5aee177136e526e3ead3cc563a`, describes a Godot 4.3+ extension with libdatachannel 0.24.6 and mbedTLS 3.6.7. The extension is MIT; dependencies retain their own notices. The official [minimal demo](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/networking/webrtc_minimal/minimal.gd) exchanges data between two peers in one process. The separate [signaling protocol](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/networking/webrtc_signaling/README.md) and [client example](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/networking/webrtc_signaling/client/multiplayer_client.gd) demonstrate WebSocket offer/answer/candidate exchange and STUN configuration.

**Finding and decision.** Signaling exchanges connection metadata; STUN helps discover candidates; TURN relays traffic when needed. These are separate operational requirements. A same-process demo and a broad Godot version statement establish neither cross-network success nor native 4.8-beta2 exports. Defer this adapter unless a measured ENet/EOS limitation justifies it.

**Next experiment — after MP-04, 2–4 days for local feasibility.** Load the pinned extension, exchange bounded controls/poses, inspect mode/channel semantics and teardown, then separately qualify direct and controlled relay paths on each required OS. Stop on failed loads, sender attribution or missing binaries. Export and restrictive-network qualification are additional work. Local testing needs no paid TURN; no hosted relay, public STUN entitlement or signaling deployment is assumed.

## 05. GameNetworkingSockets and Steam boundaries

**Useful material.** Valve's [GameNetworkingSockets v1.6.1](https://github.com/ValveSoftware/GameNetworkingSockets/blob/d534c19aa760df3fb75fd20db13ba1932b8a5463/README.md), commit `d534c19aa760df3fb75fd20db13ba1932b8a5463`, is BSD-3-Clause. Its message transport offers reliable/unreliable delivery, encryption, lanes and impairment settings. The [P2P guide](https://github.com/ValveSoftware/GameNetworkingSockets/blob/d534c19aa760df3fb75fd20db13ba1932b8a5463/README_P2P.md) describes the native ICE implementation, built by default, and the separate signaling/STUN/TURN requirements. The [chat example](https://github.com/ValveSoftware/GameNetworkingSockets/blob/d534c19aa760df3fb75fd20db13ba1932b8a5463/examples/example_chat.cpp) shows listen, accept, poll and close while warning that it is not robust production server code.

**Finding and decision.** Open-source GNS can run without Steam. Steam authentication, Steam signaling and Steam Datagram Relay are distinct services; source availability does not grant unrestricted SDR access. [Steam Direct](https://partner.steamgames.com/doc/gettingstarted/appfee) currently requires US$100 per new app, so an unpaid Steam app cannot become a mandatory zero-spend dependency. GNS also needs a new native Godot adapter; it does not implement our replicas or replace ENet transparently.

**Next experiment — optional after MP-04, 3–6 days.** Map callback identity, polling, delivery modes, channels and close semantics to the existing protocol before building a small two-process adapter. Require the same sender-binding and lifecycle tests as ENet. Stop on incompatible semantics, missing native exports or service prerequisites. This estimate excludes release qualification and signaling/relay operation. No Steam enrollment, purchase or server is part of the proposal.

## 06. Nakama and Colyseus room examples

**Useful material.** Nakama's Apache-2.0 [TypeScript match handler](https://github.com/heroiclabs/nakama-project-template/blob/6cab10c292049449d41882081a732c3bda6a1c3c/match_handler.ts) illustrates join attempts, reservations, presence and idle cleanup. Its [Godot client](https://github.com/heroiclabs/nakama-godot) is a separate integration to pin and qualify. Colyseus's MIT [reconnection example](https://github.com/colyseus/colyseus-examples/blob/ae39826b6348edfdc4f1a67bed634c6468b409f4/src/rooms/04-reconnection.ts) distinguishes drop, a ten-second reconnect allowance, reconnect and leave; [the documentation](https://0-17.docs.colyseus.io/) distinguishes self-hosting from managed hosting.

**Finding and decision.** The pinned Nakama example increments `joinsInProgress` in a disconnected-user branch while returning `accept: false`. Without compensation, this can retain reservations: a useful source-level counterexample for our tests, not a demonstrated production exploit. Colyseus's example package has ranged dependencies, not a qualified deployed dependency set. Neither license supplies a durable free server/database or solves host migration. Defer both backends for the player-hosted first product.

**Next experiment — MP-01b, 0.5–1 day.** Borrow scenarios: simultaneous applicants for the last slot, rejected reconnect, cancelled admission, idle expiry and host loss. Require each reservation to release exactly once and stale connections never to reclaim ownership. If a server-owned product is later justified, evaluate a pinned local backend separately. Stop if the first LAN state machine begins requiring a remote database or account. These state fixtures use existing local tools; backend implementation, operations and abuse controls need another estimate.

## 07. UDP impairment with netem

**Useful material.** Linux [network namespaces](https://man7.org/linux/man-pages/man8/ip-netns.8.html), [veth pairs](https://man7.org/linux/man-pages/man4/veth.4.html) and [tc netem](https://man7.org/linux/man-pages/man8/tc-netem.8.html) can isolate stacks and impair outgoing UDP. [Toxiproxy](https://github.com/Shopify/toxiproxy) is a TCP proxy; it cannot reproduce Gate B on ENet datagrams.

**Decision and example.** Use a disposable, owned Linux test host/VM. Give H and G1–G3 separate namespaces, one subnet/veth pair per guest, and an independent egress qdisc at **both ends** of each pair. Inside the appropriate namespaces, an illustrative pair is:

```sh
tc qdisc add dev g1 root netem delay 50ms 20ms loss random 2% seed 101
tc qdisc add dev h1 root netem delay 50ms 20ms loss random 2% seed 102
```

These are proposed commands, not executed setup. Verify installed kernel/iproute2 support, record versions, all six directional placements, `tc -s qdisc`, queue/capture drops and cleanup. Do not apply them to a production NIC. Seeds do not fix scheduling or packet order. Two independently lossy links yield `1 - 0.98² = 3.96%` expected compounded loss, not 2%.

**Next experiment — MP-04, 1–2 days before the game soak.** First qualify an isolated pair with 10,000 numbered datagrams each way and a shared-host clock. Check the requested delay/jitter profile with documented timing tolerance, approximately 1.5–2.5% observed per-link loss, and no unexplained drops; then qualify all directions. Stop on unsupported options, unknown ownership or failed cleanup. This synthetic result does not pass the separate 60-minute game gate. Privileges and existing Linux hardware are needed; no hosted emulator is required.

## 08. Wireshark and TShark traffic accounting

**Useful material.** Official [dumpcap](https://www.wireshark.org/docs/man-pages/dumpcap.html) and [TShark](https://www.wireshark.org/docs/man-pages/tshark.html) support bounded captures and field extraction. The community [ENet Lua dissector](https://github.com/cgutman/wireshark-enet-dissector/blob/master/enet.lua) declares GPLv3 and needs explicit Decode As; its compatibility with Godot's fork is unverified. Keep it optional and external. Basic UDP fields are sufficient for initial accounting.

**Decision and example.** Capture one owned test flow with dummy credentials and a new output path:

```sh
dumpcap -i IFACE -p -f 'udp and host 192.0.2.11 and port 42424' \
  -s 0 -a duration:60 -a filesize:5120 -w flow.pcapng
```

Replace the documentation address, interface and proposed port with the actual isolated fixture. Either stop limit may end collection. The [pinned Godot sender](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/multiplayer/scene_multiplayer.cpp#L439-L455) adds one command byte before ENet/UDP/IP overhead. A 20 Hz × 128-byte sender produces 2,560 application bytes/s, not 2,560 physical-wire bytes/s. UDP length includes its eight-byte header; captured frame length may omit physical overhead or reflect offload.

**Next experiment — MP-02/04, 0.5–1 day.** Reconcile a 60-second capture with application send counters and known pose/control records, separating direction and overhead. Mark capture loss, truncation or dissector disagreement inconclusive; a send or capture does not prove receipt. Retain raw pcaps locally because cleartext endpoints/capabilities can be present. Existing free tools suffice; none were installed or run here.

## 09. Checked multi-process Godot tests

**Useful material.** Reuse [run_checked.py](../../../tools/godot/run_checked.py), the [runner contract](../../../tools/godot/README.md) and [test queue](../../../tools/testqueue/README.md), alongside the official [Godot CLI guide](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html). [GUT](https://github.com/bitwes/Gut/blob/main/README.md) is MIT and its 9.7.1 row names Godot 4.7.x; MIT [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4/blob/master/README.md) master v7.0.0 names 4.8.dev7. Neither proves our exact beta, and neither is required just to manage two processes.

**Finding and decision.** The existing checked runner catches errors even when Godot exits zero. Its collector explicitly flushes the log at stream end, so a supervisor must not rely on live log-tail readiness. Use a run-unique atomic readiness file with endpoint/run identity, separate output/profile directories, distinct completion markers and a bounded watchdog. Independent codec tests can use the pool; dependent host/guest processes need **one admitted composite session**, not separately scheduled jobs that may land on different machines.

**Next experiment — MP-02a, 1–2 days after the adapter exists.** Launch two checked processes, complete admission and one golden exchange, then refuse an incompatible version. Pass only with both complete successful receipts, matching identities and confirmed teardown of owned children. A timeout, missing marker or child failure fails the composite result. Import resources using existing rules. Stop if additional frameworks merely duplicate the current runner. Loopback does not establish physical LAN, native OS or network-impairment performance. No new test dependency or hosted run is needed.

## 10. Property-based and fuzz testing

**Useful material.** [Hypothesis settings](https://hypothesis.readthedocs.io/en/latest/settings.html) describe generated/shrunk Python cases and reproducibility limits; its [license is MPL-2.0](https://github.com/HypothesisWorks/hypothesis/blob/master/LICENSE.txt). [Atheris](https://github.com/google/atheris) is Apache-2.0 coverage-guided Python fuzzing. These are possible later tools, not new dependencies now.

**Decision.** Start with the [synthetic vectors](../../../research/multiplayer/packet-vectors.json), fixed boundary cases and deterministic mutations under the existing checked GDScript runner. Fuzzing a Python model exercises that model, not the actual Godot decoder. A future Python generator must feed raw cases into a bounded batch harness that executes the real GDScript code; coverage claims must identify what was instrumented.

**Next experiment — MP-01a/b, 1–2 days after the codec.** Cover lengths 0–127, overlength, wrong framing/flags, nonfinite values, limits after float32 rounding, quaternion norms, ownership/config/epoch rejection, quantization ties, invalid control UTF-8/length and sequence wrap/half-range. Snapshot replica state before invalid input and require no partial mutation, crash, timeout or engine error. Compare valid decoded fields with independently reviewed bytes, not only round trips through one implementation. Save minimal failing inputs and version/seed identities as permanent regression fixtures.

Stop and repair a fixed-corpus failure before broad fuzzing. Adopt a package only for a demonstrated gap, pin its version and preserve notices; a random seed alone is not permanent cross-version reproducibility. The delivered corpus does not cover complete controls, clocks or lifecycle. Local tools suffice; no hosted fuzzing service is required.

## 11. GitHub Actions and the zero-spend boundary

**Useful material.** The pinned [OpenRC CI workflow](https://github.com/bultodepapas/OpenRCsimulator/blob/0cc7635f9638ae67416198895654ad9694078451/.github/workflows/ci.yml) already has Linux integration/unit partitions, native Windows jobs and a [macOS workflow](https://github.com/bultodepapas/OpenRCsimulator/blob/0cc7635f9638ae67416198895654ad9694078451/.github/workflows/native-macos.yml). Many diagnostics retain seven days; visual shadow is separately opt-in. The files were inspected through the complete Git tree despite the sparse checkout.

**Finding and decision.** Current [GitHub billing documentation](https://docs.github.com/en/billing/concepts/product-billing/github-actions) makes standard hosted runners free for public repositories, while larger runners remain billed. Private-repository usage draws from shared included compute; GitHub Free currently lists $12 monthly included value and 500 MB artifact storage. Artifacts share storage allowance with Packages; caches are separate. Later deletion does not erase already accrued storage usage. Actual account budget/stop settings were not inspected, so an arbitrary CI matrix is not guaranteed zero-cost.

**Next experiment — MP-01/07, 0.5–1 day.** Add a focused future MP test to its existing partition, preserve required selection/completion receipts and measure incremental duration/artifact size. Verify relevant visibility, runner and billing boundary before new hosted work; use existing local admission if that cannot be established. Stop rather than weaken a required gate or introduce billable runners/storage. Real OS/network qualification stays separate. No CI configuration or hosted run is changed here; publishing this feature branch alone does not trigger the inspected required workflow.

## 12. Local Workers and Durable Objects testing

**Useful material.** Cloudflare's current [Vitest guide](https://developers.cloudflare.com/workers/testing/vitest-integration/write-your-first-test/) uses `@cloudflare/vitest-plugin` with Vitest 4.1+, and the [upstream examples](https://github.com/cloudflare/workers-sdk/tree/main/fixtures/vitest-plugin-examples/durable-objects) include Durable Objects. Do not assume an older pool example is the current API. Pin selected Node/Wrangler/Miniflare/plugin versions, compatibility date and licenses when implementing. Use local execution/bindings only; remote bindings can touch real services.

**Finding and decision.** The [SQLite API](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/) warns that cursors across `await` lack snapshot isolation; fully consume synchronously and then record final `rowsRead`/`rowsWritten`, which can increase during iteration. Alarms also have write cost. This reinforces lazy expiry and measured quotas rather than one continuously active object/timer per room.

**Next experiment — conditional MP-06, 2–3 days.** Model five rooms, 30 s heartbeat and 90 s TTL with an injected clock. Test 89/90 s boundaries, revoked/wrong owner capability, private-room exclusion, bounded bodies and owner-only changes. Independently exhaust request/DO/read/write/duration allowances at the plan's 70% operating thresholds; include counters, indexes, retries and cleanup. Require predictable refusal and continued manual direct join. Check quota bypass behavior separately before deployment.

Local simulation proves application behavior, not [provider Free-limit enforcement](https://developers.cloudflare.com/durable-objects/platform/pricing/), deployed bills, distributed abuse protection or UDP reachability. Stop if the experiment needs remote bindings, accounts or a second backend before route selection. No deployment, domain or paid plan is required.

## 13. Optional LAN discovery

**Useful material.** Pinned Godot [PacketPeerUDP documentation/examples](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/PacketPeerUDP.xml) support IPv4 broadcast and interface-specific multicast. [UDPServer](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/UDPServer.xml) creates per-source peers and needs polling; its teaching peer list is not a bounded discovery browser. These built-in MIT components need no add-on.

**Candidate and limit.** After manual joining, an opt-in browser can send a fixed small IPv4 query from an ephemeral socket; a host replies unicast to the observed sender with a marker and ENet port. Keep responses shorter than requests, cap rate/candidates, expire entries and close on cancel. Never auto-join or transmit invite capabilities in discovery. A reply is an untrusted hint, not admission or authenticated identity.

The pinned [UDP polling source](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/io/packet_peer_udp.cpp) drains until `ERR_BUSY`, even after its queue fills. Limiting a GDScript receive loop therefore does not bound engine CPU under sustained traffic. Qualify only friendly LAN until lower-level limits are proved. IPv6 multicast needs scoped/interface tests; [mDNS](https://datatracker.ietf.org/doc/html/rfc6762) is a separate protocol, not this broadcast format.

**Next experiment — optional after MP-02, 1–2 days plus OS checks.** On two same-subnet machines, require a fresh valid candidate, stale/malformed-entry rejection and a successful manual join with discovery blocked. Stop if discovery delays the first manual LAN release. VLANs, firewalls and VPNs can hide broadcasts; retain explicit IP/port. No service/account is needed.

## 14. UPnP ownership and alternative mapping protocols

**Useful material.** The exact-engine [UPNP docs and threaded example](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/upnp/doc_classes/UPNP.xml) describe blocking calls, leases and mapping conflicts. The [UPNPDevice API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/upnp/doc_classes/UPNPDevice.xml) exposes add/delete but no mapping-ownership query or conditional deletion. The built-in implementation uses MiniUPnP; this does not establish [NAT-PMP](https://datatracker.ietf.org/doc/html/rfc6886) or [PCP](https://datatracker.ietf.org/doc/html/rfc6887) support through this API.

**Finding and decision.** An add can overwrite a mapping; delete names only external port/protocol. Success plus a local `created_by_us` flag cannot prove safe later cleanup after another actor replaces it. Keep automation off and blocked until collision-safe creation/ownership/cleanup, including races, are demonstrated. Otherwise offer manual forwarding/direct join. A finite lease is preferable to permanent fallback, but proves neither ownership nor external reachability. A local mapping alone does not establish a path through ISP CGNAT: optional [UPnP-to-PCP interworking](https://datatracker.ietf.org/doc/html/rfc6970#section-3) exists, but router/provider support is unverified.

`discover(2000)` describes response waiting, not a proven total deadline for all blocking router operations. Off-thread work needs session generations, cancellation handling and safe late completion; do not block UI waiting for an uncancellable worker.

**Next experiment — optional MP-03 investigation, 2–4 days.** A fake gateway must cover preexisting/replaced mappings, denied/permanent-only gateways, late completion and cancellation without touching unrelated mappings. Then qualify real owned routers/two networks. Stop on ambiguous ownership or worker lifetime; a native adapter requires separate estimation. This optional work does not expand the core commitment. Existing hardware only; no relay service.

## 15. User-managed Tailscale and ZeroTier

**Useful material.** Tailscale's [private game-server walkthrough](https://tailscale.com/docs/use-cases/personal-or-at-home-use/share-private-game-server) illustrates joining by private address and game port. Keep this outside OpenRC: willing eligible testers manage their own client and enter the virtual endpoint through ordinary manual join. No bundled SDK or account dependency is proposed.

As checked on 2026-11-16, [Tailscale Personal](https://tailscale.com/pricing) permits six users and unlimited user devices for noncommercial personal use; tagged/ephemeral resources have separate limits. [ZeroTier Personal](https://www.zerotier.com/pricing.md), effective 2026-10-20, lists ten users, ten devices, one network and one administrator, with no added devices on that tier. These are dated service terms, not a guarantee of commercial-team eligibility. Record actual client versions in future tests.

**Finding and decision.** Tailscale's [route documentation](https://tailscale.com/docs/reference/connection-types) distinguishes direct, DERP and peer-relay paths. Inspect `tailscale status`/`tailscale ping` after communication and during changes; a relay may affect latency and throughput. Do not require broadcast discovery over the overlay. A successful VPN session proves that route, not unaided ENet NAT traversal or an OpenRC-owned free relay.

**Next experiment — MP-03, 0.5–1 day plus testers.** On two already eligible consenting devices across separate networks, record route, versions, IP family and a 30-minute ENet session. Require usable connection/failure reporting under the relevant plan criteria. Stop if eligibility/setup requires spending or mandatory project accounts. Ordinary LAN/direct access remains account-free; no auto-upgrade is allowed.

## 16. STUN and coturn diagnostics

**Useful material.** coturn 4.18.0's [turnutils guide](https://github.com/coturn/coturn/blob/4.18.0/README.turnutils) documents `turnutils_stunclient` and `turnutils_natdiscovery`; its [license is BSD-3-Clause](https://github.com/coturn/coturn/blob/4.18.0/LICENSE). Example for a future authorized endpoint:

```sh
turnutils_stunclient -p 3478 -t 3000 <stun-server-ip>
```

This command was not run. Pin any installed binary; these remain external developer tools. The [server example](https://github.com/coturn/coturn/blob/4.18.0/examples/etc/turnserver.conf) explains the multiple listening addresses needed for full behavior discovery. [RFC 5780](https://datatracker.ietf.org/doc/html/rfc5780) describes experimental observations, not a universal connectivity verdict.

**Finding and decision.** A STUN binding observes the tool's own socket at a particular server endpoint; the cited client can make additional RFC 5780 observations when supported. A different ENet socket or destination need not have the same mapping. An unsupported behavior-discovery endpoint means inconclusive, not “blocked network.” A public IP, directory heartbeat or STUN response does not prove a second peer can join the actual listening ENet port. Nor does a timeout alone diagnose CGNAT. Plain ENet also does not become TURN-capable by installing coturn; it needs a compatible adapter and actual relay allocation/credentials/bandwidth.

**Next experiment — MP-03, 1–2 days for diagnostics design.** Test actual ENet join from a consenting client on another network and an intentionally unreachable case. Require bounded timeout with accurate, non-diagnostic wording and local redacted evidence. Stop on paid infrastructure or claims stronger than observations. Synthetic UI outcomes test wording only; no server, network probe or hosted TURN was created here.

## 17. Flight logs, ghosts and the correct aircraft datum

**Useful material.** OpenRC already has the [flight-log workflow](../../FLIGHT-LOGGING.md), [stdlib CLI](../../../tools/flight_log/flight_log.py), [recorder](../../../app/sim/flight_log.gd) and [render-frame helpers](../../../app/render/frames.gd). Reuse complete, identified `.orfl` records and their CSV/report pairs for remote-presentation traces. Exact replay is a separate same-build/platform claim; export is not a ready-made 3D ghost player. Existing pause events add no simulation time, so a log's `tick × dt` cannot recover actual wall-time stalls or pause duration. Any playback arrival/wall schedule must be explicitly synthetic or separately recorded.

**New correction.** The [session source](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/sim/flight_session.gd#L580-L585) locates fixed body datum O. [Mass inventory](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/physics/mass_inventory.gd#L175-L180) defines O at the authored reference-state CG; live fuel CG and selected starting-fill CG may differ. Rotate O's body velocity into NED, and apply the constant authored model offset. Do not shift the network transform to live CG because of legacy helper names/comments. The proposal's bytes stay unchanged; their position/velocity meaning is corrected.

**Next experiment — MP-01c, 1–2 days.** Replay a short identified trace into a visual-only replica at synthetic 20 Hz; test NED axes, yaw/roll, trailing-edge surfaces, reset and pause. Holding O pose/attitude fixed while changing live `cg_body_m` must leave the model root unchanged, including a rotated case. No remote `FlightSession` is needed. Stop on ambiguous datum, missing surface semantics or incomplete evidence. File-based shared ghost challenges are promising MP-08 work with no server, separately scoped; they do not establish live networking or fair scores.

## 18. Binary codec references and delivered vectors

**Useful material.** Python's [struct specification](https://docs.python.org/3/library/struct.html) makes `<` explicitly little-endian with standard sizes and no native padding. Godot's [StreamPeerBuffer](https://docs.godotengine.org/en/stable/classes/class_streampeerbuffer.html) provides an in-memory binary cursor; [pinned StreamPeer](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/io/stream_peer.cpp#L128-L215) with `big_endian=false` and [marshalling primitives](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/io/marshalls.h#L76-L115) provide an auditable candidate. The [PackedByteArray docs](https://docs.godotengine.org/en/latest/classes/class_packedbytearray.html) explicitly caution that its encoding representation is an implementation detail for external applications. Do not substitute Variant/object serialization for the specified wire format.

**Delivered research asset.** [packet_vectors.py](../../../research/multiplayer/packet_vectors.py) emits [packet-vectors.json](../../../research/multiplayer/packet-vectors.json): **26 packets** (three passing outer-field examples and 23 malformed cases), seven sequence cases, six contextual admission cases and five quantization cases. It uses only the standard library and no network. Examples cover identity/yaw, old negative paused time, nonfinite/bounds/framing failures and little-endian fields. “Pass” means outer guards only: selected-aircraft limits, actual sender/roster/config/epoch and time context remain required.

```sh
python3 -B research/multiplayer/packet_vectors.py > /tmp/openrc-mp-vectors.json
```

Use a new output path when retaining evidence. The file includes raw encoded throttle; the protocol now specifies validated normalized throttle rounding to nearest, positive half upward. Surface ties remain half away from zero.

**Next experiment — MP-01a, 0.5–1 day after codec creation.** Match every byte with an independently written Godot encoder/decoder and manual offset anchors, then prove atomic rejection. Precheck length before buffer reads; explicit endianness is not validation. Stop on any mismatch; Python regeneration alone proves neither Godot compatibility nor networking. Full controls/clock/lifecycle fixtures remain separate work.

## 19. Existing debug metrics, PlotJuggler and Perfetto

**Useful material.** The [debug bridge](../../../tools/debug/README.md) already supports state, frames, logs and CSV watches; [Godot tools](../../../tools/godot/README.md) already export checked incident/Perfetto evidence. Godot's [custom monitor tutorial](https://docs.godotengine.org/en/latest/tutorials/scripting/debug/custom_performance_monitors.html) shows lightweight counters. [PlotJuggler](https://github.com/PlotJuggler/PlotJuggler) and its [CSV loader](https://github.com/PlotJuggler/pj-official-plugins/tree/main/data_load_csv) provide external time-series inspection; current core licensing is [MPL-2.0](https://github.com/PlotJuggler/PlotJuggler/blob/main/LICENSE.md). Perfetto accepts [external trace formats](https://perfetto.dev/docs/getting-started/other-formats). No plotting SDK or telemetry SaaS needs embedding.

**Finding and decision.** Tick-based watches stop when the local simulation pauses, exactly when network routing/heartbeats must continue. Proposed network metrics therefore belong to the always-processing session, sampled on monotonic wall time. Record send/receive counts and bytes, sequence gaps, rejection reasons, history occupancy, offset/RTT/uncertainty, pose age, interpolation misses, stale time and poll/callback cost. Distinguish application gaps from proven wire loss and unsynchronized timestamps from measured one-way latency.

**Next experiment — MP-02/04, 0.5–1 day.** Expose bounded, read-only summaries through the existing **loopback-only** bridge; keep identifiers/capabilities redacted. Use constant counters and a capped ring with low-rate flushes, not per-packet disk writes. Compare metrics during live pause, disconnect and controlled stall, and compare enabled/disabled overhead at 1080p. Pass only if time coverage, units, bounds and the plan's CPU target hold. Stop if diagnostics alter the solver or require public debug access. New metric/export schema work is pending; existing exporters do not automatically understand proposed networking fields. Local files/tools only.

## 20. Content identities and admission manifests

**Useful material.** [ScenarioConfig](../../../app/scenarios/scenario_config.gd) already validates source identities, while [ModelRegistry](../../../app/aircraft/model_registry.gd) checks the model manifest and dependency closure; alternate liveries are validated on use. Godot's [HashingContext example](https://docs.godotengine.org/en/latest/classes/class_hashingcontext.html) shows incremental SHA-256 without loading a whole large file. Reuse these MIT repository/engine facilities instead of inventing a package download service.

**Finding and decision.** The [scenario digest](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/scenarios/scenario_config.gd#L190-L200) canonicalizes to twelve significant digits. It is not bit-exact equality of every float. Cached top-level hashes are not permission to skip the uncached launch validation. A model-manifest hash and its validated dependency closure cover different claims; a chosen nondefault livery needs its own on-use validation. SHA-256 detects content mismatch under an agreed manifest; it does not authenticate a hostile sender or make downloaded code safe.

**Next experiment — MP-01a/04, 1–2 days within admission work.** Pin one stock field/aircraft/model/configuration and validate local sources before advertising readiness. Store common source/protocol identities separately from OS-specific package hashes. In disposable fixtures, alter aircraft bytes, a manifest dependency, selected livery and a scenario value below the canonical precision; require either explicit versioned compatibility or refusal, never silent mismatch. Validate through local allowlisted IDs, not peer-supplied paths. Fail before scene mutation and leave a useful error. Stop on missing dependency coverage; no automatic assets/skin download is part of this plan. Recheck against current `main`, whose Extra presentation changed during this round.

## Work selected from these investigations

The first implementation sequence remains **MP-01a → MP-01b → MP-01c → MP-02a/b/c**. Use 18/20 for codec/content fixtures; 01/06/10 for state-machine cases; 02/17 for visual-only playback; 09/19 for process ownership and observability. Use 07/08 before the four-pilot impairment gate. Connectivity extras 03/13–16 are optional after manual LAN; native adapters 04/05 and backend adoption 06 do not block it. Directory work 12 is conditional on the selected MP-06 route.

The concrete checks performed this round, source-drift limit and unexecuted gates belong in [verification](verification.md#mp-00-r3-twenty-investigations--2026-11-16). Do not turn the research examples, synthetic vectors or library version tables into claims that multiplayer now works.
