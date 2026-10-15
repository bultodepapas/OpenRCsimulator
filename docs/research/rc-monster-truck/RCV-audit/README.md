# RCV-20/22/24/25/33 strict runtime audit

Date: 2026-10-14. Scope: the MT8 working tree after the effects/damage revision, including Session persistence, damage attribution, activity lifecycle and render adapters. The [baseline receipt](baseline.json) identifies 35 input/source files. Indexed graph discovery had insufficient ground-vehicle coverage; findings were checked against current source and executable fixtures. Three reviewers owned separate Session, damage and render paths; the integration reviewer owned the activity and final verification.

## Findings and corrections

| ID | Severity | Reproduced defect | Correction |
| --- | --- | --- | --- |
| A01 | High: saved data | An invalid checkpoint replaced a previously valid file with `{}` and cleared its in-memory cache. The direct writer also ignored partial writes. | Reject empty candidates; write and flush a sibling temporary file, verify its exact bytes, preserve the old file before replacement, and update cache only after success. Failed replacement rolls back; failed rollback retains a named backup and exposes its path. |
| A02 | Medium: recording provenance | A rejected non-finite control tick left recording active and the retained prefix labeled valid. | Interrupt once, record the reason, preserve an exportable invalid prefix, and refuse new recording while faulted. |
| A03 | Medium: recovery provenance | A rehashed checkpoint could claim an unassisted run despite a manual recovery, or omit its corresponding event. | Check recovery action/event correspondence and require assisted status. |
| A04 | Low: checkpoint consistency | A rehashed damaged checkpoint accepted applied throttle below requested throttle times its saved drive authority. | Enforce the monotone lower bound while preserving the pre-impact control phase. This is consistency checking, not authentication. |
| A05 | Medium: jump scoring | A new takeoff did not cancel the previous landing timer; an upright airborne truck could receive its old landing award. | Cancel on takeoff; evaluate only after accepted ticks and require wheel support, upright attitude and an unassisted run after the settling interval. |
| A06 | Low: recording UI | A refused recording start still changed the button to “Stop and save recording.” | Change the button only on success; explain a refused start. |
| A07 | Medium: render inputs | Non-finite speed/slip could emit dust or accumulate grime; an infinite road height could create a non-finite particle pose. | Reject malformed telemetry and gate individual road samples before using them in transforms or grime accumulation. |
| A08 | Low: effects lifecycle | Failed effects preparation attached an unusable node to the scene. | Validate before attachment. |
| A09 | Medium: repair lifecycle | Preparing a damage view twice could adopt its already damaged mesh as the original, breaking repair. | Reject repeated preparation and preserve the original mesh/material bindings. |
| A10 | Medium: damage attribution | A supported wheel-only wall scrape accumulated ordinary mechanical losses as impact energy, damaging body and drive. | Gate contact-energy accumulation on translational speed loss; route wheel-only wall impacts to contacting suspension corners. The two supported scrape fixtures remain wear-free while positive impacts still register. |
| A11 | Medium: bottoming events | Existing overtravel could create new damage while the suspension was extending. | Require compressing travel for a new bottoming event. |
| A12 | Low: damage API validation | Malformed contact/load/model evidence and overflow in derived energy were not consistently rejected before commit. | Validate evidence and derived values; rejection preserves the previous damage snapshot. |

All severities refer to the simulator's data or gameplay behavior, not real hardware safety. Damage version **2** keeps the 19-value layout; earlier damage-version checkpoints are refused because their event semantics differ. Start a new run when updating from version 1.

## Evidence and verification

- [Baseline activity reproduction](scene-before.log): pending landing survives a new jump; rejected recording changes the button.
- [Baseline save reproduction](storage-before.log): a disposable copy redirects only the save directory, then demonstrates replacement of a valid checkpoint with `{}`. User saves are not used by this fixture.
- [Activity regressions](../../../../app/tests/test_rcv_activity_audit.gd): isolated temporary directories, reported and silent short writes, directory and rename failures, rollback failure and retained-backup restore, successful replacement, save during recording, recording-button state, bounced/unsupported/assisted and supported landing awards.
- [Session findings and evidence](session-integrity.md): checkpoint consistency, recovery provenance, recording interruption and exact replay.
- [Render findings and evidence](render-effects.md): invalid samples, setup lifecycle, private mesh caching and source-resource immutability.
- [Damage findings and evidence](damage-01.md): wheel-only/hull-wall scrapes, positive lateral and frontal impacts, bottoming and invalid-input rejection.

The [24-group runtime receipt](checks-final/verification.json) and [additional production contact audit](checks-contact/verification.json) pass all **25 distinct configured checks**, with identical runtime-source hash maps and unchanged sources during both runs. The runner now includes the contact audit by default. Focused counts include Session **101**, damage **175**, damage Session **19**, activity audit **39**, render audit **34**, existing effects **91** and effects activity **17**, all without failures. The [parse receipt](parse-final.json) covers all ten changed/new GDScript files; it does not claim a fresh whole-application parse. The final [source receipt](final-sources.json) binds runtime, tests and research drivers to this audit.

## Complete drive and native review

The ordinary fast circuit completed **5,393 ticks / 22.471 simulated seconds**, covering **85.699 m** with a peak speed of **5.974 m/s**. All 31 exported physical-state channels and driver inputs exactly match the prior accepted effects drive: [comparison](drive-comparison.json), [complete drive receipt](drive-final.json), [compressed trace](drive-final.csv.gz), [compression identities](retained-drive.json). Body/suspension damage stayed zero and drive authority stayed at 100% throughout. This confirms that the fixes preserve that accepted driving case; contact cases intentionally change under damage version 2.

The native Compatibility [capture](runtime-impact.png) and [receipt](runtime-impact.png.json) run 720 accepted ticks with ordinary controls against the airfield slalom. The default start remains the aircraft runway. A wall contact occurs, the truck stays renderable, the Spanish HUD reports scuffing and about **90% propulsion**, and the private shell/suspension remain visible. The final estimated body damage is 0.1726; the most damaged suspension corner is 0.1797. The HUD reports that suspension travel exceeds the authored visual range; rendering clamps that articulation rather than hiding the diagnostic. This is a small-impact visual check, not severe-destruction validation. The [native log](runtime-impact.log) contains no script/shader errors or leaked-resource warning on this run.

The drive's Session tick P95 is **5.438 ms**, exceeding the 4.167 ms budget at 240 Hz. This shared-workstation run is not an isolated performance qualification. No performance improvement or sustained real-time 240 Hz claim is made.

The Windows replacement guard follows the pinned [Godot 4.7.2 implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/windows/dir_access_windows.cpp#L288): an ordinary rename removes an existing destination before moving. The code therefore preserves the old file under a separate name first. [DirAccess](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html#class-diraccess-method-rename-absolute) returns an error code, and [FileAccess](https://docs.godotengine.org/en/4.6/classes/class_fileaccess.html#class-fileaccess-method-flush) exposes flush/error checks. This is recovery from reported I/O failures, not a promise of atomic publication, concurrent multi-process saving, or power-loss durability.

## Remaining limits

The damage observer is an estimated gameplay model, not calibrated material strength or fracture mechanics. Its 0.05 m/s per-tick scalar speed-loss gate can undercount glancing/angular impacts; concurrent braking, tire and suspension losses can still enter the energy estimate. The two negative scrape fixtures do not prove universal immunity to false wear. Suspension damage is diagnostic; only propulsion is derated. Checkpoint hashes are public integrity checks, not anti-cheat signatures or proof that a state is physically reachable. Vehicle, tire and damper calibration, breakable joints and target-hardware frame pacing remain open in the [RCV plan](../../../plans/rc-monster-truck.md). This audit does not qualify unrelated parallel aircraft/helicopter edits or a new packaged application build.
