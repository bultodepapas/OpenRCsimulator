# TOD-08b — Paused time editing

2026-10-10 · Status: implemented and software-verified; target-display/pilot acceptance remains open.

The Pause menu opens a dedicated time-of-day draft. Apply validates and prepares the complete field, environment and Sun before replacing them synchronously. Cancel discards the draft. Both return to Pause; Continue remains explicit. The editor reuses Home's time/date/location controls and translations.

`Main.apply_lighting_config` changes lighting only. It does not call physical checkpoint restoration, reset the session, sample input, change holds or alter the propeller phase. Invalid, unchanged and refused preparations leave the current scene and recording untouched. Applying while flying is refused. Scene reconstruction happens only on Apply, not while dragging the time slider.

Interactive edits update the configured start selection and saved preferences. Restart uses that selection at tick zero; End flight shows it on Home. Direct CLI flights never access preferences. A failed preferences save leaves the applied session selection active and reports the failure.

## User flow

Press Esc during flight, choose **Time of day**, select a preset or enter the desired clock time, then Apply. Choose Continue when ready to fly. Escape closes an open selector first; another Escape discards the editor. [EN/ES layout captures](ui/README.md) cover 800×600 and 1280×720 with advanced fields scrolling.

## Recording contract

Each accepted change appends a validated configuration event at the current integer simulation tick. Multiple edits at one paused tick retain their application order; the last event wins. No-op applies add no event. The existing `openrc-visual-timeline v1` evaluator reconstructs the selection at a specified tick.

While recording, the initial `visual_context` stays frozen and `visual_timeline` is updated inside the same CSV metadata. A recording that began in untouched legacy daylight gains explicit initial legacy context on its first edit. A recording started after edits includes the history immediately. Restart saves the old recording before beginning a new timeline at tick zero with the latest selection. Physics metadata and CSV sample columns remain unchanged. This provides lighting reconstruction, not a rendered trace player.

## Verification

[Check summary and source hashes](check-summary.json), [final affected UI tests](ui-final.log.gz), [lint](lint-final.json), [scene smoke](smoke-final.json). Lint reports zero errors with the same 12 existing warnings; all three scene smoke runs pass with zero errors and the same 317 existing warnings.

The core regression passes 54 checks, including active recording edits with steady wind, turbulence, nonstandard physical atmosphere and the coupled P-51 shaft model ([log](core.log)). The serializer preserves frozen physical headers while explicitly merging visual event fields; testing only the public metadata dictionary missed this branch. The full `app/test.sh` run passed all 153 GDScript programs and integration blocks ([compressed log](full.log.gz)). After the final native-popup adjustment, the five affected UI tests were rerun. The native keyboard probe exposed stale focus links after a preset enabled astronomical controls; direct handler calls had not exercised that navigation path. Successful presets now rebuild the dialog focus chain. The rendered probe uses the real production Main at a fixed physical pose and camera, with scenery both off and on. It checks first-frame settling, repeated day/night pixel equality, changed day/night output and exact preservation of the physical checkpoint.

Each scenery mode retains one `legacy-before.png` and one `night-applied.png`. The `legacy-applied.png` and `night-repeated.png` copies were byte-identical to those retained captures and are omitted; the reports preserve the exact-pixel checks. The `capture_edit.gd` commands below regenerate the full sequence.

The checked-in `SHA256SUMS` snapshot retains historical hashes for the omitted copies; those paths no longer exist, and its `README.md` hash predates this note.

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

## Native release verification

The actual Linux release binary was driven through Home → Fly → recording → Pause → Time of day → Night → Apply → Continue → stop recording, using X11 keyboard events under Xvfb. The saved CSV has 145 samples, initial legacy context and a time edit at tick 276. The final run contains no engine errors: [report](export/report.json), [trace](export/recording.csv), [paused night](export/night-paused.png), [engine log](export/engine.log).

```bash
xvfb-run -a -s '-screen 0 1280x720x24' python3 research/time-of-day/tod-08b/export_edit_smoke.py \
  --binary /absolute/path/to/openrc-simulator.x86_64 --out /tmp/tod08b-export
```

An isolated OptionButton reproduces an embedded-popup parent-signal disconnect error in the pinned 4.7.2 release template while the editor executable stays clean. The Pause dialog uses native popup windows when the display backend supports subwindows; headless retains embedded controls. The workaround is scoped to this dialog, with no global viewport setting or engine upgrade. See the [minimal reproduction](popup-repro/README.md).
