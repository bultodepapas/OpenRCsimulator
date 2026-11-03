# Shared M1 Mac: developer and agent access

Use this guide to connect from Linux, prepare a native task workspace, run Godot
checks and retrieve evidence. DT/PT owns this operating guide; the
[Apple plan](../plans/apple-silicon-performance.md) owns acceptance and the
[dated M1 evidence](../research/desktop-delivery-investigations/DT-MAC-02/README.md)
owns measurements. Access and tool paths below were rechecked on **2026-11-03**.

## 1. Connect from Linux

Run in Bash from `/home/bulto/OpenRCsimulator`:

```bash
M1_HOST=gius@100.79.151.42
M1_KEY="$PWD/tmp/apple-m1-access/id_ed25519"
test -r "$M1_KEY"
m1ssh() {
  ssh -i "$M1_KEY" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o UpdateHostKeys=no -o ConnectTimeout=15 \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 "$M1_HOST" "$@"
}
m1ssh 'uname -sm; sw_vers -productVersion; pmset -g batt; df -h /System/Volumes/Data'
```

The address is the Mac's **Tailscale** address. Expect `Darwin arm64`; commands
without `m1ssh` still execute on Linux. `m1ssh` with no command opens a native
shell from an interactive terminal. Recreate these shell variables/functions
in each new terminal; they are not repository configuration.

**Keep the existing SSH keys.** The user explicitly requested their retention.
The private key is mode 0600 inside ignored `tmp/apple-m1-access/`; the Mac user
is `gius`, with the corresponding public key in `~/.ssh/authorized_keys`.
Never include key contents or debug-bridge tokens in Git, reports or chat.
A new clone does not contain this credential: obtain authorized access to the
existing key through the owner, rather than generating a replacement or changing
the Mac's account configuration. Preserve normal SSH host-key verification.

## 2. Paths and installed tools

These are existing resources, not destinations to overwrite with a sync.

| Resource | Location / scope |
| --- | --- |
| Linux development checkout | `/home/bulto/OpenRCsimulator` |
| Original Mac checkout | `/Users/gius/Documents/OpenRCsimulator`; preserve the owner's work and preferences |
| Native engine | `/Users/gius/Documents/OpenRCsimulator/.tools/Godot_v4.8-beta1_macos.arm64/Godot.app/Contents/MacOS/Godot` |
| Retained research workspace | `/Users/gius/OpenRC-m1-check`; contains the tested tools, Python environment and historical copies, not an automatically current checkout |
| Tested Python | `/Users/gius/OpenRC-m1-check/.venv/bin/python`; native ARM64 Python 3.9.6, psutil 7.2.2 |
| Frozen comparison evidence | `/Users/gius/OpenRC-m1-check/tmp/apple-round5/` and `apple-round6/`; preserve role copies, imports, authoring inputs, fixtures, manifests, raw captures and analysis |
| Round-6 host helper | `/Users/gius/OpenRC-m1-check/tmp/apple-round6/host/macos_host_state-r4`; build receipt in the same directory |
| Round-6 final analysis | `/Users/gius/OpenRC-m1-check/tmp/apple-round6/analysis/long-final.json`; raw captures in `runs/metal-long-{baseline,candidate}-{1..3}/` |
| Retained development package | `/Users/gius/OpenRC-m1-package-check/tmp/round2-final-20261102/OpenRC-M1-round2.zip`; historical build, not the current release |
| New task workspaces | Use a fresh `/Users/gius/OpenRC-m1-work/<task-id>/` |
| Apple tools | `/usr/bin/xcrun`, `/usr/bin/caffeinate`; clang resolves under `/Library/Developer/CommandLineTools/` |

The tested engine reports `4.8.beta1.official.4d10419ca`. Recheck `--version`
and source/build hashes when identifying a new result. The inventory was
MacBookAir10,1, M1/8 GiB, macOS 27.0.1; these are dated facts, not permanent
assumptions. Use the existing
[native preflight](../../tools/godot/README.md#native-apple-silicon-setup-and-preflight-dt-mac-02a)
for a new hardware/tool receipt.

The Python above is sufficient for the exercised checked runner, psutil and
bridge. **Template correction requires Python 3.11+** through
`OPENRC_GODOT_PYTHON`; do not use the 3.9 environment for that step.
Source checks need no export templates. Reuse the pinned engine rather than
downloading another copy for each task.

## 3. Prepare a fresh source workspace

Coordinate one owner for the Mac's rendered app and performance measurements.
Other agents may research or edit on Linux. Check available space before copying
or importing: only about **1.6 GiB** was free at the last access check. Budget for
source, imports and outputs; insufficient headroom requires resolving storage
before a large transfer. Preserve the paths in the table above.

For a **committed source snapshot**, run from the Linux checkout after setting
the connection variables above:

```bash
M1_TASK="m1-$(date -u +%Y%m%dT%H%M%SZ)"
M1_WORK="/Users/gius/OpenRC-m1-work/$M1_TASK"
(
set -euo pipefail
mkdir "tmp/$M1_TASK"
git rev-parse HEAD > "tmp/$M1_TASK/source-head.txt"
git status --short > "tmp/$M1_TASK/source-status.txt"
m1ssh "mkdir -p /Users/gius/OpenRC-m1-work && mkdir '$M1_WORK'"
git archive --format=tar HEAD | m1ssh "tar -xf - -C '$M1_WORK'"
scp -i "$M1_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o UpdateHostKeys=no \
  "tmp/$M1_TASK/source-head.txt" "$M1_HOST:$M1_WORK/source-head.txt"
)
```

This transfers tracked committed contents without Linux `.godot`, `.tools`,
virtual environments, credentials or old captures. It excludes uncommitted and
untracked changes. For a dirty candidate, transfer only reviewed changes into
your new task directory and retain its diff and file hashes; identify the actual
bytes tested. A failed transfer leaves a partial directory: inspect it and use a
new task ID for a fresh attempt.

The archive is a source snapshot, **not a Git checkout**. The examples below use
an explicit engine path. `app/test.sh` calls the getter directly, needs a proper
Git checkout/cache and does not honor `OPENRC_GODOT` as an engine override;
follow the [full-suite contract](shared.md#full-app-suite) when that gate is needed.

## 4. Import and run focused native checks

In a **Mac shell**, enter the new task path printed/selected above, then:

```bash
cd '/Users/gius/OpenRC-m1-work/<task-id>'
M1_PY=/Users/gius/OpenRC-m1-check/.venv/bin/python
export OPENRC_GODOT=/Users/gius/Documents/OpenRCsimulator/.tools/Godot_v4.8-beta1_macos.arm64/Godot.app/Contents/MacOS/Godot
"$M1_PY" tools/godot/macos_preflight.py --godot "$OPENRC_GODOT"
"$M1_PY" tools/graphics/prepare_research.py --dest tmp/research
M1_APP="$PWD/tmp/research/app"
"$M1_PY" tools/godot/run_checked.py --out-dir tmp/checks --label m1-import \
  --timeout 600 -- "$OPENRC_GODOT" --headless --path "$M1_APP" \
  --audio-driver Dummy --import
"$M1_PY" tools/godot/run_checked.py --out-dir tmp/checks --label m1-frame-tests \
  --timeout 90 -- "$OPENRC_GODOT" --headless --path "$M1_APP" \
  --audio-driver Dummy --script res://tests/test_frame_samples.gd
```

Replace `<task-id>` with your task directory, and select the test appropriate to
your change. Proceed after the checked import passes; exit zero alone can hide
Godot script errors. Inspect each `report.json`, `ok`/`complete` and `engine.log`.
The runner creates unique run folders under `tmp/checks`.

The [research-copy tool](../../tools/graphics/README.md#isolated-mac-renderer-trials-dt-mac)
gives the project a unique name, separating macOS `user://` from the player's
preferences and radio calibration. `APPDATA`/bridge `--profile` alone does not
redirect macOS `~/Library`. The prepared copy changes project name and the
multi-bounce setting; identify it as a research configuration. Its sibling
`assets/` links to the source snapshot: freeze that source during a comparison.
Prepare a new copy for a new independent smoke; preserve existing profiles.

## 5. Inspect the visible app

From the same Mac task shell, with the variables above:

```bash
"$M1_PY" tools/debug/debugctl.py launch --app "$M1_APP" --resolution 2560x1600
# Set OPENRC_DEBUG_BRIDGE to the port printed by launch, in this Mac shell.
export OPENRC_DEBUG_BRIDGE='<printed-port>'
"$M1_PY" tools/debug/debugctl.py state
"$M1_PY" tools/debug/debugctl.py ui
"$M1_PY" tools/debug/debugctl.py logs --summary
"$M1_PY" tools/debug/debugctl.py stop
```

Substitute the actual port before running the commands. In separate SSH calls,
pass that same port explicitly on every bridge command. The bridge client runs
on the Mac alongside its local session/token; no public bridge port is needed.
Use the [bridge commands](../../tools/debug/README.md#quick-start) for controls,
screenshots, smoke, leaks and app navigation. Its `smoke --app <prepared-app>`
starts and owns a separate session; finish an existing session first. Use the
[graphics launcher](../../tools/graphics/README.md#isolated-mac-renderer-trials-dt-mac)
for explicit renderer comparisons; this bridge example is a functional check.

The owner must be logged into the Mac's graphical desktop, awake and unlocked.
For performance runs, leave the game visible and focused on the active desktop;
minimizing, switching Spaces/apps or locking can invalidate the flight. A
headless test proves software behavior, not native GPU performance.

## 6. Performance, evidence and cleanup

| Need | Existing tool / authoritative instructions |
| --- | --- |
| Native inventory, engine and display identity | [Mac preflight](../../tools/godot/README.md#native-apple-silicon-setup-and-preflight-dt-mac-02a) |
| CPU/RSS/system-memory samples with checked launch | [Resource sampler](../../tools/godot/README.md#process-ram-io-and-storage-pt1h-r4); use the pinned Python above |
| Optional thermal/power/pressure series and raw-clock join | [Host companion build and runner integration](../../tools/godot/README.md#optional-macos-host-state-companion-dt-mac-02e) |
| Repeatable active flight and health/hash receipts | [Sustained fixture](../../research/performance/README.md#repeatable-active-flight-dt-mac-03) |
| Long stream and explicit 30/1,800-second reducer minima | [Long capture contract](../../research/performance/README.md#long-continuous-captures-dt-mac-02b) |
| Completed three-pair M1 comparison and known limits | [Round-6 evidence](../research/desktop-delivery-investigations/DT-MAC-02/README.md#repeated-30-minute-metal-comparison) |
| Export/signature/package replay | [Release tools](../../tools/release/README.md); the retained old ZIP is not a new candidate |

For a new campaign, use new run paths and freeze source, linked assets, imports,
engine, helper, settings and workload identities. Round-5/6 scripts contain
absolute frozen paths and source pins: retain them as evidence, not mutable
launchers for a new build. Rebuild an optional helper in a new output directory
when its source/toolchain changes; keep its source and binary receipt together.

Use `pmset -g batt` before an AC comparison and retain sampled power/thermal
context throughout. `caffeinate -dis <runner-command>` gives a bounded,
command-lifetime hold; it does not maintain focus or prove drawing. Avoid
persistent power-setting changes. Run imports, transfers, profilers and other
GPU work outside measured intervals. Never suppress focus/drawability/clock gates
to accept a failed run; preserve the failure and collect a fresh complete run.

For this Mac, the user authorizes the built-in display instead of an external
1080p screen. The panel is 2560×1600; desktop logical size and Godot's reported
screen/viewport can differ. Record requested, reported, internal and drawable
dimensions separately; unknown drawable pixels stay unknown. This exception
does not change the repository's 1080p product priority. Uncapped throughput,
60 Hz pacing, observer overhead and final-package qualification are separate.

After measurement, retrieve only the relevant complete output directories. From
Linux, for the focused checks above:

```bash
scp -Cr -i "$M1_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o UpdateHostKeys=no \
  "$M1_HOST:$M1_WORK/tmp/checks" "tmp/$M1_TASK/"
```

For a performance run, copy its frame JSON **and all sidecars**, health receipt,
checked logs, resource/host attachments, manifests and analysis. Validate hashes
after transfer. Keep bulky evidence/images outside Git and link the dated result
from its owning evidence page. Clean only your identified disposable outputs
after retaining required evidence; never delete the shared workspaces, frozen
campaigns, original checkout, player's profile or SSH keys. Stop only the app,
helper and keep-awake processes owned by your task.

## Connection and launch failures

| Symptom | Next check |
| --- | --- |
| Timeout / unreachable | Retry the bounded SSH probe; check Linux `tailscale status` / `tailscale ping 100.79.151.42` if installed, and Mac awake/network/Tailscale state. Ask the owner to wake/reconnect only if access still fails. |
| Connection refused | Mac System Settings → General → Sharing → Remote Login, permitted user `gius`. Reuse the existing setup when enabled. |
| Permission denied | Check the selected key exists and its mode is 0600, `IdentitiesOnly=yes`, user `gius`, and Mac `authorized_keys` permissions. Preserve the key pair. |
| Host-key change | Verify the Mac's identity with the owner; preserve normal SSH trust checks instead of disabling them. |
| SSH works, GUI does not | Confirm an unlocked logged-in Aqua session and an available visible desktop. Use headless only for checks that do not require graphics. |
| Capture pauses or has no draw progress | Restore actual focus/visibility, inspect bridge state and collector reasons, then start a fresh capture. |
| Import/copy fails or storage is low | Inspect the checked log and `df -h`; retain partial evidence and resolve task-owned storage before retrying. |
| Getter/full suite fails in a snapshot | The archive has no `.git`; use the explicit native engine for focused commands or prepare a proper checkout for getter/full-suite workflows. |

Completion means the intended native command passed its own validation, exact
source/tool identities and required evidence are retained, and owned processes
are stopped. Connectivity, headless success or an old package alone is not a
new performance or release result.
