# DT-LNX-10 — Snapdragon X and DGX Spark feasibility

**Research snapshot: 2026-11-01.** Source inspection and primary-source research only. No ARM export, target access, installation, benchmark or device qualification was performed. Inspected working tree at HEAD `46b004c7b469448c29ef96168da4f03cee2c6d23`, with unrelated uncommitted work, including the Godot 4.8-beta2 migration. This is not a clean build identity. The [Linux execution plan](../../../plans/linux-support-distribution.md) owns status; DT-LNX-10 remains pending.

## Recommendation

Develop one generic Linux ARM64 preview with the existing GDScript reference physics and Compatibility renderer. **The user has neither target machine and wants an experimental native executable, without an emulator requirement for players.** Use native hosted ARM64 CI for initial software evidence; optional local emulation can supplement it. Target hardware is required for target qualification, not for producing an experimental candidate. If physical access later becomes available to both machines, use **NVIDIA DGX Spark first**, then qualify a **specific Snapdragon X laptop**. This ordering is an engineering inference from vendor Linux enablement, not measured OpenRC performance. Keep Snapdragon X/X Plus/X Elite (X1) and X2 as separate hardware entries. “NVIDIA Spark” here means Linux DGX Spark/GB10, not a Windows product.

The same application payload is a reasonable goal, conditional on ELF/ABI/ISA compatibility and tests on both hosts. GPU drivers remain host components; do not bundle NVIDIA or Mesa drivers. Share code and assets, but keep per-host graphics, input, audio, numerical and thermal evidence. No kernel or aircraft-law fork is needed merely to add an architecture.

## Platform evidence

| Target | Verified upstream facts | OpenRC consequence / unmeasured work |
| --- | --- | --- |
| Snapdragon X1 laptops | Ubuntu 26.04 LTS includes the Secure Boot mechanism for supported Snapdragon X Elite machines [S1]. Ubuntu 26.10 adds named X Elite/Plus devices and records remaining hardware issues [S2]. | Choose the exact laptop, SoC, firmware and OS image before promising support. A supported CPU family does not establish every laptop's peripherals or GPU path. |
| Snapdragon firmware | The September 2026 Ubuntu Concept announcement still describes firmware that cannot yet be redistributed and extraction from an existing Windows installation [S3]. | Preserve the vendor update/recovery route during an eventual installation. Do not infer that a generic ARM64 ISO alone supplies every device dependency. No OS installation is authorized or performed by this research. |
| Snapdragon graphics | Mesa documents Freedreno for OpenGL and Turnip for Vulkan, and directs readers to the device table for exact chip coverage [S4]. | Start with Compatibility; verify hardware rendering on the exact Adreno GPU. Record Mesa/kernel/firmware versions and reject software-rendered results as GPU qualification. Vulkan/Forward+ is a later independent test. |
| Snapdragon X2 | Ubuntu 26.10 includes early support for selected X2 laptops [S2]; Canonical's September announcement targets official X2 support for 2027 [S5]. | Early enablement and the future certified offering are different milestones. Do not extend X1 results to X2. |
| DGX Spark | GB10 combines a 20-core Arm CPU and Blackwell GPU [S6]. NVIDIA documents Ubuntu 24.04-derived DGX OS, desktop mode and OpenGL/Vulkan acceleration [S7]. | A suitable first native ARM64 build/test candidate, with a vendor-maintained graphics stack. Launch locally with a display for latency and graphics acceptance. |
| Spark software maintenance | October release notes list DGX OS 7.6.0, driver 580.178.04 and kernel 7.0.0-1019; they include display-memory changes and OpenGL/Vulkan/X11 fixes [S8]. | Inventory the installed versions. The porting guide's older 6.11 description is not a current kernel pin. Partner GB10 products can have a different update schedule. |
| Spark memory | NVIDIA documents unified memory and limitations in GPU-memory reporting [S9]. | Record system memory pressure as well as GPU telemetry. Measure OpenRC alone first; concurrent AI workloads require separate contention measurements. |

The release notes list a suspend/Wi-Fi issue on some Snapdragon machines and an X2 keyboard regression (the section heading and body differ; the body specifies X2) [S2]. These are test leads, not proof that every X1 laptop has those faults. Spark also lists an HDMI monitor wake issue [S9]. Validate focus, sleep/resume and controller recovery on the actual machines.

## Repository readiness and remaining changes

Godot's official 4.8-beta2 archive offers Linux ARM64, and its Linux exporter supports `arm64` [S10, S11]. Reuse those free upstream binaries/templates. The current project remains GDScript with float64 simulation and 240 Hz ticks; Compatibility is the default. The configured 720p viewport does not change the 1080p acceptance priority.

| Existing source | Finding / work required |
| --- | --- |
| [Editor getter](../../../../app/get-godot.sh), [template getter](../../../../app/get-templates.sh), [presets](../../../../app/export_presets.cfg) | Add Linux ARM64 host acquisition where needed, verified ARM64 template membership and an ARM64 export preset. Cross-exporting does not require an ARM editor, but native development/CI needs a supported getter. |
| [Native stage](../../../../app/sim/native_stage.gd), [NK lock](../../../../research/native-kernel/toolchain-lock.json) | NK-3 explicitly accepts Linux x86_64 only. The initial preview must use `gdscript_reference`; do not relabel an x86 library or bypass receipt checks. |
| [Ground native guide](../../../../research/rc-monster-truck/native/README.md) | Existing Windows/Linux native builds are x86_64. Exclude unsupported libraries/descriptors from the ARM preview and test reference behavior for each included vehicle route. |
| [Exporter](../../../../app/export.sh), [release manifest](../../../../tools/release/manifest.py) | Existing flow couples native qualification and three fixed deliverables. Extend architecture/schema handling and package tests deliberately; do not weaken existing x86 gates. |
| [Release tooling](../../../../tools/release/README.md) | ELF inspection already supports `--architecture arm64`; this is static tooling, not ARM application evidence. |
| [NVIDIA graphics guide](../../../../tools/graphics/native/README.md) | Current DLSS/DLAA/Reflex integration is a Windows package. GB10 hardware does not make it a Linux ARM64 feature. Keep it outside initial scope. |

CUDA, Tensor Cores and Qualcomm's NPU do not automatically accelerate the existing CPU simulation. No CUDA/NPU rewrite is proposed. Advertised AI throughput cannot establish frame rate, 240 Hz tick cost or deterministic replay.

## Development without either target machine

**Clarification researched 2026-11-01:** build/test infrastructure and the player's runtime are independent. An ARM64 executable exported on x86, or tested through QEMU, still runs directly on a compatible ARM64 Linux host. Its package must contain the ARM64 Godot runtime and resources, with no x86 executable, emulator launcher or incompatible native extension. Using GDScript reference physics does not mean emulating an x86 CPU.

| Environment | What it establishes | What it cannot establish |
| --- | --- | --- |
| Existing x86 Linux development host or ordinary x86 Proxmox guest | Cross-export using the official ARM64 template; package structure, checksums and ELF architecture/dependency inspection | Execution of the ARM executable without an emulator |
| QEMU ARM64 guest on an Intel/AMD host | Emulated ARM Linux startup, dependency loading and selected functional checks | Native CPU timing, target numerical qualification, Adreno/GB10 graphics, USB-radio latency or 1080p performance |
| Native ARM64 GitHub-hosted runner | Actual ARM instruction execution, package smoke, relevant physics tests and replay checks on that runner | Snapdragon/GB10-specific behavior, native desktop GPU acceptance or radio qualification |
| Future tester with a named target | Final downloaded-package behavior, actual graphics/input/audio and sustained performance | Blanket support for every Snapdragon model or Linux distribution |

### Proxmox option

The Proxmox host architecture/version has not been inspected. If it uses Intel/AMD, KVM does not turn it into an ARM processor. QEMU's TCG can emulate ARM64; KVM acceleration of an ARM64 guest requires an ARM64 host [S12]. Proxmox now has an official ARM64 host edition [S13], but installing it is not a way to make Intel/AMD execute ARM instructions natively, and its server validation is not proof of Snapdragon/DGX Spark guest graphics support.

A practical optional setup is an ordinary Ubuntu x86_64 VM in the existing Proxmox installation, running `qemu-system-aarch64` with an ARM64 Ubuntu image and the generic `virt` machine. That inner guest uses CPU emulation; nested KVM is not required for TCG. Direct Proxmox management is another possibility, conditional on the installed version and QEMU packages; the current command schema exposes `aarch64` [S14]. No ready-to-run Proxmox configuration is claimed without that inventory.

QEMU explicitly describes `virt` as a generic virtual platform, not a model of real hardware [S15]. Do not call it a Snapdragon emulator or a virtual DGX Spark. An ordinary x86 VM with a passed-through NVIDIA GPU remains x86; passthrough does not reproduce GB10's Arm CPU and integrated-memory platform. Start with headless checks; a software-rendered UI smoke may detect basic presentation failures but is not graphics qualification.

### Recommended primary path: native ARM CI

GitHub currently provides `ubuntu-24.04-arm` standard runners for public and private repositories. Its public-repository table specifies 4 CPUs, 16 GB RAM and 14 GB SSD, with free standard-runner usage [S16]. Private-repository billing/allowances must be checked for the account; no paid runner is required or provisioned by this proposal.

Use a separate experimental ARM job, pinned checkout/actions/tool hashes and a recorded runner-image identity. The runner label itself is a moving image, not a reproducible OS lock. Prefer downloading and testing the exact ARM package produced by the export job; preserve its SHA-256 before and after transfer. Keep native-library work outside this first candidate. The limited runner disk also requires checking checkout, import-cache and artifact space before choosing the full-suite layout.

The experimental gate is: valid AArch64 payload and dependencies; successful execution on native ARM CI; relevant completed software checks; reference-backend identity; no unsupported extensions; and explicit unresolved hardware coverage. Use the desktop package's headless mode for smoke without stripping graphical resources into a server-only export. Where feasible add software-rendered UI checks, clearly labeled. CI failures remain failures; the experimental label does not waive them.

After those gates, the proposed description is **“Experimental Linux ARM64; native ARM CI tested; Snapdragon X and DGX Spark hardware unverified.”** This permits an honestly scoped experimental delivery without claiming that either target already works. GPU/driver failures may still be discovered by testers. Publication remains a separate action. No VM, CI job or package was created during this research.

## Proposed full target-qualification sequence

1. **Freeze two named hosts.** Snapdragon laptop model and full SoC identifier; Spark Founders Edition or exact partner model. Record RAM, firmware, distribution, kernel, display server, driver/API, actual resolution and power mode. Ubuntu 26.04 LTS is a candidate for an already-enabled X1 model; use 26.10 only when its device support is needed and tested. Start Spark with its supported DGX OS stack.
2. **Produce a reference preview.** Pin the current official engine/template hashes; export ARM64 without incompatible extensions. Audit every ELF and dependency floor, preserve executable permissions, and test the final extracted package. No claim of a universal glibc floor precedes inspection.
3. **Prove software behavior on both native hosts.** Import/parse, relevant physics tests, aircraft loading, completed traces and exact replay within the recorded source/config/backend identity. Cross-architecture exactness is a separate measurement; never regenerate goldens or relax tolerances merely to admit ARM.
4. **Measure at 1920×1080.** Use the existing [performance workflow](../../../../research/performance/README.md) and [debug bridge](../../../../tools/debug/README.md). Record frame-time distribution, hitches, physics tick cost, memory and sustained thermals. Preserve 240 Hz; retain the existing 500 microsecond physics budget as a gate. A 60 fps presentation target is proposed, not achieved. Test higher resolutions afterward; 720p is fallback evidence only.
5. **Exercise real devices and lifecycle.** Radio USB calibration, arming, reconnect, focus loss, audio, fullscreen/windowed switching, sleep/resume, settings and file import/export. Use local display/input first; remote streaming adds independent latency. Test the included vehicle routes separately.
6. **Port native evaluators only after the reference baseline.** Extend build locks, descriptors, receipts and architecture admission for both native modules. Preserve float64 and controlled floating-point flags; avoid `-march=native`. Re-run parity, trajectories, replay and actual timing on each CPU. Native CI supplies software coverage, not GPU/controller qualification.

Preview packaging and native ARM CI are a moderate change; full target/native-evaluator qualification is a larger NK/SF/DT effort. Lack of target access does not block the experimental path above. Calendar estimates for target qualification remain unjustified without an inventory and access. Public support must distinguish built, native-smoke-tested and qualified packages, as defined by the parent plan.

## Primary sources

All accessed 2026-11-01. Live documentation may change; versions above describe this research snapshot, not permanent install instructions.

- **S1:** [Ubuntu ARM summer 2026 update](https://discourse.ubuntu.com/t/ubuntu-on-arm-summer-26-update/84872), July 6, 2026.
- **S2:** [Ubuntu 26.10 release notes](https://documentation.ubuntu.com/release-notes/26.10/), Snapdragon enablement and known issues.
- **S3:** [Ubuntu Concept 26.10 Snapdragon Edition](https://discourse.ubuntu.com/t/ubuntu-concept-26-10-snapdragon-edition/88518), September 29, 2026; maintainer announcement, not later user reports.
- **S4:** [Mesa Freedreno/Turnip documentation](https://docs.mesa3d.org/drivers/freedreno.html). Its introductory GPU ranges are not an exhaustive current device list; no exact Adreno API version is inferred here.
- **S5:** [Canonical/Qualcomm X2 announcement](https://canonical.com/blog/ubuntu-coming-soon-to-qualcomm-snapdragon-x2-series-platforms), September 23, 2026.
- **S6:** [DGX Spark hardware](https://docs.nvidia.com/dgx/dgx-spark/hardware.html).
- **S7:** [DGX Spark software stack](https://docs.nvidia.com/dgx/dgx-spark-porting-guide/latest/porting/software-requirements.html).
- **S8:** [DGX Spark release notes](https://docs.nvidia.com/dgx/dgx-spark/release-notes.html), October 2026 update.
- **S9:** [DGX Spark known issues](https://docs.nvidia.com/dgx/dgx-spark/known-issues.html).
- **S10:** [Official Godot 4.8-beta2 downloads](https://godotengine.org/download/archive/4.8-beta2/).
- **S11:** [Godot Linux export architectures](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_linux.html).
- **S12:** [Ubuntu Server: ARM64 VMs with QEMU](https://ubuntu.com/server/docs/how-to/virtualisation/qemu/#boot-arm64-virtual-machines-on-qemu), distinguishes emulation on x86 from KVM on ARM64.
- **S13:** [Proxmox official ARM64 host support](https://proxmox.com/en/about/company-details/press-releases/proxmox-virtual-environment-launches-official-arm64-support), August 5, 2026.
- **S14:** [Proxmox generated qm command schema](https://github.com/proxmox/pve-docs/blob/master/generated/qm.1-synopsis.adoc), architecture selection; moving upstream source, not an installed-host inventory.
- **S15:** [QEMU generic Arm virt platform](https://www.qemu.org/docs/master/system/arm/virt.html).
- **S16:** [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), current architecture, capacity and public-repository usage terms.
