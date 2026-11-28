# PRIMIS Intel/Linux/iGPU test host

Owner: **TQ shared-host test admission**, steps **TQ-06-P0…P5**. Parents:
[agent-first fleet plan](mcp-agent-fleet.md) (TQ-05) and its
[resilience invariants](mcp-queue-resilience.md). Consumers:
[Linux support](linux-support-distribution.md) (DT-LNX) and
[automatic graphics](automatic-graphics.md). Operating contract:
[queue guide](../../tools/testqueue/README.md). Node operations, addresses and
credentials live in the private HomeLab repository, never here.

The [operating guide](../tools/primis-testlab.md#what-to-expect) lists the current
allocation and watchdog policy. The figures below describe the initial deployment.

**Status, 20 November 2026: P0 and P1.1–P1.3 done; P1.4 parity passed, soak
pending; P2.1–P2.2 spike passed (manual).** An independent review of the
deployment found egress spoofing, remote forwarding through the jump account and
a filter that failed open; all three are fixed. CT 405 `openrc-testlab` exists and
host `primis` is in the pool config. Owner decisions: D0 accepted; D1 *no
upgrade and no stopped guests*, so RAM is handled per burst (§3). Every R-plan
and TQ-05 invariant stays binding: no duplicated attempt, no foreign-process
kill, no unverified evidence passing, no contaminated performance claim.

A separate, stopped benchmark CT on megatron's UHD 630 serves VQ-07h
performance measurement outside the pool. This host is the pool's functional
Linux/iGPU lane; neither one replaces the other.

## 1. Why

The fleet has no Linux host with a GPU. The `linux` pool host is a KVM guest
without `/dev/dri`, so every Linux rendering observation so far is software
rendering, which the [Linux plan](linux-support-distribution.md) refuses as
hardware evidence. PRIMIS, an always-on Proxmox node, has an idle Intel UHD 630
iGPU. A container on it gives:

1. **Linux + Intel + Mesa rendering**: Compatibility on `iris` (OpenGL) and
   Forward+ on `ANV` (Vulkan), the "Intel + Mesa" row of the Linux GPU matrix.
2. **A Wayland-only/no-X11 launch gate**, the open item for the pinned beta's
   X11-fallback crash in the [Linux plan](linux-support-distribution.md).
3. **A second Linux pool host on a different physical parent** than `linux`,
   so one node outage does not remove Linux coverage (input to R5).
4. **A modest-hardware reference** for automatic preset recommendation:
   6-core 35 W desktop CPU plus a Gen9 iGPU, indicative only (§6).
5. **Disposable distribution containers** for DT-LNX package lifecycle and ABI
   checks (Debian, Ubuntu, Fedora) with the real GPU visible.

It adds no CPU diversity worth claiming: both Linux hosts are Skylake-derived
Intel cores (i5-9500T and i5-10500).

## 2. Node facts (read-only probe, 20 November 2026)

| Item | Observed |
| --- | --- |
| Hardware | HP ProDesk 600 G5 Mini, i5-9500T 6C/6T (AVX2, no AVX-512), 16 GB RAM, 256 GB NVMe |
| Hypervisor | Proxmox VE 9.2.4, kernel 7.0.14-4-pve |
| iGPU | UHD 630 (CFL GT2), `i915` loaded, `card1` (group `video`) and `renderD128` (group `render`); no guest uses it |
| RAM | **3.0 GB available**; Home Assistant VM 8 GB fixed, a 2 GB pilot VM running, the public telemetry CT, swap unused |
| Storage | Thin pool 141 GB at 26 %, already overcommitted by allocation; root 46 GB free; Debian 13 template present |
| Stability | 41 days uptime now; lifetime 64 unsafe shutdowns from earlier NVMe/PCIe freezes (mitigated, not closed); 38 correctable PCIe RxErr this boot |
| Reach | Remote site, Tailscale only (no subnet routes); DEVIL→node 14 ms direct, **~11 MB/s** SSH upload |

Consequences: RAM is the hard limit; a full ~3.9 GB snapshot transfer costs
about six minutes; the node also carries Home Assistant and the public
telemetry receiver, which have priority over tests.

The HomeLab node record has two standing gates that this plan must respect,
not bypass. First, a NO-GO for any guest holding unique work while the
NVMe/PCIe AER diagnosis is open. Second, a NO-GO whenever node `MemAvailable`
falls below 2.5 GiB. Today's 3.0 GB leaves no room for a 2–3 GiB container.
Cgroup limits do not isolate the node's known failure mode, a whole-host freeze
followed by a watchdog reset. A test CT holds no unique work, but its load lands
on the same node. It therefore proceeds only under an explicit owner exception
(D0) and after RAM is freed (D1).

## 3. Design

| Choice | Decision | Reason |
| --- | --- | --- |
| Guest type | **Unprivileged Debian 13 LXC**, one CT (`openrc-testlab`) | No fixed VM RAM reservation; the iGPU is shared through the render node. A VM would need full iGPU passthrough (GVT-d) with IOMMU and vfio, taking the GPU from the host for little gain. Docker adds nothing: the pool agent is plain Python plus the pinned Godot binary. |
| GPU | `dev0` passthrough of `renderD128` with the CT's `render` GID; add `card1` only if P2 proves it is required | Render-node-only access is the smallest privilege that lets Mesa render. |
| Display | `weston --backend=headless` with the GL renderer, 1920×1080 output; Godot `--display-driver wayland`, no Xwayland | Xvfb has no DRI, so OpenGL would silently fall back to llvmpipe. A Wayland-only session also exercises the no-X11 gate. |
| Software-rendering guard | A rendered job passes only when the engine's adapter line positively names the Intel device (`UHD Graphics 630` with `iris`/Mesa for OpenGL, the Intel device for Vulkan); `llvmpipe`, `lavapipe` or `softpipe` is a hard failure | Mesa falls back silently when the render node is unusable; software rendering must never pass as GPU evidence. |
| Resources | 4 cores, CPU weight 50, **3072 MiB + 2048 MiB swap**, rootfs 8 GiB, **40 GiB** pool/engine mount with `backup=0`, `onboot=0` | The node's own services win every contention; the thin pool is already overcommitted. Heavy rendered scenes failed GPU allocations (ENOMEM) at 2.5 GiB. |
| RAM per burst (D1), **plan v2** | Home Assistant: 7168 MiB maximum (−1 GiB), 5120 MiB balloon floor. Hermes pilot VM: ballooning on, 4096 MiB maximum, 2048 MiB floor. 3 GiB zstd zram ahead of the NVMe swap. A **burst governor** in the host watchdog inflates both balloons to their floors at once when CT 405 has a pool job, and holds the node ballooning target at 60 %. It returns to 80 % after 5 idle minutes. | The RRD history and the guests' own memory showed real use of ~3.3 GB in HA and ~1.1 GB in hermes; the rest was cache. Auto-ballooning reclaims only 100 MiB per 10 s, too slowly for a test burst, and the hermes VM had been switched to 4 GiB fixed. Verified: with CT 405 at 2.9–3.0 GB, node `MemAvailable` stayed ≥ 4.2 GB. Before plan v2 it dropped to 1.3 GB, and the watchdog stopped the CT. |
| Guards | A Proxmox hookscript refuses to start the CT unless node `MemAvailable` ≥ 3 GiB, the egress table is loaded and the thin pool is below 85 % data and 80 % metadata. A host watchdog stops the CT if `MemAvailable` stays under 1536 MiB for 15 s, if the egress table disappears or if thin data reaches 90 %. The watchdog also logs i915 GPU hangs. | Startup checks alone cannot protect the node during a run. |
| Network | Host-only bridge; host-side nftables NAT that allows Internet egress only. It drops spoofed source addresses, private, CGNAT/tailnet and reserved ranges, and all traffic to the node. The table stays loaded when its service stops, and its own sysctl enables forwarding. The jump account allows only local forwarding to the CT, enforced in `sshd` with `Match User` as well as in the key options. | On the site LAN, the CT could reach Home Assistant. Unlike in-CT rules (the telemetry CT pattern), host rules cannot be removed by root inside the CT. See D2. |
| Access | DEVIL reaches the CT through a **dedicated restricted jump account** on the node (key-only, no shell, forwarding permitted only to the CT's SSH port), with a dedicated key. SSH aliases `openrc-primis-jump` and `openrc-primis` pin both host keys and use `BatchMode`. The CT user is non-root and holds only that public key. | No new tailnet identity, no subnet route, and test runs do not depend on the node's root key. The CT stores no tokens, passwords or private keys. |
| Placement | Pool host `primis`, platform `linux`, `transfer_bytes_per_second` set to the measured 11 MB/s. Today's agent advertises only `headless`; GPU capabilities arrive with P2.4. | The ordinary completion estimate makes it an overflow host for Linux and portable checks, and jobs can pin `host: primis`. |

## 4. Steps

### P0: gates and a one-day spike, before any pool or queue work

| ID | Work | Proof/status |
| --- | --- | --- |
| TQ-06-P0.1 | Owner decisions D0 (stability exception) and D1 (RAM). Record the stability baseline: unsafe shutdowns, PCIe RxErr, uptime and thin-pool use. | **Done 20 Nov:** D0 yes; D1 no upgrade, burst strategy instead. Baseline: 64 unsafe shutdowns, 38 RxErr this boot, 41 days uptime, thin pool 26 % (HomeLab CT 405 record) |
| TQ-06-P0.2 | Measure peak memory for a cold remote import plus checks. The host samples CT memory, CT swap, node `MemAvailable` and zram every second during the first pool batch. | **Done 20 Nov.** The cold import fills the 2560 MiB CT limit (peak 2541 MiB) and swaps up to 526 MiB, which zram absorbed at a 216 MiB peak. At a 75 % ballooning target, node `MemAvailable` dipped to **1795 MiB for about 60 s**, below the 2.5 GiB floor, because auto-ballooning reclaims only 100 MiB per 10 s. At **65 %** the headroom is reserved in advance: the next cold run's minimum was **4248 MiB**, with the HA VM at about 6.1 GiB and 2.2 GB available inside it. |
| TQ-06-P0.3 | GPU spike in the CT with only the render node shared. | **Done 20 Nov.** Vulkan: `Intel(R) UHD Graphics 630 (CFL GT2)`, Mesa 25.0.7 ANV, API 1.4.305. OpenGL: iris 4.6. weston 14 headless with the GL renderer needs no card node or seat. Godot 4.8-beta2 rendered a 3D test scene at 1920×1080 in both Forward+ and Compatibility with `--display-driver wayland` and no X11 (`DISPLAY` unset), without crashing. Peak RSS 407 MB (Vulkan) and 280 MB (OpenGL). |

### P1: provision the container and enroll it as a headless pool host

| ID | Work | Proof/status |
| --- | --- | --- |
| TQ-06-P1.1 | Create the CT per §3 (Debian 13, unprivileged, `onboot=0`), the host-only bridge and the host egress rules. Document it in the HomeLab guest record with its configuration and rollback. | **Done 20 Nov.** From inside the CT, Internet is reachable; the node UI, the LAN gateway, the node's SSH and its tailnet address are refused. The jump account refuses a shell, and refuses any forward except to the CT. |
| TQ-06-P1.2 | Install Python 3, the pinned Godot Linux binary with its SHA-256, and the pool runtime; add the SSH aliases on DEVIL. | **Done 20 Nov:** Python 3.13.5; official engine SHA-256 equals the pool pin; runtime from `a271ea782` (same as `linux`); agent `probe` OK. The key's ACL is limited to the user, SYSTEM and Administrators, because the MCP's Windows OpenSSH rejects inherited group read access. `sim_fleet` lists `primis` online. |
| TQ-06-P1.3 | Add host `primis` to the pool config. Edit only with no unfinished receipts, because every receipt binds the whole config's digest. Add a weekly host-side `pct fstrim`. | **Done 20 Nov** (no in-flight receipts; backup `config.json.bak.20261120T-primis`): `pool hosts` shows `primis` online and idle. `fstrim` timer pending |
| TQ-06-P1.4 | Acceptance: a checked headless batch with `host: primis` passes, and the same scripts pass on `linux`; then a 2-hour soak of repeated portable checks. | **Parity done 20 Nov.** Snapshot of `50a142903` from a clean worktree; batch 1 pinned `test_math3d` and `test_camera_math` to both hosts with identical outcomes. `math3d` passed both, `camera_math` printed 21/21 passed on both but missed a wrong marker in the manifest. Batch 2 on `primis` with the correct marker: **PASSED**. Node unsafe shutdowns 64 and RxErr 38, unchanged. **Soak pending.** |
| TQ-06-P1.5 | Placement: one slot (R5 physical-parent identity is still unimplemented). The honest measured transfer rate goes into the existing completion estimate, so `primis` wins only when it really finishes sooner (typically when `linux` is busy) or when a job pins it. No separate transfer mechanism is built here; that would duplicate F3.2. After F3.2, measure warm transfer again. | Decision records show the transfer and load components for each placement |

### P2: Intel iGPU rendering lane

| ID | Work | Proof/status |
| --- | --- | --- |
| TQ-06-P2.1 | Install distribution Mesa, Vulkan loader and tools, and weston; verify inside the CT that `vulkaninfo` and `eglinfo` on the surfaceless/GBM platform report the UHD 630, not a software device. | Device and driver versions recorded |
| TQ-06-P2.2 | Manual rendered smoke under weston headless at 1920×1080: Compatibility (`opengl3`) and Forward+ (`vulkan`), Home → Fly → Home, screenshot through the debug bridge. | Engine adapter lines naming Intel; screenshots reviewed then discarded (not committed) |
| TQ-06-P2.3 | Wayland-only gate: start without any X11 server or `DISPLAY`. Record whether the pinned beta crashes in X11 fallback and which explicit display-driver option avoids it. | Result handed to DT-LNX as evidence for its Wayland gate |
| TQ-06-P2.4 | **Implemented 20 Nov.** Contract: [queue guide](../../tools/testqueue/README.md#rendered-checks-on-a-gpu-host); fixtures: `tools/testqueue/test_graphics_lane.py`. The original requirement follows. **New queue feature**, not part of enrollment. Today the remote agent refuses non-headless jobs and hardcodes `--headless` (`remote_agent.py` checked-options validation and launch argv). Add a **rendered** job class on remote hosts: declared `workload: rendered`, a host capability match, a per-job compositor started and torn down by the agent, an exclusive slot, and the software-rendering guard from §3. Unknown workloads stay headless-only. Coordinate with TQ-05-F5.1 and F4.2. | Fixtures: rendered job refused on a host without the capability; llvmpipe line fails the job; compositor never outlives the job |
| TQ-06-P2.5 | MCP: `sim_test_run`/`sim_test_launch` jobs accept `rendering_driver`, which implies `workload: graphics`. The agent probe advertises `graphics` and `gpu:<id>`. Agent guide: [PRIMIS test host](../tools/primis-testlab.md). | **Implemented 20 Nov.** Native acceptance through MCP is below in P2.6 |
| TQ-06-P2.6 | Native acceptance: one rendered job each for `vulkan` and `opengl3` through MCP on `primis`. | **Done 20 Nov.** `tq06-gpu-mcp-20261120f` ran through a fresh MCP server and returned **PASSED**. The `test_math3d` check used Vulkan ("Using Device #0: Intel - Intel(R) UHD Graphics 630 (CFL GT2)") and `test_camera_math` used OpenGL ("OpenGL API 4.6 … Mesa 25.0.7 … UHD Graphics 630"); collection re-derived both lines from the logs. Other sessions' rendered jobs also passed (`phoenix_real_render.gd` ×3, `test_landscape_import.gd` ×2). **Limit:** heavy rendered scenes do not fit this node. The iGPU allocates from system RAM outside the CT limit. `test_advanced_graphics_settings` (Vulkan, MSAA 8x) needed about 3 GB in the CT, 1.6 GB of GPU memory and 2 GB of swap, until the watchdog stopped the CT. `phoenix_native_flight_render.gd` timed out or hit ENOMEM. With CT swap at 512 MiB, an oversized job now fails inside the CT instead of pressing the node. |
| TQ-06-P2.7 | Remote retention for failed jobs: `pool gc` removes only PASSED jobs. An hourly timer in the CT (`openrc-prune-failed-sources`) drops `source/` and `input.tar` of FINISHED non-PASSED jobs older than 1 h and keeps all evidence. | **Done 20 Nov:** the first run freed 31.4 GB. Fold into TQ-05/R8 retention when that lands |

### P3: distribution containers for Linux packaging

| ID | Work | Proof/status |
| --- | --- | --- |
| TQ-06-P3.1 | Scripted, disposable CTs from Debian 13, Ubuntu 24.04 LTS and a current Fedora template, sharing the render node, created for one DT-LNX check and destroyed afterwards. Never more than one alive alongside `openrc-testlab`. | Create/run/destroy log; node RAM never below the P0 floor |
| TQ-06-P3.2 | Run DT-LNX lifecycle and ABI checks for the tar/AppImage (extract mode)/`.deb`/`.rpm` payloads as an unprivileged user, plus a GPU launch smoke under weston. | Evidence filed with DT-LNX; results are container evidence, not desktop qualification |

### P4: indicative modest-hardware measurements

| ID | Work | Proof/status |
| --- | --- | --- |
| TQ-06-P4.1 | Fixed scenes and presets at 1920×1080 under weston headless, with the node quiet (no other test load, pilot VM stopped when the owner allows) and guest load recorded before and after. Feeds automatic-graphics preset recommendation as an indicative Intel Gen9 data point. | Report labelled **indicative**: shared host, headless compositor, no real display or vsync |

### P5: operations

| ID | Work | Proof/status |
| --- | --- | --- |
| TQ-06-P5.1 | Kill switch: draining `primis` in the pool config and stopping the CT has no effect on other hosts or node services. Abort rule: any new unsafe shutdown or a sharp RxErr rise during test load removes the host until the owner reviews it. | Documented drain/stop drill run once |
| TQ-06-P5.2 | After P1 and P2 hold for two weeks, the owner decides on `onboot=1`. | Owner decision recorded |

## 5. Sequencing

P0 (D0, D1, measurement, spike) → P1 → P2.1–P2.3 (manual, no queue code) →
P2.4–P2.5 (queue code, after TQ-05-F1.1 and F5.1) → P3/P4. P1.5's restriction
lifts only after F3.2. If the P0.3 spike fails or D0 is refused, stop at P0;
the fallback is a manual GPU smoke on a bare-metal Linux machine with a real
display.

## 6. Limits

- Results are **container evidence on a shared hypervisor**. They establish no
  Linux desktop qualification, which still needs a native display session,
  input devices and lifecycle checks per the [Linux plan](linux-support-distribution.md).
- The kernel is Proxmox's, not a distribution kernel; only Mesa and userland
  vary per container.
- Performance numbers are never 1080p qualification: the CPU is shared with
  other guests, the compositor is headless and nothing is presented to a panel.
- The node's earlier freeze history makes it best-effort. It never becomes the
  only host for a required platform.

## 7. Decisions needed

| ID | Question | Recommendation |
| --- | --- | --- |
| D0 (P0.1) | Accept test load on a node whose HomeLab AER/stability gate is still open? | **Owner: yes** (20 Nov), limited to a stateless, `onboot=0` test CT with the P5.1 abort rule. |
| D1 (P0.1) | How to free RAM for a 2–3 GiB CT on a node with 3 GB available? | **Owner: no upgrade, work with what exists; restarts allowed; HA may lose 1 GiB.** Implemented as RAM plan v2 (§3): Home Assistant and hermes balloon to floors only during test bursts, under the host governor. Both VMs were restarted once (HA down 83 s). |
| D2 (P1.1) | Host-only bridge with host NAT, or the simpler telemetry-CT pattern (site LAN plus in-CT rules)? | **Decided: host-only bridge.** The CT runs repository code and dependencies, and on the LAN it could reach Home Assistant. |
| D3 (P1.2) | Restricted jump account on the node, or a dedicated identity on the main tailnet for the CT (never the public-receiver tailnet)? | **Decided: restricted jump account** with a dedicated key. |
| D4 (P5.2) | Autostart the CT? | Not before two clean weeks. |
