# UI-29-R3 — final visual and navigation review

2026-10-16. Review of the current native menu shell after [UI-23-R5](../UI-23-R5/README.md), with bounded fixes to focus rendering, Escape handling and Spanish copy. This is a source-tree review, not export or cross-platform acceptance.

## Visual direction and findings

The composition keeps the aircraft and field visible, uses dark translucent surfaces and one gold accent, and gives each screen one primary action. Home reserves space for Fly and utilities; Pause emphasizes Continue; dense reference and editor content scrolls inside its own body. The existing 140 ms entrance fade, visible keyboard focus and focus restoration supply restrained interaction feedback. Reduced motion remains available.

| Area | Finding and disposition |
| --- | --- |
| Home, Settings and default Pause | Fit the checked normal-text desktop canvases without unnecessary body scrolling. Text and controls remain bounded at 720p, 1080p and native fullscreen 4K. |
| Keyboard focus | Outward focus borders were clipped by scroll viewports in Pause and Controls. The shared outline now draws inside control bounds, retaining its color and width without changing layout. Compare [before](before/en-1280x720-100-controls.webp) and [after](captures/en-1280x720-100-controls.webp). |
| Native Escape | Windows input produced logical Escape (`4194305`) with another physical code (`4194313`). Menus ignored it. The shared surface now recognizes either code; native Controls closes and restores its Home opener. A regression also checks nested Controls → Settings → Home. [Observed input before](interactive.log), [after](interactive-fixed.log). Flight-control physical-key mapping is unchanged. |
| English and Spanish | Added missing time/sky validation and unknown-controller help translations; removed a conflicting duplicate entry; made controller-screen references consistent. Spanish uses “Taller” and “fallas” consistently across navigation and status messages. Display confirmation and disconnected-radio instructions now state the resulting action clearly. English source labels remain unchanged. |
| Large text / small windows | At 960×540 with 200% text, dense bodies require scrolling. Pinned dialog actions and primary Home actions stay reachable. Controller title ellipsis and conditions tab overflow remain intentional space-saving behavior. This extreme mode is usable but substantially denser than the normal desktop layout. |
| Workshop preview | Still too small for comfortable model inspection. Its fixed camera preserves the visual comparison between 0.5× and 2× recipes. A projected-bounds experiment only increased the model by about 6% and was removed. A separate preview/inspection design remains open; this review does not claim to resolve it. |

Representative final captures: [720p Home EN](captures/en-1280x720-100-home.webp), [720p Settings ES](captures/es-1280x720-100-settings-display.webp), [4K Home ES](captures/es-3840x2160-100-home.webp), [4K expanded Pause EN](captures/en-3840x2160-100-pause-session.webp), [200% text Settings](captures/es-960x540-200-settings-interface.webp), [Workshop ES](captures/es-1920x1080-100-workshop.webp).

## Native coverage and flow

Godot 4.7.2 `ed1daf0bf`, Compatibility/OpenGL, Windows, NVIDIA RTX 3090. The host reported 3840×2160 at 144 DPI. The 4K cases use fullscreen mode; other cases use native windows. Preferences are isolated under `tmp/menu-final-review/`.

| Pixel size | Language | Text size |
| --- | --- | --- |
| 1280×720 | EN, ES | 100% |
| 1920×1080 | EN, ES | 100% |
| 3840×2160, fullscreen | EN, ES | 100% |
| 960×540 | ES | 200% |
| 3440×1440 | ES | 100% |

The native pass originally saved **158 screenshots** with actual pixel and Control geometry in [geometry.json](geometry.json). The evidence folder retains **63 representative images**: all 42 full-route screens at 1920×1080 in English and Spanish; Home, Settings Display and default Pause in the six other viewport/text cases; and focused after-fix Controls at 720p, expanded Pause at fullscreen 4K, and Settings Interface at 200% text. This preserves visual route coverage in both languages at 1080p and the core layout evidence across every checked case. The [core scroll inventory](core-scroll.json) points to all 24 retained core images and confirms that Home, Settings Display and Pause have no visible scrollbar in the seven normal-text cases; the 200% small-window case scrolls as intended.

`geometry.json` retains the pixel and Control measurements for all 158 original frames. Its `image` values for the 95 omitted frames, and the corresponding names in [the native log](native-final.log), are historical output paths; those images are no longer in `captures/`. The retained 63 frames occupy 8.2 MiB, down from 23.5 MiB for the original matrix. The three `before/` comparison images and all scripts, logs and geometry records remain available.

Keyboard activation and Escape exercise production routes. Assertions check Home returns, collapse-before-resume behavior in Pause, preserved simulation ticks while Settings is open, and End flight returning to Home. Separate Windows mouse/keyboard interaction checks cover language switching, nested Controls, Tab navigation and the logical-Escape correction. A connected XInput controller caused the expected startup arming pause; the driver accounts for it without resuming the aircraft. [Native log](native-final.log).

## Fluidity

Six warmed Settings open → Interface → Sound → close cycles were sampled at each size below. Intervals are native process-frame cadence measured with a monotonic clock. Screenshot encoding is excluded; other host applications remained open. These observations cover the tested menu navigation, not first-load model construction, input-to-display latency or general flight performance.

| Canvas | Samples | Median interval | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| 1920×1080 | 589 | 8.229 ms | 10.539 ms | 25.685 ms |
| 3840×2160 fullscreen | 525 | 11.048 ms | 15.043 ms | 29.407 ms |

[Raw frame samples and Settings creation CPU timings](fluency.json). Cold model selection/loading remains outside this measurement; prior [UI-05-R3](../UI-05-R3/README.md) limits still apply.

## Verification

Fourteen focused scripts pass their functional checks, including the 560-case modal matrix, 422 responsive Pause checks and 17,245 controller-layout checks. Language, Settings preview/revert, Home, pause lifecycle, nested screen stack, conditions, Workshop, failure practice and menu audio are included. The final retained test and native logs contain no script/engine-error diagnostics. [Test logs and summary](tests.json), [parse results](parse.json), [source identity](source-identity.json).

Reproduce the original full matrix in a clean worktree at the [source identity](source-identity.json) commit (`4658775315b7b273c4a547f60ca16d3b4e113e0e`) with Godot 4.7.2 `ed1daf0bf`. From the repository root, run `.tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script ../docs/research/menu-investigations/UI-29-R3/review.gd`. The script writes fresh captures and geometry to `tmp/menu-final-review/final-captures/`, not into this retained evidence folder. Add `-- --interactive` for the isolated 1080p manual session. The native matrix requires a physical 4K host for its fullscreen pixel assertion. The retained [test runner](verify.py) can be copied to `tmp/menu-final-review/` and accepts test script names as arguments.

The shared workspace also contained changes from other tracks, including new accident-report translations. Those are preserved and are not part of this menu review. Mixed-monitor DPI, other operating systems, exported packages, first-load stalls and human pilot acceptance remain separate gates.
