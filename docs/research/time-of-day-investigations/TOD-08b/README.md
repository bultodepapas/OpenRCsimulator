# TOD-08b — Paused time editing

2026-10-10 · Status: implementation under validation.

The Pause menu opens a dedicated time-of-day draft. Apply validates and prepares the complete field, environment and Sun before replacing them synchronously. Cancel discards the draft. Both return to Pause; Continue remains explicit. The editor reuses Home's time/date/location controls and translations.

`Main.apply_lighting_config` changes lighting only. It does not call physical checkpoint restoration, reset the session, sample input, change holds or alter the propeller phase. Invalid, unchanged and refused preparations leave the current scene and recording untouched. Applying while flying is refused. Scene reconstruction happens only on Apply, not while dragging the time slider.

Interactive edits update the configured start selection and saved preferences. Restart uses that selection at tick zero; End flight shows it on Home. Direct CLI flights never access preferences. A failed preferences save leaves the applied session selection active and reports the failure.

## Recording contract

Each accepted change appends a validated configuration event at the current integer simulation tick. Multiple edits at one paused tick retain their application order; the last event wins. No-op applies add no event. The existing `openrc-visual-timeline v1` evaluator reconstructs the selection at a specified tick.

While recording, the initial `visual_context` stays frozen and `visual_timeline` is updated inside the same CSV metadata. A recording that began in untouched legacy daylight gains explicit initial legacy context on its first edit. A recording started after edits includes the history immediately. Restart saves the old recording before beginning a new timeline at tick zero with the latest selection. Physics metadata and CSV sample columns remain unchanged. This provides lighting reconstruction, not a rendered trace player.

## Verification

The core regression passes 54 checks, including active recording edits with steady wind, turbulence, nonstandard physical atmosphere and the coupled P-51 shaft model ([log](core.log)). The serializer preserves frozen physical headers while explicitly merging visual event fields; testing only the public metadata dictionary missed this branch. Full-suite and native-menu verification are still running. The native keyboard probe exposed stale focus links after a preset enabled astronomical controls; direct handler calls had not exercised that navigation path. The rendered probe uses the real production Main at a fixed physical pose and camera, with scenery both off and on. It checks first-frame settling, repeated day/night pixel equality, changed day/night output and exact preservation of the physical checkpoint.

```bash
xvfb-run -a "$(app/get-godot.sh)" --path app --audio-driver Dummy \
  --script "$PWD/research/time-of-day/tod-08b/capture_edit.gd" \
  -- --probe-out=/tmp/tod08b-default
OPENRC_SCENERY=on xvfb-run -a "$(app/get-godot.sh)" --path app --audio-driver Dummy \
  --script "$PWD/research/time-of-day/tod-08b/capture_edit.gd" \
  -- --probe-out=/tmp/tod08b-scenery
app/test.sh
```

The measured synchronous Apply cost was 392–412 ms with scenery off and 478–512 ms with scenery on in this llvmpipe run (three commits each; CPU resource construction plus submission, not a target-GPU frame budget). Reports: [default](default/report.json), [scenery](scenery/report.json).

Software-rendered evidence does not close target-GPU/display or pilot readability acceptance. Time remains fixed during flight; progression, lunar lighting and aircraft lamps remain separate phases. Rebuilding the field is acceptable for a paused commit; it is not yet a demonstrated update policy for continuous progression.
