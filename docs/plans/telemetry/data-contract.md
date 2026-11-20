# Data, measurement and retention contract

Status: v1, implemented by [app/telemetry](../../../app/telemetry/) and [services/telemetry](../../../services/telemetry/README.md); not yet active in any build. [Schema source](../../../research/telemetry/generate_contracts.py), [generated batch schema](../../../research/telemetry/contracts/batch.schema.json), [synthetic example](../../../research/telemetry/examples/batch.json).
Every object is closed. Unknown fields are rejected, not stored for later inspection.
This document specifies production intent; the [starter](../../../research/telemetry/README.md) lists what its offline model actually covers.

## What the initial data can answer

| Engineering question | Minimum data | Interpretation |
| --- | --- | --- |
| Which broad machine classes struggle? | CPU/GPU family, RAM/thread bucket, OS/architecture, renderer, cadence | Consenting observations, not unique hardware installations |
| Did release B regress? | Published release identity, same allowed context, eligible duration and frame counts | Association within comparable cells; validate causality with a controlled replay/benchmark |
| Which aircraft are actually flown? | Accepted built-in vehicle ID, activity duration/outcome | Selections and failed launches do not count as successful flights |
| Which broad rendering context accompanies slow cadence? | Renderer/driver, resolution basis/class, vsync/cap and coarse default/custom label | This narrow context does not identify reconstruction, MSAA, scene detail, shadows or other settings; custom combines different settings and cannot establish setting effects or comparable configurations |
| Is simulation slowing while drawing continues? | Accepted simulated vs active wall seconds, later validated tick-cost summaries | Separate simulation speed from render FPS; no physics state or inputs |
| Which failures need attention? | Finite error category and count | An aircraft crash is not an application crash; an abrupt process exit may be unobserved |

No DAU, MAU, retention, country, persistent cross-launch individual journey, device lifetime, marketing attribution or unique-player metric is possible or promised. Telemetry-off and lost offline sessions are absent; download totals cannot supply a valid denominator.

## Envelope

| Field | Allowed representation / purpose |
| --- | --- |
| schema_version | Integer 1; changes require a coordinated decoder/notice review |
| notice_version | Exact current notice identifier, initially 2026-11-18 |
| session_id | Exactly 32 lowercase hex characters; random 128 bits. The active collection epoch lasts at most four hours and ends at the UTC day boundary; already sealed RAM-only queue bytes may retain its token for the remainder of their existing ten-minute TTL |
| batch_id | Independently random 128 bits; exactly 32 lowercase hex characters; immutable retry identity |
| build.release_id | Bounded published release tag; no arbitrary build description; collector also checks its deployment allowlist |
| build.channel | stable or preview |
| build.engine_minor | 4.8 for this proposal; the exact pinned beta/export is separately qualified |
| context | Finite hardware/settings object below, stable for all events in that batch |
| events | 1–16 events, each with an approved name and monotonically increasing per-session seq |

No client wall-clock timestamps are sent. Receipt day is trusted server metadata. IDs are not proof of authenticity; a modified client can forge any measurement. Controls limit abuse but do not create trusted benchmark evidence.

Retire the active collection epoch at restart, re-enable, day change or the four-hour bound. Queued old-session batches may remain for their existing ten-minute lifetime, including across the four-hour or day boundary, but do not receive new observations or migrate into a new session or consent generation. Cancel an in-flight old-session request at the same original queue deadline and fence its later callback. Session rotation alone does not prevent correlation through hardware or traffic timing.

## Hardware and effective graphics

| Context field | v1 values / source strategy |
| --- | --- |
| os_family | windows / macos / linux / other / unknown; OS.get_name mapped explicitly |
| architecture | x86_64 / arm64 / other / unknown; Engine architecture mapped explicitly |
| cpu_family | intel_core / amd_ryzen / apple_silicon / other / unknown |
| logical_threads_bucket | ≤4, 5–8, 9–16, 17+ or unknown; logical threads, not physical cores |
| ram_gib_bucket | ≤4, 5–8, 9–16, 17–32, 33–64, 65+ or unknown; classify usable physical bytes, never free memory or swap |
| gpu_family | nvidia_gtx / nvidia_rtx / amd_radeon / intel_arc / intel_integrated / apple_silicon / software / other / unknown |
| renderer | gl_compatibility / mobile / forward_plus / unknown |
| driver | opengl3 / opengl3_es / opengl3_angle / metal / vulkan / d3d12 / unknown |
| resolution_class | below1080p / 1080p / 1440p / 2160p / above2160p / other / unknown. TELEM-18: pixel-count bands named after their 16:9 reference (< 1.6 MP, < 2.9 MP, < 5.5 MP, < 10 MP, larger), so 16:10, MacBook panels, ultrawide and windowed sizes are classified; `other` is no longer produced. The size is the window size Godot reports, so it describes the window, not the display (a windowed 1280×720 session on a 4K panel is `below1080p`); on macOS Retina whether that is points or backing pixels is not yet verified |
| resolution_basis | viewport_coordinates / native_drawable_verified / unknown |
| vsync | off / on / adaptive / mailbox / unknown |
| fps_cap_bucket | unlimited / ≤30 / 31–60 / 61–120 / 121+ / unknown |
| graphics_profile | current_default / custom / unknown; derive only from an authoritative owning graphics subsystem after grant and use unknown if it cannot determine the relation. This is not a complete or comparable graphics-settings snapshot |
| input_class | keyboard / gamepad / rc / other / unknown; never device name or serial |

For product telemetry, read raw engine strings only after consent, classify locally, discard them immediately and construct a new object. Independent local graphics detection keeps its own behavior. Exact CPU/GPU model strings, OS patch versions and driver versions are excluded from automatic v1. An unknown or ambiguous classifier returns other/unknown; it never falls back to the original string. The prototype classifier is a deliberately small example, not a complete hardware database.

The reviewed newer-main graphics system has renderer modes and independent scene-detail choices; their local decisions and calibration contain richer hardware information and are outside this wire contract. A default/custom label alone cannot isolate reconstruction, MSAA, scene, shadow or effect differences; defer detailed setting comparisons and causal explanations to a separately reviewed field proposal or controlled benchmark.

Resolution classes describe height/area buckets with a documented classifier to be qualified; do not use exact unusual dimensions as identifiers. At implementation, define exact thresholds and aspect-ratio treatment in tests before freezing the field. In the pilot use common reviewed 16:9 sizes only, otherwise other; this avoids falsely calling an arbitrary 1080-high ultrawide display “1080p.”

Godot physical-memory output may exclude reserved memory. Implement buckets using ceilings with a small documented tolerance for common capacities, or publish range labels literally; never infer a model/SKU. Unsupported values are unknown. Total VRAM, process RSS, free VRAM, temperature, utilization, OS major versions, refresh rate and exact driver models are **not in v1**. Their portability, privacy and utility need a later field proposal.

## Event catalog

| Event | Required event-specific fields | Cadence and meaning |
| --- | --- | --- |
| session_started | None beyond name/seq | Once after admission; never replay an earlier session |
| performance_window | mode, vehicle_id, phase, window_complete, interval_count, interval_sum_us, rendered_frames, draw_counter_status, interval_histogram, excluded_gap_count, gpu_status, gpu_ms | About 30 s; close early on context boundaries |
| activity_summary | vehicle_id, active_seconds, simulated_seconds, outcome, complete_observation, classification, takeoffs, landings, aircraft_crashes | Accepted activity close/reset or 5-minute slice (TELEM-19: quitting from a flight loses only its last slice and unsealed events, about 6 minutes at most); only new post-consent observations |
| error_count | category and count | Coalesced bounded counters; no text or stack |

Approved error categories: renderer_unavailable, asset_load_failed, aircraft_validation_failed, simulation_fault. They identify software outcomes, not diagnoses. Start with capped counters, never one network message per error. The client emits `asset_load_failed` and `renderer_unavailable` ([architecture](architecture.md#implemented-modules)); the other two are reserved.

Approved vehicle IDs come from the inspected stock catalog/roster. Research-only hidden configurations are excluded. Workshop or Creator/custom content becomes custom before any batching. Do not transmit custom filenames, UUIDs, physics hashes, paint names, workshop parameters or local source references. The schema has none/unknown only where meaningful.

The fixed-wing statistics service may provide accepted takeoff/landing/aircraft-crash counts. A classifier unavailable for a helicopter, drone, airship, car or custom model sets classification=unsupported and all three counts to null. Missing observations are not zero. Existing local flight statistics retain their own behavior when product telemetry is off; no historical records are read or backfilled into this pipeline.

Mode, stock vehicle ID and arrival times form a short-lived activity trace even without full trajectories. Disclose this as session/activity usage. Do not claim that the receiver learns nothing about what was played.

## Measurement mathematics

Process intervals use the monotonic wall clock. For eligible observed intervals i, with interval duration t_i in microseconds and an independently observed render-count delta r_i:

- Active observed duration = sum(t_i) / 1,000,000.
- Render-cadence FPS estimate = 1,000,000 × sum(r_i) / sum(t_i).
- Mean process interval in ms = sum(t_i) / interval_count / 1,000.
- A rate aggregated across windows uses the ratio of totals. Never average per-window FPS.
- A draw counter that is unavailable or resets produces null and an unavailable status. An observed zero remains zero. A process callback is not evidence that one frame was rendered.

Example: one observed draw in 10 ms and one in 50 ms gives 2 / 0.060 = **33.33 FPS**, not the arithmetic mean of 100 and 20 FPS (60).

Histogram upper bounds in microseconds: **8,333; 16,667; 33,333; 50,000; 100,000; 250,000; 1,000,000; 5,000,000**. Each bin is greater than the prior upper bound and at most its own bound; the first starts at 1. Count sums and plausible duration sums must agree. Counters are bounded and finite. An interval above five seconds is excluded as a gap, counted separately and never clamped into a short frame. This fixed duration rule also excludes a genuine foreground freeze longer than five seconds. Do not infer suspend/resume from length alone, describe v1 as freeze-complete, or compare results without acknowledging this censoring.

A histogram percentile is an interval/bound estimate. It is not an exact p99 and is not “1% low FPS.” Exact 1% low requires a separately defined statistic such as the reciprocal of the mean of the slowest one percent of frame intervals; v1 does not transmit enough detail to compute it exactly. Never average percentile values across windows.

A normal window is complete only when its observed eligible interval sum reaches at least 30,000,000 microseconds in unchanged context, with the 60,000,000-microsecond hard bound never exceeded. Check the threshold after each admitted interval; if a lifecycle/context/size boundary closes the window first, mark it partial. For an interval that would exceed a hard bound, seal the existing window as partial and start a new window according to the lifecycle contract rather than overflow or fabricate a complete one. An observation that cannot fit even an empty window, such as a draw delta above 60,000, must be dropped with a bounded local category and the affected window marked partial/unavailable; reset and prime the source. Never clamp it or retry rollover indefinitely. The reference raises before mutating its counters. An observed zero draw count may qualify for the daily table; missing or reset draw coverage cannot.

Prime the clock; reset at pause, minimized/undrawable/focus-loss and known suspend/resume; keep warmup separate for the first ten eligible seconds after a scene/configuration transition. A real 100 ms hitch remains in the distribution. Exclusion counts/coverage must accompany comparisons. Loading and first-run work that occurred before grant are not backfilled.

Vsync, frame cap, window state and software renderer influence the result. Main-loop cadence is not GPU utilization or display presentation. Frame generation and native render cadence require separate future instruments. Product telemetry does not tune graphics. The newer-main local automatic graphics feature remains independent and continues even when telemetry is off.

Independent tools use different definitions: PresentMon separates present calls and display changes; the inspected MangoHud percentile is not the reciprocal mean of the slowest fraction. Do not relabel the fixed histogram as either statistic. Coordinated-omission correction adds modeled samples and must not change v1's observed interval counts or duration. The [validation laboratory](validation-lab.md#measurement-qualification) defines the cross-checks and synthetic counterexamples from F01–F04/F13.

Known focus/drawable signals do not establish complete physical visibility on every compositor. Qualify focus and occlusion separately; label coverage unknown when the engine/platform cannot distinguish them. Do not infer visibility or a suspend cause from interval length alone; the separate fixed >5-second exclusion still removes some real foreground freezes. A changed hardware/context exposure mix can change pooled FPS without a within-context slowdown; compare only with the limitations in [statistical interpretation](validation-lab.md#statistical-interpretation-and-follow-through).

## GPU and memory truthfulness

Base mode leaves GPU timing off and sends not_measured with null. If a later cost-qualified adapter opts into the existing shared timing lease, preserve the source statuses: not_measured, zero_ambiguous, positive_freshness_unverified, invalid_reading. Only the positive-unverified state carries a positive value; do not claim per-frame freshness or align it with a particular interval. Invalid/nonfinite values are never serialized as numeric zero.

Godot monitor zeros can mean release-build unavailability. Rendering memory is an engine estimate, not free VRAM or process RSS. Those memory measurements are deferred until a release/export capability matrix and a purpose justify them. Coarse installed RAM remains in v1.

## Strict ingestion and versioning

Both sides validate closed JSON. The server additionally rejects duplicate keys, excessive depth, non-UTF-8 input, nonfinite values, impossible histogram totals, duplicate or non-increasing event sequences within a batch and unapproved builds. Sequence gaps are permitted; transport loss must not require historical replay. Enforce 32 KiB before parsing/allocating a full body. No compressed ingress in v1. Reject whole batches atomically and log only the failure category.

A batch key reused with identical bytes is acknowledged without another count. A reused key with different bytes or overlapping session/sequence in another batch is a conflict. Retry the same body/ID only. Uniqueness is enforced transactionally, not by a best-effort cache before insertion. Dedup protection ends at its stated expiry; hostile replays after that horizon can be accepted. No anonymous client design makes user-supplied metrics authoritative.

Backward-compatible new fields still need a purpose/privacy review. Never accept unknown fields into a generic JSON blob “for future use.” Adding a data category, broader identifiers, new recipients or longer retention can require a new notice and paused collection; a corrective enum/decoder patch alone need not repeatedly ask a user who declined.

## Retention and aggregation lifetimes

These are **deployment requirements**, not claims about a service already running.

| Surface | Maximum lifetime | Implementation / qualification |
| --- | --- | --- |
| Unsealed counters / pending client bytes | 10 minutes for sealed queue; current session for counters | RAM only; immediately clear on off, unknown consent or exit |
| Client session token | Active collection epoch: four hours or UTC day boundary, whichever first; pending sealed bytes: remainder of their original ten-minute TTL | RAM only. Old sealed bytes may cross the epoch/day boundary, but never recover a token from local flight history or reuse it for new observations |
| Client consent choice | Until changed/reset | Contains choice and notice, no player identifier; atomic persistence and fail-closed recovery |
| Raw minimized receiver records, session IDs, event and batch dedup indexes | **48 hours from each receipt** | Per-record expiry, including queues, replicas, backups and recoveries |
| IP-derived abuse keys | 15 minutes, memory only | No raw-IP analytics; rotating keyed value remains potentially identifying |
| ID-free internal daily aggregates | 180 days | Fixed dimensions, operator access; row deletion/backup expiry tested |
| Public GitHub reports | Indefinite unless deliberately removed; copies may persist | No raw records, IDs or sensitive small cells; private TTL does not erase publication |

Why 48 hours: a report received early in a UTC day must survive the next day's rollup. Roll up at day close + one hour, commit idempotently and purge raw data by its exact deadline. Allow recovery only while the oldest contributing records are still available. The prototype conservatively permits completion only before UTC day start +47 hours. A missed deadline yields an incomplete/missing day, not fabricated data or extended retention. A privacy provider/configuration that cannot honor this requirement must be changed or explicitly revisited before release.

The daily job removes session IDs from its output. For public GPU tables, require at least 20 distinct **ephemeral session tokens within that closed receipt day and cell**. Cap each token's contribution at 120 eligible steady-flight windows. If any cell in the proposed table is below the threshold, suppress the entire table and omit its totals. This conservative initial rule avoids a total-minus-visible-cells disclosure; more useful coarsening requires a later reviewed policy.

**TELEM-16/17 (2026-11-19, owner-approved reviewed policy).** The daily rollup additionally stores **unsuppressed** ID-free cells (`daily_cells`) for fixed dimensions: flight cadence by GPU family, frame-pacing limit, resolution class, OS + driver and vehicle; menu/workshop cadence; vehicle usage; error categories; and session counts per hardware/settings dimension. They hold no session or batch identifier or free text, stay in the operator's aggregate database for at most 180 days and are re-validated when read. Disclosure control moves to reporting: the weekly insights report pools the week's cells and shows a cell only with at least 20 session-day observations (10 allowed, labelled private floor); cells below the floor, plus the smallest shown cell when needed, form one combined row, and a table below the floor is not shown, so no table leaves a withheld remainder. **Insights are operator-only:** nested dimensions shared between tables can still be differenced, and a weekly session-day floor can be filled by one very active player (new tokens at each launch, UTC day and four hours). The whole-table daily rule above remains for the public v2 report; never publish both for the same week and release.

Since TELEM-19 activity summaries are cut every 5 minutes, so `complete_observation` is true only for activities shorter than one slice; complete-summary counts are not comparable with builds before that change.

The weekly report pools only eligible, already gated daily cells and labels counts **contributing session-day observations**. It excludes suppressed/missing days and must say so. Do not call the sum unique sessions, players, devices or the whole week's population. A session spanning receipt days, re-enabling, token rotation and repeat players can add observations. The threshold is a disclosure mitigation, not k-anonymity, differential privacy or resistance to a Sybil attack.

The executable reducer takes trusted receipt-day/body pairs, rejects mixed or open days and models this one-day GPU gate. It enforces the 30-second floor for a claimed complete window and rejects impossible aggregate exposure/frame totals. It cannot establish that a remote client actually respected context, visibility or lifecycle boundaries; native qualification remains required. Weekly orchestration, other tables, late-window coverage and database deletion remain TELEM-09/10 implementation work. Published aircraft popularity can start with manually reviewed aggregates; do not copy the private session table to GitHub.

For a daily GPU row with S contributing session tokens, observed time must be between S × 30,000,000 and S × 120 × 60,000,000 microseconds; rendered frames cannot exceed S × 120 × 60,000. The row's summed 8-bucket interval histogram must bracket its observed time by the bucket bounds and total at most S × 120 × 60,000 intervals; its excluded-gap total is at most S × 120 × 1,000. These plausibility checks do not authenticate observations. Independent scalar capacity limits also apply: at most 1,000,000,000 session observations, 1,000,000,000,000 frames and 9,007,199,254,740,991 microseconds per row. All reported integers fit the exact common JSON integer range. Exceeding any bound rejects the whole report; never truncate totals or silently publish a partial table. Production must qualify its admitted-volume ceiling and mark capacity failures as missing/error coverage, without extending raw retention.

The starter's daily table is explicitly release-wide: it can pool stable/preview channels and other contexts within a GPU family and does not preserve a channel field. Since report v2 each row carries the summed 8-bucket frame-interval histogram and excluded-gap total, which the weekly report turns into slow-frame shares. Its threshold is for that pooled cell, not each channel. It is a descriptive summary, not the planned release-comparison evidence. Channel-specific or matched-context comparisons still need a validated release/channel identity, exposure/coverage aggregates and a bound publication identity. Those facts cannot be reconstructed from the current ID-free row; new output dimensions require another schema/disclosure review.

The threshold, status changes and overlapping/corrected reports still have inference channels. A 19-to-20 token transition changes suppressed output into visible output under strong auxiliary knowledge. Public release review must consider the whole inventory and previous versions, not only each table in isolation. The [publication protocol](publication-protocol.md) freezes exact reviewed titles and bodies and refuses an automatic changed-digest publication; it does not prove formal privacy.

Ordinary PostgreSQL deletion is logical expiry, not demonstrated physical erasure. WAL, dead tuples, replicas and backup chains may preserve readable data. A backup age measured from snapshot creation can exceed the oldest included record's 48-hour deadline. The [operational specification](delivery.md#retention-and-logging-feasibility) keeps this requirement explicit; no row-TTL test, restore filter or ordinary backup setting closes it.

## Never collect automatically

Names, emails, accounts, installation/device IDs, MAC addresses or hashes, serials, hostnames, environment variables, filesystem paths, document/project names, custom aircraft/paint labels or hashes, exact locations, IP/GeoIP analytics, raw user-agent, controller identity/axis sequences, screenshots, microphone/audio, raw logs, exception text, crash dumps, full flight tapes, persistent statistics IDs or arbitrary event properties. Hashing a prohibited identifier does not make it permitted.
