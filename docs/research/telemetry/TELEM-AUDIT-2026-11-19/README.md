# Telemetry system audit, 2026-11-19

Scope: is telemetry released, deployed, working and receiving data, and will the data answer our questions? Source `e0a733937` (main, clean). The [plan](../../../plans/telemetry.md#completion-plan-telem-1626) holds the resulting phases; this page holds the evidence.

## Answer

| Question | Finding | Evidence |
| --- | --- | --- |
| Released? | **No.** The client ships inside v0.2.9 but is unavailable: no build carries a telemetry configuration | v0.2.9 notes ("a telemetry client is included but unavailable"); the repository has **0** Actions variables (`gh api .../actions/variables` → `total_count: 0`) |
| Server deployed? | **No.** No operator, host, hostname or TLS exists | Plan status; no endpoint configured anywhere |
| Data received? | **None, and none can arrive from any published build.** Every installed v0.2.9 refuses to offer telemetry; only a new tag exported with the variables can send | The downloaded macOS v0.2.9 package (SHA-256 `90fc7…731f`, matches `SHA256SUMS`) contains the client scripts (3 matches for `telemetry/telemetry_service` in the `.pck`) but **0** matches for `telemetry_release.json` |
| Does the software work? | **Yes, on Windows and macOS.** Client, receiver and the Mac-to-receiver network path pass | Section below |
| Will the data be useful? | **Not yet.** At pilot volume the weekly report would be empty, and most collected context is discarded | [Findings](#findings) U1–U4 |

## Executed checks

| Check | Host | Result |
| --- | --- | --- |
| Receiver suite (`python -m unittest discover`) | Windows, Python 3.12, pinned requirements | 109 tests OK |
| Godot client → receiver end to end (`test_godot_e2e`) | Windows, Godot 4.8-beta2 | OK |
| `test_telemetry_contract`, `_admission`, `_queue`, `_service`, `_sender` | Windows, headless, run directly (logs scanned) | all passed, 0 script errors |
| `test_telemetry_app` (real AppRoot, staged loading, flight round trip) | Windows, headless | all passed, 0 script errors |
| **Cross-machine network path**: real client on the Mac, receiver on Windows, through an SSH reverse tunnel over Tailscale | ANGEL (MacBookAir10,1, M1, macOS 27, official `4.8.beta2.official.cafc17a19`); minimal project holding only `app/telemetry/*.gd`, `app_state/build_info.gd` and `tests/telemetry_receiver_e2e.gd` from `e0a733937` | `E2E sent=3 queued=0 dropped=0 local_drops=0 status=on`; receiver stored 3 batches, 1 session token |
| Stored Mac context | same | `macos`, `arm64`, `apple_silicon`, threads `5_8`, RAM `5_8`, `forward_plus`/`metal`, no names, paths or user strings; `gpu_family: unknown` (headless has no adapter; the classifier maps `Apple M1` to `apple_silicon`) |
| Contract CI | GitHub | `Telemetry contracts` green on the last five pushes including the v0.2.9 tag |
| Shared test pool (14 jobs, Windows/macOS/Linux) | pool request `telem-audit-20261119a` | Windows and Linux jobs never placed: `INSUFFICIENT_DISK` (C: 3.6 GB, Linux 1.5 GB free; 4.67 GB needed) and ANGEL reported `OFFLINE` to the pool although SSH worked. One macOS job placed on ANGELA |

Not done here: a rendered/controller run of the notice on the Mac native panel, Linux runtime, TLS against a real endpoint, and an exported build sending to a real host (none exists). These are TELEM-21/22 gates.

## Findings

Verified by the lead against source; a Good Enemy review and a hosting/dashboard research pass contributed. Severity is for the goal "useful data from the first pilot".

### Usefulness

- **U1 (high): the weekly report will be empty at pilot volume.** `gpu_report` suppresses a whole day when any GPU family has fewer than 20 sessions ([rollup.py:91](../../../../services/telemetry/openrc_telemetry/rollup.py#L91)); the vehicle table does the same across every vehicle ([rollup.py:125](../../../../services/telemetry/openrc_telemetry/rollup.py#L125)). The weekly table only pools days that passed ([report.py:84](../../../../services/telemetry/openrc_telemetry/report.py#L84)). With tens to hundreds of players a week, split across nine GPU families and per-tag releases, no day passes; one `software` session suppresses the day. A single forged valid batch can also suppress a day.
- **U2 (high): 12 of 14 context fields are collected and discarded.** Rollup groups only by `gpu_family` ([rollup.py:81](../../../../services/telemetry/openrc_telemetry/rollup.py#L81)). OS, CPU, RAM, renderer, driver, resolution, VSync, FPS cap, graphics profile and input class live 48 h and vanish, so frame cadence mixes 60 Hz-capped with uncapped play and 1080p with 4K. Home/Workshop and warmup windows are sent but never aggregated; `gpu_ms` is always null.
- **U3 (medium): questions we care about cannot be answered.** No native-versus-reference flight-kernel flag (a stale native install silently falls back), no quality preset name (only default/custom), no session length, no physics tick cost. Crashes and hangs are unobservable by design (no spool, nothing at exit).
- **U4 (medium, Apple priority): MacBook panels are never recognised.** `resolution_class` accepts only exact 16:9 sizes ([telemetry_hardware.gd:107](../../../../app/telemetry/telemetry_hardware.gd#L107)); 2560×1600, 2880×1864, 1920×1200 and any windowed size become `other`. Whether the reported size is points or backing pixels on Retina is unverified.
- **U5 (low):** Core Ultra "Intel Arc Graphics" counts as `intel_arc`; GeForce MX/GT, Quadro and RTX A-series become `other`; RTX classes do not separate a 3050 from a 4090.

### Robustness

- **R1 (high): a tag missing from the receiver allowlist loses a release silently.** The receiver answers 422; the client drops and keeps collecting; nothing alerts.
- **R2 (high): `OPENRC_TELEMETRY_TRUST_PROXY` defaults to 0.** Behind any proxy every player shares one 20-burst, ~10/min bucket, so a few concurrent players get 429s and drop batches; 429s are not counted.
- **R3 (medium):** a redirecting endpoint (http→https, trailing slash, host alias) is dropped as non-retryable; a WAF 401/403 suspends the process.
- **R4 (medium): quitting from a flight loses that flight's summary** and the last ≤60 s ([telemetry_service.gd:200](../../../../app/telemetry/telemetry_service.gd#L200)). Usage counts lean toward players who return to Home; sessions under ~70 s send nothing.
- **R5 (medium):** only English and Spanish players are asked, and any launch argument except a renderer choice closes the route; the eligible population is smaller than the player base.
- **R6 (low):** a missed daily rollup cannot be redone (raw purge follows the 47 h deadline); days answered 503 or suspended still report `ready`.

### Weight

The design is careful but heavy for a pilot: three contract implementations (schema/reference, GDScript, receiver) change together on every field; the GitHub publisher's durable-intent ledger exists to post one private weekly issue. Keep the privacy core (consent, fail-closed release gate, allowlist, strict validation, raw/aggregate split). Simplify reporting rather than add to it.

### Tooling found on the way

The pool could not run telemetry tests on Windows or Linux for lack of disk, and lists ANGEL as offline while SSH to it works. That belongs to the [test queue](../../../../tools/testqueue/README.md) owners.

## External inputs (checked 2026-11-19, prices change)

- Hosting: Fly.io one machine in an EU region, about US$3.5–5/month, two volumes, with **scheduled snapshots disabled on the raw volume** (on by default, 5-day retention, [docs](https://docs.fly.io/volumes/snapshots)). Fly keeps app logs for days and its privacy policy says it collects IPs, so the service must log nothing personal and the canary test must run on the real host. A Hetzner VPS with Caddy gives full log control but new cloud servers showed "unavailable" at check time ([pricing](https://www.hetzner.com/cloud/cost-optimized)). Cloud Run (FUSE storage unsafe for SQLite), Oracle Free (reclaimable) and Workers + D1 (rewrite) were rejected.
- Dashboard: a static page built by GitHub Actions from aggregate JSON (Chart.js or Observable Plot; Observable Framework if it grows). Privately published Pages needs GitHub Enterprise Cloud ([docs](https://docs.github.com/en/enterprise-cloud@latest/pages/getting-started-with-github-pages/about-privately-published-github-pages-sites)); otherwise a Pages site is public to anyone with the URL.
- Precedent: the OpenTTD survey (opt-in, no identifier, weekly per-release public summaries weighted by play time, explicit non-representative warning; [participate](https://survey.openttd.org/participate), [summaries](https://survey.openttd.org/summaries/2026/wk27/15.3)) is the closest model to ours.
- Cohort floors: no product-analytics standard; k=5 (IAB PAIR) to k=20–50 appear in the literature ([arXiv 2304.13677](https://arxiv.org/pdf/2304.13677)). A per-cell floor does not prevent differencing across overlapping tables.
- Free always-on hosting (owner question; a release cannot depend on the owner's machines): **Cloudflare Workers free plan fits, with one design rule.** Limits per account: Workers 100,000 requests/day, 10 ms CPU per request, 1 s startup ([limits](https://developers.cloudflare.com/workers/platform/limits), [startup](https://developers.cloudflare.com/changelog/2025-10-10-increased-startup-time/)); D1 100,000 rows written and 5 M read per day, 5 GB, each written secondary index counts as another row ([D1 limits](https://developers.cloudflare.com/d1/platform/limits)); Durable Objects (SQLite only on Free) 100,000 requests and 100,000 rows written per day; Analytics Engine 100,000 data points/day, fixed 90-day retention ([pricing](https://developers.cloudflare.com/analytics/analytics-engine/pricing/)). Over a limit, requests fail until 00:00 UTC; nothing is billed. The client sends at most one batch per minute of play, so requests allow about 1,600 play-hours/day; writing each batch to D1 (≈5–8 rows) would cap at about 200–300 play-hours/day. Rule: **no database write per batch** — validate in the Worker, aggregate in one Durable Object, flush aggregates every few minutes (the pattern of [duyet/telemetry](https://github.com/duyet/telemetry), "no database writes on the hot path"). Constraints: D1 Time Travel keeps 7 days on Free and cannot be disabled ([docs](https://developers.cloudflare.com/d1/reference/time-travel/)), and Analytics Engine keeps 90 days, so neither may hold session tokens or batches under the 48-hour promise; new Workers have Workers Logs **enabled at 100 % by default** ([docs](https://developers.cloudflare.com/workers/observability/logs/workers-logs/)), so the deployment must disable observability; D1 can be pinned to the EU only when created (`--jurisdiction=eu`, [data location](https://developers.cloudflare.com/d1/configuration/data-location/)), Free-plan eligibility and Durable Object jurisdiction unverified; precompile schema validation to stay within 10 ms CPU. Comparable projects: [duyet/telemetry](https://github.com/duyet/telemetry) (Worker + Analytics Engine + D1), [gonzamoiguer/Game-Telemetry](https://github.com/gonzamoiguer/Game-Telemetry) (Unity playtests, Worker + D1 + R2), [bstudios/telemetry-and-analytics](https://github.com/bstudios/telemetry-and-analytics) (game studio, Workers + D1), [Counterscale](https://github.com/benvinegar/counterscale) (widely used web analytics on Analytics Engine); all small, none a large game. Paid fallback: Workers Paid US$5/month.
- Other free options compared at the owner's request (checked 2026-11-19):
  - **Owner's always-on Proxmox, unprivileged LXC** running the existing receiver unchanged as a systemd service; raw database on a separate volume mount point with `backup=0` (Proxmox excludes such volumes from vzdump; bind mounts are never backed up, [thread](https://pve.proxmox.com/pipermail/pve-user/2021-January/015808.html)). Exposure without open ports: **Cloudflare Tunnel** (free, needs a domain on Cloudflare, client address in `CF-Connecting-IP`, unverified here; [guide](https://flaviocopes.com/cloudflare-tunnel/)) or **Tailscale Funnel** (free, no domain, fixed `<node>.<tailnet>.ts.net`, ports 443/8443/10000, unpublished bandwidth limits, client address in `X-Forwarded-For` reported but not documented; [docs](https://tailscale.com/kb/1223/funnel); LXC needs `/dev/net/tun`, [docs](https://tailscale.com/kb/1130/lxc-unprivileged)). Residential availability is lower than cloud; the client already treats an unreachable receiver as best effort.
  - **Google Cloud e2-micro (Always Free):** runs the receiver unchanged, but only in us-west1/us-central1/us-east1 (no EU), standard disk only, 1 GB egress/month, and the external IPv4 may bill about US$3.65/month (sources conflict; [Google](https://cloud.google.com/free/docs/compute-getting-started), [analysis](https://yangworks.dev/guides/google-cloud-free-tier-e2-micro)); requires a card.
  - **Oracle Always Free:** runs unchanged, EU regions, but idle instances (CPU p95 under 20 % for 7 days, which describes this receiver) may be reclaimed ([docs](https://docs.oracle.com/iaas/Content/FreeTier/resourceref.htm)) and A1 limits were cut in 2026 ([InfoQ](https://infoq.com/news/2026/07/oracle-cloud-free-tier-limits/)); requires a card.
  - **Supabase Free:** rewrite to Edge Functions and Postgres; 500,000 invocations/month (about 270 play-hours/day), 0.5 GB, projects pause after a week of low activity ([pausing](https://supabase.com/docs/guides/platform/free-plan-pausing), [pricing](https://supabase.com/pricing)). Dominated by Cloudflare Workers.
- "Is data arriving": a free uptime monitor on `/healthz` plus a staleness check; GitHub scheduled workflows can be delayed or skipped, so use them only as a secondary check.
