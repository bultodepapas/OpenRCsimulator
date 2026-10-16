# UI-23-R4 — resolution and live reflow

2026-10-16. Source implementation following [revision 8](../../../MENU-REDESIGN-PLAN.md). This extends the existing compact shell; it does not change simulation state or aircraft data.

## Changes

- Home reflows navigation, labels and utility actions within the available rail. Enlarged navigation moves into the scroll body on short windows; essential controls retain the full chosen font scale. Pause restores a useful scroll position after resizing, preserving the focused action and pause reason. Deferred fade updates tolerate teardown.
- Controller forms use labeled fields and adaptive arrangements; section navigation wraps and moves into the body on short windows. Save/Cancel remain pinned. Draft bindings, preview, save and capture behavior remain owned by the existing controller flow.
- Controller axis labels remain owned by their hidden table during compact reflow. Verification exposed detached labels leaking at teardown; ownership, table ordering and destruction now have regression coverage.
- Weather, Time and Sky remove longest-item minimum widths from selectors, wrap long captions and measure the remaining body height after header/tabs/actions.
- Failure and overlay dialogs have bounded panels and scrollable bodies with pinned actions. Enlarged text stacks their fields. Natural Random leaves space for all four recovery actions at 540p.
- Workshop bounds its workspace, stacks aircraft/recipe columns when needed, keeps Close/Test fly available, and places history actions with the recipe. Status messages reveal themselves in the body.
- Help reflows key tables and keeps Close outside the body. Arrow/Page/Home/End input reaches the complete reference and About. Its test now sets a real 1280×720 window and checks actual viewport geometry and keyboard reachability; the old minimum-size comparison ran against the headless default 64×64 window and did not establish a no-scroll layout.

## Verification

The matrix uses EN/ES, 100%/200% text, live wide→narrow→wide resizing, and physical-to-logical conversion through `UiScale`. Pixel sizes include 960×540, 1024×576, 1024×768, 1280×720, 1280×800, 1366×768, 1600×900, 1920×1080, 1920×1200, 2560×1440, 2560×1080, 3440×1440 and 3840×2160. The 4K logical canvas remains 1920×1080; ultrawide 3440×1440 becomes 2580×1080.

Focused geometry tests cover Home, Pause, controller sections, all Conditions pages and six other modal/briefing screens. The modal test alone exercises **560 combinations**, checking horizontal containment, viewport bounds outside scrolling bodies, and usable body height, including long error messages. Existing functional tests cover keyboard routes, reversible settings, pause holds, failure drafts, Natural Random, overlays and Workshop trials. All **28 focused test scripts** pass their assertions; results and retained logs are in [tests.json](tests.json). [Parse checks](parse.json) cover the 12 changed UI scripts and these 28 tests. This is not a full physics or export test run.

The controller matrix passes 17,245 checks across all five sections, including full font scaling, live resize, focus, node ownership and teardown. Home passes 239 checks and Pause reflow passes 422. These are software assertions, not a substitute for human readability review or physical-device acceptance.

One headless batch of `test_failure_availability_ui` passes all 62 assertions but reports two resources still in use at engine shutdown; the diagnostic is retained in its log and `tests.json`. Targeted verbose reruns did not reproduce it, and a preview teardown probe found no pending or queued load. Its cause remains unconfirmed. The final native matrix and fullscreen runs have no script, engine-error or shutdown-leak diagnostics. No arbitrary teardown delay was added.

Normal Home does not require body scrolling at 720p and above. The 540p recovery layout, catalogs, full reference text, dense editors and enlarged-text bodies can scroll; their primary actions and exits remain available. No claim is made that arbitrary content must fit without scrolling.

## Native evidence and limits

[capture.gd](capture.gd) runs production routes with isolated preferences and saves **84 native viewport images** (75 windowed, nine fullscreen) plus [geometry](captures/geometry.json). Captures use the pinned Godot 4.7.2 build, Compatibility/OpenGL and the RTX 3090. The harness verifies requested pixel dimensions against actual image dimensions. Twelve Pause→Settings→Pause checks preserve the paused simulation tick. [Source identity](source-identity.json) records the tested files. These checks supplement geometry assertions with visual review.

| Inspected case | Capture |
| --- | --- |
| 4K fullscreen, normal text, Home / Pause | [Home](captures/es-3840x2160-100-fullscreen-home.webp), [Pause](captures/es-3840x2160-100-fullscreen-pause.webp) |
| 3440×1440 ultrawide | [Home](captures/es-3440x1440-100-home.webp) |
| 1024×768, English | [Settings](captures/en-1024x768-100-settings.webp) |
| 960×540, Spanish, 200% text | [Home](captures/es-960x540-200-home.webp), [Controls](captures/es-960x540-200-controls-axes.webp), [Workshop](captures/es-960x540-200-workshop.webp) |
| 4K, Spanish, 200% text | [Settings](captures/es-3840x2160-200-settings-interface.webp), [Controls](captures/es-3840x2160-200-controls.webp) |

Reproduce from the repository root in PowerShell (the harness writes to `tmp/menu-resolution/captures`):

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script ../docs/research/menu-investigations/UI-23-R4/capture.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script ../docs/research/menu-investigations/UI-23-R4/capture.gd -- --fullscreen-only
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_ui_modal_responsive.gd
```

The final retained Windows runs report one **3840×2160, 144-DPI display**. The initial session reported 1920×1080/96 DPI; once Windows reported 4K, the matrix was repeated and a separate fullscreen pass added. The nine fullscreen images verify `Window.MODE_FULLSCREEN`, actual display dimensions and actual image pixels for Home, Settings and Pause in EN/ES at normal text, plus ES at 200%. See [windowed log](native-final.log) and [fullscreen log](native-fullscreen.log). Ultrawide images remain native-size window renders. Mixed-monitor DPI transitions, physical controller usability and exported builds remain open.

No new assets, dependencies, physics tuning or golden-flight recordings are introduced. The shared working tree also contains unrelated work; the recorded source hashes identify this slice without claiming ownership of those changes.
