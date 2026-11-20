# Player update help and interface copy

DT-UPD-00 follow-up, 2026-11-17. **Draft for a future update-capable release.**
The current game opens a GitHub release page; downloading, installation, repair
and the controls below are not implemented by this research branch.
[Active plan](../../../plans/github-updates.md) · [Design](design.md) ·
[Qualification briefs](reuse-spikes.md) · [Acceptance](validation.md).

Keep public instructions conditional on the exact supported platform/layout.
Confirm every button and recovery path in the shipped build before publishing
this help. Translate through the existing localization system.

## Intended everyday experience

1. Open OpenRC Simulator as usual. An update card appears in Home when an eligible
   release is available.
2. Read What's new and the download size, then choose Download update. Continue
   using the game; heavier download/preparation work pauses during a flight by
   default.
3. When preparation finishes, choose Restart and update or Install when I exit.
   Finish a flight and save Workshop work through the normal exit prompts.
4. The game reopens after a successful installation. Your existing radio profiles,
   settings, aircraft and recordings stay in their normal location.

The game continues to work offline. Automatic installation requires a successful
update-information check before applying the prepared version. If that check is
unavailable, the prepared update waits and the installed game remains usable.
This is a proposed policy to verify, not a promise of instant release withdrawal.

## Draft messages

Use actual authenticated version/size and measured disk values in placeholders.
Do not infer Current from a failed request or show a verification failure as a
successful download. Only expose controls supported by that platform.

| State | Text | Actions |
| --- | --- | --- |
| Available | OpenRC Simulator {version} is available. Download: {transfer_size}. Free space needed: {free_space}. | What's new · Download update · Later · Skip this version |
| Checking | Checking for updates… | Cancel |
| Current | You're using the latest eligible version on the {channel} channel. Last checked: {time}. | Check now |
| Not checked | Updates have not been checked yet. | Check now |
| Downloading | Downloading {version}: {received} of {total}. | Pause · Cancel download |
| Paused | Download paused. Your current game is ready to use. | Resume · Cancel download |
| Network retry | Download interrupted. {received} is saved. Retrying in {time}. | Retry now · Pause |
| Verifying | Checking the downloaded update… | Cancel |
| Ready | {version} is ready to install. | Restart and update · Install when I exit · Later |
| Exit cancelled | Installation is waiting. Finish saving your work when you're ready. | Return to game |
| Update check failed | We couldn't check for updates. Last successful check: {time_or_never}. | Retry · Open GitHub releases |
| Verification failed | This download could not be verified. Your installed game has not been changed. | Download again · View details |
| Metadata expired | Update information needs to be refreshed before installation. You can keep playing. | Retry · Open GitHub releases |
| Prepared update changed | The prepared version is no longer offered by the verified update information. | Check available version · Keep playing |
| Delta fallback | A complete download is needed for this update: {full_size}. | Download complete update · Later |
| Insufficient disk | This update needs {additional_space} more free space on {volume}. | Retry · Open download folder · Later |
| Assisted installation | The download is verified. This installation needs a manual update. | Open download folder · Installation steps |
| Another copy open | Another copy of this installation is still running. Close it when you're ready. | Retry · Later |
| Applied and healthy | Updated to {version}. | What's new · Close |
| Recovery required | The update needs repair. Your previous version is retained at {verified_location}. | Open recovery instructions · Export update log |
| Unsupported older profile | This version cannot safely write the newer player data. | Open compatible version · Read recovery instructions |

After a verification failure, Installed game unchanged is valid only before
activation. A post-activation failure needs the recovery message and its actual
observed state. The UI must not claim the previous version is retained unless
the helper has verified its presence.

Skip this version affects offers, not game files. Changing stable/preview should
show the chosen channel and avoid silently installing an older version. Explain
any future separate preview profile before creating it.

## One-time bootstrap

An existing version that only opens GitHub cannot install updater functionality
by itself. The first update-capable release needs one complete manual installation.
Publish a short explanation with the eligible release, its supported platforms and
the ordinary download button. Players never need a GitHub account, Git, Python,
the Godot editor or a separate launcher.

Proposed instructions:

1. Download the complete package for your operating system and architecture from
   the official OpenRC Simulator GitHub release.
2. Close OpenRC Simulator after saving Workshop work and completing recordings.
3. Extract the complete package into a new, writable folder. Keep all supplied
   files together so the executable, libraries and package information agree.
4. Open the new copy directly. Check your radio profile, settings and aircraft.
5. Keep the previous installation until the new one has started successfully and
   its compatibility/recovery instructions permit removal.

For macOS, keep the supplied app and companion files together as delivered.
Future packaging may change this instruction; qualify it against the actual
release. For a per-user Windows installer, replace the ZIP steps with the tested
installer flow and retain the same player-data checks.

Existing custom files inside an old installation need an explicit migration
decision. The first updater cannot infer ownership of every legacy file from
the installed version number. Preserve that folder until ownership is known.

## When something goes wrong

### The game still opens

Keep playing or retry later. Use Update details to see the selected version,
download progress, most recent successful check and reason installation stopped.
A full-package fallback requires approval of its displayed transfer size.
Download cleanup may remove identified update cache; player data remains outside
that cleanup.

### The new version does not reach Home

Use the independently installed recovery entry if that platform has qualified it.
Show its exact location in the installer/help before enabling automatic apply.
Recovery must identify a complete previous version and state whether its use
with the current profile is writable, read-only or unsupported.

If that recovery entry is unavailable, obtain a complete official ZIP and extract
it to a new folder, then follow the current platform guide. A missing executable
cannot be repaired by a menu inside the missing game. The public help must explain
the reachable route instead of promising an invisible automatic repair.

### I want an older version

Older application files and newer player data are separate compatibility concerns.
Keep the newer player files and their recovery copies. Follow the version-specific
compatibility guidance before opening an older game against them.

Exact flight replays can require their original game/backend identity. Show the
recorded identity and an official historical package link when applicable.
Successful startup in a newer version does not establish exact replay compatibility.

## Local diagnostic assistance

A future Export update log control should prepare a reviewable local file with
updater version, installed/target build identities, OS/architecture, safe state
transitions, HTTP status classes, byte counts, validation verdicts and recovery
result. Redact personal paths, credentials, redirect query strings and player
content. Show what is included before the player chooses to share it.
This feature sends nothing automatically.

## Help acceptance

Use T61–T62 and T63–T82 in [validation](validation.md), plus the relevant native
cases. Exercise keyboard, controller and mouse at 1920×1080 first. A tester should
find the next safe action from the displayed state, preserve an existing profile,
and recover without knowing a developer-only path. Retain observed outcomes;
these prose drafts alone do not pass those cases.
