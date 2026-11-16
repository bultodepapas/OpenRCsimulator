# Multiplayer research, round two — 2026-11-16

**MP-00-R2.** This follow-up advances the existing branch from `81af96688e8111173f15b66e54fdd9dba19d1e02`. GitHub `main` still points to the audited `cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`; no production drift was found. The [original comparison](README.md) retains the broader options, while the [current plan](../../plans/multiplayer.md) owns decisions. This round uses pinned engine/wrapper source and official service documentation. It does not deliver multiplayer runtime.

## Decisions advanced

| Question | Finding / decision | Authoritative follow-up |
| --- | --- | --- |
| Can Godot defaults implement our host validation model? | Automatic relay must be disabled; one manually polled API owner and an application roster are required. Raw packet sizes and application queues are separate from engine transport limits | [MP-01/02 adapter and protocol](../../plans/multiplayer-protocol.md) |
| Can the existing 128-byte proposal be made unambiguous? | Define all offsets; add a 64-bit room incarnation within the same total budget; specify surface-angle semantics, status revisions, baseline ordering and sequence wrap | [Snapshot contract](../../plans/multiplayer-protocol.md#2-candidate-snapshot-v1-exactly-128-application-bytes) |
| Does 100 ms interpolation cover the proposed Internet topology? | It leaves no bracket margin in the two-hop reference case. Start at 200 ms and measure age/error/uncertainty separately | [Clock and delay contract](../../plans/multiplayer-protocol.md#4-time-interpolation-and-bounded-work) |
| Is EOSG ready to become a dependency? | No. Source inspection found sender attribution and guest-login concerns; EOS remains a candidate behind a bounded investigation | [EOS trial and evidence](eos-trial.md) |
| Does the first directory example include the cost of quota accounting? | No. A per-request durable counter changes the 10-host/10-browser example to 86,400 minimum writes/day. Start with five advertised rooms and measure the complete query plan | [Corrected directory model](#directory-costs-and-failure-contract) |
| What should be built next? | Six small slices now distinguish a pure codec/state machine, presentation, actual processes and physical machines. A two-player product still needs a three-process routing fixture | [MP-01a through MP-02c](../../plans/multiplayer-protocol.md#5-reviewable-implementation-slices) |

The lead accepted the source-backed relay, ownership, reset and surface-conversion findings. The proposed 64-bit nonce was adapted by rearranging the header and moving the configuration revision, rather than increasing the 128-byte payload. EOS source findings became explicit stop conditions. A full custom EOS adapter and public-room transport hardening remain separately estimated work; research confidence does not substitute for those implementations.

## Directory costs and failure contract

This remains an **optional discovery service for reachable ENet hosts**, not a relay or a requirement for LAN/private rooms. No service is deployed by this change. Account-specific free-plan status and limits must be verified before use.

### Count the counter

The original 57,600-request calculation correctly counted ten host heartbeats and ten continuously open browsers, each every 30 seconds. It omitted the extra writes of one straightforward durable quota counter. Under a model with one room-row update per heartbeat and one counter-row update per accepted request:

`H = hosts × 86,400 / 30`; `L = browsers × 86,400 / list_period`; `requests = H + L`; `minimum_writes = H + requests`.

Every modeled request invokes one Worker and one Durable Object; their request quotas are **separate**, not one combined pool. The 70% operating allowance is 70,000/day for each 100,000/day limit. [Workers limits](https://developers.cloudflare.com/workers/platform/limits/) and [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/) are the dated provider inputs.

| Advertised hosts | Browsers open all day | List interval | Requests/day in each modeled bucket | Minimum SQL writes/day | Fits both 70,000 operating allowances? |
| ---: | ---: | ---: | ---: | ---: | --- |
| 2 | 2 | 30 s | 11,520 | 17,280 | Yes, before excluded work |
| 10 | 10 | 30 s | 57,600 | 86,400 | **No — writes** |
| 5 | 10 | 30 s | 43,200 | 57,600 | Yes, before excluded work |
| 5 | 20 | 30 s | 72,000 | 86,400 | **No — both** |
| 10 | 10 | 60 s | 43,200 | 72,000 | **No — writes** |
| 5 | 10 | 60 s | 28,800 | 43,200 | Yes, before excluded work |

“Fits” is a planning calculation, not admitted capacity. Extra index updates, cleanup/deletes, auth lookups, create/leave operations, retries, rejected traffic, other applications and telemetry remain excluded. An indexed `last_seen` column can add writes; do not assume one SQL statement is one billed row. Measure each completed cursor's [`rowsRead` and `rowsWritten`](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/) using the actual schema. Listing-row reads in the five-host/ten-browser/30-second example are 144,000/day, before other reads.

**Revised first directory scope: at most five advertised rooms**, each still capped at four pilots by the game. This limits directory entries, not all direct/LAN sessions. Ten continuously open browsers are a modeled load, not an enforceable promise about public traffic. Stop accepting/listing when the measured allowance is consumed; re-open only under the bounded recovery policy. Raise the room cap only after metering includes the complete operation mix. Do not add a complex quota-allocation system just to preserve the old ten-room example.

### Exact admission is different from an approximate edge limiter

Cloudflare's [rate-limiting binding](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) uses approximate, location-local counts; it is not an exact worldwide daily budget. It executes after the Worker starts, so rejected requests can still consume Worker allowance. Use it only as a cheap first filter. The selected design must atomically check/update admitted-room and accepted-operation accounting in one SQLite Durable Object; plan for conservative refusal after a crash or unclear meter state. A room owner's high-entropy capability is useful for identity/rate grouping; IP-only limits can unfairly combine users behind one NAT.

The actual **Workers Free / SQLite Durable Objects Free refusal behavior** remains the no-new-invoice boundary. Application counters cannot prevent every denial of service or account-wide quota exhaustion. For a routed endpoint, require fail-closed at the request limit or prove that no unsafe bypass origin exists; the [documented fail-open mode](https://developers.cloudflare.com/workers/platform/limits/#daily-requests) can bypass the Worker. Test the selected workers.dev/route behavior instead of assuming it. These limits cover the selected Worker/SQLite DO usage, not unrelated paid account products. Newly documented [spending controls](https://developers.cloudflare.com/billing/manage/spend-management/) do not make a paid plan equivalent to a hard-zero plan: reporting/enforcement can lag, and subscription/storage or ongoing operations can remain chargeable. Budget alerts merely notify. Do not upgrade or activate a chargeable fallback to restore availability.

### Avoid paying with the duration allowance

Use short HTTPS operations and durable rows, with expiry evaluated on every list/resolve. Do not keep a `setInterval`, an outbound connection or one busy timer per room. The [Durable Object lifecycle](https://developers.cloudflare.com/durable-objects/concepts/durable-object-lifecycle/) explains when an idle object remains billable and that in-memory state can disappear. A continuous 0.128 GB object consumes **11,059.2 GB-s/day**, exceeding the 9,100 GB-s operating allowance obtained by reserving 30% of 13,000. Eligible idle time is different; handler duration must be measured. This is a reason for a short-lived request design, not a claim that every directory runs continuously.

Keep heartbeat 30 s and server-assigned TTL 90 s. Filter expired entries immediately on reads even if deletion is lazy; quota exhaustion must not let stale rows masquerade as live rooms. Expired deletion and alarm writes count too. Pause browsing when its UI closes or a flight begins. On 429/503, honor valid Retry-After with bounded jitter and exponential backoff; on malformed/non-JSON provider error (including quota pages), stop tight retries and show unavailable. After a daily quota block, avoid automatic retry storms at the reset boundary. Cached rows retain their original expiry and a stale label; do not refresh their timestamp locally.

### Small metadata and honest access claims

Store only room ID, approved build/content identities, bounded display name, player count/cap, chosen reachable endpoint, server timestamps and token digests. Owner update/revoke capabilities and private join capabilities are separate, cryptographically random and excluded from public listings, logs and URL query strings. HTTPS protects the directory exchange; a capability later sent over plain ENet does not make the game transport confidential. Public listing requires explicit host opt-in. The service must not fetch or probe arbitrary advertised addresses; a heartbeat over HTTPS does not prove UDP reachability. Endpoint/port validation and public-room abuse review are required before public discovery ships.

## Reproducible analysis and evidence ladder

The standard-library [capacity model](../../../research/multiplayer/capacity_model.py) regenerates [capacity-results.json](../../../research/multiplayer/capacity-results.json). Run from the repository root:

```bash
python3 research/multiplayer/capacity_model.py > research/multiplayer/capacity-results.json
```

It recomputes six directory scenarios, the rearranged snapshot size, 2/4/8-pilot application bandwidth, the loss-free interpolation bound and a continuously billed object's duration. It performs **no networking, provider metering, physics simulation or benchmarking**. Its model inputs and exclusions are retained in the output. A successful calculation cannot close a runtime gate.

| Evidence level | What it establishes | What remains open |
| --- | --- | --- |
| Pinned source / official docs — done | API behavior visible in source, wrapper concerns, published service terms | Executable compatibility and actual service behavior |
| Analytical model — done | Arithmetic under stated assumptions | Actual byte overhead, query metering, timing and capacity |
| Codec/state fixtures — pending MP-01 | Exact bytes, invalid-input refusal, epochs, clocks and local invariants | OS sockets and real network delivery |
| Multiple actual processes — pending MP-02 | Adapter integration and routing/lifecycle on that host | Independent-machine/OS/network behavior |
| Physical LAN, then Internet/service — pending | Only the recorded machines, versions, routes and conditions | Universal connectivity, unlimited capacity or untested platforms |

## Open decisions and stop conditions

Before MP-01 code, choose the exact stock field/aircraft IDs, tighten their numeric bounds, pin all control schemas/rate limits and record fixture traces. The source-guided standalone adapter is still a candidate until run on 4.8-beta2. Before EOS integration, close the wrapper sender/identity gates or defer; before a directory, meter the actual schema and confirm the free account. Before public stranger rooms, prove transport-level flood/fragmentation limits: application history caps do not bound engine work. Each uncertainty has an owning phase in the current plan; none justifies silently expanding the first LAN release.
