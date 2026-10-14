# UI-05-R3 — responsive selection and bounded resource loading

2026-10-14. Implements the first loading/selection slice of [investigation 26](../26-menu-responsiveness-loading.md). This improves feedback and removes obsolete work; it does **not** eliminate every first-visit frame stall.

## Delivered behavior

- The aircraft card, controls and saved selection update immediately. Recent model hits retain UI-05-R2's synchronous three-model cache. Misses permit a rendered frame before preparing a preview; successive requests replace pending intent instead of building every intermediate aircraft.
- Imported aircraft resources load through `ResourceLoader` with subthreads off. One request may be active and only the latest replacement queued. At most two completed scene references are retained. Procedural construction, provenance/data validation, shadows and night dressing remain on the main thread.
- Loading/error text is separate from save/launch errors and translates live. A failed preview preserves the last valid image. Request generation and Home identity prevent obsolete success/failure callbacks from replacing current state.
- AppRoot owns the resource broker. Departing Home cancels its consumers and releases retained references; outstanding engine work is drained without applying it. A temporarily detached Home can resume its current intent. On **application teardown only**, the broker joins any outstanding load because the engine API has no cancellation operation; quitting during a load can therefore wait for it. Ordinary Home replacement does not join the worker.
- Fly uses the selected aircraft ID and independently validates its model/physics. It never silently substitutes the previous image's aircraft. Failed startup restores usable Home and retains the launch error.

Runtime: `app/ui/home_preview_resources.gd`, `app/ui/home_scene.gd`, `app/ui/home.gd`, `app/app_root.gd`, and Spanish strings. No aircraft geometry, import settings, physics, goldens or engine pin changed.

## Measured effect

Windows Godot **4.7.2 ed1daf0bf**, Compatibility, RTX 3090 / NVIDIA 610.88, 1280×720, existing evening defaults, Dummy audio. Five fresh processes per variant, alternating order; each process visits Stik → Extra → jet for five cycles. Stik is already constructed when Home opens and is not a cold-selection case. Four subsequent cycles give **20 warm samples per aircraft/variant**.

The reference uses the same frozen candidate shell with its selection call changed back to synchronous `show_aircraft`; this isolates the new scheduling/loading behavior from unrelated shared-tree work. First feedback ends at the first `frame_post_draw` after selection. Ready ends at the frame displaying the requested model. Neither is physical input-to-scanout latency. A fresh process does not clear OS/GPU caches.

| First visit, median | Synchronous reference | Candidate |
| --- | ---: | ---: |
| Extra selection handler | 357.59 ms | 1.68 ms |
| Extra first feedback | 394.17 ms | 8.67 ms |
| Extra requested preview ready | 394.17 ms | 427.51 ms |
| Jet selection handler | 1684.77 ms | 1.51 ms |
| Jet first feedback | 1727.34 ms | 6.44 ms |
| Jet requested preview ready | 1727.34 ms | 1604.27 ms |

The Extra's full preview is **33.34 ms later** in this campaign: deferred procedural work improves immediate feedback/coalescing, not construction time. Warm handler medians remain 4.71–5.01 ms in the candidate versus 4.70–4.78 ms in the reference. Warm measured frame intervals stay below 18 ms in both variants; this is a small host-specific observation, not a hardware or FPS guarantee.

The jet's worst first-visit frame interval decreases from **1865.74 to 1173.92 ms**, but there is still a frame over 100 ms in every fresh-process selection. Extra likewise retains one frame over 100 ms per first visit. P95 alone hides the jet's rare large build spike among many short background-loading frames; [summary.json](summary.json) includes maxima and counts above 33/50/100 ms. The final observer waits for the process-frame boundary after completion, so the final blocking build is counted.

The attribution [profile](profile.log) separately loaded the jet resource in **716.22 ms** and instantiated it in **0.55 ms** before calling selection. The remaining model adapter, shadow collection and night dressing still cost hundreds of milliseconds. This is a separate diagnostic run, not a term to add to the comparison table. An initial instrumentation attempt invalidated the imported builder's pinned hash; the accepted probe observes that builder externally and retains all contract checks. An early timing observer omitted the final frame boundary; its frame distributions are superseded by the retained final samples.

## Verification and limits

- Resource broker: **13 checks**, including latest queued intent, obsolete completion disposal, bounded references, cached completion, cancellation, procedural replacement and application teardown.
- Preview lifecycle: **23 checks headless and native**, using real Home/builders with controlled resource completions. Covers rapid bursts, stale success/failure, retry, live EN/ES, retained reversal, detach/restore, immediate/double Fly and a deliberately rejected startup. The rejected-flight fixture exercises shell rollback; it is not a physical flight validation.
- Existing aircraft selection/launch, Home/rotorcraft routing, language, layout, launch-caption layout, controller, input, projected shadow and preview-cache checks pass on the frozen source. Full `app/test.sh` and platform exports were not run.
- Final-ready reference/candidate native images and their pixel comparison are retained. The backdrop outside the 440 px sidebar is pixel-identical; 3028 sidebar pixels differ because the captures have different focused buttons (Start/Fly). This is not full-frame pixel parity. Pending EN/ES captures use controlled incomplete loading to inspect the real layout; they are not timing evidence.
- The short pending-capture observer reports four audio stream/playback objects at shutdown; verbose output identifies MP3/WAV objects. Its control run with no preview request reports the same warning. Native preview lifecycle tests and the timing runs are clean. The capture warning is retained, not represented as general audio/shutdown qualification.
- Static-memory observations include engine caches and cannot isolate the broker or establish resident VRAM. Bounds are by resource/model count, not bytes. Initial Home and flight construction remain synchronous.

The shared-tree integration results are recorded separately in [integrated.json](integrated.json); all accepted measurements use the frozen project. The host may have unrelated development workloads. Claims are limited to this campaign and its retained source.

## Reproduction and remaining order

[manifest.json](manifest.json) hashes the retained artifacts. `sources.json.gz` identifies the initial working-tree snapshot; `candidate-sources.json` and compressed runtime/test sources identify the accepted candidate. Compressed preparation, attribution, benchmark, capture and verification scripts preserve the exact observers. `samples.json.gz` contains all 150 final selection records; `summary.json` uses milliseconds, while raw sample fields ending in `_usec` use microseconds.

Recreate `tmp/ui05-r3/snapshot/app` from the initial source identities plus the retained candidate. Include the manifest-referenced authoring sources as `prepare.py` does; import using the pinned engine. Do not import over a shared working tree. Decompress the scripts into `tmp/ui05-r3/`, then run `bench.py` sequentially without overlapping Godot workloads. The accepted campaign copied an existing import cache with unchanged source assets; a clean import/export remains a separate qualification gate. Run the two new `test_ui_preview_*.gd` scripts and the existing route checks headless; repeat preview requests natively. `verify.py` and `integrated.py` retain command scope and exit/error checks.

Next: isolate and reduce the remaining main-thread night-kit/model work before promising smooth first visits. Neighbor prefetch, subthread tuning and texture compression A/B remain conditional experiments: no speculative fleet loading is enabled. Texture changes keep VQ-01c/d and VQ-02a gates; shader warmup waits for attribution of a shader-specific first-draw stall. The current evidence supports selected-resource loading and faster feedback, not those untested changes.
