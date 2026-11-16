# Primary sources

Checked **2026-11-15 (America/Bogota)**. Provider pages are live documents and can change; recheck before integration and release. Source facts, repository observations and proposed engineering targets are distinguished in the [research](README.md) and [plan](../../plans/multiplayer.md). No paywalled or secondary comparison article is required for the decisions.

## Services

| ID | Primary source | Evidence used |
| --- | --- | --- |
| S01 | [Godot high-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html) | ENet, UDP routing, transport modes/channels, native versus web capability |
| S02 | [EOS licensing](https://onlineservices.epicgames.com/licensing) | No royalty/hosting fees for eligible game-related services |
| S03 | [EOSG maintainer documentation](https://3ddelano.github.io/epic-online-services-godot/) | Community-wrapper status, platforms, minimum engine and SDK declarations |
| S04 | [EOSG releases](https://github.com/3ddelano/epic-online-services-godot/releases) | Observed 2.3.1 release, Godot 4.7 loading fix; not 4.8-beta qualification |
| S05 | [EOS overview](https://dev.epicgames.com/docs/epic-online-services/eos-overview?lang=en-US) | Game Services/Connect versus Epic Account Services; P2P and lobby scope |
| S06 | [EOS lobby reference](https://dev.epicgames.com/docs/epic-online-services/multiplayer/lobbies-and-sessions/lobby-interface/lobby-interface-reference) | Lobby lifecycle, membership promotion, 64-member/API limits |
| S07 | [Cloudflare DO pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/) | SQLite Free quotas, refusal/reset behavior, compute/storage metering; updated 2026-11-13 |
| S08 | [Workers limits](https://developers.cloudflare.com/workers/platform/limits/) | Separate Free request and CPU limits; error at daily exhaustion |
| S09 | [DO WebSocket hibernation](https://developers.cloudflare.com/durable-objects/best-practices/websockets/) | Idle connection handling and duration qualification |
| S10 | [GD-Sync plans](https://www.gd-sync.com/plans) | Four-player Free cap; conflicting 5 GB/month card and 200 MB/day comparison |
| S11 | [GD-Sync general information](https://www.gd-sync.com/docs/general-information) | Transfer accounting, daily Free reset and immediate room closure at quota |
| S12 | [netfox hosting](https://foxssake.github.io/netfox/latest/hosting/) | Player hosting, noray/nohub, public evaluation instances and self-host responsibility |
| S13 | [Tailscale pricing](https://tailscale.com/pricing) | Six Personal users/unlimited user devices, eligibility and separately priced resources |
| S14 | [ZeroTier current pricing](https://www.zerotier.com/pricing.md) | Personal ten devices/one network/one admin; effective 2026-10-20 |
| S15 | [Cloudflare TURN FAQ](https://developers.cloudflare.com/realtime/turn/faq/) | Free STUN, TURN allowance and operational limits |
| S16 | [Cloudflare Realtime pricing](https://developers.cloudflare.com/realtime/sfu/platform/pricing/) | Shared TURN/SFU free allowance and paid egress thereafter |
| S17 | [Photon Godot SDK download](https://doc.photonengine.com/fusion-godot/v3-shared-authority/getting-started/sdk-download) | Godot 3.0.0 development preview Build 684, 2026-10-26; explicitly not production |
| S18 | [Photon pricing policy](https://doc.photonengine.com/photon/current/pricing) | Free-plan CCU eligibility/hard caps versus separate traffic overage policy |
| S19 | [Photon Fusion plans](https://www.photonengine.com/Fusion/Pricing) | One-app free 100 CCU and 0.3 TB traffic allowance |
| S20 | [Photon Godot topology choice](https://doc.photonengine.com/fusion-godot/v3-client-server/getting-started/choose-topology) | Shared/client-server options and separate dedicated-server responsibility |
| S21 | [Firebase RTDB limits](https://firebase.google.com/docs/database/usage/limits) | Spark simultaneous connections |
| S22 | [Firebase RTDB billing](https://firebase.google.com/docs/database/usage/billing) | Spark storage and download allowance |
| S23 | [Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans) | No-payment-information Spark, quota interruption and billing-plan changes |
| S24 | [Supabase Realtime limits](https://supabase.com/docs/guides/realtime/limits) | Free connections/event rate and sent/received accounting |
| S25 | [Supabase Realtime pricing](https://supabase.com/docs/guides/realtime/pricing) | Monthly included messages |
| S26 | [Nakama getting started](https://heroiclabs.com/docs/nakama/getting-started/index.html) | Open-source server and deployment responsibility |
| S27 | [Colyseus pricing](https://colyseus.io/pricing/) | Self-hosted software versus managed hosting |
| S28 | [Steam Direct fee](https://partner.steamgames.com/doc/gettingstarted/appfee) | US$100 per new app; no assumption it is already paid |
| S29 | [Oracle Free Tier FAQ](https://www.oracle.com/cloud/free/faq/) | Card verification, eligibility/capacity and trial distinction |
| S30 | [Oracle Always Free resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) | Resource/idle-reclamation limits |
| S31 | [PartyKit shutdown announcement](https://blog.partykit.io/posts/hosted-platform-shutdown) | Hosted platform closed 2026-10-23; direct Cloudflare/PartyServer alternative |
| S32 | [PeerJS maintainer free-TURN notice](https://github.com/orgs/peers/discussions/1172) | Free TURN discontinued; do not infer relay from signaling |
| S33 | [PeerJS cloud](https://peerjs.com/server/cloud) | Shared signaling offer and self-hosting recommendation |

## Networking

| ID | Primary source | Evidence used |
| --- | --- | --- |
| N01 | [Godot ENetMultiplayerPeer](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html) | UDP, client/server/mesh, explicit client cap and bind options |
| N02 | [Godot SceneMultiplayer](https://docs.godotengine.org/en/stable/classes/class_scenemultiplayer.html) | Implementation-private wire format, admission, object decoding and relay |
| N03 | [Godot WebSocketPeer](https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html) | RFC 6455 frames, polling, WSS and queue control |
| N04 | [Godot UPNP](https://docs.godotengine.org/en/stable/classes/class_upnp.html) | Synchronous discovery/mapping, return codes and cleanup |
| N05 | [Godot WebRTC](https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html) | Native extension and signaling requirement; page notes version-update limitations |
| N06 | [WebRTC TURN guidance](https://webrtc.org/getting-started/turn-server) | Relaying when direct connectivity fails |
| N07 | [MDN WebRTC session lifetime](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Session_lifetime) | Application-defined signaling exchange, including manual methods |
| N08 | [Tailscale connection types](https://tailscale.com/docs/reference/connection-types) | Direct, peer relay and DERP behavior |
| N09 | [Godot C++ extension compatibility](https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/about_godot_cpp.html) | Engine/API/precision compatibility requirements |
| N10 | [Godot webrtc-native](https://github.com/godotengine/webrtc-native) | Native extension implementation/releases/build requirements |
| N11 | [W3C WebRTC specification](https://www.w3.org/TR/webrtc/) | ICE policies, peer-address visibility and data-channel semantics |
| N12 | [Cloudflare protocols](https://developers.cloudflare.com/workers/reference/protocols/) | Worker HTTP/WebSocket/TCP capabilities; no native inbound ENet listener |
| N13 | [Steam networking](https://partner.steamgames.com/doc/features/multiplayer/networking) | Steam transport/relay capabilities and platform integration |

The [repository audit](repository-audit.md) cites the immutable project commit directly. Source runtime/configuration takes precedence over stale implementation statements in plans. Vendor maximums and suggested examples do not prove this simulator's performance, compatibility or billable usage.


## Follow-up evidence, 2026-11-16

The original 46-URL register above remains the first-pass source set. The [round-two report](round-2.md) links the added Cloudflare rate-limiter, spending-control, SQLite cursor and lifecycle documentation alongside the corrected calculations. The [EOS trial](eos-trial.md) retains immutable EOSG 2.3.1 source links and Epic identity/policy/relay references. The [protocol contract](../../plans/multiplayer-protocol.md) cites Godot's pinned `cafc17a19` source for polling, root paths, automatic relay, channels and cleanup, plus the audited OpenRC presentation/session interfaces. Follow-up source facts do not establish runtime qualification.

## Twenty practical investigations, 2026-11-16

The [round-three report](round-3-20-investigations.md) keeps each primary reference beside its decision and experiment: official Godot demos, netfox/noray, native WebRTC, Valve GNS, Nakama/Colyseus, Linux network tools, Wireshark, test frameworks/fuzzers, current GitHub/Cloudflare/VPN terms, coturn/RFCs, and OpenRC's own trace/manifest/debug sources. Immutable source pins are used for consequential code findings; moving manuals/service terms carry the research date and require rechecking before adoption. The report is the single source register for this round rather than a duplicated URL list. Source-reading and synthetic Python vectors do not establish engine/export/network compatibility.
