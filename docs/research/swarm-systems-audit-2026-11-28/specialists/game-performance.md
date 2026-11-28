# Game performance and presentation audit, second pass

Production revision `8d4169f8febfd7d78a028eaa817414217a54f24b`. The probes use Linux x86-64, Godot 4.8 beta 2 official `cafc17a19`, and the headless renderer. The figures below count application work and camera inputs. Target frame time, GPU commands completed, energy, and visible pixel differences require a rendered run. The audit made no production edits.

## 1. Toggling tree visibility leaves the pilot's solar occlusion stale

**Priority.** Fix the presentation error before optimizing the two smaller loops below. The cached answer can be exactly opposite to the current tree setting in either direction. A player at a stationary pilot position can retain the wrong answer until the eye moves more than two metres or the glare layer is replaced.

**Reproduction.** The fixture registered one 20 m tall ordinary mesh through the production tree preference, 60 m east of the 1.7 m pilot eye. It queried the production glare layer at 8° elevation, finished its budgeted worker, applied Tree detail, and compared the cached value with a new skyline built over precisely the same geometry and eye. The mesh stands in for production tree geometry because the headless renderer discards MultiMesh instance transform readback. The comparison exercises the actual visibility policy, worker and cache in both directions. The probe did not render pixels.

| Transition | Tree visible | Cached prior | Fresh prior at same eye | Prior after moving 2.1 m |
| --- | ---: | ---: | ---: | ---: |
| Full → Off | No | 0 | 1 | 1 |
| Off → Full | Yes | 1 | 0 | 0 |

**Production path.** `app/app_root.gd:2289` applies the live setting. `app/render/field_detail_preferences.gd:25` changes visibility for registered nodes. `app/render/field.gd:236` registers field tree cards and detail, and `app/scenery/imported_vegetation.gd:279` registers imported tree parts. `app/render/sun/skyline.gd:188` excludes hidden nodes during a build. `app/render/landscape_upgrade/sun_glare.gd:219` invalidates on eye displacement or initial construction only. The stale prior enters retinal dose at line 185 and the shader's off-screen fallback at line 204. The shader also has on-screen depth information. `docs/plans/low-end-gpu-performance.md` describes the live visibility and collision policy.

**Candidate change and acceptance.** Give the field's visible skyline geometry a revision, change it on Full/Simple ↔ Off tree visibility transitions, and include it in the glare cache key. Retain worker cancellation/join and staggered rebuild behavior, including a change while a job is in flight. Verify fixed-eye toggle parity and stable-setting reuse, then capture a stock pilot sightline through real canopy and a sightline clear of it. Tree collisions and the accepted simulation clock should remain identical.

## 2. A finished water impact keeps updating its hidden splash geometry

**Priority.** A localized opportunity for the fixed-wing water-crash screen. Ordinary live water impacts can remain on screen until restart. Active flight and ordinary dry crashes use different paths.

**Production path.** `app/main.gd:1337` disables automatic crash restart when its director is configured. The frame updates aircraft pose before `app/main.gd:1589` calls the director. `app/render/crash/director.gd:183` keeps calling the water layer for a live crash, including frames with a user hold. The separately restored aftermath without a live crash resets on expiry at line 163. `app/render/lake/water_effects.gd:178` clamps elapsed time to 3.2 seconds and still calls both the splash visuals and aircraft sink. At the cap the plume, two rings and droplets have expired. At line 472 it nevertheless updates three materials and two rings and visits 16 expired droplets. `_hide_droplet` at line 566 writes a transform and color for each slot.

**Reproduction.** The probe installed a forwarding counter subclass on a real Main scene's configured crash director, supplied a water impact snapshot and manually drove its production frame method. At 0.12 s the plume, droplets and one ring were visible. After expiry the effect checkpoint remained identical and the ordinary crash stayed active with automatic restart disabled. Every effect mesh was hidden in both terminal arms. The reference simulation backend ran headless. The input was a synthetic impact rather than a flown collision.

| Arm | Updates | Visual syncs | Expired-droplet hide calls | Material-clock calls | Sink-pose syncs |
| --- | ---: | ---: | ---: | ---: | ---: |
| Configured water layer, no impact | 60 | 0 | 0 | 0 | 0 |
| Live crash at 3.2 s | 60 Main frames | 60 | 960 | 180 | 60 |
| Same crash under a user hold | 60 Main frames | 60 | 960 | 180 | 60 |

Each expired-droplet hide calls one transform setter and one color setter in the implementation. The 960 measured hides therefore imply 1,920 setter calls per 60-frame terminal arm. Each of the 180 measured material-clock calls sets three uniforms, and each visual sync sets three alpha uniforms, implying 720 shader parameter assignments per arm. GPU execution and target timing were outside this probe.

**Candidate change and acceptance.** On a phase change, apply the new splash visuals once, including the final hide. A pause at an unchanged phase and later capped frames can skip those updates. Keep per-frame aircraft sinking/pose override, water-shadow suppression, camera target, event/checkpoint state, audio pause/resume and the restored director's expiry rule. Reinitialize on configure, begin, reset and restore; preserve one-shot audio silence on restore. Re-run startup, active splash, held/resumed splash, expired event and a second impact.

## 3. Settled Birds Off checks every allocated bird on every presentation frame

**Priority.** Small, recurring CPU work on scenery-enabled fields. Its 39-state stock roster makes this a lower priority than a measured bottleneck. The existing behavior directly supports live animated departures, arrivals and option changes.

**Reproduction.** On the stock field with Birds Off at build, the staged scenery setup allocated two MultiMeshes and two shader materials with 39 instance/state slots. All 39 were hidden. Over 120 stable polls with an advancing clock the production runtime called its real pending check 120 times. Each returned false. The code's full scan on false implies exactly 4,680 state visits. There were zero settle calls, zero lighting reapplications and zero reported changes in that arm. Six separate sun changes across the runtime's threshold triggered six full lighting reapplications while drawn primitives stayed zero. Switching to Many and finishing arrivals yielded 805 drawn primitives. The separate `OPENRC_SCENERY_BIRDS=off` build produced no bird node.

**Production path.** `app/app_root.gd:2309` sets the saved preference independently of `app/scenery/scenery.gd:76` and the build switch at line 462. `app/scenery/birds.gd:263` constructs the species geometry and instance allocations. `app/scenery/birds/birds_runtime.gd:40` polls local state, weather and preference serial, then calls `app/scenery/birds.gd:177` to scan every steady or hidden state. A flow threshold calls `apply_lighting` at line 67, which copies the state arrays and loops over both groups. Fully hidden buffers issue no per-bird transform or color writes.

**Candidate change and acceptance.** Maintain a transition count or pending flag when target states change and settle. Once Birds Off has fully settled, avoid weather-driven recalculation while still responding immediately to the preference serial. On re-enable, read current weather and sun before scheduling arrivals. A lightweight dormant layer could defer mesh construction at boot if measurements justify the added lifecycle complexity. The existing contract in `app/tests/test_birds.gd:572` requires departures/arrivals, pause settling and an addressable Off-built layer. Include reverse transitions, clock wrap, lighting snapshots and staged-build cancellation in regression coverage.

## Reproduction files

The three companion scripts run individually with the pinned Godot executable, `--headless --path app --script <absolute-probe-path>`. For the water witness, append `-- --soundscape=off`. The result lines are machine-readable JSON. The skyline witness compares cached and freshly rebuilt values, the bird witness forwards high-level method dispatch without changing results, and the water witness instruments a subclass that forwards the supported implementation methods.

| Reproduction | Script | Console receipt |
| --- | --- | --- |
| Fixed-eye tree setting | `skyline_tree_toggle.gd` | `skyline-console.log` |
| Water splash expiry | `water_after_expiry.gd` | `water-console.log` |
| Settled Birds Off | `birds_off_poll.gd` | `birds-console.log` |
