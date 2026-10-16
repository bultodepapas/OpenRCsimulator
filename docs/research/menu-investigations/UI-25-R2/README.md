# UI-22–26-R2 — bounded menus and grounded Home presentation

2026-10-15. Implementation evidence for the [active redesign](../../../MENU-REDESIGN-PLAN.md). Visual references and resource decisions remain in [UI-20-R2](../UI-20-R2/README.md).

## Delivered behavior

Home now uses a quiet navigation rail, separate language/settings header, prepared-flight summary and pinned Fly/utility actions. Flight, Aircraft, Practice and RC garage have separate bodies; Workshop retains its existing editor route. Full specifications and limitations live under **More flight details**. Aircraft capability and preview failures remain visible. The catalog reveals the selected entry and keyboard navigation enters that selection.

The desktop composition uses a 1920×1080 logical reference. Native 4K uses a factor of 2, retaining native 3D resolution. Navigation is about 320 logical / 640 physical pixels wide at 4K, approximately 16.7% of the screen; the rejected baseline was about 1320 physical pixels. At 720p the rail is 304 pixels and navigation/conditions use two columns. Long controller identifiers occupy one compact line with the complete identity in the tooltip and Controls. Spanish launch/time captions no longer force a wider column. Accepted astronomical time is shown in the time row, with phase/location/date/offset retained in its tooltip.

Charcoal scrims, warm white text and amber primary actions replace the large red button and repeated filled utility boxes. Red remains reserved for danger/destructive states. Opaque panels and reduced motion remain available. Settings has an 800-pixel workspace with bounded selectors and small toggles. Its header, Close and Keep/Revert actions remain pinned. Conditions fits all five tabs across its 960-pixel desktop workspace. Pause keeps the frozen flight view, a compact Resume action and expandable Session/Exit options.

Home presents the actual selected model parked on the existing field. A 40° camera replaces the 12° airborne shot. Render-only gear/skid contacts determine alignment and height; projected mesh bounds determine camera distance. Bounds/shadow geometry share the existing three-model cache. No aircraft geometry, flight start state, solver, weather model or golden flight was changed by this UI work.

## Native Windows evidence

Godot 4.7.2 `ed1daf0bf`, Compatibility/OpenGL, NVIDIA GeForce RTX 3090, Windows. Captures come directly from the native game's rendered viewport, not a browser or headless renderer. The script records actual pixel size, logical area, window mode, GPU, control rectangles and visible scrollbars in [geometry.json](geometry.json). At 4K the recorded image is **3840×2160**, `Window.MODE_FULLSCREEN = 3`; the desktop logical area remains 1920×1080.

The final matrix contains **104 lossless WebP captures**: 13 screen states × EN/ES × 720p/1080p/1440p/4K. States are Home, catalog, Practice, garage entry, Settings, Help, Controls, Conditions, Workshop, Natural Random, Failures, Pause and Settings over Pause. Final retained display captures were taken sequentially, with isolated preferences. The capture script activates production routes/buttons and sends real Esc key events; this is not a recorded physical-controller usability study.

| Output | EN and ES, normal text | Window mode |
| --- | --- | --- |
| 1280×720 | Home, Settings, Pause and Pause→Settings: no scrollbar | Windowed |
| 1920×1080 | Same | Windowed |
| 2560×1440 | Same | Windowed |
| 3840×2160 | Same | Fullscreen |

Catalog and long editor/help bodies intentionally scroll. At 200% text, body scrolling is permitted; primary/exit actions remain available. [Stress captures](stress/) cover Spanish Home/Settings/Pause with opaque panels and reduced motion at 720p, 1080p and fullscreen 4K.

Representative full-resolution frames:

- [Spanish 4K Home](captures/es-2160-home.webp), [English 4K Home](captures/en-2160-home.webp).
- [Spanish 4K Settings](captures/es-2160-settings.webp), [Spanish 4K Pause](captures/es-2160-pause.webp).
- [Spanish 720p Home](captures/es-720-home.webp), [English 1080p catalog](captures/en-1080-aircraft.webp).
- [English 1080p Conditions](captures/en-1080-weather.webp), [English 1080p Workshop](captures/en-1080-workshop.webp).

[Scene studies](studies/) compare runway, pits and club viewpoints for the trainer, jet and helicopter at 1080p. The runway/club composition was selected because the model and its contact shadow remain clear while the shelter, windsock and club establish RC scale. The nine study images are exploratory; final source and camera fitting are represented by the main capture matrix. The study matrix was not repeated at 4K.

## Verification

**23 targeted suites passed.** [Capture validation](validation.json), [test results](tests.json), [individual logs](logs/) and [native capture log](native.log), [Home refresh](home-native.log) and [1440p refresh](1440-native.log) retain results and expected aircraft-provenance warnings. Tests exercise complete catalog grounding/framing (including portrait/ultrawide math), compact EN/ES layouts with a long controller identifier and all time presets, live translation, popup anchoring after resize, Settings transactions, Pause teardown/restart/return, screen holds, preview cancellation/cache/resource ownership, Weather, runway starts, Workshop trials and input isolation. Tests are software checks, not physical flight validation.

Every captured Pause→Settings→Esc flow kept the simulation tick unchanged and returned to Pause. The native matrix emitted no `ERROR` or `SCRIPT ERROR`. Home, update-notice and the enlarged-text Pause test report two ObjectDB instances leaked at process exit. These warnings remain visible in the logs; no runtime error was ignored. The Workshop trial test also deliberately exercises rejection of changed presentation identity. Full physics/CI and fresh export packaging were not rerun for this UI slice.

Reproduce from the repository root, with the pinned executable available:

```powershell
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --editor --path app --import
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script docs/research/menu-investigations/UI-25-R2/capture.gd -- --out=C:/path/to/captures
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_ui_home.gd
& .\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_home_presentation.gd
```

The capture requires a 3840×2160 display for its fullscreen cases. `--height=720`, `--core`, `--home-only` and `--quick` narrow the capture run. Use an absolute script path if the local engine resolves relative script paths against `app/`. [Source identities](source-identity.json) identify the working-tree inputs; concurrent aircraft/crash work was kept separate.

## Remaining acceptance

The implementation fixes the reported oversized/no-scroll failures and provides a concrete native result for review. It does not claim owner aesthetic acceptance or universal accessibility certification. Catalog thumbnails, new font selection, optional blur/camera travel, same-host GPU performance comparison, full night/lighting review, every dense tab at 200%, DPI/monitor movement, fresh exports, other operating systems and first-time-user tasks retain the plan's gates. No new dependency or downloaded asset was needed for this slice.
