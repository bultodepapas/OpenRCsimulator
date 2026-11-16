# Apple Silicon closeout

Date: 2026-11-16. Owner: lead developer. Status: executing.

## Deliverable

One runnable ARM64 development app on the M1, a measured 1080p comparison, and
an evidence-backed default-backend decision. Preserve reference fallback.
Public Developer ID distribution remains deferred by the owner.

This is the bounded closeout work order under the
[Apple master plan](apple-silicon-performance.md). The four-feature
[MetalFX plan](apple-metalfx.md) remains separate and incomplete; do not add new
rendering features, build another engine, or claim newer-hardware qualification
in this closeout.

## Fixed inputs

- Runtime baseline: `cb42e3bbf1479c47170bf35fb247c97672ef7992`; retain its
  completed native and Startup evidence. Keep the verified Engine 26 pair.
- Reuse existing export, debug, capture and admission tools. No new framework,
  profiler, evidence format or parallel optimization track.
- Only fix a reproduced blocker to package launch, measurement or admission.
  Finish such fixes before freezing the final candidate.
- Reuse native evidence only when the existing strict readers accept the
  actual app, harness, engine and absolute paths. Preserve original provenance;
  never relabel old receipts. Repeat a check only after a relevant change,
  failure or inconclusive result.

## Execution order

| Step | Action | Exit |
| --- | --- | --- |
| 1. Freeze | Resolve the public-CI transport blocker with the smallest tested host-only change, if needed. Verify retained native evidence with the current strict readers. Freeze one final source revision. | Exact source, engine and evidence identities agree; no unfinished runtime change. |
| 2. Package | Export one canonical ARM64 development app using the existing paired template. Exercise Home → Fly → pause → restart → Home → Fly → quit. Run the existing five packaged native checks. | Same app passes the route and package checks; clean shutdown; reference fallback works. |
| 3. Screen | On an idle M1, collect one reference/native pair at actual acquired 1920×1080, using the existing 30 s warmup and 120 s samples. | Valid focus, drawable, clock, physics/input and host evidence; report callback FPS, p95/p99, CPU and RSS. |
| 4. Qualify | Only after the screen is valid, collect the remaining four short pairs and three 30-minute pairs, alternating order. Run required CI for the frozen source. | Existing sustained-performance and CI gates pass on that exact candidate. |
| 5. Activate | Use the existing admission producer, required fleet evidence and four Home/default cases. Verify an ordinary launch selects native in its qualified scope and fallback still works. | Verified admission marker and actual native-default launch; no forced backend or bypass. |
| 6. Deliver | Give the exact app location, source revision, measured comparison, passed checks and remaining limitations. Update this checklist and consolidate results into the existing evidence home. | User can launch the tested app; each completion claim has direct evidence. |

## Acceptance stays unchanged

- Physics remains float64 at 240 Hz; no solver, aircraft-data, tolerance or golden changes.
- Use actual acquired 1080p pixels. Callback FPS is not displayed FPS or scanout proof.
- The first pair uses the complete existing promotion format and package pins,
  including both host witnesses; keep the same witnessed boot for all 16 captures.
- Keep p95 ≤ 18 ms, p99 ≤ 25 ms, simulation/wall ratio 0.99–1.01 and the
  existing maximum 5% regression limits, plus all host/resource gates.
- Require at least 5% median benefit in process CPU per accepted simulated
  second **or** callback FPS, separately in short and long groups.
- A short screen does not authorize default activation. The existing sustained
  protocol takes over three hours of collection; run it unattended only after
  the package works. No imports, builds or other benchmarks during captures.

## Stop rules

- On failure, retain the files and name one concrete cause. Fix only that cause;
  do not restart research, retune thresholds or create another optimization branch.
- Stop collection at the first invalid role. Inspect ownership and teardown
  before another launch. Never repeat a failed long campaign without a diagnosis.
- If the candidate fails admission, keep reference as default and report the
  exact blocker. Do not describe the native-default objective as completed.
- No repeated full native battery for an unchanged evaluator merely because a
  private wrapper or document changed. Required CI is still mandatory.

## Progress

- [x] 1. Final candidate frozen: `74aff714fe7415238bcd3527299d24945dcc73fa`;
  unchanged runtime accepted by the existing native verifier on M1.
- [ ] 2. Development app and package/lifecycle checks passed.
- [ ] 3. Valid 1080p reference/native screen reviewed.
- [ ] 4. Sustained comparison and required CI passed.
- [ ] 5. Native default and fallback verified through ordinary launches.
- [ ] 6. Tested app and concise results delivered.
