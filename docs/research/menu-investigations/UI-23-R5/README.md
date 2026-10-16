# UI-23-R5 — measured menu invalidation costs

2026-10-16. A bounded optimization of the responsive shell delivered in [UI-23-R4](../UI-23-R4/README.md). Changes are limited to presentation invalidation in `app_root.gd` and Home. Aircraft loading, physics, visual assets and engine settings are unchanged by this slice.

## Delivered changes

- Volume preview updates the mixer without rebuilding every screen's Theme. Motion policy updates its live flag. Text scale and opacity still rebuild themes; compact-density changes retain their existing resize path. Keep/Revert and fullscreen recovery remain intact.
- Home updates a local font override only when its resolved size differs. Its two gradient textures change only when their colors differ. Repeated same-density layout passes no longer invalidate those resources; changing text scale or opacity still updates them.

## Measurement

Windows, pinned Godot 4.7.2 `ed1daf0bf`, headless rendering and Dummy audio. Five fresh processes per variant, alternating order, 60 samples per process (300 samples per operation/variant). Startup, aircraft construction and presentation frames are excluded from the synchronous-handler timers. Other applications remained running. These are local CPU measurements, not GPU/frame-rate or input-to-scanout results.

The reference retains the immediately preceding `app_root.gd` and Home implementations in [reference/](reference/). The volume probe opens real Home→Settings and changes the actual slider; the Home probe isolates repeated layout calls from the 3D preview. Shared dependencies are unchanged between paired variants. [Summary](summary.json), [raw runs](measurements/), [observer](benchmark.gd), [runner](compare.py) and [source hashes](source-identity.json) retain the evidence.

| Synchronous operation | Reference median | Candidate median | Reference p95 | Candidate p95 |
| --- | ---: | ---: | ---: | ---: |
| Menu volume change | 7.063 ms | 0.064 ms | 9.950 ms | 0.097 ms |
| Repeated Home layout | 0.833 ms | 0.494 ms | 1.120 ms | 0.662 ms |

The median measured handler cost decreases by approximately 99.1% and 40.7%, respectively. Each run's 60 volume changes previously produced 120 Home/Settings theme notifications; the candidate produces zero. The 60 unchanged Home layout calls previously produced 360 gradient notifications and 60 notifications on the observed navigation button; both now remain zero. The broader resolution tests verify that actual scale, language and viewport transitions still reflow.

## Verification and limits

Nine focused test scripts pass their functional assertions, including Home's 240 checks, Settings integration's 25 checks and the 560-case modal matrix. Existing Conditions, time, weather-slider, audio and scaling checks remain included. [Results and logs](tests.json) and [parse checks](parse.json) are retained. New regression assertions check theme identity during volume changes, live opacity/motion/Revert behavior, and the absence of resource invalidation during same-density window resizing.

The [native pass](native.log) saves [15 captures and window metadata](captures/geometry.json) at EN 1280×720/100%, ES 960×540/200% and ES 3840×2160/100%. Windows reports a 3840×2160 screen at 144 DPI; the last case uses fullscreen mode. Native slider changes verify stable Theme identities and updated mixer gain. The final native run has no script or engine-error diagnostics.

- [720p Home](captures/en-1280x720-100-home.webp)
- [Small window, 200% text, sound settings](captures/es-960x540-200-sound.webp)
- [4K fullscreen sky controls](captures/es-3840x2160-100-sky.webp)

Two parallel headless integration runs report the previously observed intermittent “2 resources still in use at exit” diagnostic after passing all assertions. Serial verbose Settings and Weather reruns are clean; both the diagnostic and reruns are retained. Its cause remains unconfirmed, as in R4. This slice makes no memory-leak, physics, export or general FPS claim.

A separate experiment replaced the Conditions grids' temporary two-column measurement with a read-only calculation. It removed redundant sorting in a 480-pixel stress fixture, but supported 960×540 cases already had no idle sorting, and the small direct-call timing sample showed no gain. That candidate was removed; the existing Conditions implementation is retained.

To repeat the paired measurement, copy `benchmark.gd`, `compare.py` and both `reference/*.gd` files into `tmp/menu-optimization/`, then run `python tmp/menu-optimization/compare.py` from the repository root. Run `native.gd` through the pinned Godot executable with `--path app --audio-driver Dummy --script ../docs/research/menu-investigations/UI-23-R5/native.gd` for the native flow. Both probes use isolated preferences and write under `tmp/menu-optimization`.
