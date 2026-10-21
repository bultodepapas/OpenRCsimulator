# TOD-08a — Paired visual checkpoints

Status: implemented and software-verified, 2026-10-10. Parent: [time-of-day plan](../../../TIME-OF-DAY-PLAN.md).

## TOD-08a-R1 — Finite-fuel checkpoint integration

2026-10-19: the visual envelope's supported-format list omitted the new liquid-fuel v11 boundary. A production P-51 checkpoint therefore returned an empty visual record despite valid physics. The envelope now accepts v11, including inside the collision-world wrapper; FlightSession still validates the physics law, configuration and state during restoration.

Native Windows Godot 4.7.2 checked runs pass `test_visual_checkpoint.gd` (48 checks) and `test_time_of_day_checkpoint.gd` (49 checks). Coverage includes byte-exact finite-fuel pairing, real P-51 paired/bare restoration and refusal of unknown inner formats. `test_time_of_day_edit.gd` passes 57 checks after its recorder fixtures receive the same electrical and mass samplers as production, preserving finite-fuel CSV rows through visual edits. These focused results do not replace the full release matrix or physical validation.

## Contract

`Main.checkpoint()` pairs the existing physical checkpoint with a fixed-time visual timeline and field identity. `Main.restore_checkpoint(candidate)` validates the pair, prepares detached lighting resources, asks the existing physics owner to restore, then replaces the field, Sun and environment in the same synchronous call. Invalid visual data, incompatible physics and preparation failures leave the active flight, recording and scene unchanged. Successful restore closes the previous recording and retains the existing paused, recorded-input replay contract. It does not restore live radio conditioning, camera history, rendering/scenery preferences, propeller/audio phase or a complete saved game. Pixel comparisons hold those other settings fixed.

The physics checkpoint and its native 64-bit arrays remain unchanged. No simulation or physics code is modified. `openrc-visual-checkpoint v1` contains `physics`, `timeline`, `field_identity` and `payload_sha256`. The digest is SHA-256 over `var_to_bytes([physics, timeline, field_identity])`; the field identity is SHA-256 of the native validated field dictionary. This binds both halves to the same saved record and detects accidental corruption/mispairing; it is not an authenticity signature. Native Variant encoding is required for the paired record. JSON is supported for the visual timeline only, never as a bit-exact physical-checkpoint transport.

Bare `openrc-flight-checkpoint v1`–`v4` records retain the physical owner's compatibility rules and explicitly use `legacy_missing_visual` with default legacy daylight. A broken paired record never falls back. Unknown schemas, incompatible profiles, a different field, invalid identity hashes, future events beyond the checkpoint and ticks preceding the visual anchor are refused. A checkpoint also refuses an applied config that disagrees with its recorded timeline.

## Fixed-time history

`openrc-visual-timeline v1` stores an initial config/profile/hash, anchor tick, rate `0`, and ordered config edits. Its pure evaluator returns the selection active at a known tick. Events at the same tick retain array order; the last one wins. Ticks are nonnegative integers no greater than 2^53−1, preserving exact JSON transport; booleans, fractional values and nonfinite numbers are refused. Schema v1 cannot enable progression. Config validation and solar evaluation reuse TOD-02; astronomy is not reimplemented here.

The timeline module exposes `create`, `validate`, `append_config_edit` and `evaluate`. It is independent of rendering. The checkpoint module owns pairing, validation and copying; the physical owner remains responsible for mass, integrator, weather, state and replay compatibility. A successful restore retains the selected history. Restart retains the current configured selection at tick zero and clears the prior history. Recording after restoration embeds the visual status and frozen timeline alongside the existing visual-context header in the same trace file; there is no independent sidecar to associate with the wrong trace. Existing fresh-flight trace headers are unchanged.

## Rendering and scope

Preparation builds a detached field, directional light and environment. Existing material factories initialise a global cloud offset, so preparation restores the previous offset before returning. Commit restores shader/cloud clocks from the restored physical time immediately. With QUALITY sky processing, the new environment refreshes its ambient/reflection radiance in the first rendered frame, verified by post-draw image comparison. This remains a single active world, not a simultaneous preview viewport.

The production field is supported; scripted/capture routes and the legacy atmosphere fixture refuse this technical restore interface. Static scenery is rebuilt only on successful restore. The airborne geometry, input panels and camera nodes are retained. No paused editor, clock progression, rendered trace player, seek UI, moon or aircraft lamps are added. TOD-08b will consume this foundation for paused editing and must separately verify its menu holds, Apply/Cancel and recording behavior. It needs a separate lighting-only apply operation: calling checkpoint restore to change the hour would disable live input and replace launch provenance.

## Verification

| Check | Result |
| --- | --- |
| Pre-change `app/test.sh` | Complete, exit 0: 148 GDScript test programs plus integration checks; [log](baseline.log.gz) |
| Post-integration `app/test.sh` | Complete, exit 0: 151 GDScript test programs plus all integration checks; [log](post-integration.log.gz) |
| Focused timeline / envelope / Main | 53 / 40 / 44 checks pass both in the isolated integration copy and in the project-wide test run |
| Static linter | Zero errors; exactly the same 12 pre-existing warnings |
| Scene smoke with deterministic input fuzzing | 3/3 scenes pass, zero errors; 317 existing warning diagnostics retained |
| Rendered restoration | Eight captures across scenery off/on; first/second post-draw images stable, repeated daylight/night pixels exact, physical state unchanged |
| Native Linux pack | Release export and legacy/noon/night trace smoke pass; invalid hour rejected; [result](export-check.json), [export log](export.log.gz) |

[Machine-readable checks](check-summary.json) retain source hashes. The [rendered probe and artifacts](../../../../research/time-of-day/tod-08a/README.md) preserve reproduction commands and checksums. Headless Main checks cover failed preparation, mismatched records, detached history, restart, frozen recording metadata, exact physical continuation, and real v1/v2/v3/v4 checkpoints including turbulence, custom atmosphere and the P-51 coupled shaft.

Each scenery mode retains only its distinct `legacy-before.png` and `night-restored.png` captures. The `legacy-restored.png` and `night-repeated.png` copies were byte-identical to those retained images and are omitted; the reports preserve the exact-pixel checks. The [probe](../../../../research/time-of-day/tod-08a/capture_restore.gd) regenerates the full sequence.

The checked-in `SHA256SUMS` snapshots retain historical hashes for the omitted copies; those paths no longer exist.

The Linux release template does not expose a `--script` option ([help output](export-help.txt)); its smoke exercises real launch/trace routes and packaging, not an external checkpoint harness. The checkpoint interface is exercised against the pinned source engine. No target-GPU performance or pilot acceptance is claimed.

```sh
bash app/test.sh
$(app/get-godot.sh) --headless --path app --audio-driver Dummy --script res://tests/test_visual_timeline.gd
$(app/get-godot.sh) --headless --path app --audio-driver Dummy --script res://tests/test_visual_checkpoint.gd
$(app/get-godot.sh) --headless --path app --audio-driver Dummy --script res://tests/test_time_of_day_checkpoint.gd
```

Suggested commit: `TOD-08a: pair native flight checkpoints with fixed-time visual history`. Proof: full `app/test.sh`, 137 focused checks, eight exact restoration captures, and Linux pack smoke.
