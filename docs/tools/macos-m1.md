# Shared M1 Macs: developer and agent access

Use this guide to select a host, prepare a native task workspace, run Godot
checks and retrieve evidence. DT/PT owns this operating guide; the
[Apple plan](../plans/apple-silicon-performance.md) owns acceptance and the
[dated M1 evidence](../research/desktop-delivery-investigations/DT-MAC-02/README.md)
owns measurements. Historical inventory below was checked on **2026-11-03**;
the Windows-through-Linux route and reusable beta2 engine were rechecked on
**2026-11-06**.

**2026-11-12 follow-up:** strict direct Windows SSH to ANGELA_AIR succeeded. The
[isolated M1 experiment record](../research/native-kernel/apple-silicon-m1-experiments-2026-11-12.md)
binds current host/engine identities, a checked math test, standalone compilation
and the SDK C++ header-path issue. The old checkout remains absent; preserve the
reused engine and new frozen evidence. This does not qualify a native evaluator
or renew the historical rendered campaign. The separate `angel` mDNS alias did
not resolve in that session.

## Select the Mac first

These are separate machines, accounts and SSH identities. Sections 1–6 below
describe **ANGELA_AIR**, the original remote Mac; do not run their hard-coded
`/Users/gius` paths on ANGEL.

| Host | Verified route | Account | Client credential |
| --- | --- | --- | --- |
| ANGELA_AIR, original remote M1 | Tailscale `100.79.151.42` | `gius` | Original Linux key or Windows `~/.ssh/openrc_m1_ed25519`; section 1 |
| ANGEL, Gius's second test M1 | DEVIL LAN, `ssh angel` / `ssh angel-lan`; `Gs-MacBook-Air.local`, observed `192.168.80.27` | `g` | Existing Windows `~/.ssh/devil_automation_ed25519` |

### ANGEL: Windows access and native setup

Rechecked **2026-11-07** from DEVIL. The existing aliases use
`IdentitiesOnly yes`, `StrictHostKeyChecking yes`, agent forwarding disabled
and `~/.ssh/angel_known_hosts`. No key was regenerated, copied to the Mac or
added to Git. Retain the private key in `C:\Users\bulto\.ssh`; preserve the
existing public authorization and known-host entries.

- Client public fingerprint: `SHA256:1SbbL8B31iPgP1JvON/j81ioZQmpYcQLWR1H+6hezoA`.
- Server ED25519 fingerprint: `SHA256:P5MpdEMrTX7R9/QYfcms6d1WfaxkCruIH5sG0Bq6ts4`.
  Initial acceptance on November 6 was TOFU, not out-of-band verification.
- Live host: MacBookAir10,1, Apple M1, 8 GiB, native `arm64`, macOS
  `27.0` / `26A5425a`; on AC, about 154 GiB free before setup.

From Windows PowerShell:

```powershell
ssh -o BatchMode=yes -o ConnectTimeout=15 -o UpdateHostKeys=no angel `
  'id -un; hostname; uname -sm; sw_vers -productVersion; pmset -g batt'
```

| Setup resource | ANGEL path / status |
| --- | --- |
| Reusable native Python | `/Users/g/OpenRC-m1-tools/venv-3.12.16/bin/python`; CPython 3.12.16 ARM64, psutil 7.2.2 |
| Bootstrap provenance | uv 0.13.7 official ARM64 archive and SHA-256 retained under `/Users/g/OpenRC-m1-tools/bootstrap-20261107/`; user-only installation, shell profiles unchanged |
| Initial frozen source | `/Users/g/OpenRC-m1-work/angel-setup-20261107`; commit `997e212784dbf873a7b054ddbbc68e7905495adf` in `source-head.txt` |
| Native editor | `.tools/Godot_v4.8-beta2_macos.arm64/Godot.app/Contents/MacOS/Godot` inside that workspace; `4.8.beta2.official.cafc17a19` |
| Editor provenance | Official ZIP checked against the getter's SHA-512, manually extracted with its signed ARM64 bundle intact; exact version, `codesign --verify --deep --strict` and bundle-file manifest checked. After Apple tools were installed, the unmodified getter validated/reused that cache; path retained in `tmp/verified-engine.txt` |
| Apple developer tools | Owner completed the `xcode-select --install` dialog. Verified Git `2.54.0 (Apple Git-157)`, Apple clang `21.0.0`, active `/Library/Developer/CommandLineTools` and its `MacOSX.sdk`; native compilation itself is untested |
| Local receipts | `D:\OpenRCsimulator-evidence\angel-setup-20261107` on DEVIL, outside Git |

Use a new `/Users/g/OpenRC-m1-work/<task-id>/` for each future candidate.
On Windows, create the pinned source archive with `git archive --output=...`
and transfer it with `scp`; avoid a binary archive pipeline through Windows
PowerShell. Apply section 3's attribute/space checks, preserve the source commit,
and compare archive hashes before extraction. Reuse the verified engine above
for focused checked runs rather than downloading another copy.

The initial source archive is 7,338,792,960 bytes, SHA-256
`cb7561ed9d4f51eecacf8fb4f8bfd5793052a9e1169cba909af28bf38eeb4952`.
Checked native setup on November 7:

| Check | Retained result under the Mac workspace |
| --- | --- |
| Inventory after Apple tools installation | `tmp/macos-preflight/macos-preflight-20261107T113255Z-56a9f9c9f71942e7a68285986b1ac9aa.json`; complete, native ARM64 Python, no Rosetta |
| Authoring identities and isolated copy | 11 Workshop descriptors current; `tmp/research/research-preparation.json`, complete. Git metadata is null because preparation preceded local `git init`; `source-head.txt` identifies the archived source, which has no historical Git commit |
| Checked import | `tmp/checks/angel-import-48mvom4m/`; `ok` and `complete`, zero errors, eight OBJ ambient-material/PBR warnings |
| Focused frame collector test | `tmp/checks/angel-frame-tests-0xlpode_/`; `ok` and `complete`, **161 checks, zero failures**, zero errors/warnings |

To repeat that focused check, enter `ssh angel` and run in the Mac shell:

```bash
cd /Users/g/OpenRC-m1-work/angel-setup-20261107 || exit 1
M1_PY=/Users/g/OpenRC-m1-tools/venv-3.12.16/bin/python
OPENRC_GODOT="$(cat tmp/verified-engine.txt)"
"$M1_PY" tools/godot/run_checked.py --out-dir tmp/checks \
  --label angel-frame-tests --timeout 90 --require-text '0 failed' -- \
  "$OPENRC_GODOT" --headless --path tmp/research/app --audio-driver Dummy \
  --script res://tests/test_frame_samples.gd
```

The checked runner creates a fresh result directory. Use the explicit managed
Python; it was reinstalled at the same pin after Apple tools became available
to complete its library install-name setup. These are headless source checks;
the full suite, native compilation, GUI, GPU/performance and release gates
still need their own evidence. No task-owned Godot process remains running.
The original Mac's built-in-display exception below does not apply to ANGEL;
use the repository's 1920×1080 priority for future rendered qualification.

Bootstrap references checked November 7: [uv installation](https://docs.astral.sh/uv/getting-started/installation/),
[managed Python versions](https://docs.astral.sh/uv/concepts/python-versions/)
and [Apple Command Line Tools](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools).

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

From the Windows development checkout, the existing SSH alias `vscode-megatron`
reaches that Linux checkout. Access was verified on **2026-11-06** through this
route; the key is on Linux, not in the Windows or WSL checkout. Run the Linux
commands above after connecting with `ssh vscode-megatron`, or pass a quoted
remote command through that host. Keep both hops' host-key verification enabled.
Do not copy the private key merely to make Windows access direct.
The [Linux SSH guide](linux-ssh.md) owns the dedicated `openrc-linux` alias and
current connection-readiness procedure; historical access does not prove availability.

For direct access from Windows, the owner can instead enroll a dedicated Windows
public key on the Mac. The 2026-11-06 task created
`$env:USERPROFILE\.ssh\openrc_m1_ed25519` at the owner's request; its private
half stays on Windows. Use the command below only after the public half has been
added to the Mac account's existing `~/.ssh/authorized_keys`. Preserve the Linux
key and all existing authorized entries. A reachable SSH server does not prove
that the new key is authorized. This direct route was verified on 2026-11-06
after owner enrollment and used for the current native checks.

For a Windows client that does not yet trust this host, first obtain its ED25519
host fingerprint from Terminal on the Mac, or through an already verified SSH
session. This is the server's identity, separate from the login key above:

```bash
ssh-keygen -l -E sha256 -f /etc/ssh/ssh_host_ed25519_key.pub
```

Then make one interactive connection from Windows. Compare its displayed
fingerprint with the trusted value before answering `yes`; stop on a mismatch.
Confirmation adds the host key to the Windows user's `~/.ssh/known_hosts`.
These options follow the [OpenSSH host-key policy](https://man.openbsd.org/ssh_config#StrictHostKeyChecking).

```powershell
ssh -i "$env:USERPROFILE/.ssh/openrc_m1_ed25519" -o IdentitiesOnly=yes `
  -o HostKeyAlgorithms=ssh-ed25519 -o StrictHostKeyChecking=ask `
  -o BatchMode=no -o UpdateHostKeys=no -o ConnectTimeout=15 `
  gius@100.79.151.42 'uname -sm'
```

After both host trust and login-key enrollment are established, use the strict
noninteractive command for automation:

```powershell
ssh -i "$env:USERPROFILE/.ssh/openrc_m1_ed25519" -o IdentitiesOnly=yes `
  -o BatchMode=yes -o StrictHostKeyChecking=yes -o UpdateHostKeys=no `
  -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 `
  gius@100.79.151.42 'uname -sm; sw_vers -productVersion; pmset -g batt'
```

Retain normal host-key verification, including the initial trust decision for
a new client. Do not disable checking or replace an existing host-key entry to
work around a mismatch. Once enrollment is verified, this route needs no Linux
gateway. Keep private keys outside source snapshots, Git and evidence bundles.

**Keep the existing SSH keys.** The user explicitly requested their retention.
The original Linux private key is mode 0600 inside ignored `tmp/apple-m1-access/`; the Mac user
is `gius`, with the corresponding public key in `~/.ssh/authorized_keys`.
Never include key contents or debug-bridge tokens in Git, reports or chat.
A new clone does not contain this credential: obtain authorized access to the
existing key through the owner, rather than generating a replacement or changing
the Mac's account configuration. Preserve normal SSH host-key verification.

## 2. Paths and installed tools

The final access check found SSH and the Python environment available, but the
original checkout/engine and Mac campaign copies below had been removed since
the earlier check. Do not treat historical paths as installed tools. The Linux
campaign evidence remains available. Check existence before reuse.

| Resource | Location / scope |
| --- | --- |
| Linux development checkout | `/home/bulto/OpenRCsimulator` |
| Original Mac checkout | `/Users/gius/Documents/OpenRCsimulator`; **absent at final check**, historical location |
| Historical native engine | `/Users/gius/Documents/OpenRCsimulator/.tools/Godot_v4.8-beta1_macos.arm64/Godot.app/Contents/MacOS/Godot`; **absent**, acquire through the existing getter in section 4 |
| Remaining research workspace | `/Users/gius/OpenRC-m1-check`; Python and partial source remain, but its `assets` link targets the missing original checkout. Use a fresh complete source snapshot for game checks |
| Tested Python | `/Users/gius/OpenRC-m1-check/.venv/bin/python`; native ARM64 Python 3.9.6, psutil 7.2.2 |
| Retained comparison evidence on Linux | `/home/bulto/OpenRCsimulator/tmp/apple-round5/` and `apple-round6/`; preserve raw captures, analysis and manifests. Mac copies formerly under `/Users/gius/OpenRC-m1-check/tmp/` are absent |
| Historical host helper | `/Users/gius/OpenRC-m1-check/tmp/apple-round6/host/macos_host_state-r4`; **absent**. Linux `tmp/apple-round6/host/` retains the build evidence; build a new helper for a new campaign |
| Round-6 final analysis on Linux | `/home/bulto/OpenRCsimulator/tmp/apple-round6/analysis/long-final.json`; raw captures in sibling `metal-long-{baseline,candidate}-{1..3}/` directories |
| Historical development package | `/Users/gius/OpenRC-m1-package-check/tmp/round2-final-20261102/OpenRC-M1-round2.zip`; **absent at final check**, not a current release |
| New task workspaces | Use a fresh `/Users/gius/OpenRC-m1-work/<task-id>/` |
| Verified reusable beta2 engine (2026-11-06) | `/Users/gius/OpenRC-m1-work/m1-20261105T153146Z/.tools/Godot_v4.8-beta2_macos.arm64/Godot.app/Contents/MacOS/Godot`; `4.8.beta2.official.cafc17a19`. Recheck the bundle/hash before reuse; preserve the owning campaign. |
| Apple tools | `/usr/bin/xcrun`, `/usr/bin/caffeinate`; clang resolves under `/Library/Developer/CommandLineTools/` |

Historical campaigns used `4.8.beta1.official.4d10419ca`; the current reusable
engine above reports `4.8.beta2.official.cafc17a19`. Recheck `--version`
and source/build hashes when identifying a new result. The historical inventory was
MacBookAir10,1, M1/8 GiB, macOS 27.0.1; these are dated facts, not permanent
assumptions. Use the existing
[native preflight](../../tools/godot/README.md#native-apple-silicon-setup-and-preflight-dt-mac-02a)
for a new hardware/tool receipt.

The Python above is sufficient for the exercised checked runner, psutil and
bridge. **Template correction requires Python 3.11+** through
`OPENRC_GODOT_PYTHON`; do not use the 3.9 environment for that step.
Source checks need no export templates. Once acquired, reuse a validated pinned
engine cache across tasks rather than downloading another copy each time.

## 3. Prepare a fresh source workspace

Coordinate one owner for the Mac's rendered app and performance measurements.
Other agents may research or edit on Linux. Check available space before copying
or importing. Resolve the intended commit once; use that exact ID for both the
identity receipt and transferred archive. Inspect the tracked payload size:

```bash
M1_COMMIT="$(git rev-parse --verify HEAD)"
git ls-tree -r -l "$M1_COMMIT" | awk '{bytes += $4} END {printf "Tracked payload: %.2f GiB\n", bytes/1073741824}'
m1ssh 'df -h /System/Volumes/Data'
```

At the reviewed `cdc08bd6f` snapshot the full tracked tree is 6.71 GiB, and the
research app copy adds 0.83 GiB **before** imports, engine cache and outputs.
Proceed only when the complete task budget fits with OS headroom. Preserve all
remaining evidence and credentials; resolve insufficient storage before transfer.

For a **committed source snapshot**, run from the Linux checkout after setting
the connection variables and `M1_COMMIT` above:

```bash
M1_TASK="m1-$(date -u +%Y%m%dT%H%M%SZ)"
M1_WORK="/Users/gius/OpenRC-m1-work/$M1_TASK"
(
set -euo pipefail
mkdir "tmp/$M1_TASK"
printf '%s\n' "$M1_COMMIT" > "tmp/$M1_TASK/source-head.txt"
git status --short > "tmp/$M1_TASK/source-status.txt"
# info/attributes overrides committed rules; refuse it rather than changing the developer's configuration.
M1_INFO_ATTRIBUTES="$(git rev-parse --git-path info/attributes)"
if test -s "$M1_INFO_ATTRIBUTES"; then
  echo "Nonempty info/attributes: use an isolated repository export." >&2
  exit 1
fi
: > "tmp/$M1_TASK/empty-attributes"
m1ssh "mkdir -p /Users/gius/OpenRC-m1-work && mkdir '$M1_WORK'"
GIT_ATTR_NOSYSTEM=1 git -c core.attributesFile="$PWD/tmp/$M1_TASK/empty-attributes" \
  -c core.autocrlf=false -c core.eol=lf -c tar.umask=0022 \
  archive --format=tar "$M1_COMMIT" | m1ssh "tar -xf - -C '$M1_WORK'"
scp -i "$M1_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o UpdateHostKeys=no \
  "tmp/$M1_TASK/source-head.txt" "$M1_HOST:$M1_WORK/source-head.txt"
)
```

This transfers tracked committed contents without ignored Linux `.godot`, `.tools`,
virtual environments, credentials or capture outputs. It excludes uncommitted and
untracked changes. Global and system attributes are disabled for this export;
nonempty repository-local override attributes cause an early refusal. For a dirty candidate, transfer only reviewed changes into
your new task directory and retain its diff and file hashes; identify the actual
bytes tested. A failed transfer leaves a partial directory: inspect it and use a
new task ID for a fresh attempt.

When disk headroom is limited, an APFS copy-on-write clone (`cp -cR`) into a new
task directory can avoid duplicating unchanged source bytes. This is separate
storage from the old campaign, not a hard link. Reconcile every scoped source
file against an export using the same pinned settings and the intended commit's
`.gitattributes`, transfer differences, and record the materialized file hashes
in a complete manifest before import or checks. Raw Git blob bytes can differ
from checkout bytes: stock aircraft data uses CRLF, and Workshop descriptors
bind those exact bytes. Blob identity alone does not verify a usable snapshot.
Remove extra files only in the new task-owned clone. A copied import cache still
needs a checked import; a clone does not establish the new source identity by
itself.

The archive is a source snapshot, **not a historical Git checkout**. If the engine
is missing, section 4 initializes local Git metadata solely so the existing getter
can locate its cache. This does not restore source history or establish a new
source commit. `app/test.sh` calls the getter directly, needs a proper checkout
and its prerequisites, and does not honor `OPENRC_GODOT` as an engine override;
follow the [full-suite contract](shared.md#full-app-suite) when that gate is needed.

## 4. Import and run focused native checks

In a **Mac shell**, enter the new task path printed/selected above, then:

```bash
cd '/Users/gius/OpenRC-m1-work/<task-id>' || exit 1
M1_PY=/Users/gius/OpenRC-m1-check/.venv/bin/python
# Only in this new archive snapshot: give the official getter a cache root.
test -f source-head.txt || exit 1
git init -q . || exit 1
# Reuse a validated existing engine path instead when one is available.
OPENRC_GODOT="$(bash app/get-godot.sh)" || exit 1
export OPENRC_GODOT
M1_APP="$PWD/tmp/research/app"
```

Stop if acquisition fails. The getter verifies the official ARM64 archive,
bundle and exact engine version; record the resulting absolute path for reuse.
Keep `source-head.txt` as the archived source identity: the initialized repository
has no source commit. With a working engine, run the dependent checks together:

```bash
(
set -eu
"$M1_PY" research/aircraft-editor/build_descriptors.py --check
"$M1_PY" tools/godot/macos_preflight.py --godot "$OPENRC_GODOT"
"$M1_PY" tools/graphics/prepare_research.py --dest tmp/research
"$M1_PY" tools/godot/run_checked.py --out-dir tmp/checks --label m1-import \
  --timeout 600 -- "$OPENRC_GODOT" --headless --path "$M1_APP" \
  --audio-driver Dummy --import
"$M1_PY" tools/godot/run_checked.py --out-dir tmp/checks --label m1-frame-tests \
  --timeout 90 -- "$OPENRC_GODOT" --headless --path "$M1_APP" \
  --audio-driver Dummy --script res://tests/test_frame_samples.gd
)
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
for explicit renderer comparisons, passing `--godot "$OPENRC_GODOT"` and
`--research-project "$M1_APP"`. That launcher does not read `OPENRC_GODOT`
implicitly. This bridge example is a functional check.

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
| Export/signature/package replay | [Release tools](../../tools/release/README.md); a historical ZIP is not a new candidate |

For a new campaign, use new run paths and freeze source, linked assets, imports,
engine, helper, settings and workload identities. Round-5/6 scripts retained on Linux contain
absolute historical Mac paths and source pins: retain them as evidence, not mutable
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
  "$M1_HOST:$M1_WORK/tmp/checks" \
  "$M1_HOST:$M1_WORK/tmp/macos-preflight" \
  "$M1_HOST:$M1_WORK/tmp/research/research-preparation.json" \
  "$M1_HOST:$M1_WORK/source-head.txt" "tmp/$M1_TASK/"
```

Retain the preflight and preparation receipts with the logs: they bind the
engine/host and the prepared project/file manifest. For a dirty candidate, also
retain its reviewed patch and changed-file hashes before cleaning the workspace.

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
| Getter/full suite fails in a snapshot | The getter needs the local Git cache root described above. Full-suite workflows need a proper checkout and prerequisites; the archive identity is its separately retained source commit. |

Completion means the intended native command passed its own validation, exact
source/tool identities and required evidence are retained, and owned processes
are stopped. Connectivity, headless success or an old package alone is not a
new performance or release result.
