# PRIMIS test host: Linux + Intel iGPU

Pool host **`primis`** is CT 405 `openrc-testlab`, an unprivileged Debian 13
container on an always-on Proxmox node. It runs two kinds of checked jobs:

- **Headless checks**, the same as the `linux` host. It is a second Linux host on
  different hardware.
- **Rendered checks on a real GPU.** Godot renders on an Intel UHD 630 (Mesa 25.0.7:
  Vulkan ANV, OpenGL iris) at 1920×1080 under a private headless Wayland
  compositor. It is the pool's only Linux host with a GPU.

Plan and evidence: [TQ-06](../plans/primis-intel-test-host.md). Queue contract:
[test queue guide](../../tools/testqueue/README.md#rendered-checks-on-a-gpu-host).
Node addresses, credentials and operations live in the private HomeLab
repository (`guests/primis/405-openrc-testlab`), never here.

## Use it from MCP

Headless, pinned to this host:

```text
sim_test_run: {"jobs":[{"script":"res://tests/test_math3d.gd","platform":"linux","host":"primis","require":["0 failed"]}]}
```

Rendered on the GPU: add `rendering_driver` (`vulkan` for Forward+, `opengl3`
for Compatibility). Any host advertising `graphics` qualifies; today only `primis`
does.

```text
sim_test_run: {"jobs":[{"script":"res://tests/test_x.gd","platform":"linux","rendering_driver":"vulkan","require":["0 failed"],"timeout":600}]}
```

- `sim_fleet` shows the host as `primis` with `"gpu": "intel-uhd630"`. Every host
  with a `gpu` field takes `rendering_driver` jobs.
- A rendered check **passes only if the engine log names the UHD 630**. A software
  renderer (`llvmpipe`, `lavapipe`, `softpipe`), another adapter or a missing device
  line makes it `INFRA_FAILED`. The job status records the reason under `gpu`.
- The import stage stays headless. Only the check renders. The check runs without
  X11 (`DISPLAY` unset) and with `--display-driver wayland`, so it also covers
  Wayland-only startup.
- A rendered check is a functional check. It is not performance evidence: the
  CPU is shared with other guests, the compositor is headless and no panel or
  vsync is involved.

## What to expect

| Item | Value |
| --- | --- |
| Slots | 1; a second job waits with `HOST_BUSY` |
| CPU / RAM | 4 cores (low priority), 3 GiB + 512 MiB swap. While a job runs, the node squeezes its other VMs to make room |
| Rendered scene size | Light and medium scenes pass (math/camera checks, `phoenix_real_render`, landscape import). **Heavy scenes do not fit:** the iGPU allocates from system RAM outside the CT limit. Flight scenes and `test_advanced_graphics_settings` with Vulkan and MSAA 8x exhausted it, and such a job now fails inside the CT. Run heavy rendered checks on a machine with more RAM or a dedicated GPU |
| Upload per attempt | Full snapshot, ~3.9 GB at ~11 MB/s, about 6 min, until TQ-05-F3.2. The pool includes this in placement, so unpinned headless work usually goes to `linux` |
| Import | About 20 s with the host's import cache; a cold import takes minutes |
| Engine | The pinned 4.8-beta2 official binary; the SHA-256 matches the pool config |

## When `primis` is offline or refuses work

| Symptom | Cause and action |
| --- | --- |
| `offline_reason: Bad permissions … openrc_testlab_ed25519` | The MCP uses Windows OpenSSH, which refuses a key readable by groups. Restrict the key's ACL to the user, SYSTEM and Administrators. |
| Offline, SSH timeout | CT stopped or node unreachable. The node's watchdog stops the CT when node memory, the egress filter or thin-pool space is at risk; a start guard also refuses to start it in those conditions. The operator restarts it on the node. |
| `INSUFFICIENT_MEMORY` while another job runs | Expected; one job at a time. |
| `INFRA_FAILED`, `import: timeout` | A cold import does not fit the default 90 s budget on 4 cores. The host's [import cache](../../tools/testqueue/README.md#remote-import-cache) fixes that once one job imports completely. Give the first job after an engine or asset change a larger `timeout` (for example 900). |
| Rendered job `INFRA_FAILED`, `gpu.reason` set | The GPU lane was not usable (compositor, render node, driver). Report it; do not retry on another host as a pass. |
| Rendered job `INFRA_FAILED` with `TeardownUnconfirmed`, or the host goes offline mid-job | The scene was too large for the node's RAM. The CT ran out of memory, or the node's watchdog stopped it. Use a lighter scene or another machine. After the CT restarts, the operator runs `testctl.py pool remote-reconcile --host primis JOB` to clear the quarantine. |
| `INSUFFICIENT_DISK` on `primis` | Failed jobs keep their source copy for 1 h; an hourly timer then removes it. `pool gc --host primis --execute` removes collected passing jobs. |
| Status stays `total: 0`; supervisor `ERROR: source changed during snapshot` | Another session edited the tree while it was being frozen. Pass `source` pointing to a clean worktree (for example `git worktree add --detach <dir> HEAD`). |
| `pool configuration changed` on recovery | The pool config was edited while that job was unfinished. Restore the previous config to recover it. |

## Host setup (operator)

The GPU lane is declared by `/srv/openrc/testpool/graphics.json` on the host:

```json
{"compositor": "weston-headless", "gpu": "intel-uhd630", "adapter": "UHD Graphics 630", "render_node": "/dev/dri/renderD128"}
```

The agent advertises `graphics` only while this file is valid, the render node
is readable and writable, and `weston` is installed. Remove the file to take the
host out of the GPU lane. The remote runtime (`remote_agent.py`, `processes.py`,
`common.py`) sits read-only under `/srv/openrc/testpool/runtime/tools/testqueue/`.
Redeploy it only when no job is running there.
