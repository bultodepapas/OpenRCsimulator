# UI-28-R3 — menu feedback and flow refinement

## 2026-10-24 — natural feedback follow-up

The owner's listening feedback replaces the electronic Interface Sounds palette with fourteen unmodified wood/soft-impact clips from Kenney Impact Sounds 1.0 (CC0). Navigation rotates three takes with small downward pitch variation. [Current source hashes, license and interaction contract](../../../../assets/ui-audio/README.md).

The service distinguishes open, pause, resume, restart, activity exit, committed quit, saved, cancel and rejection. Failed restart, failed Settings persistence and failed trace recovery report rejection before any success/exit cue. Same-action incidental sounds yield to outcomes; replaced tails fade over 18 ms within the existing two-voice budget. Quit keeps its native tail for at most 500 ms after all recording/draft decisions, blocking further input; muted/Dummy routes quit immediately.

`test_menu_audio`, `test_ui_settings_integration`, `test_ui_pause` and `test_ui_quit` pass through the checked runner. They exercise actual input, successful/rejected restart, failed-save retry, Stay/Discard, nested Workshop/trace quit guards and repeated Home/flight cleanup. The existing aircraft inertia warning remains unrelated.

The [WASAPI report](audio/natural-2026-10-24.json) records all sixteen logical cues at 48 kHz: peak 0.14731 at 35%, 0.42093 at 100%, and zero nonzero PCM samples at mute. The [final closing-tail check](audio/natural-quit-2026-10-24.json) observes one deferred quit, locked input and nonzero tail output. Reproduce with [tools/audio/menu_probe.gd](../../../../tools/audio/README.md#menu-feedback); WAVs are kept outside Git. These are mixer/routing checks; speaker listening remains subjective. The original evidence below describes the earlier palette.

2026-10-15. Implemented in `app/`, following the [revision 7 plan](../../../MENU-REDESIGN-PLAN.md). This is a local-source result, not an exported-release or human usability acceptance claim.

## Delivered behavior

- **Home:** the Garage destination replaces Fly with the pinned RC-car action. Practice uses short explanatory copy, vertically arranged actions and explicit next-flight failure status. Neither destination expands the compact rail. Catalog entries show model/capability, keep a persistent selected accent and reveal the selected entry without stealing focus. Flight details have a changing disclosure caret.
- **Settings:** Display, Interface and Sound are separate categories in an 800×600 logical-pixel workspace with pinned title, Close and Keep/Revert. Normal EN/ES layouts fit without scrolling. Disabled Keep is visibly inactive; the volume slider has a visible full track and numeric value. Enlarged text scrolls only the body, with extra focus clearance to avoid fractional-pixel clipping. Language retains its existing immediate-save behavior, stated beside the selector.
- **Audio:** a host-owned service observes the active screen once, gates focus/hover/range cues to input, suppresses route-button duplicates, survives detach/reattach, and limits playback to two voices. Acceptance/back/rejection can replace a navigation voice. Initial Home/autofocus stays silent. Resume/Restart use acceptance; failed launches use rejection. Same-frame nested transitions produce one acceptance cue. Flight technical routes do not install the service.
- **Preferences:** menu volume defaults to 35%, previews live and supports complete mute. Keep persists it; Revert/Close restores the saved value. It is an optional schema-1 extension in the separate presentation file, preserving older files and future-schema write protection. The existing 15-second fullscreen recovery remains intact.

Seven unmodified OGG clips come from [Kenney Interface Sounds 1.0, CC0](https://kenney.nl/assets/interface-sounds). [Provenance, exact archive/file hashes and retained license](../../../../assets/ui-audio/README.md) identify the source; no generated replacement sounds were used.

## Native visual review

Godot 4.7.2 `ed1daf0bf`, Windows, Compatibility OpenGL 3.3, NVIDIA RTX 3090. Native sessions ran sequentially with isolated preferences. The normal matrix contains **60 captures**: EN/ES × 1280×720, 1920×1080 and actual fullscreen 3840×2160 × Home, Aircraft, Practice, Garage, the three Settings categories, Conditions, Pause and Settings from Pause.

At 4K the recorded window mode is `3` (fullscreen), the image is 3840×2160 and the logical canvas is 1920×1080. The normal matrix has no body scrollbar outside the intentionally scrolling catalog. Settings panels remain inside the viewport. Ten additional Spanish 200% captures cover the three categories, the focused language selector and its open popup at 720p/4K. Focus reveals the complete selector while Close/Keep/Revert remain pinned.

Reviewed images include:

- [Spanish 4K Home](captures/es-2160-home.webp), [catalog](captures/es-2160-aircraft.webp), [garage](captures/es-2160-garage.webp) and [Pause](captures/es-2160-pause.webp).
- [720p Practice](captures/es-720-practice.webp), [Interface](captures/es-720-settings-interface.webp) and [Sound](captures/es-720-settings-sound.webp).
- [200% language focus at 720p](stress/es-720-settings-interface-language.webp) and [4K language popup](stress/es-2160-settings-language-popup.webp).

The inspection caught and corrected a width expansion from horizontal Practice actions/unwrapped Garage text, an indistinct volume rail, an apparently active disabled Keep action, and fractional-pixel clipping of focused enlarged controls. [Normal geometry](captures/geometry.json), [enlarged geometry](stress/geometry.json), [validation](validation.json), [native log](logs/native.log) and [stress log](logs/stress.log) retain the measurements. The actual RC-car scene still opens after choosing the Garage action; Home's shared backdrop remains the aircraft presentation.

## Behavior and audio proof

[Fifteen focused suites](tests.json) finish with exit 0 and no `ERROR`, `SCRIPT ERROR` or `FAIL` records in their retained final logs. Coverage includes menu audio, Settings validation/persistence/integration, Home, Pause, ScreenStack, language, keyboard input, controller menu/ground routing, Natural Random, Workshop trials and preview lifecycle/cache. Settings integration exercises actual keyboard selector/category input, live volume undo, nested focus restoration, held simulation ticks and explicit Resume. Native capture logs confirm that closing Settings returns to Pause without advancing ticks.

An additional [native mixer probe](audio_probe.gd) records engine output with [Godot AudioEffectRecord](https://docs.godotengine.org/en/stable/classes/class_audioeffectrecord.html); it does not open a microphone. [Seven cues](audio/menu-cues.wav) are recorded at the default 35% volume, stereo 48 kHz. [Muted output](audio/muted.wav) has zero nonzero PCM samples. [Measurements](audio/measurements.json) show a peak of approximately 0.151 (below full scale) for the cue sequence. This establishes mixer output and mute, not a listening-panel judgment or speaker calibration. Headless audio checks verify cue requests, lifetimes and routing rather than audibility.

One preview regression exposed a deferred Home layout call after removal from the tree; the callback now exits before viewport access. Parallel scenery additions required a fresh resource import before the final Weather run. Final logs include the existing two-ObjectDB-instance exit warning in some scene suites and the expected Workshop presentation-identity warning; neither is claimed fixed by this slice. There is no full physics-suite, release export, physical-controller matrix, monitor/DPI matrix or performance benchmark claim.

## Reproduction and identity

From the repository root, import resources first with the pinned engine, then run the test names recorded in `tests.json` using `--headless --path app --audio-driver Dummy --script res://tests/<name>.gd`.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --editor --import --quit
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --script ../docs/research/menu-investigations/UI-28-R3/capture.gd -- --core --out=C:/DEVELOPMENT/OpenRCsimulator/tmp/menu-r3-repro
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --script ../docs/research/menu-investigations/UI-28-R3/capture.gd -- --stress --out=C:/DEVELOPMENT/OpenRCsimulator/tmp/menu-r3-stress-repro
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --script ../docs/research/menu-investigations/UI-28-R3/audio_probe.gd
```

[Source identity](source-identity.json) records the relevant UI hashes and HEAD at evidence collection. Other tracks were active in the shared working tree; captures establish this menu composition rather than freezing unrelated scenery/vehicle work. The broader [redesign acceptance gates](../../../MENU-REDESIGN-PLAN.md#10-acceptance-and-completion) remain open.
