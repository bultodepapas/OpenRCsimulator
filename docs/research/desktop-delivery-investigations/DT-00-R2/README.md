# DT-00-R2 — Godot on Apple Silicon: twelve investigations

2026-10-07 · **Research complete; native Mac launch, performance and pilot acceptance remain pending.**

Supports [Desktop Delivery Plan, revision 3](../../../DESKTOP-DELIVERY-PLAN.md). This is a new Mac-focused round after [DT-00-R1](../DT-00-R1/README.md), not a claim that the application was optimized or certified on M1. Documents are English by repository convention.

## Findings that change the plan

| Investigation | New finding or sharper contract | Plan integration |
| --- | --- | --- |
| [01 — Renderer and Metal](01-renderer-metal-opengl.md) | Current Mac configuration is Compatibility/OpenGL; native Metal requires a different rendering method, and the logger omits actual driver name | DT-10 identifies runtime backend; DT-11d allows a controlled Mobile/Metal experiment |
| [02 — Retina, fill cost and memory](02-retina-fillrate-memory.md) | MSAA enum 2 is 4×; full M1 Air panel pixels are 4.44× the configured 720p base; unified memory still needs a measured budget | DT-01a/10b freeze an 8 GB floor and actual backing dimensions; DT-11c separates AA, scale and readability |
| [03 — ProMotion and pacing](03-promotion-frame-pacing.md) | Panel capability, chosen refresh, VSync and actual presentation differ; Compatibility does not provide distinct adaptive/mailbox behavior | DT-10a separates clocks; 60 Hz is the initial target, high-refresh acceptance remains separate |
| [04 — ARM64 and native dependencies](04-arm64-native-dependencies.md) | Existing bundle declares ARM64 macOS 13, despite lower Mach-O load-command minimum; native dependencies need per-architecture coverage | DT-01a freezes the OS floor; DT-02a verifies native execution; DT-09c checks full bundle |
| [05 — Spaces, Retina and Mac input](05-spaces-retina-input.md) | Cached fullscreen state can precede AppKit completion; Godot's mobile safe-area API is not a Mac notch contract | DT-04/05 require usable-window evidence, native transitions, notched/external displays and menu escape |
| [06 — Signing, quarantine and upgrades](06-signing-quarantine-updates.md) | Existing checker requires ad-hoc flags and is structural, not cryptographic; Developer ID needs an explicit validation path | DT-08/09c preserve structural checks and verify the final trusted artifact natively |
| [07 — Thermal and energy soak](07-apple-silicon-thermal-energy-soak.md) | Current frame logging ends at 300 s and quits; it cannot provide a continuous 30-minute soak | DT-10b adds bounded measurement; separate power/thermal/idle conditions |
| [08 — USB radio on macOS](08-macos-usb-radio-access.md) | Accessory authorization, OS discovery, SDL identity and saved calibration are separate failure layers | DT-05b tests actual radio/cable/hub and user-visible recovery without speculative permission requests |
| [09 — CoreAudio and sleep](09-coreaudio-device-sleep-recovery.md) | Engine handles default-output change internally; generator skips do not measure endpoint/Bluetooth failures | DT-05a tests audible output and safe resume with physical hardware |
| [10 — Native CI qualification](10-native-ci-qualification.md) | Linux-specific downloader/timeouts block a simple Mac runner switch; headless, GUI and physical-owner evidence differ | DT-02a introduces a small pinned platform adapter and final-package tests |
| [11 — ARM64 numerical physics](11-arm64-physics-numerics.md) | Float64 state already has a portable design, but Mac math agreement and sustained 240 Hz cost remain unproved | DT-02b preserves H9 tolerances; DT-10b retains the existing physics budget |
| [12 — Diagnostics and symbols](12-macos-diagnostics-symbols.md) | Native crash decoding needs exact UUID-matched symbols; the current release pipeline has no demonstrated symbol-retention coverage | DT-08b records diagnostic identity and symbol gaps; DT-12 rehearses failure reporting |

## Qualification order

1. Freeze a clean package, exact Godot version, physical M1 Air-class 8 GB baseline, OS/build and newer-Mac comparison. macOS 13 is the initial Apple Silicon floor candidate from current docs/bundle metadata, not a tested support promise.
2. Prove ARM64 source regression and final-package execution, including existing numerical budgets. Keep CI VM capability separate from a real display, radio and fanless laptop.
3. Accept fullscreen/Spaces/Retina/input, close/sleep and audio. Then qualify final Developer ID/notarized distribution and sustained flight on the same bytes.
4. Optimize a measured bottleneck. Compare graphics settings first; treat Mobile/Metal as a bounded candidate requiring visual/numerical and thermal evidence, not an assumed upgrade.

The six new implementation steps are DT-01a, DT-02a, DT-02b, DT-08b, DT-10b and DT-11d. Existing DT steps retain responsibility for UI, signing, input and release acceptance. The plan remains the status authority.

## Executed evidence and limitations

| Evidence | Scope |
| --- | --- |
| [Mac artifact probe](probes/macos_macho_probe.py), [results](probes/macos_macho_probe.json) | Read-only ZIP/plist/Mach-O metadata on Linux; architecture, OS floors, UUIDs, dependency/signature flags for one existing export. Source provenance is unknown; no native execution or cryptographic verification |
| [Checker-contract probe](probes/checker_contract_probe.py), [results](probes/checker-contract-results.json) | Actual current Python checker accepts synthetic ad-hoc metadata and rejects non-ad-hoc flags. Neither fixture contains a valid executable/signature; this proves checker scope/policy, not a macOS trust bypass |
| [Audit snapshot](audit-snapshot.json) | Hashes of inspected working-tree files and probe scripts; concurrent changes remain identifiable |
| [Source inventory](sources.json) | Deduplicated cited primary references, mapped to reports; no automated claim that all remote links will remain available |
| [Documentation validator](probes/validate_documents.py), [results](validation.json) | Twelve reports, local targets, step uniqueness, registry revision, Python/JSON syntax and whitespace |

Reproduce the checker probe from the repository root with `python3 docs/research/desktop-delivery-investigations/DT-00-R2/probes/checker_contract_probe.py`. The Mac artifact report documents its separate probe. Neither needs or runs macOS. Never interpret these probes as Finder/Gatekeeper, GPU, CoreAudio or USB acceptance.

No full app suite, export, installer, Mac job, signing operation or performance benchmark ran in this round. Proposed M1 targets, RAM/pixel arithmetic and renderer comparisons are labeled as such. The native slipstream experiment stays outside production; research here neither adopts it nor changes physics. The shared application's landscape/input/physics files were inspected without editing them.

Refresh the documentation snapshot/inventory and checks with `python3 docs/research/desktop-delivery-investigations/DT-00-R2/probes/validate_documents.py`. It does not rerun the recorded probes or change application files.

Sources accessed 2026-10-07: official Godot 4.7 documentation and pinned 4.7.2 source, Apple documentation/specifications, GitHub runner references, Clang and SDL/EdgeTX where relevant. Apple DocC JSON was used when HTML required JavaScript. Repository-authored research/probes retain the repository license; cited material retains its upstream terms. No third-party source/assets were imported.
