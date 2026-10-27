# GP-19f — Unloaded ground-audio rows well clear of the ground

2026-10-27. Working-tree change on baseline `b6e3fe7d4`, selected by the owner as the first
"observers per frame" step. Headless CPU evidence on the Linux dev VM (Godot 4.8-beta1
official editor binary, shared host); not listening, release-build or target-hardware
qualification.

## Finding and change

The accepted ground-audio observer (GP-19c) rebuilds a contact row for every wheel at every
240 Hz tick: a wheel frame with a terrain sample, a per-contact `gear.duplicate()` and
`Ground.loads` call, and a full solid-support material query. Detaching the presentation
observers showed they take about a third of main-thread CPU in flight
([VQ-01c record](../../../../visual-quality-implementation/VQ-01c/tick-observers-2026-10-27/README.md#unprofiled-observer-share)),
and this snapshot was the largest of them.

`GroundAudioModel.snapshot_contacts` now returns cheap rows while the CG is higher than
`gear.reach` + the terrain height bound + 1 m + 0.5 s × speed. That is the contact law's
own no-touch bound (`ground_contact.gd`) plus a margin. Those rows keep every field: body
pose and point velocity; flat-ground normal, approach speed and compression (exact on flat
ground); zero force, rolling and rim speed; and the explicit hard-roll fallback material.
The observer still runs every tick, so airborne time keeps aging; inside the margin every
row is evaluated as before. Invalid surface tables take the original path.

Contract change: far rows report `material_id = "unspecified"` and
`surface_audio_fallback = true` instead of the material under a wheel in the air. Rolling
gain needs load, so the material is inaudible there. `test_ground_audio_materials.gd` now
pins the far-row fallback at the airborne start and checks the installed material with
the aircraft lowered to gear reach.

## Behaviour checks

[`ground_audio_far_pair.gd`](../../../../../../research/performance/ground_audio_far_pair.gd)
flies three real descents to touchdown and feeds the baseline and candidate snapshots to two
accepted `GroundAudio` observers, tick by tick:

| Descent | Ticks | Far rows | Full rows | Touchdown cues | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Glide-in from 18 m, 14 m/s, 1.6 m/s sink | 2,880 | 964 | 1,916 | 7 | rows near the ground bytewise equal; cues identical |
| Firm from 6 m (inside the margin: control) | 2,880 | 0 | 2,880 | 6 | all rows bytewise equal; cues identical |
| Steep from 25 m, 18 m/s, 4 m/s sink | 2,880 | 2,053 | 827 | 1 | rows near the ground bytewise equal; cues identical |

Cues compare tick, force, reference load, approach speed and the captured contact row.
Far rows always carry zero normal force. Audio scripts pass: ground audio (33), ground
audio materials (24), FlightAudio accepted endpoints (35), mechanical audio (103), hull
scrape audio (60), crash audio (12) and bus freshness (6).

## Cost

`app_cpu_per_sim.py`, airborne climb, 30 fps cap, `time_scale` 0.5, 10 s warmup and 40 s
sample; the baseline ran from a hard-linked app snapshot with `HEAD`'s
`ground_audio_model.gd` (`OPENRC_APP_DIR`), so the shared tree was never swapped
([raw](pairs.jsonl)):

| Pair | Baseline main ms / simulated s | Candidate | Change |
| ---: | ---: | ---: | ---: |
| 1 | 805 | 710 | −11.8% |
| 2 | 774 | 719 | −7.1% |
| 3 | 785 | 704 | −10.3% |

Median −10.3% of main-thread CPU in flight. Runway and approach work inside the margin is
unchanged by design.

A windsock/field-people per-frame variant was measured first and rejected: +3.2%, +1.0%
and −1.2% (no gain beyond noise), so it was reverted with its test edit.
