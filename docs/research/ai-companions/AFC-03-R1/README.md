# AFC-03-R1 companion lifecycle evidence

Evidence captured 2026-10-20 with the pinned Godot 4.7.2 console build on Windows. These checks exercise tree-owned companion managers, agents, flight sessions and a bounded visual/audio lifecycle. They are software lifecycle checks, not physical validation or wall-clock performance measurements.

The headless lifecycle test passed **653 checks with 0 failures**. It repeatedly enables, reconfigures, removes and frees companions in the live scene tree; checks replacement and release with weak references; counts player observer callbacks before and after `Remove`; verifies manager reuse reconnects exactly once; and exercises hold, fault, crash isolation, player reset and recovery. Its 10 visual/audio cycles create the actual model and engine voice, then check node, session, view, generated audio stream and callback release after the audio fade tail.

Run it with:

```powershell
python tools/godot/run_checked.py --label afc-03-r1-lifecycle-test --timeout 60 --require-text "companions lifecycle:" --out-dir docs/research/ai-companions/AFC-03-R1/checks -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_companions_lifecycle.gd
```

The integrated-profile run passed again with **653 checks and 0 failures**; see [the runner report](checks/afc-03-r1-lifecycle-test-integrated-profiles-5ocrtjfo/report.json) and [the engine log](checks/afc-03-r1-lifecycle-test-integrated-profiles-5ocrtjfo/engine.log). The runner recorded zero parsed engine errors or warnings. Its log still contains the aircraft data's inertia advisories (`Jyy = 0.3692 kg·m²`); these are visible and were not treated as lifecycle failures.

The bounded probe completed **50 measured lifecycle cycles**, including 10 visual/audio cycles, then **2,400 fixed simulation ticks** (10 simulated seconds) with one companion. It checks live node counts, object/resource envelopes, callback connections, weak-reference release, player/manager tick agreement, and player plus companion fault/crash state throughout the active flight. A one-cycle visual warmup is explicitly excluded from the 50 measured cycles so first-use renderer/audio initialization is not mistaken for repeated lifecycle growth.

```powershell
python tools/godot/run_checked.py --label afc-03-r1-lifecycle-probe --timeout 90 --require-text "COMPANION LIFECYCLE PROBE COMPLETE" --out-dir docs/research/ai-companions/AFC-03-R1/checks -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/ai-companions/lifecycle_probe.gd -- --cycles=50 --visual-cycles=10 --seconds=10 --out-dir=docs/research/ai-companions/AFC-03-R1/runs/bounded-10s-50-cycles-10-visual-warmed2
```

The [probe report](runs/bounded-10s-50-cycles-10-visual-warmed2/report.json) records the full measurements and SHA-256 source receipt. During the measured lifecycle phase, live nodes remained at 3; objects were 1,842–1,846 and resources stayed at 259. During active flight, player and manager both accepted all 2,400 ticks; nodes stayed at 7 and objects/resources stayed at 1,850/259. The [runner report](checks/afc-03-r1-lifecycle-probe-warmup-7nxzdh92/report.json) records exit code 0 with no engine errors or warnings.

The first probe run is retained as a diagnostic: [its lifecycle report](runs/bounded-10s-50-cycles-10-visual/report.json) failed the object envelope when visuals were first enabled after the 40 headless cycles, increasing the monitor from 1,796 to 1,843 objects. The visual warmup separated that one-time engine initialization from the measured cycles; the follow-up then passed. This first result was not discarded or counted as a passing run.

The integrated-profile probe then completed the **20-minute simulated-duration run** with one companion, 50 measured lifecycle cycles and 10 visual/audio cycles:

```powershell
python tools/godot/run_checked.py --label afc-03-r1-soak-20m-count1-integrated-profiles --timeout 1800 --require-text "COMPANION LIFECYCLE PROBE COMPLETE" --out-dir docs/research/ai-companions/AFC-03-R1/checks -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/ai-companions/lifecycle_probe.gd -- --cycles=50 --visual-cycles=10 --seconds=1200 --count=1 --out-dir=docs/research/ai-companions/AFC-03-R1/runs/full-20m-count1-50cycles-10visual-profile-integrated
```

The [20-minute report](runs/full-20m-count1-50cycles-10visual-profile-integrated/report.json) completed **288,000 of 288,000 ticks** (1,200 simulated seconds), with `complete: true` and no recorded failure. Its SHA-256 source receipt is complete for 22 files, including `profile_loader.gd` and both companion profile JSONs. The measured lifecycle cycles stayed at 3 nodes, 1,846–1,849 objects and 262 resources. Active flight produced 1,200 one-second samples; the player and manager both accepted every tick, nodes stayed at 7, and objects/resources stayed at 1,853/262 from start to finish. No player/companion crash, agent failure or simulation fail-safe was observed. The [checked-runner report](checks/afc-03-r1-soak-20m-count1-integrated-profiles-85zm_oii/report.json) records exit code 0; the [engine log](checks/afc-03-r1-soak-20m-count1-integrated-profiles-85zm_oii/engine.log) contains 103 repeated aircraft inertia advisories and no parsed engine errors or warnings.

This soak is fixed-step and headless during sustained flight; it does not represent a 20-minute rendered/audio flight or 50 fully rendered/audio cycles. The probe checks pilot/session failure, crash and simulation fault conditions on every tick, but this report does not capture terminal fuel quantity or spatial route deviation. It supports lifecycle and fault-isolation behavior over the requested duration, not a finite-fuel endurance or pilot route-quality claim.
