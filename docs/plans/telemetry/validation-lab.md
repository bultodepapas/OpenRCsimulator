# Telemetry validation laboratory

Status: executable offline preparation plus **planned** native/network/operations experiments. No fault proxy, interception certificate, receiver, database or profiler has been deployed by this work. [Verification gates](verification.md) own release acceptance; [follow-up research](../../research/telemetry/TELEM-00-R1/README.md) owns the dated evidence.

## Reuse established tools at the right boundary

| Tool / evidence | Proposed use | What a passing result does not establish |
| --- | --- | --- |
| PresentMon, F01 | Windows comparison of engine draws, present calls and displayed-frame changes | Optical panel output, identical metrics, or support for every renderer |
| MangoHud, F02 | Optional local Linux capture after qualifying its exact logger and sampling behavior | Equivalence of a HUD percentile, an averaged slowest fraction and the wire histogram |
| Perfetto, F03 | Optional local timing/coverage investigation with explicit clock mapping | A shared epoch merely because two clocks are monotonic, or zero tracing overhead |
| Toxiproxy, F11 | Directional TCP latency, reset, silence and lost-response experiments | The database commit boundary or an independent absolute request deadline |
| mitmproxy, F12 | Inspect synthetic HTTPS headers/body using a disposable test-only CA/proxy setup | Complete DNS/direct-IP/UDP observation, or normal release trust behavior |
| HdrHistogram, F13 | Understand sampling and coordinated-omission assumptions | Permission to add modeled observations to the measured-frame histogram |
| ASV, F14 | Borrow benchmark identity, interleaving and variation practices | Qualification of an exported Godot renderer by a Python microbenchmark |
| Hypothesis, F09 | Generated consent/request sequences and hostile payload encodings | Real thread scheduling, file durability, sockets or database isolation |
| Schemathesis, F18 | Later isolated receiver conformance against the OpenAPI proposal | Correct semantic acceptance, log privacy, transaction durability or retention |

Only Hypothesis is installed/pinned as a **test-only dependency** in the starter. Before running another tool, pin its actual reviewed version, inspect its license and dependencies, establish local ownership and cleanup, and follow the existing checked-runner/test-host rules. Use synthetic inputs; no player dataset is needed. No profiler, capture agent or fault-proxy dependency enters the shipped game.

## Controlled delivery failure experiment

1. Use a synthetic HTTPS receiver and database, with a fixture barrier immediately after a verified commit and before the response is sent.
2. Complete TLS and send the bounded body. Observe the commit independently, then activate a downstream response-loss fault and release the response barrier.
3. Verify the client's actual monotonic deadline, immutable retry identity/body and one accepted contribution after an identical retry. Separately test disable, exit, late callback and response-after-timeout.
4. Repeat upstream silence, downstream silence, reset, partial response and 429/Retry-After cases. Record the activation point and both sides' state. A proxy configured before TLS may test handshake failure instead of a lost acknowledgment.
5. Stop owned processes and remove synthetic trust/capture material. Keep normal TLS verification enabled; a test CA is narrowly scoped to the disposable fixture.

Toxiproxy's inspected timeout toxic drops bytes, and its positive timeout is not a total wall-clock deadline under every stream pattern. The actual sender needs its own deadline. A missing interception flow is ambiguous until a positive control proves the routing/capture works; off-state proof separately observes relevant DNS and network paths, including caches, loopback and IPv4/IPv6. Treat unobserved paths as coverage limits.

## Request and error canaries

The complete tested deployment, including defaults and inherited configuration, needs an inventory of edge/WAF, reverse proxy, application server, database driver, stderr, journal/container logging, APM, queues, temporary files, replicas, backups and crash capture. NGINX can spill a valid 32 KiB body with its smaller default buffer; Uvicorn's access-log switch does not disable its error logger. FastAPI/Pydantic error details can include rejected input. See F06/F17 for the inspected sources.

Use uniquely labelled **synthetic** values in payloads, paths, headers and deliberately raised exceptions. Exercise valid maximum-size input; one-byte-over-limit; duplicate decoded keys; malformed JSON/UTF-8; chunked and Content-Length input; slow/aborted clients; wrong routes; database/startup/validator errors; and post-response exceptions. Check responses and every inventoried sink during and after the run. Preserve fixed error categories and aggregate health counters without storing input or arbitrary exception text. A safe custom 500 response does not prove a re-raised exception was safely handled by the server.

For future Schemathesis tests, load local schema references and explicitly override the non-routable example base URL. Use no production credentials and deny external egress. Independently semantically valid bodies must be accepted; schema-valid but semantically invalid histogram/sequence/release cases may correctly receive 422. Assert an intentionally injected storage outage's 503 separately. Do not globally suppress 5xx or assume every schema-valid object deserves 202. Raw-byte decoder tests remain necessary.

## Measurement qualification

Retain all run outcomes and the exact build, renderer, scene/aircraft, input tape, settings, resolution, warmup, graphics-calibration state and power/thermal conditions. Use 1080p-first except Apple Silicon Retina panels, which use their native physical-panel target; record output, drawable and internal 3D pixels separately under the [Apple plan](../apple-silicon-performance.md). Record measurement tool version, fields, clocks, capture boundaries, loss/availability and benchmark definition. Use at least five alternating off/on runs. Material benchmark/context changes make a comparison noncomparable until deliberately rebaselined. Use the non-shipped explicitly admitted qualification build and local-only endpoint defined in the [verification plan](verification.md#target-hardware-performance-campaign); demonstrate actual observer/serializer activity and equivalence to the shipped code. Replay/capture remains forbidden for production ingestion. Real host timings are controlled QA observations. Test ordinary shipped-route off safety separately. If noise cannot resolve the proposed 1% overhead gate, report inconclusive.

Qualify visible-focused, visible-unfocused, minimized, fully occluded, restored, suspend/resume and a deliberate foreground hitch separately. Where possible use a nonactivating occluder to separate focus from coverage. Observe actual callbacks, draw deltas and drawable signals for the pinned beta and each relevant window system. Do not label the result visible-only if occlusion cannot be determined. Prime/reset on known boundaries. V1 also excludes every interval longer than five seconds regardless of cause, so a genuine foreground freeze that long is omitted as well; label the censoring and do not infer resume from duration alone. Test a real foreground stall and a known resume independently.

PresentMon's present/display counters, engine draws and process intervals may legitimately differ. Match intervals and availability before comparing; retain dropped/generated-frame classifications where available. A trace-clock mapping needs known origins, units, bounded alignment uncertainty and end-to-end coverage; re-anchor after suspend and check buffer loss/overwrite.

Three synthetic counterexamples are retained in [test_publication.py](../../../research/telemetry/test_publication.py):

- A 200-interval tape distinguishes a reciprocal percentile (40 FPS) from the reciprocal mean of its two slowest intervals (16 FPS). Neither is the v1 histogram's exact 1% low.
- One observed 100 ms interval remains one observation and 100 ms of exposure. An assumed 10 ms coordinated-omission correction would create modeled 100…10 ms observations totaling 550 ms, which must not be mixed into v1.
- A hardware exposure mix change moves pooled FPS from 75 to 65 while both underlying strata remain at 100 and 50 FPS. A pooled decline is an investigation lead, not a causal release verdict.

## Statistical interpretation and follow-through

Predeclare the comparison's release/channel, metric definition, eligible days, context and exposure. The default/custom label does not make distinct detailed graphics settings comparable. State >5-second interval censoring and missing duration as a measurement limitation. Preserve missing/suppressed days, input-definition changes and unknown coverage. Compare within sufficiently supported, already approved coarse cells; additional breakdowns require a whole-report disclosure review. Do not manufacture independent-user sample counts or confidence intervals from rotating tokens. Confirm suspected regressions with controlled, matched replay/benchmark runs.

The privacy threshold and publication model do not protect against every auxiliary-information or composition attack. The [publication protocol](publication-protocol.md) freezes report history and requires a separately trusted public review receipt; it is not differential privacy. The [delivery plan](delivery.md) owns actual transaction, logging and retention obligations.
