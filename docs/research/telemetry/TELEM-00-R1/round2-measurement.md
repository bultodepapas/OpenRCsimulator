# Telemetry follow-up: targeted investigations F11–F14

Research date: 2026-11-18; all queries and findings are in English. Baseline commit: `48ae3016a655acf7d062da3f32d72b9050c9e59a`; the lead's round-one checkpoint in `docs/research/telemetry/TELEM-00-R1/README.md` was present as untracked work. Sources below were read on the research date. `main`, `master`, and `stable` are moving references, not a claim about the code in a named release or about OpenRC's pinned Godot 4.8-beta2. No external tool was installed or run, and no application integration, end-to-end behavior, or performance was demonstrated.

<a id="f11"></a>

## F11 — Toxiproxy: test uncertain delivery at a known commit boundary

**Falsifiable question.** Can a network fault proxy alone prove that a request was committed and its acknowledgement was lost, or that a positive timeout is a fixed wall-clock deadline?

**Exact English searches.** `site:github.com/Shopify/toxiproxy timeout 0 downstream toxic latency reset peer`; `site:github.com/Shopify/toxiproxy README upstream downstream timeout zero remove toxic data dropped latency`; `site:github.com/Shopify/toxiproxy "Timeout" "time.After" "stub.Input"`.

**Inspected primary evidence.** Shopify's [README and tutorial](https://github.com/Shopify/toxiproxy/blob/main/README.md), [`toxics/timeout.go`](https://github.com/Shopify/toxiproxy/blob/main/toxics/timeout.go), and [database test examples](https://github.com/Shopify/toxiproxy/blob/main/_examples/tests/db_test.go), `main` as accessed; the [release page](https://github.com/Shopify/toxiproxy/releases) listed v2.13.0, which was not the inspected source revision.

**Observation.** The README describes a TCP proxy: upstream is client-to-server, downstream is server-to-client. Latency is directional; `reset_peer` simulates a reset. A timeout toxic drops data; timeout zero does not itself close the connection, while positive timeout permits closure. In the inspected implementation, `time.After(timeout)` is created inside a loop: a received chunk returns control to another iteration, so repeated chunks can postpone timer expiry. A zero-timeout toxic drops intercepted bytes; removing it must not be assumed to replay them. The control API is unauthenticated by default.

**Inference and limits.** A proxy does not know when an HTTP transaction committed. Installing the downstream toxic before TLS setup may disrupt the handshake rather than model a lost post-commit response. A stream fault cannot by itself prove durable database state, test all packet-level network phenomena, or establish what Godot does on cancellation.

**Plan/test change.** With a synthetic HTTPS receiver, complete TLS and receipt, then hold its response behind a fixture barrier. Independently confirm database commit, activate a downstream zero-timeout fault, release the response, and verify client timeout/disable, immutable retry ID/body, and exactly one committed batch after retry. Separately test positive timeout, upstream fault, reset and latency. Record each fault's activation point, client wall-clock deadline, server state, and cleanup. Bind the test proxy and API to controlled loopback/isolated interfaces. Retain a real silent-peer shutdown test and stale-callback injection; do not infer them from this one proxy case.

**Follow-up lead.** Identify a fixture's durable commit signal and transport fault seam that do not change the production sender or weaken TLS.

<a id="f12"></a>

## F12 — mitmproxy: synthetic HTTPS inspection is not a no-egress proof

**Falsifiable question.** Does seeing no HTTPS flow in a configured interception proxy establish that telemetry-off generated neither DNS nor network traffic?

**Exact English searches.** `site:docs.mitmproxy.org certificate authority HTTPS explicit proxy certificate pinning transparent mode addon flows`; `site:docs.mitmproxy.org certificate pinning proxy modes certificate authority trust store client dns traffic not proxied`; `site:docs.godotengine.org/en/stable/classes/class_httprequest.html "set_https_proxy" "set_http_proxy"`; `site:docs.mitmproxy.org/stable/addons/examples/ request response headers content script`; `site:docs.mitmproxy.org/stable/concepts/modes/ regular mode proxy client configured port https DNS`; `site:docs.godotengine.org/en/stable/classes/class_tlsoptions.html trusted_chain client certificate TLS`.

**Inspected primary evidence.** mitmproxy's [repository](https://github.com/mitmproxy/mitmproxy), [proxy modes](https://docs.mitmproxy.org/stable/concepts/modes/), [certificate guidance](https://docs.mitmproxy.org/stable/concepts/certificates/), and [addon examples](https://docs.mitmproxy.org/stable/addons/examples/); Godot stable's [HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html), [TLSOptions](https://docs.godotengine.org/en/stable/classes/class_tlsoptions.html), and [TLS certificate guide](https://docs.godotengine.org/en/stable/tutorials/networking/ssl_certificates.html). The mitmproxy release list showed v12.3.1, but no installed version was examined.

**Observation.** Regular proxy mode requires the client to route through it; the docs acknowledge applications may bypass system proxy settings. HTTPS interception needs the client to trust the proxy CA, and certificate pinning may reject it. Godot stable documents request-level `set_https_proxy`, `set_tls_options`, and a validating `TLSOptions.client` with custom CA chain. Its TLS guide says it tries the OS bundle and has a bundled Mozilla fallback, so a system trust-store change is not sufficient evidence for every build. Addons can inspect HTTP flow data.

**Inference and limits.** No intercepted flow could mean no request, proxy bypass, connection failure, or incompatible trust. Explicit HTTP interception is not a complete DNS, direct-IP, UDP, encrypted-DNS, or system-wide egress observation. An altered test trust chain cannot validate the original release's normal certificate policy.

**Plan/test change.** Use synthetic canary values and a disposable test-only proxy/CA configuration, preserving hostname and certificate validation. First demonstrate that a positive-control request is visible, then inspect accepted telemetry headers and bodies against the allowlist and search controlled ingress logs/temp paths for canaries. Separately test the unmodified release's bad/untrusted certificate and hostname rejection with a direct synthetic endpoint. For off-state, use independently validated, appropriately scoped DNS and network observation on relevant interfaces/processes, with controls for bypass, resolver cache, loopback, IPv4/IPv6, and encrypted DNS; report any blind spots. Avoid real player data and clean up test trust and captures.

**Follow-up lead.** Qualify whether the exact beta2 export supports a bounded test-only proxy/CA seam without changing normal release trust behavior.

<a id="f13"></a>

## F13 — HdrHistogram: corrected latency is a different population

**Falsifiable question.** Does coordinated-omission correction preserve the v1 contract's observed process-interval count and duration sum?

**Exact English searches.** `site:github.com/HdrHistogram/HdrHistogram coordinated omission recordValueWithExpectedInterval synthetic values`; `site:github.com/HdrHistogram/HdrHistogram "coordinated omission" "expected" "recordValueWithExpectedInterval" example`; `site:github.com/HdrHistogram/HdrHistogram release version 2026 java histogram`.

**Inspected primary evidence.** Original Java [HdrHistogram README](https://github.com/HdrHistogram/HdrHistogram/blob/master/README.md), [`AbstractHistogram.java`](https://github.com/HdrHistogram/HdrHistogram/blob/master/src/main/java/org/HdrHistogram/AbstractHistogram.java) and [releases](https://github.com/HdrHistogram/HdrHistogram/releases). The release page displayed 2.2.2 (`3ae7ae1`); source examined was moving `master`. Local context: the observed-interval/histogram mathematics in `docs/plans/telemetry/data-contract.md`.

**Observation.** HdrHistogram describes a response-time sampling problem in which slow operations prevent scheduled observations. Its expected-interval recording method adds modeled observations decreasing by the expected interval; its code includes the expected-interval value. It offers either at-recording or post-recording correction and warns not to apply both for the same omission. This is a model for a specified sampling process, not a universal transformation into observed frames.

**Inference and limits.** In a purely illustrative tape, one observed 100 ms process interval corrected with an assumed 10 ms period produces 100, 90, …, 10 ms: ten entries totaling 550 ms, instead of one observed entry totaling 100 ms. Those extra entries are modeled waiting times, not nine measured process callbacks or draws. Mixing them into v1 would alter both the histogram population and the denominator used for observed time. Conversely, raw event-based samples alone do not answer every time-weighted experience question; preserving them is not a claim that coordinated omission is irrelevant.

**Plan/test change.** Add an independent 100 ms fixture that asserts v1 records one eligible interval, a 100,000 µs sum and its existing histogram bin; it must not invent counts. Keep separate tests for real hitches versus excluded suspend gaps. If a later responsiveness study needs open-loop or time-weighted experience, define its independent observation schedule, modeled population and labeling first, and evaluate a corrected result separately from product telemetry. No wire-format or HDR runtime dependency is needed for this lesson.

**Follow-up lead.** Investigate independent fixed-arrival sampling or display capture that can observe a stalled main loop without presuming a target frame rate.

<a id="f14"></a>

## F14 — airspeed velocity: bind comparisons to a compatible benchmark context

**Falsifiable question.** Are two performance results comparable merely because they share a benchmark name, and can a Python benchmark tool qualify an exported Godot frame-cadence budget?

**Exact English searches.** `airspeed velocity asv benchmark regression compare machine environment repeat variance continuous documentation`; `site:asv.readthedocs.io benchmark regression comparison machine operating system benchmark suite change repeat confidence noise`; `site:asv.readthedocs.io benchmark version changed not comparable compare hash machine parameter`; `site:github.com/airspeed-velocity/asv compare benchmark versions "not comparable"`.

**Inspected primary evidence.** The maintained [ASV repository](https://github.com/airspeed-velocity/asv), its stable 0.6.6 [using](https://asv.readthedocs.io/en/stable/using.html), [timing](https://asv.readthedocs.io/en/stable/tuning.html), [benchmark authoring](https://asv.readthedocs.io/en/stable/writing_benchmarks.html), and [result-format](https://asv.readthedocs.io/en/stable/dev.html) documentation.

**Observation.** ASV is primarily a Python-package benchmark suite. Its results associate project commit, environment and machine details, and its default benchmark version hashes benchmark source and setup; results with another version are ignored. ASV distinguishes short-term jitter from longer-term load, thermal and power drift and offers repeated samples and interleaved rounds. Its comparison displays noncomparable or failed cases; the documented default 1.1 comparison factor is a presentation threshold, not OpenRC's 1% acceptance rule. Results can include machine identifiers and environment variables.

**Inference and limits.** Matching names or machine labels do not establish equal renderer, scene, clocks, GPU driver, settings, thermal conditions or effective workload; a hash of benchmark code need not capture every external dependency. ASV is a useful methodology and possible offline Python prototype tool, but no examined source establishes it as an end-to-end Godot GPU or gameplay profiler. Host metadata and environment snapshots must not be copied into player telemetry.

**Plan/test change.** Require a comparison record for each paired off/on run with build and benchmark identity, host class, OS/driver, renderer, effective 1080p settings, scene/aircraft, input tape, warmup, power and thermal conditions, and measurement method. Preserve the existing minimum five alternating off/on runs and all observations; record failures, interruptions and missing cases instead of selecting favorable runs. Rebaseline or mark noncomparable when material inputs change. Report the paired variation and leave the 1% gate inconclusive when noise cannot resolve it. An ASV spike, if chosen, would be limited to independently defined Python offline operations and cannot replace exported-hardware tests.

**Follow-up lead.** Examine benchmark communities' primary guidance on paired/interleaved GPU experiments and interpretation when noise exceeds the decision threshold.

## Recommended direction for the unconventional round

Accept the methodological direction: use independently observed commit barriers and controlled cross-checks for transport, and compare measured frame populations with explicit provenance. Seek original game-performance or distributed-systems examples, including non-English primary material found through English searches, that challenge those assumptions. Defer runtime HDR correction and adopting Toxiproxy, mitmproxy or ASV as production dependencies; their optional developer use still needs exact-version and platform qualification.
