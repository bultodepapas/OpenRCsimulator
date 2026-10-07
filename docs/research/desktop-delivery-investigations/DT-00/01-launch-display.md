# DT-00 — Launch and display

2026-10-07 · **Investigated; recommendations, not implemented behavior.**

## Code audit

Paths are relative to the repository root. Hashes and engine probe results are in [audit-snapshot.json](audit-snapshot.json).

| Evidence | Finding | Consequence |
| --- | --- | --- |
| `app/project.godot` | 1280×720 design size; no explicit fullscreen mode, icon or UI scaling policy | First-launch fullscreen and desktop identity need implementation |
| `app/app_root.gd`, `wants_direct_flight()` | Any argument after `--` enters direct flight; that route bypasses preferences | Adding `-- --safe-display` naively would skip Home; recovery must have an explicit routing contract |
| `app/app_state/preferences.gd` | Validated language, hint and aircraft; future schemas are read-only | Extend this store with its owner; a second settings file would create conflicting authority |
| `app/app_root.gd`, `_notification()` | Focus loss opens pause; returning does not automatically resume | Fullscreen transitions must preserve the session's pause reasons |
| `docs/MENU-PLAN.md` | UI-07 owns preferences; UI-09a owns scale; UI-09b owns window/fullscreen with confirmation | Desktop delivery specifies exported behavior and acceptance; the menu track implements the shared UI |
| Existing [display investigation](../../menu-investigations/18-pantalla-ventana-plataformas.md) | Earlier proposal starts windowed; native multi-monitor/focus behavior remains untested | The user's fullscreen request changes the proposed first-launch default; coordinate that change explicitly |

Reproduce the static audit:

```bash
git status --short
rg -n 'window/|physics_ticks|max_physics|renderer/' app/project.godot
rg -n 'wants_direct_flight|user_args|preferences|FOCUS_OUT' app/app_root.gd
rg -n 'SCHEMA|DEFAULTS|writable' app/app_state/preferences.gd
"$(app/get-godot.sh)" --version
"$(app/get-godot.sh)" --help
```

## Engine facts and their limits

Godot's ordinary fullscreen covers one display without switching its video mode. macOS uses a separate Space. Exclusive fullscreen has different platform behavior, including equivalence to ordinary fullscreen on Wayland; it is unnecessary for the requested default. Wayland does not offer normal application-controlled window positioning. Read back the effective mode and geometry rather than assuming a request succeeded. [DisplayServer](https://docs.godotengine.org/en/stable/classes/class_displayserver.html).

Window dimensions, 2D scale and 3D resolution are distinct. The design size does not change the physical monitor resolution. UI scaling should preserve layout and text rather than stretch the whole low-resolution scene. [Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html). `Window.content_scale_factor` supports UI scaling; platform close requests also need an intentional application lifecycle policy. [Window](https://docs.godotengine.org/en/stable/classes/class_window.html).

The installed CLI advertises `--windowed`, `--fullscreen`, `--resolution` and `--screen` as runtime options. Put engine options before `--`; tokens after it belong to the app. The engine's `--recovery-mode` is an **editor** option, not an exported-game recovery solution. [Command-line reference](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html), locally checked in the snapshot.

## Recommended launch contract

These are product proposals derived from the audit, not Godot guarantees.

1. An ordinary first launch opens Home in non-exclusive fullscreen on the launch display. Subsequent launches honor the last confirmed window mode. An explicit windowed CLI request takes precedence and does not rewrite saved preferences.
2. Apply the mode early in the interactive bootstrap, while Home is being prepared, with bounded readback after the first drawable frame. Measure the startup transition on each OS; do not promise zero flicker from an API call. Failure falls back to an onscreen window.
3. Preserve deterministic automation. `--trace`, captures, inspectors and frame measurements retain their current routing and avoid preferences; their mode/size come from explicit engine flags. Do not set unconditional project-wide fullscreen before this distinction exists.
4. Use the menu track's validated store and display controller. First-run fullscreen is a default, not a settings trial; later changes use Apply → Keep/Revert. Proposed timeout: 15 seconds on a monotonic clock, including while flight is paused. Save only after confirmation. On timeout, cancellation or process interruption, restore the last confirmed state on the next launch; test an interrupted first trial too.
5. F11 is the proposed fullscreen/window toggle, subject to macOS function-key conflicts; the menu must offer the same operation. Escape keeps its existing pause/menu meaning. Radio axes never change mode or navigate confirmation controls.
6. Recovery uses the verified engine `--windowed --resolution 1280x720` contract, with application preference overrides respecting it. Supply an easy recovery launcher/help entry in each package. If a separate reset action is later needed, limit it to display keys and keep calibration, language and aircraft selection.
7. Remember only valid display preferences. Revalidate a monitor at every launch; indices are not durable identities. Restore window size within current usable bounds, reposition where supported, and let Wayland's compositor place it. Never reopen an inaccessible offscreen window after undocking.
8. Treat transition focus notifications separately from the confirmation decision. Focus loss still pauses flight; avoid reverting immediately due to the app's own fullscreen transition. Keep/Revert remains reachable after switching applications. Resume requires pilot action.

## Acceptance probes

Exercise first launch, saved windowed/fullscreen, malformed/future/unwritable settings, lost display, mixed DPI, Alt+Tab/Cmd+Tab, sleep/wake, minimize/restore, close while a trace is active, and termination during a settings trial. Test both Home and flight, plus a connected radio.

Layout coverage: 1280×720, 1920×1080, 2560×1440, 3840×2160, 16:10 and ultrawide; Windows 100/125/150/200% scaling, macOS Retina and an external display, Linux X11 and native Wayland including fractional scale. Each claimed combination needs an actual result; untested combinations remain explicit gaps.

Headless tests can prove route precedence, persistence, fallback decisions and timer logic. Captures can prove layout. Xvfb without a real window manager cannot prove native fullscreen, DPI, focus or input-to-display latency. No native display test was executed in DT-00.
