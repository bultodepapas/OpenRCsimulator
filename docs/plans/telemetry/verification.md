# Telemetry verification and release gates

Status: only offline contract/prototype checks have run; [actual evidence](../../research/telemetry/TELEM-00/verification.md).
The [follow-up evidence](../../research/telemetry/TELEM-00-R1/verification.md) records added generative/publication checks and their independent review.
Production UI, packets, exported Godot behavior, database, provider retention, GitHub publishing and hardware performance remain unqualified.

## Test layers

| Layer | Cases | Required proof |
| --- | --- | --- |
| Contract | Closed nested objects, bounds, enum values, exact string endings, UTF-8, duplicate keys, depth, NaN/Infinity, schema/notice versions | Python reference passes; port same fixtures to GDScript/client and actual ingress |
| Consent | Pending/declined/unknown; current grant; no re-prompt after saved denial; changed notice; save failure; corrupt/future files | No telemetry probe, queue, request, DNS or SDK auto-init before admission |
| Lifecycle | Disable while collecting/in flight/retrying; re-enable; old callback; old attempt within same generation; restart | No resurrection; fresh session; atomically saved denial or honest persistence error |
| Measurement | Independent known frame tape, 10+50 ms example, histogram boundaries, zero vs unavailable, suspend gaps, ordinary hitches, warmup/pause/context | Correct units/weighting and documented coverage |
| Hardware | Windows/Linux/macOS release APIs, Intel Core/Xeon/Arc distinction, unknown values, software renderer, Apple unified memory | Correct category or unknown; no raw string fallback |
| Activity | Accepted vs rejected starts, same aircraft reset, custom source, all vehicle routes, pause/replay/restore, unsupported classifier | Only new accepted observations; no local-history UUID/time/hash leakage |
| Transport | TLS failure, off-host/307 redirect, silent peer, partial response, 4 KiB response cap, 32 KiB request cap, 408/429/5xx, permanent 4xx | One bounded asynchronous unthreaded request; no shutdown blocking |
| Backpressure | Queue bytes/count/TTL, hourly request/byte budget, long Retry-After, five-retry limit, offline recovery | Drop/expire with bounded resource use; game remains usable |
| Ingress | Duplicate/ambiguous commit, conflicting body, concurrent batches, event-sequence overlap, invalid multi-event batch, DB full/unavailable | Durable all-or-nothing 202 with exact idempotency |
| Privacy operations | Log canaries, all retention surfaces, raw access denied to publisher, backup restore | Actual provider/configuration evidence, not serializer-only assertions |
| Reporting | Closed receipt day, mixed days/builds, 19/20 threshold, repeated windows, small-cell totals, partial/missing days, weighted FPS | No false unique-user/whole-population claim; conservative publication gate |
| GitHub | Permission/rate/schedule failures, timeout after create, duplicate concurrent runs, malicious Markdown, untrusted PR | One report identity, least privileges, no raw data/token exposure |
| Publication history | Changed digest/status/audience, missing review receipt, incomplete/zero/multiple reconciliation matches | Frozen approved body; unknown outcome never becomes blind create; no formal anonymity claim |
| Accessibility | EN/ES, focus, controller back/accept, screen reader, scale and contrast, large fonts | Equal usable choices and persistent effective state |

## Offline prototype reproduction

From the repository root, in a Python 3.12 virtual environment:

~~~bash
python3 -m venv .venv-telemetry
.venv-telemetry/bin/python -m pip install -r research/telemetry/requirements.txt
.venv-telemetry/bin/python research/telemetry/generate_contracts.py --check
.venv-telemetry/bin/python research/telemetry/generate_examples.py --check
.venv-telemetry/bin/python -m unittest discover -s research/telemetry -p 'test_*.py' -v
~~~

On Windows, use the corresponding Scripts/python.exe in the created environment. These commands do not read hardware, player data or credentials, and perform no telemetry/GitHub networking. Dependency installation is a separate package download.

The prototype does not implement persistent consent, HTTP sockets, secure random lifecycle rotation by time/day, threaded races, actual database transactions or weekly scheduling. IngressModel is in-memory; “202” in that model proves state-machine expectations only, not production durability. Unit tests cannot qualify a consent window or an exported game.

The follow-up adds Hypothesis 6.170.15 with bounded deterministic generated examples and a 120-example, up-to-50-step consent state machine. It checks independently stated observable invariants, without sockets or a player dataset. Public review receipts and discovery completeness are trusted inputs to the sequential publication model, not authenticated services. Deliberate faults are applied only to disposable copies to verify that the new tests can detect selected regressions. See the [starter](../../../research/telemetry/README.md) for the scope.

The [validation laboratory](validation-lab.md) specifies later Toxiproxy/mitmproxy/Schemathesis, error-canary, visibility, PresentMon/MangoHud/Perfetto and paired-hardware experiments. Those tools are research selections; their compatibility and experiment results remain pending. The [publication protocol](publication-protocol.md) owns the detailed provider-recovery and whole-history review cases.

## Focused Godot integration tests to add

Use the repository's [checked runner](../../tools/shared.md#one-godot-script) and shared-host admission when applicable. Read app/tests/AGENTS.md before adding runtime tests. Do not run the full physics/graphics suites for a docs-only prototype.

Proposed cases:

- test_telemetry_policy.gd: exported/dev/debug/direct/headless classification, local forced-off, current notice.
- test_telemetry_consent_store.gd: atomic write, disk full, protected/newer file, damaged primary, stale grant backup, deny persistence error.
- test_telemetry_projection.gd: all published catalog IDs, custom data/paths, classifier unavailable, no historical store access.
- test_telemetry_frames.gd: monotonic intervals, histogram edges, frame counts, no physics/input mutation and bounded allocations.
- test_telemetry_queue.gd: byte/count/age caps, unknown consent purge, generation and per-attempt token fences.
- test_telemetry_sender.gd: injected local transport outcomes and silent-peer cancellation without worker join.
- test_telemetry_ui.gd: equal actions, Escape/back=off, preview without pre-grant probes, saved state and offline/suspended copy.

Use local synthetic fixtures. Test collector ports and processes need explicit ownership and cleanup. No production endpoint or real telemetry is needed for these checks.

## Network acceptance matrix

Run packaged release binaries with an isolated test profile and controlled DNS/HTTP receiver. Capture only synthetic test traffic.

1. Fresh launch with no decision for 60 seconds: zero telemetry DNS/TCP/TLS requests. Disable the independent update checker or identify its requests separately.
2. Decline, fly, switch aircraft, exit and restart: zero telemetry; no implicit enabling after update.
3. Accept: first payload matches the current notice/schema; no pre-acceptance events/history.
4. Disable during a delayed request; re-enable: old response cannot queue or acknowledge new-generation data.
5. Sender retry timeout followed by a late response: per-attempt identity protects the new attempt.
6. Offline 15 minutes, then reconnect: expired memory data cannot be replayed.
7. 429 with Retry-After longer than TTL: drop at expiry; do not shorten server delay.
8. Redirect to another origin, bad TLS or invalid large response: no payload forwarded; bounded failure.
9. Close the game while the peer accepts and never responds: exit completes without telemetry wait/join.
10. Any installed SDK or native crash extension: disabled-state packet capture proves it cannot bypass the gate.

No-network assertions concern telemetry. Local renderer detection and gameplay statistics that already exist may still operate for their independent game features; do not mislabel those as remote collection.

## Target-hardware performance campaign

Priority: **1920×1080 first**, then 1440p/4K, then 720p fallback. Compare the same clean exported build, renderer, effective settings, aircraft/field, warmup, input tape and power/thermal conditions. Use existing frame capture/GOD TEST/replay tools; no ad hoc physics benchmark. Collect at least five alternating off/on runs after an initial cold-run record and report variation rather than a single favorable number.

Required fleet: modest Windows integrated GPU, Windows discrete GPU, Linux integrated/discrete, Apple Silicon native path and Intel macOS if still supported. A software renderer or this container does not qualify those targets.

Include focus and occlusion as independent states where possible, preserve unknown coverage, and verify the metric definition and clock domain before comparing external profilers. A matched benchmark must retain build/context identity, all run outcomes and variation. Pooled voluntary telemetry is supporting evidence, not a substitute for the controlled off/on campaign.

Proposed budgets to verify:

| Resource | Acceptance target |
| --- | --- |
| Off state | No telemetry samples, queue, periodic work, network or SDK worker |
| Per-frame observer | Fixed counters, no per-frame dictionary/JSON/disk allocation; p95 added CPU <0.10 ms |
| Main-thread batch sealing | p95 <0.5 ms, measured at actual maximum accepted event size |
| Owned client memory | <2 MiB including 256 KiB queue and temporary buffers |
| Network | ≤256 KiB/hour body bytes and ≤90 attempts/hour; measured serialized data and retries |
| Gameplay | No statistically credible >1% median frame-cadence degradation in paired runs; if baseline noise exceeds this, extend measurement/report inconclusive |
| Shutdown/disable | No wait for network; pending memory released immediately, stale callbacks harmless |

Budgets are unmeasured design gates. A small unit-test runtime is not evidence that Godot observers meet them. Physics results/checkpoints must remain equivalent because the adapter observes detached state and never changes a solver callback.

## Readiness checklist

TELEM-14 remains blocked until: production adapter and UI are qualified; exact endpoint/operator/notice are recorded; exported builds pass packet/performance tests; payload/log/backup retention is proven; publication identities/permissions are tested; an operational owner and spending cap exist; and a volunteer preview has produced usable, honestly labeled reports. Record actual failures and coverage gaps; do not mark the track complete on a passing offline suite.
