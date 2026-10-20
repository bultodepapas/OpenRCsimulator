# D6-JETI-00 — JETI correspondence and support audit

Recorded: 2026-10-19. Scope: source intake, PDF inspection and read-only review of the current input/UI code. The [JETI support plan](../../../plans/jeti-support.md) owns pending work and acceptance. No runtime, profile installation, flight test or email send was performed.

## Sources and provenance

Jakub Uhlík, R&D Specialist at JETI model s.r.o., replied on **2026-10-19 at 11:09:49 +02:00** (04:09:49 America/Bogota). Subject: `Re: Fwd: Fwd: JETI model Transmitters + OpenRC Simulator — Open-Source Integration Collaboration`. Gmail message/thread ID: `1a1536cc3495022d`; RFC Message-ID: `<b3012216-1cc6-4b5f-8843-23f7586f5ae6@jetimodel.cz>`.

The owner's existing reply is dated **2026-10-19 at 07:52:09 -07:00** (09:52:09 America/Bogota), Gmail message `1a154a608b3cacca`. It commits to investigating identification/switch support and proposes transmitter selection with a possible 3D representation, subject to permission. Both plain-text message bodies and their available basic headers are preserved in [correspondence.txt](correspondence.txt), including quoted context. Transport headers were omitted. This file is a decoded text export, not an original signed MIME message; no OpenPGP verification was performed. PGP key/signature attachments and the inline logo were outside this technical intake.

| Original technical attachment | Bytes | Purpose |
| --- | ---: | --- |
| [JETI Transmitters in OpenRCsimulator by bultodepapas.pdf](sources/JETI%20Transmitters%20in%20OpenRCsimulator%20by%20bultodepapas.pdf) | 556524 | Four-page manufacturer-contact test report with simulator screenshots, Windows control annotations and transmitter photo. |
| [controller_profiles.cfg](sources/controller_profiles.cfg) | 1140 | The simulator-generated V2 profile used in the report; retained as evidence, not installed as an active profile. |
| [USB descriptors.txt](sources/USB%20descriptors.txt) | 37079 | Complete supplied USB/HID dump, including device/host identifiers. |

All three were downloaded directly from the received message and retained byte-for-byte. [source-manifest.json](source-manifest.json) records filenames, sizes, SHA-256 hashes, message provenance, PDF inspection and reviewed source identities. Original attachments and correspondence are source material, not relicensed as simulator code or branded UI assets. The raw USB dump contains serial and host details; use redacted derivatives for future shareable hardware reports rather than copying those identifiers into compatibility tables.

## PDF coverage

PyMuPDF 1.28.2 opened the original PDF without encryption or a password. Native text character counts for pages 1–4 were **696, 1350, 194, 2**. [pdf-extracted.txt](pdf-extracted.txt) retains page boundaries and native text, including the nearly empty fourth page. All four rendered pages were inspected: pages 1–2 contain simulator screenshots, page 3 contains the critical annotated Windows control panel and page 4 is a transmitter photograph. Native extraction alone omits those annotations and the photo. No OCR or changes to the source PDF were needed; disposable renders live under ignored `tmp/pdfs/jeti-2026-10-19/`.

## Confirmed information and limits

| Observation | Source / meaning |
| --- | --- |
| USB HID works without a custom driver setup in the tester's environment. Basic axes, takeoff and airplane control worked. | Inbound email and PDF pp. 1–2; externally reported. Jakub explicitly says he is not an RC pilot. Exact simulator build, transmitter firmware and flight procedure were not supplied. |
| VID `0x0483` (1155), PID `0xA07C` (41084). | Email and USB dump agree. The vendor is STMicroelectronics; VID alone is insufficient for JETI detection. |
| Manufacturer `JETI model s.r.o.`; product `JETI DC/DS Mass Storage`; `bcdDevice=0x0200`. | USB device descriptor. The product name does not identify an exact DC/DS model; `bcdDevice` is not evidence of a particular transmitter firmware version. |
| HID and mass-storage interfaces coexist. | Configuration has two interfaces, class `0x03` HID and class `0x08` mass storage. The product name does not mean that joystick input is unavailable. No access to the mounted drive is needed for control. |
| Eight analog input value capabilities and button usages 1–32. | HID capabilities, usage page `0x09`, usage range `0x0001`–`0x0020`. The eight values are signed 8-bit, logical range -127…127. These are HID capabilities, not a measured Godot mapping. |
| Interrupt endpoint `bInterval=5 ms`, `wMaxPacketSize=12`. | Descriptor configuration only. Windows HID lists `InputReportByteLength=13`; retain both layer-specific values. Neither value measures end-to-end latency or proves callback spacing. |
| Tested/example radio is DC-16II, Mode 2. Four gimbal axes and four potentiometers are described. | PDF p. 2 and owner's reply. The p. 4 reference photo has a `DC-16` faceplate; do not use the photo as proof of revision-specific geometry or permission to use its likeness. |
| Radio name appears as `model s.r.o. JETI DC/DS Mass Storage` in the supplied profile and screenshot. | Profile association and PDF p. 1. The author reports a missing initial `J`; the evidence does not establish whether the loss originates in backend naming, composition or widget clipping. |
| Remapping works, but gamepad labels and existing assignments make it confusing and create conflicts. | PDF pp. 1–2. Jakub recommends a clean assignment set and a profile with actual transmitter control names. |
| Each switch uses three mutually exclusive position buttons. Two-position installations leave the middle unused. | PDF pp. 2–3. Installed switch types can vary by position; do not assume every switch is three-position. |
| Jakub offers profile creation/testing assistance in his free time. | Inbound email. This is not a delivery schedule or a blanket JETI endorsement/brand-asset permission. |

### Known mappings

The supplied CFG contains `kind="joystick"`, `preset="radio_custom"`, `throttle_mode="radio_absolute"`, schema version 2 and an empty `actions` dictionary. Its observed GUID is `0300567e830400007ca0000000000000`. All four channels have min=-1, center=0, max=1; only pitch is inverted. It does not contain a switch-group map or measured P5–P8 Godot mapping. An empty `actions` dictionary inherits runtime defaults.

| Channel | Godot axis in supplied CFG | Invert | Range |
| --- | ---: | --- | --- |
| Roll | 0 | false | Centered |
| Pitch | 1 | true | Centered |
| Throttle | 2 | false | Absolute |
| Yaw | 3 | false | Centered |

| Physical control | Windows button numbers | Evidence | Candidate Godot indices |
| --- | --- | --- | --- |
| Sa up / middle / down | 1 / 2 / 3 | PDF p. 2 text and p. 3 annotation | 0 / 1 / 2, **unverified** |
| Sb up / middle / down | 4 / 5 / 6 | PDF p. 3 annotation | 3 / 4 / 5, **unverified** |
| Sc–Sj and any spare controls | Not individually identified | Switch names are described, but a complete map is absent. | Capture required; do not extrapolate. |

Page 3 labels Windows X/Y as Axis 1/2, Z as Axis 4, X rotation as Axis 3, Y rotation as Potentiometer 5, Z rotation as Potentiometer 6, and the two sliders as Potentiometer 8/7. These are the author's physical-control annotations, not Godot axis numbers. Backend transformations and ordering must be observed before adding labels/defaults for the remaining analog controls.

## Current-source audit

Review base: commit `be97a75a90a3f1bf27fe2d49481c8c5d52446283`, with unrelated working-tree edits present. The manifest fingerprints the actual reviewed input/UI files. The existing graph index identified RC input/report seams but returned no controller-service/profile/action nodes; current source was read directly for those missing modules.

| Existing seam | Finding and implication |
| --- | --- |
| [controller_service.gd](../../../../app/input/controller_service.gd), `observed_devices()` / `profile_for_device()`; [rc_input.gd](../../../../app/input/rc_input.gd), `RADIO_NAMES` | Radio inference uses name tokens; JETI is absent. Known RC names receive radio defaults; the supplied device was saved as a custom joystick. Add conservative family evidence while preserving saved-profile precedence and low-throttle arming. |
| [controller_profile.gd](../../../../app/input/controller_profile.gd), `defaults()` / `validate()`; [controller_profile_store.gd](../../../../app/input/controller_profile_store.gd) | V2 radio defaults already use the supplied four-axis mapping. A new input subsystem is unnecessary. Extend preset/metadata handling deliberately and keep validated, transactional persistence. |
| [controller_actions.gd](../../../../app/input/controller_actions.gd), `default_bindings()` / `effective_bindings()` | Base actions start from gamepad buttons for every kind. Additional equipment defaults are gamepad-only, but that does not remove the inherited base map on radios. Explicit unbound overrides are required for a clean JETI starter. |
| [controller_prompts.gd](../../../../app/ui/controller_prompts.gd), `prompt()` / `_binding_text()` | Generic prompts still interpret low button indices as face/shoulder/D-pad controls. There is no JETI switch-position presentation path. Changing only the glyph family does not solve naming. |
| [controller_setup.gd](../../../../app/ui/controller_setup.gd), `_clear_action_binding()` / `_capture_binding()` | Individual Clear/Remap and Save/Cancel exist. Back and Pause cannot simply be cleared; a clean-start operation must preserve validated recovery. Device selectors already have full-label tooltips, so reproduce naming/clipping before prescribing a layout fix. |
| [smoke_aux.gd](../../../../app/input/smoke_aux.gd); RC AUX adapters | Shared AUX supports an axis or one button with hold/toggle modes. It has no three-button absolute-detent binding. Extend the shared contract for maintained positions without changing aircraft mechanics. |
| [input_report_data.gd](../../../../app/input/input_report_data.gd) and [F1 guide](../F1/README.md) | Existing diagnostics record identity, axis events and bounded button transitions. Reuse them for the missing native Godot mapping; event-only reports do not establish untouched startup switch states or physical latency. |

There is no demonstrated JETI-specific arming failure in the received material. Maintained switches nevertheless need targeted startup/capture/focus/reconnect tests. Current non-gamepad arming follows the low-throttle path; do not falsely describe the gamepad neutral-release gate as a reproduced radio defect.

## Additional primary references

Checked 2026-10-19:

- [JETI DC-16II product documentation](https://www.jetimodel.com/katalog/transmitter-duplex-dc-16-ii-silver-4.htm) confirms swappable/assignable two-/three-position switches and provides official manual downloads. It does not establish this unit's firmware or Godot button mapping. The linked English manual fetch timed out and was not used as inspected evidence.
- [Godot InputEventJoypadButton](https://docs.godotengine.org/en/stable/classes/class_inputeventjoypadbutton.html) defines the button identifier and pressed/released event state; [Input](https://docs.godotengine.org/en/stable/classes/class_input.html) documents identity/polling APIs. These moving stable references supplement the checked-in source; implementation must remain compatible with the repository's pinned Godot 4.7.2.

Validation of this intake: attachment byte counts matched Gmail metadata, all hashes were recorded, every PDF page was inspected, and 15 manifest file identities plus 24 local links in the new Markdown passed checks. Scoped documentation `git diff --check` and new-Markdown whitespace checks passed. The whole-tree diff check reported an unrelated EOF blank line in concurrent `app/tests/test_extra_installation.gd` work; that file was left untouched. Runtime and hardware tests were not run for this documentation/source-download task. Concurrent commits advanced HEAD during intake; the manifest's file hashes identify the reviewed source bytes independently of later repository activity.
