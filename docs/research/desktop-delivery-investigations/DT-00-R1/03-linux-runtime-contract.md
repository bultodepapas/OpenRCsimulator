# Linux Runtime and Device Contract

2026-10-07 · DT-00-R1 · Scope: current x86_64 export ABI, display backends, RC radio access, package choice.

## Question and method

What does the exported Linux app actually require at runtime, and would AppImage or Flatpak improve the present pilot path? I read the DT plan, export script/preset, current app input and save paths, Godot 4.7 Linux/controller/system/GDExtension docs, SDL’s Linux joystick guidance, Flatpak sandbox/convention docs, and AppImage concept/FUSE docs. I statically inspected the existing ignored `dist/linux/openrc-simulator.x86_64` with `file` and `readelf`, preserving the raw outputs and checksum in the [reproducible probe and JSON evidence](probes/). I did not launch it. Accessed 2026-10-07.

## Findings

| Question | Evidence | Consequence for this project |
| --- | --- | --- |
| What is exported now? | `Linux` preset is x86_64 with `embed_pck=true`; `app/export.sh` packages one `openrc-simulator.x86_64` into a ZIP and runs a headless trimmed-flight trace on it. | Keep the ZIP as the first portable candidate; existing test proves pack loading and flight logic, not a native desktop launch. |
| What ABI did the available binary show? | Ignored artifact `dist/linux/openrc-simulator.x86_64` is ELF64 x86_64, 75,960,800 bytes, timestamp 2026-10-05, SHA-256 `936f3234f81d87b4a455f05d8183f465569feae8b391bb8d038a1ff29ee8b363`. Its ELF ABI note contains Linux 5.15.0; dynamic symbol-version scan reaches GLIBC_2.28; direct `DT_NEEDED` entries are `librt`, `libpthread`, `libdl`, `libm`, `libc`, and the ELF loader. Raw `file`/`readelf` output is retained in the probe JSON. | The ABI note is metadata, not proof that Linux 5.15 is a hard minimum kernel. This ignored `dist/` binary has no verified build-commit provenance; re-probe a clean DT-08 artifact and boot-test the oldest target before setting support claims. ELF metadata also cannot enumerate every driver or library loaded later with `dlopen`. |
| What does Godot promise broadly? | Godot says official Linux binaries use its buildroot and can run across common distributions when built against an old enough base; its exported-project minimum is a Linux distribution released after 2018, but Godot warns that a project must run its own low-end tests ([feature list](https://docs.godotengine.org/en/4.7/about/list_of_features.html), [system requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html#desktop-or-laptop-pc-minimum)). | Engine guidance is a starting bound only. Publish an OS/kernel/glibc/GPU/backend matrix from the exact exported binary; do not advertise “all Linux”. |
| Which window stack is used? | Godot 4.7 says X11 remains the default because native Wayland support is still a work in progress; X11 apps can use Xwayland, and the display-server setting can fall back if unavailable ([Wayland/X11](https://docs.godotengine.org/en/4.7/tutorials/platform/linux/wayland_x11.html)). | Name the tested backend. Smoke-test X11 on Xwayland and native Wayland separately before claiming both, including fullscreen, focus, monitor change, and scaling. |
| Does SDL provide the window or sound layer? | Since Godot 4.5, SDL 3 is used for controller input on desktop Linux/macOS/Windows, not windowing or sound; specialized flight devices are less tested ([Godot controllers](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html)). Godot’s separate system feature list names PulseAudio or ALSA for Linux audio ([feature list](https://docs.godotengine.org/en/4.7/about/list_of_features.html)). | Test display backend and radio input as separate axes. A window smoke is not a radio smoke; SDL does not define fullscreen behavior. |
| What can block joystick hotplug? | Godot documents udev support as enabled by default in its builds and says without it hotplug is less reliable. SDL documents that permission errors on `/dev/input/event*` require device access/udev configuration ([Godot controller troubleshooting](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html), [SDL Linux joystick setup](https://wiki.libsdl.org/SDL3/README-linux)). | Test the real EdgeTX radio as an ordinary user: cold connect, launch connected, unplug/replug, calibration, and throttle-safe reconnect. Do not tell users to run the simulator as root or ship a broad `MODE=0666` rule. |
| What would AppImage solve? | AppImage is one executable file and bundles dependencies not reasonably expected on target systems, while still relying on some host basics such as the C library and graphics libraries ([concepts](https://docs.appimage.org/introduction/concepts.html)). AppImages require FUSE on common systems; fallback extraction is possible but costly ([FUSE guide](https://docs.appimage.org/user-guide/troubleshooting/fuse.html)). | It may reduce extraction friction, but does not erase ABI or graphics testing and adds FUSE/extraction failure modes. Adopt only after DT-01 shows a ZIP-specific pilot problem on a named distro. |
| What would Flatpak solve or complicate? | Flatpak isolates apps, overrides XDG data paths under `~/.var/app/<app-id>/`, and supports narrow `--device=input`; raw `--device=usb` is broader and applies to libusb-style access ([conventions](https://docs.flatpak.org/en/latest/conventions.html), [permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html)). | SDL joystick input likely needs the `input` permission, not raw USB, but confirm with the EdgeTX radio. `user://` paths move with Flatpak’s XDG root; migration of settings/calibration and one stable Flatpak ID become release requirements. |
| Is native-extension packaging already in scope? | File scan found no `.gdextension`, `.so`, or `.dylib` payloads under `app/`. Godot’s manifest selects native libraries by platform/architecture and exports their dependencies ([GDExtension manifest](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html)). | No extension library currently adds to the Linux runtime contract. If one is introduced, require the x86_64 library and its transitive dependencies in the manifest/package smoke. |

## Local audit and limits

| Inspected item | Observed in repository | Not established |
| --- | --- | --- |
| `app/export.sh`, `app/export_presets.cfg`, `app/tests/check_macos_export.py`, CI workflow | Release export runs on Ubuntu 24.04; Linux binary gets a headless flight trace. CI’s GUI captures run the source project under Xvfb; the release artifact has no native GUI startup check. | No fresh export was made for this investigation. The existing ignored `dist/` ELF cannot be tied to current source or release commit. |
| `app/project.godot`, `app/input/rc_input.gd`, `app/sim/flight_session.gd`, preferences | Compatibility renderer; `user://settings.cfg`, `user://rc_calibration.cfg`; radio is read through Godot joypad axes, and `rc_input.gd` identifies EdgeTX-related device names. | No Linux GUI, Wayland, actual USB radio, host permission, audio, or persistence smoke was run. |
| Static ELF probe | [Probe script](probes/linux-elf-static-probe.py) and [captured JSON](probes/linux-elf-static-probe.json) record `file`, ELF headers, program headers, dynamic section, notes, symbol versions, tool versions, permissions, modification time, and SHA-256. The probe invokes only `file` and `readelf`; it never executes the target. | Results describe that exact ignored artifact and host inspection tools. They do not prove GPU-driver availability, dynamically loaded X11/Wayland client libraries, SDL runtime modules, filesystem execution policy, performance, a hard kernel minimum, or distro compatibility. |

Godot, SDL, Flatpak, and AppImage primary pages were opened and read directly. The ELF probe was read-only; no export or app execution occurred. There is no user-hardware evidence in this report, and no distro or backend is marked as tested.

## Runtime questions DT-01 must freeze

The default non-Flatpak `user://` directory for this project is `~/.local/share/godot/app_userdata/OpenRC Simulator`; preferences and calibration are separate files in that directory. Flatpak overrides `XDG_DATA_HOME` to `~/.var/app/<app-id>/data`, so Godot’s data root moves under that sandbox. A Flatpak migration must import both files or document a deliberate settings reset; changing the Flatpak application ID again would create a second data home.

Before publishing a Linux minimum, repeat this static probe on the exact release hash. The included script records tool versions and full static command output without launching the target:

```sh
python3 docs/research/desktop-delivery-investigations/DT-00-R1/probes/linux-elf-static-probe.py dist/linux/openrc-simulator.x86_64 --output /tmp/openrc-linux-elf-probe.json
```

Record ELF class/machine/interpreter, raw ABI-note value, direct `DT_NEEDED` entries, highest required GLIBC symbol, permissions, tool versions, and checksum. The ABI note is not a supported-kernel promise; derive the oldest supported kernel from engine/runtime requirements and a boot test on the oldest intended machine. This probe does not resolve shared libraries or prove graphics, dynamically opened X11/Wayland, audio, or radio readiness. Never use a repository `dist/` file as the accepted candidate without matching its recorded build identity to the release commit.

The package alternatives solve different problems:

| Format | Current fit | Reconsider when |
| --- | --- | --- |
| x86_64 ZIP | Low-maintenance portable baseline; preserves the current single exported binary and checksum flow. | It fails a named user workflow after native testing. |
| AppImage | Convenient single-file launch; still uses host basics such as glibc/graphics and may fail when FUSE is absent. | DT-01 identifies a concrete distro/extraction friction and the pilot accepts the FUSE/extract fallback. |
| Flatpak | Managed runtime/update integration and sandboxing; requires explicit display/audio/input permissions and user-data migration. | A target distribution or managed deployment asks for it, and EdgeTX works with minimal permissions. |

For Flatpak, distinguish the actual control path: Godot uses SDL 3 for joystick input, while its X11/Wayland backends control the window. Start with `--device=input` for the radio and test it; raw `--device=usb` is for USB-bus access and is broader than this joypad path appears to need. Do not use `--device=all` as a convenience workaround. Record any portal/device-permission difference between desktop sessions.

## Recommendation for existing DT phases

Keep DT-00’s x86_64 ZIP/archive as the distribution baseline. Do not add AppImage or Flatpak for aesthetics alone. Use DT-01 to select the real target distros and hardware; use DT-02 to launch the exported artifact outside the checkout; extend DT-09d to meet the runtime contract below. Preserve the `Linux` preset name and current embedded-PCK layout. If a clean artifact repeats `GLIBC_2.28`, record it as observed symbol-version metadata and a candidate glibc dependency floor; record Linux 5.15.0 only as the raw ELF ABI tag. Test the oldest intended machine before setting support claims, especially any kernel minimum.

| DT-02/09d proof | Pass condition |
| --- | --- |
| Artifact and ABI | Fresh build identity and SHA-256 recorded; ELF machine/class/interpreter, ABI note, `NEEDED` entries, maximum GLIBC symbol, executable bit, and archive extraction permissions checked. Re-run on the final downloaded ZIP, not a source-tree binary. |
| Native launch | Clean user account; extract to a path with spaces; run from outside checkout; Home → Fly → Pause → End → Quit; no engine errors; `user://` settings and calibration survive restart and reinstall. |
| Display | Record distro/release, kernel, GPU/driver, compositor, Godot backend, resolution/DPI, and fullscreen behavior. Cover X11 and Xwayland; add native Wayland only when claimed. |
| Audio and session | Record ALSA/PulseAudio device selection, mute/volume behavior, sleep/wake, minimize/restore, and active-flight exit handling on the actual package. |
| Radio safety | Test actual EdgeTX radio without root: plug before launch, hotplug during Home and flight, disconnect/reconnect, axis mapping/calibration, and safe throttle arming. Record whether `input` event permissions or udev setup block access. |
| Package choice | Only prototype AppImage or Flatpak after a named target fails the ZIP path. For Flatpak, test minimal display/audio/input permissions, save-data migration, upgrade/uninstall persistence, and do not request raw USB or `device=all` unless the tested radio route requires it. |

## Primary sources

- Godot 4.7: [Linux export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_linux.html), [system requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html), [X11/Wayland](https://docs.godotengine.org/en/4.7/tutorials/platform/linux/wayland_x11.html), [controllers/SDL 3](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html), [GDExtension manifest](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html), [user-data paths](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html)
- [SDL 3 Linux joystick permissions](https://wiki.libsdl.org/SDL3/README-linux)
- Flatpak: [sandbox permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html), [runtime/data conventions](https://docs.flatpak.org/en/latest/conventions.html)
- AppImage: [concepts](https://docs.appimage.org/introduction/concepts.html), [FUSE troubleshooting](https://docs.appimage.org/user-guide/troubleshooting/fuse.html)
